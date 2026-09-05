import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../models/transaction_model.dart';
import 'database_helper.dart';

/// Backup/restore portabel untuk migrasi perangkat atau reinstall.
///
/// File backup disimpan di lokasi yang dipilih pengguna sehingga tidak
/// bergantung pada storage internal aplikasi.
class BackupService {
  static const String _format = 'finchat_backup';
  static const int _version = 1;

  /// Membuat backup seluruh transaksi dan daftar transaksi yang telah dihapus.
  ///
  /// Mengembalikan URI lokasi file backup jika berhasil disimpan.
  /// Mengembalikan null jika pengguna membatalkan.
  static Future<Uri?> createBackup() async {
    final transactions =
        await DatabaseHelper.instance.getAllTransactions();

    final deletedIds =
        await DatabaseHelper.instance.getDeletedTransactionIds();

    final payload = {
      'format': _format,
      'version': _version,
      'created_at': DateTime.now().toIso8601String(),
      'transactions': transactions
          .map((transaction) => transaction.toMap())
          .toList(),
      'deleted_transaction_ids': deletedIds,
    };

    final jsonData =
        const JsonEncoder.withIndent('  ').convert(payload);

    final bytes = Uint8List.fromList(
      utf8.encode(jsonData),
    );

    final fileName =
        'finchat_backup_${DateTime.now().millisecondsSinceEpoch}.json';

    final uri = await FilePicker.saveFile(
      dialogTitle: 'Simpan Backup Finchat',
      fileName: fileName,
      mimeType: 'application/json',
      bytes: bytes,
    );

    return uri;
  }

  /// Memilih dan memulihkan file backup Finchat.
  ///
  /// Secara default restore hanya dilakukan ketika database lokal kosong,
  /// agar data yang sudah ada tidak tertimpa.
  ///
  /// Mengembalikan jumlah transaksi yang berhasil dipulihkan.
  static Future<int> restoreBackup({
    bool requireEmpty = true,
  }) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (file == null) {
      return 0;
    }

    final data = await file.readAsBytes();

    if (data.isEmpty) {
      throw Exception('File backup kosong.');
    }

    final jsonText = utf8.decode(data);
    final decoded = jsonDecode(jsonText);

    if (decoded is! Map) {
      throw Exception('Format backup tidak valid.');
    }

    if (decoded['format'] != _format) {
      throw Exception(
        'File bukan backup Finchat AI yang valid.',
      );
    }

    final rows = decoded['transactions'];

    if (rows is! List) {
      throw Exception(
        'Data transaksi di backup tidak valid.',
      );
    }

    final local =
        await DatabaseHelper.instance.getAllTransactions();

    if (requireEmpty && local.isNotEmpty) {
      throw Exception(
        'Database lokal masih berisi ${local.length} transaksi. '
        'Restore dibatalkan agar data tidak tertimpa.',
      );
    }

    final transactions = <TransactionModel>[];

    for (final raw in rows) {
      if (raw is! Map) {
        continue;
      }

      try {
        final map = Map<String, dynamic>.from(raw);

        final amount =
            double.tryParse(map['amount']?.toString() ?? '') ?? 0;

        if (amount <= 0) {
          continue;
        }

        transactions.add(
          TransactionModel.fromMap(map),
        );
      } catch (_) {
        // Lewati transaksi yang rusak agar transaksi lainnya
        // tetap dapat dipulihkan.
      }
    }

    await DatabaseHelper.instance.restoreTransactions(
      transactions,
    );

    final deleted = <int>[];

    final deletedRaw =
        decoded['deleted_transaction_ids'];

    if (deletedRaw is List) {
      for (final value in deletedRaw) {
        final id = int.tryParse(value.toString());

        if (id != null) {
          deleted.add(id);
        }
      }
    }

    await DatabaseHelper.instance.restoreDeletedTransactionIds(
      deleted,
    );

    return transactions.length;
  }
}
