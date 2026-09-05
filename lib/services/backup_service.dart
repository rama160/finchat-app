import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import '../models/transaction_model.dart';
import 'database_helper.dart';

/// Backup/restore portabel untuk migrasi perangkat atau reinstall.
/// File tidak disimpan hanya di storage aplikasi, tetapi dipilih sendiri oleh
/// pengguna sehingga tetap dapat dipakai setelah aplikasi dihapus.
class BackupService {
  static const _format = 'finchat_backup';
  static const _version = 1;

  static Future<String?> createBackup() async {
    final transactions = await DatabaseHelper.instance.getAllTransactions();
    final deletedIds = await DatabaseHelper.instance.getDeletedTransactionIds();

    final payload = {
      'format': _format,
      'version': _version,
      'created_at': DateTime.now().toIso8601String(),
      'transactions': transactions.map((tx) => tx.toMap()).toList(),
      'deleted_transaction_ids': deletedIds,
    };

    final bytes = Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)));
    final path = await FilePicker.saveFile(
      dialogTitle: 'Simpan Backup Finchat',
      fileName: 'finchat_backup_${DateTime.now().millisecondsSinceEpoch}.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes,
    );

    return path;
  }

  static Future<int> restoreBackup({bool requireEmpty = true}) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return 0;

    final data = result.files.single.bytes;
    if (data == null) {
      throw Exception('File backup tidak dapat dibaca.');
    }

    final decoded = jsonDecode(utf8.decode(data));
    if (decoded is! Map || decoded['format'] != _format) {
      throw Exception('File bukan backup Finchat yang valid.');
    }

    final rows = decoded['transactions'];
    if (rows is! List) {
      throw Exception('Data transaksi di backup tidak valid.');
    }

    final local = await DatabaseHelper.instance.getAllTransactions();
    if (requireEmpty && local.isNotEmpty) {
      throw Exception(
        'Database lokal masih berisi ${local.length} transaksi. Restore dibatalkan agar data tidak tertimpa.',
      );
    }

    final transactions = <TransactionModel>[];
    for (final raw in rows) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final amount = double.tryParse(map['amount']?.toString() ?? '') ?? 0;
      if (amount <= 0) continue;
      transactions.add(TransactionModel.fromMap(map));
    }

    await DatabaseHelper.instance.restoreTransactions(transactions);

    final deleted = <int>[];
    final deletedRaw = decoded['deleted_transaction_ids'];
    if (deletedRaw is List) {
      for (final value in deletedRaw) {
        final id = int.tryParse(value.toString());
        if (id != null) deleted.add(id);
      }
    }
    await DatabaseHelper.instance.restoreDeletedTransactionIds(deleted);

    return transactions.length;
  }
}
