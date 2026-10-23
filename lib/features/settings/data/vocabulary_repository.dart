import 'package:drift/drift.dart';
import 'package:rbnotes/data/database/database.dart';

/// Vocabulário do Whisper: nomes/termos que viram o `initialPrompt` da
/// transcrição (ex.: "Thaís" para o Whisper não ouvir "Taís").
class VocabularyRepository {
  VocabularyRepository(this._db);

  final AppDatabase _db;

  Stream<List<VocabularyRow>> watchTerms() => (_db.select(
    _db.vocabulary,
  )..where((v) => v.deleted.equals(false))).watch();

  Future<List<String>> getTerms() async {
    final rows = await (_db.select(
      _db.vocabulary,
    )..where((v) => v.deleted.equals(false))).get();
    return rows.map((r) => r.term).toList();
  }

  /// Monta o `initialPrompt` do Whisper a partir dos termos salvos, ou null se
  /// não houver nenhum.
  Future<String?> initialPrompt() async {
    final terms = await getTerms();
    if (terms.isEmpty) return null;
    return 'Vocabulário: ${terms.join(', ')}.';
  }

  Future<void> add(String id, String term) async {
    final clean = term.trim();
    if (clean.isEmpty) return;
    await _db
        .into(_db.vocabulary)
        .insert(
          VocabularyCompanion.insert(
            id: id,
            term: clean,
            updatedAt: DateTime.now(),
          ),
        );
  }

  Future<void> remove(String id) {
    return (_db.update(_db.vocabulary)..where((v) => v.id.equals(id))).write(
      VocabularyCompanion(
        deleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
