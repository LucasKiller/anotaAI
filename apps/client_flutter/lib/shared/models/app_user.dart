class AppUser {
  AppUser({
    required this.id,
    required this.email,
    required this.name,
    required this.status,
  });

  final String id;
  final String email;
  final String? name;
  final String status;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String?,
      status: json['status'] as String? ?? 'active',
    );
  }
}
