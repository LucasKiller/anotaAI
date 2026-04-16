import 'package:flutter/foundation.dart';

import 'recording_audio_player_service_stub.dart'
    if (dart.library.html) 'recording_audio_player_service_web.dart';

abstract class RecordingAudioPlayerService extends ChangeNotifier {
  bool get isSupported;
  bool get isLoaded;
  bool get isPlaying;
  bool get isLoadingSource;
  Duration get position;
  Duration get duration;

  Future<void> load({
    required List<int> bytes,
    required String mimeType,
  });

  Future<void> togglePlayback();
  Future<void> seek(Duration position);
  Future<void> stop();
}

RecordingAudioPlayerService createRecordingAudioPlayerService() =>
    createRecordingAudioPlayerServiceImpl();
