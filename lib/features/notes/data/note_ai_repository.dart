import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/ai/domain/note_ai.dart';

/// Persistência do enriquecimento por IA: resumo (`note_ai`), ações e chat.
class NoteAiRepository {
  NoteAiRepository(this._db);

  final AppDatabase _db;

  // ---------- note_ai ----------

  Stream<NoteAi?> watchNoteAi(String noteId) {
    return (_db.select(
      _db.noteAiTable,
    )..where((t) => t.noteId.equals(noteId))).watchSingleOrNull().map(
      (row) => row == null ? null : NoteAi.decode(row.json),
    );
  }

  Future<NoteAi?> getNoteAi(String noteId) async {
    final row = await (_db.select(
      _db.noteAiTable,
    )..where((t) => t.noteId.equals(noteId))).getSingleOrNull();
    return row == null ? null : NoteAi.decode(row.json);
  }

  Future<void> saveNoteAi(String noteId, NoteAi ai) async {
    await _db
        .into(_db.noteAiTable)
        .insertOnConflictUpdate(
          NoteAiTableCompanion.insert(
            noteId: noteId,
            json: ai.encode(),
            updatedAt: DateTime.now(),
          ),
        );
  }

  // ---------- actions ----------

  Stream<List<ActionRow>> watchActions(String noteId) {
    return (_db.select(_db.actions)
          ..where((a) => a.noteId.equals(noteId) & a.deleted.equals(false))
          ..orderBy([(a) => OrderingTerm.asc(a.orderIndex)]))
        .watch();
  }

  /// Todas as ações não apagadas (para "Tarefas esquecidas").
  Future<List<ActionRow>> allActions() =>
      (_db.select(_db.actions)..where((a) => a.deleted.equals(false))).get();

  Stream<List<ActionRow>> watchAllActions() =>
      (_db.select(_db.actions)..where((a) => a.deleted.equals(false))).watch();

  Future<void> replaceActions(
    String noteId,
    List<NoteAction> actions, {
    required String Function() genId,
  }) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.delete(
        _db.actions,
      )..where((a) => a.noteId.equals(noteId))).go();
      await _db.batch((b) {
        for (var i = 0; i < actions.length; i++) {
          final a = actions[i];
          b.insert(
            _db.actions,
            ActionsCompanion.insert(
              id: genId(),
              noteId: noteId,
              content: a.text,
              owner: Value(a.owner),
              due: Value(a.due),
              orderIndex: Value(i),
              updatedAt: now,
            ),
          );
        }
      });
    });
  }

  Future<void> setActionDone(String id, {required bool done}) {
    return (_db.update(_db.actions)..where((a) => a.id.equals(id))).write(
      ActionsCompanion(done: Value(done), updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> snoozeAction(String id, DateTime until) {
    return (_db.update(_db.actions)..where((a) => a.id.equals(id))).write(
      ActionsCompanion(
        snoozedUntil: Value(until),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> dismissAction(String id) {
    return (_db.update(_db.actions)..where((a) => a.id.equals(id))).write(
      ActionsCompanion(
        dismissed: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // ---------- chat ----------

  Stream<List<ChatMessageRow>> watchChat(String noteId) {
    return (_db.select(_db.chatMessages)
          ..where((m) => m.noteId.equals(noteId) & m.deleted.equals(false))
          ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
        .watch();
  }

  Future<void> addChatMessage({
    required String id,
    required String noteId,
    required ChatRole role,
    required String content,
    List<int> cites = const [],
  }) async {
    final now = DateTime.now();
    await _db
        .into(_db.chatMessages)
        .insert(
          ChatMessagesCompanion.insert(
            id: id,
            noteId: noteId,
            role: role,
            content: content,
            citesJson: Value(cites.isEmpty ? null : jsonEncode(cites)),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  /// Decodifica os instantes citados de uma mensagem (`citesJson`).
  static List<int> decodeCites(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return (jsonDecode(raw) as List).map((e) => (e as num).toInt()).toList();
  }
}
