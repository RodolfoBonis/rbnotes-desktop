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

  factory SyncChange.fromJson(Map<String, dynamic> j) => SyncChange(
    entity: j['entity'] as String,
    id: j['id'] as String,
    updatedAt:
        DateTime.tryParse((j['updatedAt'] as String?) ?? '')?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0),
    deleted: (j['deleted'] as bool?) ?? false,
    data: (j['data'] as Map?)?.cast<String, dynamic>() ?? const {},
  );

  final String entity;
  final String id;
  final DateTime updatedAt;
  final bool deleted;
  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() => {
    'entity': entity,
    'id': id,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'deleted': deleted,
    'data': data,
  };

  @override
  List<Object?> get props => [entity, id, updatedAt, deleted, data];
}

class PushResult extends Equatable {
  const PushResult({required this.applied, required this.conflicts});

  factory PushResult.fromJson(Map<String, dynamic> j) => PushResult(
    applied: ((j['applied'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList(),
    conflicts: ((j['conflicts'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SyncChange.fromJson)
        .toList(),
  );

  final List<String> applied;
  final List<SyncChange> conflicts;

  @override
  List<Object?> get props => [applied, conflicts];
}

class PullResult extends Equatable {
  const PullResult({required this.changes, required this.cursor});

  factory PullResult.fromJson(Map<String, dynamic> j) => PullResult(
    changes: ((j['changes'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SyncChange.fromJson)
        .toList(),
    cursor: (j['cursor'] as String?) ?? '0',
  );

  final List<SyncChange> changes;
  final String cursor;

  @override
  List<Object?> get props => [changes, cursor];
}

/// Cliente de sincronização. Local-first via [FakeSyncClient]; a implementação
/// real (`ApiSyncClient`) fala com `/v1/sync/{push,pull}`.
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
