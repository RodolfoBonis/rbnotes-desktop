import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/features/security/data/note_cipher.dart';
import 'package:rbnotes/features/security/data/note_key.dart';
import 'package:rbnotes/features/security/data/note_key_store.dart';

void main() {
  final keyA = NoteKey(Uint8List.fromList(List.generate(32, (i) => i)));
  final keyB = NoteKey(Uint8List.fromList(List.generate(32, (i) => 255 - i)));

  group('NoteKey', () {
    test('rejects keys that are not 32 bytes', () {
      expect(() => NoteKey(Uint8List(16)), throwsArgumentError);
    });

    test('recovery string round-trips through base32', () {
      final restored = NoteKey.fromRecovery(keyA.recovery);
      expect(restored, keyA);
      expect(restored.bytes, keyA.bytes);
    });

    test('recovery is grouped and case/separator tolerant', () {
      expect(keyA.recovery, contains('-'));
      final messy = keyA.recovery.toLowerCase().replaceAll('-', ' ');
      expect(NoteKey.fromRecovery(messy), keyA);
    });

    test('rejects a recovery string of the wrong length', () {
      expect(() => NoteKey.fromRecovery('AAAA'), throwsFormatException);
    });

    // B15: dígito verificador.
    test('recovery carries a check digit and the old format still reads', () {
      // Novo formato: 52 chars de corpo + 1 dígito = 53 (sem separadores).
      final full = keyA.recovery.replaceAll('-', '');
      expect(full.length, 53);
      // Formato antigo (sem o dígito, só os 52 chars) ainda é aceito.
      final legacy = full.substring(0, 52);
      expect(NoteKey.fromRecovery(legacy), keyA);
    });

    test('a corrupted check digit is rejected', () {
      final full = keyA.recovery.replaceAll('-', '');
      final last = full[52];
      final wrong = last == 'A' ? 'B' : 'A';
      final broken = full.substring(0, 52) + wrong;
      expect(() => NoteKey.fromRecovery(broken), throwsFormatException);
    });
  });

  group('NoteCipher', () {
    test('round-trips a note data map (envelope v2)', () async {
      final cipher = NoteCipher(keyA);
      final data = {
        'title': 'Reunião confidencial',
        'tldr': 'Decisão sobre salários',
        'points': ['A', 'B'],
        'durationMs': 1234,
      };
      final envelope = await cipher.encrypt(data);
      expect(envelope['enc'], 'v2');
      expect(NoteCipher.isEncrypted(envelope), isTrue);
      final decrypted = await cipher.decrypt(envelope);
      expect(decrypted, data);
    });

    test('a wrong key fails to decrypt', () async {
      final envelope = await NoteCipher(keyA).encrypt({'title': 'segredo'});
      expect(
        () => NoteCipher(keyB).decrypt(envelope),
        throwsA(isA<NoteDecryptException>()),
      );
    });

    // A4: AAD liga o ciphertext à sua entidade/id.
    test('a different AAD fails to decrypt (tamper-evident)', () async {
      final cipher = NoteCipher(keyA);
      final envelope = await cipher.encrypt(
        {'title': 'segredo'},
        aad: utf8.encode('rbnotes|note|n1'),
      );
      expect(
        () => cipher.decrypt(envelope, aad: utf8.encode('rbnotes|note|n2')),
        throwsA(isA<NoteDecryptException>()),
      );
      final ok = await cipher.decrypt(
        envelope,
        aad: utf8.encode('rbnotes|note|n1'),
      );
      expect(ok['title'], 'segredo');
    });

    test('v1 (legacy, no AAD) still decrypts', () async {
      // Monta um envelope v1 à mão com a mesma construção AES-GCM sem AAD.
      final v2 = await NoteCipher(keyA).encrypt({'x': 1});
      final v1 = {...v2, 'enc': 'v1'};
      // v1 foi gerado sem AAD, então só decifra sem AAD — e é o que o v1 faz.
      expect(NoteCipher.isEncrypted(v1), isTrue);
      final back = await NoteCipher(keyA).decrypt(v1);
      expect(back, {'x': 1});
    });

    // B18: a mensagem de falha não interpola a exceção crua.
    test('decrypt failure message is generic (no raw exception)', () async {
      final envelope = await NoteCipher(keyA).encrypt({'title': 'segredo'});
      try {
        await NoteCipher(keyB).decrypt(envelope);
        fail('expected NoteDecryptException');
      } on NoteDecryptException catch (e) {
        expect(e.message, 'Falha ao decifrar.');
        expect(e.message.contains('Secret'), isFalse);
      }
    });

    test('the envelope carries no cleartext of the payload', () async {
      final envelope = await NoteCipher(keyA).encrypt({
        'title': 'PALAVRA_SECRETA',
        'tldr': 'conteudo sensivel',
      });
      expect(envelope.keys.toSet(), {'enc', 'nonce', 'ct'});
      final blob = jsonEncode(envelope);
      expect(blob.contains('PALAVRA_SECRETA'), isFalse);
      expect(blob.contains('conteudo'), isFalse);
      final ct = utf8.decode(
        base64.decode(envelope['ct']! as String),
        allowMalformed: true,
      );
      expect(ct.contains('PALAVRA_SECRETA'), isFalse);
    });

    test('rejects a non-encrypted envelope', () async {
      expect(
        () => NoteCipher(keyA).decrypt({'title': 'plain'}),
        throwsA(isA<NoteDecryptException>()),
      );
    });

    test('two encryptions of the same data use different nonces', () async {
      final cipher = NoteCipher(keyA);
      final a = await cipher.encrypt({'x': 1});
      final b = await cipher.encrypt({'x': 1});
      expect(a['nonce'], isNot(b['nonce']));
      expect(a['ct'], isNot(b['ct']));
    });
  });

  group('key stores', () {
    test('InMemoryNoteKeyStore generates and keeps the key', () async {
      final store = InMemoryNoteKeyStore();
      expect(await store.hasKey(), isFalse);
      final key = await store.getOrCreate();
      expect(await store.hasKey(), isTrue);
      expect(await store.getOrCreate(), key);
      expect(await store.load(), key);
    });

    test('import overrides the stored key', () async {
      final store = InMemoryNoteKeyStore();
      await store.getOrCreate();
      await store.import(keyB);
      expect(await store.load(), keyB);
    });

    test('generateNoteKey produces distinct 32-byte keys', () {
      final a = generateNoteKey();
      final b = generateNoteKey();
      expect(a.bytes.length, 32);
      expect(a, isNot(b));
    });
  });
}
