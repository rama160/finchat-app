import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/transaction_model.dart';
import '../models/chat_message_model.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

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
      version: 2,
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
  }

  // Ditambahkan untuk mendukung fitur baru (Chat AI, Laporan, Sinkronisasi
  // Google Sheets) TANPA mengubah tabel/kolom transaksi yang sudah ada.
  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createChatMessagesTable(db);
    }
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
    return await db.insert('transactions', transaction.toMap());
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

  Future<int> deleteTransaction(int id) async {
    final db = await instance.database;
    return await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
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
