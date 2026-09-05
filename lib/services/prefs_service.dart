import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferensi ringan. API key dipindahkan ke secure storage pada V4 agar tidak
/// lagi disimpan sebagai plaintext di SharedPreferences.
class PrefsService {
  static const _kApiKey = 'gemini_api_key';
  static const _kSheetsUrl = 'sheets_webhook_url';
  static const _kAiProxyUrl = 'ai_proxy_url';
  static const _kLastSync = 'last_sync_time';

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  static Future<String> getApiKey() async {
    final secure = await _secureStorage.read(key: _kApiKey);
    if (secure != null && secure.isNotEmpty) return secure;

    // Migrasi otomatis dari versi lama yang menyimpan API key di prefs.
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(_kApiKey) ?? '';
    if (legacy.isNotEmpty) {
      await _secureStorage.write(key: _kApiKey, value: legacy);
      await prefs.remove(_kApiKey);
    }
    return legacy;
  }

  static Future<void> setApiKey(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _secureStorage.delete(key: _kApiKey);
    } else {
      await _secureStorage.write(key: _kApiKey, value: trimmed);
    }

    // Hapus key legacy bila masih ada.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kApiKey);
  }


  static Future<String> getAiProxyUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kAiProxyUrl) ?? '';
  }

  static Future<void> setAiProxyUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAiProxyUrl, value.trim());
  }

  static Future<String> getSheetsUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kSheetsUrl) ?? '';
  }

  static Future<void> setSheetsUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSheetsUrl, value.trim());
  }

  static Future<String?> getLastSync() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kLastSync);
  }

  static Future<void> setLastSync(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastSync, value);
  }
}
