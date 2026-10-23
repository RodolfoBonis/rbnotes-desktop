import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/features/diary/domain/diary_calendar.dart';

void main() {
  group('buildDiaryCalendar', () {
    final october = DateTime(2026, 10);

    test('builds cells with leading fillers for the first weekday', () {
      final cal = buildDiaryCalendar(
        reference: october,
        entryDays: const {},
        now: DateTime(2026, 10, 23),
      );
      // 1 Oct 2026 is a Thursday → weekday 4 (Sun=0): 4 fillers.
      final fillers = cal.cells.takeWhile((c) => c.isFiller).length;
      expect(fillers, 4);
      final days = cal.cells.where((c) => !c.isFiller).toList();
      expect(days.length, 31);
    });

    test('counts a streak ending today', () {
      final cal = buildDiaryCalendar(
        reference: october,
        entryDays: const {20, 21, 22, 23},
        now: DateTime(2026, 10, 23),
      );
      expect(cal.streak, 4);
    });

    test('counts a streak ending yesterday when today is empty', () {
      final cal = buildDiaryCalendar(
        reference: october,
        entryDays: const {20, 21, 22},
        now: DateTime(2026, 10, 23),
      );
      expect(cal.streak, 3);
    });

    test('marks today and future days', () {
      final cal = buildDiaryCalendar(
        reference: october,
        entryDays: const {},
        now: DateTime(2026, 10, 23),
      );
      final today = cal.cells.firstWhere((c) => c.day == 23);
      expect(today.isToday, isTrue);
      expect(cal.cells.firstWhere((c) => c.day == 25).isFuture, isTrue);
      expect(cal.cells.firstWhere((c) => c.day == 10).isFuture, isFalse);
    });

    test('no streak when the chain is broken', () {
      final cal = buildDiaryCalendar(
        reference: october,
        entryDays: const {18, 19, 21},
        now: DateTime(2026, 10, 23),
      );
      expect(cal.streak, 0);
    });
  });
}
