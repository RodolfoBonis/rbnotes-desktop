// Smoke test for the example app shell.
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes_native_example/main.dart';

void main() {
  testWidgets('renders the example controls', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('Check permissions'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
  });
}
