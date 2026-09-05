import 'package:flutter/material.dart';
import '../services/prefs_service.dart';
import '../services/sheets_service.dart';
import '../services/backup_service.dart';

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
  bool _syncSuccess = false;
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

  Future<void> _save({bool showMessage = true}) async {
    await PrefsService.setApiKey(_apiKeyController.text.trim());
    await PrefsService.setSheetsUrl(_sheetsUrlController.text.trim());
    await PrefsService.setAiProxyUrl(_aiProxyController.text.trim());
    if (!mounted || !showMessage) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pengaturan tersimpan.')),
    );
  }

  void _markSyncSuccess() {
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _syncSuccess = true;
    });
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _syncSuccess = false);
    });
  }

  String _shortSyncError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    if (message.contains('Failed host lookup') ||
        message.contains('SocketException')) {
      return 'Koneksi internet ke Google Sheets gagal.';
    }
    if (message.length > 180) {
      return '${message.substring(0, 180)}…';
    }
    return message;
  }

  Future<void> _syncNow() async {
    setState(() {
      _syncing = true;
      _syncSuccess = false;
    });
    try {
      await _save(showMessage: false);
      final count = await SheetsService.syncUnsyncedTransactions();
      final lastSync = await PrefsService.getLastSync();
      if (mounted) {
        setState(() => _lastSync = lastSync);
        // Tidak menampilkan SnackBar setelah sinkronisasi berhasil.
        // Tombol sendiri berubah menjadi centang selama beberapa detik.
        _markSyncSuccess();
      }
      debugPrint('Sinkronisasi selesai: $count transaksi.');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal sinkron: ${_shortSyncError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _syncAll() async {
    setState(() {
      _syncing = true;
      _syncSuccess = false;
    });
    try {
      await _save(showMessage: false);
      final count = await SheetsService.syncAllTransactions();
      final lastSync = await PrefsService.getLastSync();
      if (mounted) {
        setState(() => _lastSync = lastSync);
        _markSyncSuccess();
      }
      debugPrint('Sinkronisasi semua selesai: $count transaksi.');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sinkron semua gagal: ${_shortSyncError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _checkSheets() async {
    try {
      await _save();
      final message = await SheetsService.checkConnection();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✓ $message')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Koneksi Google Sheets gagal: $e')),
      );
    }
  }

  Future<void> _backupData() async {
    try {
      final path = await BackupService.createBackup();
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup berhasil disimpan: $path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuat backup: $e')),
      );
    }
  }

  Future<void> _restoreFromBackup() async {
    setState(() => _syncing = true);
    try {
      final count = await BackupService.restoreBackup();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 0
                ? 'Restore dibatalkan atau file kosong.'
                : 'Berhasil memulihkan $count transaksi dari backup.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal restore backup: $e')),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _restoreFromSheets() async {
    setState(() => _syncing = true);
    try {
      await _save();
      final count = await SheetsService.restoreIfLocalEmpty();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 0
                ? 'Tidak ada data yang dipulihkan. Pemulihan hanya dilakukan jika transaksi lokal kosong.'
                : 'Berhasil memulihkan $count transaksi dari Google Sheets.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memulihkan data: $e')),
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
                  'Buat Google Sheet baru → Extensions > Apps Script → tempel file '
                  'server/google_apps_script/Code.gs dari proyek ini → Deploy sebagai '
                  'Web App → Execute as: Me → Who has access: Anyone → salin URL /exec '
                  'ke sini. Transaksi tetap tersimpan offline di HP dan dapat dipulihkan '
                  'setelah reinstall melalui tombol "Pulihkan Data" jika sebelumnya '
                  'sudah pernah disinkronkan.',
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
                            : Icon(
                                _syncSuccess ? Icons.check_circle : Icons.cloud_sync,
                                color: _syncSuccess ? Colors.green : null,
                              ),
                        label: const Text('Sinkron Sekarang'),
                        onPressed: _syncing ? null : _syncNow,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.wifi_tethering),
                        label: const Text('Tes Koneksi'),
                        onPressed: _syncing ? null : _checkSheets,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.restore),
                        label: const Text('Pulihkan Data'),
                        onPressed: _syncing ? null : _restoreFromSheets,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Pulihkan Data hanya mengisi database jika transaksi lokal benar-benar kosong, misalnya setelah reinstall.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: Icon(
                    _syncSuccess ? Icons.check_circle : Icons.cloud_upload,
                    color: _syncSuccess ? Colors.green : null,
                  ),
                  label: const Text('Kirim Semua Transaksi ke Google Sheets'),
                  onPressed: _syncing ? null : _syncAll,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Gunakan sekali saat migrasi dari versi lama atau jika sebelumnya muncul "sinkron 0". Data yang sudah ada di Sheets akan diperbarui berdasarkan ID, bukan digandakan.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (_lastSync != null) ...[
                  const SizedBox(height: 12),
                  Text('Sinkron terakhir: $_lastSync',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
                const SizedBox(height: 24),
                const Text(
                  'Backup & Migrasi',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Sebelum uninstall atau pindah HP, buat backup JSON. File ini disimpan di lokasi yang Anda pilih dan dapat dipulihkan setelah memasang ulang aplikasi.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.backup),
                        label: const Text('Backup Data'),
                        onPressed: _syncing ? null : _backupData,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.file_open),
                        label: const Text('Restore Backup'),
                        onPressed: _syncing ? null : _restoreFromBackup,
                      ),
                    ),
                  ],
                ),
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
