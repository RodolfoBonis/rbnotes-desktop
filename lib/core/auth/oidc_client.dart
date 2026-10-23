import 'package:dio/dio.dart';
import 'package:rbnotes/core/auth/auth_tokens.dart';
import 'package:rbnotes/core/auth/pkce.dart';

/// Endpoints OIDC resolvidos pelo discovery do realm.
class OidcEndpoints {
  const OidcEndpoints({
    required this.issuer,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    this.endSessionEndpoint,
  });

  factory OidcEndpoints.fromJson(Map<String, dynamic> j) => OidcEndpoints(
    issuer: j['issuer'] as String,
    authorizationEndpoint: j['authorization_endpoint'] as String,
    tokenEndpoint: j['token_endpoint'] as String,
    endSessionEndpoint: j['end_session_endpoint'] as String?,
  );

  final String issuer;
  final String authorizationEndpoint;
  final String tokenEndpoint;
  final String? endSessionEndpoint;
}

/// Erro de autenticação OIDC (discovery, troca de código, refresh).
class OidcException implements Exception {
  const OidcException(this.message, {this.isNetwork = false});
  final String message;

  /// Falha de transporte (sem resposta HTTP): offline/timeout. O chamador deve
  /// tratar como transitória — nunca encerrar a sessão por causa dela.
  final bool isNetwork;

  @override
  String toString() => 'OidcException: $message';
}

/// Cliente OIDC enxuto para o fluxo Authorization Code + PKCE (S256) contra o
/// realm Keycloak `rbnotes`. Faz discovery, monta a URL de autorização, troca o
/// código por tokens e renova (com rotação do refresh token). Só lógica de
/// protocolo — a abertura do navegador e o loopback ficam no AuthService.
class OidcClient {
  OidcClient({
    required Dio dio,
    required this.issuer,
    required this.clientId,
    required this.redirectUri,
    this.scopes = const ['openid', 'profile', 'email', 'offline_access'],
  }) : _dio = dio;

  final Dio _dio;
  final String issuer;
  final String clientId;
  final String redirectUri;
  final List<String> scopes;

  OidcEndpoints? _endpoints;

  /// Resolve (e memoiza) os endpoints via `.well-known/openid-configuration`.
  Future<OidcEndpoints> discover() async {
    if (_endpoints != null) return _endpoints!;
    final url =
        '${issuer.replaceAll(RegExp(r'/$'), '')}'
        '/.well-known/openid-configuration';
    try {
      final res = await _dio.get<Map<String, dynamic>>(url);
      final data = res.data;
      if (data == null) throw const OidcException('Discovery vazio.');
      return _endpoints = OidcEndpoints.fromJson(data);
    } on DioException catch (e) {
      throw OidcException(
        'Falha no discovery OIDC: ${e.message}',
        isNetwork: e.response == null,
      );
    }
  }

  /// URL de autorização para abrir no navegador. [idpHint] = `kc_idp_hint`
  /// (ex.: `google`); [loginHint] prefill do e-mail; [prompt]/[kcAction] extras.
  Future<Uri> authorizationUrl(
    PkcePair pkce, {
    String? idpHint,
    String? loginHint,
    String? prompt,
    String? kcAction,
  }) async {
    final ep = await discover();
    final params = <String, String>{
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': scopes.join(' '),
      'state': pkce.state,
      'nonce': pkce.nonce,
      'code_challenge': pkce.codeChallenge,
      'code_challenge_method': 'S256',
      'kc_idp_hint': ?idpHint,
      if (loginHint != null && loginHint.isNotEmpty) 'login_hint': loginHint,
      'prompt': ?prompt,
      'kc_action': ?kcAction,
    };
    return Uri.parse(ep.authorizationEndpoint).replace(queryParameters: params);
  }

  /// Troca o `code` do callback pelos tokens.
  Future<AuthTokens> exchangeCode({
    required String code,
    required String codeVerifier,
  }) {
    return _token({
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri,
      'client_id': clientId,
      'code_verifier': codeVerifier,
    });
  }

  /// Renova os tokens. O realm rotaciona o refresh token
  /// (`revoke_refresh_token`), então o resultado traz um novo refresh.
  Future<AuthTokens> refresh(String refreshToken) {
    return _token({
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'client_id': clientId,
    });
  }

  /// URL de `end_session` para logout (abre no navegador). Null se o provider
  /// não anuncia `end_session_endpoint`.
  Future<Uri?> endSessionUrl({
    String? idToken,
    String? postLogoutRedirect,
  }) async {
    final ep = await discover();
    final endpoint = ep.endSessionEndpoint;
    if (endpoint == null) return null;
    return Uri.parse(endpoint).replace(
      queryParameters: {
        'client_id': clientId,
        'id_token_hint': ?idToken,
        'post_logout_redirect_uri': ?postLogoutRedirect,
      },
    );
  }

  Future<AuthTokens> _token(Map<String, String> form) async {
    final ep = await discover();
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        ep.tokenEndpoint,
        data: form,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );
      final data = res.data;
      if (data == null) throw const OidcException('Token endpoint vazio.');
      final access = data['access_token'] as String?;
      if (access == null || access.isEmpty) {
        throw const OidcException('Resposta sem access_token.');
      }
      final expiresIn = (data['expires_in'] as num?)?.toInt();
      return AuthTokens(
        accessToken: access,
        refreshToken: (data['refresh_token'] as String?) ?? '',
        idToken: data['id_token'] as String?,
        accessExpiry: expiresIn == null
            ? null
            : DateTime.now().add(Duration(seconds: expiresIn)),
      );
    } on DioException catch (e) {
      final body = e.response?.data;
      final desc = body is Map<String, dynamic>
          ? (body['error_description'] ?? body['error'])?.toString()
          : null;
      throw OidcException(
        desc ?? 'Falha ao obter tokens: ${e.message}',
        isNetwork: e.response == null,
      );
    }
  }
}
