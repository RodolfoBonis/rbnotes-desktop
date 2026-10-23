import 'dart:convert';

import 'package:rbnotes/core/network/api_client.dart';
import 'package:rbnotes/core/network/api_error.dart';
import 'package:rbnotes/features/ai/data/ai_activity.dart';
import 'package:rbnotes/features/ai/data/ai_client.dart';
import 'package:rbnotes/features/ai/data/ai_exceptions.dart';
import 'package:rbnotes/features/ai/data/sse_client.dart';
import 'package:rbnotes/features/ai/domain/note_ai.dart';
import 'package:rbnotes/features/collections/domain/collection_rule.dart';

/// `AiClient` real: dispara o job (`202 { id }`) e acompanha o resultado por
/// SSE (`GET /ai/streams/{id}`). A saída estruturada chega nos eventos `json`
/// (o objeto cresce incrementalmente; `text` é o streaming do chat/ask).
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
  }) {
    return _stream(
      path: '/ai/notes/$noteId/chat',
      body: {
        'message': message,
        'transcript': [for (final s in segments) _segment(s)],
        'model': _model(),
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

  /// Consome o stream até `done`, devolvendo o último objeto `json`.
  Future<Map<String, dynamic>> _collect(String id) async {
    _activity?.set(AiPhase.streaming);
    Map<String, dynamic>? last;
    try {
      await for (final ev in _sse.connect('/ai/streams/$id')) {
        if (ev.isError) {
          _activity?.set(AiPhase.error);
          throw AiException(_errorMessage(ev.data));
        }
        if (ev.event == 'json') last = _parse(ev.data) ?? last;
        if (ev.isDone) break;
      }
    } on AiException {
      rethrow;
    } on Object catch (_) {
      _activity?.set(AiPhase.error);
      rethrow;
    }
    if (last == null) {
      _activity?.set(AiPhase.error);
      throw const AiException('A IA não retornou um resultado.');
    }
    _activity?.set(AiPhase.idle);
    return last;
  }

  Stream<AiDelta> _stream({
    required String path,
    required Map<String, dynamic> body,
    required AiDelta Function(Map<String, dynamic> obj, {required bool done})
    toDelta,
  }) async* {
    final id = await _start(path, body);
    _activity?.set(AiPhase.streaming);
    Map<String, dynamic>? last;
    await for (final ev in _sse.connect('/ai/streams/$id')) {
      if (ev.isError) {
        _activity?.set(AiPhase.error);
        throw AiException(_errorMessage(ev.data));
      }
      if (ev.event == 'json') {
        final obj = _parse(ev.data);
        if (obj != null) {
          last = obj;
          yield toDelta(obj, done: false);
        }
      }
      if (ev.isDone) break;
    }
    _activity?.set(AiPhase.idle);
    yield toDelta(last ?? const {}, done: true);
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

  Map<String, dynamic>? _parse(String data) {
    if (data.isEmpty) return null;
    try {
      final decoded = jsonDecode(data);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  String _errorMessage(String data) {
    final obj = _parse(data);
    return (obj?['message'] as String?) ??
        (obj?['error'] as String?) ??
        'Falha na IA.';
  }
}
