import 'dart:async';

import 'package:dio/dio.dart';
import 'package:rbnotes/core/auth/auth_tokens.dart';
import 'package:rbnotes/core/auth/oidc_client.dart';
import 'package:rbnotes/core/auth/token_store.dart';
import 'package:rbnotes/core/network/session_events.dart';
import 'package:rbnotes/core/observability/app_logger.dart';

/// Chave em `RequestOptions.extra` para requisições públicas (sem Bearer).
const kSkipAuth = 'skip_auth';
const _kRetried = 'auth_retried';

/// Anexa o Bearer do access token e, em `401`, tenta **um** refresh contra
/// o token endpoint do Keycloak.
///
/// - **Single-flight**: vários 401 concorrentes aguardam a mesma renovação.
/// - **Rotação**: o realm rotaciona o refresh; sempre salvamos o novo par.
/// - `403 not_allowed`: emite [AccessRevoked] (conta fora da allowlist).
/// - Refresh impossível/falho: limpa os tokens e emite [SessionExpired].
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required TokenStore tokens,
    required OidcClient oidc,
    required SessionEvents events,
    required Dio retryDio,
  }) : _tokens = tokens,
       _oidc = oidc,
       _events = events,
       _retryDio = retryDio;

  final TokenStore _tokens;
  final OidcClient _oidc;
  final SessionEvents _events;
  final Dio _retryDio;

  Future<AuthTokens?>? _refreshing;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra[kSkipAuth] != true) {
      final tokens = await _tokens.read();
      if (tokens != null) {
        options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    final options = err.requestOptions;
    final status = response?.statusCode;

    if (status == 403) {
      final data = response?.data;
      final code = data is Map ? data['code']?.toString() : null;
      if (code == 'not_allowed') _events.emit(const AccessRevoked());
      return handler.next(err);
    }

    final canRefresh =
        status == 401 &&
        options.extra[kSkipAuth] != true &&
        options.extra[_kRetried] != true;
    if (!canRefresh) return handler.next(err);

    final refreshed = await _refreshOnce();
    if (refreshed == null) {
      _events.emit(const SessionExpired());
      return handler.next(err);
    }

    try {
      options
        ..extra[_kRetried] = true
        ..headers['Authorization'] = 'Bearer ${refreshed.accessToken}';
      final retry = await _retryDio.fetch<dynamic>(options);
      return handler.resolve(retry);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await _tokens.clear();
        _events.emit(const SessionExpired());
      }
      return handler.next(e);
    }
  }

  Future<AuthTokens?> _refreshOnce() {
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<AuthTokens?> _refresh() async {
    final current = await _tokens.read();
    if (current == null || !current.hasRefresh) return null;
    try {
      final next = await _oidc.refresh(current.refreshToken);
      // Rotação: preserva o refresh anterior só se o provider não devolver um
      // novo (não deveria acontecer com revoke_refresh_token ligado).
      final rotated = next.refreshToken.isEmpty
          ? next.copyWith(refreshToken: current.refreshToken)
          : next;
      await _tokens.write(rotated);
      AppLogger.info('Sessão renovada', category: 'auth');
      return rotated;
    } on Object catch (e) {
      AppLogger.warning('Falha ao renovar sessão', category: 'auth', error: e);
      await _tokens.clear();
      return null;
    }
  }
}
