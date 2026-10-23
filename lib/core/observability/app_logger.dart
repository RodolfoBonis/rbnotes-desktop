import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:rbnotes/native/rb_native.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Logger da aplicação: console em dev + breadcrumbs/eventos no Sentry.
///
/// Nunca registre o conteúdo das notas nem caminhos de arquivos pessoais.
abstract final class AppLogger {
  static void debug(String message, {String category = 'app'}) {
    developer.log(message, name: category);
  }

  static void info(
    String message, {
    String category = 'app',
    Map<String, Object?>? data,
  }) {
    developer.log(message, name: category);
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
