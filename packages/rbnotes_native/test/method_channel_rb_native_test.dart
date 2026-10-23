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

  /// Installs a handler that records calls and returns [response] (or runs
  /// [onCall] to compute it / throw).
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

  group('permissions', () {
    test('permissionStatus serializes permission and maps status', () async {
      handle(response: 'granted');

      final status = await native.permissionStatus(RbPermission.microphone);

      expect(status, PermissionStatus.granted);
      expect(calls.single.method, 'permissionStatus');
      expect(calls.single.arguments, {'permission': 'microphone'});
    });

    test('requestPermission maps screenRecording/notDetermined', () async {
      handle(response: 'notDetermined');

      final status = await native.requestPermission(
        RbPermission.screenRecording,
      );

      expect(status, PermissionStatus.notDetermined);
      expect(calls.single.method, 'requestPermission');
      expect(calls.single.arguments, {'permission': 'screenRecording'});
    });

    test('accessibility wire name is correct', () async {
      handle(response: 'denied');

      final status = await native.permissionStatus(RbPermission.accessibility);

      expect(status, PermissionStatus.denied);
      expect(calls.single.arguments, {'permission': 'accessibility'});
    });
  });

  group('recording', () {
    test('startRecording serializes args and parses handle', () async {
      final startedAt = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      handle(response: {'id': 'note-1', 'startedAtMs': 1700000000000});

      final handleResult = await native.startRecording(
        id: 'note-1',
        directory: '/tmp/notes',
        captureSystemAudio: true,
      );

      expect(handleResult.id, 'note-1');
      expect(handleResult.startedAt, startedAt);
      expect(calls.single.method, 'startRecording');
      expect(calls.single.arguments, {
        'id': 'note-1',
        'directory': '/tmp/notes',
        'captureSystemAudio': true,
      });
    });

    test('stopRecording parses result with system audio', () async {
      handle(
        response: {
          'id': 'note-1',
          'durationMs': 65000,
          'micWavPath': '/tmp/notes/note-1.mic.wav',
          'systemWavPath': '/tmp/notes/note-1.system.wav',
          'playbackPath': '/tmp/notes/note-1.m4a',
        },
      );

      final result = await native.stopRecording('note-1');

      expect(result.duration, const Duration(milliseconds: 65000));
      expect(result.micWavPath, '/tmp/notes/note-1.mic.wav');
      expect(result.systemWavPath, '/tmp/notes/note-1.system.wav');
      expect(result.playbackPath, '/tmp/notes/note-1.m4a');
    });

    test('stopRecording tolerates null systemWavPath (mic-only)', () async {
      handle(
        response: {
          'id': 'note-2',
          'durationMs': 1000,
          'micWavPath': '/tmp/note-2.mic.wav',
          'systemWavPath': null,
          'playbackPath': '/tmp/note-2.m4a',
        },
      );

      final result = await native.stopRecording('note-2');

      expect(result.systemWavPath, isNull);
    });

    test('pause/resume send id', () async {
      handle();
      await native.pauseRecording('x');
      await native.resumeRecording('x');
      expect(calls.map((c) => c.method), ['pauseRecording', 'resumeRecording']);
      expect(calls.first.arguments, {'id': 'x'});
    });

    test('findRecoverableRecordings parses a list', () async {
      handle(
        response: [
          {
            'id': 'orphan-1',
            'micWavPath': '/tmp/orphan-1.mic.wav',
            'systemWavPath': '/tmp/orphan-1.system.wav',
            'durationMs': 42000,
          },
          {
            'id': 'orphan-2',
            'micWavPath': '/tmp/orphan-2.mic.wav',
            'systemWavPath': null,
            'durationMs': 1000,
          },
        ],
      );

      final list = await native.findRecoverableRecordings('/tmp');

      expect(list, hasLength(2));
      expect(list.first.id, 'orphan-1');
      expect(list.first.duration, const Duration(milliseconds: 42000));
      expect(list[1].systemWavPath, isNull);
      expect(calls.single.arguments, {'directory': '/tmp'});
    });
  });

  group('transcription', () {
    test('modelState parses downloaded + size', () async {
      handle(response: {'downloaded': true, 'sizeBytes': 123456});

      final state = await native.modelState(WhisperModel.largeV3TurboQ5);

      expect(state.downloaded, isTrue);
      expect(state.sizeBytes, 123456);
      expect(calls.single.arguments, {'model': 'largeV3TurboQ5'});
    });

    test('transcribe serializes args with default normal priority', () async {
      handle(
        response: [
          {'startMs': 0, 'endMs': 1500, 'text': 'olá'},
          {'startMs': 1500, 'endMs': 3000, 'text': 'mundo'},
        ],
      );

      final segments = await native.transcribe(
        wavPath: '/tmp/a.wav',
        model: WhisperModel.smallQ5,
      );

      expect(segments, hasLength(2));
      expect(segments.first.text, 'olá');
      expect(segments.first.start, Duration.zero);
      expect(segments.first.end, const Duration(milliseconds: 1500));
      expect(calls.single.method, 'transcribe');
      expect(calls.single.arguments, {
        'wavPath': '/tmp/a.wav',
        'model': 'smallQ5',
        'language': 'pt',
        'priority': 'normal',
      });
    });

    test('transcribe forwards language override and high priority', () async {
      handle(response: <Object?>[]);

      await native.transcribe(
        wavPath: '/tmp/a.wav',
        model: WhisperModel.largeV3TurboQ5,
        language: 'en',
        priority: TranscriptionPriority.high,
      );

      expect(calls.single.arguments, containsPair('language', 'en'));
      expect(calls.single.arguments, containsPair('priority', 'high'));
    });

    test('cancelTranscription sends wavPath', () async {
      handle();
      await native.cancelTranscription('/tmp/a.wav');
      expect(calls.single.method, 'cancelTranscription');
      expect(calls.single.arguments, {'wavPath': '/tmp/a.wav'});
    });
  });

  group('dictation', () {
    test('registerDictationHotkey serializes keyCode/modifiers/mode', () async {
      handle();

      await native.registerDictationHotkey(
        const Hotkey(
          keyCode: 49,
          modifiers: {HotkeyModifier.command, HotkeyModifier.option},
        ),
        DictationMode.holdToTalk,
      );

      expect(calls.single.method, 'registerDictationHotkey');
      final args = calls.single.arguments as Map;
      expect(args['mode'], 'holdToTalk');
      final hotkey = args['hotkey'] as Map;
      expect(hotkey['keyCode'], 49);
      expect(
        (hotkey['modifiers'] as List).toSet(),
        {'command', 'option'},
      );
    });

    test('unregisterDictationHotkey', () async {
      handle();
      await native.unregisterDictationHotkey();
      expect(calls.single.method, 'unregisterDictationHotkey');
    });

    test('pasteText sends text', () async {
      handle();
      await native.pasteText('conteúdo');
      expect(calls.single.method, 'pasteText');
      expect(calls.single.arguments, {'text': 'conteúdo'});
    });

    test('playDictationSound serializes sound', () async {
      handle();
      await native.playDictationSound(DictationSound.end);
      expect(calls.single.arguments, {'sound': 'end'});
    });
  });

  group('DictationEvent decoding', () {
    test('decodes the sealed hierarchy', () {
      expect(
        DictationEvent.fromMap(const {'type': 'started'}),
        isA<DictationStarted>(),
      );
      final stopped = DictationEvent.fromMap(const {
        'type': 'stopped',
        'wavPath': '/tmp/d.wav',
      });
      expect(stopped, isA<DictationStopped>());
      expect((stopped as DictationStopped).wavPath, '/tmp/d.wav');
      expect(
        DictationEvent.fromMap(const {'type': 'cancelled'}),
        isA<DictationCancelled>(),
      );
    });

    test('unknown type throws invalid_event', () {
      expect(
        () => DictationEvent.fromMap(const {'type': 'bogus'}),
        throwsA(
          isA<RbNativeException>().having(
            (e) => e.code,
            'code',
            RbNativeErrorCode.invalidEvent,
          ),
        ),
      );
    });

    test('stopped without wavPath throws invalid_event', () {
      expect(
        () => DictationEvent.fromMap(const {'type': 'stopped'}),
        throwsA(
          isA<RbNativeException>().having(
            (e) => e.code,
            'code',
            RbNativeErrorCode.invalidEvent,
          ),
        ),
      );
    });
  });

  group('error mapping', () {
    test(
      'PlatformException becomes RbNativeException with same code',
      () async {
        handle(
          onCall: (_) async => throw PlatformException(
            code: RbNativeErrorCode.alreadyRecording,
            message: 'already going',
          ),
        );

        expect(
          () => native.startRecording(
            id: 'x',
            directory: '/tmp',
            captureSystemAudio: false,
          ),
          throwsA(
            isA<RbNativeException>()
                .having((e) => e.code, 'code', 'already_recording')
                .having((e) => e.message, 'message', 'already going'),
          ),
        );
      },
    );

    test('invalid_argument code is preserved', () async {
      handle(
        onCall: (_) async => throw PlatformException(
          code: RbNativeErrorCode.invalidArgument,
          message: 'missing id',
        ),
      );

      await expectLater(
        native.stopRecording('x'),
        throwsA(
          isA<RbNativeException>().having(
            (e) => e.code,
            'code',
            RbNativeErrorCode.invalidArgument,
          ),
        ),
      );
    });

    test('MissingPluginException maps to unknown code', () async {
      messenger.setMockMethodCallHandler(methodChannel, null);

      await expectLater(
        native.unregisterDictationHotkey(),
        throwsA(
          isA<RbNativeException>().having(
            (e) => e.code,
            'code',
            RbNativeErrorCode.unknown,
          ),
        ),
      );
    });
  });

  group('event channels', () {
    test('audioLevels decodes per-channel maps', () async {
      messenger.setMockStreamHandler(
        const EventChannel(RbNativeChannels.levels),
        _ListStreamHandler([
          {'mic': 0.5, 'system': 0.25},
          {'mic': 0.1, 'system': null},
        ]),
      );

      final events = await native.audioLevels('note-1').take(2).toList();

      expect(events.first.mic, 0.5);
      expect(events.first.system, 0.25);
      expect(events[1].system, isNull);
    });

    test('dictationEvents decodes the sealed hierarchy', () async {
      messenger.setMockStreamHandler(
        const EventChannel(RbNativeChannels.dictation),
        _ListStreamHandler([
          {'type': 'started'},
          {'type': 'stopped', 'wavPath': '/tmp/d.wav'},
          {'type': 'cancelled'},
        ]),
      );

      final events = await native.dictationEvents().take(3).toList();

      expect(events[0], isA<DictationStarted>());
      expect(events[1], isA<DictationStopped>());
      expect((events[1] as DictationStopped).wavPath, '/tmp/d.wav');
      expect(events[2], isA<DictationCancelled>());
    });

    test('diagnostics decodes NativeDiagnostic incl. recordingId', () async {
      messenger.setMockStreamHandler(
        const EventChannel(RbNativeChannels.diagnostics),
        _ListStreamHandler([
          {
            'code': 'write_failed',
            'message': 'disk full',
            'recordingId': 'note-7',
          },
          {'code': 'audio_config_changed', 'message': 'device swapped'},
        ]),
      );

      final events = await native.diagnostics().take(2).toList();

      expect(events[0].code, 'write_failed');
      expect(events[0].message, 'disk full');
      expect(events[0].recordingId, 'note-7');
      expect(events[1].code, 'audio_config_changed');
      expect(events[1].recordingId, isNull);
    });

    test('downloadModel maps doubles and propagates errors', () async {
      messenger.setMockStreamHandler(
        const EventChannel(RbNativeChannels.modelDownload),
        _ListStreamHandler(
          [0.0, 0.5],
          error: const _StreamError(
            code: RbNativeErrorCode.modelDownloadFailed,
            message: 'network down',
          ),
        ),
      );

      final progress = <double>[];
      await expectLater(
        native.downloadModel(WhisperModel.largeV3TurboQ5).forEach(progress.add),
        throwsA(
          isA<RbNativeException>().having(
            (e) => e.code,
            'code',
            'model_download_failed',
          ),
        ),
      );
      expect(progress, [0.0, 0.5]);
    });

    test('transcribe multiplexes progress filtered by wavPath', () async {
      messenger
        ..setMockStreamHandler(
          const EventChannel(RbNativeChannels.transcriptionProgress),
          _ListStreamHandler([
            {'wavPath': '/tmp/a.wav', 'progress': 0.25},
            {'wavPath': '/tmp/other.wav', 'progress': 0.9},
            {'wavPath': '/tmp/a.wav', 'progress': 0.75},
          ]),
        )
        ..setMockMethodCallHandler(methodChannel, (call) async {
          // Give the progress stream a chance to deliver before returning.
          await Future<void>.delayed(const Duration(milliseconds: 40));
          return <Object?>[
            {'startMs': 0, 'endMs': 100, 'text': 'ok'},
          ];
        });

      final progress = <double>[];
      final segments = await native.transcribe(
        wavPath: '/tmp/a.wav',
        model: WhisperModel.smallQ5,
        onProgress: progress.add,
      );

      expect(segments.single.text, 'ok');
      // Only this wavPath's events, not /tmp/other.wav's 0.9.
      expect(progress, containsAllInOrder(<double>[0.25]));
      expect(progress, isNot(contains(0.9)));
    });
  });
}

/// Minimal [MockStreamHandler] that replays [events] and optionally ends with
/// an [error].
class _ListStreamHandler extends MockStreamHandler {
  _ListStreamHandler(this.events, {this.error});

  final List<Object?> events;
  final _StreamError? error;

  @override
  void onListen(Object? arguments, MockStreamHandlerEventSink events) {
    for (final event in this.events) {
      events.success(event);
    }
    if (error != null) {
      events.error(code: error!.code, message: error!.message);
    } else {
      events.endOfStream();
    }
  }

  @override
  void onCancel(Object? arguments) {}
}

class _StreamError {
  const _StreamError({required this.code, required this.message});
  final String code;
  final String message;
}
