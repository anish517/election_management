import 'package:dio/dio.dart';
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
      headers: {'Content-Type': 'application/json'},
    ),
  );

  dio.interceptors.add(JwtInterceptor(dio));
  return dio;
});

class JwtInterceptor extends Interceptor {
  final Dio _dio;
  JwtInterceptor(this._dio);

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
    if (err.response?.statusCode == 401) {
      try {
        final refreshToken = await TokenStorage.read('refresh_token');
        if (refreshToken == null) {
          handler.next(err);
          return;
        }
        final refreshDio = Dio(BaseOptions(baseUrl: ApiConstants.baseUrl));
        final resp = await refreshDio.post(
          ApiConstants.tokenRefresh,
          data: {'refresh': refreshToken},
        );
        final newAccess = resp.data['access'] as String;
        await TokenStorage.write('access_token', newAccess);

        // Retry original request with new token
        err.requestOptions.headers['Authorization'] = 'Bearer $newAccess';
        final cloned = await _dio.fetch(err.requestOptions);
        handler.resolve(cloned);
      } catch (_) {
        await TokenStorage.deleteAll();
        handler.next(err);
      }
    } else {
      handler.next(err);
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
