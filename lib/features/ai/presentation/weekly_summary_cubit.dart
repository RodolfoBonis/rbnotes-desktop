import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/features/ai/data/ai_client.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/notifications/notification_scheduler.dart';

class WeeklySummaryState extends Equatable {
  const WeeklySummaryState({
    this.summary,
    this.loading = false,
    this.error,
  });

  final WeeklySummary? summary;
  final bool loading;
  final String? error;

  WeeklySummaryState copyWith({
    WeeklySummary? summary,
    bool? loading,
    String? error,
    bool clearError = false,
  }) => WeeklySummaryState(
    summary: summary ?? this.summary,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
  );

  @override
  List<Object?> get props => [summary, loading, error];
}

/// Gera e mostra o resumo semanal (Claude), excluindo notas bloqueadas.
class WeeklySummaryCubit extends Cubit<WeeklySummaryState> {
  WeeklySummaryCubit({
    required AiClient ai,
    required SettingsStore settings,
    this.tz = 'America/Sao_Paulo',
    DateTime Function()? now,
  }) : _ai = ai,
       _settings = settings,
       _now = now ?? DateTime.now,
       super(const WeeklySummaryState());

  final AiClient _ai;
  final SettingsStore _settings;
  final String tz;
  final DateTime Function() _now;

  /// Gera o resumo da semana atual e marca o horário (para a regra de gerar na
  /// primeira abertura se o Mac estava desligado).
  Future<void> generate() async {
    if (state.loading) return;
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final weekStart = NotificationScheduler.weekStartOf(_now());
      final summary = await _ai.weeklySummary(weekStart: weekStart, tz: tz);
      await _settings.setLastWeeklySummaryAt(_now());
      emit(state.copyWith(summary: summary, loading: false));
    } on Object catch (e, st) {
      await AppLogger.error(e, st, reason: 'weekly_summary', category: 'ai');
      emit(
        state.copyWith(loading: false, error: 'Não foi possível gerar agora.'),
      );
    }
  }
}
