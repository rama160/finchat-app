import 'package:flutter_test/flutter_test.dart';
import 'package:finchat_app/main.dart';

void main() {
  testWidgets('FinchatApp dapat dibuat', (WidgetTester tester) async {
    await tester.pumpWidget(const FinchatApp());
    expect(find.text('Finchat AI'), findsOneWidget);
  });
}
