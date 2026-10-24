import 'package:rbnotes/core/network/api_client.dart';
import 'package:rbnotes/features/ai/data/ai_usage.dart';

/// Lê o consumo de IA do usuário (`GET /v1/ai/usage`).
// ignore: one_member_abstracts
abstract interface class AiUsageClient {
  /// [from]/[to] inclusivos (YYYY-MM-DD); [tz] é um IANA (ex.:
  /// `America/Sao_Paulo`). O servidor devolve totais, série diária por kind e a
  /// cota de 24 h.
  Future<AiUsage> fetch({
    required String from,
    required String to,
    required String tz,
  });
}

/// Implementação real sobre a `rbnotes-api`.
class ApiAiUsageClient implements AiUsageClient {
  ApiAiUsageClient(this._api);

  final ApiClient _api;

  @override
  Future<AiUsage> fetch({
    required String from,
    required String to,
    required String tz,
  }) async {
    final json = await _api.getJson(
      '/ai/usage',
      query: {'from': from, 'to': to, 'tz': tz},
    );
    return AiUsage.fromJson(json);
  }
}
