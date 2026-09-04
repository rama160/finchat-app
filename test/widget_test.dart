```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:finchat_app/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Inisialisasi sqflite menggunakan implementasi FFI agar test
    // tidak membutuhkan platform channel native.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Inisialisasi locale Indonesia yang digunakan oleh aplikasi.
    await initializeDateFormatting('id_ID', null);

    // SharedPreferences menggunakan storage in-memory selama test.
    SharedPreferences.setMockInitialValues(<String, Object>{});

    // FlutterSecureStorage menggunakan mock in-memory.
    //
    // Kondisi awal dibuat seperti aplikasi baru:
    // belum ada API key yang tersimpan.
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  testWidgets('FinchatApp dapat dibuat', (WidgetTester tester) async {
    await tester.pumpWidget(const FinchatApp());

    // Berikan waktu kepada proses async yang dijalankan oleh widget
    // saat initialization.
    await tester.pumpAndSettle();

    expect(find.byType(FinchatApp), findsOneWidget);
  });
}
```
