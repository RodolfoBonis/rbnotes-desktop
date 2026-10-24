import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/features/ai/data/ai_usage.dart';
import 'package:rbnotes/features/ai/data/ai_usage_client.dart';

/// Período pré-definido para o consumo de IA.
enum UsagePeriod { thisMonth, last30Days, previousMonth, custom }

class AiUsageState extends Equatable {
  const AiUsageState({
    this.period = UsagePeriod.thisMonth,
    this.from,
    this.to,
    this.usage,
    this.loading = false,
    this.error,
  });

  final UsagePeriod period;
  final DateTime? from;
  final DateTime? to;
  final AiUsage? usage;
  final bool loading;
  final String? error;

  AiUsageState copyWith({
    UsagePeriod? period,
    DateTime? from,
    DateTime? to,
    AiUsage? usage,
    bool? loading,
    String? error,
    bool clearError = false,
  }) => AiUsageState(
    period: period ?? this.period,
    from: from ?? this.from,
    to: to ?? this.to,
    usage: usage ?? this.usage,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
  );

  @override
  List<Object?> get props => [period, from, to, usage, loading, error];
}

/// Carrega o consumo de IA (`GET /v1/ai/usage`) para o período selecionado.
class AiUsageCubit extends Cubit<AiUsageState> {
  AiUsageCubit({
    required AiUsageClient client,
    this.tz = 'America/Sao_Paulo',
    DateTime Function()? now,
  }) : _client = client,
       _now = now ?? DateTime.now,
       super(const AiUsageState());

  final AiUsageClient _client;
  final String tz;
  final DateTime Function() _now;

  /// Carrega o período padrão (mês atual).
  Future<void> start() => selectPeriod(UsagePeriod.thisMonth);

  Future<void> selectPeriod(UsagePeriod period) async {
    final (from, to) = _rangeFor(period);
    await _load(period: period, from: from, to: to);
  }

  /// Período personalizado (inclusivo).
  Future<void> setCustomRange(DateTime from, DateTime to) async {
    final a = _dateOnly(from.isAfter(to) ? to : from);
    final b = _dateOnly(from.isAfter(to) ? from : to);
    await _load(period: UsagePeriod.custom, from: a, to: b);
  }

  Future<void> refresh() => _load(
    period: state.period,
    from: state.from ?? _rangeFor(state.period).$1,
    to: state.to ?? _rangeFor(state.period).$2,
  );

  Future<void> _load({
    required UsagePeriod period,
    required DateTime from,
    required DateTime to,
  }) async {
    emit(
      state.copyWith(
        period: period,
        from: from,
        to: to,
        loading: true,
        clearError: true,
      ),
    );
    try {
      final usage = await _client.fetch(
        from: _fmt(from),
        to: _fmt(to),
        tz: tz,
      );
      emit(state.copyWith(usage: usage, loading: false));
    } on Object catch (e, st) {
      await AppLogger.error(e, st, reason: 'ai_usage_fetch', category: 'ai');
      emit(state.copyWith(loading: false, error: 'Não foi possível carregar.'));
    }
  }

  (DateTime, DateTime) _rangeFor(UsagePeriod period) {
    final now = _dateOnly(_now());
    return switch (period) {
      UsagePeriod.thisMonth => (DateTime(now.year, now.month), now),
      UsagePeriod.last30Days => (
        now.subtract(const Duration(days: 29)),
        now,
      ),
      UsagePeriod.previousMonth => (
        DateTime(now.year, now.month - 1),
        DateTime(now.year, now.month, 0),
      ),
      UsagePeriod.custom => (
        state.from ?? DateTime(now.year, now.month),
        state.to ?? now,
      ),
    };
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
