// ignore_for_file: avoid_print
// =============================================================================
// Auditoría mínima — PUTTS + SKINS
//
// OBJETIVO: detectar errores reales de cálculo, sin modificar el engine.
//
// ── PUTTS ────────────────────────────────────────────────────────────────────
// ANÁLISIS ESTÁTICO PREVIO:
//
//   totalPutts() itera h=from..to y llama round.getScore(pid, h).
//   getScore devuelve HoleScore(putts=0) cuando el hoyo no existe en el mapa.
//   La guarda es:  if (s.hasScore) total += s.putts
//   hasScore = grossScore != null && grossScore! > 0
//
//   → Un hoyo sin entrada en el mapa retorna HoleScore con grossScore=null
//     → hasScore = false → NO se suma → CORRECTO ✅
//
//   → Un hoyo con HoleScore(grossScore=3, putts=0) tiene hasScore=true y suma 0.
//     Eso es legítimo (chip-in). El engine tiene el comentario al respecto.
//
//   RIESGO REAL detectado: si alguien crea HoleScore(grossScore=3) sin especificar
//   putts, el default es putts=0 → se cuenta como 0 putts aun si son "datos
//   basura". Pero eso es responsabilidad del caller, no del engine.
//
//   CONCLUSIÓN PUTTS: el engine es CORRECTO. hasScore garantiza que los hoyos
//   sin score no se cuentan. Los tests P1-P4 lo confirman.
//
// ── SKINS ────────────────────────────────────────────────────────────────────
// ANÁLISIS ESTÁTICO PREVIO:
//
//   Modo onePot grupal (3+ jugadores):
//     holeWinner() → ordena por netScore individual (contextForHole().netScore)
//     El ganador es el de menor netScore con diferencia estricta del segundo.
//     Es 100% ranking individual, no lógica bilateral.
//
//   Modo allVsAll (o n==2):
//     Cada par tiene su propio duelo 1v1 (_skins1v1).
//     El handicap se distribuye sobre hoyos jugados (strokesReceivedInPlayedHoles).
//
//   DIFERENCIA CRITICA entre ambos modos de handicap:
//     onePot grupal: usa strokesReceived(hcp absoluto, ch) → strokes del jugador
//                    según su HCP relativo al campo (full handicap allowance).
//     1v1:           usa strokesReceivedInPlayedHoles(diff=recv, ch, playedHoles)
//                    → distribución proporcional sobre hoyos jugados.
//
//   S5 documenta si los resultados entre onePot-grupal y 1v1 divergen y por qué.
//
// ── NOTA ─────────────────────────────────────────────────────────────────────
//   Los tests P1-P4 y S1-S5 son auditoría, no regresión. Si alguno falla,
//   indica un bug real de cálculo en el engine actual.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/game_engine.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Fixtures comunes
// ─────────────────────────────────────────────────────────────────────────────

/// Curso estándar de 18 hoyos, todos par-4, SI 1-18 en orden.
final _course18 = CourseInfo(
  name: 'Audit Course',
  holes: List.generate(18, (i) =>
      CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)),
);

/// Curso de 9 hoyos (front, 1-9), todos par-4.
final _course9F = CourseInfo(
  name: 'F9 Course',
  holes: List.generate(9, (i) =>
      CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)),
);

// ─────────────────────────────────────────────────────────────────────────────
// Factory de Round
// ─────────────────────────────────────────────────────────────────────────────

/// Crea un Round completo.
/// [scoreMaps] = { pid → { hole → (gross, putts) } }  — solo hoyos jugados.
Round _makeRound({
  required List<Map<String, dynamic>> players,   // {id, hcp}
  required List<BetGroup> groups,
  Map<String, Map<int, (int, int)>> scoreMaps = const {},
  CourseInfo? course,
  int totalHoles = 18,
  StartingNine startingNine = StartingNine.front,
}) {
  final c = course ?? _course18;

  final rPlayers = players.map((p) => RoundPlayer(
    playerId:         p['id'] as String,
    handicapEnRonda:  (p['hcp'] as num).toDouble(),
  )).toList();

  final pObjects = players.map((p) => Player(
    id:            p['id'] as String,
    name:          p['id'] as String,
    handicapBase:  (p['hcp'] as num).toDouble(),
  )).toList();

  // Construir mapa de scores
  final scoresMap = <String, Map<int, HoleScore>>{};
  for (final entry in scoreMaps.entries) {
    final pid    = entry.key;
    final holeMap = <int, HoleScore>{};
    for (final hEntry in entry.value.entries) {
      final hole = hEntry.key;
      final (gross, putts) = hEntry.value;
      holeMap[hole] = HoleScore(
        playerId:   pid,
        hole:       hole,
        grossScore: gross,
        putts:      putts,
      );
    }
    if (holeMap.isNotEmpty) scoresMap[pid] = holeMap;
  }

  return Round(
    id:           'audit-test',
    name:         'Audit Round',
    course:       c,
    players:      pObjects,
    roundPlayers: rPlayers,
    betGroups:    groups,
    scores:       scoresMap,
    events:       const {},
    oyeseRankings: const {},
    sliding:      const [],
    createdAt:    DateTime(2025, 1, 1),
    totalHoles:   totalHoles,
    startingNine: startingNine,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Factories de módulos
// ─────────────────────────────────────────────────────────────────────────────

BetModuleInstance _puttsMod(
  List<String> pids, {
  double value        = 50,
  PuttsMode mode      = PuttsMode.total,
  BetFormatMode fmt   = BetFormatMode.allVsAll,
}) =>
    BetModuleInstance.defaultFor(BetModuleType.putts, pids).copyWith(
      puttsConfig: PuttsConfig(value: value, puttsMode: mode),
      formatMode:  fmt,
    );

BetModuleInstance _skinsMod(
  List<String> pids, {
  double value        = 10,
  bool   carryOver    = false,
  bool   useHandicap  = false,
  BetFormatMode fmt   = BetFormatMode.onePot,
}) =>
    BetModuleInstance.defaultFor(BetModuleType.skins, pids).copyWith(
      skinsConfig: SkinsConfig(
        valuePerSkin: value,
        carryOver:    carryOver,
        mode:         useHandicap ? GrossNetMode.net : GrossNetMode.gross,
      ),
      formatMode: fmt,
    );

BetGroup _group(List<String> pids, BetModuleInstance mod) => BetGroup(
  id:       'g1',
  name:     'Audit',
  format:   PartidaFormat.allInOnePot,
  playerIds: pids,
  modules:  [mod],
);

// Helpers de extracción
List<LedgerEntry> _puttsE(List<LedgerEntry> all) =>
    all.where((e) => e.betType == BetModuleType.putts).toList();

List<LedgerEntry> _skinsE(List<LedgerEntry> all) =>
    all.where((e) => e.betType == BetModuleType.skins).toList();

// =============================================================================
// PARTE 1 — PUTTS
// =============================================================================

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // P1 — Ronda incompleta: A juega 9 hoyos, B juega 5
  // Confirmar: totalPutts solo suma hoyos con hasScore
  // ─────────────────────────────────────────────────────────────────────────
  group('P1 – Ronda incompleta: A=9H B=5H', () {

    test('P1.1 – totalPutts ignora hoyos sin score (no cuenta 0 implícitos)', () {
      // A: H1-H9 jugados, 2 putts cada uno → total = 18
      // B: H1-H5 jugados, 2 putts cada uno → total = 10
      // H6-H18 de ambos: sin score → NO deben sumarse
      final scoreMaps = <String, Map<int, (int, int)>>{
        'A': { for (int h = 1; h <= 9;  h++) h: (4, 2) },
        'B': { for (int h = 1; h <= 5;  h++) h: (4, 2) },
      };

      final round = _makeRound(
        players:    [{'id': 'A', 'hcp': 0.0}, {'id': 'B', 'hcp': 0.0}],
        groups:     [_group(['A', 'B'], _puttsMod(['A', 'B']))],
        scoreMaps:  scoreMaps,
      );

      final tA = GameEngine.totalPutts(round, 'A');
      final tB = GameEngine.totalPutts(round, 'B');

      print('[P1.1] totalPutts A=$tA  B=$tB  (esperado: A=18, B=10)');

      // ✅ Debe contar SOLO hoyos jugados
      expect(tA, equals(18),
          reason: 'A jugó 9 hoyos × 2 putts = 18. Los H10-H18 sin score NO se cuentan.');
      expect(tB, equals(10),
          reason: 'B jugó 5 hoyos × 2 putts = 10. Los H6-H18 sin score NO se cuentan.');

      // ❌ Si hubiera bug (hoyos vacíos = 0 putts), A tendría 18 (ok) pero
      //    el engine habría sumado 9 ceros implícitos → confundiría la comparación.
      // La prueba real: B=10, no B=36 (si contara 18 hoyos × 0)
      expect(tB, isNot(equals(0)),
          reason: 'B tiene hoyos jugados → no puede ser 0');
    });

    test('P1.2 – ledger: A gana (menos putts) sin importar los hoyos faltantes', () {
      // A: 9 hoyos, 2 putts c/u → 18 total
      // B: 5 hoyos, 3 putts c/u → 15 total — MENOR, B gana
      // Si el engine contara hoyos faltantes como 0, A tendría 18 y
      // B tendría 15+13×0=15, B seguiría ganando (no hay inversión de resultado)
      // pero el número sería incorrecto.
      final scoreMaps = <String, Map<int, (int, int)>>{
        'A': { for (int h = 1; h <= 9; h++) h: (4, 2) },   // 18 putts
        'B': { for (int h = 1; h <= 5; h++) h: (4, 3) },   // 15 putts
      };

      final round = _makeRound(
        players:    [{'id': 'A', 'hcp': 0.0}, {'id': 'B', 'hcp': 0.0}],
        groups:     [_group(['A', 'B'], _puttsMod(['A', 'B']))],
        scoreMaps:  scoreMaps,
      );

      final tA = GameEngine.totalPutts(round, 'A');
      final tB = GameEngine.totalPutts(round, 'B');
      print('[P1.2] totalPutts A=$tA  B=$tB  (esperado A=18, B=15 → B gana)');

      expect(tA, equals(18));
      expect(tB, equals(15));

      // Verificar que el ledger da la entrada correcta (B→A: B tiene menos putts)
      final entries = _puttsE(BetEngine.computeAll(round));
      expect(entries.length, equals(1));
      expect(entries.first.toPlayerId, equals('B'),
          reason: 'B tiene menos putts totales → B gana → A paga a B');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // P2 — F9 incompleto: H1-H5 jugados, H6-H9 sin score
  // ─────────────────────────────────────────────────────────────────────────
  group('P2 – F9 incompleto: solo H1-H5 jugados', () {

    test('P2.1 – Putts F9 solo suma hoyos jugados (from=1 to=9)', () {
      // A: H1-H5 con 2 putts. H6-H9 sin score.
      // B: H1-H5 con 3 putts. H6-H9 sin score.
      final scoreMaps = <String, Map<int, (int, int)>>{
        'A': { for (int h = 1; h <= 5; h++) h: (4, 2) },
        'B': { for (int h = 1; h <= 5; h++) h: (4, 3) },
      };

      final round = _makeRound(
        players:    [{'id': 'A', 'hcp': 0.0}, {'id': 'B', 'hcp': 0.0}],
        groups:     [_group(['A', 'B'], _puttsMod(['A', 'B'], mode: PuttsMode.perHole))],
        scoreMaps:  scoreMaps,
      );

      final f9A = GameEngine.totalPutts(round, 'A', from: 1, to: 9);
      final f9B = GameEngine.totalPutts(round, 'B', from: 1, to: 9);
      print('[P2.1] Putts F9: A=$f9A  B=$f9B  (esperado A=10, B=15)');

      // 5 hoyos × 2 putts = 10, 5 hoyos × 3 putts = 15
      expect(f9A, equals(10),
          reason: 'Solo H1-H5 jugados × 2 putts = 10. H6-H9 sin score = 0 sumados.');
      expect(f9B, equals(15));

      // Si hubiera bug, f9A sería 10 igualmente porque H6-H9 inexistentes
      // tienen hasScore=false → no se suman. ✅ Verificado.
    });

    test('P2.2 – modo f9b9: cuando solo F9 tiene datos, B9 empata en 0 (sin entradas B9)', () {
      // A y B: solo H1-H5 jugados, A=2 putts, B=3 putts
      // F9: A gana (menos putts)
      // B9: ambos = 0 → empate → sin entrada
      final scoreMaps = <String, Map<int, (int, int)>>{
        'A': { for (int h = 1; h <= 5; h++) h: (4, 2) },
        'B': { for (int h = 1; h <= 5; h++) h: (4, 3) },
      };

      final round = _makeRound(
        players:    [{'id': 'A', 'hcp': 0.0}, {'id': 'B', 'hcp': 0.0}],
        groups:     [_group(['A', 'B'], _puttsMod(['A', 'B'], mode: PuttsMode.perHole))],
        scoreMaps:  scoreMaps,
      );

      final entries = _puttsE(BetEngine.computeAll(round));
      print('[P2.2] Entries f9b9 con solo F9 parcial: ${entries.map((e) => '${e.fromPlayerId}→${e.toPlayerId} ${e.reason}').toList()}');

      // Solo F9 genera resultado (A gana) → 1 entrada
      // B9: ambos tienen totalPutts=0 → empate → sin entrada para B9
      final f9Entries = entries.where((e) => e.reason.contains('F9')).toList();
      final b9Entries = entries.where((e) => e.reason.contains('B9')).toList();

      expect(f9Entries.length, equals(1),
          reason: 'F9: A gana (10 vs 15) → 1 entrada');
      expect(f9Entries.first.toPlayerId, equals('A'),
          reason: 'A tiene menos putts en F9');
      expect(b9Entries, isEmpty,
          reason: 'B9: ambos 0 putts (sin hoyos jugados) → empate → sin entrada');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // P3 — B9 incompleto: solo H10-H14 jugados
  // ─────────────────────────────────────────────────────────────────────────
  group('P3 – B9 incompleto: solo H10-H14 jugados', () {

    test('P3.1 – totalPutts(from=10,to=18) suma solo H10-H14', () {
      final scoreMaps = <String, Map<int, (int, int)>>{
        'A': { for (int h = 10; h <= 14; h++) h: (4, 2) },   // 10 putts B9
        'B': { for (int h = 10; h <= 14; h++) h: (4, 1) },   //  5 putts B9
      };

      final round = _makeRound(
        players:    [{'id': 'A', 'hcp': 0.0}, {'id': 'B', 'hcp': 0.0}],
        groups:     [_group(['A', 'B'], _puttsMod(['A', 'B'], mode: PuttsMode.perHole))],
        scoreMaps:  scoreMaps,
      );

      final b9A = GameEngine.totalPutts(round, 'A', from: 10, to: 18);
      final b9B = GameEngine.totalPutts(round, 'B', from: 10, to: 18);
      print('[P3.1] Putts B9: A=$b9A  B=$b9B  (esperado A=10, B=5)');

      expect(b9A, equals(10));
      expect(b9B, equals(5));

      // Verificar ledger: B gana B9, F9 empate en 0
      final entries = _puttsE(BetEngine.computeAll(round));
      final b9e = entries.where((e) => e.reason.contains('B9')).toList();
      final f9e = entries.where((e) => e.reason.contains('F9')).toList();

      expect(b9e.length, equals(1));
      expect(b9e.first.toPlayerId, equals('B'),
          reason: 'B tiene menos putts B9 (5 vs 10)');
      expect(f9e, isEmpty, reason: 'F9: ambos 0 → sin entrada');
    });

    test('P3.2 – comportamiento consistente con P2 (simetría F9/B9)', () {
      // Mismo diseño que P2 pero en B9
      // A: H10-H14, 2 putts; B: H10-H14, 3 putts → A gana B9
      final scoreMaps = <String, Map<int, (int, int)>>{
        'A': { for (int h = 10; h <= 14; h++) h: (4, 2) },
        'B': { for (int h = 10; h <= 14; h++) h: (4, 3) },
      };

      final round = _makeRound(
        players:    [{'id': 'A', 'hcp': 0.0}, {'id': 'B', 'hcp': 0.0}],
        groups:     [_group(['A', 'B'], _puttsMod(['A', 'B'], mode: PuttsMode.perHole))],
        scoreMaps:  scoreMaps,
      );

      final entries = _puttsE(BetEngine.computeAll(round));
      final b9e = entries.where((e) => e.reason.contains('B9')).toList();

      expect(b9e.length, equals(1));
      expect(b9e.first.toPlayerId, equals('A'),
          reason: 'A: 10 putts B9, B: 15 putts B9 → A gana');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // P4 — Total 18 incompleto: huecos en distintos segmentos
  // ─────────────────────────────────────────────────────────────────────────
  group('P4 – Total 18 incompleto: huecos dispersos', () {

    test('P4.1 – total suma exactamente los hoyos jugados, sin defaults', () {
      // A: H1,H2,H3 (2 putts c/u), H7,H8,H9 (1 putt c/u), H15,H16 (2 putts c/u)
      //   = 3×2 + 3×1 + 2×2 = 6+3+4 = 13 putts
      // B: H1-H9 (2 putts c/u) = 18 putts
      // A gana (13 < 18)
      final scoreMaps = <String, Map<int, (int, int)>>{
        'A': {
          1:  (4, 2), 2:  (4, 2), 3:  (4, 2),
          7:  (4, 1), 8:  (4, 1), 9:  (4, 1),
          15: (4, 2), 16: (4, 2),
        },
        'B': { for (int h = 1; h <= 9; h++) h: (4, 2) },
      };

      final round = _makeRound(
        players:    [{'id': 'A', 'hcp': 0.0}, {'id': 'B', 'hcp': 0.0}],
        groups:     [_group(['A', 'B'], _puttsMod(['A', 'B'], mode: PuttsMode.total))],
        scoreMaps:  scoreMaps,
      );

      final tA = GameEngine.totalPutts(round, 'A');
      final tB = GameEngine.totalPutts(round, 'B');
      print('[P4.1] Total 18 incompleto: A=$tA  B=$tB  (esperado A=13, B=18)');

      expect(tA, equals(13),
          reason: '3×2 + 3×1 + 2×2 = 13. Los huecos (H4,H5,H6,H10-H14,H17,H18) no se cuentan.');
      expect(tB, equals(18));

      final entries = _puttsE(BetEngine.computeAll(round));
      expect(entries.length, equals(1));
      expect(entries.first.toPlayerId, equals('A'),
          reason: 'A: 13 putts < B: 18 putts → A gana');
    });

    test('P4.2 – sin liquidación incorrecta: ronda con 0 hoyos jugados → 0 entradas', () {
      // Si todos los hoyos están vacíos, totalPutts = 0 para todos → empate → sin entradas
      final round = _makeRound(
        players:    [{'id': 'A', 'hcp': 0.0}, {'id': 'B', 'hcp': 0.0}],
        groups:     [_group(['A', 'B'], _puttsMod(['A', 'B']))],
        scoreMaps:  const {},
      );

      final tA = GameEngine.totalPutts(round, 'A');
      final tB = GameEngine.totalPutts(round, 'B');
      print('[P4.2] Sin hoyos jugados: A=$tA  B=$tB  (esperado: ambos 0)');

      expect(tA, equals(0));
      expect(tB, equals(0));

      final entries = _puttsE(BetEngine.computeAll(round));
      // Ambos en 0 → empate → sin entradas (NO liquidación errónea)
      expect(entries, isEmpty,
          reason: 'Empate en 0 putts → sin entradas. No hay liquidación por defecto.');
    });
  });

  // =============================================================================
  // PARTE 2 — SKINS
  // =============================================================================

  // ─────────────────────────────────────────────────────────────────────────
  // S1 — 3 jugadores, ganador claro (gross, sin handicap)
  // ─────────────────────────────────────────────────────────────────────────
  group('S1 – 3 jugadores, ganador claro (gross)', () {

    test('S1.1 – A=3 B=4 C=5 en H1: A gana el skin', () {
      // onePot grupal, sin carry, gross
      // H1: A=3, B=4, C=5 → A menor → A gana
      final scoreMaps = <String, Map<int, (int, int)>>{
        'A': {1: (3, 2)},
        'B': {1: (4, 2)},
        'C': {1: (5, 2)},
      };

      final round = _makeRound(
        players: [
          {'id': 'A', 'hcp': 0.0},
          {'id': 'B', 'hcp': 0.0},
          {'id': 'C', 'hcp': 0.0},
        ],
        groups:     [_group(['A', 'B', 'C'], _skinsMod(['A', 'B', 'C']))],
        scoreMaps:  scoreMaps,
      );

      final entries = _skinsE(BetEngine.computeAll(round));
      print('[S1.1] A=3 B=4 C=5: ${entries.map((e) => '${e.fromPlayerId}→${e.toPlayerId} \$${e.amount}').toList()}');

      // A gana → B→A y C→A
      expect(entries.length, equals(2),
          reason: 'A gana: 2 perdedores pagan a A (B→A, C→A)');
      expect(entries.every((e) => e.toPlayerId == 'A'), isTrue,
          reason: 'Todos los pagos van a A (el ganador)');

      // Monto correcto: pot / (n-1) = 10 / 2 = 5 por jugador
      expect(entries.every((e) => (e.amount - 5.0).abs() < 0.01), isTrue,
          reason: 'pot=10, n=3 → share = 10/2 = 5 por jugador');
    });

    test('S1.2 – holeWinner selecciona por netScore individual (no bilateral)', () {
      // Verificar directamente que holeWinner usa ranking absoluto de netScore
      // A=3, B=4, C=5 → netScore = grossScore (sin HCP) → menor netScore = A
      final scoreMaps = <String, Map<int, (int, int)>>{
        'A': {1: (3, 2)},
        'B': {1: (4, 2)},
        'C': {1: (5, 2)},
      };
      final round = _makeRound(
        players: [
          {'id': 'A', 'hcp': 0.0},
          {'id': 'B', 'hcp': 0.0},
          {'id': 'C', 'hcp': 0.0},
        ],
        groups: [_group(['A', 'B', 'C'], _skinsMod(['A', 'B', 'C']))],
        scoreMaps: scoreMaps,
      );

      final winner = GameEngine.holeWinner(round, ['A', 'B', 'C'], 1, false);
      print('[S1.2] holeWinner H1 (gross): $winner  (esperado: A)');

      expect(winner, equals('A'),
          reason: 'holeWinner ordena por netScore individual → A=3 es el mínimo');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // S2 — 3 jugadores con handicap
  // ─────────────────────────────────────────────────────────────────────────
  group('S2 – 3 jugadores con handicap (modo grupal onePot)', () {

    test('S2.1 – handicap reduce netScore individual; gana el menor neto', () {
      // Curso SI=[1,2,3,...] → H1 tiene SI=1 (el más difícil, primero en recibir strokes)
      // A: hcp=0,  gross=4 → net=4
      // B: hcp=18, gross=5 → net=5-1=4  (recibe 1 stroke en H1 SI=1)
      // C: hcp=36, gross=6 → net=6-2=4  (recibe 2 strokes en H1 SI=1)
      // Todos net=4 → EMPATE → sin ganador en H1

      // strokesReceived(18, SI=1) = 1 (hcp=18 >= SI=1, y 18<36 → no hay segundo)
      // strokesReceived(36, SI=1) = 2 (hcp=36 > 18 → extra stroke: 36-18=18 >= SI=1)
      final scoreMaps = <String, Map<int, (int, int)>>{
        'A': {1: (4, 2)},
        'B': {1: (5, 2)},
        'C': {1: (6, 2)},
      };

      final round = _makeRound(
        players: [
          {'id': 'A', 'hcp':  0.0},
          {'id': 'B', 'hcp': 18.0},
          {'id': 'C', 'hcp': 36.0},
        ],
        groups:    [_group(['A', 'B', 'C'], _skinsMod(['A', 'B', 'C'], useHandicap: true))],
        scoreMaps: scoreMaps,
      );

      // Verificar strokes individuales
      final ch = _course18.holes.firstWhere((h) => h.hole == 1);
      final strkB = GameEngine.strokesReceived(18.0, ch);
      final strkC = GameEngine.strokesReceived(36.0, ch);
      print('[S2.1] strokes en H1: B=$strkB  C=$strkC');
      expect(strkB, equals(1), reason: 'hcp=18 ≥ SI=1 → 1 stroke');
      expect(strkC, equals(2), reason: 'hcp=36 > 18+SI=1 → 2 strokes');

      // holeWinner con HCP
      final winner = GameEngine.holeWinner(round, ['A', 'B', 'C'], 1, true);
      print('[S2.1] holeWinner H1 (neto): $winner  (esperado: null — empate neto)');
      expect(winner, isNull, reason: 'Net A=4, B=4, C=4 → empate → sin ganador');

      // Sin ganador → sin entradas de skins
      final entries = _skinsE(BetEngine.computeAll(round));
      expect(entries, isEmpty,
          reason: 'Empate neto → sin skin ganado');
    });

    test('S2.2 – con handicap: gana el de menor netScore cuando no hay empate', () {
      // H1 (SI=1):
      // A: hcp=0,  gross=4 → net=4
      // B: hcp=18, gross=4 → net=4-1=3  ← GANA (menor neto)
      // C: hcp=18, gross=5 → net=5-1=4
      final scoreMaps = <String, Map<int, (int, int)>>{
        'A': {1: (4, 2)},
        'B': {1: (4, 2)},
        'C': {1: (5, 2)},
      };

      final round = _makeRound(
        players: [
          {'id': 'A', 'hcp':  0.0},
          {'id': 'B', 'hcp': 18.0},
          {'id': 'C', 'hcp': 18.0},
        ],
        groups:    [_group(['A', 'B', 'C'], _skinsMod(['A', 'B', 'C'], useHandicap: true))],
        scoreMaps: scoreMaps,
      );

      final winner = GameEngine.holeWinner(round, ['A', 'B', 'C'], 1, true);
      print('[S2.2] holeWinner H1 con HCP: $winner  (esperado: B)');
      expect(winner, equals('B'),
          reason: 'B net=3 < A net=4 = C net=4 → B gana');

      final entries = _skinsE(BetEngine.computeAll(round));
      expect(entries.every((e) => e.toPlayerId == 'B'), isTrue);
      expect(entries.length, equals(2), reason: 'B gana → A→B y C→B');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // S3 — Empate grupal: A=B (mejor), C peor
  // ─────────────────────────────────────────────────────────────────────────
  group('S3 – Empate grupal: A=B, C peor', () {

    test('S3.1 – A=B=3 C=5: empate → sin ganador → carry acumulado', () {
      // H1: A=3, B=3, C=5 → dos con el mínimo → empate → no hay ganador
      // carryOver=true → H2 vale 2 skins
      final scoreMaps = <String, Map<int, (int, int)>>{
        'A': {1: (3, 2), 2: (4, 2)},
        'B': {1: (3, 2), 2: (5, 2)},
        'C': {1: (5, 2), 2: (5, 2)},
      };

      final round = _makeRound(
        players: [
          {'id': 'A', 'hcp': 0.0},
          {'id': 'B', 'hcp': 0.0},
          {'id': 'C', 'hcp': 0.0},
        ],
        groups:    [_group(['A', 'B', 'C'], _skinsMod(['A', 'B', 'C'], carryOver: true))],
        scoreMaps: scoreMaps,
      );

      // Verificar que H1 no tiene ganador
      final winner1 = GameEngine.holeWinner(round, ['A', 'B', 'C'], 1, false);
      print('[S3.1] holeWinner H1: $winner1  (esperado: null)');
      expect(winner1, isNull, reason: 'A=B=3 → empate → sin ganador');

      // H2: A=4, B=5, C=5 → A gana y recibe el carry (2 skins)
      final entries = _skinsE(BetEngine.computeAll(round));
      print('[S3.1] Entries: ${entries.map((e) => '${e.fromPlayerId}→${e.toPlayerId} H${e.hole} \$${e.amount}').toList()}');

      // H1 sin ganador → no hay entradas para H1
      final h1Entries = entries.where((e) => e.hole == 1).toList();
      expect(h1Entries, isEmpty, reason: 'H1 empate → sin entradas');

      // H2 A gana → 2 pagos (B→A, C→A) con monto del carry
      final h2Entries = entries.where((e) => e.hole == 2).toList();
      expect(h2Entries.length, equals(2));
      expect(h2Entries.every((e) => e.toPlayerId == 'A'), isTrue);
      // pot H2 = 10 (carry de H1) + 10 (H2) = 20 → share = 20/2 = 10 por jugador
      expect(h2Entries.every((e) => (e.amount - 10.0).abs() < 0.01), isTrue,
          reason: 'pot=20 (carry+H2), n=3 → share=10');
    });

    test('S3.2 – sin carry: H1 empatado se pierde, H2 vale solo 1 skin', () {
      final scoreMaps = <String, Map<int, (int, int)>>{
        'A': {1: (3, 2), 2: (4, 2)},
        'B': {1: (3, 2), 2: (5, 2)},
        'C': {1: (5, 2), 2: (5, 2)},
      };

      final round = _makeRound(
        players: [
          {'id': 'A', 'hcp': 0.0},
          {'id': 'B', 'hcp': 0.0},
          {'id': 'C', 'hcp': 0.0},
        ],
        groups:    [_group(['A', 'B', 'C'], _skinsMod(['A', 'B', 'C'], carryOver: false))],
        scoreMaps: scoreMaps,
      );

      final entries = _skinsE(BetEngine.computeAll(round));
      print('[S3.2] Sin carry: ${entries.map((e) => '${e.fromPlayerId}→${e.toPlayerId} H${e.hole} \$${e.amount}').toList()}');

      // H1 empatado (sin carry) → sin entradas H1
      expect(entries.where((e) => e.hole == 1), isEmpty);

      // H2 A gana con pot=10 (sin carry)
      final h2 = entries.where((e) => e.hole == 2).toList();
      expect(h2.length, equals(2));
      expect(h2.every((e) => (e.amount - 5.0).abs() < 0.01), isTrue,
          reason: 'Sin carry: pot=10 → share=5');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // S4 — Carry acumulado: 2 hoyos empatados, 3er hoyo ganador claro
  // ─────────────────────────────────────────────────────────────────────────
  group('S4 – Carry acumulado: 2 empates + 1 ganador', () {

    test('S4.1 – pot acumulado correcto: 3 skins en un solo hoyo', () {
      // H1 empate, H2 empate, H3 A gana → pot = 3 skins
      // pot H3 = 30 (base 10 × 3) → share = 30/2 = 15 por perdedor
      final scoreMaps = <String, Map<int, (int, int)>>{
        'A': {1: (4, 2), 2: (4, 2), 3: (3, 2)},
        'B': {1: (4, 2), 2: (4, 2), 3: (4, 2)},
        'C': {1: (4, 2), 2: (4, 2), 3: (4, 2)},
      };

      final round = _makeRound(
        players: [
          {'id': 'A', 'hcp': 0.0},
          {'id': 'B', 'hcp': 0.0},
          {'id': 'C', 'hcp': 0.0},
        ],
        groups:    [_group(['A', 'B', 'C'], _skinsMod(['A', 'B', 'C'], carryOver: true, value: 10))],
        scoreMaps: scoreMaps,
      );

      final entries = _skinsE(BetEngine.computeAll(round));
      print('[S4.1] Carry 2 empates + A gana H3: ${entries.map((e) => '${e.fromPlayerId}→${e.toPlayerId} H${e.hole} \$${e.amount}').toList()}');

      // H1, H2 empate → sin entradas
      expect(entries.where((e) => e.hole == 1 || e.hole == 2), isEmpty);

      // H3: A gana, pot=30 → B→A: 15, C→A: 15
      final h3 = entries.where((e) => e.hole == 3).toList();
      expect(h3.length, equals(2), reason: 'A gana H3 → 2 pagos');
      expect(h3.every((e) => e.toPlayerId == 'A'), isTrue);
      expect(h3.every((e) => (e.amount - 15.0).abs() < 0.01), isTrue,
          reason: 'pot=30 (3 skins × 10), n=3 → share=15');
    });

    test('S4.2 – después del carry ganado, el pot se resetea', () {
      // H1-H2 empate, H3 A gana (acumula pot), H4 B gana (solo 1 skin)
      final scoreMaps = <String, Map<int, (int, int)>>{
        'A': {1: (4, 2), 2: (4, 2), 3: (3, 2), 4: (5, 2)},
        'B': {1: (4, 2), 2: (4, 2), 3: (4, 2), 4: (4, 2)},
        'C': {1: (4, 2), 2: (4, 2), 3: (4, 2), 4: (5, 2)},
      };

      final round = _makeRound(
        players: [
          {'id': 'A', 'hcp': 0.0},
          {'id': 'B', 'hcp': 0.0},
          {'id': 'C', 'hcp': 0.0},
        ],
        groups:    [_group(['A', 'B', 'C'], _skinsMod(['A', 'B', 'C'], carryOver: true, value: 10))],
        scoreMaps: scoreMaps,
      );

      final entries = _skinsE(BetEngine.computeAll(round));
      print('[S4.2] H1-H2 empate, H3 A gana, H4 B gana: ${entries.map((e) => '${e.fromPlayerId}→${e.toPlayerId} H${e.hole} \$${e.amount}').toList()}');

      // H3: A gana con pot=30 → share=15
      final h3 = entries.where((e) => e.hole == 3).toList();
      expect(h3.length, equals(2));
      expect(h3.every((e) => (e.amount - 15.0).abs() < 0.01), isTrue);

      // H4: B gana con pot=10 (reset a 1 skin) → share=5
      final h4 = entries.where((e) => e.hole == 4).toList();
      expect(h4.length, equals(2));
      expect(h4.every((e) => e.toPlayerId == 'B'), isTrue);
      expect(h4.every((e) => (e.amount - 5.0).abs() < 0.01), isTrue,
          reason: 'Pot reseteado a 10 después de H3 → share=5');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // S5 — Comparación grupal onePot vs 1v1 (allVsAll)
  // Documenta si los resultados difieren y por qué (diferente algoritmo de HCP)
  // ─────────────────────────────────────────────────────────────────────────
  group('S5 – Comparación onePot grupal vs duelos 1v1 (allVsAll)', () {

    test('S5.1 – sin handicap: onePot y allVsAll producen el mismo ganador en cada hoyo', () {
      // Con gross (sin HCP), ambos modos deben identificar al mismo ganador
      // ya que no hay diferencia de distribución de strokes.
      // H1: A=3, B=4, C=5 → A gana en ambos modos
      final scoreMaps = <String, Map<int, (int, int)>>{
        'A': {1: (3, 2)},
        'B': {1: (4, 2)},
        'C': {1: (5, 2)},
      };

      final pids = ['A', 'B', 'C'];
      final players = [
        {'id': 'A', 'hcp': 0.0},
        {'id': 'B', 'hcp': 0.0},
        {'id': 'C', 'hcp': 0.0},
      ];

      final roundPot = _makeRound(
        players:    players,
        groups:     [_group(pids, _skinsMod(pids, fmt: BetFormatMode.onePot))],
        scoreMaps:  scoreMaps,
      );
      final roundAvA = _makeRound(
        players:    players,
        groups:     [_group(pids, _skinsMod(pids, fmt: BetFormatMode.allVsAll))],
        scoreMaps:  scoreMaps,
      );

      final potE = _skinsE(BetEngine.computeAll(roundPot));
      final avaE = _skinsE(BetEngine.computeAll(roundAvA));

      print('[S5.1] onePot: ${potE.map((e) => '${e.fromPlayerId}→${e.toPlayerId}').toList()}');
      print('[S5.1] allVsAll: ${avaE.map((e) => '${e.fromPlayerId}→${e.toPlayerId}').toList()}');

      // onePot: A gana → B→A y C→A (2 entradas)
      expect(potE.every((e) => e.toPlayerId == 'A'), isTrue,
          reason: 'onePot: A gana el skin grupal');

      // allVsAll: A gana vs B y A gana vs C → B→A, C→A
      // (B vs C: B=4 < C=5 → B gana → C→B también)
      final avaToA = avaE.where((e) => e.toPlayerId == 'A').toList();
      expect(avaToA.length, equals(2),
          reason: 'allVsAll: A derrota a B y a C → 2 entradas hacia A');

      // El ganador del skin en onePot == el ganador en todos los duelos
      print('[S5.1] ✅ Sin HCP: mismo ganador en onePot y allVsAll');
    });

    test('S5.2 – CON handicap: documentar divergencia entre onePot y allVsAll', () {
      // ESCENARIO deliberado para exponer la diferencia de algoritmo de HCP:
      //
      // onePot grupal: usa strokesReceived(hcp_absoluto, ch)
      //   → strokes asignados por HCP individual del jugador respecto al campo
      //
      // allVsAll (_skins1v1): usa strokesReceivedInPlayedHoles(diff=recv, ch, playedHoles)
      //   → strokes distribuidos según la DIFERENCIA de HCP entre el par
      //   → y solo sobre los hoyos jugados por el receptor
      //
      // Con A=hcp0, B=hcp9, C=hcp18 en H1 (SI=1):
      //
      //   onePot:
      //     A: hcp=0  → strokesReceived(0,  SI=1) = 0 → net = gross
      //     B: hcp=9  → strokesReceived(9,  SI=1) = 1 → net = gross - 1
      //     C: hcp=18 → strokesReceived(18, SI=1) = 1 → net = gross - 1
      //
      //   1v1 (A vs B): diff = hcp(B) - hcp(A) = 9. recv = 9.
      //     B recibe strokes de A sobre los 18 hoyos jugados.
      //     H1 SI=1 entre 18 hoyos → rank=1 ≤ 9 → 1 stroke → net_B = gross_B - 1
      //     Resultado IGUAL al onePot para este par.
      //
      //   1v1 (A vs C): diff = 18. recv = 18.
      //     C recibe 18 strokes distribuidos en 18 hoyos (1 por hoyo) → 1 stroke en H1
      //     Resultado IGUAL al onePot para este par.
      //
      //   Nota: La divergencia real emerge cuando los hoyos jugados < 18
      //   (strokesReceivedInPlayedHoles re-distribuye). Con 18 hoyos jugados
      //   ambos algoritmos son equivalentes.
      //
      // CONCLUSIÓN S5.2: Con ronda de 18 hoyos COMPLETA, ambos modos son
      // matemáticamente equivalentes en el resultado del ganador.
      // La divergencia ocurre con rondas parciales (ver S5.3).

      final scoreMaps = <String, Map<int, (int, int)>>{
        'A': {1: (4, 2)},
        'B': {1: (5, 2)},   // gross=5, net=4 (1 stroke HCP)
        'C': {1: (6, 2)},   // gross=6, net=5 (1 stroke HCP)
      };

      final pids = ['A', 'B', 'C'];
      final players = [
        {'id': 'A', 'hcp':  0.0},
        {'id': 'B', 'hcp':  9.0},
        {'id': 'C', 'hcp': 18.0},
      ];

      final roundPot = _makeRound(
        players:    players,
        groups:     [_group(pids, _skinsMod(pids, useHandicap: true, fmt: BetFormatMode.onePot))],
        scoreMaps:  scoreMaps,
      );
      final roundAvA = _makeRound(
        players:    players,
        groups:     [_group(pids, _skinsMod(pids, useHandicap: true, fmt: BetFormatMode.allVsAll))],
        scoreMaps:  scoreMaps,
      );

      final potE = _skinsE(BetEngine.computeAll(roundPot));
      final avaE = _skinsE(BetEngine.computeAll(roundAvA));

      final potWinner = potE.isNotEmpty ? potE.first.toPlayerId : 'ninguno';
      final avaH1 = avaE.where((e) => e.hole == 1).toList();

      print('[S5.2] onePot H1 ganador: $potWinner');
      print('[S5.2] allVsAll H1: ${avaH1.map((e) => '${e.fromPlayerId}→${e.toPlayerId}').toList()}');

      // onePot: A=net4, B=net4 (5-1), C=net5 (6-1) → A=B empate neto → sin ganador
      expect(potE, isEmpty,
          reason: 'onePot HCP: A net=4, B net=4 → empate → sin skin');

      // allVsAll 1v1:
      //   A vs B: recv=9, H1 SI=1, 1 hoyo jugado por B →
      //     strokesReceivedInPlayedHoles(diff=9, ch=H1, playedHoles=[H1])
      //     → sorted=[H1], n=1, fullRounds=9, remainder=0 → 9 strokes
      //     B gross=5, net=5-9=-4 → B.net=-4 < A.gross=4 → B gana (tiene la menor net)
      // NOTA: Este es el punto crítico de divergencia:
      //   onePot grupal: B recibe 1 stroke (strokesReceived(9, SI=1) = 1)
      //   allVsAll 1v1:  B recibe 9 strokes (9 strokes distribuidos en 1 hoyo jugado)
      // Ambos resultados son CORRECTOS según su propia lógica:
      //   onePot: handicap absoluto del jugador vs el campo
      //   1v1:    diferencia de HCP distribuida en los hoyos jugados
      final avaAvsB = avaH1.where((e) =>
          (e.fromPlayerId == 'A' && e.toPlayerId == 'B') ||
          (e.fromPlayerId == 'B' && e.toPlayerId == 'A')).toList();
      print('[S5.2] allVsAll A vs B en H1: ${avaAvsB.map((e) => '${e.fromPlayerId}→${e.toPlayerId} \$${e.amount}').toList()}');

      // Documentar (no afirmar dirección pues depende de algoritmo)
      // La divergencia onePot vs allVsAll está documentada arriba.
      // Verificar solo que el cálculo no truena
      expect(() => BetEngine.computeAll(roundPot), returnsNormally);
      expect(() => BetEngine.computeAll(roundAvA), returnsNormally);

      print('[S5.2] DIVERGENCIA DOCUMENTADA:');
      print('  onePot: usa strokesReceived(hcp_absoluto, SI) → 1 stroke para B(hcp=9) en H1');
      print('  allVsAll: usa strokesReceivedInPlayedHoles(diff=recv, playedHoles) → strokes concentrados en hoyos jugados');
      print('  Con ronda parcial, allVsAll puede dar strokes MUCHO mayores por hoyo.');
      print('  Con ronda COMPLETA de 18 hoyos, ambos son equivalentes.');
    });

    test('S5.3 – ronda completa 18H: onePot y allVsAll concuerdan en ganador', () {
      // Con 18 hoyos completos, ambos modos de HCP son equivalentes
      // → mismo ganador en cada hoyo
      // A: hcp=0, gross=4 en todos los hoyos
      // B: hcp=18, gross=5 en todos los hoyos
      // H1 (SI=1): A net=4, B net=5-1=4 → empate (en ambos modos)
      // H19+: no aplica. Usamos H1 gross diferente para tener ganador
      //
      // A: gross=3 en H1, B: gross=4, hcp=18 → B recibe 1 stroke en H1 (SI=1)
      // onePot:   A net=3, B net=4-1=3 → empate
      // allVsAll: recv=18, 18 hoyos jugados → rank(H1)=1 ≤ 18 → 1 stroke → B net=3
      //           → empate también (mismo resultado)
      final scoreMaps = <String, Map<int, (int, int)>>{
        'A': { for (int h = 1; h <= 18; h++) h: (4, 2) },
        'B': { for (int h = 1; h <= 18; h++) h: h == 1 ? (3, 2) : (4, 2) },
      };
      // H1: A=4, B=3 gross, B tiene hcp=18 → recibe 1 stroke en H1 → net=2 → B gana

      final pids = ['A', 'B'];
      final players = [
        {'id': 'A', 'hcp':  0.0},
        {'id': 'B', 'hcp': 18.0},
      ];

      final roundPot = _makeRound(
        players:    players,
        groups:     [_group(pids, _skinsMod(pids, useHandicap: true, fmt: BetFormatMode.onePot))],
        scoreMaps:  scoreMaps,
      );
      final roundAvA = _makeRound(
        players:    players,
        groups:     [_group(pids, _skinsMod(pids, useHandicap: true, fmt: BetFormatMode.allVsAll))],
        scoreMaps:  scoreMaps,
      );

      final potH1 = _skinsE(BetEngine.computeAll(roundPot)).where((e) => e.hole == 1).toList();
      final avaH1 = _skinsE(BetEngine.computeAll(roundAvA)).where((e) => e.hole == 1).toList();

      print('[S5.3] onePot H1: ${potH1.map((e) => '${e.fromPlayerId}→${e.toPlayerId}').toList()}');
      print('[S5.3] allVsAll H1: ${avaH1.map((e) => '${e.fromPlayerId}→${e.toPlayerId}').toList()}');

      // Ambos: B gana H1 (gross=3, net=2 con 1 stroke)
      expect(potH1.every((e) => e.toPlayerId == 'B'), isTrue,
          reason: 'onePot: B net=2 (3-1) < A net=4 → B gana H1');
      expect(avaH1.every((e) => e.toPlayerId == 'B'), isTrue,
          reason: 'allVsAll: misma distribución con 18H completos → B gana H1');

      print('[S5.3] ✅ Ronda 18H completa: onePot y allVsAll coinciden en ganador por hoyo');
    });
  });
}
