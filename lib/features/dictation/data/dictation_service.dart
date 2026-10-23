import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/domain/note_models.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/settings/data/vocabulary_repository.dart';
import 'package:rbnotes/native/rb_native.dart';
import 'package:uuid/uuid.dart';

/// Estado do registro do atalho de ditado, para exibir nas configurações sem
/// reportar erro ao Sentry a cada boot (ex.: falta de Acessibilidade).
class DictationHotkeyStatus {
  const DictationHotkeyStatus({required this.registered, this.error});

  /// Atalho registrado e ativo.
  final bool registered;

  /// Mensagem do erro de registro (ex.: conflito/permissão), ou `null`.
  final String? error;

  static const disabled = DictationHotkeyStatus(registered: false);
}

/// Ditado global: escuta o atalho, transcreve o áudio do mic, cola no app em
/// foco e salva como nota `source: dictation`. Guarda o último texto ditado
/// para o menu "Colar último ditado".
class DictationService {
  DictationService({
    required RbNative native,
    required NoteRepository repository,
    required SettingsStore settings,
    required VocabularyRepository vocabulary,
    Uuid? uuid,
  }) : _native = native,
       _repository = repository,
       _settings = settings,
       _vocabulary = vocabulary,
       _uuid = uuid ?? const Uuid();

  final RbNative _native;
  final NoteRepository _repository;
  final SettingsStore _settings;
  final VocabularyRepository _vocabulary;
  final Uuid _uuid;

  StreamSubscription<DictationEvent>? _sub;
  String? _lastText;
  DictationHotkeyStatus _hotkeyStatus = DictationHotkeyStatus.disabled;

  final _notices = StreamController<String>.broadcast();

  /// Último texto ditado, disponível para "Colar último ditado".
  String? get lastDictatedText => _lastText;

  /// Estado atual do registro do atalho (para a tela de configurações).
  DictationHotkeyStatus get hotkeyStatus => _hotkeyStatus;

  /// Avisos para o usuário (ex.: a colagem falhou mas o texto foi salvo). A
  /// casca do app assina e mostra um snackbar/tray.
  Stream<String> get notices => _notices.stream;

  /// Registra o atalho (se habilitado) e passa a escutar os eventos.
  Future<void> start() async {
    _sub = _native.dictationEvents().listen(
      _onEvent,
      onError: (Object e, StackTrace st) {
        unawaited(
          AppLogger.error(
            e,
            st,
            reason: 'dictation_stream',
            category: 'dictation',
          ),
        );
      },
    );
    await _applyHotkey();
  }

  /// Re-registra o atalho após mudança nas configurações.
  Future<void> applySettings() => _applyHotkey();

  Future<void> _applyHotkey() async {
    try {
      if (_settings.dictationEnabled) {
        await _native.registerDictationHotkey(
          _settings.hotkey,
          _settings.dictationMode,
        );
        _hotkeyStatus = const DictationHotkeyStatus(registered: true);
      } else {
        await _native.unregisterDictationHotkey();
        _hotkeyStatus = DictationHotkeyStatus.disabled;
      }
    } on Object catch (e) {
      // Não é erro de servidor: tipicamente falta Acessibilidade ou conflito de
      // atalho. Guardamos para exibir nas configurações; só breadcrumb (sem
      // evento de erro no Sentry a cada boot).
      _hotkeyStatus = DictationHotkeyStatus(
        registered: false,
        error: e is RbNativeException ? e.message : e.toString(),
      );
      AppLogger.warning(
        'dictation hotkey registration failed',
        category: 'dictation',
        error: e,
      );
    }
  }

  Future<void> _onEvent(DictationEvent event) async {
    // Captura qualquer erro (não só RbNativeException) para o ditado nunca
    // derrubar o stream de eventos.
    try {
      switch (event) {
        case DictationStarted():
          unawaited(_playSound(DictationSound.start));
        case DictationStopped(:final wavPath):
          await _handleStopped(wavPath);
        case DictationCancelled():
          break;
      }
    } on Object catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'dictation_event',
        category: 'dictation',
      );
    }
  }

  Future<void> _handleStopped(String wavPath) async {
    List<TranscriptSegment> segments;
    try {
      segments = await _native.transcribe(
        wavPath: wavPath,
        model: _settings.model,
        initialPrompt: await _vocabulary.initialPrompt(),
        // Ditado é interativo: prioridade alta para não ficar atrás de uma nota
        // longa na fila nativa.
        priority: TranscriptionPriority.high,
      );
    } on Object catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'dictation_transcribe',
        category: 'dictation',
      );
      unawaited(_playSound(DictationSound.end));
      await _deleteTempWav(wavPath);
      return;
    }

    unawaited(_playSound(DictationSound.end));
    // O wav do ditado é temporário: apaga após transcrever (sucesso ou erro).
    await _deleteTempWav(wavPath);

    final text = segments.map((s) => s.text.trim()).join(' ').trim();
    if (text.isEmpty) return;
    _lastText = text;

    // Salva a nota ANTES de colar: mesmo que a colagem falhe, o texto não some.
    await _saveNote(text, segments);

    // Colagem num try/catch separado: falhar aqui não descarta a nota.
    try {
      await _native.pasteText(text);
    } on Object catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'dictation_paste',
        category: 'dictation',
      );
      _notices.add(
        'Ditado salvo. Não consegui colar no app — use "Colar último ditado".',
      );
    }
  }

  /// Cola novamente o último texto ditado, se houver.
  Future<void> pasteLast() async {
    final text = _lastText;
    if (text == null || text.isEmpty) return;
    try {
      await _native.pasteText(text);
    } on Object catch (e, st) {
      await AppLogger.error(e, st, reason: 'paste_last', category: 'dictation');
      _notices.add('Não consegui colar o último ditado.');
    }
  }

  Future<void> _playSound(DictationSound sound) async {
    // Som tocado do lado Dart (o nativo não toca mais sozinho).
    try {
      await _native.playDictationSound(sound);
    } on Object catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'dictation_sound',
        category: 'dictation',
      );
    }
  }

  Future<void> _deleteTempWav(String wavPath) async {
    try {
      final file = File(wavPath);
      if (file.existsSync()) await file.delete();
    } on Object catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'dictation_cleanup',
        category: 'dictation',
      );
    }
  }

  Future<void> _saveNote(String text, List<TranscriptSegment> segments) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final title = words.take(8).join(' ');
    await _repository.insertNote(
      NotesCompanion.insert(
        id: id,
        title: Value(title),
        createdAt: now,
        updatedAt: now,
        status: NoteStatus.ready,
        source: NoteSource.dictation,
      ),
    );
    await _repository.replaceSegments(id, [
      for (final s in segments)
        DraftSegment(
          speaker: SegmentSpeaker.me,
          startMs: s.start.inMilliseconds,
          endMs: s.end.inMilliseconds,
          content: s.text.trim(),
        ),
    ]);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _notices.close();
    try {
      await _native.unregisterDictationHotkey();
    } on Object catch (_) {
      // encerrando; ignore.
    }
  }
}
