import 'dart:convert';

import 'package:rbnotes/core/network/api_client.dart';
import 'package:rbnotes/core/network/api_error.dart';
import 'package:rbnotes/features/ai/data/ai_activity.dart';
import 'package:rbnotes/features/ai/data/ai_client.dart';
import 'package:rbnotes/features/ai/data/ai_exceptions.dart';
import 'package:rbnotes/features/ai/data/sse_client.dart';
import 'package:rbnotes/features/ai/domain/note_ai.dart';
import 'package:rbnotes/features/collections/domain/collection_rule.dart';

/// Conteúdo de um evento SSE já **desembrulhado** do envelope do servidor
/// (`{"data": "<conteúdo>", "code"?: "<código>"}`).
class _Envelope {
  const _Envelope(this.data, this.code);
  final String data;
  final String? code;
}

/// `AiClient` real: dispara o job (`202 { id }`) e acompanha o resultado por
/// SSE (`GET /ai/streams/{id}`).
///
/// Cada evento SSE vem embrulhado num envelope `{"data":"…","code"?:"…"}`: o
/// conteúdo real está sempre em `data` (uma string). Os eventos `json` trazem o
/// JSON estruturado em **pedaços** (acumulados num buffer, só para a UI de
/// streaming); o **resultado final canônico** vem no evento `done` (parse
/// estrito). O bug corrigido aqui tratava o envelope como se fosse o resultado,
/// gerando um `NoteAi` vazio.
class ApiAiClient implements AiClient {
  ApiAiClient(
    this._api, {
    SseClient? sse,
    AiActivity? activity,
    String? Function()? modelName,
  }) : _sse = sse ?? SseClient(_api),
       _activity = activity,
       _modelName = modelName;

  final ApiClient _api;
  final SseClient _sse;
  final AiActivity? _activity;
  final String? Function()? _modelName;

  @override
  Future<NoteAi> enrich(EnrichRequest request) async {
    final id = await _start('/ai/notes/${request.noteId}/enrich', {
      'transcript': [for (final s in request.segments) _segment(s)],
      'speakers': request.speakers,
      'folder': request.folder,
      'style': request.style.name,
      'length': request.length.name,
      'extractTasks': request.extractTasks,
      'model': _model(),
      if (request.ephemeral) 'ephemeral': true,
    });
    final obj = await _collect(id);
    return NoteAi.fromJson(obj);
  }

  @override
  Stream<AiDelta> chat({
    required String noteId,
    required List<AiSegment> segments,
    required List<String> speakers,
    required String message,
    bool ephemeral = false,
  }) {
    return _stream(
      path: '/ai/notes/$noteId/chat',
      body: {
        'message': message,
        'transcript': [for (final s in segments) _segment(s)],
        'model': _model(),
        if (ephemeral) 'ephemeral': true,
      },
      toDelta: (obj, {required done}) => AiDelta(
        text: (obj['text'] as String?) ?? '',
        isDone: done,
        cites: done ? _cites(obj) : const [],
      ),
    );
  }

  @override
  Stream<AiDelta> ask({
    required String question,
    required List<AskCandidate> candidates,
  }) {
    return _stream(
      path: '/ai/ask',
      body: {'question': question, 'model': _model()},
      toDelta: (obj, {required done}) => AiDelta(
        text: (obj['text'] as String?) ?? '',
        isDone: done,
        sources: done ? _sources(obj) : const [],
      ),
    );
  }

  @override
  Future<CollectionRuleResult> collectionRule(String description) async {
    final id = await _start('/ai/collections/rule', {
      'description': description,
      'model': _model(),
    });
    final obj = await _collect(id);
    return CollectionRuleResult(
      label: (obj['label'] as String?) ?? description,
      ruleText: (obj['ruleText'] as String?) ?? description,
      rule: obj['rule'] is Map<String, dynamic>
          ? CollectionRule.fromJson(obj['rule'] as Map<String, dynamic>)
          : const CollectionRule(),
    );
  }

  @override
  Future<DiaryMonth> diaryMonth({
    required String month,
    required List<String> entries,
  }) async {
    final id = await _start('/ai/diary/month', {
      'month': month,
      'model': _model(),
    });
    final obj = await _collect(id);
    return DiaryMonth(
      summary: (obj['summary'] as String?) ?? '',
      themes: ((obj['themes'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(
            (t) => DiaryTheme(
              name: (t['name'] as String?) ?? '',
              count: (t['count'] as num?)?.toInt() ?? 0,
            ),
          )
          .toList(),
    );
  }

  @override
  Future<String> dailyPrompt(DateTime date) async {
    final day =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final id = await _startGet('/ai/diary/prompt', {'date': day});
    final obj = await _collect(id);
    return (obj['prompt'] as String?) ?? '';
  }

  @override
  Future<WeeklySummary> weeklySummary({
    required DateTime weekStart,
    required String tz,
  }) async {
    final day =
        '${weekStart.year.toString().padLeft(4, '0')}-'
        '${weekStart.month.toString().padLeft(2, '0')}-'
        '${weekStart.day.toString().padLeft(2, '0')}';
    final id = await _start('/ai/weekly-summary', {
      'weekStart': day,
      'tz': tz,
    });
    final obj = await _collect(id);
    return WeeklySummary.fromJson(obj);
  }

  // ---------------- internals ----------------

  Future<String> _start(String path, Map<String, dynamic> body) async {
    _activity?.set(AiPhase.queued);
    try {
      final res = await _api.post(path, body: _clean(body));
      return _jobId(res);
    } on ApiError catch (e) {
      _activity?.set(e.isAiDailyLimit ? AiPhase.dailyLimit : AiPhase.error);
      if (e.isAiDailyLimit) throw const AiDailyLimitException();
      throw AiException(e.message);
    }
  }

  Future<String> _startGet(String path, Map<String, dynamic> query) async {
    _activity?.set(AiPhase.queued);
    try {
      final res = await _api.getJson(path, query: query);
      return _jobId(res);
    } on ApiError catch (e) {
      _activity?.set(e.isAiDailyLimit ? AiPhase.dailyLimit : AiPhase.error);
      if (e.isAiDailyLimit) throw const AiDailyLimitException();
      throw AiException(e.message);
    }
  }

  /// Consome o stream até `done`, devolvendo o **resultado final canônico**.
  ///
  /// Prioridade: o `data` do evento `done` (parse estrito). Se o `done` vier
  /// vazio (servidor antigo), cai para o buffer acumulado dos eventos `json`
  /// (os pedaços concatenados reconstroem o JSON completo).
  Future<Map<String, dynamic>> _collect(String id) async {
    _activity?.set(AiPhase.streaming);
    final buffer = StringBuffer();
    Map<String, dynamic>? result;
    try {
      await for (final ev in _sse.connect('/ai/streams/$id')) {
        final env = _unwrap(ev.data);
        if (ev.isError) {
          _activity?.set(AiPhase.error);
          throw AiException(_errorMessage(env));
        }
        if (ev.event == 'json') buffer.write(env.data);
        if (ev.isDone) {
          result = _parseStrict(env.data) ?? _parseStrict(buffer.toString());
          break;
        }
      }
    } on AiException {
      rethrow;
    } on Object catch (_) {
      _activity?.set(AiPhase.error);
      rethrow;
    }
    if (result == null) {
      _activity?.set(AiPhase.error);
      throw const AiException('A IA não retornou um resultado.');
    }
    _activity?.set(AiPhase.idle);
    return result;
  }

  Stream<AiDelta> _stream({
    required String path,
    required Map<String, dynamic> body,
    required AiDelta Function(Map<String, dynamic> obj, {required bool done})
    toDelta,
  }) async* {
    final id = await _start(path, body);
    _activity?.set(AiPhase.streaming);
    final buffer = StringBuffer();
    Map<String, dynamic>? result;
    await for (final ev in _sse.connect('/ai/streams/$id')) {
      final env = _unwrap(ev.data);
      if (ev.isError) {
        _activity?.set(AiPhase.error);
        throw AiException(_errorMessage(env));
      }
      if (ev.event == 'json') {
        buffer.write(env.data);
        final partial = _parseTolerant(buffer.toString());
        if (partial != null) yield toDelta(partial, done: false);
      }
      if (ev.isDone) {
        result = _parseStrict(env.data) ?? _parseStrict(buffer.toString());
        break;
      }
    }
    _activity?.set(AiPhase.idle);
    yield toDelta(result ?? const {}, done: true);
  }

  Map<String, dynamic> _segment(AiSegment s) => {
    'index': s.index,
    'speaker': s.speaker == AiSpeaker.me ? 'me' : 'others',
    'startMs': s.startMs,
    'endMs': s.endMs,
    'text': s.text,
  };

  List<int> _cites(Map<String, dynamic> obj) => ((obj['cites'] as List?) ?? [])
      .whereType<Map<String, dynamic>>()
      .map((c) => (c['atMs'] as num?)?.toInt() ?? 0)
      .toList();

  List<AskSource> _sources(Map<String, dynamic> obj) =>
      ((obj['sources'] as List?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(
            (s) => AskSource(
              noteId: (s['noteId'] as String?) ?? '',
              title: (s['title'] as String?) ?? '',
            ),
          )
          .toList();

  String? _model() {
    final raw = _modelName?.call();
    if (raw == null) return null;
    final l = raw.toLowerCase();
    if (l.contains('opus')) return 'opus';
    if (l.contains('haiku')) return 'haiku';
    if (l.contains('sonnet')) return 'sonnet';
    return null;
  }

  Map<String, dynamic> _clean(Map<String, dynamic> body) => {
    for (final e in body.entries)
      if (e.value != null) e.key: e.value,
  };

  String _jobId(Object? res) {
    if (res is Map<String, dynamic> && res['id'] is String) {
      return res['id'] as String;
    }
    throw const AiException('Resposta inesperada ao enfileirar a IA.');
  }

  /// Desembrulha o envelope `{"data":"…","code"?:"…"}`. Tolera um payload já
  /// "cru" (servidor antigo sem envelope): nesse caso devolve a string inteira.
  _Envelope _unwrap(String raw) {
    if (raw.isEmpty) return const _Envelope('', null);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return _Envelope(
          (decoded['data'] as String?) ?? '',
          decoded['code'] as String?,
        );
      }
    } on FormatException {
      // não é JSON: trata como conteúdo cru.
    }
    return _Envelope(raw, null);
  }

  /// Parse estrito de um objeto JSON completo (`null` se vazio/ inválido).
  Map<String, dynamic>? _parseStrict(String data) {
    if (data.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(data);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// Parse tolerante do JSON **parcial** acumulado (streaming de chat/ask):
  /// tenta o parse estrito e, se o objeto ainda está incompleto, extrai o campo
  /// `text` parcial para exibir enquanto a resposta chega.
  Map<String, dynamic>? _parseTolerant(String raw) {
    final strict = _parseStrict(raw);
    if (strict != null) return strict;
    final text = _partialText(raw);
    return text == null ? null : {'text': text};
  }

  /// Extrai o valor (possivelmente incompleto) do campo `"text"` de um JSON
  /// parcial, tratando escapes JSON e um escape cortado no fim do buffer.
  String? _partialText(String raw) {
    final match = RegExp(r'"text"\s*:\s*"').firstMatch(raw);
    if (match == null) return null;
    final out = StringBuffer();
    var i = match.end;
    while (i < raw.length) {
      final c = raw[i];
      if (c == r'\') {
        if (i + 1 >= raw.length) break; // escape cortado no fim do buffer
        final n = raw[i + 1];
        switch (n) {
          case 'n':
            out.write('\n');
          case 't':
            out.write('\t');
          case 'r':
            out.write('\r');
          case 'b':
            out.write('\b');
          case 'f':
            out.write('\f');
          case '"':
            out.write('"');
          case '/':
            out.write('/');
          case r'\':
            out.write(r'\');
          case 'u':
            if (i + 5 < raw.length) {
              final code = int.tryParse(raw.substring(i + 2, i + 6), radix: 16);
              if (code != null) out.writeCharCode(code);
              i += 4;
            }
          default:
            out.write(n);
        }
        i += 2;
        continue;
      }
      if (c == '"') break; // fim da string do campo text
      out.write(c);
      i++;
    }
    return out.toString();
  }

  String _errorMessage(_Envelope env) {
    final obj = _parseStrict(env.data);
    if (obj != null) {
      return (obj['message'] as String?) ??
          (obj['error'] as String?) ??
          'Falha na IA.';
    }
    return env.data.isNotEmpty ? env.data : 'Falha na IA.';
  }
}
