import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App Build Canary Test', (WidgetTester tester) async {
    // A simple canary test to ensure the test suite and dependencies compile successfully in CI.
    expect(true, isTrue);
  });
}
