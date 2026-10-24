import 'package:equatable/equatable.dart';

/// Ação aberta de uma nota, para avaliar "Tarefas esquecidas".
class TaskActionInput {
  const TaskActionInput({
    required this.id,
    required this.text,
    required this.done,
    required this.dismissed,
    this.owner,
    this.snoozedUntil,
  });

  final String id;
  final String text;
  final String? owner;
  final bool done;
  final bool dismissed;
  final DateTime? snoozedUntil;
}

/// Nota com suas ações, para avaliar "Tarefas esquecidas".
class TaskNoteInput {
  const TaskNoteInput({
    required this.noteId,
    required this.title,
    required this.createdAt,
    required this.isDiary,
    required this.actions,
    this.isLocked = false,
  });

  final String noteId;
  final String title;
  final DateTime createdAt;
  final bool isDiary;
  final List<TaskActionInput> actions;

  /// Nota bloqueada: a tarefa aparece como "tarefa em nota bloqueada" sem o
  /// texto nem o título.
  final bool isLocked;
}

/// Uma tarefa esquecida: ação aberta de uma nota parada há vários dias.
class ForgottenTask extends Equatable {
  const ForgottenTask({
    required this.noteId,
    required this.noteTitle,
    required this.actionId,
    required this.text,
    required this.owner,
    required this.ageDays,
    this.locked = false,
  });

  final String noteId;
  final String noteTitle;
  final String actionId;
  final String text;
  final String? owner;
  final int ageDays;

  /// A tarefa está numa nota bloqueada: a UI mostra "tarefa em nota bloqueada"
  /// sem o texto.
  final bool locked;

  @override
  List<Object?> get props => [noteId, actionId, text, owner, ageDays, locked];
}

/// Retorna as tarefas abertas há [minAgeDays] dias ou mais, ignorando o diário,
/// ações concluídas/descartadas e as adiadas para o futuro (snooze).
///
/// Ordenadas da mais antiga para a mais recente (como no design v3).
List<ForgottenTask> forgottenTasks({
  required List<TaskNoteInput> notes,
  required DateTime now,
  int minAgeDays = 3,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final out = <ForgottenTask>[];
  for (final note in notes) {
    if (note.isDiary) continue;
    final created = DateTime(
      note.createdAt.year,
      note.createdAt.month,
      note.createdAt.day,
    );
    final ageDays = today.difference(created).inDays;
    if (ageDays < minAgeDays) continue;
    for (final a in note.actions) {
      if (a.done || a.dismissed) continue;
      if (a.snoozedUntil != null && a.snoozedUntil!.isAfter(now)) continue;
      out.add(
        ForgottenTask(
          noteId: note.noteId,
          // Nota bloqueada: sem título nem texto da tarefa.
          noteTitle: note.isLocked ? '' : note.title,
          actionId: a.id,
          text: note.isLocked ? '' : a.text,
          owner: note.isLocked ? null : a.owner,
          ageDays: ageDays,
          locked: note.isLocked,
        ),
      );
    }
  }
  out.sort((x, y) => y.ageDays.compareTo(x.ageDays));
  return out;
}
