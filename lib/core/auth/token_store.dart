import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:rbnotes/core/auth/auth_tokens.dart';

/// Persistência dos tokens do Keycloak.
abstract interface class TokenStore {
  Future<AuthTokens?> read();
  Future<void> write(AuthTokens tokens);
  Future<void> clear();
}

/// Keychain do macOS. Usa o keychain legado (`usesDataProtectionKeychain:
/// false`) para funcionar em builds sem time de assinatura (o Data Protection
/// Keychain exige `keychain-access-groups`), seguindo o SpoolIQ.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            mOptions: MacOsOptions(useDataProtectionKeyChain: false),
          );

  final FlutterSecureStorage _storage;

  static const _accessKey = 'rbnotes.access_token';
  static const _refreshKey = 'rbnotes.refresh_token';
  static const _idKey = 'rbnotes.id_token';
  static const _expiryKey = 'rbnotes.access_expiry';

  AuthTokens? _cache;

  @override
  Future<AuthTokens?> read() async {
    if (_cache != null) return _cache;
    final access = await _storage.read(key: _accessKey);
    if (access == null || access.isEmpty) return null;
    final refresh = await _storage.read(key: _refreshKey);
    final id = await _storage.read(key: _idKey);
    final expiryRaw = await _storage.read(key: _expiryKey);
    return _cache = AuthTokens(
      accessToken: access,
      refreshToken: refresh ?? '',
      idToken: id,
      accessExpiry: expiryRaw == null ? null : DateTime.tryParse(expiryRaw),
    );
  }

  @override
  Future<void> write(AuthTokens tokens) async {
    _cache = tokens;
    await _storage.write(key: _accessKey, value: tokens.accessToken);
    await _storage.write(key: _refreshKey, value: tokens.refreshToken);
    if (tokens.idToken != null) {
      await _storage.write(key: _idKey, value: tokens.idToken);
    }
    if (tokens.accessExpiry != null) {
      await _storage.write(
        key: _expiryKey,
        value: tokens.accessExpiry!.toIso8601String(),
      );
    }
  }

  @override
  Future<void> clear() async {
    _cache = null;
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _idKey);
    await _storage.delete(key: _expiryKey);
  }
}

/// Implementação em memória para testes.
class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this.tokens]);

  AuthTokens? tokens;

  @override
  Future<void> clear() async => tokens = null;

  @override
  Future<AuthTokens?> read() async => tokens;

  @override
  Future<void> write(AuthTokens tokens) async => this.tokens = tokens;
}
