// ignore_for_file: avoid_print
// ─────────────────────────────────────────────────────────────────────────────
// Tests de Nassau con presiones (usando BetModuleType.nassau + pressEnabled:true)
// Actualizado para usar NassauConfig en lugar del tipo nassauPress obsoleto.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';

BetModuleInstance _nassauPressMod(List<String> pids, {
  double frontValue = 50,
  double backValue  = 50,
  double totalValue = 100,
  double frontPressValue = 25,
  double backPressValue  = 25,
  int    trigger = 2,
  GrossNetMode mode = GrossNetMode.gross,
}) => BetModuleInstance(
  id: 'np1',
  type: BetModuleType.nassau,
  name: 'Nassau con Press',
  participantIds: pids,
  nassauConfig: NassauConfig(
    frontValue:      frontValue,
    backValue:       backValue,
    totalValue:      totalValue,
    frontPressValue: frontPressValue,
    backPressValue:  backPressValue,
    pressEnabled:    true,
    autoPressTrigger: trigger,
    mode:            mode,
  ),
);

void main() {
  test('nassauPress genera entries cuando hay scores (front start)', () {
    final p1 = Player(id: 'p1', name: 'Carlos', handicapBase: 10, colorIndex: 0);
    final p2 = Player(id: 'p2', name: 'Rafa',   handicapBase: 10, colorIndex: 1);

    final mod = _nassauPressMod(['p1', 'p2']);

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

    // p1 gana 3 hoyos → F9 +3 → p2 paga a p1 $50
    final nassauEntries = entries.where((e) => e.betType == BetModuleType.nassau).toList();
    expect(nassauEntries.isNotEmpty, true,
        reason: 'Debe haber al menos 1 entry de nassau (con press)');
    expect(breakdown[BetModuleType.nassau], greaterThan(0),
        reason: 'p1 ganó F9 → debe tener balance positivo');
  });

  // ── Caso real reportado: CAM vs CAV, F9, 2 strokes (CAV da 2 a CAM) ──────
  // Scores netos F9:
  //   H1 CAM, H2 CAM, H3 CAV, H4 CAM (stroke), H5 CAV,
  //   H6 CAV, H7 CAV, H8 CAV, H9 AS
  // → F9 = CAV +2 (correcto)
  // → Press H3 debería ser CAV ganando (CAV dominó desde H3)
  // → Press H7 debería ser CAV ganando (CAV ganó H7, H8, H9=AS)
  // → Press H9 AS
  //
  // BUG PREVIO: history normalizado incorrectamente (doble inversión) →
  //   press.score con signo invertido → UI mostraba CAM +1 en vez de CAV +1.
  test('nassauPressLiveStatus - presiones con signo correcto (caso real CAM vs CAV F9)', () {
    // CAM = p1 (viewer), CAV = p2; CAV da 2 strokes a CAM
    final cam = Player(id: 'cam', name: 'CAM', handicapBase: 14, colorIndex: 0);
    final cav = Player(id: 'cav', name: 'CAV', handicapBase: 12, colorIndex: 1);

    // strokeIndex estándar de 18 hoyos; el SI=1 está en H4 → CAM recibe stroke ahí
    final holes = List.generate(18, (i) => CourseHole(
      hole: i + 1, par: 4,
      strokeIndex: [5, 11, 15, 1, 9, 17, 3, 13, 7, 6, 2, 18, 8, 4, 16, 10, 12, 14][i],
    ));
    final course = CourseInfo(name: 'Test', holes: holes);

    // Scores brutos del reporte:
    // H1: CAV=6  CAM=5  → CAM gana neto
    // H2: CAV=11 CAM=8  → CAM gana neto
    // H3: CAV=3  CAM=4  → CAV gana
    // H4: CAV=6  CAM=6  → CAM gana neto (stroke en H4, SI=1, diff=2 → 1 stroke aquí)
    // H5: CAV=4  CAM=5  → CAV gana
    // H6: CAV=7  CAM=8  → CAV gana
    // H7: CAV=5  CAM=7  → CAV gana
    // H8: CAV=5  CAM=6  → CAV gana
    // H9: CAV=6  CAM=6  → AS
    final scoresCAV = <int, HoleScore>{
      1: HoleScore(playerId: 'cav', hole: 1,  grossScore: 6),
      2: HoleScore(playerId: 'cav', hole: 2,  grossScore: 11),
      3: HoleScore(playerId: 'cav', hole: 3,  grossScore: 3),
      4: HoleScore(playerId: 'cav', hole: 4,  grossScore: 6),
      5: HoleScore(playerId: 'cav', hole: 5,  grossScore: 4),
      6: HoleScore(playerId: 'cav', hole: 6,  grossScore: 7),
      7: HoleScore(playerId: 'cav', hole: 7,  grossScore: 5),
      8: HoleScore(playerId: 'cav', hole: 8,  grossScore: 5),
      9: HoleScore(playerId: 'cav', hole: 9,  grossScore: 6),
    };
    final scoresCAM = <int, HoleScore>{
      1: HoleScore(playerId: 'cam', hole: 1,  grossScore: 5),
      2: HoleScore(playerId: 'cam', hole: 2,  grossScore: 8),
      3: HoleScore(playerId: 'cam', hole: 3,  grossScore: 4),
      4: HoleScore(playerId: 'cam', hole: 4,  grossScore: 6),
      5: HoleScore(playerId: 'cam', hole: 5,  grossScore: 5),
      6: HoleScore(playerId: 'cam', hole: 6,  grossScore: 8),
      7: HoleScore(playerId: 'cam', hole: 7,  grossScore: 7),
      8: HoleScore(playerId: 'cam', hole: 8,  grossScore: 6),
      9: HoleScore(playerId: 'cam', hole: 9,  grossScore: 6),
    };

    final mod = _nassauPressMod(
      ['cam', 'cav'],
      frontValue: 50, backValue: 50, totalValue: 100,
      frontPressValue: 50, backPressValue: 50,
      trigger: 2,
      mode: GrossNetMode.net,
    );

    final group = BetGroup(
      id: 'g1', name: 'Test', format: PartidaFormat.allInOnePot,
      playerIds: ['cam', 'cav'],
      modules: [mod],
    );

    final round = Round(
      id: 'r1', name: 'Test CAM vs CAV F9', course: course,
      players: [cam, cav],
      roundPlayers: [
        RoundPlayer(playerId: 'cam', handicapEnRonda: 14),
        RoundPlayer(playerId: 'cav', handicapEnRonda: 12),
      ],
      betGroups: [group],
      scores: {'cam': scoresCAM, 'cav': scoresCAV},
      events: {'cam': {}, 'cav': {}},
      oyeseRankings: {}, sliding: [],
      createdAt: DateTime.now(),
      startingNine: StartingNine.front,
      totalHoles: 9,
    );

    // ── nassauLiveStatus (sin press) ──────────────────────────────────────
    final liveStatus = BetEngine.nassauLiveStatus(round, 'cam', 'cav', mod);
    print('Nassau F9 front=${liveStatus.front} (esperado -2 = CAV +2UP desde perspectiva cam)');
    // Desde perspectiva cam=p1: CAV gana → front debe ser negativo
    expect(liveStatus.front, -2,
        reason: 'F9: CAV gana 2UP → front=-2 desde perspectiva de cam=p1');

    // ── nassauPressLiveStatus ─────────────────────────────────────────────
    final st = BetEngine.nassauPressLiveStatus(round, 'cam', 'cav', mod);
    print('nassauPressLiveStatus front=${st.front}');
    print('frontPresses count=${st.frontPresses.length}');
    for (final p in st.frontPresses) {
      print('  press H${p.startHole}: score=${p.score} loser=${p.loser} isOpen=${p.isOpen}');
    }

    // F9 principal: CAV +2UP desde perspectiva cam=p1 → front=-2
    expect(st.front, -2,
        reason: 'F9: CAV +2UP → front=-2 (perspectiva cam=p1)');

    // Debe haber 3 presiones (H3, H7, H9)
    expect(st.frontPresses.length, 3,
        reason: 'Debe haber 3 presiones en F9 con trigger=2 y estos scores');

    // Press H3: CAV ganó H3-H6 vs CAM→ score debe ser negativo (CAV arriba)
    final pressH3 = st.frontPresses.firstWhere((p) => p.startHole == 3);
    print('Press H3 score=${pressH3.score} (esperado <0 = CAV arriba)');
    expect(pressH3.score, isNegative,
        reason: 'Press H3: CAV domina H3→H6 → score negativo desde perspectiva cam=p1');
    // loser = jugador que iba PERDIENDO y dispara la press.
    // Cuando CAM iba +2UP al terminar H2, CAV iba -2DOWN → CAV es el loser/presionador.
    expect(pressH3.loser, 'cav',
        reason: 'Loser de press H3 es cav (quien iba -2DOWN al disparo, CAM iba +2UP)');

    // Press H7: CAV ganó H7,H8; H9 AS → score negativo (CAV arriba)
    final pressH7 = st.frontPresses.firstWhere((p) => p.startHole == 7);
    print('Press H7 score=${pressH7.score} (esperado <0 = CAV arriba)');
    expect(pressH7.score, isNegative,
        reason: 'Press H7: CAV ganó H7+H8, H9=AS → score negativo desde perspectiva cam=p1');
    // Al terminar H6, CAM fue a 0 (from +2) → CAV recuperó y CAM cayó -2 relativo → cam es loser
    expect(pressH7.loser, 'cam',
        reason: 'Loser de press H7 es cam (quien estaba -2DOWN relativo al disparar desde H6)');

    // Press H9: AS (solo H9 disponible, resultado empate)
    final pressH9 = st.frontPresses.firstWhere((p) => p.startHole == 9);
    print('Press H9 score=${pressH9.score} (esperado 0 = AS)');
    expect(pressH9.score, 0,
        reason: 'Press H9: H9 fue AS → score=0');
  });

  test('nassauPressLiveStatus - p1IsBase=true (p1 da strokes, p2 recibe) no invierte presiones', () {
    // Simétrico: ahora p1 DA strokes a p2 → p1IsBase=true
    // Las presiones deben reportar el mismo resultado sin inversión
    final giver   = Player(id: 'giver',   name: 'Giver',   handicapBase: 10, colorIndex: 0);
    final recvr   = Player(id: 'recvr',   name: 'Recvr',   handicapBase: 14, colorIndex: 1);

    final holes = List.generate(18, (i) => CourseHole(
      hole: i + 1, par: 4,
      strokeIndex: [5, 11, 15, 1, 9, 17, 3, 13, 7, 6, 2, 18, 8, 4, 16, 10, 12, 14][i],
    ));
    final course = CourseInfo(name: 'Test', holes: holes);

    // giver gana H1,H2,H3,H4 → giver +4 en F9
    // trigger=2 → recvr dispara press en H2 (recvr va -2), press H3
    // En la press H3 giver también domina → press score debería ser positivo (giver=p1 arriba)
    final scoresGiver = <int, HoleScore>{
      for (int h = 1; h <= 9; h++)
        h: HoleScore(playerId: 'giver', hole: h, grossScore: h <= 4 ? 3 : 5),
    };
    final scoresRecvr = <int, HoleScore>{
      for (int h = 1; h <= 9; h++)
        h: HoleScore(playerId: 'recvr', hole: h, grossScore: 5),
    };

    final mod = _nassauPressMod(
      ['giver', 'recvr'],
      frontValue: 50, backValue: 50, totalValue: 100,
      frontPressValue: 50, backPressValue: 50,
      trigger: 2,
      mode: GrossNetMode.net,
    );

    final group = BetGroup(
      id: 'g1', name: 'Test', format: PartidaFormat.allInOnePot,
      playerIds: ['giver', 'recvr'],
      modules: [mod],
    );

    final round = Round(
      id: 'r1', name: 'Test giver vs recvr', course: course,
      players: [giver, recvr],
      roundPlayers: [
        RoundPlayer(playerId: 'giver', handicapEnRonda: 10),
        RoundPlayer(playerId: 'recvr', handicapEnRonda: 14),
      ],
      betGroups: [group],
      scores: {'giver': scoresGiver, 'recvr': scoresRecvr},
      events: {'giver': {}, 'recvr': {}},
      oyeseRankings: {}, sliding: [],
      createdAt: DateTime.now(),
      startingNine: StartingNine.front,
      totalHoles: 9,
    );

    final st = BetEngine.nassauPressLiveStatus(round, 'giver', 'recvr', mod);
    print('giver p1IsBase test: front=${st.front}, presses=${st.frontPresses.length}');
    for (final p in st.frontPresses) {
      print('  press H${p.startHole}: score=${p.score} loser=${p.loser}');
    }

    // giver domina → front debe ser positivo
    expect(st.front, isPositive,
        reason: 'giver (p1) domina F9 → front positivo');

    // La press H3 (recvr iba -2DOWN) → loser=recvr
    // La press H5 puede ser ganada por recvr si gana hoyos dentro del segmento
    final pressH3b = st.frontPresses.firstWhere((p) => p.startHole == 3);
    expect(pressH3b.loser, 'recvr',
        reason: 'Loser de press H3 es recvr (giver estaba +2UP, recvr iba perdiendo)');
    // Verificar que el front es positivo (giver=p1 domina)
    expect(st.front, isPositive,
        reason: 'giver (p1) domina F9 → front positivo');
  });

  test('nassauPressLiveStatus - par parejo (sin strokes) detecta presiones correctamente', () {
    final alpha = Player(id: 'alpha', name: 'Alpha', handicapBase: 10, colorIndex: 0);
    final beta  = Player(id: 'beta',  name: 'Beta',  handicapBase: 10, colorIndex: 1);

    final holes = List.generate(18, (i) => CourseHole(
      hole: i + 1, par: 4,
      strokeIndex: [5, 11, 15, 1, 9, 17, 3, 13, 7, 6, 2, 18, 8, 4, 16, 10, 12, 14][i],
    ));
    final course = CourseInfo(name: 'Test', holes: holes);

    // alpha gana H1, H2 → alpha +2 al trigger, press en H3
    // H3-H9 alpha gana H3, H4; beta gana H5, H6; H7-H9 empate
    // press H3: alpha +2 dentro de la press → score positivo
    final scoresAlpha = <int, HoleScore>{
      1: HoleScore(playerId: 'alpha', hole: 1, grossScore: 3),
      2: HoleScore(playerId: 'alpha', hole: 2, grossScore: 3),
      3: HoleScore(playerId: 'alpha', hole: 3, grossScore: 3),
      4: HoleScore(playerId: 'alpha', hole: 4, grossScore: 3),
      5: HoleScore(playerId: 'alpha', hole: 5, grossScore: 5),
      6: HoleScore(playerId: 'alpha', hole: 6, grossScore: 5),
      7: HoleScore(playerId: 'alpha', hole: 7, grossScore: 4),
      8: HoleScore(playerId: 'alpha', hole: 8, grossScore: 4),
      9: HoleScore(playerId: 'alpha', hole: 9, grossScore: 4),
    };
    final scoresBeta = <int, HoleScore>{
      for (int h = 1; h <= 9; h++)
        h: HoleScore(playerId: 'beta', hole: h, grossScore: 4),
    };

    final mod = _nassauPressMod(
      ['alpha', 'beta'],
      frontValue: 50, backValue: 50, totalValue: 100,
      frontPressValue: 50, backPressValue: 50,
      trigger: 2,
      mode: GrossNetMode.gross,
    );

    final group = BetGroup(
      id: 'g1', name: 'Test', format: PartidaFormat.allInOnePot,
      playerIds: ['alpha', 'beta'],
      modules: [mod],
    );

    final round = Round(
      id: 'r1', name: 'Test alpha vs beta', course: course,
      players: [alpha, beta],
      roundPlayers: [
        RoundPlayer(playerId: 'alpha', handicapEnRonda: 10),
        RoundPlayer(playerId: 'beta',  handicapEnRonda: 10),
      ],
      betGroups: [group],
      scores: {'alpha': scoresAlpha, 'beta': scoresBeta},
      events: {'alpha': {}, 'beta': {}},
      oyeseRankings: {}, sliding: [],
      createdAt: DateTime.now(),
      startingNine: StartingNine.front,
      totalHoles: 9,
    );

    final st = BetEngine.nassauPressLiveStatus(round, 'alpha', 'beta', mod);
    print('Parejo test: front=${st.front}, presses=${st.frontPresses.length}');
    for (final p in st.frontPresses) {
      print('  press H${p.startHole}: score=${p.score} loser=${p.loser}');
    }

    // alpha gana H1,H2,H3,H4; beta gana H5,H6; H7-H9 AS → front = +4-2=+2
    expect(st.front, 2,
        reason: 'alpha gana H1+H2+H3+H4, beta gana H5+H6 → front=+2');

    // Debe haber press H3 (beta disparó en H2)
    expect(st.frontPresses.isNotEmpty, true,
        reason: 'Debe haber al menos 1 presión');

    // En la press H3: alpha gana H3,H4; beta gana H5,H6; AS resto → alpha +0 → puede variar
    final pressH3 = st.frontPresses.first;
    print('Press H3 score=${pressH3.score}');
    // El loser de la press H3 es beta (quien iba perdiendo cuando se triggereó)
    expect(pressH3.loser, 'beta',
        reason: 'Loser de press H3 es beta (alpha estaba +2UP, beta iba perdiendo)');
  });

  test('nassauPressLiveStatus - simetría: resultado consistente sin importar orden p1/p2', () {
    // El score del F9 y los signs de press deben ser opuestos al intercambiar p1/p2
    final cam = Player(id: 'cam', name: 'CAM', handicapBase: 14, colorIndex: 0);
    final cav = Player(id: 'cav', name: 'CAV', handicapBase: 12, colorIndex: 1);

    final holes = List.generate(18, (i) => CourseHole(
      hole: i + 1, par: 4,
      strokeIndex: [5, 11, 15, 1, 9, 17, 3, 13, 7, 6, 2, 18, 8, 4, 16, 10, 12, 14][i],
    ));
    final course = CourseInfo(name: 'Test', holes: holes);

    final scoresCAV = <int, HoleScore>{
      1: HoleScore(playerId: 'cav', hole: 1,  grossScore: 6),
      2: HoleScore(playerId: 'cav', hole: 2,  grossScore: 11),
      3: HoleScore(playerId: 'cav', hole: 3,  grossScore: 3),
      4: HoleScore(playerId: 'cav', hole: 4,  grossScore: 6),
      5: HoleScore(playerId: 'cav', hole: 5,  grossScore: 4),
      6: HoleScore(playerId: 'cav', hole: 6,  grossScore: 7),
      7: HoleScore(playerId: 'cav', hole: 7,  grossScore: 5),
      8: HoleScore(playerId: 'cav', hole: 8,  grossScore: 5),
      9: HoleScore(playerId: 'cav', hole: 9,  grossScore: 6),
    };
    final scoresCAM = <int, HoleScore>{
      1: HoleScore(playerId: 'cam', hole: 1,  grossScore: 5),
      2: HoleScore(playerId: 'cam', hole: 2,  grossScore: 8),
      3: HoleScore(playerId: 'cam', hole: 3,  grossScore: 4),
      4: HoleScore(playerId: 'cam', hole: 4,  grossScore: 6),
      5: HoleScore(playerId: 'cam', hole: 5,  grossScore: 5),
      6: HoleScore(playerId: 'cam', hole: 6,  grossScore: 8),
      7: HoleScore(playerId: 'cam', hole: 7,  grossScore: 7),
      8: HoleScore(playerId: 'cam', hole: 8,  grossScore: 6),
      9: HoleScore(playerId: 'cam', hole: 9,  grossScore: 6),
    };

    final mod = _nassauPressMod(
      ['cam', 'cav'],
      frontValue: 50, backValue: 50, totalValue: 100,
      frontPressValue: 50, backPressValue: 50,
      trigger: 2,
      mode: GrossNetMode.net,
    );
    final group = BetGroup(
      id: 'g1', name: 'Test', format: PartidaFormat.allInOnePot,
      playerIds: ['cam', 'cav'],
      modules: [mod],
    );
    final round = Round(
      id: 'r1', name: 'Simetria', course: course,
      players: [cam, cav],
      roundPlayers: [
        RoundPlayer(playerId: 'cam', handicapEnRonda: 14),
        RoundPlayer(playerId: 'cav', handicapEnRonda: 12),
      ],
      betGroups: [group],
      scores: {'cam': scoresCAM, 'cav': scoresCAV},
      events: {'cam': {}, 'cav': {}},
      oyeseRankings: {}, sliding: [],
      createdAt: DateTime.now(),
      startingNine: StartingNine.front,
      totalHoles: 9,
    );

    // cam=p1 vs cav=p2
    final stCamP1 = BetEngine.nassauPressLiveStatus(round, 'cam', 'cav', mod);
    // cav=p1 vs cam=p2 (orden invertido)
    final stCavP1 = BetEngine.nassauPressLiveStatus(round, 'cav', 'cam', mod);

    print('cam=p1: front=${stCamP1.front}, presses=${stCamP1.frontPresses.map((p) => "H${p.startHole}:${p.score}").join(",")}');
    print('cav=p1: front=${stCavP1.front}, presses=${stCavP1.frontPresses.map((p) => "H${p.startHole}:${p.score}").join(",")}');

    // Los scores del F9 deben ser opuestos
    expect(stCamP1.front, -stCavP1.front,
        reason: 'front(cam=p1) debe ser el opuesto de front(cav=p1)');

    // El número de presiones debe ser el mismo
    expect(stCamP1.frontPresses.length, stCavP1.frontPresses.length,
        reason: 'Mismo número de presiones independientemente del orden p1/p2');

    // Los scores de presiones deben ser opuestos (misma magnitud, signo contrario)
    for (int i = 0; i < stCamP1.frontPresses.length; i++) {
      expect(stCamP1.frontPresses[i].score, -stCavP1.frontPresses[i].score,
          reason: 'score de press $i debe ser opuesto al intercambiar p1/p2');
    }
  });

  test('nassauPressLiveStatus - genera entries correctamente con startingNine=back (hoyos 10-18)', () {
    final p1 = Player(id: 'p1', name: 'CAV',  handicapBase: 0,  colorIndex: 0);
    final p2 = Player(id: 'p2', name: 'CAM',  handicapBase: 10, colorIndex: 1);

    final mod = _nassauPressMod(
      ['p1', 'p2'],
      frontValue: 50, backValue: 50, totalValue: 100,
      frontPressValue: 50, backPressValue: 50,
      trigger: 2,
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
    final nassauEntries = entries.where((e) => e.betType == BetModuleType.nassau).toList();
    final pressEntries  = nassauEntries.where((e) => e.reason.contains('Press')).toList();
    print('Nassau entries: ${nassauEntries.length}, Press entries: ${pressEntries.length}');

    expect(nassauEntries.isNotEmpty, true,
        reason: 'Debe haber entries de nassau en ronda back nine');
    expect(breakdown[BetModuleType.nassau], isNotNull);
    expect(breakdown[BetModuleType.nassau]!, lessThan(0),
        reason: 'p1 (CAV) perdió el B9 → balance debe ser negativo (p2=CAM gana)');

    // Con trigger=2, no debe haber más de 2 presiones
    expect(pressEntries.length, lessThanOrEqualTo(2),
        reason: 'No debe haber más de 2 presiones con trigger=2 en estos scores');
  });
}
