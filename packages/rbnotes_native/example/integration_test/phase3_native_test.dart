// macOS integration tests for the Phase 3 native features that need the real
// plugin (not the method-channel fake): energy-VAD silence detection and local
// sherpa-onnx diarization over the smoke WAV.
//
// Run with:
//   fvm flutter test integration_test/phase3_native_test.dart -d macos
//
// Diarization downloads ~34 MB of models on first run (segmentation +
// embedding) into Application Support; the test skips the diarization
// assertions gracefully if the models cannot be fetched (offline CI).
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rbnotes_native/rbnotes_native.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final native = MethodChannelRbNative();

  group('detectSilences (energy VAD)', () {
    late String wavPath;

    setUpAll(() {
      wavPath = '${Directory.systemTemp.path}/rb_vad_fixture.wav';
      // 1 s tone, 3 s silence, 1 s tone @ 16 kHz mono s16le.
      final samples = <int>[
        ..._tone(seconds: 1),
        ..._silence(seconds: 3),
        ..._tone(seconds: 1),
      ];
      File(wavPath).writeAsBytesSync(_wav16kMono(samples));
    });

    testWidgets('finds the long silence run', (tester) async {
      final ranges = await native.detectSilences(
        wavPath,
        minSilence: const Duration(seconds: 2),
      );
      expect(ranges, isNotEmpty);
      final run = ranges.first;
      expect(run.duration.inMilliseconds, greaterThanOrEqualTo(2000));
      // The run sits roughly between 1 s and 4 s.
      expect(run.start.inMilliseconds, greaterThan(500));
      expect(run.end.inMilliseconds, lessThan(4500));
    });

    testWidgets('ignores silence shorter than the minimum', (tester) async {
      final ranges = await native.detectSilences(
        wavPath,
        minSilence: const Duration(seconds: 10),
      );
      expect(ranges, isEmpty);
    });
  });

  group('diarize (sherpa-onnx)', () {
    testWidgets('runs the pipeline over the smoke WAV', (tester) async {
      final fixture = await _ensureTwoSpeakerFixture();
      if (fixture == null) {
        // No `say` voices available to synthesize a fixture — skip.
        return;
      }

      // Ensure the models are present (download once, ~34 MB).
      final state = await native.diarizationModelState();
      if (!state.downloaded) {
        try {
          await native.downloadDiarizationModel().last;
        } on Object {
          // Offline / download blocked → skip the diarization assertions.
          return;
        }
      }

      final turns = await native.diarize(fixture);
      // The pipeline must return well-formed, time-ordered turns.
      expect(turns, isNotEmpty);
      for (final t in turns) {
        expect(t.end, greaterThan(t.start));
        expect(t.speaker, greaterThanOrEqualTo(0));
      }
      for (var i = 1; i < turns.length; i++) {
        expect(
          turns[i].start.inMilliseconds,
          greaterThanOrEqualTo(turns[i - 1].start.inMilliseconds),
        );
      }
    });
  });
}

/// Generates a two-voice 16 kHz mono fixture via `say` + `afconvert` if it does
/// not already exist. Returns its path, or null when no voices are available.
Future<String?> _ensureTwoSpeakerFixture() async {
  const out = '/tmp/rbicon/diar_two.wav';
  if (File(out).existsSync()) return out;
  Directory('/tmp/rbicon').createSync(recursive: true);

  Future<bool> say(List<String> args) async {
    try {
      final r = await Process.run('say', args);
      return r.exitCode == 0;
    } on Object {
      return false;
    }
  }

  Future<bool> convert(String src, String dst) async {
    final r = await Process.run('afconvert', [
      '-f',
      'WAVE',
      '-d',
      'LEI16@16000',
      '-c',
      '1',
      src,
      dst,
    ]);
    return r.exitCode == 0;
  }

  final okA = await say([
    '-v',
    'Luciana',
    '-o',
    '/tmp/rbicon/a.aiff',
    'Olá, bom dia. Vamos começar a reunião de hoje falando sobre o projeto.',
  ]);
  final okB = await say([
    '-v',
    'Daniel',
    '-o',
    '/tmp/rbicon/b.aiff',
    'Sure, I prepared the quarterly numbers and the pending tasks for the team.',
  ]);
  if (!okA || !okB) return null;
  if (!await convert('/tmp/rbicon/a.aiff', '/tmp/rbicon/a16.wav')) return null;
  if (!await convert('/tmp/rbicon/b.aiff', '/tmp/rbicon/b16.wav')) return null;

  // Concatenate A|B|A|B PCM bodies into one WAV.
  final a = _pcmBody(File('/tmp/rbicon/a16.wav').readAsBytesSync());
  final b = _pcmBody(File('/tmp/rbicon/b16.wav').readAsBytesSync());
  final body = <int>[...a, ...b, ...a, ...b];
  File(out).writeAsBytesSync(_wav16kMonoBytes(Uint8List.fromList(body)));
  return out;
}

List<int> _tone({required int seconds, double freq = 220, double amp = 0.5}) {
  const rate = 16000;
  final n = rate * seconds;
  final out = <int>[];
  for (var i = 0; i < n; i++) {
    final v = (amp * 32767 * math.sin(2 * math.pi * freq * i / rate)).round();
    out.add(v & 0xFF);
    out.add((v >> 8) & 0xFF);
  }
  return out;
}

List<int> _silence({required int seconds}) {
  const rate = 16000;
  return List<int>.filled(rate * seconds * 2, 0);
}

Uint8List _wav16kMono(List<int> pcmBytes) =>
    _wav16kMonoBytes(Uint8List.fromList(pcmBytes));

Uint8List _wav16kMonoBytes(Uint8List pcm) {
  const rate = 16000;
  final out = BytesBuilder();
  void a32(int v) =>
      out.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  void a16(int v) => out.add([v & 0xFF, (v >> 8) & 0xFF]);
  out.add('RIFF'.codeUnits);
  a32(36 + pcm.length);
  out.add('WAVE'.codeUnits);
  out.add('fmt '.codeUnits);
  a32(16);
  a16(1);
  a16(1);
  a32(rate);
  a32(rate * 2);
  a16(2);
  a16(16);
  out.add('data'.codeUnits);
  a32(pcm.length);
  out.add(pcm);
  return out.toBytes();
}

/// Extracts the PCM body of a canonical 44-byte-header WAV.
List<int> _pcmBody(Uint8List wav) =>
    wav.length > 44 ? wav.sublist(44) : <int>[];
