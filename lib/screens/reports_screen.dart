import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/transaction_model.dart';
import '../services/database_helper.dart';
import '../services/pdf_service.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  // Mode tanggal tunggal (default) atau mode rentang waktu.
  bool _isRangeMode = false;
  DateTime _singleDate = DateTime.now();
  DateTimeRange _range = DateTimeRange(start: DateTime.now(), end: DateTime.now());

  bool _loading = true;
  bool _isMonthly = false;
  List<TransactionModel> _transactions = [];
  String _periodLabel = '';
  String _reportTitle = 'Laporan Harian';

  @override
  void initState() {
    super.initState();
    DatabaseHelper.transactionChanges.addListener(_onTransactionsChanged);
    _load();
  }

  DateTime _lastDayOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0);

  void _onTransactionsChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    List<TransactionModel> data;
    String label;
    String title;
    bool isMonthly = false;

    if (_isRangeMode) {
      final start = DateTime(_range.start.year, _range.start.month, _range.start.day);
      final end = DateTime(_range.end.year, _range.end.month, _range.end.day);
      final lastDay = _lastDayOfMonth(start);
      final isFullMonth = start.day == 1 &&
          start.year == end.year &&
          start.month == end.month &&
          end.day == lastDay.day;

      if (isFullMonth) {
        isMonthly = true;
        final yearMonth = DateFormat('yyyy-MM').format(start);
        data = await DatabaseHelper.instance.getTransactionsByMonth(yearMonth);
        label = _capitalize(DateFormat('MMMM yyyy', 'id_ID').format(start));
        title = 'Laporan Bulanan';
      } else {
        data = await DatabaseHelper.instance.getTransactionsByDateRange(
          DateFormat('yyyy-MM-dd').format(start),
          DateFormat('yyyy-MM-dd').format(end),
        );
        label =
            '${DateFormat('dd MMM yyyy', 'id_ID').format(start)} - ${DateFormat('dd MMM yyyy', 'id_ID').format(end)}';
        title = 'Laporan Rentang Tanggal';
      }
    } else {
      final dateStr = DateFormat('yyyy-MM-dd').format(_singleDate);
      data = await DatabaseHelper.instance.getTransactionsByDate(dateStr);
      label = _capitalize(DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(_singleDate));
      title = 'Laporan Harian';
    }

    if (!mounted) return;
    setState(() {
      _transactions = data;
      _periodLabel = label;
      _reportTitle = title;
      _isMonthly = isMonthly;
      _loading = false;
    });
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  void _shiftDay(int delta) {
    setState(() {
      _isRangeMode = false;
      _singleDate = _singleDate.add(Duration(days: delta));
    });
    _load();
  }

  Future<void> _showPeriodPicker() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text('Pilih Periode Laporan',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            ListTile(
              leading: const Icon(Icons.today, color: Colors.teal),
              title: const Text('Pilih Tanggal'),
              subtitle: const Text('Lihat laporan untuk satu hari tertentu'),
              onTap: () => Navigator.pop(context, 'date'),
            ),
            ListTile(
              leading: const Icon(Icons.date_range, color: Colors.teal),
              title: const Text('Pilih Rentang Waktu'),
              subtitle: const Text(
                  'Rentang satu bulan penuh otomatis tampil sebagai laporan bulanan'),
              onTap: () => Navigator.pop(context, 'range'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted || choice == null) return;

    if (choice == 'date') {
      final picked = await showDatePicker(
        context: context,
        initialDate: _isRangeMode ? _range.start : _singleDate,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (picked != null) {
        setState(() {
          _isRangeMode = false;
          _singleDate = picked;
        });
        _load();
      }
    } else if (choice == 'range') {
      final picked = await showDateRangePicker(
        context: context,
        initialDateRange:
            _isRangeMode ? _range : DateTimeRange(start: _singleDate, end: _singleDate),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (picked != null) {
        setState(() {
          _isRangeMode = true;
          _range = picked;
        });
        _load();
      }
    }
  }

  @override
  void dispose() {
    DatabaseHelper.transactionChanges.removeListener(_onTransactionsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currency =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
    final summary = DatabaseHelper.instance.summarize(_transactions);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.teal,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: Colors.white),
                  onPressed: _isRangeMode ? null : () => _shiftDay(-1),
                ),
                Flexible(
                  child: InkWell(
                    onTap: _showPeriodPicker,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _periodLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_drop_down, color: Colors.white),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, color: Colors.white),
                  onPressed: _isRangeMode ? null : () => _shiftDay(1),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.all(12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.teal.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isMonthly
                                  ? 'Menampilkan rangkuman satu bulan penuh'
                                  : (_isRangeMode ? 'Rentang tanggal terpilih' : 'Laporan harian'),
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Masuk: ${currency.format(summary['income'])}',
                                    style: const TextStyle(
                                        color: Colors.green, fontWeight: FontWeight.bold)),
                                Text('Keluar: ${currency.format(summary['expense'])}',
                                    style: const TextStyle(
                                        color: Colors.redAccent, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('Saldo: ${currency.format(summary['balance'])}',
                                style: const TextStyle(
                                    color: Colors.teal, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _transactions.isEmpty
                            ? const Center(
                                child: Text('Tidak ada transaksi pada periode ini.'))
                            : ListView.builder(
                                itemCount: _transactions.length,
                                itemBuilder: (context, index) {
                                  final tx = _transactions[index];
                                  return ListTile(
                                    title: Text(tx.description),
                                    subtitle:
                                        Text('${tx.category} • ${tx.transactionDate}'),
                                    trailing: Text(
                                      currency.format(tx.amount),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: tx.type == 'income'
                                            ? Colors.green
                                            : Colors.redAccent,
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            icon: const Icon(Icons.picture_as_pdf),
                            label: const Text('Export PDF'),
                            onPressed: _transactions.isEmpty
                                ? null
                                : () => PdfService.exportAndShare(
                                      title: _reportTitle,
                                      periodLabel: _periodLabel,
                                      transactions: _transactions,
                                      totalIncome: summary['income'],
                                      totalExpense: summary['expense'],
                                    ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
