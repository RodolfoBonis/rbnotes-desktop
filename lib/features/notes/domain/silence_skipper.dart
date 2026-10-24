import 'package:rbnotes/native/rb_native.dart';

/// Lógica pura para "pular silêncios longos" na reprodução, sem reescrever o
/// áudio. A partir dos intervalos de silêncio (em ms), calcula:
///
/// * [skipTarget]: se a posição real cai num silêncio, para onde pular;
/// * [toDisplay]/[adjustedDuration]: tempo exibido descontando os silêncios;
/// * [fromDisplay]: o inverso, para o seek a partir da barra de progresso.
///
/// O tempo "real" é o do arquivo de áudio (que os segmentos da transcrição
/// usam); o tempo "exibido" é o que o usuário vê, sem as pausas longas.
class SilenceSkipper {
  SilenceSkipper(List<(int start, int end)> ranges)
    : _ranges = _normalize(ranges);

  /// A partir dos intervalos nativos ([SilenceRange]).
  factory SilenceSkipper.fromRanges(List<SilenceRange> ranges) =>
      SilenceSkipper([
        for (final r in ranges) (r.start.inMilliseconds, r.end.inMilliseconds),
      ]);

  final List<(int, int)> _ranges;

  List<(int, int)> get ranges => _ranges;
  bool get isEmpty => _ranges.isEmpty;

  /// Ordena, descarta inválidos e funde intervalos sobrepostos/adjacentes.
  static List<(int, int)> _normalize(List<(int, int)> input) {
    final valid = [
      for (final (s, e) in input)
        if (e > s && s >= 0) (s, e),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(int, int)>[];
    for (final r in valid) {
      if (merged.isNotEmpty && r.$1 <= merged.last.$2) {
        final last = merged.removeLast();
        merged.add((last.$1, r.$2 > last.$2 ? r.$2 : last.$2));
      } else {
        merged.add(r);
      }
    }
    return merged;
  }

  /// Se [realMs] está dentro de um silêncio `[s, e)`, devolve `e` (o ponto para
  /// onde o player deve dar seek). Caso contrário, `null`.
  int? skipTarget(int realMs) {
    for (final (s, e) in _ranges) {
      if (realMs >= s && realMs < e - _epsilonMs) return e;
    }
    return null;
  }

  /// Total de silêncio em `[0, realMs]` (parcial se [realMs] cai dentro).
  int silenceBefore(int realMs) {
    var total = 0;
    for (final (s, e) in _ranges) {
      if (realMs <= s) break;
      total += (realMs >= e ? e : realMs) - s;
    }
    return total;
  }

  /// Posição exibida (sem silêncios) para uma posição real.
  int toDisplay(int realMs) => realMs - silenceBefore(realMs);

  /// Duração exibida = duração real menos os silêncios.
  int adjustedDuration(int realDurationMs) =>
      realDurationMs - silenceBefore(realDurationMs);

  /// Posição real para uma posição exibida (inverso de [toDisplay]), para o
  /// seek pela barra de progresso.
  int fromDisplay(int displayMs) {
    var real = displayMs;
    for (final (s, e) in _ranges) {
      if (s <= real) {
        real += e - s;
      } else {
        break;
      }
    }
    return real;
  }

  /// Tolerância para não ficar "preso" na borda de um silêncio.
  static const _epsilonMs = 20;
}
