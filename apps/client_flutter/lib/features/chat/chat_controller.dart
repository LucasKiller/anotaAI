import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../shared/models/chat_models.dart';
import 'chat_service.dart';

class ChatController extends ChangeNotifier {
  ChatController({ChatService? service}) : _service = service ?? ChatService();

  final ChatService _service;

  String? _recordingId;
  ChatSessionModel? _session;
  List<ChatMessageModel> _messages = <ChatMessageModel>[];
  bool _isLoading = false;
  bool _isSending = false;
  String? _errorMessage;

  String? get recordingId => _recordingId;
  ChatSessionModel? get session => _session;
  List<ChatMessageModel> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  String? get errorMessage => _errorMessage;

  Future<void> loadForRecording({
    required String accessToken,
    required String recordingId,
  }) async {
    _recordingId = recordingId;
    _setLoading(true);
    _setError(null);

    try {
      final sessions = await _service.listSessions(
        accessToken: accessToken,
        recordingId: recordingId,
      );
      if (sessions.isEmpty) {
        _session = null;
        _messages = <ChatMessageModel>[];
        notifyListeners();
        return;
      }

      final detail = await _service.getSession(
        accessToken: accessToken,
        sessionId: sessions.first.id,
      );
      _session = detail.session;
      _messages = detail.messages;
      notifyListeners();
    } on ApiException catch (error) {
      _setError(error.message);
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> sendMessage({
    required String accessToken,
    required String recordingId,
    required String content,
  }) async {
    _recordingId = recordingId;
    _setSending(true);
    _setError(null);

    try {
      final session = await _ensureSession(
        accessToken: accessToken,
        recordingId: recordingId,
      );
      final reply = await _service.sendMessage(
        accessToken: accessToken,
        sessionId: session.id,
        content: content,
      );
      _messages = <ChatMessageModel>[
        ..._messages,
        reply.userMessage,
        reply.assistantMessage,
      ];
      notifyListeners();
    } on ApiException catch (error) {
      _setError(error.message);
      rethrow;
    } finally {
      _setSending(false);
    }
  }

  Future<void> reload({required String accessToken}) async {
    final currentRecordingId = _recordingId;
    if (currentRecordingId == null) {
      return;
    }
    await loadForRecording(
      accessToken: accessToken,
      recordingId: currentRecordingId,
    );
  }

  void clear() {
    _recordingId = null;
    _session = null;
    _messages = <ChatMessageModel>[];
    _errorMessage = null;
    notifyListeners();
  }

  Future<ChatSessionModel> _ensureSession({
    required String accessToken,
    required String recordingId,
  }) async {
    if (_session != null && _session!.recordingId == recordingId) {
      return _session!;
    }

    final sessions = await _service.listSessions(
      accessToken: accessToken,
      recordingId: recordingId,
    );
    if (sessions.isNotEmpty) {
      final detail = await _service.getSession(
        accessToken: accessToken,
        sessionId: sessions.first.id,
      );
      _session = detail.session;
      _messages = detail.messages;
      notifyListeners();
      return detail.session;
    }

    final created = await _service.createSession(
      accessToken: accessToken,
      recordingId: recordingId,
      title: 'Chat principal',
    );
    _session = created;
    _messages = <ChatMessageModel>[];
    notifyListeners();
    return created;
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setSending(bool value) {
    _isSending = value;
    notifyListeners();
  }

  void _setError(String? value) {
    _errorMessage = value;
    notifyListeners();
  }
}
