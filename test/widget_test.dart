import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finchat_app/main.dart';

// CATATAN PERBAIKAN (v1):
// Test ini gagal ("FinchatApp dapat dibuat (failed)") bukan karena bug di
// aplikasi, tapi karena HomeScreen/Dashboard/Chat/Reports/Settings semuanya
// memanggil DatabaseHelper (sqflite) dan PrefsService (flutter_secure_storage)
// di initState(). Kedua plugin itu memakai platform channel native yang
// TIDAK tersedia saat `flutter test` dijalankan (bukan di emulator/HP asli),
// sehingga melempar MissingPluginException secara asynchronous dan membuat
// test dianggap gagal walau widget-nya sendiri berhasil dibangun.
//
// Solusi ini hanya menambahkan mock KHUSUS UNTUK LINGKUNGAN TEST:
// - sqflite diarahkan ke implementasi FFI (sqflite_common_ffi) yang jalan
//   murni di Dart tanpa platform channel.
// - flutter_secure_storage di-mock supaya `read` mengembalikan null (anggap
//   belum ada API key tersimpan), sama seperti kondisi app baru diinstal.
//
// CATATAN PERBAIKAN (v2 — penyebab error yang masih tersisa):
// Setelah mock di atas terpasang, test MASIH gagal. Penyebabnya:
// DashboardScreen & ReportsScreen memanggil `DateFormat('MMMM yyyy', 'id_ID')`
// (lib/screens/dashboard_screen.dart & reports_screen.dart) begitu data
// selesai dimuat. Data locale 'id_ID' untuk paket `intl` hanya diinisialisasi
// lewat `initializeDateFormatting('id_ID', null)` di dalam main()
// (lib/main.dart) — dan `main()` TIDAK pernah dipanggil oleh widget test,
// karena test langsung memanggil `tester.pumpWidget(const FinchatApp())`.
// Akibatnya `DateFormat(..., 'id_ID')` melempar LocaleDataException saat
// Dashboard/Laporan selesai memuat data, dan itulah yang membuat test gagal.
//
// Perbaikan: panggil `initializeDateFormatting('id_ID', null)` juga di
// setUpAll test ini — persis operasi yang sama seperti yang dilakukan
// main(), hanya dipindah ke setup test. Ini murni inisialisasi data locale,
// tidak menyentuh satu baris pun logika/struktur di lib/.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Sama seperti main.dart: inisialisasi data locale Bahasa Indonesia agar
    // DateFormat('...', 'id_ID') di Dashboard & Laporan tidak melempar
    // LocaleDataException saat dijalankan di lingkungan test.
    await initializeDateFormatting('id_ID', null);

    // Pastikan shared_preferences juga pakai penyimpanan in-memory di test,
    // bukan platform channel asli.
    SharedPreferences.setMockInitialValues(<String, Object>{});

    const secureStorageChannel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel,
            (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'read':
          return null;
        case 'readAll':
          return <String, String>{};
        case 'containsKey':
          return false;
        case 'write':
        case 'delete':
        case 'deleteAll':
          return null;
        default:
          return null;
      }
    });
  });

  testWidgets('FinchatApp dapat dibuat', (WidgetTester tester) async {
    await tester.pumpWidget(const FinchatApp());

    // Beri kesempatan initState() async (load transaksi, cek API key, dll.)
    // di semua tab selesai sebelum diverifikasi.
    await tester.pumpAndSettle();

    expect(find.byType(FinchatApp), findsOneWidget);
  });
}
