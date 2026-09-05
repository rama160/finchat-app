import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finchat_app/main.dart';

void main() {
TestWidgetsFlutterBinding.ensureInitialized();

setUpAll(() async {
sqfliteFfiInit();
databaseFactory = databaseFactoryFfi;

await initializeDateFormatting('id_ID', null);

SharedPreferences.setMockInitialValues(
  <String, Object>{},
);

FlutterSecureStorage.setMockInitialValues(
  <String, String>{},
);

});

testWidgets(
'FinchatApp dapat dibuat',
(WidgetTester tester) async {
await tester.pumpWidget(
const FinchatApp(),
);

  await tester.pump();

  expect(
    find.byType(FinchatApp),
    findsOneWidget,
  );
},

);
}
