import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Integrasi Gemini melalui REST API langsung.
///
/// Versi sebelumnya menggunakan google_generative_ai yang sudah deprecated.
/// REST API dipakai agar aplikasi tidak bergantung pada SDK Dart yang sudah
/// tidak dikembangkan, sekaligus memakai model stabil Gemini 2.5 Flash.
class GeminiService {
  static const String model = 'gemini-2.5-flash';
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  static Future<String> _generateText({
    required String apiKey,
    String proxyUrl = '',
    required List<Map<String, dynamic>> parts,
    double temperature = 0.1,
  }) async {
    final key = apiKey.trim();
    final proxy = proxyUrl.trim();
    if (key.isEmpty && proxy.isEmpty) {
      throw const GeminiException('API Key Gemini atau AI Proxy belum diatur.');
    }

    final uri = proxy.isNotEmpty
        ? Uri.parse(proxy.endsWith('/') ? '${proxy}v1/gemini/generate' : '$proxy/v1/gemini/generate')
        : Uri.parse('$_baseUrl/$model:generateContent?key=${Uri.encodeQueryComponent(key)}');
    final body = {
      'contents': [
        {'parts': parts}
      ],
      'generationConfig': {
        'temperature': temperature,
        'responseMimeType': 'application/json',
      },
    };

    try {
      final response = await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        String message = 'Gemini mengembalikan HTTP ${response.statusCode}.';
        try {
          final error = jsonDecode(response.body);
          final apiMessage = error['error']?['message'];
          if (apiMessage is String && apiMessage.isNotEmpty) message = apiMessage;
        } catch (_) {}
        throw GeminiException(message);
      }

      final decoded = jsonDecode(response.body);
      final candidates = decoded['candidates'];
      if (candidates is List && candidates.isNotEmpty) {
        final content = candidates.first['content'];
        final responseParts = content?['parts'];
        if (responseParts is List) {
          final texts = responseParts
              .whereType<Map>()
              .map((part) => part['text'])
              .whereType<String>()
              .toList();
          if (texts.isNotEmpty) return texts.join();
        }
      }

      throw const GeminiException('Respons Gemini kosong atau tidak dapat dibaca.');
    } on SocketException catch (e) {
      throw GeminiException(
        'Tidak dapat terhubung ke server Gemini. Periksa internet/DNS. (${e.message})',
      );
    } on http.ClientException catch (e) {
      throw GeminiException('Koneksi ke Gemini gagal: ${e.message}');
    }
  }

  static Map<String, dynamic> _decodeJson(String raw) {
    var cleaned = raw.trim();
    cleaned = cleaned.replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '');
    cleaned = cleaned.replaceFirst(RegExp(r'\s*```$'), '');
    cleaned = cleaned.trim();

    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is Map<String, dynamic>) return decoded;
      throw const GeminiException('Format JSON Gemini tidak sesuai.');
    } catch (e) {
      if (e is GeminiException) rethrow;
      throw const GeminiException('Gemini mengembalikan JSON yang tidak valid.');
    }
  }

  /// Chat AI. Transaksi sederhana ditangani parser lokal sebelum method ini
  /// dipanggil; method ini fokus pada pertanyaan/permintaan yang memerlukan AI.
  static Future<Map<String, dynamic>> processChatMessage({
    required String apiKey,
    required String userText,
    required Map<String, dynamic> financeContext,
    String proxyUrl = '',
  }) async {
    final prompt = '''
Kamu adalah Finchat AI, asisten keuangan pribadi yang ramah dan ringkas.
Selalu jawab dalam Bahasa Indonesia.

Ringkasan keuangan bulan ini:
- Total pemasukan: ${financeContext['income']}
- Total pengeluaran: ${financeContext['expense']}
- Saldo: ${financeContext['balance']}
- Pengeluaran per kategori: ${jsonEncode(financeContext['byCategory'])}

Pesan pengguna:
$userText

Tugas:
- Jawab pertanyaan keuangan berdasarkan ringkasan di atas.
- Jika pengguna meminta saran, berikan saran praktis dan tidak menghakimi.
- Jika pesan ternyata berisi transaksi yang tidak tertangkap parser lokal,
  boleh ekstrak transaksi tersebut.

Balas JSON dengan format:
{
  "intent": "chat" atau "transaction",
  "transaction": null atau {
    "type": "expense" atau "income",
    "category": "kategori singkat",
    "description": "deskripsi singkat",
    "amount": angka,
    "merchant": "nama merchant atau kosong",
    "transaction_date": null
  },
  "reply": "jawaban singkat dalam Bahasa Indonesia"
}
''';

    final raw = await _generateText(
      apiKey: apiKey,
      proxyUrl: proxyUrl,
      parts: [
        {'text': prompt}
      ],
    );

    return _decodeJson(raw);
  }

  /// Fallback AI untuk teks transaksi yang terlalu bebas/kompleks untuk
  /// parser lokal. Dapat mengembalikan beberapa transaksi sekaligus.
  static Future<List<Map<String, dynamic>>> parseTransactionTextMany({
    required String apiKey,
    required String text,
    String proxyUrl = '',
  }) async {
    final prompt = '''
Ekstrak semua transaksi keuangan dari teks Bahasa Indonesia berikut.
Pisahkan setiap transaksi walaupun dalam satu kalimat dan walaupun dipisahkan
koma. Jangan menggabungkan nominal dari transaksi berbeda.

Balas HANYA JSON valid dengan format:
{
  "transactions": [
    {
      "type": "expense" atau "income",
      "category": "Makanan|Rokok|Transportasi|Belanja|Tagihan|Pulsa & Data|Kesehatan|Hiburan|Pendidikan|Rumah Tangga|Gaji|Bonus|Pemasukan|Lainnya",
      "description": "deskripsi singkat",
      "amount": angka_nominal,
      "merchant": "nama merchant jika ada, boleh kosong"
    }
  ]
}

Aturan nominal:
- 25rb, 25 rb, 25 ribu = 25000
- 1,5 juta = 1500000
- Rp50.000 = 50000
- angka tanpa satuan diperlakukan sebagai rupiah

Teks:
$text
''';

    final raw = await _generateText(
      apiKey: apiKey,
      proxyUrl: proxyUrl,
      parts: [
        {'text': prompt}
      ],
    );
    final decoded = _decodeJson(raw);
    final list = decoded['transactions'];
    if (list is! List) return [];

    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => double.tryParse(e['amount'].toString()) != null)
        .toList();
  }

  /// Kompatibilitas dengan nama method versi sebelumnya.
  static Future<Map<String, dynamic>?> parseTransactionText({
    required String apiKey,
    required String text,
    String proxyUrl = '',
  }) async {
    final list = await parseTransactionTextMany(apiKey: apiKey, text: text, proxyUrl: proxyUrl);
    return list.isEmpty ? null : list.first;
  }

  /// OCR/ekstraksi struk. Respons diminta JSON sehingga koma pada nama barang
  /// atau merchant tidak lagi merusak parsing seperti pendekatan CSV lama.
  static Future<Map<String, dynamic>> parseReceipt({
    required String apiKey,
    required List<int> imageBytes,
    required String mimeType,
    String proxyUrl = '',
  }) async {
    final prompt = '''
Analisis foto struk belanja ini.
Ekstrak total transaksi yang paling jelas dan relevan untuk pencatatan keuangan.
Balas HANYA JSON valid:
{
  "type": "expense",
  "category": "kategori singkat",
  "description": "ringkasan belanja",
  "amount": angka_nominal_total,
  "merchant": "nama toko jika terbaca",
  "transaction_date": "YYYY-MM-DD atau null"
}

Prioritaskan TOTAL/GRAND TOTAL struk, bukan subtotal atau harga salah satu item.
Jika tanggal tidak terbaca, gunakan null.
''';

    final raw = await _generateText(
      apiKey: apiKey,
      proxyUrl: proxyUrl,
      temperature: 0,
      parts: [
        {'text': prompt},
        {
          'inline_data': {
            'mime_type': mimeType,
            'data': base64Encode(imageBytes),
          }
        },
      ],
    );

    return _decodeJson(raw);
  }
}

class GeminiException implements Exception {
  final String message;
  const GeminiException(this.message);

  @override
  String toString() => message;
}
