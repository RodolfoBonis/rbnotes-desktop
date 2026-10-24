import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:rbnotes/features/security/data/biometric_auth.dart';

/// Gate de Touch ID do Diário (M12).
///
/// Ao entrar na aba/rota do Diário — ou abrir uma entrada do diário pela lista,
/// favoritos, busca ou ⌘K — é preciso passar pelo Touch ID. Uma sessão curta
/// (padrão 5 min) evita repetir a autenticação a cada navegação; a sessão
/// expira sozinha e também é encerrada quando o app trava ([clear]).
///
/// O estado (`true` = sessão aberta) alimenta a UI do Diário: enquanto for
/// `false`, o conteúdo fica atrás de um placeholder que chama [ensure].
class DiaryGate extends Cubit<bool> {
  DiaryGate({
    required BiometricAuth auth,
    Duration session = const Duration(minutes: 5),
  }) : _auth = auth,
       _session = session,
       super(false);

  final BiometricAuth _auth;
  final Duration _session;
  Timer? _timer;

  /// Garante a sessão do Diário: se já estiver aberta, retorna `true`; senão
  /// pede Touch ID e, em caso de sucesso, abre a sessão por [_session].
  Future<bool> ensure() async {
    if (state) return true;
    if (!await _auth.authenticate('Abrir o Diário')) return false;
    if (isClosed) return false;
    _timer?.cancel();
    _timer = Timer(_session, () {
      if (!isClosed) emit(false);
    });
    emit(true);
    return true;
  }

  /// Encerra a sessão (ao travar o app, ou ao expirar). Idempotente.
  void clear() {
    _timer?.cancel();
    _timer = null;
    if (!isClosed && state) emit(false);
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
