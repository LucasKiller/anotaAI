class JobModel {
  JobModel({
    required this.id,
    required this.recordingId,
    required this.jobType,
    required this.status,
    required this.attempts,
    required this.errorMessage,
    required this.queuedAt,
    required this.startedAt,
    required this.finishedAt,
  });

  final String id;
  final String recordingId;
  final String jobType;
  final String status;
  final int attempts;
  final String? errorMessage;
  final DateTime queuedAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  factory JobModel.fromJson(Map<String, dynamic> json) {
    return JobModel(
      id: json['id'] as String,
      recordingId: json['recording_id'] as String,
      jobType: json['job_type'] as String,
      status: json['status'] as String,
      attempts: json['attempts'] as int? ?? 0,
      errorMessage: json['error_message'] as String?,
      queuedAt: DateTime.parse(json['queued_at'] as String),
      startedAt: json['started_at'] == null ? null : DateTime.parse(json['started_at'] as String),
      finishedAt: json['finished_at'] == null ? null : DateTime.parse(json['finished_at'] as String),
    );
  }
}
