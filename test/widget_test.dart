import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

    const secureStorageChannel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );

    TestDefaultBinaryMessengerBinding
        .instance
        .defaultBinaryMessenger
        .setMockMethodCallHandler(
      secureStorageChannel,
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
      },
    );
  });

  testWidgets(
    'FinchatApp dapat dibuat',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const FinchatApp(),
      );

      await tester.pumpAndSettle();

      expect(
        find.byType(FinchatApp),
        findsOneWidget,
      );
    },
  );
}
