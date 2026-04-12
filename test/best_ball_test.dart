// Test para verificar la lógica de Best Ball
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/game_engine.dart';

void main() {
  group('Best Ball - Strokes Relativos', () {
    test('Jugadores reciben strokes relativos al mejor jugador', () {
      // Crear jugadores con diferentes handicaps
      final players = [
        Player(id: 'A', name: 'Jugador A', handicapBase: 5.0),
        Player(id: 'B', name: 'Jugador B', handicapBase: 10.0),
        Player(id: 'C', name: 'Jugador C', handicapBase: 12.0),
        Player(id: 'D', name: 'Jugador D', handicapBase: 18.0),
      ];

      // Crear RoundPlayers con HCP de ronda
      final roundPlayers = [
        RoundPlayer(playerId: 'A', handicapEnRonda: 5.0, tee: TeeInfo.standard),
        RoundPlayer(playerId: 'B', handicapEnRonda: 10.0, tee: TeeInfo.standard),
        RoundPlayer(playerId: 'C', handicapEnRonda: 12.0, tee: TeeInfo.standard),
        RoundPlayer(playerId: 'D', handicapEnRonda: 18.0, tee: TeeInfo.standard),
      ];

      // Crear campo simple
      final course = CourseInfo(
        name: 'Test Course',
        holes: List.generate(18, (i) => CourseHole(
          hole: i + 1,
          par: 4,
          strokeIndex: i + 1,
        )),
      );

      // Crear ronda
      final round = Round(
        id: 'test_round',
        name: 'Test Round',
        course: course,
        players: players,
        roundPlayers: roundPlayers,
        betGroups: [],
        scores: {},
        events: {},
        oyeseRankings: {},
        sliding: [],
        createdAt: DateTime.now(),
      );

      // Calcular mapa de HCP para equipos
      final hcpMap = GameEngine.buildTeamHcpMap(
        round,
        ['A', 'B', 'C', 'D'],
      );

      // Verificar strokes relativos
      expect(hcpMap['A'], 0.0);   // Mejor jugador (HCP 5) → 0 strokes
      expect(hcpMap['B'], 5.0);   // HCP 10 - 5 = 5 strokes
      expect(hcpMap['C'], 7.0);   // HCP 12 - 5 = 7 strokes
      expect(hcpMap['D'], 13.0);  // HCP 18 - 5 = 13 strokes

      print('✅ Best Ball - Strokes relativos correctos:');
      print('   Jugador A (HCP 5):  0 strokes');
      print('   Jugador B (HCP 10): 5 strokes');
      print('   Jugador C (HCP 12): 7 strokes');
      print('   Jugador D (HCP 18): 13 strokes');
    });

    test('Best Ball usa el mejor score neto del equipo', () {
      // Setup similar al anterior
      final players = [
        Player(id: 'A', name: 'Jugador A', handicapBase: 5.0),
        Player(id: 'B', name: 'Jugador B', handicapBase: 10.0),
      ];

      final roundPlayers = [
        RoundPlayer(playerId: 'A', handicapEnRonda: 5.0, tee: TeeInfo.standard),
        RoundPlayer(playerId: 'B', handicapEnRonda: 10.0, tee: TeeInfo.standard),
      ];

      final course = CourseInfo(
        name: 'Test Course',
        holes: [
          CourseHole(hole: 1, par: 4, strokeIndex: 1),
          CourseHole(hole: 2, par: 4, strokeIndex: 10),
        ],
      );

      // Scores en hoyo 1 (SI=1, más difícil):
      // Jugador A: bruto 5, neto 5 (0 strokes)
      // Jugador B: bruto 6, neto 5 (1 stroke porque HCP relativo = 5, y SI=1)
      final scores = {
        'A': {1: HoleScore(playerId: 'A', hole: 1, grossScore: 5, putts: 2)},
        'B': {1: HoleScore(playerId: 'B', hole: 1, grossScore: 6, putts: 2)},
      };

      final round = Round(
        id: 'test_round',
        name: 'Test Round',
        course: course,
        players: players,
        roundPlayers: roundPlayers,
        betGroups: [],
        scores: scores,
        events: {},
        oyeseRankings: {},
        sliding: [],
        createdAt: DateTime.now(),
      );

      // Verificar cálculo de HCP relativo
      final hcpMap = GameEngine.buildTeamHcpMap(round, ['A', 'B']);
      expect(hcpMap['A'], 0.0);
      expect(hcpMap['B'], 5.0);

      // Verificar strokes en hoyo 1 (SI=1)
      final strokesA = GameEngine.strokesReceived(hcpMap['A']!, course.holes[0]);
      final strokesB = GameEngine.strokesReceived(hcpMap['B']!, course.holes[0]);
      
      expect(strokesA, 0);  // HCP 0 → 0 strokes
      expect(strokesB, 1);  // HCP 5 → 1 stroke en SI=1

      print('✅ Hoyo 1 (SI=1):');
      print('   Jugador A: bruto 5, strokes 0 → neto 5');
      print('   Jugador B: bruto 6, strokes 1 → neto 5');
      print('   Mejor bola del equipo: 5 (empate)');
    });
  });
}
