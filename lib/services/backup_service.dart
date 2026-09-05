import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:finchat_app/models/transaction_model.dart';
import 'package:finchat_app/services/database_helper.dart';

class BackupService {
  static final DatabaseHelper _db = DatabaseHelper.instance;

  /// Membuat JSON backup dari seluruh transaksi.
  static Future<String> createBackupJson() async {
    final transactions = await _db.getAllTransactions();

    final backup = {
      'format': 'finchat_backup',
      'version': 1,
      'created_at': DateTime.now().toIso8601String(),
      'transactions': transactions.map((transaction) {
        return transaction.toMap();
      }).toList(),
    };

    return const JsonEncoder.withIndent('  ').convert(backup);
  }

  /// Simpan backup JSON ke file.
  static Future<String?> exportBackup() async {
    try {
      final jsonData = await createBackupJson();
      final bytes = Uint8List.fromList(utf8.encode(jsonData));

      final fileName =
          'finchat_backup_${DateTime.now().millisecondsSinceEpoch}.json';

      final path = await FilePicker.saveFile(
        dialogTitle: 'Simpan Backup Finchat AI',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );

      if (path == null || path.isEmpty) {
        debugPrint('Backup dibatalkan oleh pengguna.');
        return null;
      }

      debugPrint('Backup berhasil disimpan: $path');
      return path;
    } catch (e, stackTrace) {
      debugPrint('Gagal membuat backup: $e');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Membaca file backup JSON dan mengembalikan jumlah transaksi
  /// yang berhasil dipulihkan.
  static Future<int> importBackup() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: false,
      );

      if (files.isEmpty) {
        debugPrint('Restore dibatalkan oleh pengguna.');
        return 0;
      }

      final pickedFile = files.first;

      Uint8List? bytes = pickedFile.bytes;

      if (bytes == null) {
        bytes = await pickedFile.readAsBytes();
      }

      if (bytes.isEmpty) {
        throw Exception('File backup kosong.');
      }

      final jsonText = utf8.decode(bytes);
      final decoded = jsonDecode(jsonText);

      if (decoded is! Map<String, dynamic>) {
        throw Exception('Format backup tidak valid.');
      }

      if (decoded['format'] != 'finchat_backup') {
        throw Exception(
          'File bukan backup Finchat AI yang valid.',
        );
      }

      final transactionData = decoded['transactions'];

      if (transactionData is! List) {
        throw Exception(
          'Data transaksi tidak ditemukan di file backup.',
        );
      }

      int restoredCount = 0;

      for (final item in transactionData) {
        if (item is! Map) {
          continue;
        }

        try {
          final map = Map<String, dynamic>.from(item);

          final transaction = TransactionModel.fromMap(map);

          await _db.restoreTransaction(transaction);

          restoredCount++;
        } catch (e) {
          debugPrint(
            'Gagal restore satu transaksi: $e',
          );
        }
      }

      debugPrint(
        'Restore selesai. $restoredCount transaksi dipulihkan.',
      );

      return restoredCount;
    } catch (e, stackTrace) {
      debugPrint('Gagal restore backup: $e');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }
}
