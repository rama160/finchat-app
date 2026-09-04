import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finchat_app/main.dart';

void main() {
TestWidgetsFlutterBinding.ensureInitialized();

setUpAll(() async {
// Gunakan database FFI agar sqflite dapat berjalan di environment
// flutter test tanpa membutuhkan plugin SQLite native.
sqfliteFfiInit();
databaseFactory = databaseFactoryFfi;

```
// Inisialisasi locale Bahasa Indonesia yang digunakan oleh
// Dashboard dan Reports.
await initializeDateFormatting('id_ID', null);

// Mock SharedPreferences untuk environment test.
SharedPreferences.setMockInitialValues(
  <String, Object>{},
);

// Mock resmi flutter_secure_storage.
//
// Jangan menggunakan MethodChannel manual karena flutter_secure_storage
// 11.x menggunakan platform implementation/federated plugin.
FlutterSecureStorage.setMockInitialValues(
  <String, String>{},
);
```

});

testWidgets(
'FinchatApp dapat dibuat',
(WidgetTester tester) async {
await tester.pumpWidget(
const FinchatApp(),
);

```
  // Jalankan satu frame tambahan agar widget selesai dibangun.
  //
  // Sengaja tidak menggunakan pumpAndSettle() karena beberapa widget
  // aplikasi menjalankan proses async dan animasi internal pada saat
  // initialization. Test ini hanya bertujuan memastikan FinchatApp
  // berhasil dibuat.
  await tester.pump();

  expect(
    find.byType(FinchatApp),
    findsOneWidget,
  );
},
```

);
}
