import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../shared/models/artifact_model.dart';
import '../../shared/models/job_model.dart';
import '../../shared/models/recording_model.dart';
import '../../shared/models/transcript_model.dart';
import 'recordings_service.dart';

class RecordingsController extends ChangeNotifier {
  RecordingsController({RecordingsService? service}) : _service = service ?? RecordingsService();

  final RecordingsService _service;

  List<RecordingModel> _recordings = <RecordingModel>[];
  RecordingModel? _selected;
  TranscriptModel? _transcript;
  ArtifactModel? _summary;
  ArtifactModel? _mindmap;
  List<JobModel> _jobs = <JobModel>[];

  bool _isListLoading = false;
  bool _isDetailLoading = false;
  String? _errorMessage;

  List<RecordingModel> get recordings => _recordings;
  RecordingModel? get selected => _selected;
  TranscriptModel? get transcript => _transcript;
  ArtifactModel? get summary => _summary;
  ArtifactModel? get mindmap => _mindmap;
  List<JobModel> get jobs => _jobs;

  JobModel? get latestJob {
    if (_jobs.isEmpty) {
      return null;
    }
    return _jobs.last;
  }

  bool get isListLoading => _isListLoading;
  bool get isDetailLoading => _isDetailLoading;
  String? get errorMessage => _errorMessage;

  Future<void> bootstrap({required String accessToken}) async {
    await refreshRecordings(accessToken: accessToken);
    if (_recordings.isNotEmpty) {
      await selectRecording(accessToken: accessToken, recordingId: _recordings.first.id);
    }
  }

  Future<void> refreshRecordings({required String accessToken}) async {
    _setListLoading(true);
    _setError(null);

    try {
      final previousId = _selected?.id;
      _recordings = await _service.listRecordings(accessToken: accessToken);

      if (previousId != null) {
        _selected = _findById(previousId);
      }

      notifyListeners();
    } on ApiException catch (error) {
      _setError(error.message);
      rethrow;
    } finally {
      _setListLoading(false);
    }
  }

  Future<void> createRecording({
    required String accessToken,
    required String title,
  }) async {
    _setListLoading(true);
    _setError(null);

    try {
      final created = await _service.createRecording(accessToken: accessToken, title: title);
      _recordings = <RecordingModel>[created, ..._recordings];
      _selected = created;
      notifyListeners();
      await _loadDetails(accessToken: accessToken, recordingId: created.id);
    } on ApiException catch (error) {
      _setError(error.message);
      rethrow;
    } finally {
      _setListLoading(false);
    }
  }

  Future<void> selectRecording({
    required String accessToken,
    required String recordingId,
  }) async {
    _selected = _findById(recordingId);
    _transcript = null;
    _summary = null;
    _mindmap = null;
    _jobs = <JobModel>[];
    notifyListeners();

    await _loadDetails(accessToken: accessToken, recordingId: recordingId);
  }

  Future<void> startProcessing({
    required String accessToken,
    required String recordingId,
  }) async {
    _setDetailLoading(true);
    _setError(null);
    try {
      await _service.startProcessing(accessToken: accessToken, recordingId: recordingId);
      await refreshRecordings(accessToken: accessToken);
      await _loadDetails(accessToken: accessToken, recordingId: recordingId);
    } on ApiException catch (error) {
      _setError(error.message);
      rethrow;
    } finally {
      _setDetailLoading(false);
    }
  }

  Future<void> uploadAudio({
    required String accessToken,
    required String recordingId,
    required String fileName,
    required List<int> bytes,
  }) async {
    _setDetailLoading(true);
    _setError(null);
    try {
      await _service.uploadAudioBytes(
        accessToken: accessToken,
        recordingId: recordingId,
        fileName: fileName,
        bytes: bytes,
      );
      await refreshRecordings(accessToken: accessToken);
      await _loadDetails(accessToken: accessToken, recordingId: recordingId);
    } on ApiException catch (error) {
      _setError(error.message);
      rethrow;
    } finally {
      _setDetailLoading(false);
    }
  }

  Future<void> updateSelectedRecording({
    required String accessToken,
    required String recordingId,
    required String title,
    String? description,
    String? language,
  }) async {
    _setDetailLoading(true);
    _setError(null);
    try {
      await _service.updateRecording(
        accessToken: accessToken,
        recordingId: recordingId,
        title: title,
        description: description,
        language: language,
      );

      await refreshRecordings(accessToken: accessToken);
      await _loadDetails(accessToken: accessToken, recordingId: recordingId);
    } on ApiException catch (error) {
      _setError(error.message);
      rethrow;
    } finally {
      _setDetailLoading(false);
    }
  }

  Future<void> deleteSelectedRecording({
    required String accessToken,
    required String recordingId,
  }) async {
    _setDetailLoading(true);
    _setError(null);
    try {
      await _service.deleteRecording(accessToken: accessToken, recordingId: recordingId);

      _recordings = _recordings.where((item) => item.id != recordingId).toList();
      _selected = null;
      _transcript = null;
      _summary = null;
      _mindmap = null;
      _jobs = <JobModel>[];

      if (_recordings.isNotEmpty) {
        _selected = _recordings.first;
        await _loadDetails(accessToken: accessToken, recordingId: _recordings.first.id);
      }
      notifyListeners();
    } on ApiException catch (error) {
      _setError(error.message);
      rethrow;
    } finally {
      _setDetailLoading(false);
    }
  }

  Future<void> reloadDetails({
    required String accessToken,
    required String recordingId,
  }) {
    return _loadDetails(accessToken: accessToken, recordingId: recordingId);
  }

  Future<void> _loadDetails({
    required String accessToken,
    required String recordingId,
  }) async {
    _setDetailLoading(true);
    _setError(null);

    try {
      final transcript = await _service.getTranscript(accessToken: accessToken, recordingId: recordingId);
      final summary = await _service.getSummary(accessToken: accessToken, recordingId: recordingId);
      final mindmap = await _service.getMindmap(accessToken: accessToken, recordingId: recordingId);
      final jobs = await _service.listJobs(accessToken: accessToken, recordingId: recordingId);

      _transcript = transcript;
      _summary = summary;
      _mindmap = mindmap;
      _jobs = jobs;
      notifyListeners();
    } on ApiException catch (error) {
      _setError(error.message);
      rethrow;
    } finally {
      _setDetailLoading(false);
    }
  }

  void _setListLoading(bool value) {
    _isListLoading = value;
    notifyListeners();
  }

  void _setDetailLoading(bool value) {
    _isDetailLoading = value;
    notifyListeners();
  }

  void _setError(String? value) {
    _errorMessage = value;
    notifyListeners();
  }

  RecordingModel? _findById(String id) {
    for (final item in _recordings) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }
}
