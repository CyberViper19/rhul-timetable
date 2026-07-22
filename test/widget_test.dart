import 'package:flutter_test/flutter_test.dart';
import 'package:rhul_timetable/main.dart';

void main() {
  testWidgets('Timetable app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const RHULTimetableApp());
    expect(find.text('Royal Holloway Login'), findsOneWidget);
  });
}
