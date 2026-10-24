import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:rbnotes/core/auth/oidc_client.dart';
import 'package:rbnotes/core/auth/token_store.dart';
import 'package:rbnotes/core/network/api_error.dart';
import 'package:rbnotes/core/network/auth_interceptor.dart';
import 'package:rbnotes/core/network/session_events.dart';
import 'package:rbnotes/core/observability/app_logger.dart';

/// Resposta binária (ex.: chunk de áudio baixado com Range).
class BytesResponse {
  const BytesResponse({
    required this.bytes,
    required this.statusCode,
    required this.contentType,
    required this.contentRange,
    required this.totalLength,
  });

  final Uint8List bytes;
  final int statusCode;
  final String? contentType;
  final String? contentRange;

  /// Tamanho total do recurso, quando dá para inferir (Content-Range ou
  /// Content-Length). Null se desconhecido.
  final int? totalLength;
}

/// Cliente HTTP da `rbnotes-api`.
///
/// Todos os métodos lançam somente [ApiError] — nunca `DioException`. Erros de
/// servidor (5xx) vão ao Sentry com contexto (método/caminho/trace_id), sem PII.
class ApiClient {
  ApiClient({
    required String baseUrl,
    required TokenStore tokens,
    required OidcClient oidc,
    required SessionEvents events,
    Dio? dio,
  }) : _dio = dio ?? Dio() {
    _dio.options = _dio.options.copyWith(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'Accept': 'application/json'},
    );
    _dio.interceptors.add(
      AuthInterceptor(
        tokens: tokens,
        oidc: oidc,
        events: events,
        retryDio: _dio,
      ),
    );
  }

  final Dio _dio;

  Dio get dio => _dio;

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? query,
  }) async => _asJson(
    await _send(
      () => _dio.get<Object?>(path, queryParameters: _clean(query)),
    ),
  );

  Future<Map<String, dynamic>> postJson(String path, {Object? body}) async =>
      _asJson(await _send(() => _dio.post<Object?>(path, data: body)));

  /// POST que devolve o corpo cru (ex.: `202 { id, status }` dos jobs de IA).
  Future<Object?> post(String path, {Object? body}) =>
      _send(() => _dio.post<Object?>(path, data: body));

  /// DELETE (ex.: `DELETE /notes/{id}/audio` → 204, idempotente).
  Future<void> delete(String path) => _send(() => _dio.delete<Object?>(path));

  /// Envia um chunk binário com `Content-Length` obrigatório (áudio).
  Future<Map<String, dynamic>> putBytes(
    String path, {
    required List<int> bytes,
    required Map<String, dynamic> query,
    String contentType = 'application/octet-stream',
  }) async {
    final res = await _send(
      () => _dio.put<Object?>(
        path,
        data: Stream.fromIterable([bytes]),
        queryParameters: _clean(query),
        options: Options(
          contentType: contentType,
          headers: {Headers.contentLengthHeader: bytes.length},
        ),
      ),
    );
    return _asJson(res);
  }

  /// Baixa bytes (áudio), opcionalmente por `Range: bytes=start-end`.
  Future<BytesResponse> getBytes(
    String path, {
    int? rangeStart,
    int? rangeEnd,
  }) async {
    try {
      final headers = <String, dynamic>{};
      if (rangeStart != null) {
        final end = rangeEnd?.toString() ?? '';
        headers['Range'] = 'bytes=$rangeStart-$end';
      }
      final res = await _dio.get<List<int>>(
        path,
        options: Options(
          responseType: ResponseType.bytes,
          headers: headers,
          // 206 é sucesso; não deixar o dio tratar como erro.
          validateStatus: (s) => s != null && s >= 200 && s < 300,
        ),
      );
      final contentRange = res.headers.value('content-range');
      final contentLength = res.headers.value(Headers.contentLengthHeader);
      return BytesResponse(
        bytes: Uint8List.fromList(res.data ?? const []),
        statusCode: res.statusCode ?? 200,
        contentType: res.headers.value(Headers.contentTypeHeader),
        contentRange: contentRange,
        totalLength: _totalFrom(contentRange, contentLength),
      );
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  /// Abre um stream bruto (SSE). O chamador consome `response.data.stream`.
  Future<ResponseBody> openStream(
    String path, {
    Map<String, String>? headers,
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio.get<ResponseBody>(
        path,
        queryParameters: _clean(query),
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': 'text/event-stream', ...?headers},
          receiveTimeout: Duration.zero,
        ),
      );
      final body = res.data;
      if (body == null) throw const ApiError(code: 'stream_empty');
      return body;
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  static int? _totalFrom(String? contentRange, String? contentLength) {
    if (contentRange != null) {
      final slash = contentRange.lastIndexOf('/');
      if (slash >= 0) {
        final total = contentRange.substring(slash + 1).trim();
        if (total != '*') return int.tryParse(total);
      }
    }
    return contentLength == null ? null : int.tryParse(contentLength);
  }

  Map<String, dynamic>? _clean(Map<String, dynamic>? query) {
    if (query == null) return null;
    return {
      for (final e in query.entries)
        if (e.value != null && e.value.toString().isNotEmpty) e.key: e.value,
    };
  }

  Future<Object?> _send(Future<Response<Object?>> Function() call) async {
    try {
      final res = await call();
      return res.data;
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Map<String, dynamic> _asJson(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is List<int>) {
      final decoded = _decodeJson(data);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    if (data == null || data == '' || data == true) return <String, dynamic>{};
    throw const ApiError(code: 'bad_response');
  }

  ApiError _map(DioException e) {
    final status = e.response?.statusCode;
    if (status == null) {
      AppLogger.warning(
        'Falha de rede: ${e.type.name} ${e.requestOptions.path}',
        category: 'http',
      );
      return const ApiError.network();
    }
    var body = e.response?.data;
    if (body is List<int>) body = _decodeJson(body);
    final error = ApiError.fromResponse(status, body);
    if (error.isServer) {
      unawaited(
        AppLogger.error(
          error,
          e.stackTrace,
          reason: '${e.requestOptions.method} ${e.requestOptions.path}',
          category: 'http',
        ),
      );
    } else {
      AppLogger.info(
        'HTTP $status ${e.requestOptions.method} ${e.requestOptions.path}',
        category: 'http',
        data: {'code': error.code, 'trace_id': error.traceId},
      );
    }
    return error;
  }
}

final Converter<List<int>, Object?> _utf8Json = utf8.decoder.fuse(json.decoder);

Object? _decodeJson(List<int> bytes) {
  try {
    return _utf8Json.convert(bytes);
  } on FormatException {
    return null;
  }
}
