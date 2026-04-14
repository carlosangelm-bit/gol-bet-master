// ignore_for_file: avoid_print
// Smoke test básico — verifica que la app arranca sin crash.
// No monta GolfBetApp directamente (requiere Providers de Firebase),
// sino que valida que el entrypoint compila y las clases clave existen.
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';

void main() {
  testWidgets('Golf Bet Master smoke test — modelos y motor cargan correctamente',
      (WidgetTester tester) async {
    // Verifica que los modelos principales instancian sin error
    final player = Player(id: 'test', name: 'Test Player', handicapBase: 10);
    expect(player.id, equals('test'));

    final hole = CourseHole(hole: 1, par: 4, strokeIndex: 1);
    expect(hole.hole, equals(1));

    final course = CourseInfo(name: 'Test Course', holes: [hole]);
    expect(course.name, equals('Test Course'));

    // Verifica que BetEngine.computeAll no falla con ronda vacía
    final round = Round(
      id: 'smoke',
      name: 'Smoke Test',
      course: course,
      players: [player],
      roundPlayers: [RoundPlayer(playerId: 'test', handicapEnRonda: 10)],
      betGroups: [],
      scores: const {},
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2025, 1, 1),
    );

    final entries = BetEngine.computeAll(round);
    expect(entries, isEmpty, reason: 'Sin apuestas no debe haber entradas en el ledger');

    print('✅ Smoke test OK: modelos y motor cargados correctamente');
  });
}
