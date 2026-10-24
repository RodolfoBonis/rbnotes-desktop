import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/features/diary/presentation/diary_gate.dart';
import 'package:rbnotes/features/security/data/biometric_auth.dart';

void main() {
  group('DiaryGate (M12)', () {
    test('ensure abre a sessão com Touch ID', () async {
      final auth = FakeBiometricAuth();
      final gate = DiaryGate(auth: auth);
      expect(gate.state, isFalse);
      expect(await gate.ensure(), isTrue);
      expect(gate.state, isTrue);
      expect(auth.calls, 1);
      await gate.close();
    });

    test('ensure não repete o Touch ID com a sessão aberta', () async {
      final auth = FakeBiometricAuth();
      final gate = DiaryGate(auth: auth);
      await gate.ensure();
      await gate.ensure();
      expect(auth.calls, 1, reason: 'a sessão evita re-autenticar');
      await gate.close();
    });

    test('Touch ID negado mantém a sessão fechada', () async {
      final gate = DiaryGate(auth: FakeBiometricAuth(result: false));
      expect(await gate.ensure(), isFalse);
      expect(gate.state, isFalse);
      await gate.close();
    });

    test('clear encerra a sessão (ex.: app travou)', () async {
      final gate = DiaryGate(auth: FakeBiometricAuth());
      await gate.ensure();
      expect(gate.state, isTrue);
      gate.clear();
      expect(gate.state, isFalse);
      await gate.close();
    });

    test('a sessão expira sozinha', () async {
      final gate = DiaryGate(
        auth: FakeBiometricAuth(),
        session: const Duration(milliseconds: 40),
      );
      await gate.ensure();
      expect(gate.state, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(gate.state, isFalse);
      await gate.close();
    });
  });
}
