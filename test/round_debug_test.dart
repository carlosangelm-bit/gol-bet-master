// ignore_for_file: avoid_print
// =============================================================================
// Tests de la Parte 1 — RoundDebug helpers
//
// Valida que:
//  1. explainSlidingPair reporta correctamente pairSliding
//  2. Reporta correctamente fallback legacy bilateral
//  3. Reporta correctamente fallback legacy unilateral
//  4. Reporta correctamente fallback HCP
//  5. recv(A,B) y recv(B,A) aparecen con signos correctos
//  6. explainModuleComputation funciona para Medal y Nassau
//  7. No truena en rondas parciales o vacías
//  8. explainRoundState produce output coherente
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/round_debug.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Cursos de test
// ─────────────────────────────────────────────────────────────────────────────

final _course18 = CourseInfo(
  name: 'Debug Test Course',
  holes: List.generate(18, (i) {
    final si = (i % 9) * 2 + (i < 9 ? 1 : 2);
    return CourseHole(hole: i + 1, par: 4, strokeIndex: si);
  }),
);

/// Curso con 4 par-3 (hoyos 3, 7, 12, 16) para tests de Oyeses.
final _coursePar3 = CourseInfo(
  name: 'Par3 Test Course',
  holes: List.generate(18, (i) {
    final h = i + 1;
    final isPar3 = [3, 7, 12, 16].contains(h);
    return CourseHole(hole: h, par: isPar3 ? 3 : 4, strokeIndex: i + 1);
  }),
);

// ─────────────────────────────────────────────────────────────────────────────
// Factory de Round mínimo para tests de debug
// ─────────────────────────────────────────────────────────────────────────────

Round _makeRound({
  required List<Map<String, dynamic>> players,
  required List<BetGroup> groups,
  Map<String, List<int>> scores = const {},
  int totalHoles = 18,
  StartingNine startingNine = StartingNine.front,
  CourseInfo? course,
  Map<String, Map<String, double>>? manuals,
  Map<String, double>? pairSlid,
  Map<int, OyeseRanking>? oyeseRankings,
}) {
  final c = course ?? _course18;

  final rPlayers = players.map((p) {
    final pid = p['id'] as String;
    final hcp = (p['hcp'] as num).toDouble();
    return RoundPlayer(
      playerId: pid,
      handicapEnRonda: hcp,
      manualHandicaps: manuals?[pid] ?? {},
    );
  }).toList();

  final pObjects = players
      .map((p) => Player(
            id: p['id'] as String,
            name: (p['name'] as String?) ?? (p['id'] as String),
            handicapBase: (p['hcp'] as num).toDouble(),
          ))
      .toList();

  final holeNums = startingNine == StartingNine.back
      ? [...List.generate(9, (i) => i + 10), ...List.generate(9, (i) => i + 1)]
      : List.generate(c.holes.length, (i) => c.holes[i].hole);

  final scoresMap = <String, Map<int, HoleScore>>{};
  for (final entry in scores.entries) {
    final pid = entry.key;
    final vals = entry.value;
    final holeMap = <int, HoleScore>{};
    for (int i = 0; i < vals.length && i < holeNums.length; i++) {
      if (vals[i] > 0) {
        final h = holeNums[i];
        holeMap[h] = HoleScore(playerId: pid, hole: h, grossScore: vals[i], putts: 2);
      }
    }
    if (holeMap.isNotEmpty) scoresMap[pid] = holeMap;
  }

  return Round(
    id: 'debug-test',
    name: 'Debug Round',
    course: c,
    players: pObjects,
    roundPlayers: rPlayers,
    betGroups: groups,
    scores: scoresMap,
    events: const {},
    oyeseRankings: oyeseRankings ?? const {},
    sliding: const [],
    createdAt: DateTime(2025, 1, 1),
    totalHoles: totalHoles,
    startingNine: startingNine,
    pairSliding: pairSlid ?? const {},
  );
}

BetModuleInstance _nassauMod(List<String> pids) =>
    BetModuleInstance.defaultFor(BetModuleType.nassau, pids).copyWith(
      nassauConfig: const NassauConfig(
        frontValue: 50, backValue: 50, totalValue: 100,
        mode: GrossNetMode.gross,
      ),
    );

BetModuleInstance _medalMod(List<String> pids, {bool allVsAll = false}) =>
    BetModuleInstance.defaultFor(BetModuleType.medal, pids).copyWith(
      medalConfig: const MedalConfig(value: 100, mode: GrossNetMode.gross),
      formatMode: allVsAll ? BetFormatMode.allVsAll : BetFormatMode.onePot,
    );

BetModuleInstance _oyesesMod(List<String> pids) =>
    BetModuleInstance.defaultFor(BetModuleType.oyeses, pids).copyWith(
      oyesesConfig: const OyesesConfig(value: 50),
    );

BetGroup _group(List<String> pids, BetModuleInstance mod) => BetGroup(
      id: 'g1',
      name: 'G1',
      format: PartidaFormat.allInOnePot,
      playerIds: pids,
      modules: [mod],
    );

// ─────────────────────────────────────────────────────────────────────────────
// TESTS
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // GRUPO D1 — explainSlidingPair: fuentes correctas
  // ─────────────────────────────────────────────────────────────────────────
  group('D1 – explainSlidingPair: fuente correcta', () {

    test('D1.1 – pairSliding canónico: reporta source=pairSliding y recv correcto', () {
      // pairSliding['A|B'] = -5 → A da 5 a B → recv(A,B)=-5, recv(B,A)=+5
      final round = _makeRound(
        players: [{'id': 'A', 'hcp': 10.0}, {'id': 'B', 'hcp': 15.0}],
        groups: [_group(['A', 'B'], _nassauMod(['A', 'B']))],
        pairSlid: {'A|B': -5.0},
      );

      final report = RoundDebug.explainSlidingPair(round, 'A', 'B');
      print('[D1.1]\n$report');

      // La clave canónica debe aparecer
      expect(report, contains('pairKey=A|B'));
      // El valor almacenado
      expect(report, contains('pairSliding[A|B]=-5'));
      // recv(A,B) = -5
      expect(report, contains('recv(A,B)=-5.00'));
      // recv(B,A) = +5
      expect(report, contains('recv(B,A)=+5.00'));
      // Fuente correcta
      expect(report, contains('pairSliding (canónico)'));
    });

    test('D1.2 – pairSliding positivo: recv(A,B)=+5, recv(B,A)=-5', () {
      final round = _makeRound(
        players: [{'id': 'A', 'hcp': 15.0}, {'id': 'B', 'hcp': 10.0}],
        groups: [_group(['A', 'B'], _nassauMod(['A', 'B']))],
        pairSlid: {'A|B': 5.0},
      );

      final report = RoundDebug.explainSlidingPair(round, 'A', 'B');
      print('[D1.2]\n$report');

      expect(report, contains('recv(A,B)=+5.00'));
      expect(report, contains('recv(B,A)=-5.00'));
      expect(report, contains('pairSliding (canónico)'));
    });

    test('D1.3 – override explícito 0: se reporta nota de override', () {
      final round = _makeRound(
        players: [{'id': 'A', 'hcp': 10.0}, {'id': 'B', 'hcp': 15.0}],
        groups: [_group(['A', 'B'], _nassauMod(['A', 'B']))],
        pairSlid: {'A|B': 0.0},
      );

      final report = RoundDebug.explainSlidingPair(round, 'A', 'B');
      print('[D1.3]\n$report');

      expect(report, contains('Override explícito'));
      expect(report, contains('recv(A,B)=+0.00'));
      expect(report, contains('recv(B,A)=+0.00'));
    });

    test('D1.4 – legacy bilateral consistente: source=legacy bilateral', () {
      // manual[A][B] = -5, manual[B][A] = +5 → consistente
      final round = _makeRound(
        players: [{'id': 'A', 'hcp': 10.0}, {'id': 'B', 'hcp': 15.0}],
        groups: [_group(['A', 'B'], _nassauMod(['A', 'B']))],
        manuals: {
          'A': {'B': -5.0},
          'B': {'A': 5.0},
        },
      );

      final report = RoundDebug.explainSlidingPair(round, 'A', 'B');
      print('[D1.4]\n$report');

      expect(report, contains('legacy manualHandicaps (bilateral consistente)'));
      expect(report, contains('recv(A,B)=-5.00'));
      expect(report, contains('recv(B,A)=+5.00'));
      // pairSliding debe aparecer como <no existe>
      expect(report, contains('<no existe>'));
    });

    test('D1.5 – legacy unilateral (solo manual[A][B]): source=legacy unilateral', () {
      final round = _makeRound(
        players: [{'id': 'A', 'hcp': 10.0}, {'id': 'B', 'hcp': 15.0}],
        groups: [_group(['A', 'B'], _nassauMod(['A', 'B']))],
        manuals: {
          'A': {'B': -5.0},
          // B no tiene manual para A
        },
      );

      final report = RoundDebug.explainSlidingPair(round, 'A', 'B');
      print('[D1.5]\n$report');

      expect(report, contains('legacy manualHandicaps (unilateral)'));
      expect(report, contains('recv(A,B)=-5.00'));
      // B,A debe ser el inverso: +5
      expect(report, contains('recv(B,A)=+5.00'));
    });

    test('D1.6 – fallback HCP: source=hcp fallback con diferencia correcta', () {
      // hcp(A)=10, hcp(B)=16 → recv(A,B) = 10-16 = -6
      final round = _makeRound(
        players: [{'id': 'A', 'hcp': 10.0}, {'id': 'B', 'hcp': 16.0}],
        groups: [_group(['A', 'B'], _nassauMod(['A', 'B']))],
        // sin manuals ni pairSliding
      );

      final report = RoundDebug.explainSlidingPair(round, 'A', 'B');
      print('[D1.6]\n$report');

      expect(report, contains('hcp fallback'));
      expect(report, contains('recv(A,B)=-6.00'));
      expect(report, contains('recv(B,A)=+6.00'));
      expect(report, contains('hcp(A)=10.0'));
      expect(report, contains('hcp(B)=16.0'));
    });

    test('D1.7 – inconsistencia legacy: reporta ERROR y detalla los valores', () {
      // manual[A][B] = -5, manual[B][A] = +4 (no son opuestos → inconsistencia)
      final round = _makeRound(
        players: [{'id': 'A', 'hcp': 10.0}, {'id': 'B', 'hcp': 15.0}],
        groups: [_group(['A', 'B'], _nassauMod(['A', 'B']))],
        manuals: {
          'A': {'B': -5.0},
          'B': {'A': 4.0},  // ← inconsistente
        },
      );

      final report = RoundDebug.explainSlidingPair(round, 'A', 'B');
      print('[D1.7]\n$report');

      // Fuente = inconsistency
      expect(report, contains('INCONSISTENCIA'));
      // Debe mostrar los valores en conflicto
      expect(report, contains('-5'));
      expect(report, contains('4'));
    });

    test('D1.8 – pairSliding tiene prioridad sobre legacy manual', () {
      // pairSliding['A|B'] = -3, pero también hay manual[A][B] = -5
      // El engine debe usar pairSliding → recv = -3
      final round = _makeRound(
        players: [{'id': 'A', 'hcp': 10.0}, {'id': 'B', 'hcp': 15.0}],
        groups: [_group(['A', 'B'], _nassauMod(['A', 'B']))],
        pairSlid: {'A|B': -3.0},
        manuals: {'A': {'B': -5.0}},
      );

      final report = RoundDebug.explainSlidingPair(round, 'A', 'B');
      print('[D1.8]\n$report');

      expect(report, contains('pairSliding (canónico)'));
      expect(report, contains('recv(A,B)=-3.00'));
    });

    test('D1.9 – signos correctos cuando B.id < A.id (orden lexicográfico inverso)', () {
      // 'X' > 'A' → clave canónica = 'A|X'
      // pairSliding['A|X'] = +7 → A recibe 7 de X
      final round = _makeRound(
        players: [{'id': 'X', 'hcp': 5.0}, {'id': 'A', 'hcp': 12.0}],
        groups: [_group(['X', 'A'], _nassauMod(['X', 'A']))],
        pairSlid: {'A|X': 7.0},  // A es lowId → A recibe +7
      );

      // recv(A, X) debe ser +7 (A recibe de X)
      final recvAX = BetEngine.strokesP1ReceivesFromP2(round, 'A', 'X');
      expect(recvAX, closeTo(7.0, 0.01));

      // recv(X, A) debe ser -7 (X da a A)
      final recvXA = BetEngine.strokesP1ReceivesFromP2(round, 'X', 'A');
      expect(recvXA, closeTo(-7.0, 0.01));

      final report = RoundDebug.explainSlidingPair(round, 'X', 'A');
      print('[D1.9]\n$report');

      expect(report, contains('pairKey=A|X'));
      expect(report, contains('recv(X,A)=-7.00'));
      expect(report, contains('recv(A,X)=+7.00'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // GRUPO D2 — explainModuleComputation
  // ─────────────────────────────────────────────────────────────────────────
  group('D2 – explainModuleComputation', () {

    test('D2.1 – Nassau: imprime segmentos front/back y entries correctas', () {
      // A gana todo el Front (H1-H9), B gana todo el Back (H10-H18)
      final scoresA = [3,3,3,3,3,3,3,3,3, 5,5,5,5,5,5,5,5,5];
      final scoresB = [4,4,4,4,4,4,4,4,4, 4,4,4,4,4,4,4,4,4];
      final mod = _nassauMod(['A', 'B']);
      final group = _group(['A', 'B'], mod);
      final round = _makeRound(
        players: [{'id': 'A', 'hcp': 0.0}, {'id': 'B', 'hcp': 0.0}],
        groups: [group],
        scores: {'A': scoresA, 'B': scoresB},
      );

      final report = RoundDebug.explainModuleComputation(round, group, mod);
      print('[D2.1]\n$report');

      // Debe mencionar el tipo
      expect(report, contains('nassau'));
      // Debe tener detalle de deltas
      expect(report, contains('deltas:'));
      // Debe tener front y back
      expect(report, contains('Front='));
      expect(report, contains('Back='));
      // Ledger entries: A gana Front, B gana Back
      expect(report, contains('B → A'));  // Front: B paga a A
      expect(report, contains('A → B'));  // Back: A paga a B
    });

    test('D2.2 – Medal onePot: imprime gross de cada jugador', () {
      final scores18 = List.generate(18, (_) => 4);
      final mod = _medalMod(['A', 'B']);
      final group = _group(['A', 'B'], mod);
      final round = _makeRound(
        players: [{'id': 'A', 'hcp': 0.0}, {'id': 'B', 'hcp': 0.0}],
        groups: [group],
        scores: {'A': scores18, 'B': scores18},
      );

      final report = RoundDebug.explainModuleComputation(round, group, mod);
      print('[D2.2]\n$report');

      expect(report, contains('medal'));
      expect(report, contains('gross(A)='));
      // Empate → sin entries
      expect(report, contains('sin entradas'));
    });

    test('D2.3 – Medal allVsAll con ganador: entries con dirección correcta', () {
      // A gross total = 72 (4x18), B gross = 80 (más alto = pierde)
      final scoresA = List.generate(18, (_) => 4);
      final scoresB = List.generate(18, (_) => 5);
      final mod = _medalMod(['A', 'B'], allVsAll: true);
      final group = _group(['A', 'B'], mod);
      final round = _makeRound(
        players: [{'id': 'A', 'hcp': 0.0}, {'id': 'B', 'hcp': 0.0}],
        groups: [group],
        scores: {'A': scoresA, 'B': scoresB},
      );

      final report = RoundDebug.explainModuleComputation(round, group, mod);
      print('[D2.3]\n$report');

      expect(report, contains('allVsAll'));
      // A gana → B paga a A
      expect(report, contains('B → A'));
    });

    test('D2.4 – ronda vacía (sin scores): no truena, imprime "sin entradas"', () {
      final mod = _nassauMod(['A', 'B']);
      final group = _group(['A', 'B'], mod);
      final round = _makeRound(
        players: [{'id': 'A', 'hcp': 0.0}, {'id': 'B', 'hcp': 0.0}],
        groups: [group],
        scores: {},  // sin scores
      );

      expect(
        () => RoundDebug.explainModuleComputation(round, group, mod),
        returnsNormally,
      );
      final report = RoundDebug.explainModuleComputation(round, group, mod);
      print('[D2.4]\n$report');
      expect(report, contains('sin entradas'));
    });

    test('D2.5 – ronda parcial (solo 5 hoyos): no truena', () {
      final scoresA = [3, 3, 3, 3, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
      final scoresB = [4, 4, 4, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
      final mod = _nassauMod(['A', 'B']);
      final group = _group(['A', 'B'], mod);
      final round = _makeRound(
        players: [{'id': 'A', 'hcp': 0.0}, {'id': 'B', 'hcp': 0.0}],
        groups: [group],
        scores: {'A': scoresA, 'B': scoresB},
      );

      expect(
        () => RoundDebug.explainModuleComputation(round, group, mod),
        returnsNormally,
      );
      final report = RoundDebug.explainModuleComputation(round, group, mod);
      print('[D2.5]\n$report');
      // Debe tener deltas y al menos Front entry
      expect(report, isNotEmpty);
    });

    test('D2.6 – Oyeses: imprime ranking por hoyo', () {
      // 2 par-3 con ranking definido (H3 y H7)
      final mod = _oyesesMod(['A', 'B', 'C']);
      final group = _group(['A', 'B', 'C'], mod);
      final round = _makeRound(
        players: [
          {'id': 'A', 'hcp': 0.0},
          {'id': 'B', 'hcp': 0.0},
          {'id': 'C', 'hcp': 0.0},
        ],
        groups: [group],
        course: _coursePar3,
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A', 'B', 'C']),
          7: OyeseRanking(hole: 7, ranking: ['B', 'A', 'C']),
        },
      );

      final report = RoundDebug.explainModuleComputation(round, group, mod);
      print('[D2.6]\n$report');

      expect(report, contains('H3'));
      expect(report, contains('H7'));
      expect(report, contains('1°=A'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // GRUPO D3 — explainRoundState
  // ─────────────────────────────────────────────────────────────────────────
  group('D3 – explainRoundState', () {

    test('D3.1 – ronda básica: contiene id, isLive, startingNine, players', () {
      final mod = _nassauMod(['A', 'B']);
      final group = _group(['A', 'B'], mod);
      final round = _makeRound(
        players: [{'id': 'A', 'hcp': 10.0}, {'id': 'B', 'hcp': 16.0}],
        groups: [group],
      );

      final report = RoundDebug.explainRoundState(round, group);
      print('[D3.1]\n$report');

      expect(report, contains('id=debug-test'));
      expect(report, contains('isLive=false'));
      expect(report, contains('startingNine=front'));
      expect(report, contains('totalHoles=18'));
      // Debe listar los dos jugadores con sus handicaps
      expect(report, contains('A  hcp=10.0'));
      expect(report, contains('B  hcp=16.0'));
      // Debe listar los módulos
      expect(report, contains('nassau'));
    });

    test('D3.2 – con pairSliding: muestra el mapa canónico', () {
      final mod = _nassauMod(['A', 'B']);
      final group = _group(['A', 'B'], mod);
      final round = _makeRound(
        players: [{'id': 'A', 'hcp': 10.0}, {'id': 'B', 'hcp': 15.0}],
        groups: [group],
        pairSlid: {'A|B': -5.0},
      );

      final report = RoundDebug.explainRoundState(round, group);
      print('[D3.2]\n$report');

      expect(report, contains('A|B'));
      expect(report, contains('-5'));
      // Sin errores de validación
      expect(report, contains('sin errores de validación'));
    });

    test('D3.3 – con legacy manuals: los muestra en la sección roundPlayers', () {
      final mod = _nassauMod(['A', 'B']);
      final group = _group(['A', 'B'], mod);
      final round = _makeRound(
        players: [{'id': 'A', 'hcp': 10.0}, {'id': 'B', 'hcp': 15.0}],
        groups: [group],
        manuals: {'A': {'B': -5.0}},
      );

      final report = RoundDebug.explainRoundState(round, group);
      print('[D3.3]\n$report');

      expect(report, contains('legacy manual[A][B]=-5'));
    });

    test('D3.4 – con pairSliding inválido: detecta errores de validación', () {
      // Clave mal formada + valor NaN (construimos el mapa directamente)
      final mod = _nassauMod(['A', 'B']);
      final group = _group(['A', 'B'], mod);

      // Crear round con pairSliding que tiene entrada non-canonical (B|A en vez de A|B)
      final round = Round(
        id: 'debug-test',
        name: 'Debug Round',
        course: _course18,
        players: [
          Player(id: 'A', name: 'A', handicapBase: 10),
          Player(id: 'B', name: 'B', handicapBase: 15),
        ],
        roundPlayers: [
          RoundPlayer(playerId: 'A', handicapEnRonda: 10),
          RoundPlayer(playerId: 'B', handicapEnRonda: 15),
        ],
        betGroups: [group],
        scores: const {},
        events: const {},
        oyeseRankings: const {},
        sliding: const [],
        createdAt: DateTime(2025),
        totalHoles: 18,
        // Clave no canónica (B > A → debería ser A|B)
        pairSliding: const {'B|A': -5.0},
      );

      final report = RoundDebug.explainRoundState(round, group);
      print('[D3.4]\n$report');

      // Debe detectar el error de clave no canónica
      expect(report, contains('Errores detectados'));
    });

    test('D3.5 – con oyeseRankings: los muestra correctamente', () {
      final mod = _oyesesMod(['A', 'B']);
      final group = _group(['A', 'B'], mod);
      final round = _makeRound(
        players: [{'id': 'A', 'hcp': 0.0}, {'id': 'B', 'hcp': 0.0}],
        groups: [group],
        course: _coursePar3,
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A', 'B']),
        },
      );

      final report = RoundDebug.explainRoundState(round, group);
      print('[D3.5]\n$report');

      expect(report, contains('oyeseRankings'));
      expect(report, contains('H3'));
      expect(report, contains('1°=A'));
    });

    test('D3.6 – ronda sin scores: no truena, muestra 0 hoyos jugados', () {
      final mod = _nassauMod(['A', 'B']);
      final group = _group(['A', 'B'], mod);
      final round = _makeRound(
        players: [{'id': 'A', 'hcp': 0.0}, {'id': 'B', 'hcp': 0.0}],
        groups: [group],
        scores: {},
      );

      expect(
        () => RoundDebug.explainRoundState(round, group),
        returnsNormally,
      );
      final report = RoundDebug.explainRoundState(round, group);
      expect(report, contains('0/18 hoyos'));
    });

    test('D3.7 – ronda isLive + liveCode: aparecen en el reporte', () {
      final mod = _nassauMod(['A', 'B']);
      final group = _group(['A', 'B'], mod);
      final baseRound = _makeRound(
        players: [{'id': 'A', 'hcp': 0.0}, {'id': 'B', 'hcp': 0.0}],
        groups: [group],
      );
      final liveRound = baseRound.copyWith(isLive: true, liveCode: 'XYZ-999');

      final report = RoundDebug.explainRoundState(liveRound, group);
      print('[D3.7]\n$report');

      expect(report, contains('isLive=true'));
      expect(report, contains('liveCode=XYZ-999'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // GRUPO D4 — Invariantes críticos de signos
  // ─────────────────────────────────────────────────────────────────────────
  group('D4 – Invariantes de signos en recv', () {

    test('D4.1 – recv(A,B) + recv(B,A) = 0 para pairSliding', () {
      final round = _makeRound(
        players: [{'id': 'A', 'hcp': 0.0}, {'id': 'B', 'hcp': 0.0}],
        groups: [_group(['A', 'B'], _nassauMod(['A', 'B']))],
        pairSlid: {'A|B': -5.0},
      );

      final recvAB = BetEngine.strokesP1ReceivesFromP2(round, 'A', 'B');
      final recvBA = BetEngine.strokesP1ReceivesFromP2(round, 'B', 'A');
      expect((recvAB + recvBA).abs(), lessThan(0.001),
          reason: 'recv(A,B) + recv(B,A) debe ser 0');
    });

    test('D4.2 – recv(A,B) + recv(B,A) = 0 para HCP fallback', () {
      final round = _makeRound(
        players: [{'id': 'A', 'hcp': 10.0}, {'id': 'B', 'hcp': 16.0}],
        groups: [_group(['A', 'B'], _nassauMod(['A', 'B']))],
      );

      final recvAB = BetEngine.strokesP1ReceivesFromP2(round, 'A', 'B');
      final recvBA = BetEngine.strokesP1ReceivesFromP2(round, 'B', 'A');
      expect((recvAB + recvBA).abs(), lessThan(0.001));
    });

    test('D4.3 – recv(A,B) + recv(B,A) = 0 para legacy unilateral', () {
      final round = _makeRound(
        players: [{'id': 'A', 'hcp': 0.0}, {'id': 'B', 'hcp': 0.0}],
        groups: [_group(['A', 'B'], _nassauMod(['A', 'B']))],
        manuals: {'A': {'B': -7.0}},
      );

      final recvAB = BetEngine.strokesP1ReceivesFromP2(round, 'A', 'B');
      final recvBA = BetEngine.strokesP1ReceivesFromP2(round, 'B', 'A');
      expect((recvAB + recvBA).abs(), lessThan(0.001));
    });

    test('D4.4 – explainSlidingPair contiene signos opuestos para cualquier par', () {
      for (final sliding in [-10.0, -5.0, 0.0, 5.0, 10.0]) {
        final round = _makeRound(
          players: [{'id': 'A', 'hcp': 0.0}, {'id': 'B', 'hcp': 0.0}],
          groups: [_group(['A', 'B'], _nassauMod(['A', 'B']))],
          pairSlid: {'A|B': sliding},
        );

        final recvAB = BetEngine.strokesP1ReceivesFromP2(round, 'A', 'B');
        final recvBA = BetEngine.strokesP1ReceivesFromP2(round, 'B', 'A');
        expect((recvAB + recvBA).abs(), lessThan(0.001),
            reason: 'Fallo para sliding=$sliding');
      }
    });
  });
}
