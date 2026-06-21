import 'package:flutter_test/flutter_test.dart';
import 'package:airfresh_application/main.dart';

void main() {
  testWidgets('AirFresh app loads', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Kualitas Udara'), findsOneWidget);
  });
}
