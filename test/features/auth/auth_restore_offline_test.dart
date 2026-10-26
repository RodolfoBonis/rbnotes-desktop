import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/core/auth/auth_tokens.dart';
import 'package:rbnotes/core/auth/oidc_client.dart';
import 'package:rbnotes/core/auth/token_store.dart';
import 'package:rbnotes/core/network/api_client.dart';
import 'package:rbnotes/core/network/session_events.dart';
import 'package:rbnotes/features/auth/data/keycloak_auth_service.dart';

String _jwt(Map<String, Object?> claims) {
  String part(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part(claims)}.sig';
}

/// Regressão: sem rede no boot (DNS do servidor fora), o app mostrava o login
/// apesar de a sessão salva continuar válida.
void main() {
  // Porta fechada: toda chamada falha sem resposta HTTP (como DNS/offline).
  const unreachable = 'http://127.0.0.1:9';

  KeycloakAuthService build(MemoryTokenStore tokens) {
    final oidc = OidcClient(
      dio: Dio(),
      issuer: '$unreachable/realms/rbnotes',
      clientId: 'rbnotes-desktop',
      redirectUri: 'http://127.0.0.1:53682/callback',
    );
    final events = SessionEvents();
    return KeycloakAuthService(
      oidc: oidc,
      tokens: tokens,
      api: ApiClient(
        baseUrl: '$unreachable/v1',
        tokens: tokens,
        oidc: oidc,
        events: events,
      ),
      events: events,
    );
  }

  test('sem rede no boot entra com a sessão salva (id_token)', () async {
    final tokens = MemoryTokenStore()
      ..tokens = AuthTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
        idToken: _jwt({
          'sub': 'kc-1',
          'email': 'dev@rodolfodebonis.com.br',
          'name': 'Rodolfo',
        }),
        accessExpiry: DateTime.now().add(const Duration(minutes: 5)),
      );
    final auth = build(tokens);

    await auth.restore();

    expect(auth.currentUser?.email, 'dev@rodolfodebonis.com.br');
    expect(auth.currentUser?.name, 'Rodolfo');
    expect(tokens.tokens, isNotNull, reason: 'tokens nunca apagados por rede');
  });

  test('sem rede e sem id_token continua deslogado, sem apagar', () async {
    final tokens = MemoryTokenStore()
      ..tokens = AuthTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
        accessExpiry: DateTime.now().add(const Duration(minutes: 5)),
      );
    final auth = build(tokens);

    await auth.restore();

    expect(auth.currentUser, isNull);
    expect(tokens.tokens, isNotNull);
  });
}
