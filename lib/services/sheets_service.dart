import 'dart:convert';
import 'package:http/http.dart' as http;
import 'database_helper.dart';
import 'prefs_service.dart';

/// Sinkronisasi "cloud" sederhana menggunakan Google Sheets sebagai backend,
/// lewat Google Apps Script Web App (tidak butuh OAuth di sisi aplikasi
/// mobile, cocok untuk pola offline-first: data selalu tersimpan dulu ke
/// SQLite lokal, lalu disinkronkan ke Sheets saat online).
///
/// Cara setup (dijelaskan juga di layar Pengaturan):
/// 1. Buat Google Sheet baru.
/// 2. Extensions > Apps Script, tempel kode berikut lalu Deploy > Web App
///    (Execute as: Me, Who has access: Anyone):
///
/// function doPost(e) {
///   const sheet = SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
///   const data = JSON.parse(e.postData.contents);
///   sheet.appendRow([
///     data.id, data.chat_id, data.transaction_date, data.transaction_time,
///     data.type, data.category, data.description, data.amount,
///     data.payment_method, data.merchant, data.notes, data.source
///   ]);
///   return ContentService.createTextOutput(JSON.stringify({status: 'ok'}))
///       .setMimeType(ContentService.MimeType.JSON);
/// }
///
/// 3. Salin URL Web App yang dihasilkan ke layar Pengaturan.
class SheetsService {
  static Future<int> syncUnsyncedTransactions() async {
    final url = await PrefsService.getSheetsUrl();
    if (url.trim().isEmpty) {
      throw Exception('URL Google Sheets belum diatur di halaman Pengaturan.');
    }

    final unsynced = await DatabaseHelper.instance.getUnsyncedTransactions();
    int successCount = 0;

    for (final tx in unsynced) {
      try {
        final response = await http
            .post(
              Uri.parse(url),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(tx.toMap()),
            )
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 200 && tx.id != null) {
          await DatabaseHelper.instance.markAsSynced(tx.id!);
          successCount++;
        }
      } catch (_) {
        // Lewati transaksi ini (mis. koneksi terputus), lanjutkan yang lain.
        // Transaksi tetap tersimpan aman secara lokal (offline-first).
      }
    }

    await PrefsService.setLastSync(DateTime.now().toIso8601String());
    return successCount;
  }
}
