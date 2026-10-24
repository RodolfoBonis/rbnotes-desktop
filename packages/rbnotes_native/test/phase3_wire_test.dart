import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes_native/rbnotes_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel(RbNativeChannels.method);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late MethodChannelRbNative native;
  late List<MethodCall> calls;

  setUp(() {
    native = MethodChannelRbNative();
    calls = <MethodCall>[];
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  void handle({
    Object? response,
    Future<Object?> Function(MethodCall call)? onCall,
  }) {
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      if (onCall != null) return onCall(call);
      return response;
    });
  }

  group('recording Phase 3 options', () {
    test('startRecording forwards noiseReduction + language', () async {
      handle(response: {'id': 'n1', 'startedAtMs': 1700000000000});

      await native.startRecording(
        id: 'n1',
        directory: '/tmp',
        captureSystemAudio: false,
        noiseReduction: true,
        language: 'auto',
      );

      final args = calls.single.arguments as Map;
      expect(args['noiseReduction'], true);
      expect(args['language'], 'auto');
    });
  });

  group('lock triggers', () {
    test('lockTriggers decodes each known wire value', () async {
      messenger.setMockStreamHandler(
        const EventChannel(RbNativeChannels.lockTriggers),
        _ListStreamHandler(const [
          'screenLocked',
          'systemSleep',
          'screensaver',
        ]),
      );

      final events = await native.lockTriggers().take(3).toList();

      expect(events, const [
        LockTrigger.screenLocked,
        LockTrigger.systemSleep,
        LockTrigger.screensaver,
      ]);

      messenger.setMockStreamHandler(
        const EventChannel(RbNativeChannels.lockTriggers),
        null,
      );
    });

    test('lockTriggers surfaces an unknown value as invalid_event', () async {
      messenger.setMockStreamHandler(
        const EventChannel(RbNativeChannels.lockTriggers),
        _ListStreamHandler(const ['meteor']),
      );

      await expectLater(
        native.lockTriggers().first,
        throwsA(
          isA<RbNativeException>().having(
            (e) => e.code,
            'code',
            RbNativeErrorCode.invalidEvent,
          ),
        ),
      );

      messenger.setMockStreamHandler(
        const EventChannel(RbNativeChannels.lockTriggers),
        null,
      );
    });
  });

  group('login item', () {
    test('launchAtLogin returns the native bool', () async {
      handle(response: true);
      expect(await native.launchAtLogin(), isTrue);
      expect(calls.single.method, 'launchAtLogin');
    });

    test('setLaunchAtLogin serializes the flag', () async {
      handle();
      await native.setLaunchAtLogin(true);
      expect(calls.single.method, 'setLaunchAtLogin');
      expect(calls.single.arguments, {'enabled': true});
    });

    test('setLaunchAtLogin maps login_item_failed', () async {
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        throw PlatformException(
          code: RbNativeErrorCode.loginItemFailed,
          message: 'approve in System Settings',
        );
      });

      await expectLater(
        native.setLaunchAtLogin(true),
        throwsA(
          isA<RbNativeException>()
              .having((e) => e.code, 'code', RbNativeErrorCode.loginItemFailed)
              .having(
                (e) => e.message,
                'message',
                'approve in System Settings',
              ),
        ),
      );
    });
  });

  group('silence detection', () {
    test('detectSilences serializes args and parses ranges', () async {
      handle(
        response: [
          {'startMs': 1000, 'endMs': 3500},
          {'startMs': 8000, 'endMs': 11000},
        ],
      );

      final ranges = await native.detectSilences(
        '/tmp/a.wav',
        minSilence: const Duration(milliseconds: 1500),
      );

      expect(calls.single.method, 'detectSilences');
      expect(calls.single.arguments, {
        'wavPath': '/tmp/a.wav',
        'minSilenceMs': 1500,
      });
      expect(ranges, hasLength(2));
      expect(ranges.first.start, const Duration(seconds: 1));
      expect(ranges.first.end, const Duration(milliseconds: 3500));
      expect(ranges.first.duration, const Duration(milliseconds: 2500));
    });

    test('detectSilences defaults minSilence to 2 s', () async {
      handle(response: <Object?>[]);
      await native.detectSilences('/tmp/a.wav');
      expect((calls.single.arguments as Map)['minSilenceMs'], 2000);
    });
  });

  group('meeting detection', () {
    test('setMeetingDetection serializes the flag', () async {
      handle();
      await native.setMeetingDetection(true);
      expect(calls.single.method, 'setMeetingDetection');
      expect(calls.single.arguments, {'enabled': true});
    });

    test('meetingSignals parses start/stop events', () async {
      messenger.setMockStreamHandler(
        const EventChannel(RbNativeChannels.meetingSignals),
        _ListStreamHandler(const [
          {'app': 'zoom.us', 'micInUse': true, 'startedAtMs': 1700000000000},
          {'app': 'zoom.us', 'micInUse': false, 'startedAtMs': 1700000000000},
        ]),
      );

      final signals = await native.meetingSignals().take(2).toList();

      expect(signals.first.app, 'zoom.us');
      expect(signals.first.micInUse, isTrue);
      expect(
        signals.first.startedAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      expect(signals[1].micInUse, isFalse);

      messenger.setMockStreamHandler(
        const EventChannel(RbNativeChannels.meetingSignals),
        null,
      );
    });
  });

  group('diarization', () {
    test('diarizationModelState parses state', () async {
      handle(response: {'downloaded': true, 'sizeBytes': 12345});
      final state = await native.diarizationModelState();
      expect(calls.single.method, 'diarizationModelState');
      expect(state.downloaded, isTrue);
      expect(state.sizeBytes, 12345);
    });

    test('downloadDiarizationModel emits progress from the stream', () async {
      messenger.setMockStreamHandler(
        const EventChannel(RbNativeChannels.diarizationDownload),
        _ListStreamHandler(const [0.0, 0.5, 1.0]),
      );

      final progress = await native.downloadDiarizationModel().toList();
      expect(progress, [0.0, 0.5, 1.0]);

      messenger.setMockStreamHandler(
        const EventChannel(RbNativeChannels.diarizationDownload),
        null,
      );
    });

    test('diarize serializes args and parses turns', () async {
      handle(
        response: [
          {'startMs': 0, 'endMs': 2000, 'speaker': 0},
          {'startMs': 2000, 'endMs': 5000, 'speaker': 1},
        ],
      );

      final turns = await native.diarize('/tmp/system.wav', numSpeakers: 2);

      expect(calls.single.method, 'diarize');
      expect(calls.single.arguments, {
        'wavPath': '/tmp/system.wav',
        'numSpeakers': 2,
      });
      expect(turns, hasLength(2));
      expect(turns.first.speaker, 0);
      expect(turns[1].start, const Duration(seconds: 2));
      expect(turns[1].speaker, 1);
    });

    test('diarize maps diarization_model_missing', () async {
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        throw PlatformException(
          code: RbNativeErrorCode.diarizationModelMissing,
        );
      });

      await expectLater(
        native.diarize('/tmp/system.wav'),
        throwsA(
          isA<RbNativeException>().having(
            (e) => e.code,
            'code',
            RbNativeErrorCode.diarizationModelMissing,
          ),
        ),
      );
    });

    test('diarize passes null numSpeakers by default', () async {
      handle(response: <Object?>[]);
      await native.diarize('/tmp/system.wav');
      expect((calls.single.arguments as Map)['numSpeakers'], isNull);
    });
  });

  group('overlay accent', () {
    test('showActivityOverlay forwards accentArgb', () async {
      handle();
      await native.showActivityOverlay(
        mode: OverlayMode.recording,
        startedAt: DateTime.fromMillisecondsSinceEpoch(0),
        accentArgb: 0xFF2E7DE0,
      );
      expect((calls.single.arguments as Map)['accentArgb'], 0xFF2E7DE0);
    });

    test('showActivityOverlay defaults accentArgb to null', () async {
      handle();
      await native.showActivityOverlay(
        mode: OverlayMode.dictation,
        startedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      expect((calls.single.arguments as Map)['accentArgb'], isNull);
    });
  });
}

class _ListStreamHandler extends MockStreamHandler {
  _ListStreamHandler(this.events);

  final List<Object?> events;

  @override
  void onListen(Object? arguments, MockStreamHandlerEventSink sink) {
    for (final event in events) {
      sink.success(event);
    }
    sink.endOfStream();
  }

  @override
  void onCancel(Object? arguments) {}
}
