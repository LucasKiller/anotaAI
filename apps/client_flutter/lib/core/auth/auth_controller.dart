import 'package:flutter/foundation.dart';

import '../../shared/models/app_user.dart';
import '../network/api_client.dart';
import '../storage/token_storage.dart';

class AuthController extends ChangeNotifier {
  AuthController({
    ApiClient? apiClient,
    TokenStorage? tokenStorage,
  })  : _apiClient = apiClient ?? ApiClient(),
        _tokenStorage = tokenStorage ?? TokenStorage();

  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;

  bool _isBootstrapping = true;
  bool _isLoading = false;
  String? _errorMessage;
  String? _accessToken;
  String? _refreshToken;
  AppUser? _currentUser;

  bool get isBootstrapping => _isBootstrapping;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  AppUser? get currentUser => _currentUser;
  bool get isAuthenticated => _accessToken != null && _currentUser != null;

  Future<void> bootstrap() async {
    _setBootstrapping(true);

    final (savedAccess, savedRefresh) = await _tokenStorage.loadTokens();
    _accessToken = savedAccess;
    _refreshToken = savedRefresh;

    if (_accessToken != null) {
      try {
        await _fetchCurrentUser();
      } on ApiException {
        await _clearSession();
      }
    }

    _setBootstrapping(false);
  }

  Future<void> login({required String email, required String password}) async {
    _setLoading(true);
    _setError(null);
    try {
      final response = await _apiClient.post(
        '/auth/login',
        body: {
          'email': email,
          'password': password,
        },
      );
      await _consumeTokenPayload(response as Map<String, dynamic>);
      await _fetchCurrentUser();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> register({
    required String email,
    required String password,
    String? name,
  }) async {
    _setLoading(true);
    _setError(null);
    try {
      final response = await _apiClient.post(
        '/auth/register',
        body: {
          'email': email,
          'password': password,
          'name': name,
        },
      );
      await _consumeTokenPayload(response as Map<String, dynamic>);
      await _fetchCurrentUser();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> logout() async {
    final currentRefresh = _refreshToken;
    if (currentRefresh != null) {
      try {
        await _apiClient.post(
          '/auth/logout',
          body: {
            'refresh_token': currentRefresh,
          },
        );
      } catch (_) {
        // Logout remoto é best-effort.
      }
    }

    await _clearSession();
    notifyListeners();
  }

  Future<void> updateProfileName(String? name) async {
    final token = _accessToken;
    if (token == null) {
      throw ApiException(message: 'Sessao expirada', statusCode: 401);
    }

    _setLoading(true);
    _setError(null);
    try {
      final response = await _apiClient.patch(
        '/me',
        accessToken: token,
        body: {'name': name},
      );
      _currentUser = AppUser.fromJson(response as Map<String, dynamic>);
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _fetchCurrentUser() async {
    final token = _accessToken;
    if (token == null) {
      throw ApiException(message: 'Access token ausente', statusCode: 401);
    }

    final response = await _apiClient.get('/me', accessToken: token);
    _currentUser = AppUser.fromJson(response as Map<String, dynamic>);
    notifyListeners();
  }

  Future<void> _consumeTokenPayload(Map<String, dynamic> payload) async {
    final accessToken = payload['access_token'] as String?;
    final refreshToken = payload['refresh_token'] as String?;

    if (accessToken == null || refreshToken == null) {
      throw ApiException(message: 'Resposta de auth inválida', statusCode: 500);
    }

    _accessToken = accessToken;
    _refreshToken = refreshToken;
    await _tokenStorage.saveTokens(accessToken: accessToken, refreshToken: refreshToken);
    notifyListeners();
  }

  Future<void> _clearSession() async {
    _accessToken = null;
    _refreshToken = null;
    _currentUser = null;
    await _tokenStorage.clear();
  }

  void _setBootstrapping(bool value) {
    _isBootstrapping = value;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String? value) {
    _errorMessage = value;
    notifyListeners();
  }
}
