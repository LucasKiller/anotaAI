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

class TranscriptSegmentModel {
  TranscriptSegmentModel({
    required this.id,
    required this.transcriptId,
    required this.segmentIndex,
    required this.startMs,
    required this.endMs,
    required this.text,
    required this.speakerLabel,
    required this.tokensEstimate,
    required this.createdAt,
  });

  final String id;
  final String transcriptId;
  final int segmentIndex;
  final int startMs;
  final int endMs;
  final String text;
  final String? speakerLabel;
  final int? tokensEstimate;
  final DateTime createdAt;

  factory TranscriptSegmentModel.fromJson(Map<String, dynamic> json) {
    return TranscriptSegmentModel(
      id: json['id'] as String,
      transcriptId: json['transcript_id'] as String,
      segmentIndex: json['segment_index'] as int? ?? 0,
      startMs: json['start_ms'] as int? ?? 0,
      endMs: json['end_ms'] as int? ?? 0,
      text: json['text'] as String? ?? '',
      speakerLabel: json['speaker_label'] as String?,
      tokensEstimate: json['tokens_estimate'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
