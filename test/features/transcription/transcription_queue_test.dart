import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/transcription/data/transcription_queue.dart';
import 'package:rbnotes/native/fake_rb_native.dart';
import 'package:rbnotes/native/rb_native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late NoteRepositoryQueueHarness h;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = memoryDb();
    h = NoteRepositoryQueueHarness(db, await SharedPreferences.getInstance());
  });
  tearDown(() async {
    await h.queue.dispose();
    await db.close();
  });

  Future<void> seedRecording(
    String id, {
    bool withSystem = false,
    NoteStatus status = NoteStatus.transcribing,
    bool withMic = true,
  }) async {
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: id,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
            status: status,
            source: NoteSource.recording,
            micWavPath: withMic
                ? Value('/tmp/$id.mic.wav')
                : const Value.absent(),
            systemWavPath: withSystem
                ? Value('/tmp/$id.system.wav')
                : const Value.absent(),
          ),
        );
  }

  test('transcreve, salva segmentos, gera título e marca ready', () async {
    await seedRecording('n1');
    h.queue.enqueue('n1');
    final result = await h.queue.progress.firstWhere((p) => p.isTerminal);
    expect(result.failed, isFalse);

    final note = await h.repo.getNote('n1');
    expect(note!.status, NoteStatus.ready);
    expect(note.title, isNotEmpty);
    final segments = await h.repo.getSegments('n1');
    expect(segments, isNotEmpty);
    expect(segments.every((s) => s.speaker == SegmentSpeaker.me), isTrue);
  });

  test('com áudio do sistema junta falantes eu/outros', () async {
    await seedRecording('n2', withSystem: true);
    h.queue.enqueue('n2');
    await h.queue.progress.firstWhere((p) => p.isTerminal);
    final segments = await h.repo.getSegments('n2');
    expect(segments.any((s) => s.speaker == SegmentSpeaker.me), isTrue);
    expect(segments.any((s) => s.speaker == SegmentSpeaker.others), isTrue);
  });

  test('modelo ausente marca a nota como failed', () async {
    h.native.modelDownloaded = false;
    await seedRecording('n3');
    h.queue.enqueue('n3');
    final result = await h.queue.progress.firstWhere((p) => p.isTerminal);
    expect(result.failed, isTrue);
    expect((await h.repo.getNote('n3'))!.status, NoteStatus.failed);
  });

  test('nota sem micWavPath é marcada failed', () async {
    await seedRecording('n4', withMic: false);
    h.queue.enqueue('n4');
    final result = await h.queue.progress.firstWhere((p) => p.isTerminal);
    expect(result.failed, isTrue);
    expect((await h.repo.getNote('n4'))!.status, NoteStatus.failed);
  });

  test('enqueue de nota inexistente não derruba a fila', () async {
    await seedRecording('real');
    h.queue
      ..enqueue('ghost') // nunca existiu → tratado sem erro
      ..enqueue('real');
    await h.queue.progress.firstWhere(
      (p) => p.noteId == 'real' && p.isTerminal,
    );
    expect((await h.repo.getNote('real'))!.status, NoteStatus.ready);
  });

  test('requeueInterrupted reenfileira todas as notas transcribing', () async {
    await seedRecording('a');
    await seedRecording('b');
    await h.queue.requeueInterrupted();
    await h.queue.progress.where((p) => p.isTerminal).take(2).toList();
    expect((await h.repo.getNote('a'))!.status, NoteStatus.ready);
    expect((await h.repo.getNote('b'))!.status, NoteStatus.ready);
  });

  test('retry reenfileira uma nota que falhou', () async {
    await seedRecording('f', status: NoteStatus.failed);
    h.queue.retry('f');
    await h.queue.progress.firstWhere((p) => p.isTerminal);
    expect((await h.repo.getNote('f'))!.status, NoteStatus.ready);
  });

  group('natives roteirizados', () {
    late AppDatabase db2;
    late NoteRepository repo;
    late SettingsStore settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db2 = memoryDb();
      repo = memoryRepo(db2);
      settings = SettingsStore(await SharedPreferences.getInstance());
    });
    tearDown(() => db2.close());

    Future<void> seed(String id, {bool withSystem = false}) async {
      await db2
          .into(db2.notes)
          .insert(
            NotesCompanion.insert(
              id: id,
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
              status: NoteStatus.transcribing,
              source: NoteSource.recording,
              micWavPath: Value('/tmp/$id.mic.wav'),
              systemWavPath: withSystem
                  ? Value('/tmp/$id.system.wav')
                  : const Value.absent(),
            ),
          );
    }

    test('transcription_cancelled é estado distinto (não failed)', () async {
      final native = _ScriptedNative(
        onTranscribe: (_) => throw const RbNativeException(
          RbNativeErrorCode.transcriptionCancelled,
          'cancelada',
        ),
      );
      final queue = TranscriptionQueue(
        native: native,
        repository: repo,
        settings: settings,
      );
      await seed('c');
      queue.enqueue('c');
      final result = await queue.progress.firstWhere((p) => p.isTerminal);
      expect(result.cancelled, isTrue);
      expect(result.failed, isFalse);
      // Não vira failed: status permanece transcribing.
      expect((await repo.getNote('c'))!.status, NoteStatus.transcribing);
      await queue.dispose();
    });

    test('falha só do áudio do sistema → ready parcial com mic', () async {
      final native = _ScriptedNative(
        onTranscribe: (wavPath) {
          if (wavPath.contains('.system.wav')) {
            throw const RbNativeException(
              RbNativeErrorCode.transcriptionFailed,
              'sistema falhou',
            );
          }
          return Future.value(const [
            TranscriptSegment(
              start: Duration.zero,
              end: Duration(seconds: 1),
              text: 'só o mic sobreviveu',
            ),
          ]);
        },
      );
      final queue = TranscriptionQueue(
        native: native,
        repository: repo,
        settings: settings,
      );
      await seed('p', withSystem: true);
      queue.enqueue('p');
      final result = await queue.progress.firstWhere((p) => p.isTerminal);
      expect(result.done, isTrue);
      expect(result.partial, isTrue);
      expect((await repo.getNote('p'))!.status, NoteStatus.ready);
      final segments = await repo.getSegments('p');
      expect(segments, isNotEmpty);
      expect(segments.every((s) => s.speaker == SegmentSpeaker.me), isTrue);
      await queue.dispose();
    });

    test('dedup: nota em processamento não é enfileirada de novo', () async {
      final gate = Completer<List<TranscriptSegment>>();
      final native = _ScriptedNative(onTranscribe: (_) => gate.future);
      final queue = TranscriptionQueue(
        native: native,
        repository: repo,
        settings: settings,
      );
      await seed('d');
      queue.enqueue('d'); // começa e trava no gate
      await Future<void>.delayed(const Duration(milliseconds: 20));
      queue.enqueue('d'); // deve ser ignorada (em processamento)
      gate.complete(const [
        TranscriptSegment(
          start: Duration.zero,
          end: Duration(seconds: 1),
          text: 'pronto',
        ),
      ]);
      await queue.progress.firstWhere((p) => p.isTerminal);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(native.transcribeCalls.where((w) => w.contains('d')).length, 1);
      await queue.dispose();
    });
  });
}

/// FakeRbNative com `transcribe` roteirizado por `wavPath`.
class _ScriptedNative extends FakeRbNative {
  _ScriptedNative({required this.onTranscribe});

  final Future<List<TranscriptSegment>> Function(String wavPath) onTranscribe;
  final List<String> transcribeCalls = [];

  @override
  Future<List<TranscriptSegment>> transcribe({
    required String wavPath,
    required WhisperModel model,
    String language = 'pt',
    TranscriptionPriority priority = TranscriptionPriority.normal,
    void Function(double progress)? onProgress,
  }) {
    transcribeCalls.add(wavPath);
    onProgress?.call(1);
    return onTranscribe(wavPath);
  }
}

class NoteRepositoryQueueHarness {
  NoteRepositoryQueueHarness(AppDatabase db, SharedPreferences prefs)
    : repo = memoryRepo(db),
      native = FakeRbNative(),
      settings = SettingsStore(prefs) {
    queue = TranscriptionQueue(
      native: native,
      repository: repo,
      settings: settings,
    );
  }

  final NoteRepository repo;
  final FakeRbNative native;
  final SettingsStore settings;
  late final TranscriptionQueue queue;
}
