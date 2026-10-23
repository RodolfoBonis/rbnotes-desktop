import 'dart:async';

/// Fase atual da IA, para o card "Claude" da sidebar refletir fila/erro/limite.
enum AiPhase { idle, queued, streaming, error, dailyLimit }

/// Barramento do estado da IA. O `ApiAiClient` publica aqui; a UI escuta.
class AiActivity {
  final _controller = StreamController<AiPhase>.broadcast();
  AiPhase _phase = AiPhase.idle;

  AiPhase get phase => _phase;

  Stream<AiPhase> get stream async* {
    yield _phase;
    yield* _controller.stream;
  }

  void set(AiPhase phase) {
    _phase = phase;
    if (!_controller.isClosed) _controller.add(phase);
  }

  Future<void> dispose() => _controller.close();
}
