import 'package:flutter/foundation.dart';

/// Chave AES-256 (32 bytes) usada para cifrar as notas bloqueadas no sync.
///
/// Expõe a "chave de recuperação" como base32 (RFC 4648, sem padding) agrupada
/// em blocos de 4 para o dono conseguir anotar/digitar e importar em outro Mac.
@immutable
class NoteKey {
  NoteKey(this.bytes) {
    if (bytes.length != 32) {
      throw ArgumentError('A chave precisa ter 32 bytes (AES-256).');
    }
  }

  /// Decodifica uma chave de recuperação (base32, com ou sem separadores).
  factory NoteKey.fromRecovery(String recovery) {
    final bytes = _base32Decode(recovery);
    if (bytes.length != 32) {
      throw const FormatException('Chave de recuperação inválida.');
    }
    return NoteKey(bytes);
  }

  final Uint8List bytes;

  /// A chave em base32 agrupada (ex.: `ABCD-EFGH-…`).
  String get recovery {
    final raw = _base32Encode(bytes);
    final groups = <String>[];
    for (var i = 0; i < raw.length; i += 4) {
      groups.add(raw.substring(i, (i + 4).clamp(0, raw.length)));
    }
    return groups.join('-');
  }

  @override
  bool operator ==(Object other) =>
      other is NoteKey && _constTimeEq(other.bytes, bytes);

  @override
  int get hashCode => Object.hashAll(bytes);

  static bool _constTimeEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  // ---- base32 (RFC 4648, alfabeto maiúsculo, sem padding) ----

  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static String _base32Encode(Uint8List data) {
    final out = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final byte in data) {
      buffer = (buffer << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        out.write(_alphabet[(buffer >> bits) & 0x1f]);
      }
    }
    if (bits > 0) {
      out.write(_alphabet[(buffer << (5 - bits)) & 0x1f]);
    }
    return out.toString();
  }

  static Uint8List _base32Decode(String input) {
    final cleaned = input.toUpperCase().replaceAll(RegExp('[^A-Z2-7]'), '');
    final out = <int>[];
    var buffer = 0;
    var bits = 0;
    for (final ch in cleaned.split('')) {
      final value = _alphabet.indexOf(ch);
      if (value < 0) throw const FormatException('Caractere base32 inválido.');
      buffer = (buffer << 5) | value;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((buffer >> bits) & 0xff);
      }
    }
    return Uint8List.fromList(out);
  }
}
