import 'package:flutter_test/flutter_test.dart';
import 'package:nexuspad_app/main.dart';

void main() {
  testWidgets('App launches', (WidgetTester tester) async {
    await tester.pumpWidget(const NexusPadApp());
    expect(find.text('NexusPad'), findsOneWidget);
  });
}
