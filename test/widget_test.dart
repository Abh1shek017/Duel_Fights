import 'package:flutter_test/flutter_test.dart';
import 'package:bluetooth_brawlers/main.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const BluetoothBrawlersApp());
    expect(find.text('HOST GAME'), findsOneWidget);
    expect(find.text('JOIN GAME'), findsOneWidget);
  });
}
