import 'dart:async';

import 'package:drift/drift.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/sync/data/sync_service.dart';

/// Gatilho central de sincronização: observa as escritas no banco e pede um
/// `requestSync` (debounced) a cada mutação local de uma entidade
/// sincronizável.
///
/// Centralizar aqui evita espalhar `requestSync()` por todos os repositórios e
/// garante que **qualquer** alteração relevante (título, pasta, favorito,
/// ações, coleções, vocabulário, chat, note_ai, segmentos, exclusões) dispare
/// o sync sem depender só da cadência de 2 min. `requestSync` já respeita
/// "Sincronizar" desligado e é idempotente, então o eco de um pull não causa
/// laço (uma vez convergido, não há escrita nessas tabelas → sem novo gatilho).
///
/// Tabelas de infraestrutura (`sync_meta`, FTS) e não sincronizáveis (tags,
/// diário) ficam de fora de propósito, para não gerar sync espúrio.
class SyncTrigger {
  SyncTrigger({required AppDatabase db, required SyncService sync})
    : _db = db,
      _sync = sync;

  final AppDatabase _db;
  final SyncService _sync;

  StreamSubscription<Set<TableUpdate>>? _sub;

  /// Nomes de tabela que correspondem às entidades do contrato de sync.
  static const Set<String> _syncable = {
    'notes',
    'transcript_segments',
    'folders',
    'actions',
    'collections',
    'vocabulary',
    'chat_messages',
    'note_ai',
  };

  /// Começa a observar. Idempotente.
  void start() {
    _sub ??= _db
        .tableUpdates(
          TableUpdateQuery.allOf([
            for (final t in _syncable) TableUpdateQuery.onTableName(t),
          ]),
        )
        .listen((_) {
          // Ignora o eco das escritas que o próprio pull/push aplica — senão o
          // sync se auto-dispara em loop (ver SyncService.isApplyingRemote).
          if (_sync.isApplyingRemote) return;
          _sync.requestSync();
        });
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
