import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/features/collections/domain/forgotten_tasks.dart';

void main() {
  final now = DateTime(2026, 10, 23, 12);

  TaskNoteInput note({
    required String id,
    required int ageDays,
    bool isDiary = false,
    bool isLocked = false,
    List<TaskActionInput> actions = const [],
  }) => TaskNoteInput(
    noteId: id,
    title: 'Nota $id',
    createdAt: now.subtract(Duration(days: ageDays)),
    isDiary: isDiary,
    isLocked: isLocked,
    actions: actions,
  );

  TaskActionInput action(
    String id, {
    bool done = false,
    bool dismissed = false,
    DateTime? snoozedUntil,
  }) => TaskActionInput(
    id: id,
    text: 'Fazer $id',
    done: done,
    dismissed: dismissed,
    snoozedUntil: snoozedUntil,
  );

  test('includes open actions from notes older than 3 days', () {
    final tasks = forgottenTasks(
      notes: [
        note(id: 'a', ageDays: 5, actions: [action('a1')]),
        note(id: 'b', ageDays: 1, actions: [action('b1')]),
      ],
      now: now,
    );
    expect(tasks.map((t) => t.actionId), ['a1']);
  });

  test('excludes done, dismissed and diary actions', () {
    final tasks = forgottenTasks(
      notes: [
        note(id: 'a', ageDays: 9, actions: [action('a1', done: true)]),
        note(id: 'b', ageDays: 9, actions: [action('b1', dismissed: true)]),
        note(id: 'c', ageDays: 9, isDiary: true, actions: [action('c1')]),
      ],
      now: now,
    );
    expect(tasks, isEmpty);
  });

  test('respects snooze into the future', () {
    final tasks = forgottenTasks(
      notes: [
        note(
          id: 'a',
          ageDays: 9,
          actions: [
            action('a1', snoozedUntil: now.add(const Duration(days: 1))),
          ],
        ),
        note(
          id: 'b',
          ageDays: 9,
          actions: [
            action('b1', snoozedUntil: now.subtract(const Duration(days: 1))),
          ],
        ),
      ],
      now: now,
    );
    expect(tasks.map((t) => t.actionId), ['b1']);
  });

  test('sorts oldest first', () {
    final tasks = forgottenTasks(
      notes: [
        note(id: 'a', ageDays: 4, actions: [action('a1')]),
        note(id: 'b', ageDays: 12, actions: [action('b1')]),
        note(id: 'c', ageDays: 7, actions: [action('c1')]),
      ],
      now: now,
    );
    expect(tasks.map((t) => t.noteId), ['b', 'c', 'a']);
  });

  test('redacts tasks from locked notes', () {
    final tasks = forgottenTasks(
      notes: [
        note(id: 'a', ageDays: 5, isLocked: true, actions: [action('a1')]),
      ],
      now: now,
    );
    expect(tasks.single.locked, isTrue);
    expect(tasks.single.text, '');
    expect(tasks.single.noteTitle, '');
    expect(tasks.single.owner, isNull);
  });
}
