import '../models/transaction_model.dart';

class TransactionParser {
  /// Memisahkan beberapa transaksi yang ditulis dalam satu kalimat.
  ///
  /// Contoh:
  /// beli nasi 25rb, rokok 30 rb, es 10 rb
  static List<String> splitTransactions(String input) {
    if (input.trim().isEmpty) return [];

    final protectedInput = input.replaceAllMapped(
      RegExp(r'(\d),(\d+\s*(?:juta|jt|ribu|rb|k)?)', caseSensitive: false),
      (match) => '${match.group(1)}<DECIMAL>${match.group(2)}',
    );

    return protectedInput
        .split(RegExp(r'[,;\n]+'))
        .map((item) => item.replaceAll('<DECIMAL>', ',').trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static List<TransactionModel> parseTransactions(String input) {
    final parts = splitTransactions(input);

    final transactions = <TransactionModel>[];

    for (final part in parts) {
      final transaction = parseSingleTransaction(part);

      if (transaction != null) {
        transactions.add(transaction);
      }
    }

    return transactions;
  }

  static TransactionModel? parseSingleTransaction(String input) {
    final text = input.trim();

    if (text.isEmpty) return null;

    final amount = extractAmount(text);

    if (amount <= 0) return null;

    final type = detectType(text);
    final category = detectCategory(text, type);
    final description = extractDescription(text);

    return TransactionModel(
      type: type,
      category: category,
      description: description,
      amount: amount,
      date: DateTime.now(),
    );
  }

  static double extractAmount(String input) {
    var text = input.toLowerCase();

    // Contoh:
    // 1,5 juta
    // 2.5 juta
    final decimalMillion = RegExp(
      r'(\d+(?:[,.]\d+)?)\s*(juta|jt)',
      caseSensitive: false,
    ).firstMatch(text);

    if (decimalMillion != null) {
      final numberText = decimalMillion
          .group(1)!
          .replaceAll(',', '.');

      final value = double.tryParse(numberText);

      if (value != null) {
        return value * 1000000;
      }
    }

    // Contoh:
    // 500rb
    // 50 rb
    // 500 ribu
    // 10k
    final thousand = RegExp(
      r'(\d+(?:[,.]\d+)?)\s*(rb|ribu|k)',
      caseSensitive: false,
    ).firstMatch(text);

    if (thousand != null) {
      final numberText = thousand
          .group(1)!
          .replaceAll(',', '.');

      final value = double.tryParse(numberText);

      if (value != null) {
        return value * 1000;
      }
    }

    // Contoh:
    // Rp50.000
    // Rp 25.000
    final rupiah = RegExp(
      r'rp\.?\s*(\d[\d.]*(?:,\d+)?)',
      caseSensitive: false,
    ).firstMatch(text);

    if (rupiah != null) {
      return _parseIndonesianNumber(rupiah.group(1)!);
    }

    // Contoh:
    // 50.000
    // 100000
    final normalNumber = RegExp(
      r'\b(\d{1,3}(?:\.\d{3})+|\d+)\b',
    ).allMatches(text);

    if (normalNumber.isNotEmpty) {
      final match = normalNumber.last;

      return _parseIndonesianNumber(match.group(1)!);
    }

    return 0;
  }

  static double _parseIndonesianNumber(String value) {
    var clean = value.trim();

    // Format Indonesia:
    // 50.000 -> 50000
    // 1.500.000 -> 1500000
    if (clean.contains('.')) {
      clean = clean.replaceAll('.', '');
    }

    // Jika ada koma pada nominal biasa.
    clean = clean.replaceAll(',', '.');

    return double.tryParse(clean) ?? 0;
  }

  static String detectType(String input) {
    final text = input.toLowerCase();

    const incomeWords = [
      'gaji',
      'bonus',
      'pendapatan',
      'uang masuk',
      'dapat uang',
      'menerima',
      'dibayar',
      'jualan',
      'hasil jual',
      'profit',
    ];

    for (final word in incomeWords) {
      if (text.contains(word)) {
        return 'income';
      }
    }

    return 'expense';
  }

  static String detectCategory(String input, String type) {
    final text = input.toLowerCase();

    if (type == 'income') {
      if (text.contains('gaji')) return 'Gaji';
      if (text.contains('bonus')) return 'Bonus';
      if (text.contains('jualan') || text.contains('jual')) {
        return 'Penjualan';
      }

      return 'Pendapatan Lainnya';
    }

    const categoryKeywords = {
      'Makanan': [
        'nasi',
        'makan',
        'mie',
        'bakso',
        'ayam',
        'sate',
        'kopi',
        'es ',
        'minum',
        'teh',
        'roti',
        'pizza',
        'burger',
      ],
      'Rokok': [
        'rokok',
        'cigarette',
        'marlboro',
        'surya',
        'sampoerna',
      ],
      'Transportasi': [
        'bensin',
        'pertalite',
        'pertamax',
        'solar',
        'parkir',
        'ojek',
        'grab',
        'gojek',
        'taxi',
        'bus',
      ],
      'Belanja': [
        'beli',
        'lipstick',
        'baju',
        'sepatu',
        'tas',
        'celana',
        'kaos',
      ],
      'Tagihan': [
        'listrik',
        'air',
        'internet',
        'wifi',
        'pulsa',
        'token',
      ],
      'Kesehatan': [
        'obat',
        'dokter',
        'rumah sakit',
        'vitamin',
      ],
      'Hiburan': [
        'bioskop',
        'game',
        'netflix',
        'spotify',
      ],
    };

    for (final entry in categoryKeywords.entries) {
      for (final keyword in entry.value) {
        if (text.contains(keyword)) {
          return entry.key;
        }
      }
    }

    return 'Lainnya';
  }

  static String extractDescription(String input) {
    var text = input.trim();

    // Hapus nominal rupiah dan satuannya.
    text = text.replaceAll(
      RegExp(
        r'rp\.?\s*\d[\d.,]*\s*(juta|jt|ribu|rb|k)?',
        caseSensitive: false,
      ),
      '',
    );

    text = text.replaceAll(
      RegExp(
        r'\d+(?:[,.]\d+)?\s*(juta|jt|ribu|rb|k)',
        caseSensitive: false,
      ),
      '',
    );

    text = text.replaceAll(
      RegExp(r'\b\d{1,3}(?:\.\d{3})+\b'),
      '',
    );

    // Bersihkan kata kerja umum.
    text = text.replaceAll(
      RegExp(
        r'\b(beli|bayar|membeli|dapat|menerima|terima|gaji)\b',
        caseSensitive: false,
      ),
      '',
    );

    text = text
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return text.isEmpty ? 'Transaksi' : text;
  }
}
