import 'package:flutter/material.dart';
import '../services/prefs_service.dart';
import '../services/sheets_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  final _sheetsUrlController = TextEditingController();
  final _aiProxyController = TextEditingController();
  bool _loading = true;
  bool _syncing = false;
  String? _lastSync;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apiKey = await PrefsService.getApiKey();
    final sheetsUrl = await PrefsService.getSheetsUrl();
    final aiProxyUrl = await PrefsService.getAiProxyUrl();
    final lastSync = await PrefsService.getLastSync();
    setState(() {
      _apiKeyController.text = apiKey;
      _sheetsUrlController.text = sheetsUrl;
      _aiProxyController.text = aiProxyUrl;
      _lastSync = lastSync;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await PrefsService.setApiKey(_apiKeyController.text.trim());
    await PrefsService.setSheetsUrl(_sheetsUrlController.text.trim());
    await PrefsService.setAiProxyUrl(_aiProxyController.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pengaturan tersimpan.')),
    );
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      await _save();
      final count = await SheetsService.syncUnsyncedTransactions();
      final lastSync = await PrefsService.getLastSync();
      setState(() => _lastSync = lastSync);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Berhasil sinkron $count transaksi ke Google Sheets.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal sinkron: $e')),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _sheetsUrlController.dispose();
    _aiProxyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Gemini API Key',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: _apiKeyController,
                  obscureText: _obscureKey,
                  decoration: InputDecoration(
                    hintText: 'AIzaSy...',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureKey ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscureKey = !_obscureKey),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Dipakai untuk Scan Struk dan Chat AI. Disimpan di secure storage perangkat, bukan SharedPreferences.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 20),
                const Text('AI Proxy URL (opsional, untuk production)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: _aiProxyController,
                  decoration: const InputDecoration(
                    hintText: 'https://domain-anda.com',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Jika diisi, request AI dikirim ke proxy sehingga API key Gemini tidak perlu disimpan di APK. Kosongkan untuk mode development langsung ke Gemini.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 24),
                const Text('URL Google Sheets (Apps Script Web App)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: _sheetsUrlController,
                  decoration: const InputDecoration(
                    hintText: 'https://script.google.com/macros/s/.../exec',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Buat Google Sheet baru → Extensions > Apps Script → tempel skrip '
                  'doPost() yang menyimpan data transaksi → Deploy sebagai Web App → '
                  'salin URL-nya ke sini. Transaksi tetap tersimpan offline di HP dan '
                  'akan dikirim ke Sheets saat kamu menekan "Sinkron Sekarang".',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _save,
                        child: const Text('Simpan'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: _syncing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.cloud_sync),
                        label: const Text('Sinkron Sekarang'),
                        onPressed: _syncing ? null : _syncNow,
                      ),
                    ),
                  ],
                ),
                if (_lastSync != null) ...[
                  const SizedBox(height: 12),
                  Text('Sinkron terakhir: $_lastSync',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
                const Divider(height: 40),
                const Text(
                  'Tentang Finchat AI',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Aplikasi pencatat keuangan offline-first: semua transaksi '
                  'tersimpan lokal di SQLite dan bisa dipakai tanpa internet. '
                  'Pencatatan teks sederhana juga berjalan tanpa internet. Fitur AI '
                  'memanggil Gemini API, dan sinkron ke Google Sheets bersifat opsional.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
    );
  }
}
