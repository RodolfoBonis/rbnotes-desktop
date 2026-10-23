import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/core/auth/loopback_server.dart';
import 'package:rbnotes/core/auth/oidc_client.dart';
import 'package:rbnotes/core/auth/token_store.dart';
import 'package:rbnotes/core/network/api_client.dart';
import 'package:rbnotes/core/network/session_events.dart';
import 'package:rbnotes/features/auth/data/auth_service.dart';
import 'package:rbnotes/features/auth/data/keycloak_auth_service.dart';

import '../../helpers/local_server.dart';

class _FakeLoopback extends LoopbackAuthServer {
  _FakeLoopback(this._future);
  final Future<AuthCallback> _future;

  @override
  Future<AuthCallback> listen() => _future;

  @override
  Future<void> close() async {}
}

void main() {
  late LocalServer server;
  var meStatus = 200;

  setUp(() {
    HttpOverrides.global = null;
    meStatus = 200;
    server = _unset;
  });

  tearDown(() async {
    await server.close();
  });

  Future<void> boot() async {
    server = await LocalServer.start((req) async {
      final path = req.uri.path;
      if (path.endsWith('/.well-known/openid-configuration')) {
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType('application', 'json')
          ..write(
            jsonEncode({
              'issuer': '${server.base}/realms/rbnotes',
              'authorization_endpoint':
                  '${server.base}/realms/rbnotes/protocol/openid-connect/auth',
              'token_endpoint':
                  '${server.base}/realms/rbnotes/protocol/openid-connect/token',
              'end_session_endpoint':
                  '${server.base}/realms/rbnotes/protocol/openid-connect/logout',
            }),
          );
        await req.response.close();
        return;
      }
      if (path.endsWith('/token')) {
        await req.drain<void>();
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType('application', 'json')
          ..write(
            jsonEncode({
              'access_token': 'access-1',
              'refresh_token': 'refresh-1',
              'expires_in': 300,
            }),
          );
        await req.response.close();
        return;
      }
      if (path == '/v1/me') {
        if (meStatus == 403) {
          req.response
            ..statusCode = 403
            ..headers.contentType = ContentType('application', 'problem+json')
            ..write(jsonEncode({'code': 'not_allowed'}));
        } else {
          req.response
            ..statusCode = 200
            ..headers.contentType = ContentType('application', 'json')
            ..write(
              jsonEncode({
                'id': 'u-1',
                'email': 'eu@x.com',
                'name': 'Rodolfo',
              }),
            );
        }
        await req.response.close();
        return;
      }
      req.response.statusCode = 404;
      await req.response.close();
    });
  }

  ({KeycloakAuthService auth, List<Uri> launched}) build(
    Future<AuthCallback> Function(Uri url) onLaunch,
  ) {
    final launched = <Uri>[];
    final oidc = OidcClient(
      dio: Dio(),
      issuer: '${server.base}/realms/rbnotes',
      clientId: 'rbnotes-desktop',
      redirectUri: 'http://127.0.0.1:53682/callback',
    );
    final tokens = MemoryTokenStore();
    final events = SessionEvents();
    final api = ApiClient(
      baseUrl: '${server.base}/v1',
      tokens: tokens,
      oidc: oidc,
      events: events,
    );
    final completer = Completer<AuthCallback>();
    final auth = KeycloakAuthService(
      oidc: oidc,
      tokens: tokens,
      api: api,
      events: events,
      loopbackFactory: () => _FakeLoopback(completer.future),
      launcher: (url) async {
        launched.add(url);
        completer.complete(await onLaunch(url));
        return true;
      },
    );
    return (auth: auth, launched: launched);
  }

  Future<AuthCallback> callbackWithState(Uri url) async =>
      AuthCallback(code: 'code-1', state: url.queryParameters['state']);

  test('login com Google usa kc_idp_hint e resolve o usuário em /me', () async {
    await boot();
    final b = build(callbackWithState);
    final user = await b.auth.signInWithGoogle();
    expect(user.name, 'Rodolfo');
    expect(user.email, 'eu@x.com');
    expect(b.launched.single.queryParameters['kc_idp_hint'], 'google');
    expect(b.launched.single.queryParameters['code_challenge_method'], 'S256');
  });

  test('login por e-mail envia login_hint', () async {
    await boot();
    final b = build(callbackWithState);
    await b.auth.signInWithEmail('eu@x.com', 'ignored');
    expect(b.launched.single.queryParameters['login_hint'], 'eu@x.com');
  });

  test('cadastro abre a página de registrations do Keycloak', () async {
    await boot();
    final b = build(callbackWithState);
    await b.auth.signUp('Rodolfo', 'eu@x.com', 'ignored');
    expect(b.launched.single.path, contains('/registrations'));
  });

  test('state divergente falha (CSRF)', () async {
    await boot();
    final b = build(
      (url) async => const AuthCallback(code: 'code-1', state: 'ADULTERADO'),
    );
    await expectLater(
      b.auth.signInWithGoogle(),
      throwsA(isA<AuthException>()),
    );
    expect(b.auth.currentUser, isNull);
  });

  test('403 not_allowed → AuthException e sem sessão', () async {
    await boot();
    meStatus = 403;
    final b = build(callbackWithState);
    await expectLater(
      b.auth.signInWithGoogle(),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          contains('não tem acesso'),
        ),
      ),
    );
    expect(b.auth.currentUser, isNull);
  });
}

/// Placeholder para `server` antes do boot (tearDown tolera close()).
final LocalServer _unset = LocalServer(_NoopServer());

class _NoopServer implements HttpServer {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
