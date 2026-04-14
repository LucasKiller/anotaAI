import 'package:shared_preferences/shared_preferences.dart';

class TokenStorage {
  static const String _accessTokenKey = 'anotaai_access_token';
  static const String _refreshTokenKey = 'anotaai_refresh_token';

  Future<(String?, String?)> loadTokens() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_accessTokenKey), prefs.getString(_refreshTokenKey));
  }

  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKey, accessToken);
    await prefs.setString(_refreshTokenKey, refreshToken);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
  }
}
