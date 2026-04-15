class ChatSessionModel {
  ChatSessionModel({
    required this.id,
    required this.recordingId,
    required this.userId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String recordingId;
  final String userId;
  final String? title;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ChatSessionModel.fromJson(Map<String, dynamic> json) {
    return ChatSessionModel(
      id: json['id'] as String,
      recordingId: json['recording_id'] as String,
      userId: json['user_id'] as String,
      title: json['title'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

class ChatMessageModel {
  ChatMessageModel({
    required this.id,
    required this.chatSessionId,
    required this.role,
    required this.content,
    required this.citationsJson,
    required this.createdAt,
  });

  final String id;
  final String chatSessionId;
  final String role;
  final String content;
  final Object? citationsJson;
  final DateTime createdAt;

  bool get isAssistant => role == 'assistant';
  bool get isUser => role == 'user';

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    return ChatMessageModel(
      id: json['id'] as String,
      chatSessionId: json['chat_session_id'] as String,
      role: json['role'] as String,
      content: json['content'] as String,
      citationsJson: json['citations_json'],
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class ChatSessionDetailModel {
  ChatSessionDetailModel({
    required this.session,
    required this.messages,
  });

  final ChatSessionModel session;
  final List<ChatMessageModel> messages;

  factory ChatSessionDetailModel.fromJson(Map<String, dynamic> json) {
    final rawMessages = (json['messages'] as List<dynamic>? ?? <dynamic>[])
        .cast<Map<String, dynamic>>();
    return ChatSessionDetailModel(
      session:
          ChatSessionModel.fromJson(json['session'] as Map<String, dynamic>),
      messages: rawMessages.map(ChatMessageModel.fromJson).toList(),
    );
  }
}

class ChatReplyModel {
  ChatReplyModel({
    required this.userMessage,
    required this.assistantMessage,
  });

  final ChatMessageModel userMessage;
  final ChatMessageModel assistantMessage;

  factory ChatReplyModel.fromJson(Map<String, dynamic> json) {
    return ChatReplyModel(
      userMessage: ChatMessageModel.fromJson(
          json['user_message'] as Map<String, dynamic>),
      assistantMessage: ChatMessageModel.fromJson(
          json['assistant_message'] as Map<String, dynamic>),
    );
  }
}
