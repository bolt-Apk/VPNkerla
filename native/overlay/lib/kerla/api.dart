import 'dart:math';

import 'package:dio/dio.dart';

class KerlaApi {
  KerlaApi({String? baseUrl})
    : _http = Dio(
        BaseOptions(
          baseUrl: baseUrl ?? const String.fromEnvironment('KERLA_API_URL'),
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 20),
          followRedirects: false,
          headers: {
            'User-Agent': 'VPNkerla-App/0.1',
            'Content-Type': 'application/json',
          },
        ),
      );

  final Dio _http;
  String? _token;

  bool get configured {
    final uri = Uri.tryParse(_http.options.baseUrl);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  bool get signedIn => _token != null;

  static String identifier() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<Map<String, dynamic>> call(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? data,
  }) async {
    if (!configured) throw const KerlaApiException('API_NOT_CONFIGURED');
    try {
      final response = await _http.request<Map<String, dynamic>>(
        path,
        data: data,
        options: Options(
          method: method,
          headers: {if (_token != null) 'Authorization': 'Bearer $_token'},
        ),
      );
      return response.data ?? {};
    } on DioException catch (error) {
      final body = error.response?.data;
      final message = body is Map && body['error'] is String
          ? body['error'] as String
          : 'NETWORK_ERROR';
      if (error.response?.statusCode == 401) _token = null;
      throw KerlaApiException(message, status: error.response?.statusCode);
    }
  }

  Future<Map<String, dynamic>> verify(String email, String code) async {
    final result = await call(
      '/v1/auth/verify',
      method: 'POST',
      data: {'email': email, 'code': code},
    );
    final token = result['token'];
    if (token is! String || !RegExp(r'^[\w-]{43}$').hasMatch(token)) {
      throw const KerlaApiException('INVALID_RESPONSE');
    }
    _token = token;
    return Map<String, dynamic>.from(result['account'] as Map);
  }

  Future<void> logout() async {
    try {
      if (signedIn) await call('/v1/auth/logout', method: 'POST');
    } finally {
      _token = null;
    }
  }

  void close() {
    _token = null;
    _http.close(force: true);
  }
}

class KerlaApiException implements Exception {
  const KerlaApiException(this.message, {this.status});
  final String message;
  final int? status;
}
