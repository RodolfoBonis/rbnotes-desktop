import 'package:just_audio/just_audio.dart';
import 'package:rbnotes/features/notes/presentation/audio_player_controller.dart';

/// [AudioPlayerController] sobre `just_audio` (AVPlayer no macOS).
class JustAudioPlayer implements AudioPlayerController {
  JustAudioPlayer() : _player = AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<Duration?> load(String path) =>
      _player.setAudioSource(AudioSource.file(path));

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<bool> get playingStream => _player.playingStream;

  @override
  Future<void> dispose() => _player.dispose();
}
