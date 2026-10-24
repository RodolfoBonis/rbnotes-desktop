import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:rbnotes/features/security/data/note_key.dart';

/// Guarda a chave AES-256 das notas bloqueadas.
abstract interface class NoteKeyStore {
  /// A chave atual, ou null se ainda não foi gerada/importada.
  Future<NoteKey?> load();

  /// Retorna a chave existente ou gera e persiste uma nova (no primeiro
  /// bloqueio).
  Future<NoteKey> getOrCreate();

  /// Importa uma chave (ex.: da chave de recuperação de outro Mac).
  Future<void> import(NoteKey key);

  /// True se já existe uma chave guardada.
  Future<bool> hasKey();
}

/// Gera uma chave AES-256 com um CSPRNG.
NoteKey generateNoteKey([Random? random]) {
  final rng = random ?? Random.secure();
  final bytes = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    bytes[i] = rng.nextInt(256);
  }
  return NoteKey(bytes);
}

/// Implementação sobre `flutter_secure_storage`, guardando a chave no Keychain
/// **só neste Mac**.
///
/// Decisão do dono (revisão de segurança A3): a chave fica com
/// `first_unlock_this_device` e **sem** `synchronizable`, ou seja, ela não sai
/// deste Mac pelo iCloud Keychain. A cifra protege o sync e o servidor; a chave
/// de recuperação (base32) é o caminho para abrir as notas bloqueadas em outro
/// Mac. Localmente o Touch ID é apenas um gate de UI — o `notes` local guarda o
/// texto claro e a chave fica acessível ao app depois do primeiro desbloqueio.
///
/// Chaves gravadas por versões antigas (quando o item era `synchronizable`) são
/// migradas de forma transparente no primeiro [load]/[getOrCreate]: a chave
/// antiga é relida, regravada com a nova opção e apagada do slot antigo.
class SecureNoteKeyStore implements NoteKeyStore {
  SecureNoteKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _keyName = 'rbnotes.note_lock.aes256';

  /// Chave presa a este Mac (sem iCloud Keychain). `first_unlock_this_device`
  /// mantém a chave acessível ao sync em background depois do 1º desbloqueio.
  static const _mac = MacOsOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );
  static const _ios = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );

  /// Opções legadas (item `synchronizable`), lidas apenas para migrar.
  static const _legacyMac = MacOsOptions(
    synchronizable: true,
    accessibility: KeychainAccessibility.first_unlock,
  );
  static const _legacyIos = IOSOptions(
    synchronizable: true,
    accessibility: KeychainAccessibility.first_unlock,
  );

  @override
  Future<NoteKey?> load() async {
    final current = await _read(_mac, _ios);
    if (current != null) return current;
    // Migração: relê do slot antigo (synchronizable) e reescreve neste Mac.
    final legacy = await _read(_legacyMac, _legacyIos);
    if (legacy == null) return null;
    await _persist(legacy);
    await _deleteLegacy();
    return legacy;
  }

  Future<NoteKey?> _read(MacOsOptions mac, IOSOptions ios) async {
    final raw = await _storage.read(
      key: _keyName,
      mOptions: mac,
      iOptions: ios,
    );
    if (raw == null || raw.isEmpty) return null;
    try {
      return NoteKey(Uint8List.fromList(base64.decode(raw)));
    } on Object {
      return null;
    }
  }

  @override
  Future<bool> hasKey() async => (await load()) != null;

  @override
  Future<NoteKey> getOrCreate() async {
    final existing = await load();
    if (existing != null) return existing;
    final key = generateNoteKey();
    await _persist(key);
    return key;
  }

  @override
  Future<void> import(NoteKey key) => _persist(key);

  Future<void> _persist(NoteKey key) => _storage.write(
    key: _keyName,
    value: base64.encode(key.bytes),
    mOptions: _mac,
    iOptions: _ios,
  );

  Future<void> _deleteLegacy() async {
    try {
      await _storage.delete(
        key: _keyName,
        mOptions: _legacyMac,
        iOptions: _legacyIos,
      );
    } on Object {
      // O slot antigo pode não existir em todas as plataformas; ignore.
    }
  }
}

/// Store em memória para dev/testes (sem Keychain).
class InMemoryNoteKeyStore implements NoteKeyStore {
  InMemoryNoteKeyStore([this._key]);

  NoteKey? _key;

  @override
  Future<NoteKey?> load() async => _key;

  @override
  Future<bool> hasKey() async => _key != null;

  @override
  Future<NoteKey> getOrCreate() async => _key ??= generateNoteKey();

  @override
  Future<void> import(NoteKey key) async => _key = key;
}
