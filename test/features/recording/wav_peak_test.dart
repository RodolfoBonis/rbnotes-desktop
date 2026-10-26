import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/features/recording/domain/wav_peak.dart';

/// Monta um WAV PCM 16-bit mono com os [samples] dados.
Uint8List _wav(List<int> samples, {int sampleRate = 16000}) {
  final pcm = Int16List.fromList(samples);
  final dataBytes = pcm.buffer.asUint8List();
  final header = ByteData(44);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      header.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  header
    ..setUint32(4, 36 + dataBytes.length, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  tag(36, 'data');
  header.setUint32(40, dataBytes.length, Endian.little);
  return (BytesBuilder()
        ..add(header.buffer.asUint8List())
        ..add(dataBytes))
      .takeBytes();
}

void main() {
  group('WavPeak.parse', () {
    test('silêncio digital: todos os samples zero → isDigitalSilence', () {
      final s = WavPeak.parse(_wav(List.filled(128, 0)))!;
      expect(s.samples, 128);
      expect(s.peak, 0);
      expect(s.isDigitalSilence, isTrue);
    });

    test('com sinal: pico > 0 e não é silêncio digital', () {
      final s = WavPeak.parse(_wav([0, 16384, -32768, 100]))!;
      expect(s.peak, closeTo(1.0, 0.0001)); // -32768 → ~1.0
      expect(s.isDigitalSilence, isFalse);
    });

    test('pico pequeno (ambiente baixo) não é silêncio digital', () {
      final s = WavPeak.parse(_wav([0, 1, 0, -2]))!;
      expect(s.peak, greaterThan(0));
      expect(s.isDigitalSilence, isFalse);
    });

    test('bytes que não são WAV → null', () {
      expect(WavPeak.parse(Uint8List.fromList(List.filled(64, 7))), isNull);
    });

    test('arquivo curto demais → null', () {
      expect(WavPeak.parse(Uint8List.fromList([1, 2, 3])), isNull);
    });

    test('WAV sem dados PCM (data vazio) não é silêncio digital', () {
      final s = WavPeak.parse(_wav(const []))!;
      expect(s.samples, 0);
      expect(s.isDigitalSilence, isFalse);
    });
  });
}
