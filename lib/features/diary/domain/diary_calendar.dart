import 'package:equatable/equatable.dart';

/// Uma célula do calendário mensal do diário.
class DiaryDayCell extends Equatable {
  const DiaryDayCell({
    required this.day,
    required this.hasEntry,
    required this.isToday,
    required this.isFuture,
    required this.isFiller,
  });

  /// Célula vazia no começo do mês (antes do dia 1).
  const DiaryDayCell.filler()
    : day = 0,
      hasEntry = false,
      isToday = false,
      isFuture = false,
      isFiller = true;

  final int day;
  final bool hasEntry;
  final bool isToday;
  final bool isFuture;
  final bool isFiller;

  @override
  List<Object?> get props => [day, hasEntry, isToday, isFuture, isFiller];
}

/// Calendário do mês do diário + a sequência de dias seguidos (streak).
class DiaryCalendar extends Equatable {
  const DiaryCalendar({required this.cells, required this.streak});

  final List<DiaryDayCell> cells;
  final int streak;

  @override
  List<Object?> get props => [cells, streak];
}

/// Monta o calendário do mês de [reference] a partir dos dias com entrada
/// ([entryDays], 1..31) e calcula a sequência (streak) terminando hoje.
///
/// A sequência conta para trás a partir de hoje (se houve entrada hoje) ou de
/// ontem, enquanto houver dias consecutivos com entrada — como no design v3.
DiaryCalendar buildDiaryCalendar({
  required DateTime reference,
  required Set<int> entryDays,
  required DateTime now,
}) {
  final year = reference.year;
  final month = reference.month;
  final daysInMonth = DateTime(year, month + 1, 0).day;
  // Dia da semana do dia 1 (domingo=0 .. sábado=6).
  final firstWeekday = DateTime(year, month).weekday % 7;
  final isCurrentMonth = now.year == year && now.month == month;
  final todayDay = isCurrentMonth ? now.day : -1;

  final cells = <DiaryDayCell>[
    for (var i = 0; i < firstWeekday; i++) const DiaryDayCell.filler(),
    for (var d = 1; d <= daysInMonth; d++)
      DiaryDayCell(
        day: d,
        hasEntry: entryDays.contains(d),
        isToday: d == todayDay,
        isFuture: isCurrentMonth && d > todayDay,
        isFiller: false,
      ),
  ];

  var streak = 0;
  if (isCurrentMonth) {
    var d = entryDays.contains(todayDay) ? todayDay : todayDay - 1;
    while (d >= 1 && entryDays.contains(d)) {
      streak++;
      d--;
    }
  }
  return DiaryCalendar(cells: cells, streak: streak);
}
