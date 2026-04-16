import 'audio_recorder_service_stub.dart'
    if (dart.library.html) 'audio_recorder_service_web.dart';

class RecordedAudioCapture {
  RecordedAudioCapture({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final List<int> bytes;
  final String fileName;
  final String mimeType;
}

abstract class AudioRecorderService {
  bool get isSupported;

  Future<void> start();
  Future<void> pause();
  Future<void> resume();
  Future<RecordedAudioCapture> stop();
  Future<void> cancel();
}

AudioRecorderService createAudioRecorderService() =>
    createAudioRecorderServiceImpl();
