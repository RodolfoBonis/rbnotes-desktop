import 'dart:async';

import 'package:equatable/equatable.dart';

/// Eventos globais de sessão emitidos pela camada de rede, consumidos pelo
/// `SessionCubit`/`AuthService` para derrubar a sessão quando preciso.
sealed class SessionEvent extends Equatable {
  const SessionEvent();

  @override
  List<Object?> get props => [];
}

/// O refresh falhou (ou não há refresh token): precisa logar de novo.
final class SessionExpired extends SessionEvent {
  const SessionExpired();
}

/// `403 not_allowed`: a conta autenticou no Keycloak mas não está na allowlist
/// do RbNotes. A UI mostra o aviso e faz logout.
final class AccessRevoked extends SessionEvent {
  const AccessRevoked();
}

/// Barramento simples (broadcast) entre a rede e o estado de sessão.
class SessionEvents {
  final _controller = StreamController<SessionEvent>.broadcast();

  Stream<SessionEvent> get stream => _controller.stream;

  void emit(SessionEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  Future<void> dispose() => _controller.close();
}
