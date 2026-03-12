import 'package:flutter_test/flutter_test.dart';
import 'package:vocalytix/main.dart';

void main() {
  testWidgets('App renders Vocalytix practice screen', (WidgetTester tester) async {
    await tester.pumpWidget(const VocalytixApp());

    expect(find.text('Vocalytix Practice'), findsOneWidget);
    expect(find.text('Start Speaking'), findsOneWidget);
  });
}
