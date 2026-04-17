// Test: ronda 18H, startingNine=back, B9 jugado completo, F9 en progreso (solo H1 jugado)
// Receptor debe recibir strokes en F9 distribuidos correctamente

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/game_engine.dart';

void main() {
  // Curso 18H estándar
  final course18 = CourseInfo(
    name: 'Test 18H',
    holes: [
      ...List.generate(9, (i) => CourseHole(hole: i+1, par: 4, strokeIndex: (i*2)+1)), // F9: SI 1,3,5,7,9,11,13,15,17
      ...List.generate(9, (i) => CourseHole(hole: i+10, par: 4, strokeIndex: (i*2)+2)), // B9: SI 2,4,6,8,10,12,14,16,18
    ],
  );

  test('Ronda en progreso: B9 completo + F9 parcial (H1-H3 jugados), startingNine=back', () {
    // A(HCP10) da 10 strokes a B(HCP20) → diff18=10
    // B9 (vuelta inicio): B recibe ceil(10/2)=5 strokes → SI 2,4,6,8,10 → H10,H11,H12,H13,H14
    // F9 (vuelta secundaria): B recibe floor(10/2)=5 strokes → SI 1,3,5,7,9 → H1,H2,H3,H4,H5
    
    // Ronda en progreso: B9 jugado completo, F9 solo H1,H2,H3 jugados
    final scoresA = {
      for (int h = 10; h <= 18; h++) h: HoleScore(playerId:'A', hole:h, grossScore:4, putts:2),
      1: HoleScore(playerId:'A', hole:1, grossScore:4, putts:2),
      2: HoleScore(playerId:'A', hole:2, grossScore:4, putts:2),
      3: HoleScore(playerId:'A', hole:3, grossScore:4, putts:2),
    };
    final scoresB = {
      for (int h = 10; h <= 18; h++) h: HoleScore(playerId:'B', hole:h, grossScore:5, putts:2),
      1: HoleScore(playerId:'B', hole:1, grossScore:5, putts:2),
      2: HoleScore(playerId:'B', hole:2, grossScore:5, putts:2),
      3: HoleScore(playerId:'B', hole:3, grossScore:5, putts:2),
    };

    final round = Round(
      id: 'test', name: 'Test',
      course: course18,
      players: [Player(id:'A', name:'A', handicapBase:10), Player(id:'B', name:'B', handicapBase:20)],
      roundPlayers: [
        RoundPlayer(playerId:'A', handicapEnRonda:10),
        RoundPlayer(playerId:'B', handicapEnRonda:20),
      ],
      betGroups: [],
      scores: {'A': scoresA, 'B': scoresB},
      events: const {}, oyeseRankings: const {}, sliding: const [],
      createdAt: DateTime(2025,1,1),
      totalHoles: 18,
      startingNine: StartingNine.back,
      pairSliding: {'A|B': -10.0}, // B recibe 10 (A da)
    );

    print('\n=== TEST: B9 completo + F9 parcial (H1-H3), startingNine=back ===');
    print('diff18=10 → B9(inicio): ceil(5)=5 strokes, F9(secundaria): floor(5)=5 strokes');
    print('\nStrokes por hoyo (splitHolesForPlayerPublic):');
    
    final allHoles = course18.holes;
    final (f9, b9) = BetEngine.splitHolesForPlayerPublic(round, 'B', allHoles);
    print('  receiverF9holes (jugados): ${f9.map((h) => 'H${h.hole}').toList()}');
    print('  receiverB9holes (jugados): ${b9.map((h) => 'H${h.hole}').toList()}');
    
    print('\n  Strokes en cada hoyo jugado:');
    final recvOfficial = BetEngine.strokesP1ReceivesFromP2(round, 'A', 'B');
    final recvAbs = recvOfficial.abs().round();
    print('  recvOfficial(A de B) = $recvOfficial → B recibe ${-recvOfficial}');
    
    for (final ch in [...b9, ...f9]) {
      final strokes = GameEngine.strokesReceivedFromOfficial18Sliding(
        diff18: recvAbs,
        ch: ch,
        playedHolesInSameNine: f9.any((h) => h.hole == ch.hole) ? f9 : b9,
        startingNine: StartingNine.back,
      );
      print('  H${ch.hole}(SI${ch.strokeIndex}): $strokes stroke(s)');
    }
    
    // Verificar strokes scorecard
    final mod = BetModuleInstance(
      id: 'ski1', type: BetModuleType.skins, name: 'Skins',
      participantIds: ['A','B'],
      formatMode: BetFormatMode.allVsAll,
      skinsConfig: SkinsConfig(valuePerSkin: 10, carryOver: false, mode: GrossNetMode.net),
    );
    final results = BetEngine.skinsScorecard(round, 'A', 'B', mod);
    print('\n  Scorecard skins:');
    for (final r in results) {
      if (!r.isPending) {
        print('  H${r.hole}: winner=${r.winner ?? (r.isTie ? "TIE" : "?")} pot=${r.pot}');
      }
    }
  });
}
