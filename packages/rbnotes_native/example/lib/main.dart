import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rbnotes_native/rbnotes_native.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'rbnotes_native example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final RbNative _native = MethodChannelRbNative();
  final List<String> _log = <String>[];

  StreamSubscription<AudioLevels>? _levelsSub;
  StreamSubscription<DictationEvent>? _dictationSub;
  AudioLevels? _levels;
  RecordingResult? _lastResult;
  bool _recording = false;
  bool _overlayShown = false;
  Timer? _overlayDemoTimer;
  StreamSubscription<OverlayAction>? _overlaySub;
  static const String _recordingId = 'demo';

  void _append(String line) {
    setState(() => _log.insert(0, line));
  }

  Future<void> _checkPermissions() async {
    for (final permission in RbPermission.values) {
      final status = await _native.permissionStatus(permission);
      _append('${permission.name}: ${status.name}');
    }
  }

  Future<void> _request(RbPermission permission) async {
    try {
      final status = await _native.requestPermission(permission);
      _append('request ${permission.name}: ${status.name}');
    } on RbNativeException catch (e) {
      _append('ERR ${e.code}: ${e.message}');
    }
  }

  Future<void> _startRecording({required bool system}) async {
    try {
      final dir = (await getApplicationSupportDirectory()).path;
      final handle = await _native.startRecording(
        id: _recordingId,
        directory: dir,
        captureSystemAudio: system,
      );
      _levelsSub = _native.audioLevels(_recordingId).listen((levels) {
        setState(() => _levels = levels);
      });
      setState(() => _recording = true);
      _append('recording started @ ${handle.startedAt}');
    } on RbNativeException catch (e) {
      _append('ERR ${e.code}: ${e.message}');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final result = await _native.stopRecording(_recordingId);
      await _levelsSub?.cancel();
      setState(() {
        _recording = false;
        _lastResult = result;
        _levels = null;
      });
      _append(
        'stopped: ${result.duration.inSeconds}s, '
        'system=${result.systemWavPath != null}',
      );
    } on RbNativeException catch (e) {
      _append('ERR ${e.code}: ${e.message}');
    }
  }

  Future<void> _transcribe() async {
    final wav = _lastResult?.micWavPath;
    if (wav == null) {
      _append('no recording to transcribe');
      return;
    }
    try {
      final state = await _native.modelState(WhisperModel.smallQ5);
      if (!state.downloaded) {
        _append('downloading smallQ5...');
        await for (final p in _native.downloadModel(WhisperModel.smallQ5)) {
          _append('download ${(p * 100).toStringAsFixed(0)}%');
        }
      }
      final segments = await _native.transcribe(
        wavPath: wav,
        model: WhisperModel.smallQ5,
        onProgress: (p) =>
            _append('transcribe ${(p * 100).toStringAsFixed(0)}%'),
      );
      for (final s in segments) {
        _append('[${s.start.inMilliseconds}ms] ${s.text}');
      }
    } on RbNativeException catch (e) {
      _append('ERR ${e.code}: ${e.message}');
    }
  }

  Future<void> _registerDictation() async {
    try {
      _dictationSub = _native.dictationEvents().listen((event) {
        _append('dictation: ${event.runtimeType}');
      });
      // ⌥ Space, hold-to-talk (Space = keyCode 49).
      await _native.registerDictationHotkey(
        const Hotkey(keyCode: 49, modifiers: {HotkeyModifier.option}),
        DictationMode.holdToTalk,
      );
      _append('dictation hotkey registered (⌥Space hold)');
    } on RbNativeException catch (e) {
      _append('ERR ${e.code}: ${e.message}');
    }
  }

  Future<void> _toggleOverlay() async {
    if (_overlayShown) {
      await _native.hideActivityOverlay();
      _overlayDemoTimer?.cancel();
      await _overlaySub?.cancel();
      setState(() => _overlayShown = false);
      _append('overlay hidden');
      return;
    }
    try {
      _overlaySub = _native.overlayActions().listen((action) {
        _append('overlay action: ${action.name}');
        if (action == OverlayAction.stop) {
          unawaited(_simulateProcessing());
        } else if (action == OverlayAction.discard) {
          unawaited(_native.hideActivityOverlay());
          _overlayDemoTimer?.cancel();
          setState(() => _overlayShown = false);
        }
      });
      await _native.showActivityOverlay(
        mode: OverlayMode.recording,
        startedAt: DateTime.now(),
      );
      setState(() => _overlayShown = true);
      _append('overlay shown — feeding fake levels/transcript');
      // Feed fake levels + a growing transcript so the HUD looks alive.
      final words = 'Esta é uma demonstração do overlay que sai do notch '
              'enquanto o RbNotes grava o seu áudio localmente'
          .split(' ');
      var tick = 0;
      _overlayDemoTimer = Timer.periodic(const Duration(milliseconds: 100), (
        _,
      ) {
        tick++;
        final level = 0.2 + 0.6 * (0.5 + 0.5 * math.sin(tick / 3));
        final text = words.take((tick ~/ 6).clamp(1, words.length)).join(' ');
        _native.updateActivityOverlay(micLevel: level, liveText: text);
      });
    } on RbNativeException catch (e) {
      _append('ERR ${e.code}: ${e.message}');
    }
  }

  Future<void> _simulateProcessing() async {
    _overlayDemoTimer?.cancel();
    await _native.updateActivityOverlay(
      phase: OverlayPhase.processing,
      progress: 0.1,
      message: 'Transcrevendo com Whisper',
    );
    for (var p = 2; p <= 10; p++) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await _native.updateActivityOverlay(progress: p / 10);
    }
    await _native.updateActivityOverlay(
      phase: OverlayPhase.done,
      message: 'Nota salva',
    );
    // The native side auto-hides "done" after ~1.5s.
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (mounted) setState(() => _overlayShown = false);
  }

  @override
  void dispose() {
    _levelsSub?.cancel();
    _dictationSub?.cancel();
    _overlaySub?.cancel();
    _overlayDemoTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('rbnotes_native example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _checkPermissions,
                  child: const Text('Check permissions'),
                ),
                for (final p in RbPermission.values)
                  OutlinedButton(
                    onPressed: () => _request(p),
                    child: Text('Request ${p.name}'),
                  ),
                FilledButton(
                  onPressed: _recording
                      ? null
                      : () => _startRecording(system: true),
                  child: const Text('Record (mic+system)'),
                ),
                FilledButton(
                  onPressed: _recording ? _stopRecording : null,
                  child: const Text('Stop'),
                ),
                OutlinedButton(
                  onPressed: _transcribe,
                  child: const Text('Transcribe (smallQ5)'),
                ),
                OutlinedButton(
                  onPressed: _registerDictation,
                  child: const Text('Register dictation'),
                ),
                FilledButton.tonal(
                  onPressed: _toggleOverlay,
                  child: Text(
                    _overlayShown ? 'Esconder overlay' : 'Mostrar overlay',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_levels != null)
              Text(
                'levels — mic: ${_levels!.mic.toStringAsFixed(2)} '
                'system: ${_levels!.system?.toStringAsFixed(2) ?? "-"}',
              ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _log.length,
                itemBuilder: (_, i) => Text(
                  _log[i],
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
