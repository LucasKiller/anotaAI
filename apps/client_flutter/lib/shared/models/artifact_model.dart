import 'dart:convert';

class ArtifactModel {
  ArtifactModel({
    required this.id,
    required this.recordingId,
    required this.artifactType,
    required this.version,
    required this.contentMd,
    required this.contentJson,
    required this.modelName,
    required this.createdAt,
  });

  final String id;
  final String recordingId;
  final String artifactType;
  final int version;
  final String? contentMd;
  final Object? contentJson;
  final String? modelName;
  final DateTime createdAt;

  factory ArtifactModel.fromJson(Map<String, dynamic> json) {
    return ArtifactModel(
      id: json['id'] as String,
      recordingId: json['recording_id'] as String,
      artifactType: json['artifact_type'] as String,
      version: json['version'] as int? ?? 1,
      contentMd: json['content_md'] as String?,
      contentJson: json['content_json'],
      modelName: json['model_name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  String prettyJson() {
    if (contentJson == null) {
      return 'Sem conteúdo JSON.';
    }
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(contentJson);
  }
}
