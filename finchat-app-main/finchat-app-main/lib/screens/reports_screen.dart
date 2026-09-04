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
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Laporan'),
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Harian'),
              Tab(text: 'Per Tanggal'),
              Tab(text: 'Rentang'),
              Tab(text: 'Bulanan'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _DailyReportTab(),
            _SingleDateReportTab(),
            _RangeReportTab(),
            _MonthlyReportTab(),
          ],
        ),
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  final String title;
  final String periodLabel;
  final List<TransactionModel> transactions;
  final bool loading;

  const _ReportBody({
    required this.title,
    required this.periodLabel,
    required this.transactions,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final currency =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
    final summary = DatabaseHelper.instance.summarize(transactions);

    return Column(
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
              Text(periodLabel,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
          child: transactions.isEmpty
              ? const Center(child: Text('Tidak ada transaksi pada periode ini.'))
              : ListView.builder(
                  itemCount: transactions.length,
                  itemBuilder: (context, index) {
                    final tx = transactions[index];
                    return ListTile(
                      title: Text(tx.description),
                      subtitle: Text('${tx.category} • ${tx.transactionDate}'),
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
              onPressed: transactions.isEmpty
                  ? null
                  : () => PdfService.exportAndShare(
                        title: title,
                        periodLabel: periodLabel,
                        transactions: transactions,
                        totalIncome: summary['income'],
                        totalExpense: summary['expense'],
                      ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DailyReportTab extends StatefulWidget {
  const _DailyReportTab();
  @override
  State<_DailyReportTab> createState() => _DailyReportTabState();
}

class _DailyReportTabState extends State<_DailyReportTab> {
  bool _loading = true;
  List<TransactionModel> _data = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final data = await DatabaseHelper.instance.getTransactionsByDate(today);
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final label = 'Hari ini, ${DateFormat('dd MMMM yyyy', 'id_ID').format(DateTime.now())}';
    return _ReportBody(
      title: 'Laporan Harian',
      periodLabel: label,
      transactions: _data,
      loading: _loading,
    );
  }
}

class _SingleDateReportTab extends StatefulWidget {
  const _SingleDateReportTab();
  @override
  State<_SingleDateReportTab> createState() => _SingleDateReportTabState();
}

class _SingleDateReportTabState extends State<_SingleDateReportTab> {
  DateTime _selectedDate = DateTime.now();
  bool _loading = true;
  List<TransactionModel> _data = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final data = await DatabaseHelper.instance.getTransactionsByDate(dateStr);
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today, size: 16),
            label: Text(DateFormat('dd MMMM yyyy', 'id_ID').format(_selectedDate)),
            onPressed: _pickDate,
          ),
        ),
        Expanded(
          child: _ReportBody(
            title: 'Laporan Per Tanggal',
            periodLabel: DateFormat('dd MMMM yyyy', 'id_ID').format(_selectedDate),
            transactions: _data,
            loading: _loading,
          ),
        ),
      ],
    );
  }
}

class _RangeReportTab extends StatefulWidget {
  const _RangeReportTab();
  @override
  State<_RangeReportTab> createState() => _RangeReportTabState();
}

class _RangeReportTabState extends State<_RangeReportTab> {
  DateTimeRange _range = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 6)),
    end: DateTime.now(),
  );
  bool _loading = true;
  List<TransactionModel> _data = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await DatabaseHelper.instance.getTransactionsByDateRange(
      DateFormat('yyyy-MM-dd').format(_range.start),
      DateFormat('yyyy-MM-dd').format(_range.end),
    );
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _range,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _range = picked);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final label =
        '${DateFormat('dd MMM yyyy', 'id_ID').format(_range.start)} - ${DateFormat('dd MMM yyyy', 'id_ID').format(_range.end)}';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.date_range, size: 16),
            label: Text(label),
            onPressed: _pickRange,
          ),
        ),
        Expanded(
          child: _ReportBody(
            title: 'Laporan Rentang Tanggal',
            periodLabel: label,
            transactions: _data,
            loading: _loading,
          ),
        ),
      ],
    );
  }
}

class _MonthlyReportTab extends StatefulWidget {
  const _MonthlyReportTab();
  @override
  State<_MonthlyReportTab> createState() => _MonthlyReportTabState();
}

class _MonthlyReportTabState extends State<_MonthlyReportTab> {
  DateTime _selectedMonth = DateTime.now();
  bool _loading = true;
  List<TransactionModel> _data = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final yearMonth = DateFormat('yyyy-MM').format(_selectedMonth);
    final data = await DatabaseHelper.instance.getTransactionsByMonth(yearMonth);
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Pilih bulan (tanggal diabaikan)',
    );
    if (picked != null) {
      setState(() => _selectedMonth = picked);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = DateFormat('MMMM yyyy', 'id_ID').format(_selectedMonth);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.calendar_month, size: 16),
            label: Text(label),
            onPressed: _pickMonth,
          ),
        ),
        Expanded(
          child: _ReportBody(
            title: 'Laporan Bulanan',
            periodLabel: label,
            transactions: _data,
            loading: _loading,
          ),
        ),
      ],
    );
  }
}
