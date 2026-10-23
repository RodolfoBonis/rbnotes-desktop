import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/domain/note_models.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/native/rb_native.dart';
import 'package:uuid/uuid.dart';

/// Ditado global: escuta o atalho, transcreve o áudio do mic, cola no app em
/// foco e salva como nota `source: dictation`. Guarda o último texto ditado
/// para o menu "Colar último ditado".
class DictationService {
  DictationService({
    required RbNative native,
    required NoteRepository repository,
    required SettingsStore settings,
    Uuid? uuid,
  }) : _native = native,
       _repository = repository,
       _settings = settings,
       _uuid = uuid ?? const Uuid();

  final RbNative _native;
  final NoteRepository _repository;
  final SettingsStore _settings;
  final Uuid _uuid;

  StreamSubscription<DictationEvent>? _sub;
  String? _lastText;

  String? get lastDictatedText => _lastText;

  /// Registra o atalho (se habilitado) e passa a escutar os eventos.
  Future<void> start() async {
    _sub = _native.dictationEvents().listen(_onEvent);
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
      } else {
        await _native.unregisterDictationHotkey();
      }
    } on RbNativeException catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'register_hotkey',
        category: 'dictation',
      );
    }
  }

  Future<void> _onEvent(DictationEvent event) async {
    switch (event) {
      case DictationStarted():
        unawaited(_native.playDictationSound(DictationSound.start));
      case DictationStopped(:final wavPath):
        await _handleStopped(wavPath);
      case DictationCancelled():
        break;
    }
  }

  Future<void> _handleStopped(String wavPath) async {
    try {
      final segments = await _native.transcribe(
        wavPath: wavPath,
        model: _settings.model,
      );
      final text = segments.map((s) => s.text.trim()).join(' ').trim();
      unawaited(_native.playDictationSound(DictationSound.end));
      if (text.isEmpty) return;
      _lastText = text;
      await _native.pasteText(text);
      await _saveNote(text, segments);
    } on RbNativeException catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'dictation_transcribe',
        category: 'dictation',
      );
      unawaited(_native.playDictationSound(DictationSound.end));
    }
  }

  /// Cola novamente o último texto ditado, se houver.
  Future<void> pasteLast() async {
    final text = _lastText;
    if (text == null || text.isEmpty) return;
    try {
      await _native.pasteText(text);
    } on RbNativeException catch (e, st) {
      await AppLogger.error(e, st, reason: 'paste_last', category: 'dictation');
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
    try {
      await _native.unregisterDictationHotkey();
    } on RbNativeException catch (_) {
      // encerrando; ignore.
    }
  }
}
