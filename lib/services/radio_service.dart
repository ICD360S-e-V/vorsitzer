import 'package:just_audio/just_audio.dart';
import 'logger_service.dart';

final _log = LoggerService();

/// Radio station definition
class RadioStation {
  final String name;
  final String streamUrl;

  const RadioStation({required this.name, required this.streamUrl});
}

/// Available German radio stations
class RadioStations {
  static const hrInfo = RadioStation(
    name: 'hr-iNFO',
    streamUrl: 'https://dispatcher.rndfnk.com/hr/hrinfo/live/mp3/128/stream.mp3',
  );
}

/// Simple radio streaming service using just_audio
class RadioService {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  final RadioStation _currentStation = RadioStations.hrInfo;

  /// Whether radio is currently playing
  bool get isPlaying => _isPlaying;

  /// Current station name
  String get stationName => _currentStation.name;

  /// Stream of playing state changes
  Stream<bool> get playingStream => _player.playingStream;

  /// Toggle radio on/off
  Future<void> toggle() async {
    if (_isPlaying) {
      await stop();
    } else {
      await play();
    }
  }

  /// Start playing the current station
  Future<void> play() async {
    try {
      await _player.setUrl(_currentStation.streamUrl);
      await _player.play();
      _isPlaying = true;
      _log.info('Radio: Playing ${_currentStation.name}', tag: 'RADIO');
    } catch (e) {
      _isPlaying = false;
      _log.error('Radio: Play failed: $e', tag: 'RADIO');
    }
  }

  /// Stop playback
  Future<void> stop() async {
    try {
      await _player.stop();
      _isPlaying = false;
      _log.info('Radio: Stopped', tag: 'RADIO');
    } catch (e) {
      _log.error('Radio: Stop failed: $e', tag: 'RADIO');
    }
  }

  /// Clean up resources
  void dispose() {
    _player.dispose();
    _isPlaying = false;
  }
}
