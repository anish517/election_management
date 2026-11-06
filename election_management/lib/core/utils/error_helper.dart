import 'package:dio/dio.dart';

/// Formats and extracts clean, human-readable error messages from any API error / DioException
String extractApiErrorMessage(
  dynamic e, {
  String fallback = 'An unexpected error occurred. Please try again.',
  String? fallbackMessage,
}) {
  final resolvedFallback = fallbackMessage ?? fallback;
  if (e == null) return resolvedFallback;

  if (e is DioException) {
    // 1. Intercept low-level browser network/CORS crashes before checking response
    final rawMsg = e.message ?? '';
    final rawErr = e.error?.toString() ?? '';
    if (rawMsg.contains('XMLHttpRequest') ||
        rawMsg.contains('CORS') ||
        rawErr.contains('XMLHttpRequest') ||
        rawErr.contains('CORS')) {
      return 'Unable to reach the election server. Please check your network connection and try again.';
    }

    if (e.response != null) {
      final statusCode = e.response!.statusCode;
      final data = e.response!.data;

      if (data is Map) {
        // 1. DRF standard 'detail' field (e.g. ValidationError, PermissionDenied, NotFound)
        if (data.containsKey('detail') && data['detail'] != null) {
          final detail = data['detail'];
          if (detail is String && detail.isNotEmpty) return detail;
          if (detail is List && detail.isNotEmpty) return detail.first.toString();
        }

        // 2. Custom 'error' object/string
        if (data.containsKey('error') && data['error'] != null) {
          final err = data['error'];
          if (err is String && err.isNotEmpty) return err;
          if (err is Map && err['message'] != null) return err['message'].toString();
        }

        // 3. 'message' field
        if (data.containsKey('message') && data['message'] != null) {
          final msg = data['message'].toString();
          if (msg.isNotEmpty) return msg;
        }

        // 4. 'non_field_errors'
        if (data.containsKey('non_field_errors')) {
          final nonField = data['non_field_errors'];
          if (nonField is List && nonField.isNotEmpty) return nonField.first.toString();
          if (nonField is String && nonField.isNotEmpty) return nonField;
        }

        // 5. Field-level validation errors (e.g. {'claimant_email': ['Enter a valid email address.']})
        for (final entry in data.entries) {
          final key = entry.key;
          final val = entry.value;
          if (val is List && val.isNotEmpty) {
            final fieldName = key.replaceAll('_', ' ');
            final capitalized = fieldName.isNotEmpty ? '${fieldName[0].toUpperCase()}${fieldName.substring(1)}' : key;
            return '$capitalized: ${val.first}';
          } else if (val is String && val.isNotEmpty) {
            return val;
          }
        }
      } else if (data is String && data.isNotEmpty) {
        // Return raw text if not HTML
        if (!data.contains('<html') && !data.contains('<!DOCTYPE')) {
          return data;
        }
      }

      // Default status code fallbacks
      if (statusCode == 400) return 'Invalid request. Please verify your details.';
      if (statusCode == 401) return 'Session expired. Please log in again to continue.';
      if (statusCode == 403) return 'Access denied. You do not have permission for this action.';
      if (statusCode == 404) return 'The requested resource was not found.';
      if (statusCode == 409) return 'Conflict: A duplicate entry already exists.';
      if (statusCode == 410) return 'This single-use link has expired or has already been used.';
      if (statusCode != null && statusCode >= 500) {
        return 'The election server is momentarily unavailable. Please try again in a few moments.';
      }
    }

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timed out. Please check your network connection and try again.';
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return 'Unable to reach the election server. Please check your network connection and try again.';
      case DioExceptionType.cancel:
        return 'The request was cancelled.';
      default:
        break;
    }
  }

  // Handle String representations that might contain raw browser errors
  final str = e.toString().replaceFirst('Exception: ', '').trim();
  if (str.contains('XMLHttpRequest') || str.contains('DioException') || str.contains('CORS')) {
    return 'Unable to reach the election server. Please check your network connection and try again.';
  }

  if (str.isNotEmpty && str != 'null') return str;

  return resolvedFallback;
}

/// Helper to detect if an error is due to session or authentication expiration
bool isSessionExpiredError(dynamic e) {
  if (e is DioException) {
    if (e.response?.statusCode == 401) return true;
    final data = e.response?.data;
    if (data is Map) {
      final msg = (data['error'] ?? data['detail'] ?? data['message'] ?? '').toString().toLowerCase();
      if (msg.contains('session') && (msg.contains('expired') || msg.contains('invalid') || msg.contains('used'))) {
        return true;
      }
      if (msg.contains('token is invalid') || msg.contains('token expired') || msg.contains('unauthorized')) {
        return true;
      }
    }
  }
  final s = e.toString().toLowerCase();
  return s.contains('session expired') ||
      s.contains('session is expired') ||
      s.contains('unauthorized') ||
      s.contains('token is invalid') ||
      s.contains('token expired') ||
      (s.contains('session') && s.contains('expired'));
}
