import 'dart:async';

import 'package:rbnotes/features/notes/presentation/audio_player_controller.dart';

/// Player de áudio fake para os testes: controla posição e estado manualmente.
class FakeAudioPlayer implements AudioPlayerController {
  final _position = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();

  Duration? loaded;
  final List<Duration> seeks = [];
  bool isPlaying = false;

  @override
  Future<Duration?> load(String path) async {
    return loaded = const Duration(seconds: 10);
  }

  @override
  Future<void> play() async {
    isPlaying = true;
    _playing.add(true);
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
    _playing.add(false);
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    _position.add(position);
  }

  void emitPosition(Duration position) => _position.add(position);

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Future<void> dispose() async {
    await _position.close();
    await _playing.close();
  }
}
