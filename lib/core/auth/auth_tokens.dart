import 'package:equatable/equatable.dart';

/// Conjunto de tokens do Keycloak guardado no Keychain.
///
/// O refresh **rotaciona** (`revoke_refresh_token` no realm): toda renovação
/// devolve um novo `refreshToken`, que precisa substituir o anterior.
class AuthTokens extends Equatable {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    this.idToken,
    this.accessExpiry,
  });

  final String accessToken;
  final String refreshToken;

  /// `id_token` do OIDC (usado no `id_token_hint` do logout).
  final String? idToken;

  /// Quando o access token expira (para refresh proativo, opcional).
  final DateTime? accessExpiry;

  bool get hasRefresh => refreshToken.isNotEmpty;

  AuthTokens copyWith({
    String? accessToken,
    String? refreshToken,
    String? idToken,
    DateTime? accessExpiry,
  }) => AuthTokens(
    accessToken: accessToken ?? this.accessToken,
    refreshToken: refreshToken ?? this.refreshToken,
    idToken: idToken ?? this.idToken,
    accessExpiry: accessExpiry ?? this.accessExpiry,
  );

  @override
  List<Object?> get props => [accessToken, refreshToken, idToken, accessExpiry];
}
