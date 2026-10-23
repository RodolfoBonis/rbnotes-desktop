import 'package:equatable/equatable.dart';

enum SyncPhase { idle, syncing, offline, error, disabled }

/// Estado do sync para a UI (sidebar/aba Conta).
class SyncStatus extends Equatable {
  const SyncStatus({
    this.phase = SyncPhase.idle,
    this.lastSyncAt,
    this.message,
  });

  final SyncPhase phase;
  final DateTime? lastSyncAt;
  final String? message;

  bool get isSyncing => phase == SyncPhase.syncing;
  bool get hasError => phase == SyncPhase.error || phase == SyncPhase.offline;

  SyncStatus copyWith({
    SyncPhase? phase,
    DateTime? lastSyncAt,
    String? message,
    bool clearMessage = false,
  }) => SyncStatus(
    phase: phase ?? this.phase,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    message: clearMessage ? null : (message ?? this.message),
  );

  @override
  List<Object?> get props => [phase, lastSyncAt, message];
}
