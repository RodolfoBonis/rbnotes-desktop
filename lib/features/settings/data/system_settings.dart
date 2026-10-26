import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/native/rb_native.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abre os painéis de Privacidade das Ajustes do Sistema (macOS) para a
/// permissão certa, num ponto único e testável (o abridor de URL é injetável).
///
/// Usado quando o microfone/gravação de tela/acessibilidade estão negados —
/// cenário comum depois que o app mudou de assinatura (Apple Development em vez
/// de ad-hoc) e o TCC antigo deixou de valer.
class SystemSettingsOpener {
  const SystemSettingsOpener({
    Future<bool> Function(Uri uri)? launcher,
  }) : _launch = launcher ?? launchUrl;

  final Future<bool> Function(Uri uri) _launch;

  /// Esquema `x-apple.systempreferences:` para cada painel de Privacidade.
  static const _urls = <RbPermission, String>{
    RbPermission.microphone:
        'x-apple.systempreferences:com.apple.preference.security'
        '?Privacy_Microphone',
    RbPermission.screenRecording:
        'x-apple.systempreferences:com.apple.preference.security'
        '?Privacy_ScreenCapture',
    RbPermission.accessibility:
        'x-apple.systempreferences:com.apple.preference.security'
        '?Privacy_Accessibility',
  };

  /// A URL do painel de Privacidade para [permission].
  static String urlFor(RbPermission permission) => _urls[permission]!;

  /// Abre o painel de Privacidade de [permission]. Erros são registrados e
  /// engolidos (abrir Ajustes nunca deve derrubar o fluxo de gravação).
  Future<void> openPrivacyPane(RbPermission permission) async {
    try {
      await _launch(Uri.parse(urlFor(permission)));
    } on Object catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'open_privacy_pane',
        category: 'settings',
      );
    }
  }
}
