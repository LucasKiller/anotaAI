import '../../core/network/api_client.dart';
import '../../shared/models/chat_models.dart';

class ChatService {
  ChatService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<List<ChatSessionModel>> listSessions({
    required String accessToken,
    required String recordingId,
  }) async {
    final response = await _apiClient.get(
      '/recordings/$recordingId/chat/sessions',
      accessToken: accessToken,
    ) as Map<String, dynamic>;
    final rawItems = (response['items'] as List<dynamic>? ?? <dynamic>[])
        .cast<Map<String, dynamic>>();
    return rawItems.map(ChatSessionModel.fromJson).toList();
  }

  Future<ChatSessionModel> createSession({
    required String accessToken,
    required String recordingId,
    String? title,
  }) async {
    final response = await _apiClient.post(
      '/recordings/$recordingId/chat/sessions',
      accessToken: accessToken,
      body: {'title': title},
    ) as Map<String, dynamic>;
    return ChatSessionModel.fromJson(response);
  }

  Future<ChatSessionDetailModel> getSession({
    required String accessToken,
    required String sessionId,
  }) async {
    final response = await _apiClient.get(
      '/chat/sessions/$sessionId',
      accessToken: accessToken,
    ) as Map<String, dynamic>;
    return ChatSessionDetailModel.fromJson(response);
  }

  Future<ChatReplyModel> sendMessage({
    required String accessToken,
    required String sessionId,
    required String content,
  }) async {
    final response = await _apiClient.post(
      '/chat/sessions/$sessionId/messages',
      accessToken: accessToken,
      body: {'content': content},
    ) as Map<String, dynamic>;
    return ChatReplyModel.fromJson(response);
  }
}
