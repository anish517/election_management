import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_constants.dart';
import 'token_storage.dart';

/// Global Dio client provider
final apiClientProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: ApiConstants.connectTimeout,
      receiveTimeout: ApiConstants.receiveTimeout,
      headers: {
        'Content-Type': 'application/json',
        'Bypass-Tunnel-Reminder': 'true',
        'X-Client-Platform': kIsWeb ? 'web' : 'mobile',
      },
    ),
  );

  dio.interceptors.add(JwtInterceptor(dio));
  return dio;
});

class JwtInterceptor extends Interceptor {
  final Dio _dio;
  JwtInterceptor(this._dio);

  // Mutex lock to synchronize concurrent refresh requests
  static Future<String?>? _refreshFuture;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await TokenStorage.read('access_token');
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Avoid intercepting auth endpoints themselves to prevent infinite recursion
    final isAuthEndpoint = err.requestOptions.path.contains('/auth/login') ||
        err.requestOptions.path.contains('/auth/register') ||
        err.requestOptions.path.contains('/auth/token/refresh') ||
        err.requestOptions.path.contains('/auth/otp');

    if (err.response?.statusCode == 401 && !isAuthEndpoint) {
      try {
        // If a refresh is already in progress, await it instead of triggering another
        _refreshFuture ??= _performTokenRefresh();
        final newAccess = await _refreshFuture;

        if (newAccess != null) {
          // Retry original request with newly refreshed token
          err.requestOptions.headers['Authorization'] = 'Bearer $newAccess';
          final cloned = await _dio.fetch(err.requestOptions);
          handler.resolve(cloned);
          return;
        } else {
          handler.next(err);
          return;
        }
      } catch (_) {
        handler.next(err);
        return;
      } finally {
        _refreshFuture = null;
      }
    }

    handler.next(err);
  }

  static Future<String?> _performTokenRefresh() async {
    try {
      final refreshToken = await TokenStorage.read('refresh_token');
      if (refreshToken == null) return null;

      final refreshDio = Dio(
        BaseOptions(
          baseUrl: ApiConstants.baseUrl,
          connectTimeout: ApiConstants.connectTimeout,
          receiveTimeout: ApiConstants.receiveTimeout,
        ),
      );

      final resp = await refreshDio.post(
        ApiConstants.tokenRefresh,
        data: {'refresh': refreshToken},
      );

      final data = resp.data as Map<String, dynamic>;
      final newAccess = data['access'] as String;
      await TokenStorage.write('access_token', newAccess);

      // Save rotated refresh token if backend returns one (ROTATE_REFRESH_TOKENS=True)
      if (data.containsKey('refresh') && data['refresh'] != null) {
        final newRefresh = data['refresh'] as String;
        await TokenStorage.write('refresh_token', newRefresh);
      }

      return newAccess;
    } catch (_) {
      // Clear stored tokens only when refresh token itself fails validation
      await TokenStorage.deleteAll();
      return null;
    }
  }

  /// Save tokens
  static Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    await TokenStorage.write('access_token', access);
    await TokenStorage.write('refresh_token', refresh);
  }

  /// Clear all stored tokens (on logout)
  static Future<void> clearTokens() async {
    await TokenStorage.deleteAll();
  }

  /// Read stored access token
  static Future<String?> getAccessToken() => TokenStorage.read('access_token');
}
