import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/features/ai/domain/privacy_masker.dart';

void main() {
  group('PrivacyMasker', () {
    test('masks a formatted CPF', () {
      final out = PrivacyMasker.mask('Meu CPF é 123.456.789-09, anota aí.');
      expect(out, contains('(CPF)'));
      expect(out, isNot(contains('123.456.789-09')));
    });

    test('masks a bare 11-digit CPF', () {
      final out = PrivacyMasker.mask('documento 12345678909 pronto');
      expect(out, contains('(CPF)'));
      expect(out, isNot(contains('12345678909')));
    });

    test('masks a 16-digit card with spaces', () {
      final out = PrivacyMasker.mask('cartão 4111 1111 1111 1111 na mão');
      expect(out, contains('cartão'));
      expect(out, isNot(contains('4111 1111 1111 1111')));
    });

    test('masks a BR phone number', () {
      final out = PrivacyMasker.mask('me liga no (11) 98888-7777 depois');
      expect(out, contains('(telefone)'));
      expect(out, isNot(contains('98888-7777')));
    });

    test('leaves ordinary text untouched', () {
      const text = 'Reunião às 10h sobre o roadmap do trimestre.';
      expect(PrivacyMasker.mask(text), text);
      expect(PrivacyMasker.hasSensitiveData(text), isFalse);
    });

    test('does not treat a short year as a phone', () {
      const text = 'Em 2026 vamos lançar.';
      expect(PrivacyMasker.mask(text), text);
    });

    test('hasSensitiveData detects a CPF', () {
      expect(
        PrivacyMasker.hasSensitiveData('cpf 123.456.789-09'),
        isTrue,
      );
    });
  });
}
