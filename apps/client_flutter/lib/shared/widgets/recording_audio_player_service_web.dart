// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'recording_audio_player_service.dart';

class WebRecordingAudioPlayerService extends RecordingAudioPlayerService {
  html.AudioElement? _audioElement;
  String? _objectUrl;
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  bool _isLoadingSource = false;
  bool _isLoaded = false;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  bool get isSupported => true;

  @override
  bool get isLoaded => _isLoaded;

  @override
  bool get isPlaying => _isPlaying;

  @override
  bool get isLoadingSource => _isLoadingSource;

  @override
  Duration get position => _position;

  @override
  Duration get duration => _duration;

  @override
  Future<void> load({
    required List<int> bytes,
    required String mimeType,
  }) async {
    await stop();
    _disposeAudioElement();

    _isLoadingSource = true;
    _isLoaded = false;
    _isPlaying = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    notifyListeners();

    final blob = html.Blob(<dynamic>[Uint8List.fromList(bytes)], mimeType);
    final objectUrl = html.Url.createObjectUrlFromBlob(blob);
    final audio = html.AudioElement()
      ..src = objectUrl
      ..preload = 'metadata';

    _audioElement = audio;
    _objectUrl = objectUrl;
    _registerListeners(audio);

    final completer = Completer<void>();
    late final StreamSubscription<html.Event> metadataSubscription;
    late final StreamSubscription<html.Event> errorSubscription;

    metadataSubscription = audio.onLoadedMetadata.listen((_) async {
      await metadataSubscription.cancel();
      await errorSubscription.cancel();
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    errorSubscription = audio.onError.listen((_) async {
      await metadataSubscription.cancel();
      await errorSubscription.cancel();
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Nao foi possivel carregar o audio da gravacao.'),
        );
      }
    });

    audio.load();
    await completer.future.timeout(const Duration(seconds: 20));

    _isLoadingSource = false;
    _isLoaded = true;
    _duration = _secondsToDuration(audio.duration);
    notifyListeners();
  }

  @override
  Future<void> togglePlayback() async {
    final audio = _audioElement;
    if (audio == null || !_isLoaded) {
      return;
    }

    if (_isPlaying) {
      audio.pause();
      return;
    }

    await audio.play();
  }

  @override
  Future<void> seek(Duration position) async {
    final audio = _audioElement;
    if (audio == null || !_isLoaded) {
      return;
    }

    final clamped = position > _duration ? _duration : position;
    audio.currentTime = clamped.inMilliseconds / 1000;
    _position = clamped;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    final audio = _audioElement;
    if (audio != null) {
      audio.pause();
      audio.currentTime = 0;
    }
    _isPlaying = false;
    _position = Duration.zero;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposeAudioElement();
    super.dispose();
  }

  void _registerListeners(html.AudioElement audio) {
    _subscriptions.addAll(<StreamSubscription<dynamic>>[
      audio.onTimeUpdate.listen((_) {
        _position = _secondsToDuration(audio.currentTime);
        notifyListeners();
      }),
      audio.onDurationChange.listen((_) {
        _duration = _secondsToDuration(audio.duration);
        notifyListeners();
      }),
      audio.onPlay.listen((_) {
        _isPlaying = true;
        notifyListeners();
      }),
      audio.onPause.listen((_) {
        _isPlaying = false;
        notifyListeners();
      }),
      audio.onEnded.listen((_) {
        _isPlaying = false;
        _position = _duration;
        notifyListeners();
      }),
    ]);
  }

  void _disposeAudioElement() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();

    _audioElement?.pause();
    _audioElement?.src = '';
    _audioElement = null;

    if (_objectUrl != null) {
      html.Url.revokeObjectUrl(_objectUrl!);
      _objectUrl = null;
    }
  }

  Duration _secondsToDuration(num? seconds) {
    if (seconds == null || seconds.isNaN || seconds.isInfinite || seconds < 0) {
      return Duration.zero;
    }
    return Duration(milliseconds: (seconds * 1000).round());
  }
}

RecordingAudioPlayerService createRecordingAudioPlayerServiceImpl() =>
    WebRecordingAudioPlayerService();
