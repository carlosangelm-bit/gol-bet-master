import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/main.dart';

void main() {
  testWidgets('Golf Bet Master smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const GolfBetApp());
    expect(find.text('Golf Bet Master'), findsWidgets);
  });
}
