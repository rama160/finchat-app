import '../models/transaction_model.dart';

class TransactionParser {
  /// Memisahkan beberapa transaksi.
  ///
  /// Contoh:
  /// beli nasi 25rb, rokok 30 rb, es 10 rb
  static List<String> splitTransactions(String input) {
    if (input.trim().isEmpty) return [];

    // Lindungi koma desimal seperti "1,5 juta".
    final protectedInput = input.replaceAllMapped(
      RegExp(
        r'(\d),(\d+\s*(?:juta|jt|ribu|rb|k)?)',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}<DECIMAL>${match.group(2)}',
    );

    return protectedInput
        .split(RegExp(r'[,;\n]+'))
        .map((item) => item.replaceAll('<DECIMAL>', ',').trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  /// API utama yang digunakan main.dart, chat_screen.dart,
  /// dan test lama.
  ///
  /// Hasilnya tetap List<Map<String, dynamic>> agar kompatibel
  /// dengan struktur aplikasi yang sudah ada.
  static List<Map<String, dynamic>> parseMany(String input) {
    final parts = splitTransactions(input);
    final transactions = <Map<String, dynamic>>[];

    for (final part in parts) {
      final transaction = parseOne(part);

      if (transaction != null) {
        transactions.add(transaction);
      }
    }

    return transactions;
  }

  /// Mem-parsing satu transaksi menjadi Map.
  static Map<String, dynamic>? parseOne(String input) {
    final text = input.trim();

    if (text.isEmpty) return null;

    final amount = extractAmount(text);

    if (amount <= 0) return null;

    final type = detectType(text);
    final category = detectCategory(text, type);
    final description = extractDescription(text);

    return {
      'type': type,
      'category': category,
      'description': description,
      'amount': amount,
    };
  }

  /// Alias kompatibilitas.
  static List<Map<String, dynamic>> parseTransactions(String input) {
    return parseMany(input);
  }

  /// Alias kompatibilitas.
  static Map<String, dynamic>? parseSingleTransaction(String input) {
    return parseOne(input);
  }

  static double extractAmount(String input) {
    final text = input.toLowerCase();

    // 1,5 juta
    // 2.5 juta
    // 1 juta
    final millionMatch = RegExp(
      r'(\d+(?:[,.]\d+)?)\s*(juta|jt)',
      caseSensitive: false,
    ).firstMatch(text);

    if (millionMatch != null) {
      final numberText = millionMatch.group(1)!.replaceAll(',', '.');
      final value = double.tryParse(numberText);

      if (value != null) {
        return value * 1000000;
      }
    }

    // 50rb
    // 50 rb
    // 50 ribu
    // 10k
    final thousandMatch = RegExp(
      r'(\d+(?:[,.]\d+)?)\s*(rb|ribu|k)',
      caseSensitive: false,
    ).firstMatch(text);

    if (thousandMatch != null) {
      final numberText = thousandMatch.group(1)!.replaceAll(',', '.');
      final value = double.tryParse(numberText);

      if (value != null) {
        return value * 1000;
      }
    }

    // Rp50.000
    // Rp 50.000
    // Rp50000
    final rupiahMatch = RegExp(
      r'rp\.?\s*(\d[\d.]*(?:,\d+)?)',
      caseSensitive: false,
    ).firstMatch(text);

    if (rupiahMatch != null) {
      return _parseIndonesianNumber(rupiahMatch.group(1)!);
    }

    // 50.000
    // 100000
    final normalMatches = RegExp(
      r'\b(\d{1,3}(?:\.\d{3})+|\d+)\b',
    ).allMatches(text);

    if (normalMatches.isNotEmpty) {
      return _parseIndonesianNumber(
        normalMatches.last.group(1)!,
      );
    }

    return 0;
  }

  static double _parseIndonesianNumber(String value) {
    var clean = value.trim();

    // 50.000 -> 50000
    // 1.500.000 -> 1500000
    if (clean.contains('.')) {
      clean = clean.replaceAll('.', '');
    }

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

  static String detectCategory(
    String input,
    String type,
  ) {
    final text = input.toLowerCase();

    if (type == 'income') {
      if (text.contains('gaji')) return 'Gaji';
      if (text.contains('bonus')) return 'Bonus';

      if (text.contains('jualan') ||
          text.contains('jual')) {
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
        'token',
      ],
      'Pulsa & Data': [
        'pulsa',
        'paket data',
        'kuota',
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
      'Pendidikan': [
        'sekolah',
        'kuliah',
        'buku',
        'kursus',
      ],
      'Rumah Tangga': [
        'sabun',
        'deterjen',
        'shampoo',
        'shampo',
        'alat rumah',
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

    // Hapus nominal rupiah.
    text = text.replaceAll(
      RegExp(
        r'rp\.?\s*\d[\d.,]*\s*(juta|jt|ribu|rb|k)?',
        caseSensitive: false,
      ),
      '',
    );

    // Hapus nominal dengan satuan.
    text = text.replaceAll(
      RegExp(
        r'\d+(?:[,.]\d+)?\s*(juta|jt|ribu|rb|k)',
        caseSensitive: false,
      ),
      '',
    );

    // Hapus format 50.000.
    text = text.replaceAll(
      RegExp(r'\b\d{1,3}(?:\.\d{3})+\b'),
      '',
    );

    // Hapus kata kerja umum.
    text = text.replaceAll(
      RegExp(
        r'\b(beli|bayar|membeli|dapat|menerima|terima)\b',
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
