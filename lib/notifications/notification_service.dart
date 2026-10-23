import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_auth/local_auth.dart';
import 'package:rbnotes/core/observability/app_logger.dart';

/// Notificações locais (lembretes de tarefas e do diário) e autenticação
/// biométrica (Touch ID) para o Diário. Tudo é tolerante a falhas: num ambiente
/// sem os plugins (testes) os métodos degradam sem derrubar o app.
class NotificationService {
  NotificationService({
    FlutterLocalNotificationsPlugin? plugin,
    LocalAuthentication? localAuth,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _localAuth = localAuth ?? LocalAuthentication();

  final FlutterLocalNotificationsPlugin _plugin;
  final LocalAuthentication _localAuth;
  var _initialized = false;

  Future<void> init() async {
    try {
      await _plugin.initialize(
        const InitializationSettings(
          macOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      _initialized = true;
    } on Object catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'notifications_init',
        category: 'notifications',
      );
    }
  }

  /// Pede permissão de notificações (onboarding). Retorna se foi concedida.
  Future<bool> requestPermission() async {
    try {
      if (!_initialized) await init();
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? false;
    } on Object catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'notifications_permission',
        category: 'notifications',
      );
      return false;
    }
  }

  /// Autentica com Touch ID (desbloqueio do Diário).
  Future<bool> authenticateBiometric() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Desbloqueie seu diário',
        options: const AuthenticationOptions(biometricOnly: true),
      );
    } on Object catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'touch_id',
        category: 'notifications',
      );
      return false;
    }
  }
}
