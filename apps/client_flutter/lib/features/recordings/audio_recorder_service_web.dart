// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'audio_recorder_service.dart';

class WebAudioRecorderService implements AudioRecorderService {
  static const List<String> _preferredMimeTypes = <String>[
    'audio/webm;codecs=opus',
    'audio/webm',
    'audio/ogg;codecs=opus',
    'audio/ogg',
  ];

  html.MediaRecorder? _mediaRecorder;
  html.MediaStream? _mediaStream;
  final List<html.Blob> _chunks = <html.Blob>[];
  String _mimeType = 'audio/webm';
  static const html.EventStreamProvider<html.BlobEvent> _dataAvailableEvent =
      html.EventStreamProvider<html.BlobEvent>('dataavailable');
  static const html.EventStreamProvider<html.Event> _stopEvent =
      html.EventStreamProvider<html.Event>('stop');

  @override
  bool get isSupported => html.window.navigator.mediaDevices != null;

  @override
  Future<void> start() async {
    if (!isSupported) {
      throw UnsupportedError(
        'O navegador atual nao suporta gravacao ao vivo com MediaRecorder.',
      );
    }
    if (_mediaRecorder != null && _mediaRecorder!.state != 'inactive') {
      throw StateError('Ja existe uma gravacao em andamento.');
    }

    final mediaDevices = html.window.navigator.mediaDevices;
    if (mediaDevices == null) {
      throw UnsupportedError(
        'Acesso ao microfone indisponivel neste navegador.',
      );
    }

    final stream = await mediaDevices.getUserMedia(<String, dynamic>{
      'audio': true,
    });

    final mimeType = _pickMimeType();
    final recorder = mimeType == null
        ? html.MediaRecorder(stream)
        : html.MediaRecorder(
            stream,
            <String, dynamic>{'mimeType': mimeType},
          );

    _chunks.clear();
    _mediaStream = stream;
    _mediaRecorder = recorder;
    _mimeType = mimeType ?? recorder.mimeType ?? 'audio/webm';

    _dataAvailableEvent.forTarget(recorder).listen((event) {
      final data = event.data;
      if (data != null && data.size > 0) {
        _chunks.add(data);
      }
    });

    recorder.start();
  }

  @override
  Future<void> pause() async {
    final recorder = _mediaRecorder;
    if (recorder == null || recorder.state != 'recording') {
      throw StateError('Nao existe gravacao ativa para pausar.');
    }
    recorder.pause();
  }

  @override
  Future<void> resume() async {
    final recorder = _mediaRecorder;
    if (recorder == null || recorder.state != 'paused') {
      throw StateError('Nao existe gravacao pausada para continuar.');
    }
    recorder.resume();
  }

  @override
  Future<RecordedAudioCapture> stop() async {
    final recorder = _mediaRecorder;
    if (recorder == null || recorder.state == 'inactive') {
      throw StateError('Nao existe gravacao para finalizar.');
    }

    await _stopRecorder(recorder);

    final mimeType = _mimeType.isNotEmpty ? _mimeType : 'audio/webm';
    final blob = html.Blob(_chunks, mimeType);
    final bytes = await _readBlob(blob);
    final extension = _extensionForMimeType(mimeType);
    final fileName =
        'live_recording_${DateTime.now().millisecondsSinceEpoch}.$extension';

    _cleanup();

    return RecordedAudioCapture(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    );
  }

  @override
  Future<void> cancel() async {
    final recorder = _mediaRecorder;
    if (recorder != null && recorder.state != 'inactive') {
      await _stopRecorder(recorder);
    }
    _cleanup();
  }

  Future<void> _stopRecorder(html.MediaRecorder recorder) async {
    final completer = Completer<void>();
    late final StreamSubscription<html.Event> subscription;
    subscription = _stopEvent.forTarget(recorder).listen((_) async {
      await subscription.cancel();
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    recorder.stop();
    await completer.future.timeout(const Duration(seconds: 10));
  }

  Future<List<int>> _readBlob(html.Blob blob) {
    final completer = Completer<List<int>>();
    final reader = html.FileReader();

    reader.onLoadEnd.listen((_) {
      final result = reader.result;
      if (result is ByteBuffer) {
        completer.complete(result.asUint8List());
        return;
      }
      if (result is Uint8List) {
        completer.complete(result);
        return;
      }
      completer.completeError(
        StateError('Nao foi possivel converter o audio gravado.'),
      );
    });

    reader.onError.listen((_) {
      completer.completeError(
        StateError('Falha ao ler os bytes do audio gravado.'),
      );
    });

    reader.readAsArrayBuffer(blob);
    return completer.future;
  }

  String? _pickMimeType() {
    for (final mimeType in _preferredMimeTypes) {
      if (html.MediaRecorder.isTypeSupported(mimeType)) {
        return mimeType;
      }
    }
    return null;
  }

  String _extensionForMimeType(String mimeType) {
    final normalized = mimeType.split(';').first.trim().toLowerCase();
    if (normalized.endsWith('/ogg')) {
      return 'ogg';
    }
    if (normalized.endsWith('/mp4')) {
      return 'm4a';
    }
    return 'webm';
  }

  void _cleanup() {
    for (final track in _mediaStream?.getTracks() ?? const <html.MediaStreamTrack>[]) {
      track.stop();
    }
    _mediaRecorder = null;
    _mediaStream = null;
    _chunks.clear();
    _mimeType = 'audio/webm';
  }
}

AudioRecorderService createAudioRecorderServiceImpl() =>
    WebAudioRecorderService();
