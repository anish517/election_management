import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';
import '../../core/network/token_storage.dart';
import '../../shared/models/models.dart';

// ─── Auth State ───────────────────────────────────────────────────────────────

class AuthState {
  final UserModel? user;
  final bool isLoading;
  final String? error;

  const AuthState({this.user, this.isLoading = false, this.error});

  bool get isAuthenticated => user != null;

  AuthState copyWith({UserModel? user, bool? isLoading, String? error}) =>
      AuthState(
        user: user ?? this.user,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

// ─── Auth Notifier ────────────────────────────────────────────────────────────

class AuthNotifier extends StateNotifier<AuthState> {
  final Dio _dio;

  AuthNotifier(this._dio) : super(const AuthState()) {
    _checkStoredAuth();
  }

  Future<void> refreshUser() async {
    final token = await JwtInterceptor.getAccessToken();
    if (token == null) return;
    try {
      final resp = await _dio.get(ApiConstants.me);
      final user = UserModel.fromJson(resp.data as Map<String, dynamic>);
      state = AuthState(user: user);
    } catch (_) {
      // Don't log out if refresh fails, just keep existing state
    }
  }

  Future<void> _checkStoredAuth() async {
    final token = await JwtInterceptor.getAccessToken();
    if (token == null) return;
    try {
      state = state.copyWith(isLoading: true);
      final resp = await _dio.get(ApiConstants.me);
      final user = UserModel.fromJson(resp.data as Map<String, dynamic>);
      state = AuthState(user: user);
    } catch (_) {
      await JwtInterceptor.clearTokens();
      state = const AuthState();
    }
  }

  Future<String?> login({required String emailOrPhone, required String password}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final resp = await _dio.post(ApiConstants.login, data: {
        'email_or_phone': emailOrPhone,
        'password': password,
      });
      final data = resp.data as Map<String, dynamic>;
      await JwtInterceptor.saveTokens(
        access: data['access'] as String,
        refresh: data['refresh'] as String,
      );
      // Try to get user info from response, fallback to /me
      UserModel user;
      if (data.containsKey('user') && data['user'] != null) {
        user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
      } else {
        final meResp = await _dio.get(ApiConstants.me);
        user = UserModel.fromJson(meResp.data as Map<String, dynamic>);
      }
      state = AuthState(user: user);
      return null;
    } on DioException catch (e) {
      final msg = _extractError(e);
      state = AuthState(error: msg);
      return msg;
    }
  }

  Future<String?> register({
    required String email,
    required String password,
    required String orgName,
    required String orgType,
    String? phone,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final resp = await _dio.post(ApiConstants.register, data: {
        'email': email,
        'password': password,
        'org_name': orgName,
        'org_type': orgType,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      });
      final data = resp.data as Map<String, dynamic>;
      await JwtInterceptor.saveTokens(
        access: data['access'] as String,
        refresh: data['refresh'] as String,
      );
      UserModel user;
      if (data.containsKey('user') && data['user'] != null) {
        user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
      } else {
        final meResp = await _dio.get(ApiConstants.me);
        user = UserModel.fromJson(meResp.data as Map<String, dynamic>);
      }
      state = AuthState(user: user);
      return null;
    } on DioException catch (e) {
      final msg = _extractError(e);
      state = AuthState(error: msg);
      return msg;
    }
  }

  Future<String?> loginWithOtp({required String phoneOrEmail, required String otp}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final resp = await _dio.post(ApiConstants.otpVerify, data: {
        'phone_or_email': phoneOrEmail,
        'otp': otp,
      });
      final data = resp.data as Map<String, dynamic>;
      await JwtInterceptor.saveTokens(
        access: data['access'] as String,
        refresh: data['refresh'] as String,
      );
      UserModel user;
      if (data.containsKey('user') && data['user'] != null) {
        user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
      } else {
        final meResp = await _dio.get(ApiConstants.me);
        user = UserModel.fromJson(meResp.data as Map<String, dynamic>);
      }
      state = AuthState(user: user);
      return null;
    } on DioException catch (e) {
      final msg = _extractError(e);
      state = AuthState(error: msg);
      return msg;
    }
  }

  Future<String?> requestOtp(String phoneOrEmail) async {
    try {
      await _dio.post(ApiConstants.otpRequest, data: {'phone_or_email': phoneOrEmail});
      return null;
    } on DioException catch (e) {
      return _extractError(e);
    }
  }

  Future<void> logout() async {
    try {
      final refresh = await TokenStorage.read('refresh_token');
      if (refresh != null) {
        await _dio.post(ApiConstants.logout, data: {'refresh': refresh});
      }
    } catch (_) {}
    await JwtInterceptor.clearTokens();
    state = const AuthState();
  }

  String _extractError(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final err = data['error'];
      if (err is Map) return err['message'] as String? ?? 'An error occurred';
      if (err is String) return err;
      final nonField = data['non_field_errors'];
      if (nonField is List && nonField.isNotEmpty) return nonField.first as String;
      // Check field errors
      final fieldErrors = data['field_errors'];
      if (fieldErrors is Map && fieldErrors.isNotEmpty) {
        final firstKey = fieldErrors.keys.first;
        final firstVal = fieldErrors[firstKey];
        if (firstVal is List && firstVal.isNotEmpty) return firstVal.first.toString();
      }
    }
    return e.message ?? 'Network error. Please check your connection.';
  }
}

// ─── Providers ────────────────────────────────────────────────────────────────

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final dio = ref.watch(apiClientProvider);
  return AuthNotifier(dio);
});

final currentUserProvider = Provider<UserModel?>((ref) {
  return ref.watch(authProvider).user;
});
