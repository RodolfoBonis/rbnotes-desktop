enum Flavor { development, production }

/// Configuração do app. Local-first: sem URLs de API.
///
/// ```sh
/// fvm flutter run -d macos -t lib/main_development.dart
/// fvm flutter build macos -t lib/main_production.dart \
///   --dart-define=SENTRY_DSN=https://...
/// ```
class AppConfig {
  const AppConfig({required this.environment, required this.sentryDsn});

  factory AppConfig.forFlavor(Flavor flavor) => AppConfig(
    environment: flavor.name,
    sentryDsn: const String.fromEnvironment('SENTRY_DSN'),
  );

  final String environment;
  final String sentryDsn;

  bool get hasSentry => sentryDsn.isNotEmpty;
}
