import 'dart:async';

import 'package:rbnotes/core/auth/jwt.dart';
import 'package:rbnotes/core/auth/loopback_server.dart';
import 'package:rbnotes/core/auth/oidc_client.dart';
import 'package:rbnotes/core/auth/pkce.dart';
import 'package:rbnotes/core/auth/token_store.dart';
import 'package:rbnotes/core/network/api_client.dart';
import 'package:rbnotes/core/network/api_error.dart';
import 'package:rbnotes/core/network/session_events.dart';
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/features/auth/data/auth_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abre uma URL no navegador do sistema (injetável em testes).
typedef UrlLauncher = Future<bool> Function(Uri url);

/// Fábrica do servidor loopback (injetável em testes).
typedef LoopbackFactory = LoopbackAuthServer Function();

Future<bool> _defaultLauncher(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

/// `AuthService` real: OIDC Authorization Code + PKCE contra o realm Keycloak
/// `rbnotes`, tokens no Keychain e identidade confirmada em `GET /me`
/// (que também aplica a allowlist → `403 not_allowed`).
class KeycloakAuthService implements AuthService {
  KeycloakAuthService({
    required OidcClient oidc,
    required TokenStore tokens,
    required ApiClient api,
    required SessionEvents events,
    UrlLauncher? launcher,
    LoopbackFactory? loopbackFactory,
  }) : _oidc = oidc,
       _tokens = tokens,
       _api = api,
       _launch = launcher ?? _defaultLauncher,
       _loopbackFactory = loopbackFactory ?? LoopbackAuthServer.new {
    _sessionSub = events.stream.listen((event) {
      if (event is SessionExpired || event is AccessRevoked) {
        unawaited(signOut());
      }
    });
  }

  final OidcClient _oidc;
  final TokenStore _tokens;
  final ApiClient _api;
  final UrlLauncher _launch;
  final LoopbackFactory _loopbackFactory;

  final _controller = StreamController<AuthUser?>.broadcast();
  StreamSubscription<SessionEvent>? _sessionSub;
  AuthUser? _current;

  @override
  AuthUser? get currentUser => _current;

  @override
  Stream<AuthUser?> get authState async* {
    yield _current;
    yield* _controller.stream;
  }

  /// Restaura a sessão no boot: se há tokens válidos, confirma em `/me`.
  Future<void> restore() async {
    final stored = await _tokens.read();
    if (stored == null) return;
    try {
      _set(await _fetchMe());
    } on ApiError catch (e) {
      if (e.isAccessDenied || e.isUnauthorized) {
        await _tokens.clear();
        _set(null);
        return;
      }
      // Rede fora (DNS, servidor, offline): o app é local-first — entra com a
      // identidade do id_token salvo e o sync volta sozinho com a rede.
      _restoreOffline(stored.idToken, e);
    } on Object catch (e, st) {
      await AppLogger.error(e, st, reason: 'auth_restore', category: 'auth');
      _restoreOffline(stored.idToken, e);
    }
  }

  void _restoreOffline(String? idToken, Object error) {
    final user = _userFromIdToken(idToken);
    if (user == null) return;
    AppLogger.warning(
      'Sem conexão no boot; entrando com a sessão salva',
      category: 'auth',
      error: error,
    );
    _set(user);
  }

  static AuthUser? _userFromIdToken(String? idToken) {
    if (idToken == null) return null;
    try {
      final claims = decodeJwtClaims(idToken);
      final sub = claims['sub'] as String?;
      if (sub == null || sub.isEmpty) return null;
      final email = claims['email'] as String?;
      final name = claims['name'] as String?;
      return AuthUser(
        id: sub,
        name: (name == null || name.isEmpty) ? _nameFromEmail(email) : name,
        email: email ?? '',
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<AuthUser> signInWithGoogle() => _login(idpHint: 'google');

  @override
  Future<AuthUser> signInWithEmail(String email, String password) =>
      _login(loginHint: email.trim());

  @override
  Future<AuthUser> signUp(String name, String email, String password) =>
      _login(loginHint: email.trim(), register: true);

  @override
  Future<void> signOut() async {
    final stored = await _tokens.read();
    await _tokens.clear();
    _set(null);
    try {
      final url = await _oidc.endSessionUrl(idToken: stored?.idToken);
      if (url != null) await _launch(url);
    } on Object catch (e) {
      AppLogger.warning('Falha no end_session', category: 'auth', error: e);
    }
  }

  Future<void> dispose() async {
    await _sessionSub?.cancel();
    await _controller.close();
  }

  Future<AuthUser> _login({
    String? idpHint,
    String? loginHint,
    bool register = false,
  }) async {
    final pkce = PkcePair.generate();
    var url = await _oidc.authorizationUrl(
      pkce,
      idpHint: idpHint,
      loginHint: loginHint,
    );
    if (register) {
      url = url.replace(
        path: url.path.replaceFirst(
          '/openid-connect/auth',
          '/openid-connect/registrations',
        ),
      );
    }

    final server = _loopbackFactory();
    final callbackFuture = server.listen();
    bool launched;
    try {
      launched = await _launch(url);
    } on Object {
      launched = false;
    }
    if (!launched) {
      // Fecha o socket loopback imediatamente (não deixa ouvindo por 5 min) e
      // ignora o callback pendente (que só expiraria depois).
      await server.close();
      unawaited(callbackFuture.then((_) {}).catchError((_) {}));
      throw const AuthException('Não foi possível abrir o navegador.');
    }

    final AuthCallback cb;
    try {
      cb = await callbackFuture;
    } on TimeoutException {
      throw const AuthException('Tempo de login esgotado. Tente de novo.');
    }
    if (!cb.isSuccess) {
      throw const AuthException('Login cancelado.');
    }
    if (cb.state != pkce.state) {
      throw const AuthException('Falha de segurança no login (state).');
    }

    final tokens = await _oidc.exchangeCode(
      code: cb.code!,
      codeVerifier: pkce.codeVerifier,
    );
    final idToken = tokens.idToken;
    if (idToken != null) {
      final claims = decodeJwtClaims(idToken);
      final nonce = claims['nonce'];
      if (nonce != null && nonce != pkce.nonce) {
        throw const AuthException('Falha de segurança no login (nonce).');
      }
    }
    await _tokens.write(tokens);

    try {
      final user = await _fetchMe();
      _set(user);
      return user;
    } on ApiError catch (e) {
      await _tokens.clear();
      _set(null);
      if (e.isAccessDenied) {
        throw const AuthException('Esta conta não tem acesso ao RbNotes.');
      }
      throw AuthException(e.message);
    }
  }

  Future<AuthUser> _fetchMe() async {
    final me = await _api.getJson('/me');
    return AuthUser(
      id: (me['id'] as String?) ?? '',
      name: (me['name'] as String?) ?? _nameFromEmail(me['email'] as String?),
      email: (me['email'] as String?) ?? '',
    );
  }

  void _set(AuthUser? user) {
    _current = user;
    _controller.add(user);
  }

  static String _nameFromEmail(String? email) {
    if (email == null || email.isEmpty) return 'Você';
    final local = email.split('@').first.replaceAll(RegExp('[._-]+'), ' ');
    final words = local
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1));
    final name = words.join(' ').trim();
    return name.isEmpty ? 'Você' : name;
  }
}
