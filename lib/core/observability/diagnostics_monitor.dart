import 'dart:async';

import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/native/rb_native.dart';

/// Assina o stream permanente de diagnósticos do nativo (falhas assíncronas e
/// não-fatais) uma única vez, reporta cada uma ao Sentry com contexto e as
/// re-publica em [stream].
///
/// Fonte única de verdade: o contrato nativo assume **um stream ativo por canal
/// por vez**, então quem precisa dos diagnósticos (ex.: a UI de gravação) ouve
/// [stream], não `RbNative.diagnostics()` diretamente.
class DiagnosticsMonitor {
  DiagnosticsMonitor(this._native);

  final RbNative _native;
  StreamSubscription<NativeDiagnostic>? _sub;
  final _controller = StreamController<NativeDiagnostic>.broadcast();

  /// Diagnósticos re-publicados (ex.: a UI de gravação observa daqui).
  Stream<NativeDiagnostic> get stream => _controller.stream;

  void start() {
    _sub ??= _native.diagnostics().listen(
      (d) {
        unawaited(
          AppLogger.nativeDiagnostic(
            d.code,
            d.message,
            recordingId: d.recordingId,
          ),
        );
        if (!_controller.isClosed) _controller.add(d);
      },
      onError: (Object e, StackTrace st) {
        unawaited(
          AppLogger.error(
            e,
            st,
            reason: 'diagnostics_stream',
            category: 'native',
          ),
        );
      },
    );
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    await _controller.close();
  }
}
