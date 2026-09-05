import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/transaction_model.dart';
import 'database_helper.dart';
import 'prefs_service.dart';

/// Sinkronisasi offline-first dengan Google Sheets melalui Apps Script.
/// Mendukung batch upload, retry redirect Google (302/307), dan restore
/// otomatis ketika database lokal masih kosong setelah reinstall.
class SheetsService {
  static bool _syncInProgress = false;

  static String _compactResponse(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return 'Respons server kosong.';
    // Jangan pernah meneruskan HTML/JavaScript Google yang sangat panjang ke UI.
    if (trimmed.startsWith('<') || trimmed.contains('<!DOCTYPE') ||
        trimmed.contains('<html')) {
      return 'Google Sheets mengembalikan halaman web, bukan respons API JSON. Pastikan URL yang dipakai adalah Web App /exec.';
    }
    if (trimmed.length > 500) {
      return '${trimmed.substring(0, 500)}…';
    }
    return trimmed;
  }
  static Future<http.Response> _postJson(
    Uri uri,
    Map<String, dynamic> payload,
  ) async {
    // Google Apps Script Web App biasanya mengembalikan 302 ke host
    // script.googleusercontent.com. package:http dapat mengikuti redirect
    // POST secara otomatis dan pada beberapa kombinasi runtime mengubahnya
    // menjadi GET. Akibatnya Apps Script menerima doGet(), bukan doPost().
    // Karena itu redirect ditangani manual dan method POST dipertahankan.
    var current = uri;
    for (var attempt = 0; attempt < 5; attempt++) {
      final request = http.Request('POST', current)
        ..followRedirects = false
        ..maxRedirects = 0
        ..headers.addAll({
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json',
        })
        ..body = jsonEncode(payload);

      final streamed = await request.send().timeout(const Duration(seconds: 25));
      final response = await http.Response.fromStream(streamed);

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
        current = current.resolve(location);
        continue;
      }

      throw Exception(
        'Google Sheets HTTP ${response.statusCode}: '
        '${_compactResponse(response.body)}',
      );
    }

    throw Exception('Google Sheets terlalu banyak redirect. Gunakan URL Web App /exec.');
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
        'Google Sheets HTTP ${response.statusCode}: ${_compactResponse(response.body)}',
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
    if (_syncInProgress) return 0;
    _syncInProgress = true;
    try {
      return await _syncUnsyncedTransactionsInternal();
    } finally {
      _syncInProgress = false;
    }
  }

  static Future<int> _syncUnsyncedTransactionsInternal() async {
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
      if (decoded is! Map || (decoded['status'] != 'ok' && decoded['result'] != 'success')) {
        throw Exception('Apps Script gagal menghapus transaksi di Sheets.');
      }
      final rawRemovedIds = decoded['ids'] is List
          ? decoded['ids'] as List
          : (decoded['deleted_ids'] is List ? decoded['deleted_ids'] as List : const []);
      final removed = rawRemovedIds
          .map((e) => int.tryParse(e.toString()))
          .whereType<int>()
          .toList();
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

      if (body['status'] != 'ok' && body['result'] != 'success') {
        throw Exception(
          'Apps Script tidak mengonfirmasi sinkronisasi: ${_compactResponse(response.body)}',
        );
      }

      final rawSyncedIds = body['ids'] is List
          ? body['ids'] as List
          : (body['confirmed_ids'] is List ? body['confirmed_ids'] as List : const []);
      final syncedIds = rawSyncedIds
          .map((e) => int.tryParse(e.toString()))
          .whereType<int>()
          .toSet();

      if (syncedIds.isEmpty) {
        throw Exception(
          'Apps Script mengembalikan 0 transaksi tersinkron. Respons: ${_compactResponse(response.body)}',
        );
      }

      for (final id in syncedIds) {
        await DatabaseHelper.instance.markAsSynced(id);
        successCount++;
      }
    }

    await PrefsService.setLastSync(DateTime.now().toIso8601String());
    return successCount;
  }

  /// Sinkronkan SEMUA transaksi lokal, termasuk yang sebelumnya bertanda
  /// is_synced=1. Berguna untuk migrasi dari versi lama yang mungkin pernah
  /// salah menandai transaksi sebagai tersinkron walaupun baris belum masuk Sheets.
  static Future<int> syncAllTransactions() async {
    final url = await PrefsService.getSheetsUrl();
    if (url.trim().isEmpty) {
      throw Exception('URL Google Sheets belum diatur di halaman Pengaturan.');
    }

    final all = await DatabaseHelper.instance.getAllTransactions();
    if (all.isEmpty) return 0;

    var successCount = 0;
    const batchSize = 50;
    for (var start = 0; start < all.length; start += batchSize) {
      final end = (start + batchSize > all.length) ? all.length : start + batchSize;
      final batch = all.sublist(start, end);
      final response = await _postJson(
        Uri.parse(url.trim()),
        {
          'action': 'sync',
          'transactions': batch.map((tx) => tx.toMap()).toList(),
        },
      );

      final decoded = response.body.trim().isEmpty ? null : jsonDecode(response.body);
      final body = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
      if (body['status'] != 'ok' && body['result'] != 'success') {
        throw Exception('Apps Script gagal sinkronisasi: ${_compactResponse(response.body)}');
      }

      final rawIds = body['ids'] is List
          ? body['ids'] as List
          : (body['confirmed_ids'] is List ? body['confirmed_ids'] as List : const []);
      final syncedIds = rawIds
          .map((e) => int.tryParse(e.toString()))
          .whereType<int>()
          .toSet();
      if (syncedIds.isEmpty) {
        throw Exception('Apps Script mengembalikan 0 transaksi. Respons: ${_compactResponse(response.body)}');
      }
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

    final transactions = <TransactionModel>[];
    for (final raw in rows) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final amount = double.tryParse(map['amount']?.toString() ?? '') ?? 0;
      final id = int.tryParse(map['id']?.toString() ?? '');
      if (amount <= 0 || id == null) continue;
      map['id'] = id;
      map['is_synced'] = 1;
      transactions.add(TransactionModel.fromMap(map));
    }

    // Pertahankan ID asli dari Sheets. Ini penting agar edit setelah restore
    // tetap meng-update baris yang sama, bukan membuat duplikat baru.
    await DatabaseHelper.instance.restoreTransactions(transactions);
    return transactions.length;
  }
}
