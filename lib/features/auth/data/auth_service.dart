import 'dart:async';

import 'package:equatable/equatable.dart';

/// Usuário autenticado.
class AuthUser extends Equatable {
  const AuthUser({required this.id, required this.name, required this.email});

  final String id;
  final String name;
  final String email;

  /// Iniciais para o avatar (até 2 letras).
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  @override
  List<Object?> get props => [id, name, email];
}

/// Erro de autenticação (credenciais inválidas, etc.).
class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => 'AuthException: $message';
}

/// Autenticação do RbNotes. A integração Keycloak/PKCE (Authorization Code +
/// loopback, tokens no Keychain) entra depois; a UI depende só desta interface.
///
/// O login com a Apple fica fora por ora (exige Apple Developer pago) — a UI
/// mostra o botão desabilitado.
abstract interface class AuthService {
  /// Usuário atual, ou null se não autenticado.
  AuthUser? get currentUser;

  /// Emite o usuário atual (ou null ao sair). Começa com o estado atual.
  Stream<AuthUser?> get authState;

  Future<AuthUser> signInWithEmail(String email, String password);
  Future<AuthUser> signUp(String name, String email, String password);
  Future<AuthUser> signInWithGoogle();
  Future<void> signOut();
}

/// Autenticação de mentira para desenvolvimento/testes: aceita qualquer
/// credencial e deriva um nome do e-mail quando o nome não é informado.
class FakeAuthService implements AuthService {
  FakeAuthService({this.latency = const Duration(milliseconds: 700)});

  final Duration latency;
  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? _current;

  @override
  AuthUser? get currentUser => _current;

  @override
  Stream<AuthUser?> get authState async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  Future<AuthUser> signInWithEmail(String email, String password) async {
    await Future<void>.delayed(latency);
    if (email.trim().isEmpty || password.isEmpty) {
      throw const AuthException('Informe e-mail e senha.');
    }
    return _set(AuthUser(id: _id(email), name: _nameFrom(email), email: email));
  }

  @override
  Future<AuthUser> signUp(String name, String email, String password) async {
    await Future<void>.delayed(latency);
    if (email.trim().isEmpty || password.isEmpty) {
      throw const AuthException('Informe e-mail e senha.');
    }
    final resolved = name.trim().isEmpty ? _nameFrom(email) : name.trim();
    return _set(AuthUser(id: _id(email), name: resolved, email: email));
  }

  @override
  Future<AuthUser> signInWithGoogle() async {
    await Future<void>.delayed(latency);
    return _set(
      const AuthUser(
        id: 'google-user',
        name: 'Renata Borges',
        email: 'renata@borges.studio',
      ),
    );
  }

  @override
  Future<void> signOut() async {
    _current = null;
    _controller.add(null);
  }

  Future<void> dispose() => _controller.close();

  AuthUser _set(AuthUser user) {
    _current = user;
    _controller.add(user);
    return user;
  }

  static String _id(String email) => 'user:${email.trim().toLowerCase()}';

  static String _nameFrom(String email) {
    final local = email.split('@').first.replaceAll(RegExp('[._-]+'), ' ');
    final words = local
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1));
    final name = words.join(' ').trim();
    return name.isEmpty ? 'Você' : name;
  }
}
