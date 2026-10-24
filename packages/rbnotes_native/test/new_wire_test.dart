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

  group('recording with new options', () {
    test('startRecording forwards liveTranscription + inputDeviceId', () async {
      handle(response: {'id': 'n1', 'startedAtMs': 1700000000000});

      await native.startRecording(
        id: 'n1',
        directory: '/tmp',
        captureSystemAudio: false,
        liveTranscription: true,
        inputDeviceId: 'device-uid-42',
      );

      expect(calls.single.arguments, {
        'id': 'n1',
        'directory': '/tmp',
        'captureSystemAudio': false,
        'liveTranscription': true,
        'inputDeviceId': 'device-uid-42',
      });
    });

    test(
      'startRecording defaults liveTranscription false, device null',
      () async {
        handle(response: {'id': 'n2', 'startedAtMs': 1700000000000});

        await native.startRecording(
          id: 'n2',
          directory: '/tmp',
          captureSystemAudio: true,
        );

        final args = calls.single.arguments as Map;
        expect(args['liveTranscription'], false);
        expect(args['inputDeviceId'], isNull);
      },
    );
  });

  group('input devices', () {
    test('inputDevices parses the list', () async {
      handle(
        response: [
          {'id': 'uid-1', 'name': 'Built-in', 'isDefault': true},
          {'id': 'uid-2', 'name': 'USB Mic', 'isDefault': false},
        ],
      );

      final devices = await native.inputDevices();

      expect(calls.single.method, 'inputDevices');
      expect(devices, hasLength(2));
      expect(devices.first.id, 'uid-1');
      expect(devices.first.name, 'Built-in');
      expect(devices.first.isDefault, isTrue);
      expect(devices[1].isDefault, isFalse);
    });
  });

  group('waveform peaks', () {
    test('waveformPeaks serializes args and parses doubles', () async {
      handle(response: <Object?>[0.0, 0.5, 1.0]);

      final peaks = await native.waveformPeaks('/tmp/a.m4a', 3);

      expect(calls.single.method, 'waveformPeaks');
      expect(calls.single.arguments, {'path': '/tmp/a.m4a', 'buckets': 3});
      expect(peaks, [0.0, 0.5, 1.0]);
    });

    test('waveformPeaks tolerates int values on the wire', () async {
      handle(response: <Object?>[0, 1]);

      final peaks = await native.waveformPeaks('/tmp/a.wav', 2);

      expect(peaks, [0.0, 1.0]);
    });
  });

  group('models', () {
    test('new model wire names and deleteModel', () async {
      handle();

      await native.deleteModel(WhisperModel.tiny);
      await native.deleteModel(WhisperModel.medium);
      await native.deleteModel(WhisperModel.largeV3);

      expect(calls.map((c) => c.method), [
        'deleteModel',
        'deleteModel',
        'deleteModel',
      ]);
      expect(calls[0].arguments, {'model': 'tiny'});
      expect(calls[1].arguments, {'model': 'medium'});
      expect(calls[2].arguments, {'model': 'largeV3'});
    });

    test('modelState round-trips for medium', () async {
      handle(response: {'downloaded': true, 'sizeBytes': 539212467});

      final state = await native.modelState(WhisperModel.medium);

      expect(calls.single.arguments, {'model': 'medium'});
      expect(state.sizeBytes, 539212467);
    });

    test('file names match the ggml artifacts', () {
      expect(WhisperModel.tiny.fileName, 'ggml-tiny.bin');
      expect(WhisperModel.smallQ5.fileName, 'ggml-small-q5_1.bin');
      expect(WhisperModel.medium.fileName, 'ggml-medium-q5_0.bin');
      expect(
        WhisperModel.largeV3TurboQ5.fileName,
        'ggml-large-v3-turbo-q5_0.bin',
      );
      expect(WhisperModel.largeV3.fileName, 'ggml-large-v3-q5_0.bin');
    });
  });

  group('transcription with vocabulary + words', () {
    test('transcribe forwards initialPrompt and parses words', () async {
      handle(
        response: [
          {
            'startMs': 0,
            'endMs': 1000,
            'text': 'olá mundo',
            'words': [
              {
                'text': 'olá',
                'startMs': 0,
                'endMs': 400,
                'probability': 0.92,
              },
              {
                'text': 'mundo',
                'startMs': 400,
                'endMs': 1000,
                'probability': 0.81,
              },
            ],
          },
        ],
      );

      final segments = await native.transcribe(
        wavPath: '/tmp/a.wav',
        model: WhisperModel.tiny,
        initialPrompt: 'RbNotes, whisper.cpp',
      );

      expect(calls.single.arguments, {
        'wavPath': '/tmp/a.wav',
        'model': 'tiny',
        'language': 'pt',
        'initialPrompt': 'RbNotes, whisper.cpp',
        'priority': 'normal',
      });
      final words = segments.single.words!;
      expect(words, hasLength(2));
      expect(words.first.text, 'olá');
      expect(words.first.start, Duration.zero);
      expect(words.first.end, const Duration(milliseconds: 400));
      expect(words.first.probability, closeTo(0.92, 1e-9));
    });

    test('transcribe tolerates segments without a words field', () async {
      handle(
        response: [
          {'startMs': 0, 'endMs': 500, 'text': 'sem palavras'},
        ],
      );

      final segments = await native.transcribe(
        wavPath: '/tmp/a.wav',
        model: WhisperModel.largeV3,
      );

      expect(segments.single.words, isNull);
      expect(calls.single.arguments, containsPair('initialPrompt', null));
      expect(calls.single.arguments, containsPair('model', 'largeV3'));
    });
  });

  group('live transcript stream', () {
    test('liveTranscript filters a single stream by recordingId', () async {
      messenger.setMockStreamHandler(
        const EventChannel(RbNativeChannels.liveTranscript),
        _ListStreamHandler([
          {'recordingId': 'n1', 'text': 'olá', 'isFinal': false},
          {'recordingId': 'n2', 'text': 'outro', 'isFinal': false},
          {'recordingId': 'n1', 'text': 'olá mundo', 'isFinal': true},
        ]),
      );

      final events = await native.liveTranscript('n1').take(2).toList();

      expect(events, hasLength(2));
      expect(events[0].recordingId, 'n1');
      expect(events[0].text, 'olá');
      expect(events[0].isFinal, isFalse);
      expect(events[1].text, 'olá mundo');
      expect(events[1].isFinal, isTrue);

      messenger.setMockStreamHandler(
        const EventChannel(RbNativeChannels.liveTranscript),
        null,
      );
    });
  });

  group('global hotkeys', () {
    test('registerGlobalHotkey serializes id + hotkey', () async {
      handle();

      await native.registerGlobalHotkey(
        id: 'record_note',
        hotkey: const Hotkey(
          keyCode: 49,
          modifiers: {HotkeyModifier.option, HotkeyModifier.shift},
        ),
      );

      expect(calls.single.method, 'registerGlobalHotkey');
      final args = calls.single.arguments as Map;
      expect(args['id'], 'record_note');
      final hotkey = args['hotkey'] as Map;
      expect(hotkey['keyCode'], 49);
      expect((hotkey['modifiers'] as List).toSet(), {'option', 'shift'});
    });

    test('unregisterGlobalHotkey serializes id', () async {
      handle();
      await native.unregisterGlobalHotkey('record_note');
      expect(calls.single.method, 'unregisterGlobalHotkey');
      expect(calls.single.arguments, {'id': 'record_note'});
    });

    test('registerGlobalHotkey maps hotkey_conflict', () async {
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        throw PlatformException(code: RbNativeErrorCode.hotkeyConflict);
      });

      await expectLater(
        native.registerGlobalHotkey(
          id: 'record_note',
          hotkey: const Hotkey(keyCode: 49, modifiers: {HotkeyModifier.option}),
        ),
        throwsA(
          isA<RbNativeException>().having(
            (e) => e.code,
            'code',
            RbNativeErrorCode.hotkeyConflict,
          ),
        ),
      );
    });

    test('globalHotkeyPressed emits the pressed id', () async {
      messenger.setMockStreamHandler(
        const EventChannel(RbNativeChannels.globalHotkeys),
        _ListStreamHandler(const ['record_note', 'other', 'record_note']),
      );

      final ids = await native.globalHotkeyPressed().take(3).toList();

      expect(ids, const ['record_note', 'other', 'record_note']);

      messenger.setMockStreamHandler(
        const EventChannel(RbNativeChannels.globalHotkeys),
        null,
      );
    });
  });

  group('activity overlay', () {
    test('showActivityOverlay serializes mode and startedAt', () async {
      handle();
      final started = DateTime.fromMillisecondsSinceEpoch(1700000000000);

      await native.showActivityOverlay(
        mode: OverlayMode.recording,
        startedAt: started,
      );

      expect(calls.single.method, 'showActivityOverlay');
      expect(calls.single.arguments, {
        'mode': 'recording',
        'startedAtMs': 1700000000000,
      });
    });

    test('showActivityOverlay forwards dictation mode', () async {
      handle();
      await native.showActivityOverlay(
        mode: OverlayMode.dictation,
        startedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      expect((calls.single.arguments as Map)['mode'], 'dictation');
    });

    test('updateActivityOverlay sends only the fields given, nulls otherwise',
        () async {
      handle();

      await native.updateActivityOverlay(micLevel: 0.6, liveText: 'olá');

      expect(calls.single.method, 'updateActivityOverlay');
      expect(calls.single.arguments, {
        'micLevel': 0.6,
        'systemLevel': null,
        'liveText': 'olá',
        'phase': null,
        'progress': null,
        'message': null,
        'paused': null,
      });
    });

    test('updateActivityOverlay serializes phase/progress/message', () async {
      handle();

      await native.updateActivityOverlay(
        phase: OverlayPhase.processing,
        progress: 0.4,
        message: 'Transcrevendo',
        paused: true,
      );

      final args = calls.single.arguments as Map;
      expect(args['phase'], 'processing');
      expect(args['progress'], 0.4);
      expect(args['message'], 'Transcrevendo');
      expect(args['paused'], true);
    });

    test('hideActivityOverlay defaults to zero delay', () async {
      handle();
      await native.hideActivityOverlay();
      expect(calls.single.method, 'hideActivityOverlay');
      expect(calls.single.arguments, {'delayMs': 0});
    });

    test('hideActivityOverlay forwards the delay in ms', () async {
      handle();
      await native.hideActivityOverlay(
        delay: const Duration(milliseconds: 1500),
      );
      expect((calls.single.arguments as Map)['delayMs'], 1500);
    });

    test('overlayActions decodes each known wire action', () async {
      messenger.setMockStreamHandler(
        const EventChannel(RbNativeChannels.overlayActions),
        _ListStreamHandler(const [
          'pause',
          'resume',
          'stop',
          'discard',
          'openApp',
        ]),
      );

      final actions = await native.overlayActions().take(5).toList();

      expect(actions, const [
        OverlayAction.pause,
        OverlayAction.resume,
        OverlayAction.stop,
        OverlayAction.discard,
        OverlayAction.openApp,
      ]);

      messenger.setMockStreamHandler(
        const EventChannel(RbNativeChannels.overlayActions),
        null,
      );
    });

    test('overlayActions surfaces an unknown action as invalid_event',
        () async {
      messenger.setMockStreamHandler(
        const EventChannel(RbNativeChannels.overlayActions),
        _ListStreamHandler(const ['explode']),
      );

      await expectLater(
        native.overlayActions().first,
        throwsA(
          isA<RbNativeException>().having(
            (e) => e.code,
            'code',
            RbNativeErrorCode.invalidEvent,
          ),
        ),
      );

      messenger.setMockStreamHandler(
        const EventChannel(RbNativeChannels.overlayActions),
        null,
      );
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
