import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/transaction_model.dart';

/// Membuat & membagikan laporan PDF dari daftar transaksi (dipakai oleh
/// layar Laporan untuk laporan harian, per tanggal, rentang tanggal, dan
/// bulanan).
class PdfService {
  static Future<void> exportAndShare({
    required String title,
    required String periodLabel,
    required List<TransactionModel> transactions,
    required double totalIncome,
    required double totalExpense,
  }) async {
    final currency =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text(title,
                style:
                    pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Text(periodLabel, style: const pw.TextStyle(fontSize: 12)),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total Pemasukan: ${currency.format(totalIncome)}'),
              pw.Text('Total Pengeluaran: ${currency.format(totalExpense)}'),
              pw.Text(
                  'Saldo: ${currency.format(totalIncome - totalExpense)}'),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: ['Tanggal', 'Kategori', 'Deskripsi', 'Tipe', 'Jumlah'],
            data: transactions
                .map((tx) => [
                      tx.transactionDate,
                      tx.category,
                      tx.description,
                      tx.type == 'income' ? 'Masuk' : 'Keluar',
                      currency.format(tx.amount),
                    ])
                .toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignment: pw.Alignment.centerLeft,
            columnWidths: {
              0: const pw.FlexColumnWidth(1.4),
              1: const pw.FlexColumnWidth(1.4),
              2: const pw.FlexColumnWidth(2.4),
              3: const pw.FlexColumnWidth(1),
              4: const pw.FlexColumnWidth(1.6),
            },
          ),
        ],
      ),
    );

    final fileName =
        'finchat_laporan_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';
    await Printing.sharePdf(bytes: await doc.save(), filename: fileName);
  }
}
