import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// As quatro notificações do RbNotes (Fase 3).
enum NotificationKind {
  noteReady,
  taskDue,
  diaryPrompt,
  weeklySummary,
  meetingSuggestion,
}

/// Payload de uma notificação: para onde o toque leva.
class AppNotification {
  const AppNotification({required this.kind, this.noteId, this.date});

  factory AppNotification.fromPayload(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return AppNotification(
        kind: NotificationKind.values.firstWhere(
          (k) => k.name == map['kind'],
          orElse: () => NotificationKind.noteReady,
        ),
        noteId: map['noteId'] as String?,
        date: map['date'] as String?,
      );
    } on Object {
      return const AppNotification(kind: NotificationKind.noteReady);
    }
  }

  final NotificationKind kind;

  /// Nota a abrir (nota pronta / tarefa).
  final String? noteId;

  /// Data relevante (diário: a pergunta do dia; semana: weekStart).
  final String? date;

  String toPayload() => jsonEncode({
    'kind': kind.name,
    if (noteId != null) 'noteId': noteId,
    if (date != null) 'date': date,
  });
}

/// Abstração de notificações locais (agendar, mostrar, cancelar) com os toques
/// num stream. A implementação real usa `flutter_local_notifications`; os
/// testes usam [FakeNotifier] para verificar o agendamento.
abstract interface class Notifier {
  Future<void> init();
  Future<bool> requestPermission();

  /// Status atual da permissão (null = desconhecido).
  Future<bool?> isPermissionGranted();

  /// Mostra uma notificação imediata.
  Future<void> show({
    required String id,
    required String title,
    required String body,
    required AppNotification payload,
  });

  /// Agenda uma notificação para [when] (substitui a de mesmo [id]).
  Future<void> schedule({
    required String id,
    required DateTime when,
    required String title,
    required String body,
    required AppNotification payload,
  });

  Future<void> cancel(String id);
  Future<void> cancelAll();

  /// Toques nas notificações (payload decodificado).
  Stream<AppNotification> get taps;
}

/// Implementação real sobre `flutter_local_notifications` + `flutter_timezone`
/// (fuso IANA de verdade, respeitando horário de verão). Tolerante a falhas:
/// num ambiente sem os plugins, degrada sem derrubar o app.
class LocalNotifier implements Notifier {
  LocalNotifier({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final _taps = StreamController<AppNotification>.broadcast();
  var _initialized = false;

  @override
  Stream<AppNotification> get taps => _taps.stream;

  @override
  Future<void> init() async {
    if (_initialized) return;
    try {
      await _initTimeZone();
      await _plugin.initialize(
        const InitializationSettings(
          macOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) {
            _taps.add(AppNotification.fromPayload(payload));
          }
        },
      );
      // Toque que abriu o app estando fechado.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      if ((launch?.didNotificationLaunchApp ?? false) &&
          payload != null &&
          payload.isNotEmpty) {
        _taps.add(AppNotification.fromPayload(payload));
      }
      _initialized = true;
    } on Object catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'notifier_init',
        category: 'notifications',
      );
    }
  }

  Future<void> _initTimeZone() async {
    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } on Object {
      // Fallback: offset fixo que bate com o sistema.
      final offset = DateTime.now().timeZoneOffset.inHours;
      final name = offset == 0
          ? 'UTC'
          : 'Etc/GMT${offset < 0 ? '+' : '-'}${offset.abs()}';
      try {
        tz.setLocalLocation(tz.getLocation(name));
      } on Object {
        tz.setLocalLocation(tz.getLocation('UTC'));
      }
    }
  }

  @override
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
        reason: 'notifier_permission',
        category: 'notifications',
      );
      return false;
    }
  }

  @override
  Future<bool?> isPermissionGranted() async {
    try {
      if (!_initialized) await init();
      return await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.checkPermissions()
          .then((p) => p?.isEnabled);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> show({
    required String id,
    required String title,
    required String body,
    required AppNotification payload,
  }) async {
    try {
      if (!_initialized) await init();
      await _plugin.show(
        _idFor(id),
        title,
        body,
        const NotificationDetails(macOS: DarwinNotificationDetails()),
        payload: payload.toPayload(),
      );
    } on Object catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'notifier_show',
        category: 'notifications',
      );
    }
  }

  @override
  Future<void> schedule({
    required String id,
    required DateTime when,
    required String title,
    required String body,
    required AppNotification payload,
  }) async {
    try {
      if (!_initialized) await init();
      await _plugin.zonedSchedule(
        _idFor(id),
        title,
        body,
        tz.TZDateTime.from(when, tz.local),
        const NotificationDetails(macOS: DarwinNotificationDetails()),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload.toPayload(),
      );
    } on Object catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'notifier_schedule',
        category: 'notifications',
      );
    }
  }

  @override
  Future<void> cancel(String id) async {
    try {
      await _plugin.cancel(_idFor(id));
    } on Object catch (_) {
      // sem plugin em teste; ignore.
    }
  }

  @override
  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } on Object catch (_) {}
  }

  /// Id numérico estável (31 bits) a partir de uma chave de string.
  static int _idFor(String key) {
    var hash = 0;
    for (final code in key.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return hash;
  }

  Future<void> dispose() => _taps.close();
}

/// Notifier em memória para testes: registra o que foi agendado/mostrado.
class FakeNotifier implements Notifier {
  bool permissionGranted = true;
  final List<ScheduledNotification> scheduled = [];
  final List<ScheduledNotification> shown = [];
  final List<String> cancelled = [];
  int cancelAllCount = 0;
  final _taps = StreamController<AppNotification>.broadcast();

  @override
  Stream<AppNotification> get taps => _taps.stream;

  void emitTap(AppNotification n) => _taps.add(n);

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<bool?> isPermissionGranted() async => permissionGranted;

  @override
  Future<void> show({
    required String id,
    required String title,
    required String body,
    required AppNotification payload,
  }) async {
    shown.add(
      ScheduledNotification(
        id: id,
        title: title,
        body: body,
        payload: payload,
      ),
    );
  }

  @override
  Future<void> schedule({
    required String id,
    required DateTime when,
    required String title,
    required String body,
    required AppNotification payload,
  }) async {
    scheduled
      ..removeWhere((s) => s.id == id)
      ..add(
        ScheduledNotification(
          id: id,
          title: title,
          body: body,
          payload: payload,
          when: when,
        ),
      );
  }

  @override
  Future<void> cancel(String id) async {
    cancelled.add(id);
    scheduled.removeWhere((s) => s.id == id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCount++;
    scheduled.clear();
  }

  ScheduledNotification? scheduledFor(String id) {
    for (final s in scheduled) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> dispose() => _taps.close();
}

class ScheduledNotification {
  const ScheduledNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
    this.when,
  });

  final String id;
  final String title;
  final String body;
  final AppNotification payload;
  final DateTime? when;
}
