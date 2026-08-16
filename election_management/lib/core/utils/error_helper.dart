import 'package:dio/dio.dart';

/// Formats and extracts clean, human-readable error messages from any API error / DioException
String extractApiErrorMessage(dynamic e, {String fallback = 'An unexpected error occurred. Please try again.'}) {
  if (e is DioException) {
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
      if (statusCode == 401) return 'Session expired. Please log in again.';
      if (statusCode == 403) return 'Permission denied. You do not have permission for this action.';
      if (statusCode == 404) return 'The requested resource was not found.';
      if (statusCode == 409) return 'Conflict: A duplicate entry already exists.';
      if (statusCode != null && statusCode >= 500) return 'Server error. Please contact the administrator.';
    }

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timed out. Please check your network and try again.';
      case DioExceptionType.connectionError:
        return 'Unable to reach the server. Please check your network connection.';
      case DioExceptionType.cancel:
        return 'The request was cancelled.';
      default:
        break;
    }
  }

  if (e is String && e.isNotEmpty) return e;
  if (e is Exception) {
    final str = e.toString().replaceFirst('Exception: ', '').trim();
    if (str.isNotEmpty && !str.contains('DioException')) return str;
  }

  return fallback;
}
