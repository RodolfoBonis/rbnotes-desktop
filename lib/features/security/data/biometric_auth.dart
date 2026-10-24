import 'package:local_auth/local_auth.dart';
import 'package:rbnotes/core/observability/app_logger.dart';

/// Autenticação local para a trava do app e das notas bloqueadas.
///
/// Diferente da trava antiga do diário (`biometricOnly: true`), aqui usamos
/// `biometricOnly: false` para permitir o **fallback para a senha do Mac**
/// quando o Touch ID falha ou não está disponível.
// ignore: one_member_abstracts
abstract interface class BiometricAuth {
  /// Pede autenticação com [reason]. Retorna true se autenticou.
  Future<bool> authenticate(String reason);
}

class LocalBiometricAuth implements BiometricAuth {
  LocalBiometricAuth({LocalAuthentication? localAuth})
    : _localAuth = localAuth ?? LocalAuthentication();

  final LocalAuthentication _localAuth;

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          // biometricOnly: false → cai para a senha do Mac se o Touch
          // ID falhar.
          // ignore: avoid_redundant_argument_values
          biometricOnly: false,
        ),
      );
    } on Object catch (e, st) {
      await AppLogger.error(e, st, reason: 'biometric_auth', category: 'lock');
      return false;
    }
  }
}

/// Fake para testes/dev: retorna [result] (default: autentica).
class FakeBiometricAuth implements BiometricAuth {
  FakeBiometricAuth({this.result = true});

  bool result;
  int calls = 0;
  final List<String> reasons = [];

  @override
  Future<bool> authenticate(String reason) async {
    calls++;
    reasons.add(reason);
    return result;
  }
}
