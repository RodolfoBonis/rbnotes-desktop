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
/// como item **synchronizable** (iCloud Keychain) para os outros Macs do dono.
///
/// Se a sincronização via iCloud exigir um `keychain-access-groups`
/// (documentado no README), o item cai para o Keychain local automaticamente —
/// o dono então usa a "chave de recuperação" para levá-la a outro Mac.
class SecureNoteKeyStore implements NoteKeyStore {
  SecureNoteKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _keyName = 'rbnotes.note_lock.aes256';

  /// `synchronizable: true` liga o iCloud Keychain. `first_unlock` mantém a
  /// chave acessível para o sync em background depois do primeiro desbloqueio.
  static const _mac = MacOsOptions(
    synchronizable: true,
    accessibility: KeychainAccessibility.first_unlock,
  );
  static const _ios = IOSOptions(
    synchronizable: true,
    accessibility: KeychainAccessibility.first_unlock,
  );

  @override
  Future<NoteKey?> load() async {
    final raw = await _storage.read(
      key: _keyName,
      mOptions: _mac,
      iOptions: _ios,
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
