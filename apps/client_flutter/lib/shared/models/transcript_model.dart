class TranscriptModel {
  TranscriptModel({
    required this.id,
    required this.recordingId,
    required this.version,
    required this.fullText,
    required this.language,
    required this.modelName,
    required this.createdAt,
  });

  final String id;
  final String recordingId;
  final int version;
  final String fullText;
  final String? language;
  final String? modelName;
  final DateTime createdAt;

  factory TranscriptModel.fromJson(Map<String, dynamic> json) {
    return TranscriptModel(
      id: json['id'] as String,
      recordingId: json['recording_id'] as String,
      version: json['version'] as int? ?? 1,
      fullText: json['full_text'] as String? ?? '',
      language: json['language'] as String?,
      modelName: json['model_name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
