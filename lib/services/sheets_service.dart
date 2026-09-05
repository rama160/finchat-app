import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/transaction_model.dart';
import 'database_helper.dart';
import 'prefs_service.dart';

/// Sinkronisasi offline-first dengan Google Sheets melalui Apps Script.
/// Mendukung batch upload, retry redirect Google (302/307), dan restore
/// otomatis ketika database lokal masih kosong setelah reinstall.
class SheetsService {
  static Future<http.Response> _postJson(
    Uri uri,
    Map<String, dynamic> payload,
  ) async {
    var current = uri;
    for (var attempt = 0; attempt < 4; attempt++) {
      final response = await http
          .post(
            current,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      }

      final location = response.headers['location'];
      if ((response.statusCode == 301 ||
              response.statusCode == 302 ||
              response.statusCode == 303 ||
              response.statusCode == 307 ||
              response.statusCode == 308) &&
          location != null &&
          location.isNotEmpty) {
        current = Uri.parse(location);
        continue;
      }

      throw Exception(
        'Google Sheets HTTP ${response.statusCode}: ${response.body.isEmpty ? 'Tidak ada respons.' : response.body}',
      );
    }

    throw Exception('Google Sheets terlalu banyak redirect.');
  }

  static Future<http.Response> _get(Uri uri) async {
    var current = uri;
    for (var attempt = 0; attempt < 4; attempt++) {
      final response = await http
          .get(current, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 20));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      }

      final location = response.headers['location'];
      if ((response.statusCode == 301 ||
              response.statusCode == 302 ||
              response.statusCode == 303 ||
              response.statusCode == 307 ||
              response.statusCode == 308) &&
          location != null &&
          location.isNotEmpty) {
        current = Uri.parse(location);
        continue;
      }

      throw Exception(
        'Google Sheets HTTP ${response.statusCode}: ${response.body}',
      );
    }

    throw Exception('Google Sheets terlalu banyak redirect.');
  }


  static Future<String> checkConnection() async {
    final url = await PrefsService.getSheetsUrl();
    if (url.trim().isEmpty) {
      throw Exception('URL Google Sheets belum diatur.');
    }
    final uri = Uri.parse(url.trim()).replace(
      queryParameters: {
        ...Uri.parse(url.trim()).queryParameters,
        'action': 'health',
      },
    );
    final response = await _get(uri);
    final decoded = jsonDecode(response.body);
    if (decoded is Map && decoded['status'] == 'ok') {
      return decoded['message']?.toString() ?? 'Google Sheets aktif.';
    }
    throw Exception('Respons Apps Script tidak valid.');
  }

  static Future<int> syncUnsyncedTransactions() async {
    final url = await PrefsService.getSheetsUrl();
    if (url.trim().isEmpty) {
      throw Exception('URL Google Sheets belum diatur di halaman Pengaturan.');
    }

    final unsynced = await DatabaseHelper.instance.getUnsyncedTransactions();
    var successCount = 0;

    // Sinkronkan penghapusan terlebih dahulu agar restore setelah reinstall
    // tidak menghidupkan kembali transaksi yang memang sudah dihapus.
    final deletedIds = await DatabaseHelper.instance.getDeletedTransactionIds();
    if (deletedIds.isNotEmpty) {
      final deleteResponse = await _postJson(
        Uri.parse(url.trim()),
        {
          'action': 'delete',
          'ids': deletedIds,
        },
      );
      final decoded = deleteResponse.body.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(deleteResponse.body);
      if (decoded is! Map || decoded['status'] != 'ok') {
        throw Exception('Apps Script gagal menghapus transaksi di Sheets.');
      }
      final removed = (decoded['ids'] is List)
          ? (decoded['ids'] as List)
              .map((e) => int.tryParse(e.toString()))
              .whereType<int>()
              .toList()
          : deletedIds;
      await DatabaseHelper.instance.clearDeletedTransactionIds(removed);
      successCount += removed.length;
    }

    if (unsynced.isEmpty) {
      await PrefsService.setLastSync(DateTime.now().toIso8601String());
      return 0;
    }

    // Batch mengurangi request dan menghindari kegagalan parsial yang sering
    // terjadi ketika Apps Script dipanggil satu per satu.
    const batchSize = 50;
    for (var start = 0; start < unsynced.length; start += batchSize) {
      final end =
          (start + batchSize > unsynced.length) ? unsynced.length : start + batchSize;
      final batch = unsynced.sublist(start, end);

      final response = await _postJson(
        Uri.parse(url.trim()),
        {
          'action': 'sync',
          'transactions': batch.map((tx) => tx.toMap()).toList(),
        },
      );

      Map<String, dynamic> body = {};
      if (response.body.trim().isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          body = Map<String, dynamic>.from(decoded);
        }
      }

      if (body['status'] != 'ok') {
        throw Exception(
          'Apps Script tidak mengonfirmasi sinkronisasi: ${response.body}',
        );
      }

      final syncedIds = (body['ids'] is List)
          ? (body['ids'] as List)
              .map((e) => int.tryParse(e.toString()))
              .whereType<int>()
              .toSet()
          : batch.map((tx) => tx.id).whereType<int>().toSet();

      for (final id in syncedIds) {
        await DatabaseHelper.instance.markAsSynced(id);
        successCount++;
      }
    }

    await PrefsService.setLastSync(DateTime.now().toIso8601String());
    return successCount;
  }

  /// Memulihkan seluruh transaksi dari Sheets hanya jika SQLite lokal kosong.
  /// Ini membuat riwayat dapat kembali setelah aplikasi di-uninstall/reinstall,
  /// selama sebelumnya sudah pernah tersinkron ke Sheets.
  static Future<int> restoreIfLocalEmpty() async {
    final local = await DatabaseHelper.instance.getAllTransactions();
    if (local.isNotEmpty) return 0;

    final url = await PrefsService.getSheetsUrl();
    if (url.trim().isEmpty) return 0;

    final uri = Uri.parse(url.trim()).replace(
      queryParameters: {
        ...Uri.parse(url.trim()).queryParameters,
        'action': 'list',
      },
    );

    final response = await _get(uri);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['status'] != 'ok') {
      throw Exception('Format data pemulihan Google Sheets tidak valid.');
    }

    final rows = decoded['transactions'];
    if (rows is! List) return 0;

    var restored = 0;
    for (final raw in rows) {
      if (raw is! Map) continue;
      final amount = double.tryParse(raw['amount']?.toString() ?? '') ?? 0;
      if (amount <= 0) continue;

      await DatabaseHelper.instance.insertTransaction(
        TransactionModel(
          transactionDate:
              raw['transaction_date']?.toString() ?? DateTime.now().toString().substring(0, 10),
          transactionTime: raw['transaction_time']?.toString() ?? '00:00:00',
          type: raw['type']?.toString() == 'income' ? 'income' : 'expense',
          category: raw['category']?.toString() ?? 'Lainnya',
          description: raw['description']?.toString() ?? 'Transaksi',
          amount: amount,
          paymentMethod: raw['payment_method']?.toString() ?? 'Cash',
          merchant: raw['merchant']?.toString() ?? '',
          notes: raw['notes']?.toString() ?? '',
          source: raw['source']?.toString() ?? 'sheets_restore',
          isSynced: 1,
        ),
      );
      restored++;
    }

    return restored;
  }
}
