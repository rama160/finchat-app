import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'models/transaction_model.dart';
import 'services/database_helper.dart';
import 'services/prefs_service.dart';
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
      DashboardScreen(onNavigate: _goToTab),
      const HomeScreen(),
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
              icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long), label: 'Transaksi'),
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
    _refreshTransactions();
    _loadSavedApiKey(); // Ditambahkan: sinkron dengan API key dari halaman Pengaturan
  }

  Future<void> _loadSavedApiKey() async {
    final saved = await PrefsService.getApiKey();
    if (saved.isNotEmpty && mounted) {
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
    setState(() {
      _transactions = data;
      _totalExpense = total;
    });
  }

  // Menangkap Foto Struk dan Proses dengan Gemini OCR
  Future<void> _processReceiptImage() async {
    if (_apiKeyController.text.trim().isEmpty) {
      _showApiKeyDialog();
      return;
    }

    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() => _isLoading = true);

    try {
      final apiKey = _apiKeyController.text.trim();
      final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: apiKey);

      final imageBytes = await File(image.path).readAsBytes();
      final prompt = TextPart(
        'Analisis gambar struk ini. Ekstrak data berikut dalam bentuk format CSV 1 baris tanpa header: '
        'Kategori,Deskripsi,Jumlah(Nominal Angka saja),Merchant. Contoh format output: Makanan,Bakso Lapangan Tembak,35000,Bakso Solo'
      );
      final imagePart = DataPart('image/jpeg', imageBytes);

      final response = await model.generateContent([
        Content.multi([prompt, imagePart])
      ]);

      final resultText = response.text ?? '';
      final parts = resultText.split(',');

      if (parts.length >= 3) {
        final now = DateTime.now();
        final newTx = TransactionModel(
          transactionDate: DateFormat('yyyy-MM-dd').format(now),
          transactionTime: DateFormat('HH:mm:ss').format(now),
          type: 'expense',
          category: parts[0].trim(),
          description: parts[1].trim(),
          amount: double.tryParse(parts[2].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0,
          merchant: parts.length > 3 ? parts[3].trim() : '',
          source: 'receipt',
        );

        await DatabaseHelper.instance.insertTransaction(newTx);
        _refreshTransactions();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membaca struk: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
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
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _processReceiptImage,
        backgroundColor: Colors.teal,
        icon: const Icon(Icons.camera_alt, color: Colors.white),
        label: const Text('Scan Struk', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}
