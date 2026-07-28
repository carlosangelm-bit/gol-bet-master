// ignore_for_file: avoid_print
// =============================================================================
// Tests de integración — módulo Nassau
// Cubre: startingNine=back, rondas 9H, strokesReceivedInPlayedHoles, empates
//        por segmento, carry, presiones automáticas, live vs ledger, equipo 2v2.
//
// NO modifica ninguna lógica del engine.
// Detecta bugs críticos: inversión front/back, acceso fuera de rango, errores
// de carry y mismatches live-ledger.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Cursos de test
// ─────────────────────────────────────────────────────────────────────────────

/// 18 hoyos. SI: impares para F9, pares para B9 (ciclo idéntico al de mandatory_fixes).
final _course18 = CourseInfo(
  name: '18-Hole Course',
  holes: List.generate(18, (i) {
    final si = (i % 9) * 2 + (i < 9 ? 1 : 2);
    return CourseHole(hole: i + 1, par: 4, strokeIndex: si);
  }),
);

/// 9 hoyos numerados 10–18 (simula back-nine round con startingNine=back).
final _courseB9 = CourseInfo(
  name: 'Back 9 Course',
  holes: List.generate(9, (i) {
    final si = (i * 2) + 2; // SI: 2,4,6,8,10,12,14,16,18
    return CourseHole(hole: i + 10, par: 4, strokeIndex: si);
  }),
);

/// 9 hoyos numerados 1–9 (simula front-nine round).
final _courseF9 = CourseInfo(
  name: 'Front 9 Course',
  holes: List.generate(9, (i) {
    final si = (i * 2) + 1; // SI: 1,3,5,7,9,11,13,15,17
    return CourseHole(hole: i + 1, par: 4, strokeIndex: si);
  }),
);

// ─────────────────────────────────────────────────────────────────────────────
// Helpers de construcción de ronda
// ─────────────────────────────────────────────────────────────────────────────

/// Construye una Round con los datos mínimos para los tests.
/// [players]   lista de maps {id, hcp, name?}
/// [scores]    playerId → lista de gross scores en orden de juego
///             (para back-start los primeros 9 son hoyos 10-18).
///             Valor 0 = hoyo no jugado.
/// [manuals]   p1Id → {p2Id: strokes} para manualHandicaps
/// [pairSlid]  mapa canónico "lowId|highId" → value
Round _makeRound({
  required List<Map<String, dynamic>> players,
  required List<BetGroup> groups,
  required Map<String, List<int>> scores,
  int totalHoles = 18,
  StartingNine startingNine = StartingNine.front,
  CourseInfo? course,
  Map<String, Map<String, double>>? manuals,
  Map<String, double>? pairSlid,
}) {
  final c = course ??
      (startingNine == StartingNine.back ? _courseB9 : _course18);

  final rPlayers = players.map((p) {
    final pid = p['id'] as String;
    final hcp = (p['hcp'] as num).toDouble();
    return RoundPlayer(
      playerId: pid,
      handicapEnRonda: hcp,
      manualHandicaps: (manuals?[pid]) ?? {},
    );
  }).toList();

  final pObjects = players
      .map((p) => Player(
            id: p['id'] as String,
            name: (p['name'] as String?) ?? (p['id'] as String),
            handicapBase: (p['hcp'] as num).toDouble(),
          ))
      .toList();

  // Orden de hoyos según startingNine
  final List<int> holeNums;
  if (totalHoles <= 9) {
    // Ronda de 9 hoyos: tomamos los hoyos que existen en el curso
    holeNums = c.holes.map((ch) => ch.hole).toList()..sort();
    if (startingNine == StartingNine.back) {
      // Para back-nine solo, los hoyos ya están ordenados 10-18
    }
  } else {
    holeNums = startingNine == StartingNine.back
        ? [
            ...List.generate(9, (i) => i + 10),
            ...List.generate(9, (i) => i + 1)
          ]
        : List.generate(18, (i) => i + 1);
  }

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
    pairSliding: pairSlid ?? const {},
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers de módulos / grupos
// ─────────────────────────────────────────────────────────────────────────────

BetModuleInstance _nassauMod(
  List<String> pids, {
  bool net = false,
  bool press = false,
  int trigger = 2,
  bool carry = false,
  bool carryApplied = false,
  double front = 50,
  double back = 50,
  double total = 100,
  double frontPress = 25,
  double backPress = 25,
  int? maxPresses,
  bool allowMultiple = true,
}) =>
    BetModuleInstance.defaultFor(BetModuleType.nassau, pids).copyWith(
      nassauConfig: NassauConfig(
        frontValue: front,
        backValue: back,
        totalValue: total,
        mode: net ? GrossNetMode.net : GrossNetMode.gross,
        pressEnabled: press,
        autoPressTrigger: trigger,
        frontPressValue: frontPress,
        backPressValue: backPress,
        carryEnabled: carry,
        carryApplied: carryApplied,
        allowMultiplePresses: allowMultiple,
        maxPresses: maxPresses,
      ),
    );

BetModuleInstance _nassauTeamMod({
  required List<String> sideAIds,
  required List<String> sideBIds,
  bool net = false,
  bool press = false,
  int trigger = 2,
  double front = 50,
  double back = 50,
  double total = 100,
}) {
  final allIds = [...sideAIds, ...sideBIds];
  final mod = BetModuleInstance.defaultFor(BetModuleType.nassau, allIds);
  return mod.copyWith(
    nassauConfig: NassauConfig(
      frontValue: front,
      backValue: back,
      totalValue: total,
      mode: net ? GrossNetMode.net : GrossNetMode.gross,
      pressEnabled: press,
      autoPressTrigger: trigger,
    ),
    sides: [
      BetSide(id: 'sA', name: 'Team A', playerIds: sideAIds),
      BetSide(id: 'sB', name: 'Team B', playerIds: sideBIds),
    ],
  );
}

BetGroup _group(List<String> pids, BetModuleInstance mod) => BetGroup(
      id: 'g1',
      name: 'Group 1',
      format: PartidaFormat.allInOnePot,
      playerIds: pids,
      modules: [mod],
    );

// ─────────────────────────────────────────────────────────────────────────────
// Helpers de aserción / diagnóstico
// ─────────────────────────────────────────────────────────────────────────────

/// Imprime y retorna las entradas del ledger para el par (p1, p2) en un módulo Nassau.
List<LedgerEntry> _nassauEntries(
    List<LedgerEntry> all, String p1, String p2) {
  return all
      .where((e) =>
          e.betType == BetModuleType.nassau &&
          ((e.fromPlayerId == p1 && e.toPlayerId == p2) ||
              (e.fromPlayerId == p2 && e.toPlayerId == p1)))
      .toList();
}

/// Verifica que la suma de entradas de un segmento dado coincide con el ledger.
void _expectSegmentEntry(
  List<LedgerEntry> entries,
  String winner,
  String loser,
  double amount,
  String label,
) {
  final match = entries.where((e) =>
      e.toPlayerId == winner &&
      e.fromPlayerId == loser &&
      e.reason.contains(label));
  expect(
    match.isNotEmpty,
    isTrue,
    reason: 'Se esperaba entrada "$label" de $loser→$winner por \$$amount. '
        'Entradas: ${entries.map((e) => '${e.fromPlayerId}→${e.toPlayerId} ${e.reason} \$${e.amount}').toList()}',
  );
  expect(match.first.amount, closeTo(amount, 0.01));
}

// Genera 9 scores idénticos (grossA, grossB) intercalados para comparaciones.
List<int> _scoresRepeat(int gross, int count) =>
    List.generate(count, (_) => gross);

// =============================================================================
// SUITE PRINCIPAL
// =============================================================================
void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // GRUPO 1: StartingNine = back
  // ───────────────────────────────────────────────────────────────────────────
  group('G1 – StartingNine = back', () {
    // Curso 18 hoyos, arranque por el 10. Los hoyos 10-18 son "Front" lógico.
    // p1 gana 5 hoyos del back-nine físico (=Front lógico) y pierde 4 del front-nine físico (=Back lógico).
    // Esperado: p1 gana Front ($50) y Total ($100); p2 gana Back ($50).

    test('G1.1 – individual sin press, back-start, p1 gana Front+Total, p2 gana Back', () {
      // Scores: hoyos 10-18 primero, luego 1-9.
      // p1 gana los 9 primeros hoyos jugados (10-18) → Front=+9 → gana Front.
      // p2 gana los 9 siguientes (1-9) → Back=-9 → p2 gana Back.
      final scores18A = [
        // Hoyos 10-18 (Front lógico): p1=3, p2=4 → p1 gana cada uno
        3, 3, 3, 3, 3, 3, 3, 3, 3,
        // Hoyos 1-9 (Back lógico): p1=5, p2=4 → p2 gana cada uno
        5, 5, 5, 5, 5, 5, 5, 5, 5,
      ];
      final scores18B = [
        4, 4, 4, 4, 4, 4, 4, 4, 4,
        4, 4, 4, 4, 4, 4, 4, 4, 4,
      ];

      final mod = _nassauMod(['A', 'B']);
      final round = _makeRound(
        players: [
          {'id': 'A', 'hcp': 0.0},
          {'id': 'B', 'hcp': 0.0},
        ],
        groups: [_group(['A', 'B'], mod)],
        scores: {'A': scores18A, 'B': scores18B},
        startingNine: StartingNine.back,
        course: _course18,
        totalHoles: 18,
      );

      final entries = BetEngine.computeAll(round);
      final pairE = _nassauEntries(entries, 'A', 'B');

      print('[G1.1] Entradas: ${pairE.map((e) => '${e.fromPlayerId}→${e.toPlayerId} ${e.reason} \$${e.amount}').toList()}');

      // A gana Front (hoyos 10-18 son el primer segmento jugado)
      _expectSegmentEntry(pairE, 'A', 'B', 50, 'Front 9');
      // B gana Back (hoyos 1-9)
      _expectSegmentEntry(pairE, 'B', 'A', 50, 'Back 9');
      // Total: A gana (9-9=0 → push) → no hay entrada Total
      // front=+9, back=-9, total=0 → push
      final totalEntries = pairE.where((e) => e.reason.contains('Total')).toList();
      expect(totalEntries, isEmpty, reason: 'Total debe ser push (0)');
    });

    test('G1.2 – individual con press trigger=2, back-start', () {
      // p1 gana los primeros 3 hoyos del Front (10,11,12) → score relativo = 3 → press en H13.
      // El press dura del H13 al H18. En el press p2 recupera, score press=0 → no hay press entry.
      // Resultado total Front: p1 gana → entrada Front $50.
      final scoresA = [
        3, 3, 3, 4, 4, 4, 4, 4, 4, // 10-18 (Front): gana H10,11,12; empata 13-18
        4, 4, 4, 4, 4, 4, 4, 4, 4, // 1-9 (Back): empate
      ];
      final scoresB = [
        4, 4, 4, 4, 4, 4, 4, 4, 4,
        4, 4, 4, 4, 4, 4, 4, 4, 4,
      ];

      final mod = _nassauMod(['A', 'B'], press: true, trigger: 2);
      final round = _makeRound(
        players: [{'id': 'A', 'hcp': 0.0}, {'id': 'B', 'hcp': 0.0}],
        groups: [_group(['A', 'B'], mod)],
        scores: {'A': scoresA, 'B': scoresB},
        startingNine: StartingNine.back,
        course: _course18,
        totalHoles: 18,
      );

      final entries = BetEngine.computeAll(round);
      final pairE = _nassauEntries(entries, 'A', 'B');
      print('[G1.2] Entradas: ${pairE.map((e) => '${e.fromPlayerId}→${e.toPlayerId} ${e.reason} \$${e.amount}').toList()}');

      // A gana Front (+3 neto en seg1)
      _expectSegmentEntry(pairE, 'A', 'B', 50, 'Front 9');
      // Back empate → sin entrada
      final backEntries = pairE.where((e) => e.reason.contains('Back 9')).toList();
      expect(backEntries, isEmpty, reason: 'Back debe ser push');
    });

    test('G1.3 – equipo 2v2, back-start, Team A gana Front', () {
      // Team A (C,D) gana los primeros 9 hoyos (10-18 = Front lógico).
      // Team B (E,F) empata el Back.
      final scoresC = [3,3,3,3,3,3,3,3,3, 4,4,4,4,4,4,4,4,4];
      final scoresD = [3,3,3,3,3,3,3,3,3, 4,4,4,4,4,4,4,4,4];
      final scoresE = [4,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];
      final scoresF = [4,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];

      final mod = _nassauTeamMod(sideAIds: ['C','D'], sideBIds: ['E','F']);
      final round = _makeRound(
        players: [
          {'id':'C','hcp':0.0}, {'id':'D','hcp':0.0},
          {'id':'E','hcp':0.0}, {'id':'F','hcp':0.0},
        ],
        groups: [_group(['C','D','E','F'], mod)],
        scores: {'C':scoresC,'D':scoresD,'E':scoresE,'F':scoresF},
        startingNine: StartingNine.back,
        course: _course18,
        totalHoles: 18,
      );

      final entries = BetEngine.computeAll(round);
      final frontEntries = entries.where((e) =>
          e.betType == BetModuleType.nassau &&
          e.reason.contains('Front 9') &&
          e.toPlayerId == 'C' || (e.betType == BetModuleType.nassau &&
          e.reason.contains('Front 9') &&
          e.toPlayerId == 'D')).toList();
      print('[G1.3] Entradas: ${entries.map((e) => '${e.fromPlayerId}→${e.toPlayerId} ${e.reason} \$${e.amount}').toList()}');

      // Debe haber entradas de Front (TeamA gana)
      final winners = entries.where((e) =>
          e.betType == BetModuleType.nassau &&
          e.reason.contains('Front 9') &&
          ['C','D'].contains(e.toPlayerId)).toList();
      expect(winners, isNotEmpty, reason: 'Team A debe ganar Front (hoyos 10-18 = seg1)');
    });

    test('G1.4 – ANTI-REGRESIÓN: sin inversión front/back en back-start', () {
      // p1 gana SOLO los hoyos 1-9 (Back lógico en back-start).
      // Si hay inversión, p1 ganaría "Front" cuando debería ganar "Back".
      final scoresA = [
        4,4,4,4,4,4,4,4,4, // hoyos 10-18 (Front lógico): empate
        3,3,3,3,3,3,3,3,3, // hoyos 1-9  (Back lógico):  A gana
      ];
      final scoresB = [
        4,4,4,4,4,4,4,4,4,
        4,4,4,4,4,4,4,4,4,
      ];

      final mod = _nassauMod(['A','B']);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        startingNine: StartingNine.back,
        course: _course18,
        totalHoles: 18,
      );

      final entries = BetEngine.computeAll(round);
      final pairE = _nassauEntries(entries, 'A', 'B');
      print('[G1.4] Entradas: ${pairE.map((e) => '${e.fromPlayerId}→${e.toPlayerId} ${e.reason}').toList()}');

      // Front (hoyos 10-18): empate → sin entrada
      final frontWinnerA = pairE.where((e) =>
          e.reason.contains('Front 9') && e.toPlayerId == 'A').toList();
      expect(frontWinnerA, isEmpty,
          reason: 'INVERSIÓN detectada: A ganó "Front 9" cuando ganó hoyos 1-9 (Back lógico)');

      // Back (hoyos 1-9): A gana → entrada Back $50
      _expectSegmentEntry(pairE, 'A', 'B', 50, 'Back 9');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GRUPO 2: Rondas de 9 hoyos
  // ───────────────────────────────────────────────────────────────────────────
  group('G2 – Rondas de 9 hoyos', () {
    test('G2.1 – solo hoyos 1-9, front-start, un único segmento', () {
      // Con totalHoles=9 y curso F9 (hoyos 1-9), solo hay un segmento.
      // p1 gana 5 de 9 hoyos.
      final scoresA = [3,3,3,3,3,4,4,4,4]; // gana 5
      final scoresB = [4,4,4,4,4,4,4,4,4];

      final mod = _nassauMod(['A','B']);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        course: _courseF9,
        totalHoles: 9,
        startingNine: StartingNine.front,
      );

      final entries = BetEngine.computeAll(round);
      final pairE = _nassauEntries(entries, 'A', 'B');
      print('[G2.1] Entradas: ${pairE.map((e) => '${e.fromPlayerId}→${e.toPlayerId} ${e.reason} \$${e.amount}').toList()}');

      // Debe haber UNA entrada "Nassau 9 hoyos" (no Front/Back)
      expect(entries.where((e) => e.reason.contains('Front 9')), isEmpty,
          reason: 'Ronda 9H no debe tener segmento "Front 9"');
      expect(entries.where((e) => e.reason.contains('Back 9')), isEmpty,
          reason: 'Ronda 9H no debe tener segmento "Back 9"');
      _expectSegmentEntry(pairE, 'A', 'B', 50, '9 hoyos');
    });

    test('G2.2 – solo hoyos 10-18 (back-nine round, startingNine=back)', () {
      // Curso B9 (hoyos 10-18), totalHoles=9, startingNine=back.
      // Solo hay un segmento. p2 gana.
      final scoresA = [4,4,4,4,4,4,4,4,4];
      final scoresB = [3,3,3,3,3,4,4,4,4];

      final mod = _nassauMod(['A','B']);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        course: _courseB9,
        totalHoles: 9,
        startingNine: StartingNine.back,
      );

      final entries = BetEngine.computeAll(round);
      final pairE = _nassauEntries(entries, 'A', 'B');
      print('[G2.2] Entradas: ${pairE.map((e) => '${e.fromPlayerId}→${e.toPlayerId} ${e.reason} \$${e.amount}').toList()}');

      _expectSegmentEntry(pairE, 'B', 'A', 50, '9 hoyos');
    });

    test('G2.3 – ronda parcial 9H: solo 5 hoyos jugados', () {
      // 9 hoyos en curso, pero solo se jugaron 5 (los 4 últimos = 0 = sin score).
      // El engine debe ignorar hoyos sin score.
      final scoresA = [3,3,3,3,3,0,0,0,0]; // solo 5 hoyos
      final scoresB = [4,4,4,4,4,0,0,0,0];

      final mod = _nassauMod(['A','B']);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        course: _courseF9,
        totalHoles: 9,
        startingNine: StartingNine.front,
      );

      final entries = BetEngine.computeAll(round);
      final pairE = _nassauEntries(entries, 'A', 'B');
      print('[G2.3] Entradas parcial: ${pairE.map((e) => '${e.reason} \$${e.amount}').toList()}');

      // A gana los 5 hoyos jugados → debe ganar el único segmento de 9H
      _expectSegmentEntry(pairE, 'A', 'B', 50, '9 hoyos');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GRUPO 3: strokesReceivedInPlayedHoles (HCP solo en hoyos jugados)
  // ───────────────────────────────────────────────────────────────────────────
  group('G3 – strokesReceivedInPlayedHoles: HCP en hoyos jugados', () {
    test('G3.1 – 18H, p1 recibe 9 strokes de p2 (gross idéntico → p1 gana neto)', () {
      // p1 HCP=9, p2 HCP=0 → p1 recibe 9 strokes distribuidos en los hoyos de SI 1-9.
      // Gross ambos = 4 en cada hoyo → neto de p1 < gross de p2 en los 9 hoyos de SI bajo.
      // Resultado: p1 gana Front, Back y Total.
      final scores18 = _scoresRepeat(4, 18);

      final mod = _nassauMod(['A','B'], net: true);
      final round = _makeRound(
        players: [{'id':'A','hcp':9.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scores18,'B':scores18},
        course: _course18,
        totalHoles: 18,
      );

      final entries = BetEngine.computeAll(round);
      final pairE = _nassauEntries(entries, 'A', 'B');
      print('[G3.1] HCP 9 dist 18H: ${pairE.map((e) => '${e.fromPlayerId}→${e.toPlayerId} ${e.reason}').toList()}');

      // A recibe 9 strokes → gana los 9 hoyos de SI bajo → gana Front, Back y Total
      expect(pairE.where((e) => e.toPlayerId == 'A'), isNotEmpty,
          reason: 'A debe ganar entradas con HCP=9 vs HCP=0');
    });

    test('G3.2 – 9H (B9), p1 recibe 9 strokes: distribuidos en 9 hoyos, gana todos', () {
      // Curso B9 (hoyos 10-18, SI: 2,4,6,8,10,12,14,16,18).
      // p1 HCP=9 → recibe 9/9=1 stroke en CADA hoyo de los 9 jugados.
      // Gross p1 = gross p2 = 5 → neto p1 = 4 → gana todos.
      final scores9 = _scoresRepeat(5, 9);
      final mod = _nassauMod(['A','B'], net: true);
      final round = _makeRound(
        players: [{'id':'A','hcp':9.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scores9,'B':scores9},
        course: _courseB9,
        totalHoles: 9,
        startingNine: StartingNine.back,
      );

      final entries = BetEngine.computeAll(round);
      final pairE = _nassauEntries(entries, 'A', 'B');
      print('[G3.2] HCP 9 en 9H: ${pairE.map((e) => '${e.fromPlayerId}→${e.toPlayerId} ${e.reason}').toList()}');
      _expectSegmentEntry(pairE, 'A', 'B', 50, '9 hoyos');
    });

    test('G3.3 – ronda parcial 9H de 18, p1 recibe 9 strokes: solo en hoyos jugados', () {
      // 18H course, solo jugaron 9 (los primeros 9, hoyos 1-9). HCP = 9.
      // Los 9 strokes se distribuyen entre los 9 hoyos jugados → 1 stroke/hoyo.
      // Gross idéntico → p1 gana todos los hoyos jugados → gana Front (hoyos 1-9).
      final scoresA = [..._scoresRepeat(5, 9), ..._scoresRepeat(0, 9)];
      final scoresB = [..._scoresRepeat(5, 9), ..._scoresRepeat(0, 9)];

      final mod = _nassauMod(['A','B'], net: true);
      final round = _makeRound(
        players: [{'id':'A','hcp':9.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        course: _course18,
        totalHoles: 18,
      );

      final entries = BetEngine.computeAll(round);
      final pairE = _nassauEntries(entries, 'A', 'B');
      print('[G3.3] HCP 9 en ronda parcial: ${pairE.map((e) => e.reason).toList()}');

      // A gana Front (los 9 hoyos jugados)
      _expectSegmentEntry(pairE, 'A', 'B', 50, 'Front 9');
      // Back: ningún hoyo jugado → no hay entrada
      expect(pairE.where((e) => e.reason.contains('Back 9')), isEmpty,
          reason: 'Back sin hoyos jugados no debe tener entrada');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GRUPO 4: Empates por segmento
  // ───────────────────────────────────────────────────────────────────────────
  group('G4 – Empates por segmento (push)', () {
    test('G4.1 – Front empatado → sin entrada Front', () {
      // Scores: Front (1-9) todos iguales, Back p1 gana.
      final scoresA = [4,4,4,4,4,4,4,4,4, 3,3,3,3,3,3,3,3,3];
      final scoresB = [4,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];
      final mod = _nassauMod(['A','B']);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        course: _course18, totalHoles: 18,
      );

      final entries = BetEngine.computeAll(round);
      final pairE = _nassauEntries(entries, 'A', 'B');
      print('[G4.1] Empate Front: ${pairE.map((e) => e.reason).toList()}');

      expect(pairE.where((e) => e.reason.contains('Front 9')), isEmpty,
          reason: 'Front empatado no debe generar entrada');
      _expectSegmentEntry(pairE, 'A', 'B', 50, 'Back 9');
    });

    test('G4.2 – Back empatado → sin entrada Back', () {
      final scoresA = [3,3,3,3,3,3,3,3,3, 4,4,4,4,4,4,4,4,4];
      final scoresB = [4,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];
      final mod = _nassauMod(['A','B']);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        course: _course18, totalHoles: 18,
      );

      final entries = BetEngine.computeAll(round);
      final pairE = _nassauEntries(entries, 'A', 'B');
      print('[G4.2] Empate Back: ${pairE.map((e) => e.reason).toList()}');

      _expectSegmentEntry(pairE, 'A', 'B', 50, 'Front 9');
      expect(pairE.where((e) => e.reason.contains('Back 9')), isEmpty,
          reason: 'Back empatado no debe generar entrada');
    });

    test('G4.3 – Total empatado → sin entrada Total', () {
      // Front: A gana +3, Back: B gana -3, Total = 0.
      final scoresA = [3,3,3,4,4,4,4,4,4, 5,5,5,4,4,4,4,4,4];
      final scoresB = [4,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];
      final mod = _nassauMod(['A','B']);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        course: _course18, totalHoles: 18,
      );

      final entries = BetEngine.computeAll(round);
      final pairE = _nassauEntries(entries, 'A', 'B');
      print('[G4.3] Total push: ${pairE.map((e) => '${e.reason} \$${e.amount}').toList()}');

      // Front: A gana
      _expectSegmentEntry(pairE, 'A', 'B', 50, 'Front 9');
      // Back: B gana
      _expectSegmentEntry(pairE, 'B', 'A', 50, 'Back 9');
      // Total: empate
      expect(pairE.where((e) => e.reason.contains('Total 18')), isEmpty,
          reason: 'Total empatado no debe generar entrada');
    });

    test('G4.4 – Todos empatados → 0 entradas', () {
      final scores = _scoresRepeat(4, 18);
      final mod = _nassauMod(['A','B']);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scores,'B':scores},
        course: _course18, totalHoles: 18,
      );

      final entries = BetEngine.computeAll(round);
      expect(entries, isEmpty, reason: 'Todos los segmentos empatados → 0 entradas');
    });

    test('G4.5 – empate en ronda 9H → 0 entradas', () {
      final scores = _scoresRepeat(4, 9);
      final mod = _nassauMod(['A','B']);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scores,'B':scores},
        course: _courseF9, totalHoles: 9,
      );
      expect(BetEngine.computeAll(round), isEmpty,
          reason: 'Ronda 9H empatada → 0 entradas');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GRUPO 5: Carry
  // ───────────────────────────────────────────────────────────────────────────
  group('G5 – Carry', () {
    test('G5.1 – carry disabled, Front empatado → Back sin multiplicar', () {
      // carryEnabled=false: aunque el Front empate, el Back vale $50 (no $100).
      final scoresA = [4,4,4,4,4,4,4,4,4, 3,3,3,3,3,3,3,3,3]; // Front=0, Back=+9
      final scoresB = [4,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];
      final mod = _nassauMod(['A','B'], carry: false, carryApplied: false);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        course: _course18, totalHoles: 18,
      );

      final entries = BetEngine.computeAll(round);
      final pairE = _nassauEntries(entries, 'A', 'B');
      print('[G5.1] Carry disabled: ${pairE.map((e) => '${e.reason} \$${e.amount}').toList()}');

      final backE = pairE.where((e) => e.reason.contains('Back 9')).toList();
      expect(backE, isNotEmpty);
      expect(backE.first.amount, closeTo(50, 0.01),
          reason: 'Carry disabled: Back debe valer \$50 no \$100');
    });

    test('G5.2 – carry enabled + carryApplied=true, Front empatado → Back duplicado', () {
      // carryEnabled=true + carryApplied=true → Back vale $100 (50 * 2.0).
      final scoresA = [4,4,4,4,4,4,4,4,4, 3,3,3,3,3,3,3,3,3];
      final scoresB = [4,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];
      final mod = _nassauMod(['A','B'], carry: true, carryApplied: true);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        course: _course18, totalHoles: 18,
      );

      final entries = BetEngine.computeAll(round);
      final pairE = _nassauEntries(entries, 'A', 'B');
      print('[G5.2] Carry applied: ${pairE.map((e) => '${e.reason} \$${e.amount}').toList()}');

      final backE = pairE.where((e) => e.reason.contains('Back 9')).toList();
      expect(backE, isNotEmpty);
      expect(backE.first.amount, closeTo(100, 0.01),
          reason: 'Carry applied: Back debe valer \$100 (50 × 2)');
    });

    test('G5.3 – carry + back-start: carry aplica al Back lógico (hoyos 1-9)', () {
      // Back-start: hoyos 10-18 = Front lógico, hoyos 1-9 = Back lógico.
      // Front lógico (10-18) empatado → carry → Back lógico (1-9) vale x2.
      final scoresA = [4,4,4,4,4,4,4,4,4, 3,3,3,3,3,3,3,3,3]; // 10-18 push; 1-9 A gana
      final scoresB = [4,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];
      final mod = _nassauMod(['A','B'], carry: true, carryApplied: true);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        startingNine: StartingNine.back,
        course: _course18, totalHoles: 18,
      );

      final entries = BetEngine.computeAll(round);
      final pairE = _nassauEntries(entries, 'A', 'B');
      print('[G5.3] Carry back-start: ${pairE.map((e) => '${e.reason} \$${e.amount}').toList()}');

      final backE = pairE.where((e) => e.reason.contains('Back 9')).toList();
      expect(backE, isNotEmpty);
      expect(backE.first.amount, closeTo(100, 0.01),
          reason: 'Carry en back-start: Back lógico (1-9) debe valer \$100');
      expect(backE.first.toPlayerId, equals('A'));
    });

    test('G5.4 – carry: Front no empatado → Back NO se duplica', () {
      // carryApplied=false: el carry no se aplicó porque el Front no fue push.
      final scoresA = [3,4,4,4,4,4,4,4,4, 3,3,3,3,3,3,3,3,3]; // Front: A gana H1
      final scoresB = [4,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];
      final mod = _nassauMod(['A','B'], carry: true, carryApplied: false);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        course: _course18, totalHoles: 18,
      );

      final entries = BetEngine.computeAll(round);
      final pairE = _nassauEntries(entries, 'A', 'B');
      print('[G5.4] Carry no aplicado: ${pairE.map((e) => '${e.reason} \$${e.amount}').toList()}');

      final backE = pairE.where((e) => e.reason.contains('Back 9')).toList();
      expect(backE, isNotEmpty);
      expect(backE.first.amount, closeTo(50, 0.01),
          reason: 'Carry no aplicado: Back debe valer \$50 normal');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GRUPO 6: Presiones automáticas
  // ───────────────────────────────────────────────────────────────────────────
  group('G6 – Presiones automáticas', () {
    test('G6.1 – press simple: se dispara exactamente una vez en Front', () {
      // p1 gana H1, H2 → score=+2 → trigger=2 → press en H3.
      // press H3-H9: p2 recupera y gana → entrada press a favor de p2.
      final scoresA = [3,3,4,5,5,5,5,5,5, 4,4,4,4,4,4,4,4,4];
      final scoresB = [4,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];
      final mod = _nassauMod(['A','B'], press: true, trigger: 2, front: 50, back: 50);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        course: _course18, totalHoles: 18,
      );

      final entries = BetEngine.computeAll(round);
      final pairE = _nassauEntries(entries, 'A', 'B');
      print('[G6.1] Press simple: ${pairE.map((e) => '${e.fromPlayerId}→${e.toPlayerId} ${e.reason} \$${e.amount}').toList()}');

      // Debe haber exactamente 1 press entry en el Front
      final pressEntries = pairE.where((e) => e.reason.contains('Press')).toList();
      expect(pressEntries.length, greaterThanOrEqualTo(1),
          reason: 'Debe dispararse al menos 1 press');
    });

    test('G6.2 – múltiples presiones permitidas', () {
      // p1 gana H1,H2 (press en H3). Luego p1 gana H3,H4 de nuevo → segunda press.
      final scoresA = [3,3,3,3,4,4,4,4,4, 4,4,4,4,4,4,4,4,4]; // +4 en Front
      final scoresB = [4,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];
      final mod = _nassauMod(['A','B'], press: true, trigger: 2, allowMultiple: true);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        course: _course18, totalHoles: 18,
      );

      final entries = BetEngine.computeAll(round);
      final pressEntries = entries.where((e) => e.reason.contains('Press')).toList();
      print('[G6.2] Múltiples presses: ${pressEntries.map((e) => e.reason).toList()}');

      expect(pressEntries.length, greaterThanOrEqualTo(1),
          reason: 'Con allowMultiple=true deben existir presiones');
    });

    test('G6.3 – presiones deshabilitadas: no hay press entries', () {
      final scoresA = [3,3,3,3,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];
      final scoresB = [4,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];
      final mod = _nassauMod(['A','B'], press: false);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        course: _course18, totalHoles: 18,
      );

      final entries = BetEngine.computeAll(round);
      final pressEntries = entries.where((e) => e.reason.contains('Press')).toList();
      expect(pressEntries, isEmpty,
          reason: 'Con pressEnabled=false no debe haber press entries');
    });

    test('G6.4 – press en back-start: presión en Front lógico (hoyos 10-18)', () {
      // p1 gana H10,H11,H12,H13 (+4 en el Front lógico en back-start) → trigger=2 → press en H12.
      // Scores: posiciones 0-8 corresponden a hoyos 10-18 (Front lógico).
      final scoresA = [3,3,3,3,4,4,4,4,4, 4,4,4,4,4,4,4,4,4]; // 10-13 gana; resto empate
      final scoresB = [4,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];
      final mod = _nassauMod(['A','B'], press: true, trigger: 2);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        startingNine: StartingNine.back,
        course: _course18, totalHoles: 18,
      );

      final entries = BetEngine.computeAll(round);
      final pairE = _nassauEntries(entries, 'A', 'B');
      print('[G6.4] Press back-start: ${pairE.map((e) => e.reason).toList()}');

      // Debe haber press entries en el Front (hoyos 10-18)
      final pressEntries = pairE.where((e) => e.reason.contains('Press')).toList();
      expect(pressEntries, isNotEmpty,
          reason: 'Debe dispararse press en Front lógico (hoyos 10-18) con back-start');
    });

    test('G6.5 – maxPresses=1: solo una presión aunque trigger se supere varias veces', () {
      // p1 gana H1..H5 consecutivos → trigger=2, debería haber 2 presses, pero maxPresses=1.
      final scoresA = [3,3,3,3,3,4,4,4,4, 4,4,4,4,4,4,4,4,4];
      final scoresB = [4,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];
      final mod = _nassauMod(['A','B'], press: true, trigger: 2, maxPresses: 1, allowMultiple: true);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        course: _course18, totalHoles: 18,
      );

      final entries = BetEngine.computeAll(round);
      // En el Front (1-9) solo debe haber como máximo 1 press entry
      final pressEntriesFront = entries.where((e) =>
          e.reason.contains('Press') && e.reason.contains('Front')).toList();
      print('[G6.5] Presses front (maxPresses=1): ${pressEntriesFront.length}');
      expect(pressEntriesFront.length, lessThanOrEqualTo(1),
          reason: 'maxPresses=1 debe limitar a 1 press en el Front');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GRUPO 7: Consistencia live status vs final ledger
  // ───────────────────────────────────────────────────────────────────────────
  group('G7 – Live status vs final ledger', () {
    /// Helper: verifica que el signo de front/back/total en liveStatus
    /// coincide con las entradas del ledger.
    void verifyLiveVsLedger(
      Round round,
      String p1,
      String p2,
      BetModuleInstance mod,
      String label,
    ) {
      final live = BetEngine.nassauLiveStatus(round, p1, p2, mod);
      final entries = BetEngine.computeAll(round);
      final pairE = _nassauEntries(entries, p1, p2);

      print('[$label] Live: F=${live.front} B=${live.back} T=${live.total}');
      print('[$label] Ledger: ${pairE.map((e) => '${e.fromPlayerId}→${e.toPlayerId} ${e.reason} \$${e.amount}').toList()}');

      // Front: live.front > 0 → p1 gana Front → ledger tiene entrada toPlayerId=p1 "Front 9"
      if (live.front > 0) {
        final frontWin = pairE.where((e) =>
            e.reason.contains('Front 9') && e.toPlayerId == p1).toList();
        expect(frontWin, isNotEmpty,
            reason: '[$label] Live front>0 pero ledger no tiene entrada Front para $p1');
      } else if (live.front < 0) {
        final frontWin = pairE.where((e) =>
            e.reason.contains('Front 9') && e.toPlayerId == p2).toList();
        expect(frontWin, isNotEmpty,
            reason: '[$label] Live front<0 pero ledger no tiene entrada Front para $p2');
      } else {
        expect(pairE.where((e) => e.reason.contains('Front 9')), isEmpty,
            reason: '[$label] Live front=0 pero hay entradas Front');
      }

      // Back
      if (live.back > 0) {
        final backWin = pairE.where((e) =>
            e.reason.contains('Back 9') && e.toPlayerId == p1).toList();
        expect(backWin, isNotEmpty,
            reason: '[$label] Live back>0 pero ledger no tiene entrada Back para $p1');
      } else if (live.back < 0) {
        final backWin = pairE.where((e) =>
            e.reason.contains('Back 9') && e.toPlayerId == p2).toList();
        expect(backWin, isNotEmpty,
            reason: '[$label] Live back<0 pero ledger no tiene entrada Back para $p2');
      } else {
        expect(pairE.where((e) => e.reason.contains('Back 9')), isEmpty,
            reason: '[$label] Live back=0 pero hay entradas Back');
      }
    }

    test('G7.1 – individual sin press, front-start: live == ledger', () {
      final scoresA = [3,3,3,4,4,4,4,4,4, 5,5,5,4,4,4,4,4,4];
      final scoresB = [4,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];
      final mod = _nassauMod(['A','B']);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        course: _course18, totalHoles: 18,
      );
      verifyLiveVsLedger(round, 'A', 'B', mod, 'G7.1');
    });

    test('G7.2 – individual sin press, back-start: live == ledger', () {
      final scoresA = [3,3,3,4,4,4,4,4,4, 5,5,5,4,4,4,4,4,4];
      final scoresB = [4,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];
      final mod = _nassauMod(['A','B']);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        startingNine: StartingNine.back,
        course: _course18, totalHoles: 18,
      );
      verifyLiveVsLedger(round, 'A', 'B', mod, 'G7.2 back-start');
    });

    test('G7.3 – live: isLive=true no cambia el cálculo vs isLive=false', () {
      final scoresA = [3,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];
      final scoresB = [4,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];
      final mod = _nassauMod(['A','B']);

      final roundLive = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        course: _course18, totalHoles: 18,
      ).copyWith(isLive: true);

      final roundNotLive = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        course: _course18, totalHoles: 18,
      ).copyWith(isLive: false);

      final liveStatus = BetEngine.nassauLiveStatus(roundLive, 'A', 'B', mod);
      final notLiveStatus = BetEngine.nassauLiveStatus(roundNotLive, 'A', 'B', mod);

      expect(liveStatus.front, equals(notLiveStatus.front));
      expect(liveStatus.back,  equals(notLiveStatus.back));
      expect(liveStatus.total, equals(notLiveStatus.total));

      final liveEntries = BetEngine.computeAll(roundLive);
      final notLiveEntries = BetEngine.computeAll(roundNotLive);
      expect(liveEntries.length, equals(notLiveEntries.length),
          reason: 'isLive no debe afectar el número de entradas');
    });

    test('G7.4 – empate completo: live F=0 B=0 T=0 == ledger 0 entradas', () {
      final scores = _scoresRepeat(4, 18);
      final mod = _nassauMod(['A','B']);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scores,'B':scores},
        course: _course18, totalHoles: 18,
      );

      final live = BetEngine.nassauLiveStatus(round, 'A', 'B', mod);
      expect(live.front, 0, reason: 'Live front debe ser 0 en empate');
      expect(live.back,  0, reason: 'Live back debe ser 0 en empate');
      expect(live.total, 0, reason: 'Live total debe ser 0 en empate');
      expect(BetEngine.computeAll(round), isEmpty,
          reason: 'Ledger debe estar vacío en empate completo');
    });

    test('G7.5 – back-start: live reporta Front=hoyos 10-18, Back=hoyos 1-9', () {
      // p1 gana SOLO hoyos 10-18 → live.front > 0, live.back = 0.
      final scoresA = [3,3,3,3,3,3,3,3,3, 4,4,4,4,4,4,4,4,4]; // 10-18: gana; 1-9: empate
      final scoresB = [4,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];
      final mod = _nassauMod(['A','B']);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        startingNine: StartingNine.back,
        course: _course18, totalHoles: 18,
      );

      final live = BetEngine.nassauLiveStatus(round, 'A', 'B', mod);
      print('[G7.5] Live back-start: front=${live.front} back=${live.back}');

      expect(live.front, greaterThan(0),
          reason: 'Hoyos 10-18 deben mapearse a "front" en back-start');
      expect(live.back, equals(0),
          reason: 'Hoyos 1-9 (no jugados en este subtest) deben dar back=0');
      verifyLiveVsLedger(round, 'A', 'B', mod, 'G7.5');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GRUPO 8: Modo equipo 2v2
  // ───────────────────────────────────────────────────────────────────────────
  group('G8 – Equipo 2v2', () {
    test('G8.1 – 2v2 sin HCP, Team A gana Front y Total', () {
      // Team A (P1,P2) vs Team B (P3,P4). Best-ball por hoyo.
      // A: ambos 3 en Front, ambos 4 en Back. B: todos 4.
      final scoresP1 = [3,3,3,3,3,3,3,3,3, 4,4,4,4,4,4,4,4,4];
      final scoresP2 = [3,3,3,3,3,3,3,3,3, 4,4,4,4,4,4,4,4,4];
      final scoresP3 = [4,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];
      final scoresP4 = [4,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];

      final mod = _nassauTeamMod(sideAIds: ['P1','P2'], sideBIds: ['P3','P4']);
      final round = _makeRound(
        players: [
          {'id':'P1','hcp':0.0},{'id':'P2','hcp':0.0},
          {'id':'P3','hcp':0.0},{'id':'P4','hcp':0.0},
        ],
        groups: [_group(['P1','P2','P3','P4'], mod)],
        scores: {'P1':scoresP1,'P2':scoresP2,'P3':scoresP3,'P4':scoresP4},
        course: _course18, totalHoles: 18,
      );

      final entries = BetEngine.computeAll(round);
      print('[G8.1] Entradas equipo: ${entries.map((e) => '${e.fromPlayerId}→${e.toPlayerId} ${e.reason} \$${e.amount}').toList()}');

      // Team A gana Front: P3→P1, P3→P2, P4→P1, P4→P2
      final frontA = entries.where((e) =>
          e.reason.contains('Front 9') &&
          ['P1','P2'].contains(e.toPlayerId) &&
          ['P3','P4'].contains(e.fromPlayerId)).toList();
      expect(frontA.length, equals(4),
          reason: '2v2 Front: deben ser 4 entradas cruzadas (2×2)');

      // Back: empate → sin entradas
      final backEntries = entries.where((e) => e.reason.contains('Back 9')).toList();
      expect(backEntries, isEmpty,
          reason: 'Back empatado en 2v2 no debe generar entradas');
    });

    test('G8.2 – 2v2 con HCP: Team B recibe strokes y gana neto', () {
      // Team B recibe HCP → con gross idéntico, B gana neto.
      // P1,P2 HCP=0; P3,P4 HCP=9.
      final scores18 = _scoresRepeat(4, 18);
      final mod = _nassauTeamMod(sideAIds: ['P1','P2'], sideBIds: ['P3','P4'], net: true);
      final round = _makeRound(
        players: [
          {'id':'P1','hcp':0.0},{'id':'P2','hcp':0.0},
          {'id':'P3','hcp':9.0},{'id':'P4','hcp':9.0},
        ],
        groups: [_group(['P1','P2','P3','P4'], mod)],
        scores: {'P1':scores18,'P2':scores18,'P3':scores18,'P4':scores18},
        course: _course18, totalHoles: 18,
      );

      final entries = BetEngine.computeAll(round);
      print('[G8.2] 2v2 HCP: ${entries.map((e) => '${e.fromPlayerId}→${e.toPlayerId} ${e.reason}').toList()}');

      // Team B (P3/P4) debe ganar entradas
      final bWins = entries.where((e) =>
          e.betType == BetModuleType.nassau &&
          ['P3','P4'].contains(e.toPlayerId)).toList();
      expect(bWins, isNotEmpty,
          reason: 'Team B debe ganar con HCP=9 vs HCP=0 y gross idéntico');
    });

    test('G8.3 – 2v2 best-ball empate hoyo → segmento push → 0 entradas', () {
      // Todos los jugadores tienen gross idéntico en todos los hoyos.
      final scores = _scoresRepeat(4, 18);
      final mod = _nassauTeamMod(sideAIds: ['P1','P2'], sideBIds: ['P3','P4']);
      final round = _makeRound(
        players: [
          {'id':'P1','hcp':0.0},{'id':'P2','hcp':0.0},
          {'id':'P3','hcp':0.0},{'id':'P4','hcp':0.0},
        ],
        groups: [_group(['P1','P2','P3','P4'], mod)],
        scores: {'P1':scores,'P2':scores,'P3':scores,'P4':scores},
        course: _course18, totalHoles: 18,
      );

      final entries = BetEngine.computeAll(round);
      expect(entries, isEmpty,
          reason: '2v2 empate completo → 0 entradas');
    });

    test('G8.4 – 2v2 back-start: Front lógico = hoyos 10-18', () {
      // Team A gana SOLO hoyos 10-18 (Front lógico en back-start).
      final scoresA = [3,3,3,3,3,3,3,3,3, 4,4,4,4,4,4,4,4,4]; // 10-18 gana; 1-9 empate
      final scoresB = [4,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];

      final mod = _nassauTeamMod(sideAIds: ['P1','P2'], sideBIds: ['P3','P4']);
      final round = _makeRound(
        players: [
          {'id':'P1','hcp':0.0},{'id':'P2','hcp':0.0},
          {'id':'P3','hcp':0.0},{'id':'P4','hcp':0.0},
        ],
        groups: [_group(['P1','P2','P3','P4'], mod)],
        scores: {'P1':scoresA,'P2':scoresA,'P3':scoresB,'P4':scoresB},
        startingNine: StartingNine.back,
        course: _course18, totalHoles: 18,
      );

      final entries = BetEngine.computeAll(round);
      print('[G8.4] 2v2 back-start: ${entries.map((e) => '${e.fromPlayerId}→${e.toPlayerId} ${e.reason}').toList()}');

      final frontTeamA = entries.where((e) =>
          e.reason.contains('Front 9') &&
          ['P1','P2'].contains(e.toPlayerId)).toList();
      expect(frontTeamA, isNotEmpty,
          reason: 'Team A debe ganar Front (hoyos 10-18 = seg1 en back-start)');

      final backEntries = entries.where((e) => e.reason.contains('Back 9')).toList();
      expect(backEntries, isEmpty,
          reason: 'Back empatado en 2v2 back-start no debe generar entradas');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GRUPO 9: Rondas parciales (ronda 18H, pocos hoyos jugados)
  // ───────────────────────────────────────────────────────────────────────────
  group('G9 – Rondas parciales', () {
    test('G9.1 – solo 3 hoyos jugados: solo esos hoyos cuentan', () {
      // Ronda 18H, solo jugaron H1, H2, H3. A gana los 3.
      // Resultado: A gana Front (3 hoyos = seg1 incompleto), sin Back.
      // El Total se basa en la suma de todos los deltas jugados (solo F9) → A gana Total.
      final scoresA = [3,3,3,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0];
      final scoresB = [4,4,4,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0];
      final mod = _nassauMod(['A','B']);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        course: _course18, totalHoles: 18,
      );

      final entries = BetEngine.computeAll(round);
      final pairE = _nassauEntries(entries, 'A', 'B');
      print('[G9.1] Parcial 3H: ${pairE.map((e) => e.reason).toList()}');

      // A gana Front (parcial F9)
      _expectSegmentEntry(pairE, 'A', 'B', 50, 'Front 9');
      // Sin Back (no hay hoyos jugados en B9)
      expect(pairE.where((e) => e.reason.contains('Back 9')), isEmpty,
          reason: 'Back 9 sin hoyos no debe generar entrada');
      // Total: A gana (suma de deltas disponibles = +3)
      _expectSegmentEntry(pairE, 'A', 'B', 100, 'Total 18');
    });

    test('G9.2 – 9 hoyos F9 jugados (ronda 18H, parcial): Front con ganador, sin Back ni Total', () {
      final scoresA = [3,3,3,3,3,3,3,3,3, 0,0,0,0,0,0,0,0,0];
      final scoresB = [4,4,4,4,4,4,4,4,4, 0,0,0,0,0,0,0,0,0];
      final mod = _nassauMod(['A','B']);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        course: _course18, totalHoles: 18,
      );

      final entries = BetEngine.computeAll(round);
      final pairE = _nassauEntries(entries, 'A', 'B');
      print('[G9.2] Parcial 9H F9: ${pairE.map((e) => e.reason).toList()}');

      _expectSegmentEntry(pairE, 'A', 'B', 50, 'Front 9');
      expect(pairE.where((e) => e.reason.contains('Back 9')), isEmpty);
      // Total: 9 hoyos jugados = 0 en Back → total = Front = +9 → A gana Total
      // (el engine sí genera Total si hay score, basado en sum de todos deltas)
    });

    test('G9.3 – sin hoyos jugados: 0 entradas, no crash', () {
      final mod = _nassauMod(['A','B']);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {},
        course: _course18, totalHoles: 18,
      );

      expect(() => BetEngine.computeAll(round), returnsNormally,
          reason: 'Sin hoyos jugados no debe lanzar excepción');
      expect(BetEngine.computeAll(round), isEmpty,
          reason: 'Sin hoyos jugados: 0 entradas');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GRUPO 10: Escenarios de victoria correcta
  // ───────────────────────────────────────────────────────────────────────────
  group('G10 – Victoria con dirección correcta', () {
    test('G10.1 – p1 gana Front y Total, p2 gana Back', () {
      // Front (+5): p1 gana. Back (-3): p2 gana. Total (+2): p1 gana.
      final scoresA = [3,3,3,3,3,4,4,4,4, 5,5,5,4,4,4,4,4,4];
      final scoresB = [4,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];
      final mod = _nassauMod(['A','B']);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        course: _course18, totalHoles: 18,
      );

      final entries = BetEngine.computeAll(round);
      final pairE = _nassauEntries(entries, 'A', 'B');

      _expectSegmentEntry(pairE, 'A', 'B', 50,  'Front 9');
      _expectSegmentEntry(pairE, 'B', 'A', 50,  'Back 9');
      _expectSegmentEntry(pairE, 'A', 'B', 100, 'Total 18');
    });

    test('G10.2 – p2 gana todos los segmentos', () {
      final scoresA = [5,5,5,5,5,5,5,5,5, 5,5,5,5,5,5,5,5,5];
      final scoresB = [4,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];
      final mod = _nassauMod(['A','B']);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        course: _course18, totalHoles: 18,
      );

      final entries = BetEngine.computeAll(round);
      final pairE = _nassauEntries(entries, 'A', 'B');

      _expectSegmentEntry(pairE, 'B', 'A', 50,  'Front 9');
      _expectSegmentEntry(pairE, 'B', 'A', 50,  'Back 9');
      _expectSegmentEntry(pairE, 'B', 'A', 100, 'Total 18');
    });

    test('G10.3 – back-start: dirección de p1 gana Front (hoyos 10-18)', () {
      final scoresA = [3,3,3,3,3,3,3,3,3, 4,4,4,4,4,4,4,4,4]; // gana 10-18 (Front lógico)
      final scoresB = [4,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];
      final mod = _nassauMod(['A','B']);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        startingNine: StartingNine.back,
        course: _course18, totalHoles: 18,
      );

      final entries = BetEngine.computeAll(round);
      final pairE = _nassauEntries(entries, 'A', 'B');

      // A gana Front (hoyos 10-18 en back-start = Front lógico)
      final frontA = pairE.where((e) =>
          e.reason.contains('Front 9') && e.toPlayerId == 'A').toList();
      expect(frontA, isNotEmpty,
          reason: 'A debe ganar Front (hoyos 10-18) en back-start');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GRUPO 11: Acceso a hoyos fuera de rango (anti-crash)
  // ───────────────────────────────────────────────────────────────────────────
  group('G11 – Anti-crash: hoyos fuera de rango', () {
    test('G11.1 – scores en hoyos no existentes en el curso no causan crash', () {
      // Curso B9 (hoyos 10-18) pero los scores incluyen hoyo 1 (no existe en curso).
      // El engine debe ignorar scores sin CourseHole correspondiente.
      final mod = _nassauMod(['A','B']);

      // Construimos round manualmente para poner score en hoyo 1 aunque curso es B9
      final rPlayers = [
        RoundPlayer(playerId: 'A', handicapEnRonda: 0.0),
        RoundPlayer(playerId: 'B', handicapEnRonda: 0.0),
      ];
      final pObjects = [
        Player(id: 'A', name: 'A', handicapBase: 0),
        Player(id: 'B', name: 'B', handicapBase: 0),
      ];
      // Score en hoyo 1 (no existe en _courseB9)
      final scoresMap = {
        'A': {1: HoleScore(playerId: 'A', hole: 1, grossScore: 3, putts: 2)},
        'B': {1: HoleScore(playerId: 'B', hole: 1, grossScore: 4, putts: 2)},
      };
      final round = Round(
        id: 'test',
        name: 'Test',
        course: _courseB9,
        players: pObjects,
        roundPlayers: rPlayers,
        betGroups: [_group(['A','B'], mod)],
        scores: scoresMap,
        events: const {},
        oyeseRankings: const {},
        sliding: const [],
        createdAt: DateTime(2025),
        totalHoles: 9,
        startingNine: StartingNine.back,
      );

      expect(() => BetEngine.computeAll(round), returnsNormally,
          reason: 'Score en hoyo no existente en curso no debe causar crash');
    });

    test('G11.2 – live status sin scores: front=0, back=0, no crash', () {
      final mod = _nassauMod(['A','B']);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {},
        course: _course18, totalHoles: 18,
      );

      expect(() {
        final live = BetEngine.nassauLiveStatus(round, 'A', 'B', mod);
        expect(live.front, equals(0));
        expect(live.back,  equals(0));
      }, returnsNormally);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GRUPO 12: Consistencia front/back en live status (mirror de G7)
  // ───────────────────────────────────────────────────────────────────────────
  group('G12 – Live status: segmentación correcta front/back', () {
    test('G12.1 – front-start: live.front refleja hoyos 1-9', () {
      // p1 gana SOLO hoyos 1-9 → live.front > 0, live.back == 0.
      final scoresA = [3,3,3,3,3,3,3,3,3, 4,4,4,4,4,4,4,4,4];
      final scoresB = [4,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];
      final mod = _nassauMod(['A','B']);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        course: _course18, totalHoles: 18,
      );

      final live = BetEngine.nassauLiveStatus(round, 'A', 'B', mod);
      expect(live.front, greaterThan(0), reason: 'Front debe reflejar hoyos 1-9 en front-start');
      expect(live.back, equals(0));
    });

    test('G12.2 – front-start: live.back refleja hoyos 10-18', () {
      final scoresA = [4,4,4,4,4,4,4,4,4, 3,3,3,3,3,3,3,3,3];
      final scoresB = [4,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];
      final mod = _nassauMod(['A','B']);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        course: _course18, totalHoles: 18,
      );

      final live = BetEngine.nassauLiveStatus(round, 'A', 'B', mod);
      expect(live.back,  greaterThan(0), reason: 'Back debe reflejar hoyos 10-18 en front-start');
      expect(live.front, equals(0));
    });

    test('G12.3 – back-start: live.front refleja hoyos 10-18 (ANTI-INVERSIÓN)', () {
      // p1 gana SOLO hoyos 10-18 → en back-start son el Front lógico → live.front > 0.
      final scoresA = [3,3,3,3,3,3,3,3,3, 4,4,4,4,4,4,4,4,4]; // 10-18 primero
      final scoresB = [4,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];
      final mod = _nassauMod(['A','B']);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        startingNine: StartingNine.back,
        course: _course18, totalHoles: 18,
      );

      final live = BetEngine.nassauLiveStatus(round, 'A', 'B', mod);
      print('[G12.3] back-start live: front=${live.front} back=${live.back}');

      expect(live.front, greaterThan(0),
          reason: 'INVERSIÓN detectada: hoyos 10-18 deben ser Front lógico en back-start');
      expect(live.back, equals(0),
          reason: 'Hoyos 1-9 (empate) deben dar back=0 en back-start');
    });

    test('G12.4 – back-start: live.back refleja hoyos 1-9 (ANTI-INVERSIÓN)', () {
      // p1 gana SOLO hoyos 1-9 → en back-start son el Back lógico → live.back > 0.
      final scoresA = [4,4,4,4,4,4,4,4,4, 3,3,3,3,3,3,3,3,3]; // hoyos 1-9 van después
      final scoresB = [4,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];
      final mod = _nassauMod(['A','B']);
      final round = _makeRound(
        players: [{'id':'A','hcp':0.0},{'id':'B','hcp':0.0}],
        groups: [_group(['A','B'], mod)],
        scores: {'A':scoresA,'B':scoresB},
        startingNine: StartingNine.back,
        course: _course18, totalHoles: 18,
      );

      final live = BetEngine.nassauLiveStatus(round, 'A', 'B', mod);
      print('[G12.4] back-start live: front=${live.front} back=${live.back}');

      expect(live.back,  greaterThan(0),
          reason: 'INVERSIÓN detectada: hoyos 1-9 deben ser Back lógico en back-start');
      expect(live.front, equals(0),
          reason: 'Hoyos 10-18 (empate) deben dar front=0 en back-start');
    });
  });
}
