import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:rbnotes/features/security/data/note_key.dart';

/// Cifra AES-256-GCM para o `data` das entidades de notas bloqueadas no sync.
///
/// Esta cifra protege o conteúdo **no servidor e no trânsito do sync**: o
/// `data` sobe/desce como envelope opaco e o backend nunca vê o texto claro.
/// Ela **não** é a trava local — localmente o Touch ID é apenas um gate de UI
/// (a chave fica no Keychain deste Mac e o `notes` local guarda o texto claro).
///
/// O envelope segue o contrato (`docs/phase3-contracts.md`):
/// `{"enc":"v2","nonce":"<b64>","ct":"<b64>"}`, onde `ct` é o texto cifrado
/// concatenado com a tag GCM (16 bytes). O conteúdo claro é o JSON canônico da
/// entidade (o mesmo `data` que iria em texto puro).
///
/// **AAD (v2):** o envelope `v2` autentica um *additional authenticated data*
/// ligando o texto cifrado à sua entidade/id (`rbnotes|<entity>|<id>`). Assim,
/// mover o `ct` de uma nota para outra — ou de `note_ai` para `chat_message` —
/// falha na decifragem (a tag GCM não bate). O `v1` (legado, sem AAD) continua
/// aceito na decifragem.
class NoteCipher {
  NoteCipher(this.key);

  final NoteKey key;

  /// Versão gerada por [encrypt]. A decifragem aceita `v1` (legado) e `v2`.
  static const envelopeVersion = 'v2';
  static const _legacyVersion = 'v1';
  static final _algorithm = AesGcm.with256bits();

  /// True se [data] é um envelope cifrado (`enc == "v1" | "v2"`).
  static bool isEncrypted(Map<String, dynamic> data) =>
      data['enc'] == envelopeVersion || data['enc'] == _legacyVersion;

  /// Cifra [data] (texto claro) no envelope `v2` `{enc, nonce, ct}`.
  ///
  /// [aad] (ver doc da classe) é autenticado mas não cifrado; passe os bytes de
  /// `rbnotes|<entity>|<id>` para prender o texto cifrado à entidade.
  Future<Map<String, dynamic>> encrypt(
    Map<String, dynamic> data, {
    List<int> aad = const [],
  }) async {
    final clear = utf8.encode(jsonEncode(data));
    final nonce = _algorithm.newNonce();
    final box = await _algorithm.encrypt(
      clear,
      secretKey: SecretKey(key.bytes),
      nonce: nonce,
      aad: aad,
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
  /// Para `v2`, [aad] precisa ser igual ao usado na cifragem; para `v1`
  /// (legado), [aad] é ignorado. Lança [NoteDecryptException] se a chave
  /// estiver errada, o payload corrompido ou o AAD não bater.
  Future<Map<String, dynamic>> decrypt(
    Map<String, dynamic> envelope, {
    List<int> aad = const [],
  }) async {
    if (!isEncrypted(envelope)) {
      throw const NoteDecryptException('Envelope não cifrado.');
    }
    // `v1` não carregava AAD; `v2` autentica o AAD fornecido.
    final effectiveAad = envelope['enc'] == _legacyVersion
        ? const <int>[]
        : aad;
    try {
      final nonce = base64.decode(envelope['nonce'] as String);
      final ctAndMac = base64.decode(envelope['ct'] as String);
      final macBytes = ctAndMac.sublist(ctAndMac.length - 16);
      final cipherText = ctAndMac.sublist(0, ctAndMac.length - 16);
      final clear = await _algorithm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
        secretKey: SecretKey(key.bytes),
        aad: effectiveAad,
      );
      final decoded = jsonDecode(utf8.decode(clear));
      return (decoded as Map).cast<String, dynamic>();
    } on NoteDecryptException {
      rethrow;
    } on Object {
      // Não interpolamos a exceção crua: ela pode carregar bytes do payload.
      throw const NoteDecryptException('Falha ao decifrar.');
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
