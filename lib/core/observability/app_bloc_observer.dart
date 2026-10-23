import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:rbnotes/core/observability/app_logger.dart';

/// Envia erros não tratados de blocs/cubits ao Sentry.
class AppBlocObserver extends BlocObserver {
  const AppBlocObserver();

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    unawaited(
      AppLogger.error(
        error,
        stackTrace,
        reason: bloc.runtimeType.toString(),
        category: 'bloc',
      ),
    );
    super.onError(bloc, error, stackTrace);
  }
}
