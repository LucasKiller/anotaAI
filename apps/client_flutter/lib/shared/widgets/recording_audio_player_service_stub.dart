import 'recording_audio_player_service.dart';

class UnsupportedRecordingAudioPlayerService
    extends RecordingAudioPlayerService {
  @override
  bool get isSupported => false;

  @override
  bool get isLoaded => false;

  @override
  bool get isLoadingSource => false;

  @override
  bool get isPlaying => false;

  @override
  Duration get duration => Duration.zero;

  @override
  Duration get position => Duration.zero;

  @override
  Future<void> load({
    required List<int> bytes,
    required String mimeType,
  }) {
    throw UnsupportedError('Playback de audio nao suportado nesta plataforma.');
  }

  @override
  Future<void> seek(Duration position) {
    throw UnsupportedError('Playback de audio nao suportado nesta plataforma.');
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> togglePlayback() {
    throw UnsupportedError('Playback de audio nao suportado nesta plataforma.');
  }
}

RecordingAudioPlayerService createRecordingAudioPlayerServiceImpl() =>
    UnsupportedRecordingAudioPlayerService();
