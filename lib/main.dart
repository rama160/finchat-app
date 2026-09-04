import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:image_picker/image_picker.dart';
import 'services/transaction_parser.dart';
import 'models/transaction_model.dart';
import 'services/database_helper.dart';
import 'services/prefs_service.dart';
import 'services/gemini_service.dart';
import 'screens/dashboard_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/settings_screen.dart';

// Ditambahkan hanya agar format tanggal Bahasa Indonesia ('MMMM yyyy', dst.)
// yang dipakai layar Dashboard & Laporan bisa berjalan. Alur & logika
// HomeScreen di bawah ini tidak diubah sama sekali.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);
  runApp(const FinchatApp());
}

class FinchatApp extends StatelessWidget {
  const FinchatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Finchat AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const MainShell(),
    );
  }
}

// ===========================================================================
// MainShell BARU: bottom navigation yang membungkus Dashboard, HomeScreen
// (Transaksi/Scan Struk — TIDAK DIUBAH), Chat AI, Laporan, dan Pengaturan.
// Ditambahkan agar semua fitur baru bisa diakses tanpa mengubah struktur
// maupun logika HomeScreen yang sudah ada.
// ===========================================================================
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  void _goToTab(int index) {
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const HomeScreen(),
      const DashboardScreen(),
      const ChatScreen(),
      const ReportsScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        selectedItemColor: Colors.teal,
        unselectedItemColor: Colors.grey,
        onTap: _goToTab,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long), label: 'Transaksi'),
          BottomNavigationBarItem(
              icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble), label: 'Chat AI'),
          BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart), label: 'Laporan'),
          BottomNavigationBarItem(
              icon: Icon(Icons.settings), label: 'Pengaturan'),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<TransactionModel> _transactions = [];
  double _totalExpense = 0;
  bool _isLoading = false;

  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _textInputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // BUGFIX: HomeScreen tetap hidup selamanya di dalam IndexedStack (tidak
    // pernah dispose saat pindah tab), sehingga tanpa listener ini daftar
    // transaksi & total di tab Transaksi tidak ikut ter-refresh saat transaksi
    // baru dicatat dari tab Chat AI/Dashboard/Laporan. Pola listener ini sudah
    // dipakai persis sama di DashboardScreen & ReportsScreen; di sini hanya
    // dilengkapi agar konsisten, bukan logika baru.
    DatabaseHelper.transactionChanges.addListener(_onTransactionsChanged);
    _refreshTransactions();
    _loadSavedApiKey(); // Ditambahkan: sinkron dengan API key dari halaman Pengaturan
  }

  void _onTransactionsChanged() {
    if (mounted) _refreshTransactions();
  }

  Future<void> _loadSavedApiKey() async {
    final saved = await PrefsService.getApiKey();
    if (saved.isNotEmpty && mounted) {
      _apiKeyController.text = saved;
    }
  }

  // BUGFIX: karena HomeScreen tidak pernah dibuat ulang selama app berjalan
  // (IndexedStack), controller ini bisa basi jika API key diubah dari tab
  // Pengaturan. Method ini menyamakan controller dengan nilai tersimpan
  // terbaru sebelum dipakai, tanpa mengubah alur/validasi yang sudah ada.
  Future<void> _syncApiKeyFromPrefs() async {
    final saved = await PrefsService.getApiKey();
    if (mounted && saved != _apiKeyController.text) {
      _apiKeyController.text = saved;
    }
  }

  void _refreshTransactions() async {
    final data = await DatabaseHelper.instance.getAllTransactions();
    double total = 0;
    for (var item in data) {
      if (item.type == 'expense') {
        total += item.amount;
      }
    }
    if (!mounted) return;
    setState(() {
      _transactions = data;
      _totalExpense = total;
    });
  }

  // Menangkap Foto Struk dan Proses dengan Gemini OCR.
  // Teks sederhana tidak membutuhkan Gemini; hanya scan struk yang memerlukan
  // koneksi AI.
  Future<void> _processReceiptImage(ImageSource source) async {
    await _syncApiKeyFromPrefs();
    final proxyUrl = await PrefsService.getAiProxyUrl();
    if (_apiKeyController.text.trim().isEmpty && proxyUrl.trim().isEmpty) {
      _showApiKeyDialog();
      return;
    }

    final picker = ImagePicker();
    final image = await picker.pickImage(source: source, imageQuality: 90);
    if (image == null) return;

    setState(() => _isLoading = true);

    try {
      final imageBytes = await File(image.path).readAsBytes();
      final mimeType = image.mimeType ??
          (image.path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
      final result = await GeminiService.parseReceipt(
        apiKey: _apiKeyController.text.trim(),
        proxyUrl: proxyUrl,
        imageBytes: imageBytes,
        mimeType: mimeType,
      );

      final amount = double.tryParse(result['amount'].toString()) ?? 0;
      if (amount <= 0) {
        throw const GeminiException('Total pada struk tidak terbaca.');
      }

      final now = DateTime.now();
      final date = (result['transaction_date'] as String?)?.trim();
      final transaction = TransactionModel(
        transactionDate: date != null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)
            ? date
            : DateFormat('yyyy-MM-dd').format(now),
        transactionTime: DateFormat('HH:mm:ss').format(now),
        type: 'expense',
        category: (result['category'] ?? 'Lainnya').toString(),
        description: (result['description'] ?? 'Transaksi struk').toString(),
        amount: amount,
        merchant: (result['merchant'] ?? '').toString(),
        source: 'receipt',
      );

      await DatabaseHelper.instance.insertTransaction(transaction);
      _refreshTransactions();

      if (mounted) {
        final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Struk tersimpan: ${currency.format(amount)}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membaca struk: ${_friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveParsedTransactions(
      List<Map<String, dynamic>> parsed, String originalText) async {
    if (parsed.isEmpty) return;

    final now = DateTime.now();
    var saved = 0;
    for (final result in parsed) {
      final amount = double.tryParse(result['amount'].toString()) ?? 0;
      if (amount <= 0) continue;

      final newTx = TransactionModel(
        transactionDate: DateFormat('yyyy-MM-dd').format(now),
        transactionTime: DateFormat('HH:mm:ss').format(now),
        type: result['type'] == 'income' ? 'income' : 'expense',
        category: (result['category'] ?? 'Lainnya').toString(),
        description: (result['description'] ?? originalText).toString(),
        amount: amount,
        merchant: (result['merchant'] ?? '').toString(),
        source: 'text',
      );
      await DatabaseHelper.instance.insertTransaction(newTx);
      saved++;
    }

    if (saved > 0) {
      _textInputController.clear();
      _refreshTransactions();
      if (mounted) {
        final label = saved == 1 ? '1 transaksi' : '$saved transaksi';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ $label berhasil dicatat.')),
        );
      }
    }
  }

  // Input transaksi bersifat offline-first: parser lokal dijalankan terlebih
  // dahulu. Gemini hanya menjadi fallback untuk kalimat yang terlalu bebas.
  Future<void> _submitTextTransaction() async {
    final text = _textInputController.text.trim();
    if (text.isEmpty || _isLoading) return;

    await _syncApiKeyFromPrefs();
    setState(() => _isLoading = true);
    try {
      final localParsed = TransactionParser.parseMany(text);
      if (localParsed.isNotEmpty) {
        await _saveParsedTransactions(localParsed, text);
        return;
      }

      final apiKey = _apiKeyController.text.trim();
      final proxyUrl = await PrefsService.getAiProxyUrl();
      if (apiKey.isEmpty && proxyUrl.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Transaksi belum dikenali. Coba: "beli nasi 25rb, rokok 30rb" atau isi API Key untuk AI.'),
            ),
          );
        }
        return;
      }

      final parsed = await GeminiService.parseTransactionTextMany(
        apiKey: apiKey,
        text: text,
        proxyUrl: proxyUrl,
      );
      if (parsed.isNotEmpty) {
        await _saveParsedTransactions(parsed, text);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak dapat memahami transaksi tersebut.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memproses transaksi: ${_friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    if (message.contains('Failed host lookup') || message.contains('SocketException')) {
      return 'Internet/DNS tidak tersedia. Transaksi teks sederhana tetap bisa dicatat tanpa internet.';
    }
    return message;
  }

  void _showApiKeyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Masukkan API Key Gemini'),
        content: TextField(
          controller: _apiKeyController,
          decoration: const InputDecoration(hintText: 'AIzaSy...'),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await PrefsService.setApiKey(_apiKeyController.text.trim());
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    DatabaseHelper.transactionChanges.removeListener(_onTransactionsChanged);
    _apiKeyController.dispose();
    _textInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finchat AI'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.key),
            onPressed: _showApiKeyDialog,
            tooltip: 'Atur API Key',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.teal.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Pengeluaran:', style: TextStyle(fontSize: 16)),
                      Text(
                        currency.format(_totalExpense),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _transactions.isEmpty
                      ? const Center(child: Text('Belum ada transaksi.'))
                      : ListView.builder(
                          itemCount: _transactions.length,
                          itemBuilder: (context, index) {
                            final item = _transactions[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.teal.shade100,
                                child: Icon(
                                  item.source == 'receipt' ? Icons.receipt_long : Icons.edit_note,
                                  color: Colors.teal,
                                ),
                              ),
                              title: Text(item.description),
                              subtitle: Text('${item.category} • ${item.transactionDate}'),
                              trailing: Text(
                                currency.format(item.amount),
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent),
                              ),
                            );
                          },
                        ),
                ),
                _buildInputBar(),
              ],
            ),
    );
  }

  // BARU: input bar bergaya chat (emoji, teks "Pesan", lampiran struk,
  // tombol bulat kamera/kirim) menggantikan FloatingActionButton lama.
  Widget _buildInputBar() {
    final hasText = _textInputController.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.grey.shade300),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(Icons.emoji_emotions_outlined, color: Colors.grey.shade500),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _textInputController,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        decoration: const InputDecoration(
                          hintText: 'Pesan',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _submitTextTransaction(),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.attach_file, color: Colors.grey.shade600),
                      tooltip: 'Lampirkan Struk',
                      onPressed: () => _processReceiptImage(ImageSource.gallery),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.teal,
              child: IconButton(
                icon: Icon(hasText ? Icons.send : Icons.camera_alt, color: Colors.white),
                tooltip: hasText ? 'Kirim Transaksi' : 'Scan Struk',
                onPressed: hasText
                    ? _submitTextTransaction
                    : () => _processReceiptImage(ImageSource.camera),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
