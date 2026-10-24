import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:rbnotes/features/security/data/note_key.dart';

/// Cifra AES-256-GCM para o `data` das entidades de notas bloqueadas no sync.
///
/// O envelope segue o contrato (`docs/phase3-contracts.md`):
/// `{"enc":"v1","nonce":"<b64>","ct":"<b64>"}`, onde `ct` é o texto cifrado
/// concatenado com a tag GCM (16 bytes). O conteúdo claro é o JSON canônico da
/// entidade (o mesmo `data` que iria em texto puro).
class NoteCipher {
  NoteCipher(this.key);

  final NoteKey key;
  static const envelopeVersion = 'v1';
  static final _algorithm = AesGcm.with256bits();

  /// True se [data] é um envelope cifrado (`enc == "v1"`).
  static bool isEncrypted(Map<String, dynamic> data) => data['enc'] == 'v1';

  /// Cifra [data] (o `data` em texto claro) no envelope `{enc, nonce, ct}`.
  Future<Map<String, dynamic>> encrypt(Map<String, dynamic> data) async {
    final clear = utf8.encode(jsonEncode(data));
    final nonce = _algorithm.newNonce();
    final box = await _algorithm.encrypt(
      clear,
      secretKey: SecretKey(key.bytes),
      nonce: nonce,
    );
    final ct = Uint8List(box.cipherText.length + box.mac.bytes.length)
      ..setAll(0, box.cipherText)
      ..setAll(box.cipherText.length, box.mac.bytes);
    return {
      'enc': envelopeVersion,
      'nonce': base64.encode(nonce),
      'ct': base64.encode(ct),
    };
  }

  /// Decifra um envelope `{enc, nonce, ct}` de volta ao `data` em texto claro.
  ///
  /// Lança [NoteDecryptException] se a chave estiver errada/corrompida.
  Future<Map<String, dynamic>> decrypt(Map<String, dynamic> envelope) async {
    if (!isEncrypted(envelope)) {
      throw const NoteDecryptException('Envelope não cifrado.');
    }
    try {
      final nonce = base64.decode(envelope['nonce'] as String);
      final ctAndMac = base64.decode(envelope['ct'] as String);
      final macBytes = ctAndMac.sublist(ctAndMac.length - 16);
      final cipherText = ctAndMac.sublist(0, ctAndMac.length - 16);
      final clear = await _algorithm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
        secretKey: SecretKey(key.bytes),
      );
      final decoded = jsonDecode(utf8.decode(clear));
      return (decoded as Map).cast<String, dynamic>();
    } on NoteDecryptException {
      rethrow;
    } on Object catch (e) {
      throw NoteDecryptException('Falha ao decifrar: $e');
    }
  }
}

/// A decifragem falhou (chave errada, payload corrompido).
class NoteDecryptException implements Exception {
  const NoteDecryptException(this.message);
  final String message;

  @override
  String toString() => 'NoteDecryptException: $message';
}
