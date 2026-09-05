import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import '../models/transaction_model.dart';
import '../models/chat_message_model.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  /// Notifier additive agar layar Dashboard/Transaksi/Laporan dapat
  /// menyegarkan data setelah transaksi ditambahkan dari layar lain.
  static final ValueNotifier<int> transactionChanges = ValueNotifier<int>(0);

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('finchat.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chat_id TEXT,
        transaction_date TEXT,
        transaction_time TEXT,
        type TEXT,
        category TEXT,
        description TEXT,
        amount REAL,
        payment_method TEXT,
        merchant TEXT,
        notes TEXT,
        source TEXT,
        is_synced INTEGER
      )
    ''');
    await _createChatMessagesTable(db);
    await _createDeletedTransactionsTable(db);
  }

  // Ditambahkan untuk mendukung fitur baru (Chat AI, Laporan, Sinkronisasi
  // Google Sheets) TANPA mengubah tabel/kolom transaksi yang sudah ada.
  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createChatMessagesTable(db);
    }
    if (oldVersion < 3) {
      await _createDeletedTransactionsTable(db);
    }
  }

  Future _createDeletedTransactionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS deleted_transactions (
        id INTEGER PRIMARY KEY
      )
    ''');
  }

  Future _createChatMessagesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        role TEXT,
        content TEXT,
        timestamp TEXT,
        related_transaction_id INTEGER
      )
    ''');
  }

  Future<int> insertTransaction(TransactionModel transaction) async {
    final db = await instance.database;
    final id = await db.insert('transactions', transaction.toMap());
    transactionChanges.value++;
    return id;
  }

  Future<List<TransactionModel>> getAllTransactions() async {
    final db = await instance.database;
    final result = await db.query('transactions', orderBy: 'id DESC');
    return result.map((json) => TransactionModel.fromMap(json)).toList();
  }

  // =====================================================================
  // Method tambahan di bawah ini bersifat ADDITIVE (murni penambahan)
  // untuk mendukung Dashboard, Laporan, Chat AI, dan Sinkronisasi Google
  // Sheets. Tidak ada method di atas yang diubah.
  // =====================================================================

  Future<int> updateTransaction(TransactionModel transaction) async {
    if (transaction.id == null) return 0;
    final db = await instance.database;
    final result = await db.update(
      'transactions',
      transaction.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [transaction.id],
    );
    if (result > 0) {
      // Edit harus masuk antrean sinkronisasi kembali agar perubahan di Sheets
      // menggantikan baris lama, bukan dianggap sudah tersinkron.
      await db.update(
        'transactions',
        {'is_synced': 0},
        where: 'id = ?',
        whereArgs: [transaction.id],
      );
      transactionChanges.value++;
    }
    return result;
  }

  Future<void> restoreTransactions(List<TransactionModel> transactions) async {
    if (transactions.isEmpty) return;
    final db = await instance.database;
    await db.transaction((txn) async {
      for (final tx in transactions) {
        await txn.insert(
          'transactions',
          tx.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
    transactionChanges.value++;
  }

  Future<void> restoreDeletedTransactionIds(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await instance.database;
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.insert(
          'deleted_transactions',
          {'id': id},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<int> deleteTransaction(int id) async {
    final db = await instance.database;
    final result = await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
    if (result > 0) {
      await db.insert(
        'deleted_transactions',
        {'id': id},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      transactionChanges.value++;
    }
    return result;
  }

  Future<List<int>> getDeletedTransactionIds() async {
    final db = await instance.database;
    final rows = await db.query('deleted_transactions', orderBy: 'id ASC');
    return rows.map((row) => (row['id'] as num).toInt()).toList();
  }

  Future<void> clearDeletedTransactionIds(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await instance.database;
    await db.delete(
      'deleted_transactions',
      where: 'id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
  }

  Future<List<TransactionModel>> getTransactionsByDate(String date) async {
    final db = await instance.database;
    final result = await db.query(
      'transactions',
      where: 'transaction_date = ?',
      whereArgs: [date],
      orderBy: 'transaction_time DESC',
    );
    return result.map((json) => TransactionModel.fromMap(json)).toList();
  }

  Future<List<TransactionModel>> getTransactionsByDateRange(
      String startDate, String endDate) async {
    final db = await instance.database;
    final result = await db.query(
      'transactions',
      where: 'transaction_date BETWEEN ? AND ?',
      whereArgs: [startDate, endDate],
      orderBy: 'transaction_date DESC, transaction_time DESC',
    );
    return result.map((json) => TransactionModel.fromMap(json)).toList();
  }

  /// [yearMonth] format: 'yyyy-MM'
  Future<List<TransactionModel>> getTransactionsByMonth(
      String yearMonth) async {
    final db = await instance.database;
    final result = await db.query(
      'transactions',
      where: "transaction_date LIKE ?",
      whereArgs: ['$yearMonth%'],
      orderBy: 'transaction_date DESC, transaction_time DESC',
    );
    return result.map((json) => TransactionModel.fromMap(json)).toList();
  }

  /// Ringkasan total pemasukan/pengeluaran & breakdown per kategori
  /// dalam sebuah daftar transaksi (dipakai Dashboard & Laporan).
  Map<String, dynamic> summarize(List<TransactionModel> transactions) {
    double income = 0;
    double expense = 0;
    final Map<String, double> byCategory = {};

    for (final tx in transactions) {
      if (tx.type == 'income') {
        income += tx.amount;
      } else {
        expense += tx.amount;
        byCategory[tx.category] = (byCategory[tx.category] ?? 0) + tx.amount;
      }
    }

    return {
      'income': income,
      'expense': expense,
      'balance': income - expense,
      'byCategory': byCategory,
    };
  }

  Future<List<TransactionModel>> getUnsyncedTransactions() async {
    final db = await instance.database;
    final result = await db.query(
      'transactions',
      where: 'is_synced = ?',
      whereArgs: [0],
      orderBy: 'id ASC',
    );
    return result.map((json) => TransactionModel.fromMap(json)).toList();
  }

  Future<int> markAsSynced(int id) async {
    final db = await instance.database;
    return await db.update(
      'transactions',
      {'is_synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> insertChatMessage(ChatMessageModel message) async {
    final db = await instance.database;
    return await db.insert('chat_messages', message.toMap());
  }

  Future<List<ChatMessageModel>> getChatMessages() async {
    final db = await instance.database;
    final result = await db.query('chat_messages', orderBy: 'id ASC');
    return result.map((json) => ChatMessageModel.fromMap(json)).toList();
  }
}
