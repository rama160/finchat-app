import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'services/transaction_parser.dart';
import 'models/transaction_model.dart';
import 'services/database_helper.dart';
import 'services/prefs_service.dart';
import 'services/gemini_service.dart';
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

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _restoreCloudHistory();
  }

  Future<void> _restoreCloudHistory() async {
    try {
      await SheetsService.restoreIfLocalEmpty();
    } catch (_) {
      // Pemulihan bersifat best-effort; aplikasi tetap dapat dipakai offline.
    }
  }

  void _goToTab(int index) {
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
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
  bool _isListening = false;
  final stt.SpeechToText _speech = stt.SpeechToText();

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
    if (!mounted) return;
    setState(() {
      _transactions = data;
      _totalExpense = total;
    });
  }

  Future<void> _toggleVoiceInput() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    final available = await _speech.initialize(
      onStatus: (status) {
        if ((status == 'done' || status == 'notListening') && mounted) {
          setState(() => _isListening = false);
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() => _isListening = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Input suara gagal: ${error.errorMsg}')),
          );
        }
      },
    );

    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pengenalan suara tidak tersedia atau izin mikrofon ditolak.')),
        );
      }
      return;
    }

    if (mounted) setState(() => _isListening = true);
    await _speech.listen(
      localeId: 'id_ID',
      listenOptions: const stt.SpeechListenOptions(
        listenMode: stt.ListenMode.confirmation,
        partialResults: true,
        cancelOnError: true,
        autoPunctuation: true,
      ),
      onResult: (SpeechRecognitionResult result) {
        if (!mounted) return;
        _textInputController.text = result.recognizedWords;
        _textInputController.selection = TextSelection.fromPosition(
          TextPosition(offset: _textInputController.text.length),
        );
        setState(() {});
      },
    );
  }

  Future<void> _deleteTransaction(TransactionModel tx) async {
    if (tx.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus transaksi?'),
        content: Text('Transaksi "${tx.description}" akan dihapus permanen dari perangkat.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await DatabaseHelper.instance.deleteTransaction(tx.id!);
      unawaited(_syncInBackground());
      _refreshTransactions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaksi dihapus.')),
        );
      }
    }
  }

  Future<void> _editTransaction(TransactionModel tx) async {
    final description = TextEditingController(text: tx.description);
    final amount = TextEditingController(text: tx.amount.round().toString());
    final category = TextEditingController(text: tx.category);
    String type = tx.type;

    final updated = await showDialog<TransactionModel>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Transaksi'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'Jenis'),
                  items: const [
                    DropdownMenuItem(value: 'income', child: Text('Pemasukan')),
                    DropdownMenuItem(value: 'expense', child: Text('Pengeluaran')),
                  ],
                  onChanged: (v) => setDialogState(() => type = v ?? type),
                ),
                TextField(controller: description, decoration: const InputDecoration(labelText: 'Deskripsi')),
                TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Nominal (Rp)'),
                ),
                TextField(controller: category, decoration: const InputDecoration(labelText: 'Kategori')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
            FilledButton(
              onPressed: () {
                final parsedAmount = double.tryParse(
                  amount.text.replaceAll('.', '').replaceAll(',', ''),
                );
                if (description.text.trim().isEmpty || parsedAmount == null || parsedAmount <= 0) {
                  return;
                }
                Navigator.pop(
                  context,
                  tx.copyWith(
                    type: type,
                    description: description.text.trim(),
                    amount: parsedAmount,
                    category: category.text.trim().isEmpty ? 'Lainnya' : category.text.trim(),
                    isSynced: 0,
                  ),
                );
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );

    description.dispose();
    amount.dispose();
    category.dispose();

    if (updated != null) {
      await DatabaseHelper.instance.updateTransaction(updated);
      unawaited(_syncInBackground());
      _refreshTransactions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaksi diperbarui.')),
        );
      }
    }
  }

  Widget _transactionTile(TransactionModel item, NumberFormat currency) {
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _deleteTransaction(item);
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.shade100,
        child: const Icon(Icons.delete, color: Colors.red),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: item.type == 'income' ? Colors.green.shade100 : Colors.teal.shade100,
          child: Icon(
            item.type == 'income' ? Icons.arrow_downward : (item.source == 'receipt' ? Icons.receipt_long : Icons.edit_note),
            color: item.type == 'income' ? Colors.green : Colors.teal,
          ),
        ),
        title: Text(item.description),
        subtitle: Text('${item.category} • ${item.transactionDate}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${item.type == 'income' ? '+' : '-'}${currency.format(item.amount)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: item.type == 'income' ? Colors.green : Colors.redAccent,
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') _editTransaction(item);
                if (value == 'delete') _deleteTransaction(item);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Hapus')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Menangkap Foto Struk dan Proses dengan Gemini OCR.
  // Teks sederhana tidak membutuhkan Gemini; hanya scan struk yang memerlukan
  // koneksi AI.
  Future<void> _processReceiptImage(ImageSource source) async {
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
      unawaited(_syncInBackground());
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
      unawaited(_syncInBackground());
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

  Future<void> _syncInBackground() async {
    try {
      await SheetsService.syncUnsyncedTransactions();
    } catch (_) {
      // Tetap offline-first: kegagalan cloud tidak mengganggu penyimpanan lokal.
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
    _speech.stop();
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
                          itemBuilder: (context, index) =>
                              _transactionTile(_transactions[index], currency),
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
                      icon: Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        color: _isListening ? Colors.redAccent : Colors.grey.shade600,
                      ),
                      tooltip: _isListening ? 'Hentikan input suara' : 'Input dengan suara',
                      onPressed: _isLoading ? null : _toggleVoiceInput,
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
