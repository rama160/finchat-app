import 'package:shared_preferences/shared_preferences.dart';

/// Penyimpanan preferensi ringan (API key Gemini, URL Google Sheets, waktu
/// sync terakhir) agar bisa dipakai bersama oleh Dashboard, Chat, Laporan,
/// dan Pengaturan tanpa mengubah cara HomeScreen yang sudah ada bekerja.
class PrefsService {
  static const _kApiKey = 'gemini_api_key';
  static const _kSheetsUrl = 'sheets_webhook_url';
  static const _kLastSync = 'last_sync_time';

  static Future<String> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kApiKey) ?? '';
  }

  static Future<void> setApiKey(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kApiKey, value);
  }

  static Future<String> getSheetsUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kSheetsUrl) ?? '';
  }

  static Future<void> setSheetsUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSheetsUrl, value);
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
