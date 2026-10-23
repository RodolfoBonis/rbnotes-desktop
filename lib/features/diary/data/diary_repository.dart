import 'package:drift/drift.dart';
import 'package:rbnotes/data/database/database.dart';

/// Perguntas e entradas do diário (calendário/sequência).
class DiaryRepository {
  DiaryRepository(this._db);

  final AppDatabase _db;

  Future<List<DiaryPromptRow>> getPrompts() => (_db.select(
    _db.diaryPrompts,
  )..orderBy([(p) => OrderingTerm.asc(p.sortOrder)])).get();

  Stream<List<DiaryEntryRow>> watchEntries() => (_db.select(
    _db.diaryEntries,
  )..where((e) => e.deleted.equals(false))).watch();

  Future<List<DiaryEntryRow>> getEntries() => (_db.select(
    _db.diaryEntries,
  )..where((e) => e.deleted.equals(false))).get();

  /// Dias (1..31) com entrada no mês de [reference].
  Future<Set<int>> entryDaysInMonth(DateTime reference) async {
    final entries = await getEntries();
    final days = <int>{};
    for (final e in entries) {
      final parts = e.day.split('-');
      if (parts.length != 3) continue;
      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final day = int.tryParse(parts[2]);
      if (year == reference.year && month == reference.month && day != null) {
        days.add(day);
      }
    }
    return days;
  }

  Future<void> upsertEntry({
    required DateTime day,
    String? noteId,
    String? promptId,
  }) async {
    final key =
        '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    final now = DateTime.now();
    await _db
        .into(_db.diaryEntries)
        .insertOnConflictUpdate(
          DiaryEntriesCompanion.insert(
            day: key,
            noteId: Value(noteId),
            promptId: Value(promptId),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }
}
