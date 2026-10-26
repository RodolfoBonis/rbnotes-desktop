import 'dart:io';
import 'dart:typed_data';

/// Resultado de uma leitura rápida de pico de um arquivo WAV PCM.
class WavSignal {
  const WavSignal({required this.peak, required this.samples});

  /// Pico absoluto normalizado (0..1). `0` = silêncio digital (todos os samples
  /// exatamente zero); `null` significa indeterminado (arquivo ilegível).
  final double peak;

  /// Quantidade de samples lidos (0 quando o arquivo não tinha dados PCM).
  final int samples;

  /// Silêncio digital: havia samples e **todos** eram exatamente zero.
  /// Diferente de ambiente baixo (pico pequeno porém > 0). É esse caso — o
  /// áudio zerado entregue pelo macOS quando o TCC do microfone deixou de
  /// valer — que marca a nota como falha em vez de concluí-la vazia.
  bool get isDigitalSilence => samples > 0 && peak == 0;
}

/// Leitor mínimo de pico de WAV PCM (sem dependências nativas), usado para
/// detectar silêncio digital pós-gravação.
///
/// Suporta PCM inteiro de 8/16/24/32 bits e float de 32 bits (formatos que o
/// plugin `rbnotes_native` pode gravar). Retorna `null` quando o arquivo não é
/// um WAV PCM legível — nesse caso o chamador não deve concluir que houve
/// silêncio (evita falso-positivo de falha).
abstract final class WavPeak {
  /// Lê [path] e devolve o pico, ou `null` se o arquivo não existe ou não é um
  /// WAV PCM reconhecível.
  static Future<WavSignal?> read(String path) async {
    final file = File(path);
    if (!file.existsSync()) return null;
    try {
      final bytes = await file.readAsBytes();
      return parse(bytes);
    } on Object {
      return null;
    }
  }

  /// Variante síncrona sobre bytes já carregados (facilita os testes).
  static WavSignal? parse(Uint8List bytes) {
    if (bytes.length < 44) return null;
    final data = ByteData.sublistView(bytes);
    // Cabeçalho RIFF/WAVE.
    if (_tag(bytes, 0) != 'RIFF' || _tag(bytes, 8) != 'WAVE') return null;

    var offset = 12;
    int? bitsPerSample;
    var isFloat = false;
    while (offset + 8 <= bytes.length) {
      final chunkId = _tag(bytes, offset);
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      final body = offset + 8;
      if (chunkId == 'fmt ' && body + 16 <= bytes.length) {
        final format = data.getUint16(body, Endian.little);
        isFloat = format == 3; // WAVE_FORMAT_IEEE_FLOAT
        bitsPerSample = data.getUint16(body + 14, Endian.little);
      } else if (chunkId == 'data') {
        if (bitsPerSample == null) return null;
        final end = (body + chunkSize <= bytes.length)
            ? body + chunkSize
            : bytes.length;
        return _scan(data, body, end, bitsPerSample, isFloat: isFloat);
      }
      // Chunks têm padding par; avança respeitando isso.
      offset = body + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }
    return null;
  }

  static WavSignal _scan(
    ByteData data,
    int start,
    int end,
    int bits, {
    required bool isFloat,
  }) {
    final bytesPerSample = bits ~/ 8;
    if (bytesPerSample == 0) return const WavSignal(peak: 0, samples: 0);
    var peak = 0.0;
    var count = 0;
    for (var i = start; i + bytesPerSample <= end; i += bytesPerSample) {
      final double norm;
      switch (bits) {
        case 8:
          // PCM de 8 bits é unsigned (0..255), centro em 128.
          norm = (data.getUint8(i) - 128) / 128.0;
        case 16:
          norm = data.getInt16(i, Endian.little) / 32768.0;
        case 24:
          final b0 = data.getUint8(i);
          final b1 = data.getUint8(i + 1);
          final b2 = data.getUint8(i + 2);
          var v = b0 | (b1 << 8) | (b2 << 16);
          if (v & 0x800000 != 0) v |= ~0xFFFFFF; // extensão de sinal
          norm = v / 8388608.0;
        case 32:
          norm = isFloat
              ? data.getFloat32(i, Endian.little)
              : data.getInt32(i, Endian.little) / 2147483648.0;
        default:
          return WavSignal(peak: peak, samples: count);
      }
      final abs = norm.abs();
      if (abs > peak) peak = abs;
      count++;
    }
    return WavSignal(peak: peak.clamp(0.0, 1.0), samples: count);
  }

  static String _tag(Uint8List bytes, int at) =>
      String.fromCharCodes(bytes.sublist(at, at + 4));
}
