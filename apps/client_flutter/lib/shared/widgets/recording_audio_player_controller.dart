import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../features/recordings/recordings_service.dart';
import 'audio_waveform_builder.dart';
import 'recording_audio_player_service.dart';

class RecordingAudioPlayerController extends ChangeNotifier {
  RecordingAudioPlayerController({
    RecordingsService? recordingsService,
    RecordingAudioPlayerService? playerService,
  })  : _recordingsService = recordingsService ?? RecordingsService(),
        _playerService = playerService ?? createRecordingAudioPlayerService() {
    _playerService.addListener(_forwardServiceChange);
  }

  final RecordingsService _recordingsService;
  final RecordingAudioPlayerService _playerService;

  bool _isFetchingAudio = false;
  String? _errorMessage;
  String? _loadedFileName;
  String? _loadedRecordingId;
  List<double> _waveformSamples = const <double>[];

  bool get isSupported => _playerService.isSupported;
  bool get isLoaded => _playerService.isLoaded;
  bool get isPlaying => _playerService.isPlaying;
  bool get isLoadingSource => _playerService.isLoadingSource;
  bool get isFetchingAudio => _isFetchingAudio;
  Duration get position => _playerService.position;
  Duration get duration => _playerService.duration;
  String? get errorMessage => _errorMessage;
  String? get loadedFileName => _loadedFileName;
  String? get loadedRecordingId => _loadedRecordingId;
  List<double> get waveformSamples => _waveformSamples;

  Future<void> loadForRecording({
    required String accessToken,
    required String recordingId,
  }) async {
    if (_isFetchingAudio) {
      return;
    }

    _isFetchingAudio = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final audio = await _recordingsService.downloadAudio(
        accessToken: accessToken,
        recordingId: recordingId,
      );
      await _playerService.load(
        bytes: audio.bytes,
        mimeType: audio.mimeType,
      );
      _waveformSamples = await buildWaveformSamples(audio.bytes);
      _loadedFileName = audio.fileName;
      _loadedRecordingId = recordingId;
    } on ApiException catch (error) {
      _errorMessage = error.message;
      rethrow;
    } catch (error) {
      _errorMessage = error
          .toString()
          .replaceFirst('Exception: ', '')
          .replaceFirst('StateError: ', '');
      rethrow;
    } finally {
      _isFetchingAudio = false;
      notifyListeners();
    }
  }

  Future<void> togglePlayback() => _playerService.togglePlayback();

  Future<void> seek(Duration position) => _playerService.seek(position);

  Future<void> stop() => _playerService.stop();

  void reset() {
    _playerService.stop();
    _errorMessage = null;
    _loadedFileName = null;
    _loadedRecordingId = null;
    _waveformSamples = const <double>[];
    notifyListeners();
  }

  @override
  void dispose() {
    _playerService.removeListener(_forwardServiceChange);
    _playerService.dispose();
    super.dispose();
  }

  void _forwardServiceChange() {
    notifyListeners();
  }
}
