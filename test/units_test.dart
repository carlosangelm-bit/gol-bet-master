// ignore_for_file: avoid_print
// ─────────────────────────────────────────────────────────────────────────────
// Tests de BetModuleType.units
//
// Bug corregido: _units iteraba h=1..totalHoles, fallando cuando
// startingNine=back porque los eventos están guardados en los hoyos 10-18.
// Fix: iterar sobre round.course.holes (hoyos físicos reales).
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';

// ── Helper: 18 hoyos estándar ─────────────────────────────────────────────────
List<CourseHole> _holes18() => List.generate(18, (i) => CourseHole(
  hole: i + 1, par: 4,
  strokeIndex: [5, 11, 15, 1, 9, 17, 3, 13, 7, 6, 2, 18, 8, 4, 16, 10, 12, 14][i],
));

// ── Helper: módulo de units configurable ─────────────────────────────────────
BetModuleInstance _unitsMod(List<String> pids, {double value = 10}) =>
    BetModuleInstance(
      id: 'u1',
      type: BetModuleType.units,
      name: 'Units Test',
      participantIds: pids,
      unitsConfig: UnitsConfig().withAllEventsValue(value),
    );

// ── Helper: ronda de 9 hoyos ──────────────────────────────────────────────────
Round _makeRound({
  required List<Player> players,
  required Map<String, Map<int, HoleScore>> scores,
  required Map<String, Map<int, List<HoleEvent>>> events,
  required StartingNine startingNine,
  int totalHoles = 9,
}) {
  final mod   = _unitsMod(players.map((p) => p.id).toList());
  final group = BetGroup(
    id: 'g1', name: 'Test',
    format: PartidaFormat.allInOnePot,
    playerIds: players.map((p) => p.id).toList(),
    modules: [mod],
  );
  return Round(
    id: 'r1', name: 'Test',
    course: CourseInfo(name: 'Test', holes: _holes18()),
    players: players,
    roundPlayers: players.map((p) =>
        RoundPlayer(playerId: p.id, handicapEnRonda: p.handicapBase.toDouble())).toList(),
    betGroups: [group],
    scores: scores,
    events: events,
    oyeseRankings: {}, sliding: [],
    createdAt: DateTime.now(),
    startingNine: startingNine,
    totalHoles: totalHoles,
  );
}

void main() {
  // ── Caso 1: Front nine — birdies en H1, H3 ──────────────────────────────────
  test('units front nine: birdies en H1 y H3 generan entries correctamente', () {
    final p1 = Player(id: 'p1', name: 'Alpha', handicapBase: 10, colorIndex: 0);
    final p2 = Player(id: 'p2', name: 'Beta',  handicapBase: 10, colorIndex: 1);

    final events = <String, Map<int, List<HoleEvent>>>{
      'p1': {
        1: [HoleEvent(playerId: 'p1', hole: 1, type: UnitEventType.birdie)],
        3: [HoleEvent(playerId: 'p1', hole: 3, type: UnitEventType.birdie)],
      },
      'p2': {},
    };
    final scores = <String, Map<int, HoleScore>>{
      'p1': {for (int h = 1; h <= 9; h++) h: HoleScore(playerId: 'p1', hole: h, grossScore: 4)},
      'p2': {for (int h = 1; h <= 9; h++) h: HoleScore(playerId: 'p2', hole: h, grossScore: 4)},
    };

    final round = _makeRound(
      players: [p1, p2], scores: scores, events: events,
      startingNine: StartingNine.front,
    );

    final entries = BetEngine.computeAll(round)
        .where((e) => e.betType == BetModuleType.units).toList();

    print('Front nine units entries: ${entries.length}');
    for (final e in entries) {
      print('  ${e.fromPlayerId} → ${e.toPlayerId}: \$${e.amount}  [${e.reason}]');
    }

    // 2 birdies × $10 × 1 oponente = $20 total que p2 paga a p1
    expect(entries.length, 2, reason: '2 birdies → 2 entries');
    expect(entries.every((e) => e.fromPlayerId == 'p2' && e.toPlayerId == 'p1'), true,
        reason: 'p2 paga a p1 en ambos');
    expect(entries.fold<double>(0, (s, e) => s + e.amount), 20.0,
        reason: '2 × \$10 = \$20');

    final bd = LedgerEngine.breakdownBetween(round, 'p1', 'p2');
    expect(bd[BetModuleType.units], 20.0,
        reason: 'breakdown p1 vs p2 = +\$20');
  });

  // ── Caso 2: Back nine (startingNine=back) — birdie en H12 ────────────────────
  // BUG PREVIO: _units iteraba h=1..9 y nunca encontraba el evento en H12.
  test('units back nine: birdie en H12 (startingNine=back) genera entry correctamente', () {
    final p1 = Player(id: 'p1', name: 'CAM', handicapBase: 14, colorIndex: 0);
    final p2 = Player(id: 'p2', name: 'CAV', handicapBase: 12, colorIndex: 1);

    final events = <String, Map<int, List<HoleEvent>>>{
      'p1': {
        12: [HoleEvent(playerId: 'p1', hole: 12, type: UnitEventType.birdie)],
      },
      'p2': {},
    };
    final scores = <String, Map<int, HoleScore>>{
      'p1': {for (int h = 10; h <= 18; h++) h: HoleScore(playerId: 'p1', hole: h, grossScore: 4)},
      'p2': {for (int h = 10; h <= 18; h++) h: HoleScore(playerId: 'p2', hole: h, grossScore: 4)},
    };

    final round = _makeRound(
      players: [p1, p2], scores: scores, events: events,
      startingNine: StartingNine.back,
    );

    final entries = BetEngine.computeAll(round)
        .where((e) => e.betType == BetModuleType.units).toList();

    print('Back nine units entries: ${entries.length}');
    for (final e in entries) {
      print('  ${e.fromPlayerId} → ${e.toPlayerId}: \$${e.amount}  [${e.reason}]');
    }

    // 1 birdie en H12 × $10 × 1 oponente = 1 entry de $10
    expect(entries.length, 1,
        reason: 'Debe haber 1 entry para el birdie en H12 (BUG: antes devolvía 0)');
    expect(entries.first.fromPlayerId, 'p2');
    expect(entries.first.toPlayerId,   'p1');
    expect(entries.first.amount,       10.0);
    expect(entries.first.hole,         12);

    final bd = LedgerEngine.breakdownBetween(round, 'p1', 'p2');
    expect(bd[BetModuleType.units], 10.0,
        reason: 'breakdown p1 vs p2 = +\$10 (BUG: antes era null/0)');
  });

  // ── Caso 3: Back nine — múltiples eventos, ambos jugadores ───────────────────
  test('units back nine: múltiples eventos ambos jugadores — balances simétricos', () {
    final p1 = Player(id: 'p1', name: 'A', handicapBase: 10, colorIndex: 0);
    final p2 = Player(id: 'p2', name: 'B', handicapBase: 10, colorIndex: 1);

    // p1: birdie en H10, eagle en H15 (vale 2x default = $20)
    // p2: birdie en H13
    final events = <String, Map<int, List<HoleEvent>>>{
      'p1': {
        10: [HoleEvent(playerId: 'p1', hole: 10, type: UnitEventType.birdie)],
        15: [HoleEvent(playerId: 'p1', hole: 15, type: UnitEventType.eagle)],
      },
      'p2': {
        13: [HoleEvent(playerId: 'p2', hole: 13, type: UnitEventType.birdie)],
      },
    };
    final scores = <String, Map<int, HoleScore>>{
      'p1': {for (int h = 10; h <= 18; h++) h: HoleScore(playerId: 'p1', hole: h, grossScore: 4)},
      'p2': {for (int h = 10; h <= 18; h++) h: HoleScore(playerId: 'p2', hole: h, grossScore: 4)},
    };

    // Módulo con birdie=$10, eagle=$20
    final mod = BetModuleInstance(
      id: 'u1', type: BetModuleType.units, name: 'Units',
      participantIds: ['p1', 'p2'],
      unitsConfig: UnitsConfig(eventValues: {
        UnitEventType.birdie:      10,
        UnitEventType.eagle:       20,
        UnitEventType.sandyPar:    10,
        UnitEventType.parUnico:    10,
        UnitEventType.birdieUnico: 10,
        UnitEventType.holeOut:     10,
      }),
    );
    final group = BetGroup(
      id: 'g1', name: 'Test', format: PartidaFormat.allInOnePot,
      playerIds: ['p1', 'p2'], modules: [mod],
    );
    final round = Round(
      id: 'r1', name: 'Multi events back',
      course: CourseInfo(name: 'Test', holes: _holes18()),
      players: [p1, p2],
      roundPlayers: [
        RoundPlayer(playerId: 'p1', handicapEnRonda: 10),
        RoundPlayer(playerId: 'p2', handicapEnRonda: 10),
      ],
      betGroups: [group], scores: scores, events: events,
      oyeseRankings: {}, sliding: [],
      createdAt: DateTime.now(),
      startingNine: StartingNine.back,
      totalHoles: 9,
    );

    final entries = BetEngine.computeAll(round)
        .where((e) => e.betType == BetModuleType.units).toList();

    print('Multi-event back nine: ${entries.length} entries');
    for (final e in entries) {
      print('  ${e.fromPlayerId} → ${e.toPlayerId}: \$${e.amount}  [${e.reason}]');
    }

    // p1 gana: birdie H10 (+$10) + eagle H15 (+$20) = +$30 de p2
    // p2 gana: birdie H13 (+$10) = +$10 de p1
    // Net p1: +$30 - $10 = +$20
    final bd = LedgerEngine.breakdownBetween(round, 'p1', 'p2');
    print('breakdown p1 vs p2: ${bd[BetModuleType.units]}');

    expect(bd[BetModuleType.units], 20.0,
        reason: 'p1: birdie H10(\$10) + eagle H15(\$20) - birdie_p2 H13(\$10) = +\$20');

    // 3 entries totales: H10 p2→p1, H15 p2→p1, H13 p1→p2
    expect(entries.length, 3, reason: '3 eventos → 3 entries');
  });

  // ── Caso 4: Front nine — eagle vale más que birdie (valores diferenciados) ────
  test('units front nine: eagle vale doble que birdie', () {
    final p1 = Player(id: 'p1', name: 'Eagle', handicapBase: 0, colorIndex: 0);
    final p2 = Player(id: 'p2', name: 'Par',   handicapBase: 0, colorIndex: 1);

    final events = <String, Map<int, List<HoleEvent>>>{
      'p1': {
        5: [HoleEvent(playerId: 'p1', hole: 5, type: UnitEventType.eagle)],
      },
      'p2': {},
    };
    final scores = <String, Map<int, HoleScore>>{
      'p1': {for (int h = 1; h <= 9; h++) h: HoleScore(playerId: 'p1', hole: h, grossScore: 4)},
      'p2': {for (int h = 1; h <= 9; h++) h: HoleScore(playerId: 'p2', hole: h, grossScore: 4)},
    };

    final mod = BetModuleInstance(
      id: 'u1', type: BetModuleType.units, name: 'Units',
      participantIds: ['p1', 'p2'],
      unitsConfig: UnitsConfig(eventValues: {
        UnitEventType.birdie:      10,
        UnitEventType.eagle:       20,   // ← doble
        UnitEventType.sandyPar:    10,
        UnitEventType.parUnico:    10,
        UnitEventType.birdieUnico: 10,
        UnitEventType.holeOut:     50,
      }),
    );
    final group = BetGroup(
      id: 'g1', name: 'Test', format: PartidaFormat.allInOnePot,
      playerIds: ['p1', 'p2'], modules: [mod],
    );
    final round = Round(
      id: 'r1', name: 'Eagle test',
      course: CourseInfo(name: 'Test', holes: _holes18()),
      players: [p1, p2],
      roundPlayers: [
        RoundPlayer(playerId: 'p1', handicapEnRonda: 0),
        RoundPlayer(playerId: 'p2', handicapEnRonda: 0),
      ],
      betGroups: [group], scores: scores, events: events,
      oyeseRankings: {}, sliding: [],
      createdAt: DateTime.now(),
      startingNine: StartingNine.front,
      totalHoles: 9,
    );

    final entries = BetEngine.computeAll(round)
        .where((e) => e.betType == BetModuleType.units).toList();

    expect(entries.length, 1);
    expect(entries.first.amount, 20.0, reason: 'Eagle vale \$20');

    final bd = LedgerEngine.breakdownBetween(round, 'p1', 'p2');
    expect(bd[BetModuleType.units], 20.0);
  });

  // ── Caso 5: 3 jugadores — el ganador cobra de ambos ───────────────────────────
  test('units 3 jugadores: ganador cobra de los otros 2', () {
    final p1 = Player(id: 'p1', name: 'A', handicapBase: 10, colorIndex: 0);
    final p2 = Player(id: 'p2', name: 'B', handicapBase: 10, colorIndex: 1);
    final p3 = Player(id: 'p3', name: 'C', handicapBase: 10, colorIndex: 2);

    final events = <String, Map<int, List<HoleEvent>>>{
      'p1': {
        4: [HoleEvent(playerId: 'p1', hole: 4, type: UnitEventType.birdie)],
      },
      'p2': {},
      'p3': {},
    };
    final scores = <String, Map<int, HoleScore>>{
      'p1': {for (int h = 1; h <= 9; h++) h: HoleScore(playerId: 'p1', hole: h, grossScore: 4)},
      'p2': {for (int h = 1; h <= 9; h++) h: HoleScore(playerId: 'p2', hole: h, grossScore: 4)},
      'p3': {for (int h = 1; h <= 9; h++) h: HoleScore(playerId: 'p3', hole: h, grossScore: 4)},
    };

    final mod   = _unitsMod(['p1', 'p2', 'p3'], value: 10);
    final group = BetGroup(
      id: 'g1', name: 'Test', format: PartidaFormat.allInOnePot,
      playerIds: ['p1', 'p2', 'p3'], modules: [mod],
    );
    final round = Round(
      id: 'r1', name: '3 players',
      course: CourseInfo(name: 'Test', holes: _holes18()),
      players: [p1, p2, p3],
      roundPlayers: [
        RoundPlayer(playerId: 'p1', handicapEnRonda: 10),
        RoundPlayer(playerId: 'p2', handicapEnRonda: 10),
        RoundPlayer(playerId: 'p3', handicapEnRonda: 10),
      ],
      betGroups: [group], scores: scores, events: events,
      oyeseRankings: {}, sliding: [],
      createdAt: DateTime.now(),
      startingNine: StartingNine.front,
      totalHoles: 9,
    );

    final entries = BetEngine.computeAll(round)
        .where((e) => e.betType == BetModuleType.units).toList();

    print('3 players entries: ${entries.length}');
    for (final e in entries) {
      print('  ${e.fromPlayerId} → ${e.toPlayerId}: \$${e.amount}');
    }

    // p1 birdie H4: p2 paga $10 a p1 + p3 paga $10 a p1 = 2 entries
    expect(entries.length, 2, reason: 'p1 cobra de p2 y p3 → 2 entries');
    expect(entries.every((e) => e.toPlayerId == 'p1'), true,
        reason: 'ambas entradas van a p1');
    expect(entries.fold<double>(0, (s, e) => s + e.amount), 20.0,
        reason: '2 oponentes × \$10 = \$20');
  });

  // ── Caso 6: back nine — runningBalance incluye los hoyos B9 ──────────────────
  test('runningBalance back nine: balance en H12 refleja el birdie de p1', () {
    final p1 = Player(id: 'p1', name: 'A', handicapBase: 10, colorIndex: 0);
    final p2 = Player(id: 'p2', name: 'B', handicapBase: 10, colorIndex: 1);

    final events = <String, Map<int, List<HoleEvent>>>{
      'p1': {
        12: [HoleEvent(playerId: 'p1', hole: 12, type: UnitEventType.birdie)],
      },
      'p2': {},
    };
    final scores = <String, Map<int, HoleScore>>{
      'p1': {for (int h = 10; h <= 18; h++) h: HoleScore(playerId: 'p1', hole: h, grossScore: 4)},
      'p2': {for (int h = 10; h <= 18; h++) h: HoleScore(playerId: 'p2', hole: h, grossScore: 4)},
    };

    final round = _makeRound(
      players: [p1, p2], scores: scores, events: events,
      startingNine: StartingNine.back,
    );

    final rb = LedgerEngine.runningBalance(round, 'p1');
    print('runningBalance p1 back nine: $rb');

    // Antes de H12: balance = 0
    // En H12: +$10 (cobró birdie)
    // Después de H12: balance = $10
    expect(rb[12], 10.0,
        reason: 'En H12 p1 cobró \$10 por el birdie (BUG: antes era 0)');
    expect(rb[13], 10.0,
        reason: 'Balance se mantiene en \$10 después de H12');
    expect(rb[11] ?? 0.0, 0.0,
        reason: 'Antes de H12 el balance era 0');
  });
}
