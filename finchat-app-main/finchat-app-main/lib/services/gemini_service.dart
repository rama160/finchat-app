import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';

/// Service AI untuk fitur Chat: mengurai input transaksi berbahasa natural
/// (mis. "beli kopi 20000") dan menjawab sebagai asisten keuangan, dengan
/// konteks ringkasan keuangan pengguna agar jawabannya akurat.
class GeminiService {
  /// Mengirim pesan chat ke Gemini dan meminta balasan terstruktur JSON:
  /// {
  ///   "intent": "transaction" | "chat",
  ///   "transaction": { "type", "category", "description", "amount",
  ///                     "merchant", "transaction_date" } | null,
  ///   "reply": "balasan asisten dalam Bahasa Indonesia"
  /// }
  static Future<Map<String, dynamic>> processChatMessage({
    required String apiKey,
    required String userText,
    required Map<String, dynamic> financeContext,
  }) async {
    final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: apiKey);

    final systemPrompt = '''
Kamu adalah "Finchat AI", asisten keuangan pribadi yang ramah dan ringkas,
selalu menjawab dalam Bahasa Indonesia.

Ringkasan keuangan pengguna bulan ini:
- Total Pemasukan: ${financeContext['income']}
- Total Pengeluaran: ${financeContext['expense']}
- Saldo: ${financeContext['balance']}
- Pengeluaran per kategori: ${jsonEncode(financeContext['byCategory'])}

Tugasmu untuk setiap pesan pengguna:
1. Jika pesan berisi transaksi keuangan baru (mis. "beli kopi 20000",
   "gaji bulan ini 5000000", "bayar listrik 150rb"), ekstrak datanya.
2. Jika pesan hanya pertanyaan/obrolan seputar keuangan (mis. "berapa
   pengeluaran saya bulan ini?", beri saran hemat), jawab menggunakan
   ringkasan keuangan di atas sebagai asisten keuangan.

WAJIB balas HANYA dengan JSON valid (tanpa markdown, tanpa penjelasan lain)
persis format berikut:
{
  "intent": "transaction" atau "chat",
  "transaction": null atau {
    "type": "expense" atau "income",
    "category": "kategori singkat, contoh: Makanan, Transportasi, Gaji",
    "description": "deskripsi singkat",
    "amount": angka_nominal_tanpa_titik_atau_koma,
    "merchant": "nama merchant jika ada, boleh kosong",
    "transaction_date": null
  },
  "reply": "balasan singkat, ramah, dalam Bahasa Indonesia"
}

Pesan pengguna: "$userText"
''';

    final response = await model.generateContent([Content.text(systemPrompt)]);
    final raw = (response.text ?? '').trim();
    final cleaned = raw
        .replaceAll(RegExp(r'^```json', multiLine: true), '')
        .replaceAll(RegExp(r'^```', multiLine: true), '')
        .replaceAll('```', '')
        .trim();

    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // Jika model tidak membalas JSON valid, fallback ke mode chat biasa
      // supaya pengguna tetap mendapat balasan alih-alih error.
    }
    return {
      'intent': 'chat',
      'transaction': null,
      'reply': raw.isNotEmpty
          ? raw
          : 'Maaf, saya belum bisa memproses pesan itu. Coba ulangi dengan kalimat lain.',
    };
  }
}
