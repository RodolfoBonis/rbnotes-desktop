/// Abstração mínima de player de áudio, para o detalhe sincronizar a
/// transcrição com o tempo. Injeta-se uma implementação `just_audio` em
/// produção e um fake nos testes.
abstract interface class AudioPlayerController {
  /// Carrega o arquivo e retorna sua duração (se conhecida).
  Future<Duration?> load(String path);

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);

  /// Posição corrente (para destacar o segmento atual).
  Stream<Duration> get positionStream;

  /// Está tocando?
  Stream<bool> get playingStream;

  Future<void> dispose();
}
