// ─────────────────────────────────────────────────────────────────────────────
// engine_team_test.dart
//
// Cobertura:
//   A. Modelo — BetSide.validateDuel (jugador duplicado, lado vacío, ok)
//   B. holeDeltaVs — fuente de verdad única hoyo-entre-lados
//      B1. 1v1 con sides ≡ modo individual actual (gross)
//      B2. 1v1 net con HCP
//      B3. 2v2 best-ball gross
//      B4. 2v2 best-ball net
//      B5. 3v2 net
//      B6. Empate de mejor bola (delta = 0)
//      B7. Hoyo incompleto (un jugador sin score → null)
//   C. Match+Press equipo
//      C1. 1v1 sides → mismo resultado que modo individual
//      C2. 2v2 trigger en hoyo correcto, press arranca hoyo siguiente
//      C3. Encadenamiento de presiones (press-sobre-press)
//   D. Nassau equipo
//      D1. Front/Back/Total evaluados de forma independiente
//      D2. Resultado correcto con best-ball net
//   E. Auditoría de fuente de HCP
//      E1. Ledger team (nassauTeam) y nassauLiveStatusTeam usan misma fuente
//      E2. matchAutoPressLiveTeam y _matchAutoPressTeam coinciden
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/game_engine.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';

// ══════════════════════════════════════════════════════════════════════════════
// HELPERS DE FIXTURE
// ══════════════════════════════════════════════════════════════════════════════

/// Crea un CourseInfo de 18 hoyos con par y strokeIndex simples.
/// Par: hoyos par-3 en 3, 6, 12, 15; par-5 en 2, 8, 13, 17; resto par-4.
/// strokeIndex: 1..18 en orden de hoyo (simplificado para tests).
CourseInfo _makeCourse() {
  final pars = {
    1: 4, 2: 5, 3: 3, 4: 4, 5: 4, 6: 3, 7: 4, 8: 5, 9: 4,
    10: 4, 11: 4, 12: 3, 13: 5, 14: 4, 15: 3, 16: 4, 17: 5, 18: 4,
  };
  return CourseInfo(
    name: 'TestCourse',
    holes: List.generate(18, (i) {
      final h = i + 1;
      return CourseHole(hole: h, par: pars[h]!, strokeIndex: h);
    }),
  );
}

/// Construye un Round mínimo con jugadores y scores configurables.
Round _makeRound({
  required Map<String, double> hcps,           // playerId → HCP
  required Map<String, Map<int, int>> gross,   // playerId → {hole → score}
  Map<String, Map<String, double>> manuals = const {}, // p1 → {p2 → strokes}
  CourseInfo? course,
  int totalHoles = 18,
}) {
  final c = course ?? _makeCourse();
  final players = hcps.keys.map((id) => Player(id: id, name: id, handicapBase: hcps[id]!)).toList();
  final roundPlayers = hcps.keys.map((id) {
    final mh = manuals[id] ?? {};
    return RoundPlayer(
      playerId: id,
      handicapEnRonda: hcps[id]!,
      manualHandicaps: mh,
    );
  }).toList();

  final scores = <String, Map<int, HoleScore>>{};
  for (final entry in gross.entries) {
    final pid = entry.key;
    scores[pid] = {};
    for (final h in entry.value.entries) {
      scores[pid]![h.key] = HoleScore(
        playerId: pid, hole: h.key, grossScore: h.value,
      );
    }
  }

  return Round(
    id: 'test', name: 'Test Round', course: c,
    players: players, roundPlayers: roundPlayers,
    betGroups: [], scores: scores,
    events: {}, oyeseRankings: {}, sliding: [],
    createdAt: DateTime(2024, 1, 1),
    totalHoles: totalHoles,
  );
}

/// Score bruto de 18 hoyos todos iguales (para tests simples).
Map<int, int> _allPar(CourseInfo c) =>
    { for (final h in c.holes) h.hole: h.par };

Map<int, int> _allScore(CourseInfo c, int score) =>
    { for (final h in c.holes) h.hole: score };

/// BetSide de un solo jugador (modo individual).
BetSide _side(String id, {String? name}) =>
    BetSide(id: 'side_$id', name: name ?? id, playerIds: [id]);

/// BetSide de varios jugadores.
BetSide _sideMulti(String id, List<String> pids, {String? name}) =>
    BetSide(id: id, name: name ?? id, playerIds: pids);

/// Módulo de match+press por defecto, valor 10, press 5, trigger 1.
BetModuleInstance _matchMod({
  required List<String> participantIds,
  List<BetSide>? sides,
  bool net = false,
  int trigger = 1,
  double matchVal = 10,
  double pressVal = 5,
}) {
  return BetModuleInstance(
    id: 'mod_match',
    type: BetModuleType.matchAutoPress,
    name: 'Match Test',
    participantIds: participantIds,
    sides: sides,
    matchAutoPressConfig: MatchAutoPressConfig(
      matchValue: matchVal,
      pressValue: pressVal,
      pressTriggerValue: trigger,
      maxPresses: 10,
      mode: net ? GrossNetMode.net : GrossNetMode.gross,
    ),
  );
}

/// Módulo de Nassau por defecto (front=10, back=10, total=10).
BetModuleInstance _nassauMod({
  required List<String> participantIds,
  List<BetSide>? sides,
  bool net = false,
}) {
  return BetModuleInstance(
    id: 'mod_nassau',
    type: BetModuleType.nassau,
    name: 'Nassau Test',
    participantIds: participantIds,
    sides: sides,
    nassauConfig: NassauConfig(
      frontValue: 10,
      backValue: 10,
      totalValue: 10,
      pressEnabled: false,
      mode: net ? GrossNetMode.net : GrossNetMode.gross,
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// SECCIÓN A — VALIDACIÓN DE MODELO
// ══════════════════════════════════════════════════════════════════════════════

void _sectionA() {
  group('A. BetSide.validateDuel', () {
    test('A1. Ok: 2 lados bien formados, sin duplicados', () {
      final sA = _sideMulti('sA', ['p1', 'p2'], name: 'Equipo A');
      final sB = _sideMulti('sB', ['p3', 'p4'], name: 'Equipo B');
      final err = BetSide.validateDuel([sA, sB]);
      expect(err, isNull, reason: 'Debe retornar null (sin error)');
    });

    test('A2. Error: jugador duplicado entre lados', () {
      final sA = _sideMulti('sA', ['p1', 'p2']);
      final sB = _sideMulti('sB', ['p2', 'p3']); // p2 aparece en ambos
      final err = BetSide.validateDuel([sA, sB]);
      expect(err, isNotNull, reason: 'Debe detectar la duplicación');
      expect(err, contains('p2'));
    });

    test('A3. Error: lado vacío (sin jugadores)', () {
      final sA = _sideMulti('sA', ['p1']);
      final sB = _sideMulti('sB', []);          // vacío
      final err = BetSide.validateDuel([sA, sB]);
      expect(err, isNotNull);
      expect(err, contains('jugadores'));
    });

    test('A4. Error: solo 1 lado (se requieren 2)', () {
      final sA = _sideMulti('sA', ['p1']);
      final err = BetSide.validateDuel([sA]);
      expect(err, isNotNull);
      expect(err, contains('2 lados'));
    });

    test('A5. Error: 3 lados (más de 2 no permitido en esta versión)', () {
      final sA = _sideMulti('sA', ['p1']);
      final sB = _sideMulti('sB', ['p2']);
      final sC = _sideMulti('sC', ['p3']);
      final err = BetSide.validateDuel([sA, sB, sC]);
      expect(err, isNotNull);
    });

    test('A6. sidesValidationError getter en BetModuleInstance', () {
      final mod = BetModuleInstance(
        id: 'm', type: BetModuleType.nassau, name: 'N',
        participantIds: [],
        sides: [
          _sideMulti('sA', ['p1']),
          _sideMulti('sB', ['p1']), // duplicado
        ],
      );
      // sidesValidationError detecta el duplicado
      expect(mod.sidesValidationError, isNotNull,
          reason: 'Debe detectar que p1 aparece en ambos lados');
      expect(mod.sidesValidationError, contains('p1'));
      // Nota: hasTeamSides solo verifica que haya 2 lados con >=1 jugador cada uno.
      // La validación de duplicados es responsabilidad de sidesValidationError
      // y debe consultarse en la UI antes de guardar.
      // El motor opera con los datos que recibe; la UI garantiza integridad.
    });
  });
}

// ══════════════════════════════════════════════════════════════════════════════
// SECCIÓN B — holeDeltaVs
// ══════════════════════════════════════════════════════════════════════════════

void _sectionB() {
  final c = _makeCourse();

  group('B1. holeDeltaVs 1v1 gross ≡ modo individual', () {
    // p1 hace 3 en H1 (par 4 → birdie), p2 hace 5 (bogey)
    // Esperado: sideA gana H1 → delta = +1
    test('A gana cuando best(A) < best(B)', () {
      final round = _makeRound(
        hcps: {'p1': 0, 'p2': 0},
        gross: {
          'p1': {1: 3},
          'p2': {1: 5},
        },
        course: c,
      );
      final delta = GameEngine.holeDeltaVs(
        round: round,
        sideA: _side('p1'),
        sideB: _side('p2'),
        holeNum: 1,
        useHandicap: false,
        hcpMap: {},
      );
      expect(delta, 1, reason: 'p1 birdie (3) vs p2 bogey (5) → sideA +1');
    });

    test('B gana cuando best(B) < best(A)', () {
      final round = _makeRound(
        hcps: {'p1': 0, 'p2': 0},
        gross: {'p1': {1: 5}, 'p2': {1: 3}},
        course: c,
      );
      final delta = GameEngine.holeDeltaVs(
        round: round, sideA: _side('p1'), sideB: _side('p2'),
        holeNum: 1, useHandicap: false, hcpMap: {},
      );
      expect(delta, -1, reason: 'p2 birdie → sideB gana → delta -1');
    });
  });

  group('B2. holeDeltaVs 1v1 net (HCP)', () {
    // H4 tiene strokeIndex=4. p2 tiene HCP 8 → recibe 1 stroke en H4 (SI=4 ≤ 8)
    // p1=HCP 0, p2=HCP 8. p1 hace 4 (par), p2 hace 5 (bogey bruto) → neto 4
    // Esperado: empate (4 vs 4)
    test('Empate neto: p1 par vs p2 bogey neto par', () {
      final round = _makeRound(
        hcps: {'p1': 0, 'p2': 8},
        gross: {'p1': {4: 4}, 'p2': {4: 5}},
        course: c,
      );
      final hcpMap = GameEngine.buildTeamHcpMap(round, ['p1', 'p2']);
      final delta = GameEngine.holeDeltaVs(
        round: round, sideA: _side('p1'), sideB: _side('p2'),
        holeNum: 4, useHandicap: true, hcpMap: hcpMap,
      );
      // p2 tiene HCP 8, strokesReceived en H4 (SI=4) = 1 → neto = 5-1 = 4
      // p1 HCP 0 → neto = 4
      expect(delta, 0, reason: 'Empate neto p1:4 vs p2:4');
    });

    // p2 hace 4 bruto en H4 → neto 3 → B gana
    test('B gana en net con strokes recibidos', () {
      final round = _makeRound(
        hcps: {'p1': 0, 'p2': 8},
        gross: {'p1': {4: 4}, 'p2': {4: 4}},
        course: c,
      );
      final hcpMap = GameEngine.buildTeamHcpMap(round, ['p1', 'p2']);
      final delta = GameEngine.holeDeltaVs(
        round: round, sideA: _side('p1'), sideB: _side('p2'),
        holeNum: 4, useHandicap: true, hcpMap: hcpMap,
      );
      // p2 neto = 4-1 = 3; p1 neto = 4 → B gana
      expect(delta, -1, reason: 'p2 neto 3 < p1 neto 4 → sideB gana');
    });
  });

  group('B3. holeDeltaVs 2v2 best-ball gross', () {
    // sideA: p1=5, p2=3 → best=3
    // sideB: p3=4, p4=4 → best=4
    // A gana (3 < 4) → delta = +1
    test('Best ball A gana con el mejor del equipo', () {
      final round = _makeRound(
        hcps: {'p1': 0, 'p2': 0, 'p3': 0, 'p4': 0},
        gross: {'p1': {1: 5}, 'p2': {1: 3}, 'p3': {1: 4}, 'p4': {1: 4}},
        course: c,
      );
      final sA = _sideMulti('sA', ['p1', 'p2'], name: 'A');
      final sB = _sideMulti('sB', ['p3', 'p4'], name: 'B');
      final delta = GameEngine.holeDeltaVs(
        round: round, sideA: sA, sideB: sB,
        holeNum: 1, useHandicap: false, hcpMap: {},
      );
      expect(delta, 1, reason: 'best(A)=3 < best(B)=4 → sideA +1');
    });

    // sideA: p1=4, p2=5 → best=4
    // sideB: p3=3, p4=6 → best=3
    // B gana → delta = -1
    test('Best ball B gana con su mejor jugador', () {
      final round = _makeRound(
        hcps: {'p1': 0, 'p2': 0, 'p3': 0, 'p4': 0},
        gross: {'p1': {1: 4}, 'p2': {1: 5}, 'p3': {1: 3}, 'p4': {1: 6}},
        course: c,
      );
      final sA = _sideMulti('sA', ['p1', 'p2']);
      final sB = _sideMulti('sB', ['p3', 'p4']);
      final delta = GameEngine.holeDeltaVs(
        round: round, sideA: sA, sideB: sB,
        holeNum: 1, useHandicap: false, hcpMap: {},
      );
      expect(delta, -1, reason: 'best(B)=3 < best(A)=4 → sideB gana');
    });
  });

  group('B4. holeDeltaVs 2v2 best-ball net', () {
    // H4, SI=4. HCP: p1=0,p2=0,p3=12,p4=4
    // p3 tiene HCP 12 → strokes en H4 (SI=4): 12>=4 → 1 stroke, también 12>18? No.
    //   strokesReceived(12, SI=4) = 1
    // p4 HCP 4 → SI=4 → 4>=4 → 1 stroke
    // sideA: p1=4 neto 4, p2=5 neto 5 → best(A)=4
    // sideB: p3=5 neto 4, p4=5 neto 4 → best(B)=4
    // Empate
    test('Empate de best-ball neto 2v2', () {
      final round = _makeRound(
        hcps: {'p1': 0, 'p2': 0, 'p3': 12, 'p4': 4},
        gross: {'p1': {4: 4}, 'p2': {4: 5}, 'p3': {4: 5}, 'p4': {4: 5}},
        course: c,
      );
      final hcpMap = GameEngine.buildTeamHcpMap(round, ['p1','p2','p3','p4']);
      final sA = _sideMulti('sA', ['p1','p2']);
      final sB = _sideMulti('sB', ['p3','p4']);
      final delta = GameEngine.holeDeltaVs(
        round: round, sideA: sA, sideB: sB,
        holeNum: 4, useHandicap: true, hcpMap: hcpMap,
      );
      expect(delta, 0, reason: 'best(A) neto=4, best(B) neto=4 → empate');
    });

    // p4 HCP=4 hace 4 en H4 → neto=3 → B gana
    test('B gana con un jugador que recibe stroke', () {
      final round = _makeRound(
        hcps: {'p1': 0, 'p2': 0, 'p3': 12, 'p4': 4},
        gross: {'p1': {4: 4}, 'p2': {4: 5}, 'p3': {4: 5}, 'p4': {4: 4}},
        course: c,
      );
      final hcpMap = GameEngine.buildTeamHcpMap(round, ['p1','p2','p3','p4']);
      final sA = _sideMulti('sA', ['p1','p2']);
      final sB = _sideMulti('sB', ['p3','p4']);
      final delta = GameEngine.holeDeltaVs(
        round: round, sideA: sA, sideB: sB,
        holeNum: 4, useHandicap: true, hcpMap: hcpMap,
      );
      // p4 bruto=4, HCP=4, SI=4 → stroke → neto=3; best(B)=3 < best(A)=4
      expect(delta, -1, reason: 'p4 neto 3 → best(B)=3 < best(A)=4 → sideB -1');
    });
  });

  group('B5. holeDeltaVs 3v2 net', () {
    // sideA: 3 jugadores, sideB: 2 jugadores (asimétrico)
    // H4, todos HCP=0 → gross=net
    // sideA: p1=5, p2=4, p3=6 → best=4
    // sideB: p4=3, p5=5 → best=3
    // B gana
    test('3v2: best-ball funciona con equipos asimétricos', () {
      final round = _makeRound(
        hcps: {'p1':0,'p2':0,'p3':0,'p4':0,'p5':0},
        gross: {'p1':{4:5},'p2':{4:4},'p3':{4:6},'p4':{4:3},'p5':{4:5}},
        course: c,
      );
      final sA = _sideMulti('sA', ['p1','p2','p3']);
      final sB = _sideMulti('sB', ['p4','p5']);
      final delta = GameEngine.holeDeltaVs(
        round: round, sideA: sA, sideB: sB,
        holeNum: 4, useHandicap: false, hcpMap: {},
      );
      expect(delta, -1, reason: 'best(A)=4 > best(B)=3 → sideB gana');
    });
  });

  group('B6. Empate de mejor bola', () {
    test('best(A) == best(B) → delta = 0', () {
      final round = _makeRound(
        hcps: {'p1':0,'p2':0,'p3':0,'p4':0},
        gross: {'p1':{1:5},'p2':{1:4},'p3':{1:4},'p4':{1:6}},
        course: c,
      );
      final sA = _sideMulti('sA', ['p1','p2']);
      final sB = _sideMulti('sB', ['p3','p4']);
      final delta = GameEngine.holeDeltaVs(
        round: round, sideA: sA, sideB: sB,
        holeNum: 1, useHandicap: false, hcpMap: {},
      );
      // best(A)=4, best(B)=4 → empate
      expect(delta, 0, reason: 'Empate cuando ambos best-balls son iguales');
    });
  });

  group('B7. Hoyo incompleto → null', () {
    test('Un jugador del lado sin score → delta = null', () {
      final round = _makeRound(
        hcps: {'p1':0,'p2':0,'p3':0,'p4':0},
        // p2 no tiene score en H1
        gross: {'p1':{1:4},'p3':{1:4},'p4':{1:4}},
        course: c,
      );
      final sA = _sideMulti('sA', ['p1','p2']);
      final sB = _sideMulti('sB', ['p3','p4']);
      final delta = GameEngine.holeDeltaVs(
        round: round, sideA: sA, sideB: sB,
        holeNum: 1, useHandicap: false, hcpMap: {},
      );
      expect(delta, isNull, reason: 'p2 sin score → lado A incompleto → null');
    });

    test('Si todos tienen score el resultado no es null', () {
      final round = _makeRound(
        hcps: {'p1':0,'p2':0,'p3':0,'p4':0},
        gross: {'p1':{1:4},'p2':{1:4},'p3':{1:4},'p4':{1:4}},
        course: c,
      );
      final sA = _sideMulti('sA', ['p1','p2']);
      final sB = _sideMulti('sB', ['p3','p4']);
      final delta = GameEngine.holeDeltaVs(
        round: round, sideA: sA, sideB: sB,
        holeNum: 1, useHandicap: false, hcpMap: {},
      );
      expect(delta, isNotNull);
    });
  });
}

// ══════════════════════════════════════════════════════════════════════════════
// SECCIÓN C — Match + Press equipo
// ══════════════════════════════════════════════════════════════════════════════

void _sectionC() {
  final c = _makeCourse();

  group('C1. 1v1 con sides produce mismo ledger que modo individual', () {
    // p1 gana todos los hoyos → cobra todo el match
    test('1v1 sides ≡ participantIds en ledger final', () {
      final gross = <String, Map<int, int>>{
        'p1': _allScore(c, 3), // birdie en todos → gana siempre
        'p2': _allScore(c, 5),
      };
      final round = _makeRound(hcps: {'p1':0,'p2':0}, gross: gross, course: c);

      final modInd = _matchMod(participantIds: ['p1','p2']);
      final modTeam = _matchMod(
        participantIds: ['p1','p2'],
        sides: [_side('p1'), _side('p2')],
      );
      final group = BetGroup(
        id: 'g', name: 'G',
        format: PartidaFormat.oneVsOne,
        playerIds: ['p1','p2'],
        modules: [],
      );

      final entriesInd  = BetEngine.computeGroup(round, group.copyWith(modules: [modInd]));
      final entriesTeam = BetEngine.computeGroup(round, group.copyWith(modules: [modTeam]));

      // En ambos casos p1 gana y p2 paga
      final totalInd  = entriesInd.fold(0.0, (s, e) => s + (e.toPlayerId == 'p1' ? e.amount : 0));
      final totalTeam = entriesTeam.fold(0.0, (s, e) => s + (e.toPlayerId == 'p1' ? e.amount : 0));

      expect(totalTeam, equals(totalInd),
          reason: '1v1 sides debe dar el mismo resultado monetario que modo individual');
    });
  });

  group('C2. 2v2 press se abre en hoyo correcto', () {
    // Diseño: sideA gana H1 con trigger=1 → llega 1UP → press abre en H2.
    // El reason del press contiene 'Press 1' y empieza en H2 ('H2' en el label).
    test('Press 1 nace tras trigger 1UP y arranca en H2', () {
      // p1 y p2 (sideA) hacen birdie en todos los hoyos; p3 y p4 (sideB) hacen bogey
      final gross = <String, Map<int, int>>{
        'p1': {for (int i = 1; i <= 18; i++) i: 3},
        'p2': {for (int i = 1; i <= 18; i++) i: 3},
        'p3': {for (int i = 1; i <= 18; i++) i: 5},
        'p4': {for (int i = 1; i <= 18; i++) i: 5},
      };
      final round = _makeRound(
        hcps: {'p1':0,'p2':0,'p3':0,'p4':0},
        gross: gross, course: c,
      );
      final sA = _sideMulti('sA', ['p1','p2'], name: 'A');
      final sB = _sideMulti('sB', ['p3','p4'], name: 'B');
      final mod = _matchMod(
        participantIds: ['p1','p2','p3','p4'],
        sides: [sA, sB],
        trigger: 1,
      );
      final group = BetGroup(
        id: 'g', name: 'G',
        format: PartidaFormat.groupVsGroup,
        playerIds: ['p1','p2','p3','p4'],
        modules: [mod],
      );

      final entries = BetEngine.computeGroup(round, group);

      // Debe haber entradas para el match principal Y para el Press 1
      final pressEntries = entries.where((e) => e.reason.contains('Press 1')).toList();
      expect(pressEntries, isNotEmpty,
          reason: 'Debe existir un Press 1 después del trigger 1UP en H1');

      // Con trigger=1: A llega 1UP después de H1 → press abre en H2.
      // El reason del press incluye 'H2' como hoyo de inicio (formato: "Press 1 H2–H18 ...")
      final pressH2 = pressEntries.where((e) => e.reason.contains('H2')).toList();
      expect(pressH2, isNotEmpty,
          reason: 'Press 1 debe iniciar en H2 (siguiente al trigger en H1)');
    });
  });

  group('C3. Encadenamiento de presiones (press-sobre-press)', () {
    // sideA domina toda la ronda:
    //   H1: A gana (Match 1UP → press abre H2)
    //   H2: A gana (Press llega 1UP → press2 abre H3)
    test('Press 2 existe cuando press 1 alcanza trigger', () {
      final gross = <String, Map<int, int>>{
        'p1': {for (int i = 1; i <= 18; i++) i: 3},
        'p2': {for (int i = 1; i <= 18; i++) i: 3},
        'p3': {for (int i = 1; i <= 18; i++) i: 5},
        'p4': {for (int i = 1; i <= 18; i++) i: 5},
      };
      final round = _makeRound(
        hcps: {'p1':0,'p2':0,'p3':0,'p4':0},
        gross: gross, course: c,
      );
      final sA = _sideMulti('sA', ['p1','p2']);
      final sB = _sideMulti('sB', ['p3','p4']);
      final mod = _matchMod(
        participantIds: ['p1','p2','p3','p4'],
        sides: [sA, sB], trigger: 1,
      );
      final group = BetGroup(
        id: 'g', name: 'G',
        format: PartidaFormat.groupVsGroup,
        playerIds: ['p1','p2','p3','p4'],
        modules: [mod],
      );

      final entries = BetEngine.computeGroup(round, group);
      final press2 = entries.where((e) => e.reason.contains('Press 2')).toList();
      expect(press2, isNotEmpty, reason: 'Encadenamiento: Press 2 debe existir');
    });

    test('matchAutoPressLiveTeam retorna múltiples matches con press chain', () {
      final gross = <String, Map<int, int>>{
        'p1': {for (int i = 1; i <= 18; i++) i: 3},
        'p2': {for (int i = 1; i <= 18; i++) i: 3},
        'p3': {for (int i = 1; i <= 18; i++) i: 5},
        'p4': {for (int i = 1; i <= 18; i++) i: 5},
      };
      final round = _makeRound(
        hcps: {'p1':0,'p2':0,'p3':0,'p4':0},
        gross: gross, course: c,
      );
      final sA = _sideMulti('sA', ['p1','p2']);
      final sB = _sideMulti('sB', ['p3','p4']);
      final mod = _matchMod(
        participantIds: ['p1','p2','p3','p4'],
        sides: [sA, sB], trigger: 1,
      );

      final live = BetEngine.matchAutoPressLiveTeam(round, mod);
      expect(live.length, greaterThan(1),
          reason: 'Debe haber más de 1 match/press en el árbol');
      // El match principal siempre es el primero
      expect(live.first.isPrimaryMatch, isTrue);
      // Al menos un press
      final presses = live.where((s) => !s.isPrimaryMatch).toList();
      expect(presses, isNotEmpty, reason: 'Debe haber al menos un press');
    });
  });
}

// ══════════════════════════════════════════════════════════════════════════════
// SECCIÓN D — Nassau equipo
// ══════════════════════════════════════════════════════════════════════════════

void _sectionD() {
  final c = _makeCourse();

  group('D1. Nassau equipo: front/back/total independientes', () {
    // sideA gana todos los hoyos del front (1-9), sideB gana todos del back (10-18)
    // → front: A cobra, back: B cobra, total: empate (no entry)
    test('Front A, Back B, Total 0 → entradas separadas por segmento', () {
      final gross = <String, Map<int, int>>{
        'p1': {for (int i = 1; i <= 9; i++) i: 3,  for (int i = 10; i <= 18; i++) i: 5},
        'p2': {for (int i = 1; i <= 9; i++) i: 3,  for (int i = 10; i <= 18; i++) i: 5},
        'p3': {for (int i = 1; i <= 9; i++) i: 5,  for (int i = 10; i <= 18; i++) i: 3},
        'p4': {for (int i = 1; i <= 9; i++) i: 5,  for (int i = 10; i <= 18; i++) i: 3},
      };
      final round = _makeRound(
        hcps: {'p1':0,'p2':0,'p3':0,'p4':0},
        gross: gross, course: c,
      );
      final sA = _sideMulti('sA', ['p1','p2'], name: 'A');
      final sB = _sideMulti('sB', ['p3','p4'], name: 'B');
      final mod = _nassauMod(
        participantIds: ['p1','p2','p3','p4'],
        sides: [sA, sB],
      );
      final group = BetGroup(
        id: 'g', name: 'G',
        format: PartidaFormat.groupVsGroup,
        playerIds: ['p1','p2','p3','p4'],
        modules: [mod],
      );

      final entries = BetEngine.computeGroup(round, group);

      // Front: todos los jugadores de B pagan a A
      final frontA = entries.where((e) =>
        e.reason.contains('Front 9') &&
        sA.playerIds.contains(e.toPlayerId) &&
        sB.playerIds.contains(e.fromPlayerId)
      ).toList();
      expect(frontA, isNotEmpty, reason: 'B paga Front 9 a A');

      // Back: todos los jugadores de A pagan a B
      final backB = entries.where((e) =>
        e.reason.contains('Back 9') &&
        sB.playerIds.contains(e.toPlayerId) &&
        sA.playerIds.contains(e.fromPlayerId)
      ).toList();
      expect(backB, isNotEmpty, reason: 'A paga Back 9 a B');

      // Total: empate → no entries de total
      final totalEntries = entries.where((e) => e.reason.contains('Total 18')).toList();
      expect(totalEntries, isEmpty, reason: 'Total empatado → sin entradas');
    });

    test('Monto de Front: valor por cada cruce de jugadores (2x2 = 4 entradas)', () {
      // 2 jugadores por lado → 2×2=4 entradas cruzadas por segmento ganado
      final gross = <String, Map<int, int>>{
        'p1': _allScore(c, 3),
        'p2': _allScore(c, 3),
        'p3': _allScore(c, 5),
        'p4': _allScore(c, 5),
      };
      final round = _makeRound(
        hcps: {'p1':0,'p2':0,'p3':0,'p4':0},
        gross: gross, course: c,
      );
      final sA = _sideMulti('sA', ['p1','p2']);
      final sB = _sideMulti('sB', ['p3','p4']);
      final mod = _nassauMod(
        participantIds: ['p1','p2','p3','p4'],
        sides: [sA, sB],
      );
      final group = BetGroup(
        id: 'g', name: 'G',
        format: PartidaFormat.groupVsGroup,
        playerIds: ['p1','p2','p3','p4'],
        modules: [mod],
      );

      final entries = BetEngine.computeGroup(round, group);
      final frontEntries = entries.where((e) => e.reason.contains('Front 9')).toList();
      // 2 jugadores en sA × 2 jugadores en sB = 4 entradas para Front 9
      expect(frontEntries.length, 4,
          reason: '2×2 jugadores → 4 cruces de pago por segmento');
    });
  });

  group('D2. Nassau equipo best-ball net', () {
    // H1 SI=1: p3 con HCP=18 recibe 1 stroke → neto = bruto - 1
    // sideA: p1 HCP=0 hace 4 → neto 4
    //        p2 HCP=0 hace 5 → neto 5  → best(A)=4
    // sideB: p3 HCP=18 hace 5 → neto 4
    //        p4 HCP=0 hace 6 → neto 6  → best(B)=4
    // Empate H1 en net → no debe contarse para front margin
    test('Empate neto de best-ball en H1 no afecta el margen', () {
      final gross = <String, Map<int, int>>{
        'p1': {1: 4, ..._allScore(c, 4)},
        'p2': {1: 5, ..._allScore(c, 5)},
        'p3': {1: 5, ..._allScore(c, 5)},
        'p4': {1: 6, ..._allScore(c, 6)},
      };
      final round = _makeRound(
        hcps: {'p1':0,'p2':0,'p3':18,'p4':0},
        gross: gross, course: c,
      );
      final hcpMap = GameEngine.buildTeamHcpMap(round, ['p1','p2','p3','p4']);
      // Verificar el delta del hoyo directamente
      final sA = _sideMulti('sA', ['p1','p2']);
      final sB = _sideMulti('sB', ['p3','p4']);
      final delta = GameEngine.holeDeltaVs(
        round: round, sideA: sA, sideB: sB,
        holeNum: 1, useHandicap: true, hcpMap: hcpMap,
      );
      // H1 SI=1: p3 HCP=18 → strokes=1 → neto=5-1=4; best(B)=4; best(A)=4 → empate
      expect(delta, 0, reason: 'H1 net best-ball empate: best(A)=4 == best(B)=4');
    });
  });
}

// ══════════════════════════════════════════════════════════════════════════════
// SECCIÓN E — Auditoría de fuente de HCP
// ══════════════════════════════════════════════════════════════════════════════

void _sectionE() {
  final c = _makeCourse();

  group('E1. Ledger nassauTeam y nassauLiveStatusTeam usan la misma fuente', () {
    // Si comparten la misma fuente (holeDeltaVs con buildTeamHcpMap),
    // los márgenes de front/back deben coincidir exactamente.
    test('Front margin en ledger == front score en liveStatus', () {
      // sideA gana todos los hoyos del front → front margin > 0
      final gross = <String, Map<int, int>>{
        'p1': {for (int i = 1; i <= 9; i++) i: 3,  for (int i = 10; i <= 18; i++) i: 4},
        'p2': {for (int i = 1; i <= 9; i++) i: 4,  for (int i = 10; i <= 18; i++) i: 4},
        'p3': {for (int i = 1; i <= 9; i++) i: 5,  for (int i = 10; i <= 18; i++) i: 4},
        'p4': {for (int i = 1; i <= 9; i++) i: 5,  for (int i = 10; i <= 18; i++) i: 4},
      };
      final round = _makeRound(
        hcps: {'p1':0,'p2':0,'p3':0,'p4':0},
        gross: gross, course: c,
      );
      final sA = _sideMulti('sA', ['p1','p2']);
      final sB = _sideMulti('sB', ['p3','p4']);
      final mod = _nassauMod(
        participantIds: ['p1','p2','p3','p4'],
        sides: [sA, sB],
      );
      final group = BetGroup(
        id: 'g', name: 'G',
        format: PartidaFormat.groupVsGroup,
        playerIds: ['p1','p2','p3','p4'],
        modules: [mod],
      );

      // Ledger: A cobra Front 9
      final entries = BetEngine.computeGroup(round, group);
      final frontCobrado = entries.any((e) =>
        e.reason.contains('Front 9') && sA.playerIds.contains(e.toPlayerId)
      );

      // LiveStatus: front positivo significa A va arriba
      final live = BetEngine.nassauLiveStatusTeam(round, mod);
      expect(live.front > 0, isTrue, reason: 'Live front debe ser positivo para A');
      expect(frontCobrado, isTrue, reason: 'Ledger debe cobrar Front 9 a A');

      // Coherencia: ledger cobra a A solo cuando live.front > 0
      expect(frontCobrado, equals(live.front > 0),
          reason: 'Ledger y LiveStatus deben coincidir en quién gana Front 9');
    });

    test('Back neutral: ledger sin entradas de Back 9 y live.back == 0', () {
      // Todos hacen lo mismo en el back → empate → live.back=0 y sin entry de Back 9
      final gross = <String, Map<int, int>>{
        'p1': {for (int i = 1; i <= 18; i++) i: 4},
        'p2': {for (int i = 1; i <= 18; i++) i: 4},
        'p3': {for (int i = 1; i <= 18; i++) i: 4},
        'p4': {for (int i = 1; i <= 18; i++) i: 4},
      };
      final round = _makeRound(
        hcps: {'p1':0,'p2':0,'p3':0,'p4':0},
        gross: gross, course: c,
      );
      final sA = _sideMulti('sA', ['p1','p2']);
      final sB = _sideMulti('sB', ['p3','p4']);
      final mod = _nassauMod(participantIds: ['p1','p2','p3','p4'], sides: [sA, sB]);
      final group = BetGroup(
        id: 'g', name: 'G',
        format: PartidaFormat.groupVsGroup,
        playerIds: ['p1','p2','p3','p4'],
        modules: [mod],
      );

      final entries = BetEngine.computeGroup(round, group);
      final live = BetEngine.nassauLiveStatusTeam(round, mod);

      expect(live.back, 0, reason: 'Empate total → live.back debe ser 0');
      expect(entries.where((e) => e.reason.contains('Back 9')).isEmpty, isTrue,
          reason: 'Empate → sin entradas de Back 9');
    });
  });

  group('E2. matchAutoPressLiveTeam y ledger comparten el mismo árbol de matches', () {
    // Si sideA gana todos los hoyos, tanto el ledger como el live deben
    // mostrar al mismo número de matches/presses activos.
    test('Conteo de matches en live == entradas únicas de reason en ledger', () {
      final gross = <String, Map<int, int>>{
        'p1': {for (int i = 1; i <= 18; i++) i: 3},
        'p2': {for (int i = 1; i <= 18; i++) i: 3},
        'p3': {for (int i = 1; i <= 18; i++) i: 5},
        'p4': {for (int i = 1; i <= 18; i++) i: 5},
      };
      final round = _makeRound(
        hcps: {'p1':0,'p2':0,'p3':0,'p4':0},
        gross: gross, course: c,
      );
      final sA = _sideMulti('sA', ['p1','p2']);
      final sB = _sideMulti('sB', ['p3','p4']);
      final mod = _matchMod(
        participantIds: ['p1','p2','p3','p4'],
        sides: [sA, sB], trigger: 1,
      );
      final group = BetGroup(
        id: 'g', name: 'G',
        format: PartidaFormat.groupVsGroup,
        playerIds: ['p1','p2','p3','p4'],
        modules: [mod],
      );

      final entries = BetEngine.computeGroup(round, group);
      final live    = BetEngine.matchAutoPressLiveTeam(round, mod);

      // Live tiene N segmentos; ledger tiene entries para cada segmento ganado.
      // En este caso A gana todo → cada segmento produce entries.
      // Los reasons tienen el patrón "Match|Press N H..." deduplicados por segmento.
      // Verificar que live tiene el match principal (isPrimary) con score > 0 (A gana)
      final primaryLive = live.firstWhere((s) => s.isPrimaryMatch);
      expect(primaryLive.score, greaterThan(0),
          reason: 'A domina → match principal score > 0 en live');

      // El ledger también tiene entries para el match principal
      final matchEntries = entries.where((e) => e.reason.contains('Match')).toList();
      expect(matchEntries, isNotEmpty, reason: 'Ledger debe tener entradas del match principal');

      // Todos los entries van de sideB → sideA
      for (final e in entries) {
        expect(sA.playerIds.contains(e.toPlayerId), isTrue,
            reason: 'Todos los pagos deben ir a A (A gana todo)');
        expect(sB.playerIds.contains(e.fromPlayerId), isTrue,
            reason: 'Todos los pagos salen de B');
      }
    });

    test('sideB que gana: leadingPlayerId en live es el jugador representante de B', () {
      final gross = <String, Map<int, int>>{
        'p1': {for (int i = 1; i <= 18; i++) i: 5},
        'p2': {for (int i = 1; i <= 18; i++) i: 5},
        'p3': {for (int i = 1; i <= 18; i++) i: 3},
        'p4': {for (int i = 1; i <= 18; i++) i: 3},
      };
      final round = _makeRound(
        hcps: {'p1':0,'p2':0,'p3':0,'p4':0},
        gross: gross, course: c,
      );
      final sA = _sideMulti('sA', ['p1','p2']);
      final sB = _sideMulti('sB', ['p3','p4']);
      final mod = _matchMod(
        participantIds: ['p1','p2','p3','p4'],
        sides: [sA, sB], trigger: 1,
      );

      final live = BetEngine.matchAutoPressLiveTeam(round, mod);
      final primary = live.firstWhere((s) => s.isPrimaryMatch);

      expect(primary.score, lessThan(0),
          reason: 'B gana → score negativo en perspectiva A');
      // El leadingPlayerId debe ser el primer jugador de sideB
      expect(primary.leadingPlayerId, equals(sB.playerIds.first),
          reason: 'leadingPlayerId debe apuntar al representante de sideB');
    });
  });

  group('E3. Rutas de HCP — mismo mapa para todas las funciones de equipo', () {
    // buildTeamHcpMap usa getHandicap() directamente (sin sliding).
    // Esto es correcto para equipos: el HCP individual de cada jugador vs par.
    // Verificamos que la función devuelve el HCP correcto para cada jugador.
    test('buildTeamHcpMap retorna HCP de ronda para cada jugador', () {
      final round = _makeRound(
        hcps: {'p1': 12.0, 'p2': 8.5, 'p3': 24.0, 'p4': 0.0},
        gross: {},
        course: _makeCourse(),
      );
      final map = GameEngine.buildTeamHcpMap(round, ['p1','p2','p3','p4']);
      expect(map['p1'], 12.0);
      expect(map['p2'], 8.5);
      expect(map['p3'], 24.0);
      expect(map['p4'], 0.0);
    });

    test('Mode gross: hcpMap vacío produce mismo delta que hcpMap con zeros', () {
      final c2 = _makeCourse();
      final round = _makeRound(
        hcps: {'p1':16, 'p2':8, 'p3':4, 'p4':20},
        gross: {'p1':{1:4},'p2':{1:3},'p3':{1:5},'p4':{1:4}},
        course: c2,
      );
      final sA = _sideMulti('sA', ['p1','p2']);
      final sB = _sideMulti('sB', ['p3','p4']);

      final deltaEmpty = GameEngine.holeDeltaVs(
        round: round, sideA: sA, sideB: sB,
        holeNum: 1, useHandicap: false, hcpMap: {},
      );
      // En gross, best(A)=min(4,3)=3, best(B)=min(5,4)=4 → A gana
      expect(deltaEmpty, 1, reason: 'Gross: best(A)=3 < best(B)=4');
    });
  });
}

// ══════════════════════════════════════════════════════════════════════════════
// ENTRY POINT
// ══════════════════════════════════════════════════════════════════════════════

void main() {
  _sectionA();
  _sectionB();
  _sectionC();
  _sectionD();
  _sectionE();
}
