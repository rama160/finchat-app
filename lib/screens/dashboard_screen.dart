import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/database_helper.dart';
import '../models/transaction_model.dart';

class DashboardScreen extends StatefulWidget {
  final void Function(int tabIndex) onNavigate;

  const DashboardScreen({super.key, required this.onNavigate});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  List<TransactionModel> _monthTransactions = [];
  Map<String, dynamic> _summary = {
    'income': 0.0,
    'expense': 0.0,
    'balance': 0.0,
    'byCategory': <String, double>{},
  };

  static const _palette = [
    Colors.teal,
    Colors.orange,
    Colors.indigo,
    Colors.redAccent,
    Colors.purple,
    Colors.brown,
    Colors.blueGrey,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final yearMonth = DateFormat('yyyy-MM').format(DateTime.now());
    final data = await DatabaseHelper.instance.getTransactionsByMonth(yearMonth);
    final summary = DatabaseHelper.instance.summarize(data);
    setState(() {
      _monthTransactions = data;
      _summary = summary;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final currency =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
    final byCategory =
        Map<String, double>.from(_summary['byCategory'] as Map);
    final recent = _monthTransactions.take(5).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Ringkasan Bulan ${DateFormat('MMMM yyyy', 'id_ID').format(DateTime.now())}',
                      style: const TextStyle(fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryCard(
                          label: 'Pemasukan',
                          value: currency.format(_summary['income']),
                          color: Colors.green,
                          icon: Icons.arrow_downward,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SummaryCard(
                          label: 'Pengeluaran',
                          value: currency.format(_summary['expense']),
                          color: Colors.redAccent,
                          icon: Icons.arrow_upward,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SummaryCard(
                    label: 'Saldo Bulan Ini',
                    value: currency.format(_summary['balance']),
                    color: Colors.teal,
                    icon: Icons.account_balance_wallet,
                    fullWidth: true,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _QuickAction(
                        icon: Icons.camera_alt,
                        label: 'Scan Struk',
                        onTap: () => widget.onNavigate(1),
                      ),
                      _QuickAction(
                        icon: Icons.chat_bubble,
                        label: 'Chat AI',
                        onTap: () => widget.onNavigate(2),
                      ),
                      _QuickAction(
                        icon: Icons.bar_chart,
                        label: 'Laporan',
                        onTap: () => widget.onNavigate(3),
                      ),
                      _QuickAction(
                        icon: Icons.settings,
                        label: 'Pengaturan',
                        onTap: () => widget.onNavigate(4),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text('Pengeluaran per Kategori',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (byCategory.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('Belum ada data pengeluaran bulan ini.')),
                    )
                  else
                    SizedBox(
                      height: 220,
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: PieChart(
                              PieChartData(
                                sections: _buildSections(byCategory),
                                sectionsSpace: 2,
                                centerSpaceRadius: 32,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: _buildLegend(byCategory),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  const Text('Transaksi Terbaru',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (recent.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Belum ada transaksi bulan ini.'),
                    )
                  else
                    ...recent.map((tx) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: tx.type == 'income'
                                ? Colors.green.shade100
                                : Colors.teal.shade100,
                            child: Icon(
                              tx.type == 'income'
                                  ? Icons.arrow_downward
                                  : (tx.source == 'receipt'
                                      ? Icons.receipt_long
                                      : Icons.edit_note),
                              color: tx.type == 'income' ? Colors.green : Colors.teal,
                            ),
                          ),
                          title: Text(tx.description),
                          subtitle: Text('${tx.category} • ${tx.transactionDate}'),
                          trailing: Text(
                            currency.format(tx.amount),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: tx.type == 'income' ? Colors.green : Colors.redAccent,
                            ),
                          ),
                        )),
                ],
              ),
            ),
    );
  }

  List<PieChartSectionData> _buildSections(Map<String, double> byCategory) {
    final entries = byCategory.entries.toList();
    final total = byCategory.values.fold<double>(0, (a, b) => a + b);
    return List.generate(entries.length, (i) {
      final pct = total == 0 ? 0 : (entries[i].value / total * 100);
      return PieChartSectionData(
        value: entries[i].value,
        title: '${pct.toStringAsFixed(0)}%',
        color: _palette[i % _palette.length],
        radius: 60,
        titleStyle: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
      );
    });
  }

  Widget _buildLegend(Map<String, double> byCategory) {
    final entries = byCategory.entries.toList();
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, i) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _palette[i % _palette.length],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(entries[i].key,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final bool fullWidth;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 13)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(
          children: [
            CircleAvatar(
              backgroundColor: Colors.teal.shade50,
              child: Icon(icon, color: Colors.teal, size: 20),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
