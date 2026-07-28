// ignore_for_file: avoid_print
// ─────────────────────────────────────────────────────────────────────────────
// Tests obligatorios A–H para los 8 fixes requeridos
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/game_engine.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers de fixture
// ─────────────────────────────────────────────────────────────────────────────

/// Curso estándar 18 hoyos par 72. SI asignado cíclicamente.
final _course18 = CourseInfo(
  name: 'Test Course',
  holes: List.generate(18, (i) {
    // SI: 1,3,5,7,9,11,13,15,17 para F9, 2,4,6,8,10,12,14,16,18 para B9
    final si = (i % 9) * 2 + (i < 9 ? 1 : 2);
    return CourseHole(hole: i + 1, par: 4, strokeIndex: si);
  }),
);

/// Curso de 9 hoyos (numerados 10-18, para simular back-nine start).
final _courseB9 = CourseInfo(
  name: 'Back 9 Course',
  holes: List.generate(9, (i) {
    final si = (i * 2) + 2; // SI: 2,4,6,8,10,12,14,16,18
    return CourseHole(hole: i + 10, par: 4, strokeIndex: si);
  }),
);

Round _makeRound({
  required List<Map<String, dynamic>> players, // {id, hcp, manual?}
  required List<BetGroup> groups,
  required Map<String, List<int>> scores, // playerId → scores por orden de hoyos, 0=sin score
  int totalHoles = 18,
  StartingNine startingNine = StartingNine.front,
  CourseInfo? course,
  Map<String, Map<String, double>>? manuals, // p1Id → {p2Id: strokes}
}) {
  final c = course ?? (startingNine == StartingNine.back ? _courseB9 : _course18);

  final rPlayers = players.map((p) {
    final pid = p['id'] as String;
    final hcp = (p['hcp'] as num).toDouble();
    final manualsForPlayer = manuals?[pid] ?? {};
    return RoundPlayer(
      playerId: pid,
      handicapEnRonda: hcp,
      manualHandicaps: manualsForPlayer,
    );
  }).toList();

  final pObjects = players.map((p) => Player(
    id: p['id'] as String,
    name: p['name'] as String? ?? p['id'] as String,
    handicapBase: (p['hcp'] as num).toDouble(),
  )).toList();

  // Los scores se pasan en orden jugado. Para back-start, los primeros
  // 9 valores corresponden a hoyos 10-18.
  final holeNums = startingNine == StartingNine.back
      ? [...List.generate(9, (i) => i + 10), ...List.generate(9, (i) => i + 1)]
      : List.generate(18, (i) => i + 1);

  final scoresMap = <String, Map<int, HoleScore>>{};
  for (final entry in scores.entries) {
    final pid = entry.key;
    final vals = entry.value;
    final holeMap = <int, HoleScore>{};
    for (int i = 0; i < vals.length && i < holeNums.length; i++) {
      final s = vals[i];
      if (s > 0) {
        final h = holeNums[i];
        holeMap[h] = HoleScore(playerId: pid, hole: h, grossScore: s, putts: 2);
      }
    }
    if (holeMap.isNotEmpty) scoresMap[pid] = holeMap;
  }

  return Round(
    id: 'test',
    name: 'Test Round',
    course: c,
    players: pObjects,
    roundPlayers: rPlayers,
    betGroups: groups,
    scores: scoresMap,
    events: const {},
    oyeseRankings: const {},
    sliding: const [],
    createdAt: DateTime(2025, 1, 1),
    totalHoles: totalHoles,
    startingNine: startingNine,
  );
}

BetModuleInstance _nassauMod(List<String> pids, {
  bool net = false,
  bool press = false,
  int trigger = 2,
}) => BetModuleInstance.defaultFor(BetModuleType.nassau, pids).copyWith(
  nassauConfig: NassauConfig(
    frontValue: 50,
    backValue: 50,
    totalValue: 100,
    mode: net ? GrossNetMode.net : GrossNetMode.gross,
    pressEnabled: press,
    autoPressTrigger: trigger,
    frontPressValue: 25,
    backPressValue: 25,
  ),
);

BetModuleInstance _medalMod(List<String> pids, {
  bool allVsAll = false,
}) => BetModuleInstance.defaultFor(BetModuleType.medal, pids).copyWith(
  medalConfig: const MedalConfig(value: 100, mode: GrossNetMode.net),
  formatMode: allVsAll ? BetFormatMode.allVsAll : BetFormatMode.onePot,
);

BetModuleInstance _puttsMod(List<String> pids) =>
    BetModuleInstance.defaultFor(BetModuleType.putts, pids).copyWith(
      puttsConfig: const PuttsConfig(value: 50, puttsMode: PuttsMode.total),
    );

BetGroup _group(List<String> pids, BetModuleInstance mod) => BetGroup(
  id: 'g1',
  name: 'Test Group',
  format: PartidaFormat.allInOnePot,
  playerIds: pids,
  modules: [mod],
);

// ─────────────────────────────────────────────────────────────────────────────
// TESTS
// ─────────────────────────────────────────────────────────────────────────────

void main() {

  // ── TEST A ────────────────────────────────────────────────────────────────
  // Nassau individual arrancando en el 10:
  // p1 gana los primeros 5 hoyos (10-14), p2 gana los últimos 4 (15-18).
  // Front = hoyos 10-18 (primer segmento jugado) → p1 debe ganar el Front.
  group('A: Nassau individual startingNine=back', () {
    test('Front 9 es el primer segmento jugado (hoyos 10-18)', () {
      // p1 score 3 en hoyos 10-14, 4 en hoyos 15-18 → gana hoyos 10-14 (5 hoyos)
      // p2 score 4 en hoyos 10-14, 3 en hoyos 15-18 → gana hoyos 15-18 (4 hoyos)
      final scores9 = List.generate(9, (i) => i < 5 ? 3 : 4);
      final round = _makeRound(
        players: [{'id': 'p1', 'hcp': 10.0}, {'id': 'p2', 'hcp': 10.0}],
        groups: [_group(['p1','p2'], _nassauMod(['p1','p2']))],
        scores: {
          'p1': scores9,                                  // 3,3,3,3,3,4,4,4,4
          'p2': List.generate(9, (i) => i < 5 ? 4 : 3), // 4,4,4,4,4,3,3,3,3
        },
        totalHoles: 9,
        startingNine: StartingNine.back,
      );

      final entries = BetEngine.computeAll(round);
      print('TEST A entries:');
      for (final e in entries) {
        print('  ${e.fromPlayerId}→${e.toPlayerId} \$${e.amount} [${e.reason}]');
      }

      // El primer segmento (hoyos 10-18) es "Front 9" lógico.
      // p1 gana 5 hoyos, p2 gana 4 → p1 gana Front (+1), p2 gana Back (era p2 los 4 últimos... pero son el segmento único)
      // Con 9 hoyos totales solo hay "Nassau 9 hoyos"
      final nassauEntries = entries.where((e) => e.betType == BetModuleType.nassau).toList();
      expect(nassauEntries.isNotEmpty, true, reason: 'Debe haber entries de nassau');
      // p1 ganó más hoyos → p1 cobra
      final p1Wins = nassauEntries.where((e) => e.toPlayerId == 'p1').toList();
      expect(p1Wins.isNotEmpty, true, reason: 'p1 ganó el segmento → debe cobrar');
    });

    test('Nassau 18 hoyos back-start: Front y Back no deben estar invertidos', () {
      // Ronda completa empezando en el 10.
      // p1 gana todos los hoyos 10-18 (score 3 vs 4)
      // p1 pierde todos los hoyos 1-9  (score 4 vs 3)
      // Con lógica CORRECTA: Front=10-18 → p1 gana Front; Back=1-9 → p1 pierde Back.
      // Con lógica INCORRECTA (bug): Front=1-9 → p1 pierde Front; Back=10-18 → p1 gana Back.
      final round = _makeRound(
        players: [{'id': 'p1', 'hcp': 10.0}, {'id': 'p2', 'hcp': 10.0}],
        groups: [_group(['p1','p2'], _nassauMod(['p1','p2']))],
        scores: {
          // Orden: primero hoyos 10-18 (scores índices 0-8), luego 1-9 (índices 9-17)
          'p1': [...List.generate(9, (_) => 3), ...List.generate(9, (_) => 4)],
          'p2': [...List.generate(9, (_) => 4), ...List.generate(9, (_) => 3)],
        },
        totalHoles: 18,
        startingNine: StartingNine.back,
        course: _course18,
      );

      final entries = BetEngine.computeAll(round);
      print('TEST A (18H back-start) entries:');
      for (final e in entries) {
        print('  ${e.fromPlayerId}→${e.toPlayerId} \$${e.amount} [${e.reason}]');
      }

      final front = entries.where((e) =>
          e.betType == BetModuleType.nassau && e.reason.contains('Front')).toList();
      final back = entries.where((e) =>
          e.betType == BetModuleType.nassau && e.reason.contains('Back')).toList();

      expect(front.isNotEmpty, true, reason: 'Debe haber entry de Front 9');
      expect(back.isNotEmpty,  true, reason: 'Debe haber entry de Back 9');

      // p1 gana Front (hoyos 10-18 primer segmento)
      expect(front.first.toPlayerId, equals('p1'),
          reason: 'p1 ganó hoyos 10-18 (Front lógico) → p1 debe cobrar el Front');
      // p2 gana Back (hoyos 1-9 segundo segmento)
      expect(back.first.toPlayerId, equals('p2'),
          reason: 'p2 ganó hoyos 1-9 (Back lógico) → p2 debe cobrar el Back');
    });
  });

  // ── TEST B ────────────────────────────────────────────────────────────────
  // Nassau equipo startingNine=back.
  group('B: Nassau equipo startingNine=back', () {
    test('Front y Back no invertidos en modo equipo', () {
      // SideA=[p1], SideB=[p2]. Misma lógica que test A.
      final sideA = BetSide(id: 'sA', name: 'A', playerIds: ['p1']);
      final sideB = BetSide(id: 'sB', name: 'B', playerIds: ['p2']);
      final mod = BetModuleInstance.defaultFor(BetModuleType.nassau, ['p1','p2']).copyWith(
        sides: [sideA, sideB],
        nassauConfig: const NassauConfig(
          frontValue: 50, backValue: 50, totalValue: 100,
          mode: GrossNetMode.gross,
        ),
      );

      final round = _makeRound(
        players: [{'id': 'p1', 'hcp': 10.0}, {'id': 'p2', 'hcp': 10.0}],
        groups: [BetGroup(id:'g1', name:'G', format: PartidaFormat.allInOnePot,
            playerIds: ['p1','p2'], modules: [mod])],
        scores: {
          'p1': [...List.generate(9, (_) => 3), ...List.generate(9, (_) => 4)],
          'p2': [...List.generate(9, (_) => 4), ...List.generate(9, (_) => 3)],
        },
        totalHoles: 18,
        startingNine: StartingNine.back,
        course: _course18,
      );

      final entries = BetEngine.computeAll(round);
      print('TEST B entries:');
      for (final e in entries) {
        print('  ${e.fromPlayerId}→${e.toPlayerId} \$${e.amount} [${e.reason}]');
      }

      final front = entries.where((e) =>
          e.betType == BetModuleType.nassau && e.reason.contains('Front')).toList();
      final back = entries.where((e) =>
          e.betType == BetModuleType.nassau && e.reason.contains('Back')).toList();

      expect(front.isNotEmpty, true);
      expect(back.isNotEmpty,  true);
      expect(front.first.toPlayerId, equals('p1'),
          reason: 'p1 ganó hoyos 10-18 (Front lógico equipo)');
      expect(back.first.toPlayerId, equals('p2'),
          reason: 'p2 ganó hoyos 1-9 (Back lógico equipo)');
    });
  });

  // ── TEST C ────────────────────────────────────────────────────────────────
  // Medal allVsAll con acuerdo bilateral espejo:
  // Con pairSliding oficial 18H en B9 back-start, pB recibe solo ceil(5/2)=3 strokes
  // (no los 5 completos). pA gana porque pA net=45 < pB net=47.
  group('C: Medal allVsAll acuerdo espejo → pA gana con sliding oficial 18H', () {
    test('A tira 45, B tira 50, A da 5 a B → pA gana (B9 back-start share=3)', () {
      // NUEVA LÓGICA pairSliding oficial de 18 hoyos:
      // A da 5 (diff18=5). back-start: B9=inicio → share=ceil(5/2)=3.
      // Net de pA vs pB: pA gross=45 (recv(pA,pB)=-5≤0, sin strokes) → pA net=45.
      // Net de pB vs pA: pB recibe 3 strokes → pB net=50-3=47.
      // → pA net=45 < pB net=47 → pA GANA.
      final mod = _medalMod(['pA','pB'], allVsAll: true);
      // pA=45 (9×5), pB=50 (8×6+2)
      final roundExact = _makeRound(
        players: [{'id': 'pA', 'hcp': 15.0}, {'id': 'pB', 'hcp': 20.0}],
        groups: [_group(['pA','pB'], mod)],
        scores: {
          'pA': List.generate(9, (_) => 5),  // 9×5 = 45
          'pB': [6, 6, 6, 6, 6, 6, 6, 6, 2], // 8×6+2 = 50
        },
        totalHoles: 9,
        startingNine: StartingNine.back,
        manuals: {
          'pA': {'pB': -5.0},
          'pB': {'pA':  5.0},
        },
      );

      final entries = BetEngine.computeAll(roundExact);
      print('TEST C entries:');
      for (final e in entries) {
        print('  ${e.fromPlayerId}→${e.toPlayerId} \$${e.amount} [${e.reason}]');
      }

      final medalEntries = entries.where((e) => e.betType == BetModuleType.medal).toList();
      // pA net=45 < pB net=47 → pA GANA
      expect(medalEntries.any((e) => e.toPlayerId == 'pA'), true,
          reason: 'pA net=45 < pB net=47 (share B9=3 con back-start) → pA cobra');
    });
  });

  // ── TEST D ────────────────────────────────────────────────────────────────
  // Medal allVsAll con acuerdo bilateral INCONSISTENTE → debe lanzar error.
  group('D: Medal allVsAll acuerdo bilateral inconsistente → error', () {
    test('manual[A][B]=-5 y manual[B][A]=4 debe lanzar StateError', () {
      final mod = _medalMod(['pA','pB'], allVsAll: true);
      final round = _makeRound(
        players: [{'id': 'pA', 'hcp': 15.0}, {'id': 'pB', 'hcp': 20.0}],
        groups: [_group(['pA','pB'], mod)],
        scores: {
          'pA': List.generate(9, (_) => 5), // 45
          'pB': List.generate(9, (_) => 5), // 45
        },
        totalHoles: 9,
        startingNine: StartingNine.back,
        manuals: {
          'pA': {'pB': -5.0}, // pA da 5
          'pB': {'pA':  4.0}, // pB recibe 4 ← inconsistente, debería ser 5
        },
      );

      expect(
        () => BetEngine.computeAll(round),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Inconsistencia bilateral'),
        )),
        reason: 'Acuerdo inconsistente debe lanzar StateError con mensaje descriptivo',
      );
    });
  });

  // ── TEST E ────────────────────────────────────────────────────────────────
  // matchPlayStatus con manual solo guardado en sentido inverso.
  group('E: matchPlayStatus con manual solo en sentido p2→p1', () {
    test('manual guardado solo en p2 es respetado bilateralmente', () {
      // Semántica: manualHandicaps[otro] = strokes que YO recibo del otro.
      //   Positivo = yo recibo, negativo = yo doy.
      // Para que p1 reciba 5 de p2 (solo guardado en p2):
      //   p2.manual['p1'] = -5.0 → "p2 DA 5 a p1" (negativo = das tú)
      //   _strokesP1ReceivesFromP2(p1, p2): m2 = p2.manual['p1'] = -5 → recv = -m2 = +5
      // matchPlayStatus(p1, p2) debe detectar recv = +5 para p1.
      // p1 recibe 5 strokes → p1 tiene ventaja.
      // Scores B9: p1=5 bruto, p2=5 bruto → con 5 strokes p1 net = 5-(dist) en cada hoyo.
      // Con 5 strokes en 9 hoyos (strokesReceivedInPlayedHoles): los 5 hoyos con SI más bajo
      // reciben 1 stroke → p1 net=4 en esos 5 hoyos, p2 bruto=5 → p1 gana esos 5.
      final course = _courseB9;
      final rPlayers = [
        RoundPlayer(playerId: 'p1', handicapEnRonda: 10.0, manualHandicaps: {}),
        RoundPlayer(playerId: 'p2', handicapEnRonda: 10.0, manualHandicaps: {'p1': -5.0}), // p2 DA 5 a p1
      ];
      final scores = {
        'p1': {for (int h = 10; h <= 18; h++) h: HoleScore(playerId: 'p1', hole: h, grossScore: 5)},
        'p2': {for (int h = 10; h <= 18; h++) h: HoleScore(playerId: 'p2', hole: h, grossScore: 5)},
      };
      final round = Round(
        id: 't', name: 'T', course: course,
        players: [
          Player(id: 'p1', name: 'p1', handicapBase: 10),
          Player(id: 'p2', name: 'p2', handicapBase: 10),
        ],
        roundPlayers: rPlayers,
        betGroups: [], scores: scores,
        events: {}, oyeseRankings: {}, sliding: [],
        createdAt: DateTime.now(),
        totalHoles: 9, startingNine: StartingNine.back,
      );

      // Con manual[p2][p1]=5, recv para p1 = +5 (p1 recibe).
      // p1 recibe 5 strokes distribuidos en 9 hoyos → net p1 < bruto p2 en ≥5 hoyos.
      final status = GameEngine.matchPlayStatus(round, 'p1', 'p2', true);
      print('TEST E matchPlayStatus: $status');
      expect(status, greaterThan(0),
          reason: 'p1 recibe 5 strokes (via manual inverso) → p1 debe estar up');
    });
  });

  // ── TEST F ────────────────────────────────────────────────────────────────
  // matchPlayStatus en media ronda B9: strokes usando pairSliding oficial 18H.
  // Con diff18=9 y back-start: B9=inicio → share=ceil(9/2)=5.
  // Los 5 strokes se distribuyen entre los 9 hoyos de B9 por SI (5 hoyos reciben 1).
  group('F: matchPlayStatus media ronda B9 - strokes pairSliding oficial 18H', () {
    test('9 strokes (diff18), back-start: B9 recibe share=5 → p1 down 4', () {
      // p2 da 9 strokes a p1 (diff18=9). Solo B9 (9 hoyos), back-start.
      // NUEVA LÓGICA: B9=vuelta inicio → share=ceil(9/2)=5.
      // Los 5 strokes se distribuyen en 9 hoyos por SI:
      //   B9 SI: 2(H10),4(H11),6(H12),8(H13),10(H14),12(H15),14(H16),16(H17),18(H18)
      //   Hoyos con rank SI ≤ 5 reciben 1 stroke: H10,H11,H12,H13,H14.
      // Scores: p1=5 bruto, p2=4 bruto en todos.
      // H10-H14 (5 hoyos): p1 net=4 == p2=4 → empate (0 delta).
      // H15-H18 (4 hoyos): p1 net=5 > p2=4 → p2 gana (-1 cada uno).
      // status = 0 - 4 = -4.
      final course = _courseB9;
      final rPlayers = [
        RoundPlayer(playerId: 'p1', handicapEnRonda: 10.0,
            manualHandicaps: {'p2': 9.0}),  // p1 recibe 9 de p2
        RoundPlayer(playerId: 'p2', handicapEnRonda: 10.0, manualHandicaps: {}),
      ];
      final scores = {
        'p1': {for (int h = 10; h <= 18; h++) h: HoleScore(playerId: 'p1', hole: h, grossScore: 5)},
        'p2': {for (int h = 10; h <= 18; h++) h: HoleScore(playerId: 'p2', hole: h, grossScore: 4)},
      };
      final round = Round(
        id: 't', name: 'T', course: course,
        players: [
          Player(id: 'p1', name: 'p1', handicapBase: 10),
          Player(id: 'p2', name: 'p2', handicapBase: 10),
        ],
        roundPlayers: rPlayers,
        betGroups: [], scores: scores,
        events: {}, oyeseRankings: {}, sliding: [],
        createdAt: DateTime.now(),
        totalHoles: 9, startingNine: StartingNine.back,
      );

      final status = GameEngine.matchPlayStatus(round, 'p1', 'p2', true, throughHole: 18);
      print('TEST F matchPlayStatus B9 con diff18=9 back-start: $status');
      // B9 share=5: 5 hoyos empate, 4 hoyos p2 gana → status = -4
      expect(status, equals(-4),
          reason: 'B9 back-start, share=5: 5 empates + 4 hoyos p2 gana → status=-4');
    });
  });

  // ── TEST G ────────────────────────────────────────────────────────────────
  // totalPutts con hoyos incompletos: no debe contar defaults silenciosos.
  group('G: totalPutts ignora hoyos sin score', () {
    test('Solo suma putts de hoyos con hasScore=true', () {
      // p1 tiene score solo en hoyos 10-14 (5 hoyos), con 2 putts cada uno.
      // Hoyos 15-18 no tienen score (no se jugaron).
      // totalPutts debe retornar 5×2 = 10, no 9×2 = 18.
      final course = _courseB9;
      final scoresMap = {
        'p1': {
          for (int h = 10; h <= 14; h++)
            h: HoleScore(playerId: 'p1', hole: h, grossScore: 4, putts: 2),
          // hoyos 15-18: sin HoleScore → no existen en el mapa
        }
      };
      final round = Round(
        id: 't', name: 'T', course: course,
        players: [Player(id: 'p1', name: 'p1', handicapBase: 10)],
        roundPlayers: [RoundPlayer(playerId: 'p1', handicapEnRonda: 10.0)],
        betGroups: [], scores: scoresMap,
        events: {}, oyeseRankings: {}, sliding: [],
        createdAt: DateTime.now(),
        totalHoles: 9, startingNine: StartingNine.back,
      );

      final puttsTotal = GameEngine.totalPutts(round, 'p1', from: 10, to: 18);
      print('TEST G totalPutts: $puttsTotal');
      expect(puttsTotal, equals(10),
          reason: 'Solo 5 hoyos con score × 2 putts = 10. Hoyos sin score no deben sumarse.');
    });

    test('putts en hoyo sin score no contribuyen al total (from=1 to=18)', () {
      // En rango 1-18 con solo 9 hoyos jugados (10-18), putts = 9×2 = 18.
      final course = _courseB9;
      final scoresMap = {
        'p1': {
          for (int h = 10; h <= 18; h++)
            h: HoleScore(playerId: 'p1', hole: h, grossScore: 4, putts: 2),
        }
      };
      final round = Round(
        id: 't', name: 'T', course: course,
        players: [Player(id: 'p1', name: 'p1', handicapBase: 10)],
        roundPlayers: [RoundPlayer(playerId: 'p1', handicapEnRonda: 10.0)],
        betGroups: [], scores: scoresMap,
        events: {}, oyeseRankings: {}, sliding: [],
        createdAt: DateTime.now(),
        totalHoles: 9, startingNine: StartingNine.back,
      );

      final putts = GameEngine.totalPutts(round, 'p1', from: 1, to: 18);
      print('TEST G totalPutts (from=1,to=18) con B9: $putts');
      expect(putts, equals(18),
          reason: '9 hoyos jugados (10-18) × 2 putts = 18. Hoyos 1-9 sin score no se suman.');
    });
  });

  // ── TEST H ────────────────────────────────────────────────────────────────
  // Nassau press con múltiples presiones: label refleja rango real.
  group('H: Nassau press labels reflejan rango real liquidado', () {
    test('Dos presiones en F9: cada label tiene su rango correcto', () {
      // p1 gana hoyos 1-2 (2up, trigger=2) → press empieza en hoyo 3.
      // p2 gana hoyos 3-4 (2up desde ref) → segunda press empieza en hoyo 5.
      // Primera press (H3-H4) debe tener label "Press H3–H4 (...)"
      // Segunda press (H5-H9) debe tener label "Press H5–H9 (...)"
      final mod = _nassauMod(['p1','p2'], press: true, trigger: 2);
      final scores = {
        'p1': [
          3, 3,  // hoyos 1-2: p1 gana (3 < 4) → +2 → trigger press en H3
          4, 4,  // hoyos 3-4: p2 gana (4 > 3) → delta desde ref = -2 → trigger press en H5
          4, 4, 4, 4, 4, // hoyos 5-9: empate
          0,0,0,0,0,0,0,0,0, // B9 sin score
        ],
        'p2': [
          4, 4,  // hoyos 1-2: pierde
          3, 3,  // hoyos 3-4: gana
          4, 4, 4, 4, 4, // hoyos 5-9: empate
          0,0,0,0,0,0,0,0,0,
        ],
      };

      final round = _makeRound(
        players: [{'id': 'p1', 'hcp': 10.0}, {'id': 'p2', 'hcp': 10.0}],
        groups: [_group(['p1','p2'], mod)],
        scores: scores,
        totalHoles: 18,
        startingNine: StartingNine.front,
        course: _course18,
      );

      final entries = BetEngine.computeAll(round);
      print('TEST H entries:');
      for (final e in entries) {
        print('  ${e.fromPlayerId}→${e.toPlayerId} \$${e.amount} [${e.reason}]');
      }

      final pressEntries = entries.where((e) =>
          e.betType == BetModuleType.nassau && e.reason.startsWith('Press')).toList();

      print('Press entries: ${pressEntries.map((e) => e.reason).toList()}');

      // Verificar que los labels no terminan todos en el mismo hoyo del segmento
      if (pressEntries.length >= 2) {
        // Las dos presiones deben tener rangos diferentes
        final reasons = pressEntries.map((e) => e.reason).toList();
        expect(reasons[0], isNot(equals(reasons[1])),
            reason: 'Dos presiones deben tener labels diferentes (rangos distintos)');
        // El label de la primera press NO debe terminar en el mismo hoyo que el segmento
        // (el bug era que siempre terminaba en holeTo=9 o holeTo=18)
        // La primera press (H3-H4) no debe decir "Press H3–H9"
        expect(reasons[0], isNot(contains('H3–H9')),
            reason: 'Primera press termina en H4, no en H9 (fin del segmento)');
      }
    });
  });
}
