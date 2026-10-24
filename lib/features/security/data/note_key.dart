import 'package:flutter/foundation.dart';

/// Chave AES-256 (32 bytes) usada para cifrar as notas bloqueadas no sync.
///
/// Expõe a "chave de recuperação" como base32 (RFC 4648, sem padding) agrupada
/// em blocos de 4 para o dono conseguir anotar/digitar e importar em outro Mac.
/// O formato novo acrescenta um **dígito verificador** (um caractere base32 ao
/// final) para pegar erros de digitação cedo; o formato antigo (sem o dígito)
/// continua sendo lido.
@immutable
class NoteKey {
  NoteKey(this.bytes) {
    if (bytes.length != 32) {
      throw ArgumentError('A chave precisa ter 32 bytes (AES-256).');
    }
  }

  /// Decodifica uma chave de recuperação (base32, com ou sem separadores, com
  /// ou sem dígito verificador).
  factory NoteKey.fromRecovery(String recovery) {
    final cleaned = _clean(recovery);
    // 52 chars = 32 bytes sem dígito (formato antigo); 53 = com dígito.
    String body;
    if (cleaned.length == _bodyLen + 1) {
      body = cleaned.substring(0, _bodyLen);
      final check = cleaned.substring(_bodyLen);
      final bytes = _base32Decode(body);
      if (bytes.length != 32 || _checkChar(bytes) != check) {
        throw const FormatException('Chave de recuperação inválida.');
      }
      return NoteKey(bytes);
    }
    final bytes = _base32Decode(body = cleaned);
    if (bytes.length != 32) {
      throw const FormatException('Chave de recuperação inválida.');
    }
    return NoteKey(bytes);
  }

  final Uint8List bytes;

  /// Nº de caracteres base32 de uma chave de 32 bytes (260 bits ⌈/5⌉ = 52).
  static const _bodyLen = 52;

  /// A chave em base32 agrupada (ex.: `ABCD-EFGH-…-X`), com dígito verificador.
  String get recovery {
    final raw = _base32Encode(bytes) + _checkChar(bytes);
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

  static String _clean(String input) =>
      input.toUpperCase().replaceAll(RegExp('[^A-Z2-7]'), '');

  /// Dígito verificador: soma dos bytes (mod 32) mapeada ao alfabeto base32.
  static String _checkChar(Uint8List bytes) {
    var sum = 0;
    for (final b in bytes) {
      sum = (sum + b) & 0x7fffffff;
    }
    return _alphabet[sum % 32];
  }

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
    final cleaned = _clean(input);
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
