import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finchat_app/main.dart';

// CATATAN PERBAIKAN:
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
// Tidak ada satu baris pun di lib/ (struktur & logika aplikasi) yang diubah.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

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
