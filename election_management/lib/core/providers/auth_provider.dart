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
    String? adminName,
    String? prefix,
    String? councilNumber,
    String? orgEmail,
    String? orgPhone,
    String? website,
    String? address,
    String? logoUrl,
    String? coverImageUrl,
    String? bankName,
    String? bankBranch,
    String? bankAccountNumber,
    String? bankAccountName,
    String? bankSwiftCode,
    String? bankQrUrl,
    Map<String, dynamic>? typeMetadata,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final resp = await _dio.post(ApiConstants.register, data: {
        'email': email,
        'password': password,
        'org_name': orgName,
        'org_type': orgType,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (adminName != null && adminName.isNotEmpty) 'admin_name': adminName,
        if (prefix != null && prefix.isNotEmpty) 'prefix': prefix,
        if (councilNumber != null && councilNumber.isNotEmpty) 'council_number': councilNumber,
        if (orgEmail != null && orgEmail.isNotEmpty) 'org_email': orgEmail,
        if (orgPhone != null && orgPhone.isNotEmpty) 'org_phone': orgPhone,
        if (website != null && website.isNotEmpty) 'website': website,
        if (address != null && address.isNotEmpty) 'address': address,
        if (logoUrl != null && logoUrl.isNotEmpty) 'logo_url': logoUrl,
        if (coverImageUrl != null && coverImageUrl.isNotEmpty) 'cover_image_url': coverImageUrl,
        if (bankName != null && bankName.isNotEmpty) 'bank_name': bankName,
        if (bankBranch != null && bankBranch.isNotEmpty) 'bank_branch': bankBranch,
        if (bankAccountNumber != null && bankAccountNumber.isNotEmpty) 'bank_account_number': bankAccountNumber,
        if (bankAccountName != null && bankAccountName.isNotEmpty) 'bank_account_name': bankAccountName,
        if (bankSwiftCode != null && bankSwiftCode.isNotEmpty) 'bank_swift_code': bankSwiftCode,
        if (bankQrUrl != null && bankQrUrl.isNotEmpty) 'bank_qr_url': bankQrUrl,
        if (typeMetadata != null && typeMetadata.isNotEmpty) 'type_metadata': typeMetadata,
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

  Future<String?> requestPasswordReset(String email) async {
    try {
      await _dio.post(ApiConstants.passwordResetRequest, data: {'email': email});
      return null;
    } on DioException catch (e) {
      return _extractError(e);
    }
  }

  Future<String?> confirmPasswordReset({
    required String email,
    required String otp,
    required String newPassword,
    required String confirmPassword,
  }) async {
    try {
      await _dio.post(ApiConstants.passwordResetConfirm, data: {
        'email': email,
        'otp': otp,
        'new_password': newPassword,
        'confirm_password': confirmPassword,
      });
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
      if (err is Map) {
        // Prefer specific field errors over the generic 'An error occurred' wrapper message
        final fieldErrors = err['field_errors'];
        if (fieldErrors is Map && fieldErrors.isNotEmpty) {
          final firstKey = fieldErrors.keys.first;
          final firstVal = fieldErrors[firstKey];
          if (firstVal is List && firstVal.isNotEmpty) return firstVal.first.toString();
        }
        // Fall back to the top-level message only if no field errors
        final msg = err['message'] as String?;
        if (msg != null && msg.isNotEmpty && msg != 'An error occurred.') return msg;
      }
      if (err is String) return err;
      final nonField = data['non_field_errors'];
      if (nonField is List && nonField.isNotEmpty) return nonField.first as String;
      // Check top-level field errors (standard DRF format)
      final fieldErrors = data['field_errors'];
      if (fieldErrors is Map && fieldErrors.isNotEmpty) {
        final firstKey = fieldErrors.keys.first;
        final firstVal = fieldErrors[firstKey];
        if (firstVal is List && firstVal.isNotEmpty) return firstVal.first.toString();
      }
      // Standard DRF field errors at top level
      for (final key in data.keys) {
        if (key == 'error') continue;
        final val = data[key];
        if (val is List && val.isNotEmpty) {
          return val.first.toString();
        }
      }
    }
    return e.response?.statusMessage ?? e.message ?? 'Network error. Please check your connection.';
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
