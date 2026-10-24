import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/features/notes/domain/silence_skipper.dart';

void main() {
  // Silêncios: [2000,4000) e [6000,7000). Total silencioso = 3000 ms.
  final skipper = SilenceSkipper([(2000, 4000), (6000, 7000)]);

  test('skipTarget pula para o fim de um silêncio', () {
    expect(skipper.skipTarget(2500), 4000);
    expect(skipper.skipTarget(6500), 7000);
  });

  test('skipTarget é null fora dos silêncios', () {
    expect(skipper.skipTarget(1000), isNull);
    expect(skipper.skipTarget(5000), isNull);
    expect(skipper.skipTarget(4000), isNull); // borda = já fora
  });

  test('toDisplay desconta os silêncios percorridos', () {
    expect(skipper.toDisplay(1000), 1000); // antes do 1º silêncio
    expect(skipper.toDisplay(3000), 2000); // dentro do 1º (parcial 1000)
    expect(skipper.toDisplay(5000), 3000); // após o 1º (desconta 2000)
    expect(skipper.toDisplay(7000), 4000); // após ambos (desconta 3000)
  });

  test('adjustedDuration subtrai o total de silêncio', () {
    expect(skipper.adjustedDuration(10000), 7000);
  });

  test('fromDisplay é o inverso de toDisplay', () {
    expect(skipper.fromDisplay(3000), 5000);
    expect(skipper.fromDisplay(4000), 7000);
    expect(skipper.fromDisplay(1000), 1000);
  });

  test('normaliza intervalos sobrepostos e inválidos', () {
    final s = SilenceSkipper([(100, 50), (1000, 2000), (1500, 2500)]);
    expect(s.ranges, [(1000, 2500)]);
  });

  test('vazio não altera nada', () {
    final s = SilenceSkipper(const []);
    expect(s.isEmpty, isTrue);
    expect(s.toDisplay(1234), 1234);
    expect(s.adjustedDuration(9999), 9999);
    expect(s.skipTarget(500), isNull);
  });
}
