import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'models/transaction_model.dart';
import 'services/database_helper.dart';

void main() {
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
      home: const HomeScreen(),
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
            onPressed: () => Navigator.pop(context),
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
