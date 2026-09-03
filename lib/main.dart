import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

  void _addSampleTransaction() async {
    final now = DateTime.now();
    final newTx = TransactionModel(
      transactionDate: DateFormat('yyyy-MM-dd').format(now),
      transactionTime: DateFormat('HH:mm:ss').format(now),
      type: 'expense',
      category: 'Makanan',
      description: 'Makan Siang Bakso',
      amount: 25000,
      source: 'manual',
    );
    await DatabaseHelper.instance.insertTransaction(newTx);
    _refreshTransactions();
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finchat AI (Offline)'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Column(
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
                ? const Center(child: Text('Belum ada transaksi offline.'))
                : ListView.builder(
                    itemCount: _transactions.length,
                    itemBuilder: (context, index) {
                      final item = _transactions[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.teal.shade100,
                          child: const Icon(Icons.receipt, color: Colors.teal),
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
      floatingActionButton: FloatingActionButton(
        onPressed: _addSampleTransaction,
        backgroundColor: Colors.teal,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
