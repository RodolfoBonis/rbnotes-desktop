import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/core/auth/auth_tokens.dart';
import 'package:rbnotes/core/auth/oidc_client.dart';
import 'package:rbnotes/core/auth/token_store.dart';
import 'package:rbnotes/core/network/api_client.dart';
import 'package:rbnotes/core/network/api_error.dart';
import 'package:rbnotes/core/network/session_events.dart';

import '../../helpers/local_server.dart';

void main() {
  late LocalServer server;
  var refreshCalls = 0;

  setUp(() {
    // O binding do flutter_test bloqueia HTTP real (devolve 400); liberamos
    // para falar com o LocalServer de loopback.
    HttpOverrides.global = null;
    refreshCalls = 0;
  });

  tearDown(() async {
    await server.close();
  });

  Future<void> boot(FutureOr<void> Function(HttpRequest) handler) async {
    server = await LocalServer.start(handler);
  }

  OidcClient oidcFor() => OidcClient(
    dio: Dio(),
    issuer: '${server.base}/realms/rbnotes',
    clientId: 'rbnotes-desktop',
    redirectUri: 'http://127.0.0.1:53682/callback',
  );

  Future<void> writeJson(HttpRequest req, int status, Object body) async {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType('application', 'problem+json')
      ..write(jsonEncode(body));
    await req.response.close();
  }

  test('problem+json 403 not_allowed → ApiError + AccessRevoked', () async {
    await boot((req) => writeJson(req, 403, {'code': 'not_allowed'}));
    final events = SessionEvents();
    final captured = <SessionEvent>[];
    final sub = events.stream.listen(captured.add);
    final api = ApiClient(
      baseUrl: '${server.base}/v1',
      tokens: MemoryTokenStore(
        const AuthTokens(accessToken: 'a', refreshToken: 'r'),
      ),
      oidc: oidcFor(),
      events: events,
    );
    try {
      await api.getJson('/me');
      fail('deveria lançar');
    } on ApiError catch (e) {
      expect(e.isAccessDenied, isTrue);
    }
    await Future<void>.delayed(Duration.zero);
    expect(captured.whereType<AccessRevoked>(), isNotEmpty);
    await sub.cancel();
  });

  test('500 → ApiError.isServer; 422 → fieldErrors', () async {
    await boot((req) {
      if (req.uri.path == '/v1/boom') {
        return writeJson(req, 500, {'title': 'kaput'});
      }
      return writeJson(req, 422, {
        'errors': [
          {'field': 'month', 'code': 'invalid'},
        ],
      });
    });
    final api = ApiClient(
      baseUrl: '${server.base}/v1',
      tokens: MemoryTokenStore(
        const AuthTokens(accessToken: 'a', refreshToken: 'r'),
      ),
      oidc: oidcFor(),
      events: SessionEvents(),
    );
    await expectLater(
      api.getJson('/boom'),
      throwsA(isA<ApiError>().having((e) => e.isServer, 'isServer', true)),
    );
    try {
      await api.getJson('/validate');
      fail('deveria lançar');
    } on ApiError catch (e) {
      expect(e.statusCode, 422);
      expect(e.fieldErrors.single.field, 'month');
    }
  });

  test('putBytes envia Content-Length; getBytes trata Range (206)', () async {
    int? sentLength;
    await boot((req) async {
      if (req.method == 'PUT') {
        sentLength = req.contentLength;
        await req.drain<void>();
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType('application', 'json')
          ..write(jsonEncode({'part': 1, 'completed': true}));
        return req.response.close();
      }
      // GET com Range
      final range = req.headers.value('range');
      req.response
        ..statusCode = range == null ? 200 : 206
        ..headers.set('accept-ranges', 'bytes');
      if (range != null) {
        req.response.headers.set('content-range', 'bytes 0-3/10');
      }
      req.response.add([1, 2, 3, 4]);
      return req.response.close();
    });
    final api = ApiClient(
      baseUrl: '${server.base}/v1',
      tokens: MemoryTokenStore(
        const AuthTokens(accessToken: 'a', refreshToken: 'r'),
      ),
      oidc: oidcFor(),
      events: SessionEvents(),
    );
    final put = await api.putBytes(
      '/notes/n1/audio',
      bytes: List<int>.filled(1024, 7),
      query: {'part': 1, 'total': 1},
    );
    expect(put['completed'], true);
    expect(sentLength, 1024);

    final got = await api.getBytes('/notes/n1/audio', rangeStart: 0);
    expect(got.statusCode, 206);
    expect(got.totalLength, 10);
    expect(got.bytes, [1, 2, 3, 4]);
  });

  test(
    'refresh single-flight com rotação: um refresh, novo par salvo',
    () async {
      await boot((req) async {
        final path = req.uri.path;
        if (path.endsWith('/.well-known/openid-configuration')) {
          return writeJson(req, 200, {
            'issuer': '${server.base}/realms/rbnotes',
            'authorization_endpoint': '${server.base}/auth',
            'token_endpoint': '${server.base}/token',
            'end_session_endpoint': '${server.base}/logout',
          });
        }
        if (path == '/token') {
          refreshCalls++;
          await req.drain<void>();
          req.response
            ..statusCode = 200
            ..headers.contentType = ContentType('application', 'json')
            ..write(
              jsonEncode({
                'access_token': 'access-2',
                'refresh_token': 'refresh-2',
                'expires_in': 300,
              }),
            );
          return req.response.close();
        }
        // /v1/me: só aceita o token rotacionado.
        final auth = req.headers.value('authorization');
        if (auth == 'Bearer access-2') {
          req.response
            ..statusCode = 200
            ..headers.contentType = ContentType('application', 'json')
            ..write(jsonEncode({'id': 'u', 'email': 'e@x', 'name': 'Eu'}));
          return req.response.close();
        }
        return writeJson(req, 401, {'code': 'unauthorized'});
      });

      final tokens = MemoryTokenStore(
        const AuthTokens(accessToken: 'access-1', refreshToken: 'refresh-1'),
      );
      final api = ApiClient(
        baseUrl: '${server.base}/v1',
        tokens: tokens,
        oidc: oidcFor(),
        events: SessionEvents(),
      );

      // Duas requisições concorrentes que recebem 401 ao mesmo tempo.
      final results = await Future.wait([
        api.getJson('/me'),
        api.getJson('/me'),
      ]);
      expect(results.every((r) => r['name'] == 'Eu'), isTrue);
      expect(refreshCalls, 1, reason: 'single-flight: só um refresh');
      final stored = await tokens.read();
      expect(stored?.accessToken, 'access-2');
      expect(stored?.refreshToken, 'refresh-2'); // rotação persistida
    },
  );
}
