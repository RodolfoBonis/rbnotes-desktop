/// Erro de um pedido de IA (falha do job, stream com `error`, etc.).
class AiException implements Exception {
  const AiException(this.message);
  final String message;

  @override
  String toString() => 'AiException: $message';
}

/// Cota diária de IA atingida (`429 ai_daily_limit`).
class AiDailyLimitException extends AiException {
  const AiDailyLimitException([
    super.message = 'Limite diário de IA atingido.',
  ]);
}
