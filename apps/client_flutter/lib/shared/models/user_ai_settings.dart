class UserAiSettings {
  UserAiSettings({
    required this.source,
    required this.providerType,
    required this.baseUrl,
    required this.model,
    required this.hasApiKey,
    required this.apiKeyHint,
    required this.updatedAt,
  });

  final String source;
  final String providerType;
  final String baseUrl;
  final String model;
  final bool hasApiKey;
  final String? apiKeyHint;
  final DateTime? updatedAt;

  bool get isUserOverride => source == 'user';
  bool get isOpenAi => providerType == 'openai';

  factory UserAiSettings.fromJson(Map<String, dynamic> json) {
    return UserAiSettings(
      source: json['source'] as String? ?? 'system',
      providerType: json['provider_type'] as String? ?? 'openai_compatible',
      baseUrl: json['base_url'] as String? ?? '',
      model: json['model'] as String? ?? '',
      hasApiKey: json['has_api_key'] as bool? ?? false,
      apiKeyHint: json['api_key_hint'] as String?,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }
}
