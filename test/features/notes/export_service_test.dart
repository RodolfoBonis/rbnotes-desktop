import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/export_service.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';

import '../../helpers/test_db.dart';

/// Lê os nomes das entradas de um zip "store" (sem compressão) pelos cabeçalhos
/// locais `PK\x03\x04`, para validar a estrutura sem um pacote externo.
List<String> zipEntryNames(List<int> bytes) {
  final names = <String>[];
  for (var i = 0; i + 30 < bytes.length; i++) {
    if (bytes[i] == 0x50 &&
        bytes[i + 1] == 0x4B &&
        bytes[i + 2] == 0x03 &&
        bytes[i + 3] == 0x04) {
      final nameLen = bytes[i + 26] | (bytes[i + 27] << 8);
      final start = i + 30;
      names.add(String.fromCharCodes(bytes.sublist(start, start + nameLen)));
    }
  }
  return names;
}

void main() {
  late AppDatabase db;
  late NoteRepository notes;
  late ExportService service;
  late Directory tmp;

  setUp(() async {
    db = memoryDb();
    notes = NoteRepository(db);
    service = ExportService(notes: notes);
    tmp = await Directory.systemTemp.createTemp('rbnotes_export');
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> seed(
    String id,
    String title, {
    bool locked = false,
    String? audioPath,
  }) async {
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: id,
            title: Value(title),
            createdAt: DateTime(2026, 6),
            updatedAt: DateTime(2026, 6),
            status: NoteStatus.ready,
            source: NoteSource.recording,
            locked: Value(locked),
            playbackPath: Value(audioPath),
          ),
        );
    await db
        .into(db.transcriptSegments)
        .insert(
          TranscriptSegmentsCompanion.insert(
            noteId: id,
            speaker: SegmentSpeaker.me,
            startMs: 0,
            endMs: 1000,
            content: 'Conteúdo de $title',
          ),
        );
  }

  test('gera um zip com uma pasta por nota (.md) e o áudio opcional', () async {
    final audio = File('${tmp.path}/a.m4a')..writeAsStringSync('audio');
    await seed('n1', 'Reunião de time', audioPath: audio.path);
    await seed('n2', 'Ideia solta');

    final dest = '${tmp.path}/export.zip';
    final steps = <int>[];
    final result = await service.exportAll(
      destinationPath: dest,
      onProgress: (done, total) => steps.add(done),
    );

    expect(result.exported, 2);
    expect(result.excludedLocked, 0);
    final names = zipEntryNames(File(dest).readAsBytesSync());
    expect(names, contains('reuniao-de-time/nota.md'));
    expect(names, contains('reuniao-de-time/audio.m4a'));
    expect(names, contains('ideia-solta/nota.md'));
    expect(steps, [1, 2]);
  });

  test('nota bloqueada fica de fora quando o Touch ID é negado', () async {
    await seed('n1', 'Aberta');
    await seed('secreta', 'Segredo', locked: true);

    final dest = '${tmp.path}/export.zip';
    final result = await service.exportAll(
      destinationPath: dest,
      unlockLocked: () async => false,
    );

    expect(result.exported, 1);
    expect(result.excludedLocked, 1);
    final names = zipEntryNames(File(dest).readAsBytesSync());
    expect(names.any((n) => n.startsWith('segredo/')), isFalse);
  });

  test('nota bloqueada entra quando o Touch ID é aprovado', () async {
    await seed('secreta', 'Segredo', locked: true);
    final dest = '${tmp.path}/export.zip';
    final result = await service.exportAll(
      destinationPath: dest,
      unlockLocked: () async => true,
    );
    expect(result.exported, 1);
    expect(result.excludedLocked, 0);
    final names = zipEntryNames(File(dest).readAsBytesSync());
    expect(names, contains('segredo/nota.md'));
  });
}
