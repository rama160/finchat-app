/// Parser lokal untuk transaksi sederhana.
///
/// Tujuannya adalah membuat pencatatan transaksi dasar tetap berjalan tanpa
/// internet/API. Parser ini sengaja konservatif: sebuah potongan hanya dianggap
/// transaksi jika memiliki nominal yang dapat dikenali.
class TransactionParser {
  static const _expenseWords = [
    'beli',
    'belanja',
    'bayar',
    'pengeluaran',
    'keluar',
    'makan',
    'minum',
    'bensin',
    'isi pulsa',
    'top up',
    'topup',
    'rokok',
    'ongkos',
    'sewa',
  ];

  static const _incomeWords = [
    'gaji',
    'bonus',
    'pendapatan',
    'pemasukan',
    'terima',
    'menerima',
    'dapat',
    'diterima',
    'transfer masuk',
  ];

  static const _categoryKeywords = <String, List<String>>{
    'Makanan': [
      'nasi', 'makan', 'ayam', 'bakso', 'mie', 'mi ', 'sate', 'warteg',
      'warung', 'resto', 'restaurant', 'kuliner', 'es ', 'kopi', 'teh ',
      'minum', 'minuman', 'snack', 'cemilan', 'roti', 'jajan', 'sarapan',
      'makanan',
    ],
    'Rokok': ['rokok', 'kretek', 'filter', 'tembakau', 'vape'],
    'Transportasi': [
      'bensin', 'pertalite', 'pertamax', 'solar', 'ojek', 'grab', 'gojek',
      'taxi', 'taksi', 'parkir', 'tol', 'bus', 'kereta', 'transport',
      'angkot', 'ongkos',
    ],
    'Belanja': [
      'lipstick', 'lipstik', 'baju', 'celana', 'sepatu', 'tas', 'makeup',
      'kosmetik', 'skincare', 'belanja', 'barang', 'shopee', 'tokopedia',
      'lazada', 'marketplace',
    ],
    'Tagihan': [
      'listrik', 'air', 'pln', 'internet', 'wifi', 'tagihan', 'sewa',
      'kontrakan', 'kos ', 'cicilan', 'bpjs',
    ],
    'Pulsa & Data': [
      'pulsa', 'data', 'paket internet', 'kuota', 'telkomsel', 'indosat',
      'xl ', 'tri ', 'by.u',
    ],
    'Kesehatan': [
      'obat', 'apotek', 'dokter', 'rumah sakit', 'klinik', 'vitamin',
      'kesehatan',
    ],
    'Hiburan': [
      'film', 'bioskop', 'game', 'musik', 'spotify', 'netflix', 'hiburan',
      'tiket', 'konser',
    ],
    'Pendidikan': [
      'sekolah', 'kuliah', 'buku', 'kursus', 'les', 'pendidikan', 'kuliah',
    ],
    'Rumah Tangga': [
      'sabun', 'deterjen', 'gas', 'elpiji', 'perabot', 'rumah tangga',
      'kebersihan',
    ],
    'Gaji': ['gaji', 'salary', 'upah'],
    'Bonus': ['bonus', 'insentif', 'thr'],
  };

  static final RegExp _amountPattern = RegExp(
    r'(?:rp\.?\s*)?([0-9]{1,3}(?:[.,][0-9]{3})*|[0-9]+(?:[.,][0-9]+)?)\s*(rb|ribu|k|jt|juta|m)?\b',
    caseSensitive: false,
  );

  /// Memecah input seperti:
  /// "beli nasi 25rb, rokok 30 rb, es 10 rb"
  /// menjadi beberapa transaksi.
  static List<Map<String, dynamic>> parseMany(String text) {
    final segments = text
        .replaceAll('\r\n', '\n')
        .replaceAll(';', ',')
        .split(RegExp(r'[,\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final result = <Map<String, dynamic>>[];
    for (final segment in segments) {
      final parsed = parseOne(segment);
      if (parsed != null) result.add(parsed);
    }
    return result;
  }

  static Map<String, dynamic>? parseOne(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) return null;

    final match = _amountPattern.firstMatch(normalized);
    if (match == null) return null;

    final amount = _parseAmount(match.group(1)!, match.group(2));
    if (amount == null || amount <= 0) return null;

    final lower = normalized.toLowerCase();
    final type = _detectType(lower);
    final category = _detectCategory(lower, type);
    final description = _cleanDescription(normalized, match);

    return {
      'type': type,
      'category': category,
      'description': description.isEmpty ? normalized : description,
      'amount': amount,
      'merchant': '',
    };
  }

  static String _detectType(String lower) {
    for (final word in _incomeWords) {
      if (lower.contains(word)) return 'income';
    }
    return 'expense';
  }

  static String _detectCategory(String lower, String type) {
    if (type == 'income') {
      if (lower.contains('gaji')) return 'Gaji';
      if (lower.contains('bonus') || lower.contains('insentif') || lower.contains('thr')) {
        return 'Bonus';
      }
      return 'Pemasukan';
    }

    for (final entry in _categoryKeywords.entries) {
      for (final keyword in entry.value) {
        if (lower.contains(keyword)) return entry.key;
      }
    }
    return 'Lainnya';
  }

  static double? _parseAmount(String rawNumber, String? suffix) {
    var raw = rawNumber.trim().toLowerCase();
    if (raw.isEmpty) return null;

    double value;
    if (raw.contains('.') && raw.contains(',')) {
      // 1.500,50 -> 1500.50
      raw = raw.replaceAll('.', '').replaceAll(',', '.');
      value = double.tryParse(raw) ?? double.nan;
    } else if (RegExp(r'^\d{1,3}(?:[.,]\d{3})+$').hasMatch(raw)) {
      // 50.000 / 1,500 -> 50000 / 1500
      value = double.tryParse(raw.replaceAll(RegExp(r'[.,]'), '')) ?? double.nan;
    } else {
      value = double.tryParse(raw.replaceAll(',', '.')) ?? double.nan;
    }

    if (value.isNaN || value.isInfinite) return null;

    final s = (suffix ?? '').toLowerCase().replaceAll(' ', '');
    switch (s) {
      case 'k':
      case 'rb':
      case 'ribu':
        value *= 1000;
        break;
      case 'jt':
      case 'juta':
      case 'm':
        value *= 1000000;
        break;
    }

    return value.isFinite ? value : null;
  }

  static String _cleanDescription(String text, RegExpMatch match) {
    var description = text.substring(0, match.start).trim();
    if (description.isEmpty) {
      description = text.substring(0, match.end).trim();
    }

    description = description
        .replaceFirst(RegExp(r'^(beli|belanja|bayar|makan|minum|catat|pengeluaran)\s+', caseSensitive: false), '')
        .trim();

    if (description.isEmpty) {
      final beforeAmount = text.substring(0, match.start).trim();
      return beforeAmount;
    }

    return description;
  }

  /// Menghasilkan nominal manusiawi untuk pesan UI/log.
  static String formatAmount(double amount) {
    final rounded = amount.round();
    if (rounded % 1000000 == 0) return '${rounded ~/ 1000000} juta';
    if (rounded % 1000 == 0) return '${rounded ~/ 1000} ribu';
    return rounded.toString();
  }
}
