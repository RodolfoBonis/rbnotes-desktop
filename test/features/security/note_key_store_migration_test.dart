import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/features/security/data/note_key.dart';
import 'package:rbnotes/features/security/data/note_key_store.dart';

/// Plataforma fake sensível a `options`: separa o slot "synchronizable"
/// (iCloud Keychain, legado) do slot local deste Mac, para exercitar a migração
/// A3. O slot legado devolve o valor para qualquer `key` até ser apagado.
class _SlotPlatform extends FlutterSecureStoragePlatform {
  _SlotPlatform(this.legacyValue);

  String? legacyValue; // slot synchronizable (legado)
  final Map<String, String> local =
      {}; // slot deste Mac (first_unlock_this_device)
  Map<String, String>? lastLocalWriteOptions;

  bool _legacy(Map<String, String> o) => o['synchronizable'] == 'true';

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => _legacy(options) ? legacyValue : local[key];

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    if (_legacy(options)) {
      legacyValue = value;
    } else {
      lastLocalWriteOptions = options;
      local[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    if (_legacy(options)) {
      legacyValue = null;
    } else {
      local.remove(key);
    }
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => _legacy(options) ? legacyValue != null : local.containsKey(key);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    legacyValue = null;
    local.clear();
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => _legacy(options) ? {} : Map.of(local);
}

void main() {
  final key = NoteKey(Uint8List.fromList(List.generate(32, (i) => i + 3)));
  final b64 = base64.encode(key.bytes);

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'A3: migra a chave do slot synchronizable para o slot deste Mac',
    () async {
      final platform = _SlotPlatform(b64); // só existe no slot legado
      FlutterSecureStoragePlatform.instance = platform;

      final store = SecureNoteKeyStore();
      final loaded = await store.load();

      expect(loaded, isNotNull);
      expect(loaded!.bytes, key.bytes);
      // A chave foi regravada neste Mac e apagada do slot legado.
      expect(platform.legacyValue, isNull);
      expect(platform.local.values.single, b64);
      // E com a acessibilidade só deste Mac, sem iCloud.
      expect(
        platform.lastLocalWriteOptions?['accessibility'],
        'first_unlock_this_device',
      );
      expect(platform.lastLocalWriteOptions?['synchronizable'], 'false');
    },
  );

  test('A3: sem chave legada, load devolve null', () async {
    FlutterSecureStoragePlatform.instance = _SlotPlatform(null);
    expect(await SecureNoteKeyStore().load(), isNull);
  });

  test('A3: depois de migrar, lê direto do slot deste Mac', () async {
    final platform = _SlotPlatform(b64);
    FlutterSecureStoragePlatform.instance = platform;
    final store = SecureNoteKeyStore();
    await store.load(); // migra
    platform.legacyValue = 'LIXO'; // garante que não relê o legado
    final again = await store.load();
    expect(again!.bytes, key.bytes);
  });
}
