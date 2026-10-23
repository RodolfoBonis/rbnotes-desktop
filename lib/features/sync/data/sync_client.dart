import 'package:equatable/equatable.dart';

/// Uma mudança de entidade para o sync offline-first (LWW por `updatedAt`),
/// espelhando `Change` do `docs/backend-contract.md`.
class SyncChange extends Equatable {
  const SyncChange({
    required this.entity,
    required this.id,
    required this.updatedAt,
    required this.deleted,
    required this.data,
  });

  final String entity;
  final String id;
  final DateTime updatedAt;
  final bool deleted;
  final Map<String, dynamic> data;

  @override
  List<Object?> get props => [entity, id, updatedAt, deleted, data];
}

class PushResult extends Equatable {
  const PushResult({required this.applied, required this.conflicts});

  final List<String> applied;
  final List<SyncChange> conflicts;

  @override
  List<Object?> get props => [applied, conflicts];
}

class PullResult extends Equatable {
  const PullResult({required this.changes, required this.cursor});

  final List<SyncChange> changes;
  final String cursor;

  @override
  List<Object?> get props => [changes, cursor];
}

/// Cliente de sincronização. Local-first via [FakeSyncClient]; a implementação
/// real fala com `/v1/sync/{push,pull}` e é injetada na fase de integração.
abstract interface class SyncClient {
  Future<PushResult> push(List<SyncChange> changes);
  Future<PullResult> pull({String? since});
}

/// Sync de mentira: não envia nada e não recebe nada (modo local-first).
class FakeSyncClient implements SyncClient {
  const FakeSyncClient();

  @override
  Future<PullResult> pull({String? since}) async =>
      PullResult(changes: const [], cursor: since ?? '0');

  @override
  Future<PushResult> push(List<SyncChange> changes) async => PushResult(
    applied: changes.map((c) => c.id).toList(),
    conflicts: const [],
  );
}
