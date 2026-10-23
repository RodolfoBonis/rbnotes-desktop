import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:rbnotes/core/network/api_error.dart';
import 'package:rbnotes/core/observability/file_log_sink.dart';
import 'package:rbnotes/native/rb_native.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Logger da aplicação: console em dev + breadcrumbs/eventos no Sentry.
///
/// Nunca registre o conteúdo das notas nem caminhos de arquivos pessoais.
abstract final class AppLogger {
  /// Sink de log em arquivo (JSON lines, rotativo). Ligado no bootstrap via
  /// [attachFileSink]; null em testes/quando não há onde escrever. Garante
  /// observabilidade em release, onde `developer.log` some.
  static FileLogSink? _file;

  // Simples atribuição de dependência; um setter aqui seria menos explícito.
  // ignore: use_setters_to_change_properties
  static void attachFileSink(FileLogSink? sink) => _file = sink;

  static void _toFile(
    String level,
    String message, {
    required String category,
    Map<String, Object?>? data,
    Object? error,
    StackTrace? stackTrace,
    String? code,
  }) {
    final sink = _file;
    if (sink == null) return;
    final record = <String, Object?>{
      'ts': DateTime.now().toUtc().toIso8601String(),
      'level': level,
      'category': category,
      'msg': LogRedaction.apply(message),
    };
    if (code != null) record['code'] = code;
    if (error != null) record['error'] = LogRedaction.value(error);
    if (stackTrace != null) {
      record['stack'] = LogRedaction.apply(stackTrace.toString());
    }
    if (data != null && data.isNotEmpty) {
      record['data'] = {
        for (final e in data.entries) e.key: LogRedaction.value(e.value),
      };
    }
    sink.write(record);
  }

  static String? _codeOf(Object? error) {
    if (error is RbNativeException) return error.code;
    if (error is ApiError) return error.code;
    return null;
  }

  static void debug(String message, {String category = 'app'}) {
    developer.log(message, name: category);
  }

  static void info(
    String message, {
    String category = 'app',
    Map<String, Object?>? data,
  }) {
    developer.log(message, name: category);
    _toFile('info', message, category: category, data: data);
    unawaited(
      Sentry.addBreadcrumb(
        Breadcrumb(message: message, category: category, data: data),
      ),
    );
  }

  static void warning(
    String message, {
    String category = 'app',
    Object? error,
  }) {
    developer.log(message, name: category, error: error, level: 900);
    _toFile(
      'warning',
      message,
      category: category,
      error: error,
      code: _codeOf(error),
    );
    unawaited(
      Sentry.addBreadcrumb(
        Breadcrumb(
          message: message,
          category: category,
          level: SentryLevel.warning,
        ),
      ),
    );
  }

  /// Reporta um diagnóstico assíncrono do nativo (falha não-fatal: queda do
  /// áudio do sistema, erro de escrita, event tap desabilitado, watchdog do
  /// ditado) ao Sentry, com o código e o contexto anexados.
  static Future<void> nativeDiagnostic(
    String code,
    String message, {
    String? recordingId,
  }) async {
    developer.log('diagnostic $code: $message', name: 'native', level: 900);
    _toFile(
      'warning',
      'native diagnostic: $message',
      category: 'native',
      code: code,
      data: recordingId == null ? null : {'recordingId': recordingId},
    );
    await Sentry.captureMessage(
      'native diagnostic: $code',
      level: SentryLevel.warning,
      withScope: (scope) async {
        await scope.setTag('native_diagnostic', code);
        await scope.setTag('category', 'native');
        if (recordingId != null) {
          await scope.setTag('recording_id', recordingId);
        }
      },
    );
  }

  static Future<void> error(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    String category = 'app',
  }) async {
    developer.log(
      reason ?? 'error',
      name: category,
      error: error,
      stackTrace: stackTrace,
      level: 1000,
    );
    _toFile(
      'error',
      reason ?? 'error',
      category: category,
      error: error,
      stackTrace: stackTrace,
      code: _codeOf(error),
    );
    if (kDebugMode) {
      debugPrint('[$category] ${reason ?? 'error'}: $error\n$stackTrace');
    }
    await Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: (scope) async {
        if (reason != null) await scope.setTag('reason', reason);
        await scope.setTag('category', category);
        // Erros do contrato nativo carregam o código para agrupar no Sentry.
        if (error is RbNativeException) {
          await scope.setTag('native_code', error.code);
        }
      },
    );
  }
}
