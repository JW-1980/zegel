import 'package:flutter_test/flutter_test.dart';
import 'package:zegel_app/main.dart';

void main() {
  testWidgets('App renders smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ZegelApp());
    await tester.pumpAndSettle();

    // Verify that the app builds successfully.
    expect(find.byType(ZegelApp), findsOneWidget);
  });
}
