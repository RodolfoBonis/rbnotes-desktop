import 'package:equatable/equatable.dart';

enum SyncPhase { idle, syncing, offline, error, disabled }

/// Estado do sync para a UI (sidebar/aba Conta).
class SyncStatus extends Equatable {
  const SyncStatus({
    this.phase = SyncPhase.idle,
    this.lastSyncAt,
    this.message,
    this.pendingCount = 0,
  });

  final SyncPhase phase;
  final DateTime? lastSyncAt;
  final String? message;

  /// Alterações locais ainda não confirmadas no servidor (visível na aba Conta
  /// e no indicador da sidebar). Zera após um ciclo bem-sucedido.
  final int pendingCount;

  bool get isSyncing => phase == SyncPhase.syncing;
  bool get hasError => phase == SyncPhase.error || phase == SyncPhase.offline;
  bool get hasPending => pendingCount > 0;

  SyncStatus copyWith({
    SyncPhase? phase,
    DateTime? lastSyncAt,
    String? message,
    bool clearMessage = false,
    int? pendingCount,
  }) => SyncStatus(
    phase: phase ?? this.phase,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    message: clearMessage ? null : (message ?? this.message),
    pendingCount: pendingCount ?? this.pendingCount,
  );

  @override
  List<Object?> get props => [phase, lastSyncAt, message, pendingCount];
}
