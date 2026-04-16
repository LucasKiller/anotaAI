import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../shared/models/artifact_model.dart';
import '../../shared/models/job_model.dart';
import '../../shared/models/recording_model.dart';
import '../../shared/models/transcript_model.dart';

class RecordingsService {
  RecordingsService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<List<RecordingModel>> listRecordings(
      {required String accessToken}) async {
    final response = await _apiClient.get('/recordings',
        accessToken: accessToken) as Map<String, dynamic>;
    final rawItems = (response['items'] as List<dynamic>? ?? <dynamic>[])
        .cast<Map<String, dynamic>>();
    return rawItems.map(RecordingModel.fromJson).toList();
  }

  Future<RecordingModel> createRecording({
    required String accessToken,
    required String title,
  }) async {
    final response = await _apiClient.post(
      '/recordings',
      accessToken: accessToken,
      body: {
        'title': title,
        'source_type': 'upload',
      },
    ) as Map<String, dynamic>;

    return RecordingModel.fromJson(response);
  }

  Future<RecordingModel> getRecording({
    required String accessToken,
    required String recordingId,
  }) async {
    final response = await _apiClient.get('/recordings/$recordingId',
        accessToken: accessToken) as Map<String, dynamic>;
    return RecordingModel.fromJson(response);
  }

  Future<void> startProcessing({
    required String accessToken,
    required String recordingId,
  }) async {
    await _apiClient.post('/recordings/$recordingId/process',
        accessToken: accessToken);
  }

  Future<void> uploadAudioBytes({
    required String accessToken,
    required String recordingId,
    required String fileName,
    required List<int> bytes,
  }) async {
    final uri = Uri.parse('${_baseUrl()}/recordings/$recordingId/upload');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..headers['Accept'] = 'application/json'
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
        ),
      );

    final response = await request.send();
    final body = await response.stream.bytesToString();

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    throw ApiException(
      message: _extractMessage(body),
      statusCode: response.statusCode,
    );
  }

  Future<RecordingModel> updateRecording({
    required String accessToken,
    required String recordingId,
    required String title,
    String? description,
    String? language,
  }) async {
    final response = await _apiClient.patch(
      '/recordings/$recordingId',
      accessToken: accessToken,
      body: {
        'title': title,
        'description': description,
        'language': language,
      },
    ) as Map<String, dynamic>;

    return RecordingModel.fromJson(response);
  }

  Future<void> deleteRecording({
    required String accessToken,
    required String recordingId,
  }) async {
    await _apiClient.delete('/recordings/$recordingId',
        accessToken: accessToken);
  }

  Future<TranscriptModel?> getTranscript({
    required String accessToken,
    required String recordingId,
  }) async {
    try {
      final response = await _apiClient.get(
          '/recordings/$recordingId/transcript',
          accessToken: accessToken) as Map<String, dynamic>;
      return TranscriptModel.fromJson(response);
    } on ApiException catch (error) {
      if (error.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  Future<List<TranscriptSegmentModel>> getSegments({
    required String accessToken,
    required String recordingId,
  }) async {
    try {
      final response = await _apiClient.get(
        '/recordings/$recordingId/segments',
        accessToken: accessToken,
      ) as Map<String, dynamic>;
      final rawItems = (response['items'] as List<dynamic>? ?? <dynamic>[])
          .cast<Map<String, dynamic>>();
      return rawItems.map(TranscriptSegmentModel.fromJson).toList();
    } on ApiException catch (error) {
      if (error.statusCode == 404) {
        return <TranscriptSegmentModel>[];
      }
      rethrow;
    }
  }

  Future<ArtifactModel?> getSummary({
    required String accessToken,
    required String recordingId,
  }) async {
    try {
      final response = await _apiClient.get('/recordings/$recordingId/summary',
          accessToken: accessToken) as Map<String, dynamic>;
      return ArtifactModel.fromJson(response);
    } on ApiException catch (error) {
      if (error.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  Future<ArtifactModel?> getMindmap({
    required String accessToken,
    required String recordingId,
  }) async {
    try {
      final response = await _apiClient.get('/recordings/$recordingId/mindmap',
          accessToken: accessToken) as Map<String, dynamic>;
      return ArtifactModel.fromJson(response);
    } on ApiException catch (error) {
      if (error.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  Future<List<JobModel>> listJobs({
    required String accessToken,
    required String recordingId,
  }) async {
    final response = await _apiClient.get('/recordings/$recordingId/jobs',
        accessToken: accessToken) as Map<String, dynamic>;
    final rawItems = (response['items'] as List<dynamic>? ?? <dynamic>[])
        .cast<Map<String, dynamic>>();
    return rawItems.map(JobModel.fromJson).toList();
  }

  String _baseUrl() {
    final value = AppConfig.apiBaseUrl;
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  String _extractMessage(String raw) {
    if (raw.isEmpty) {
      return 'Falha no upload do arquivo.';
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is String && detail.isNotEmpty) {
          return detail;
        }
      }
    } catch (_) {
      // no-op
    }
    return raw;
  }
}
