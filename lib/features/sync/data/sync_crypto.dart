import 'package:rbnotes/features/security/data/note_cipher.dart';
import 'package:rbnotes/features/security/data/note_key_store.dart';
import 'package:rbnotes/features/sync/data/sync_client.dart';
import 'package:rbnotes/features/sync/data/sync_entities.dart';

/// Cifra/decifra o `data` das entidades de notas bloqueadas no sync.
///
/// Push: para notas bloqueadas, `note`, `segment_set`, `note_ai` e
/// `chat_message` sobem com `data = {enc:"v1", nonce, ct}` — nunca texto claro.
/// Tombstones (`deleted`) passam sem cifrar (não carregam conteúdo).
///
/// Pull: um envelope `enc` é decifrado se houver chave; sem chave, o change é
/// devolvido como está (o `SyncLocalStore` grava a nota como "bloqueada em
/// outro Mac" e ignora os filhos cifrados).
///
/// A chave é resolvida *lazy* no [NoteKeyStore] (ela só nasce no primeiro
/// bloqueio ou via importação da chave de recuperação), então o serviço não
/// precisa reiniciar para passar a cifrar.
class SyncCrypto {
  SyncCrypto(this._keyStore);

  final NoteKeyStore _keyStore;
  NoteCipher? _cipher;

  /// Entidades que carregam conteúdo da nota e, portanto, são cifradas.
  static const Set<String> _encryptable = {
    SyncEntities.note,
    SyncEntities.segmentSet,
    SyncEntities.noteAi,
    SyncEntities.chatMessage,
  };

  /// Esquece a chave em cache (ex.: depois de importar a chave de recuperação).
  void invalidate() => _cipher = null;

  Future<NoteCipher?> _resolve() async {
    final cached = _cipher;
    if (cached != null) return cached;
    final key = await _keyStore.load();
    if (key == null) return null;
    return _cipher = NoteCipher(key);
  }

  /// Há uma chave disponível (cacheada) — para a UI saber se consegue decifrar.
  Future<bool> hasKey() async => (await _resolve()) != null;

  String? noteIdOf(SyncChange c) => switch (c.entity) {
    SyncEntities.note || SyncEntities.segmentSet || SyncEntities.noteAi => c.id,
    SyncEntities.chatMessage => c.data['noteId'] as String?,
    _ => null,
  };

  /// Cifra as mudanças de notas em [lockedNoteIds] (push). Requer chave.
  Future<List<SyncChange>> encryptOutgoing(
    List<SyncChange> changes,
    Set<String> lockedNoteIds,
  ) async {
    if (lockedNoteIds.isEmpty) return changes;
    final cipher = await _resolve();
    if (cipher == null) return changes;
    final out = <SyncChange>[];
    for (final c in changes) {
      out.add(await _encryptOne(c, lockedNoteIds, cipher));
    }
    return out;
  }

  Future<SyncChange> _encryptOne(
    SyncChange c,
    Set<String> lockedNoteIds,
    NoteCipher cipher,
  ) async {
    if (c.deleted) return c;
    if (!_encryptable.contains(c.entity)) return c;
    if (NoteCipher.isEncrypted(c.data)) return c;
    final noteId = noteIdOf(c);
    if (noteId == null || !lockedNoteIds.contains(noteId)) return c;
    return c.copyWith(data: await cipher.encrypt(c.data));
  }

  /// Decifra um change cifrado (pull). Sem chave ou em falha, devolve o change
  /// original (ainda com `enc`), para o store decidir o fallback.
  Future<SyncChange> decryptIncoming(SyncChange c) async {
    if (c.deleted || !NoteCipher.isEncrypted(c.data)) return c;
    final cipher = await _resolve();
    if (cipher == null) return c;
    try {
      return c.copyWith(data: await cipher.decrypt(c.data));
    } on NoteDecryptException {
      return c;
    }
  }
}
