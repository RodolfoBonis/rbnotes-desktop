import 'package:equatable/equatable.dart';

/// Erro de um campo num problem+json de validação (`errors[]`).
class ApiFieldError extends Equatable {
  const ApiFieldError({required this.field, required this.code});

  factory ApiFieldError.fromJson(Map<String, dynamic> j) => ApiFieldError(
    field: (j['field'] as String?) ?? '',
    code: (j['code'] as String?) ?? '',
  );

  final String field;
  final String code;

  @override
  List<Object?> get props => [field, code];
}

/// Erro da `rbnotes-api`, sempre mapeado a partir de `application/problem+json`
/// (RFC 7807). Todos os métodos do `ApiClient` lançam apenas [ApiError] — nunca
/// `DioException` — para a camada de feature tratar por `code`/`statusCode`.
class ApiError implements Exception {
  const ApiError({
    this.statusCode,
    this.code,
    String? message,
    this.detail,
    this.traceId,
    this.fieldErrors = const [],
  }) : _message = message;

  /// Monta o erro a partir do status e do corpo (problem+json ou outro).
  factory ApiError.fromResponse(int? statusCode, Object? body) {
    String? code;
    String? title;
    String? detail;
    String? traceId;
    var fields = const <ApiFieldError>[];
    if (body is Map<String, dynamic>) {
      code = body['code'] as String?;
      title = body['title'] as String?;
      detail = body['detail'] as String?;
      traceId = body['trace_id'] as String?;
      final errs = body['errors'];
      if (errs is List) {
        fields = errs
            .whereType<Map<String, dynamic>>()
            .map(ApiFieldError.fromJson)
            .toList();
      }
    }
    return ApiError(
      statusCode: statusCode,
      code: code,
      message: title,
      detail: detail,
      traceId: traceId,
      fieldErrors: fields,
    );
  }

  /// Sem resposta HTTP (timeout, offline, DNS…).
  const ApiError.network()
    : statusCode = null,
      code = 'network',
      _message = 'Sem conexão com o servidor.',
      detail = null,
      traceId = null,
      fieldErrors = const [];

  final int? statusCode;

  /// `code` do problem+json (ex.: `not_allowed`, `ai_daily_limit`).
  final String? code;

  final String? _message;
  final String? detail;
  final String? traceId;
  final List<ApiFieldError> fieldErrors;

  /// Rede indisponível (sem status HTTP).
  bool get isNetwork => statusCode == null;
  bool get isUnauthorized => statusCode == 401;

  /// Conta sem acesso ao RbNotes (allowlist do backend).
  bool get isAccessDenied => statusCode == 403 && code == 'not_allowed';
  bool get isForbidden => statusCode == 403;

  /// Cota diária de IA atingida.
  bool get isAiDailyLimit => statusCode == 429 && code == 'ai_daily_limit';
  bool get isRateLimited => statusCode == 429;
  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;
  bool get isServer => (statusCode ?? 0) >= 500;

  String get message => _message ?? detail ?? _defaultMessage(statusCode, code);

  static String _defaultMessage(int? status, String? code) {
    if (status == null) return 'Sem conexão com o servidor.';
    if (status == 401) return 'Sessão expirada.';
    if (status == 403 && code == 'not_allowed') {
      return 'Esta conta não tem acesso ao RbNotes.';
    }
    if (status == 403) return 'Acesso negado.';
    if (status == 429) return 'Limite de uso atingido.';
    if (status >= 500) return 'Erro no servidor. Tente de novo.';
    return 'Não foi possível concluir a operação.';
  }

  @override
  String toString() =>
      'ApiError(status: $statusCode, code: $code, message: $message)';
}
