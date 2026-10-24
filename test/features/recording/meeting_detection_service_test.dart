import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/features/recording/data/meeting_detection_service.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/native/fake_rb_native.dart';
import 'package:rbnotes/native/rb_native.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late FakeRbNative native;
  late SettingsStore settings;
  late MeetingDetectionService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    native = FakeRbNative();
    settings = SettingsStore(await SharedPreferences.getInstance());
    service = MeetingDetectionService(native: native, settings: settings);
  });

  tearDown(() async {
    await service.dispose();
    await native.dispose();
  });

  Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 20));

  MeetingSignal signal(
    String app, {
    required bool micInUse,
    int startedAtMs = 1000,
  }) => MeetingSignal(
    app: app,
    micInUse: micInUse,
    startedAt: DateTime.fromMillisecondsSinceEpoch(startedAtMs),
  );

  test('ligar a opção habilita a detecção nativa', () async {
    await settings.setAutoMeet(value: true);
    await service.applySettings();
    expect(native.meetingDetectionEnabled, isTrue);
    expect(native.lastSetMeetingDetection, isTrue);
  });

  test('desligar a opção desabilita a detecção', () async {
    await settings.setAutoMeet(value: true);
    await service.applySettings();
    await settings.setAutoMeet(value: false);
    await service.applySettings();
    expect(native.meetingDetectionEnabled, isFalse);
  });

  test('sugere uma vez por reunião ao detectar o microfone em uso', () async {
    await settings.setAutoMeet(value: true);
    await service.applySettings();
    final seen = <MeetingSuggestion>[];
    final sub = service.suggestions.listen(seen.add);

    native.emitMeetingSignal(signal('zoom.us', micInUse: true));
    await pump();
    native.emitMeetingSignal(signal('zoom.us', micInUse: true)); // repetida
    await pump();

    expect(seen, hasLength(1));
    expect(seen.single.app, 'zoom.us');
    await sub.cancel();
  });

  test('não sugere no fim da reunião (micInUse false)', () async {
    await settings.setAutoMeet(value: true);
    await service.applySettings();
    final seen = <MeetingSuggestion>[];
    final sub = service.suggestions.listen(seen.add);
    native.emitMeetingSignal(signal('Microsoft Teams', micInUse: false));
    await pump();
    expect(seen, isEmpty);
    await sub.cancel();
  });

  test('com o app travado, não sugere', () async {
    await settings.setAutoMeet(value: true);
    await service.applySettings();
    service.locked = true;
    final seen = <MeetingSuggestion>[];
    final sub = service.suggestions.listen(seen.add);
    native.emitMeetingSignal(signal('zoom.us', micInUse: true));
    await pump();
    expect(seen, isEmpty);
    await sub.cancel();
  });
}
