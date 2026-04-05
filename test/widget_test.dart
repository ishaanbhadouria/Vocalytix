import 'package:flutter_test/flutter_test.dart';
import 'package:avaixa/main.dart';

void main() {
  testWidgets('App renders Avaixa shell', (WidgetTester tester) async {
    await tester.pumpWidget(const AvaixaApp());

    expect(find.text('Select Your Speaking Context'), findsOneWidget);
    expect(find.text('Avaixa'), findsWidgets);
  });
}
