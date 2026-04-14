class RecordingModel {
  RecordingModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.description,
    required this.language,
    required this.sourceType,
    required this.status,
    required this.durationMs,
    required this.createdAt,
    required this.updatedAt,
    required this.processedAt,
    required this.failedReason,
  });

  final String id;
  final String userId;
  final String title;
  final String? description;
  final String? language;
  final String sourceType;
  final String status;
  final int? durationMs;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? processedAt;
  final String? failedReason;

  factory RecordingModel.fromJson(Map<String, dynamic> json) {
    return RecordingModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      language: json['language'] as String?,
      sourceType: json['source_type'] as String? ?? 'upload',
      status: json['status'] as String? ?? 'draft',
      durationMs: json['duration_ms'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      processedAt: json['processed_at'] == null ? null : DateTime.parse(json['processed_at'] as String),
      failedReason: json['failed_reason'] as String?,
    );
  }
}
