import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class ApiException implements Exception {
  ApiException({required this.message, required this.statusCode});

  final String message;
  final int statusCode;

  @override
  String toString() => 'ApiException(status=$statusCode, message=$message)';
}

class ApiClient {
  ApiClient({String? baseUrl}) : _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final String _baseUrl;

  Future<dynamic> get(
    String path, {
    String? accessToken,
  }) {
    return _request(
      method: 'GET',
      path: path,
      accessToken: accessToken,
    );
  }

  Future<dynamic> post(
    String path, {
    String? accessToken,
    Object? body,
  }) {
    return _request(
      method: 'POST',
      path: path,
      accessToken: accessToken,
      body: body,
    );
  }

  Future<dynamic> patch(
    String path, {
    String? accessToken,
    Object? body,
  }) {
    return _request(
      method: 'PATCH',
      path: path,
      accessToken: accessToken,
      body: body,
    );
  }

  Future<dynamic> delete(
    String path, {
    String? accessToken,
  }) {
    return _request(
      method: 'DELETE',
      path: path,
      accessToken: accessToken,
    );
  }

  Future<dynamic> put(
    String path, {
    String? accessToken,
    Object? body,
  }) {
    return _request(
      method: 'PUT',
      path: path,
      accessToken: accessToken,
      body: body,
    );
  }

  Future<dynamic> _request({
    required String method,
    required String path,
    String? accessToken,
    Object? body,
  }) async {
    final uri = Uri.parse(_composeUrl(path));

    final headers = <String, String>{
      'Accept': 'application/json',
    };

    if (accessToken != null && accessToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $accessToken';
    }

    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }

    final http.Response response;
    if (method == 'GET') {
      response = await http.get(uri, headers: headers);
    } else if (method == 'POST') {
      response = await http.post(uri, headers: headers, body: _encodeBody(body));
    } else if (method == 'PUT') {
      response = await http.put(uri, headers: headers, body: _encodeBody(body));
    } else if (method == 'PATCH') {
      response = await http.patch(uri, headers: headers, body: _encodeBody(body));
    } else if (method == 'DELETE') {
      response = await http.delete(uri, headers: headers);
    } else {
      throw ApiException(message: 'Unsupported HTTP method: $method', statusCode: 500);
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) {
        return null;
      }
      return _decodeBody(response.body);
    }

    throw ApiException(
      message: _extractErrorMessage(response.body),
      statusCode: response.statusCode,
    );
  }

  String _composeUrl(String path) {
    final normalizedBase = _baseUrl.endsWith('/') ? _baseUrl.substring(0, _baseUrl.length - 1) : _baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return '$normalizedBase$normalizedPath';
  }

  String _encodeBody(Object? body) {
    if (body == null) {
      return '';
    }
    if (body is String) {
      return body;
    }
    return jsonEncode(body);
  }

  dynamic _decodeBody(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }

  String _extractErrorMessage(String rawBody) {
    if (rawBody.isEmpty) {
      return 'Unexpected API error';
    }

    final decoded = _decodeBody(rawBody);
    if (decoded is Map<String, dynamic>) {
      final detail = decoded['detail'];
      final message = decoded['message'];

      if (detail is String && detail.isNotEmpty) {
        return detail;
      }
      if (message is String && message.isNotEmpty) {
        return message;
      }
    }

    return rawBody;
  }
}
