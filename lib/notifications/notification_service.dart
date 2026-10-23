import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_auth/local_auth.dart';
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

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
      _initTimeZone();
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

  /// Inicializa o fuso para agendar notificações. Sem o nome IANA (sem plugin
  /// de timezone nativo), usamos um fuso de offset fixo (`Etc/GMT±N`) que bate
  /// com o offset atual do sistema — suficiente para lembretes "amanhã às 9h".
  void _initTimeZone() {
    try {
      tzdata.initializeTimeZones();
      final offset = DateTime.now().timeZoneOffset.inHours;
      // Etc/GMT tem o sinal invertido: UTC-3 => 'Etc/GMT+3'.
      final name = offset == 0
          ? 'UTC'
          : 'Etc/GMT${offset < 0 ? '+' : '-'}${offset.abs()}';
      tz.setLocalLocation(tz.getLocation(name));
    } on Object {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
  }

  /// Agenda um lembrete local para [when] (ex.: "Lembrar amanhã às 9h"). [key]
  /// é a chave estável da tarefa (deriva o id numérico); re-agendar com a mesma
  /// chave substitui o anterior.
  Future<void> scheduleReminder({
    required String key,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    try {
      if (!_initialized) await init();
      await _plugin.zonedSchedule(
        _idFor(key),
        title,
        body,
        tz.TZDateTime.from(when, tz.local),
        const NotificationDetails(macOS: DarwinNotificationDetails()),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } on Object catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'schedule_reminder',
        category: 'notifications',
      );
    }
  }

  /// Cancela um lembrete agendado (tarefa concluída/descartada).
  Future<void> cancelReminder(String key) async {
    try {
      await _plugin.cancel(_idFor(key));
    } on Object catch (_) {
      // sem plugin em teste; ignore.
    }
  }

  /// Id numérico estável (31 bits) a partir de uma chave de string.
  int _idFor(String key) {
    var hash = 0;
    for (final code in key.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return hash;
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
