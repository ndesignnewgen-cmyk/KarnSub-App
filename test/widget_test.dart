import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_app/main.dart';

void main() {
  testWidgets('App launches', (WidgetTester tester) async {
    await tester.pumpWidget(const SubtitleApp());
    expect(find.byType(SubtitleApp), findsOneWidget);
  });
}
