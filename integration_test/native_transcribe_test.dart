import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rbnotes_native/rbnotes_native.dart';

/// Smoke real do caminho app → plugin → whisper.cpp (roda só no macOS, com
/// modelo baixado). Configure RBNOTES_SMOKE_WAV com um .wav 16 kHz mono.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('transcribe real wav with the default model', (tester) async {
    const wav = String.fromEnvironment('RBNOTES_SMOKE_WAV');
    if (wav.isEmpty || !File(wav).existsSync()) {
      markTestSkipped('RBNOTES_SMOKE_WAV não definido');
      return;
    }
    final native = MethodChannelRbNative();
    final state = await native.modelState(WhisperModel.largeV3TurboQ5);
    // ignore: avoid_print
    print('modelState: downloaded=${state.downloaded} size=${state.sizeBytes}');
    try {
      final segs = await native.transcribe(
        wavPath: wav,
        model: WhisperModel.largeV3TurboQ5,
        initialPrompt: '',
      );
      // ignore: avoid_print
      print('SEGMENTS ${segs.length}: ${segs.map((s) => s.text).join(' | ')}');
      expect(segs, isNotEmpty);
    } on RbNativeException catch (e) {
      // ignore: avoid_print
      print('NATIVE ERROR code=${e.code} message=${e.message}');
      rethrow;
    }
  });
}
