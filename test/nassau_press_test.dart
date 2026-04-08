import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';

void main() {
  test('nassauPress genera entries cuando hay scores (front start)', () {
    final p1 = Player(id: 'p1', name: 'Carlos', handicapBase: 10, colorIndex: 0);
    final p2 = Player(id: 'p2', name: 'Rafa',   handicapBase: 10, colorIndex: 1);

    final mod = BetModuleInstance(
      id: 'np1', type: BetModuleType.nassauPress, name: 'NP Test',
      participantIds: ['p1','p2'],
      nassauPressConfig: const NassauPressConfig(
        frontValue: 50, backValue: 50, totalValue: 100,
        frontPressValue: 25, backPressValue: 25,
        pressTriggerValue: 2,
        mode: GrossNetMode.gross, // gross para ignorar handicaps
      ),
    );

    final holes = List.generate(18, (i) => CourseHole(
      hole: i+1, par: 4,
      strokeIndex: [5,11,15,1,9,17,3,13,7,6,2,18,8,4,16,10,12,14][i],
    ));
    final course = CourseInfo(name: 'Test', holes: holes);

    // p1 gana hoyos 1,2,3 en F9 (score 3 vs 4 en esos hoyos), resto empate
    final scores = <String, Map<int, HoleScore>>{
      'p1': {for (int h=1; h<=9; h++) h: HoleScore(playerId:'p1', hole:h, grossScore: h<=3 ? 3 : 4)},
      'p2': {for (int h=1; h<=9; h++) h: HoleScore(playerId:'p2', hole:h, grossScore: 4)},
    };

    final group = BetGroup(
      id: 'g1', name: 'Test', format: PartidaFormat.allInOnePot,
      playerIds: ['p1','p2'],
      modules: [mod],
    );

    final round = Round(
      id: 'r1', name: 'Test Round', course: course,
      players: [p1, p2],
      roundPlayers: [
        RoundPlayer(playerId: 'p1', handicapEnRonda: 10),
        RoundPlayer(playerId: 'p2', handicapEnRonda: 10),
      ],
      betGroups: [group], scores: scores,
      events: {'p1': {}, 'p2': {}},
      oyeseRankings: {}, sliding: [],
      createdAt: DateTime.now(),
      startingNine: StartingNine.front,
      totalHoles: 9,
    );

    final entries = BetEngine.computeAll(round);
    print('=== Entries (${entries.length}) ===');
    for (final e in entries) {
      print('  ${e.fromPlayerId} → ${e.toPlayerId}: \$${e.amount}  [${e.reason}]');
    }

    final breakdown = LedgerEngine.breakdownBetween(round, 'p1', 'p2');
    print('=== Breakdown ===');
    breakdown.forEach((k,v) => print('  $k: \$$v'));

    // p1 gana 3 hoyos → F9 +3 → p2 paga a p1 \$50
    expect(entries.where((e) => e.betType == BetModuleType.nassauPress).isNotEmpty, true,
        reason: 'Debe haber al menos 1 entry de nassauPress');
    expect(breakdown[BetModuleType.nassauPress], greaterThan(0),
        reason: 'p1 ganó F9 → debe tener balance positivo');
  });

  test('nassauPress genera entries correctamente con startingNine=back (hoyos 10-18)', () {
    final p1 = Player(id: 'p1', name: 'CAV',  handicapBase: 0,  colorIndex: 0);
    final p2 = Player(id: 'p2', name: 'CAM',  handicapBase: 10, colorIndex: 1);

    final mod = BetModuleInstance(
      id: 'np1', type: BetModuleType.nassauPress, name: 'NP Back',
      participantIds: ['p1','p2'],
      nassauPressConfig: const NassauPressConfig(
        frontValue: 50, backValue: 50, totalValue: 100,
        frontPressValue: 50, backPressValue: 50,
        pressTriggerValue: 2,
        mode: GrossNetMode.gross, // gross para aislar el bug de startingNine
      ),
    );

    // 18 hoyos en el curso pero solo se juegan los 10-18
    final holes = List.generate(18, (i) => CourseHole(
      hole: i+1, par: 4,
      strokeIndex: [5,11,15,1,9,17,3,13,7,6,2,18,8,4,16,10,12,14][i],
    ));
    final course = CourseInfo(name: 'Test Back', holes: holes);

    // Scores reales de la ronda de prueba (hoyos 10-18)
    // CAM (p2) gana B9 3UP → CAV paga a CAM
    final scoresCAV = <int, HoleScore>{
      10: HoleScore(playerId:'p1', hole:10, grossScore: 6),
      11: HoleScore(playerId:'p1', hole:11, grossScore: 6),
      12: HoleScore(playerId:'p1', hole:12, grossScore: 6),
      13: HoleScore(playerId:'p1', hole:13, grossScore: 5),
      14: HoleScore(playerId:'p1', hole:14, grossScore: 3),
      15: HoleScore(playerId:'p1', hole:15, grossScore: 5),
      16: HoleScore(playerId:'p1', hole:16, grossScore: 5),
      17: HoleScore(playerId:'p1', hole:17, grossScore: 7),
      18: HoleScore(playerId:'p1', hole:18, grossScore: 6),
    };
    final scoresCAM = <int, HoleScore>{
      10: HoleScore(playerId:'p2', hole:10, grossScore: 5),
      11: HoleScore(playerId:'p2', hole:11, grossScore: 5),
      12: HoleScore(playerId:'p2', hole:12, grossScore: 6),
      13: HoleScore(playerId:'p2', hole:13, grossScore: 5),
      14: HoleScore(playerId:'p2', hole:14, grossScore: 4),
      15: HoleScore(playerId:'p2', hole:15, grossScore: 5),
      16: HoleScore(playerId:'p2', hole:16, grossScore: 3),
      17: HoleScore(playerId:'p2', hole:17, grossScore: 5),
      18: HoleScore(playerId:'p2', hole:18, grossScore: 4),
    };

    final group = BetGroup(
      id: 'g1', name: 'Test', format: PartidaFormat.allInOnePot,
      playerIds: ['p1','p2'],
      modules: [mod],
    );

    final round = Round(
      id: 'r1', name: 'Test Round Back', course: course,
      players: [p1, p2],
      roundPlayers: [
        RoundPlayer(playerId: 'p1', handicapEnRonda: 0),
        RoundPlayer(playerId: 'p2', handicapEnRonda: 10),
      ],
      betGroups: [group],
      scores: {'p1': scoresCAV, 'p2': scoresCAM},
      events: {'p1': {}, 'p2': {}},
      oyeseRankings: {}, sliding: [],
      createdAt: DateTime.now(),
      startingNine: StartingNine.back,  // ← clave: ronda en el back nine
      totalHoles: 9,
    );

    final entries = BetEngine.computeAll(round);
    print('=== Entries Back Nine (${entries.length}) ===');
    for (final e in entries) {
      print('  ${e.fromPlayerId} → ${e.toPlayerId}: \$${e.amount}  [${e.reason}]');
    }

    final breakdown = LedgerEngine.breakdownBetween(round, 'p1', 'p2');
    print('=== Breakdown Back Nine ===');
    breakdown.forEach((k,v) => print('  $k: \$$v'));

    // CAM (p2) gana B9 3UP → p1 paga a p2 → breakdown negativo para p1
    final npEntries = entries.where((e) => e.betType == BetModuleType.nassauPress).toList();
    expect(npEntries.isNotEmpty, true,
        reason: 'Debe haber entries de nassauPress en ronda back nine');
    expect(breakdown[BetModuleType.nassauPress], isNotNull);
    expect(breakdown[BetModuleType.nassauPress]!, lessThan(0),
        reason: 'p1 (CAV) perdió el B9 → balance debe ser negativo (p2=CAM gana)');
  });
}
