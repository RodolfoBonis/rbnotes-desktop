import 'package:intl/intl.dart';

/// Formatação pt-BR de datas e durações para a UI.
abstract final class Formatters {
  static String duration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      final m = (d.inMinutes % 60).toString().padLeft(2, '0');
      return '${d.inHours}:$m:$seconds';
    }
    return '$minutes:$seconds';
  }

  static String durationMs(int ms) => duration(Duration(milliseconds: ms));

  /// Rótulo do grupo do dia (Hoje, Ontem ou data).
  static String dayLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Hoje';
    if (diff == 1) return 'Ontem';
    return DateFormat("d 'de' MMMM 'de' y", 'pt_BR').format(day);
  }

  static String time(DateTime date) =>
      DateFormat('HH:mm', 'pt_BR').format(date);
}
