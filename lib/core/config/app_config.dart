enum Flavor { development, production }

/// Configuração do app.
///
/// Local-first por padrão em `development` (usa os fakes de Auth/Sync/IA) e
/// integrado com a `rbnotes-api` em `production`. Dá para forçar qualquer modo
/// via `--dart-define`:
///
/// ```sh
/// # dev apontando para o backend local:
/// fvm flutter run -d macos -t lib/main_development.dart \
///   --dart-define=RBNOTES_USE_BACKEND=true \
///   --dart-define=RBNOTES_API_BASE_URL=http://localhost:8080/v1
///
/// # build de produção:
/// fvm flutter build macos -t lib/main_production.dart \
///   --dart-define=SENTRY_DSN=https://...
/// ```
class AppConfig {
  const AppConfig({
    required this.environment,
    required this.sentryDsn,
    required this.useBackend,
    required this.apiBaseUrl,
    required this.authIssuer,
    required this.authClientId,
    required this.authRedirectUri,
  });

  factory AppConfig.forFlavor(Flavor flavor) {
    const defineUseBackend = String.fromEnvironment('RBNOTES_USE_BACKEND');
    final useBackend = defineUseBackend.isNotEmpty
        ? defineUseBackend == 'true'
        : flavor == Flavor.production;

    final defaultBase = flavor == Flavor.production
        ? 'https://api.notes.rodolfodebonis.com.br/v1'
        : 'http://localhost:8080/v1';

    return AppConfig(
      environment: flavor.name,
      sentryDsn: const String.fromEnvironment('SENTRY_DSN'),
      useBackend: useBackend,
      apiBaseUrl: const String.fromEnvironment(
        'RBNOTES_API_BASE_URL',
      ).ifEmpty(defaultBase),
      authIssuer: const String.fromEnvironment(
        'RBNOTES_AUTH_ISSUER',
        defaultValue: 'https://auth.rodolfodebonis.com.br/realms/rbnotes',
      ),
      authClientId: const String.fromEnvironment(
        'RBNOTES_AUTH_CLIENT_ID',
        defaultValue: 'rbnotes-desktop',
      ),
      authRedirectUri: const String.fromEnvironment(
        'RBNOTES_AUTH_REDIRECT_URI',
        defaultValue: 'http://127.0.0.1:53682/callback',
      ),
    );
  }

  final String environment;
  final String sentryDsn;

  /// Quando `true`, injeta os clientes reais (Keycloak + rbnotes-api) no lugar
  /// dos fakes locais.
  final bool useBackend;

  final String apiBaseUrl;
  final String authIssuer;
  final String authClientId;
  final String authRedirectUri;

  bool get hasSentry => sentryDsn.isNotEmpty;
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
