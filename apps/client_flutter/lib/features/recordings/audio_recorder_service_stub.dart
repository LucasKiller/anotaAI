import 'audio_recorder_service.dart';

class UnsupportedAudioRecorderService implements AudioRecorderService {
  @override
  bool get isSupported => false;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> pause() async {
    throw UnsupportedError('Gravacao ao vivo nao suportada nesta plataforma.');
  }

  @override
  Future<void> resume() async {
    throw UnsupportedError('Gravacao ao vivo nao suportada nesta plataforma.');
  }

  @override
  Future<void> start() async {
    throw UnsupportedError('Gravacao ao vivo nao suportada nesta plataforma.');
  }

  @override
  Future<RecordedAudioCapture> stop() {
    throw UnsupportedError('Gravacao ao vivo nao suportada nesta plataforma.');
  }
}

AudioRecorderService createAudioRecorderServiceImpl() =>
    UnsupportedAudioRecorderService();
