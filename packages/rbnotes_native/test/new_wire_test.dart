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
