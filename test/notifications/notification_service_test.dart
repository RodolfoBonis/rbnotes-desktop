import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/notifications/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'scheduleReminder/cancelReminder degradam sem plugin (sem throw)',
    () async {
      final service = NotificationService();
      await expectLater(
        service.scheduleReminder(
          key: 'action-1',
          title: 'Lembrete de tarefa',
          body: 'Enviar a proposta',
          when: DateTime.now().add(const Duration(days: 1)),
        ),
        completes,
      );
      await expectLater(service.cancelReminder('action-1'), completes);
    },
  );
}
