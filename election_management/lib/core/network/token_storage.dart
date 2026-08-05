import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cross-platform token storage.
/// Uses flutter_secure_storage on mobile/web, shared_preferences on Windows desktop
/// (avoids ATL dependency on Windows).
class TokenStorage {
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static bool get _useSecure => !kIsWeb
      ? defaultTargetPlatform != TargetPlatform.windows &&
            defaultTargetPlatform != TargetPlatform.linux &&
            defaultTargetPlatform != TargetPlatform.macOS
      : false;

  static Future<void> write(String key, String value) async {
    if (_useSecure) {
      await _secureStorage.write(key: key, value: value);
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    }
  }

  static Future<String?> read(String key) async {
    if (_useSecure) {
      return _secureStorage.read(key: key);
    } else {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    }
  }

  static Future<void> delete(String key) async {
    if (_useSecure) {
      await _secureStorage.delete(key: key);
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    }
  }

  static Future<void> deleteAll() async {
    if (_useSecure) {
      await _secureStorage.deleteAll();
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('access_token');
      await prefs.remove('refresh_token');
    }
  }
}
