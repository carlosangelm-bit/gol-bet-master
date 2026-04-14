// ignore_for_file: avoid_print
// =============================================================================
// Auditoría completa de Oyeses — test/oyeses_audit_test.dart
//
// HALLAZGO CENTRAL (documentado como resultado de la auditoría):
//
//   Oyeses ES UN JUEGO DE RANKING POR HOYO (Hipótesis A confirmada).
//
//   El engine usa exclusivamente round.oyeseRankings[hole].ranking:
//   una lista ordenada de playerIds donde el índice 0 = más cercano al hoyo.
//   El ranking es ingresado MANUALMENTE por el usuario en la UI de captura.
//   No usa gross score, eventos (birdie/eagle/GIR/sandSave), ni ningún otro dato.
//
//   Cobros:
//   - Por cada par (i, j) con i < j en el ranking: loser(j) paga a winner(i) cfg.value.
//   - Ej: ranking [A,B,C] en H3 → B paga a A, C paga a A, C paga a B.
//
//   Zapato:
//   - onePot:  el jugador primero ABSOLUTO en TODOS los oyeses cobra a todos.
//   - allVsAll: A hace zapato vs B si A quedó delante de B en TODOS los oyeses.
//   - Requisito: holesWithRanking == totalEligible (todos los hoyos completados).
//   - zapatoRequires18=true además exige totalEligible >= 3.
//
//   Hoyos elegibles:
//   - Si cfg.eligibleHoles vacío → todos los par-3 del curso.
//   - Si cfg.eligibleHoles definido → intersección con par-3.
//
//   Hoyos parciales:
//   - Si un hoyo no tiene ranking → se omite (no truena, no cobra).
//
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Cursos de test
// ─────────────────────────────────────────────────────────────────────────────

/// Curso 18H con par-3 en hoyos 3, 6, 12, 15 (4 par-3s).
final _course18 = CourseInfo(
  name: 'Oyeses Test 18H',
  holes: List.generate(18, (i) {
    final hole = i + 1;
    final par = (hole == 3 || hole == 6 || hole == 12 || hole == 15) ? 3 : 4;
    final si   = (i % 9) * 2 + (i < 9 ? 1 : 2);
    return CourseHole(hole: hole, par: par, strokeIndex: si);
  }),
);

/// Curso 9H con par-3 en hoyos 3 y 6 (hoyos 1-9).
final _courseF9 = CourseInfo(
  name: 'Oyeses Test F9',
  holes: List.generate(9, (i) {
    final hole = i + 1;
    final par  = (hole == 3 || hole == 6) ? 3 : 4;
    return CourseHole(hole: hole, par: par, strokeIndex: (i * 2) + 1);
  }),
);

/// Curso B9 (hoyos 10-18) con par-3 en hoyos 12 y 15.
final _courseB9 = CourseInfo(
  name: 'Oyeses Test B9',
  holes: List.generate(9, (i) {
    final hole = i + 10;
    final par  = (hole == 12 || hole == 15) ? 3 : 4;
    return CourseHole(hole: hole, par: par, strokeIndex: (i * 2) + 2);
  }),
);

/// Curso 18H sin par-3s (todos par 4).
final _courseNoPar3 = CourseInfo(
  name: 'No Par-3 Course',
  holes: List.generate(18, (i) =>
      CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)),
);

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

Round _makeRound({
  required List<String> playerIds,
  required BetModuleInstance mod,
  Map<int, OyeseRanking>? oyeseRankings,
  CourseInfo? course,
  int totalHoles = 18,
  StartingNine startingNine = StartingNine.front,
}) {
  final c = course ?? _course18;
  final players = playerIds.map((id) => Player(
    id: id, name: id, handicapBase: 0,
  )).toList();
  final rPlayers = playerIds.map((id) => RoundPlayer(
    playerId: id, handicapEnRonda: 0,
  )).toList();
  final group = BetGroup(
    id: 'g1', name: 'G1',
    format: PartidaFormat.allInOnePot,
    playerIds: playerIds,
    modules: [mod],
  );

  return Round(
    id: 'oyeses-test',
    name: 'Oyeses Test Round',
    course: c,
    players: players,
    roundPlayers: rPlayers,
    betGroups: [group],
    scores: const {},
    events: const {},
    oyeseRankings: oyeseRankings ?? const {},
    sliding: const [],
    createdAt: DateTime(2025, 1, 1),
    totalHoles: totalHoles,
    startingNine: startingNine,
  );
}

BetModuleInstance _oyesesMod(
  List<String> pids, {
  double value = 50,
  List<int> eligibleHoles = const [],
  bool allVsAll = false,
  bool zapatoEnabled = false,
  double zapatoValue = 0,
  bool zapatoRequires18 = false,
}) =>
    BetModuleInstance.defaultFor(BetModuleType.oyeses, pids).copyWith(
      oyesesConfig: OyesesConfig(
        value: value,
        eligibleHoles: eligibleHoles,
        zapatoEnabled: zapatoEnabled,
        zapatoValue: zapatoValue,
        zapatoRequires18: zapatoRequires18,
      ),
      formatMode: allVsAll ? BetFormatMode.allVsAll : BetFormatMode.onePot,
    );

/// Extrae entradas Oyeses para un par específico.
List<LedgerEntry> _pairEntries(List<LedgerEntry> all, String a, String b) =>
    all.where((e) =>
        e.betType == BetModuleType.oyeses &&
        ((e.fromPlayerId == a && e.toPlayerId == b) ||
         (e.fromPlayerId == b && e.toPlayerId == a))).toList();

// =============================================================================
// AUDITORÍA + TESTS
// =============================================================================
void main() {

  // ───────────────────────────────────────────────────────────────────────────
  // AUDITORÍA CONFIRMADA — log de resultados al inicio
  // ───────────────────────────────────────────────────────────────────────────
  setUpAll(() {
    print('\n');
    print('══════════════════════════════════════════════════════════════════');
    print('  AUDITORÍA TÉCNICA DE OYESES');
    print('  Resultado: RANKING POR HOYO (Hipótesis A)');
    print('  Fuente: round.oyeseRankings[hole].ranking = [List<String>]');
    print('  Cobros: todo par (i,j) en ranking → j paga a i cfg.value');
    print('  Hoyos elegibles: par-3 del curso ∩ eligibleHoles (si definido)');
    print('  NO usa: gross score, eventos, GIR, birdie, eagle, sandSave');
    print('══════════════════════════════════════════════════════════════════');
    print('');
  });

  // ───────────────────────────────────────────────────────────────────────────
  // CASO 1 — Ranking simple: 3 jugadores, 1 hoyo elegible
  // ───────────────────────────────────────────────────────────────────────────
  group('O1 – Ranking simple: 3 jugadores, 1 hoyo', () {

    test('O1.1 – A>B>C en H3: cobros correctos (C paga a A y B, B paga a A)', () {
      // ranking H3 = [A, B, C] → A gana vs B y C; B gana vs C.
      // Cobros:
      //   B → A: $50 (posición 2° vs 1°)
      //   C → A: $50 (posición 3° vs 1°)
      //   C → B: $50 (posición 3° vs 2°)
      final mod = _oyesesMod(['A', 'B', 'C'], value: 50);
      final round = _makeRound(
        playerIds: ['A', 'B', 'C'],
        mod: mod,
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A', 'B', 'C']),
        },
      );

      final entries = BetEngine.computeAll(round);
      print('[O1.1] Entradas H3 A>B>C: ${entries.map((e) => '${e.fromPlayerId}→${e.toPlayerId} \$${e.amount} ${e.reason}').toList()}');

      // 3 cobros esperados: B→A, C→A, C→B
      expect(entries.length, equals(3), reason: 'Con 3 posiciones hay C(3,2)=3 cobros');

      final ba = entries.where((e) => e.fromPlayerId == 'B' && e.toPlayerId == 'A').toList();
      expect(ba.length, equals(1));
      expect(ba.first.amount, closeTo(50, 0.01));

      final ca = entries.where((e) => e.fromPlayerId == 'C' && e.toPlayerId == 'A').toList();
      expect(ca.length, equals(1));
      expect(ca.first.amount, closeTo(50, 0.01));

      final cb = entries.where((e) => e.fromPlayerId == 'C' && e.toPlayerId == 'B').toList();
      expect(cb.length, equals(1));
      expect(cb.first.amount, closeTo(50, 0.01));
    });

    test('O1.2 – Reason incluye número de hoyo y posiciones', () {
      final mod = _oyesesMod(['A', 'B'], value: 50);
      final round = _makeRound(
        playerIds: ['A', 'B'],
        mod: mod,
        oyeseRankings: {3: OyeseRanking(hole: 3, ranking: ['A', 'B'])},
      );

      final entries = BetEngine.computeAll(round);
      expect(entries, isNotEmpty);
      expect(entries.first.reason, contains('H3'));
      expect(entries.first.reason, contains('1°'));
      expect(entries.first.reason, contains('2°'));
    });

    test('O1.3 – hole field en LedgerEntry es el número de hoyo correcto', () {
      final mod = _oyesesMod(['A', 'B'], value: 50);
      final round = _makeRound(
        playerIds: ['A', 'B'],
        mod: mod,
        oyeseRankings: {6: OyeseRanking(hole: 6, ranking: ['A', 'B'])},
      );

      final entries = BetEngine.computeAll(round);
      expect(entries, isNotEmpty);
      expect(entries.first.hole, equals(6));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // CASO 2 — Múltiples hoyos elegibles: acumulación correcta
  // ───────────────────────────────────────────────────────────────────────────
  group('O2 – Múltiples hoyos elegibles', () {

    test('O2.1 – 4 par-3s, A gana todos: 4 × 1 cobro = 4 entradas total (2 jugadores)', () {
      // H3, H6, H12, H15: en todos, A > B.
      final mod = _oyesesMod(['A', 'B'], value: 50);
      final round = _makeRound(
        playerIds: ['A', 'B'],
        mod: mod,
        oyeseRankings: {
          3:  OyeseRanking(hole: 3,  ranking: ['A', 'B']),
          6:  OyeseRanking(hole: 6,  ranking: ['A', 'B']),
          12: OyeseRanking(hole: 12, ranking: ['A', 'B']),
          15: OyeseRanking(hole: 15, ranking: ['A', 'B']),
        },
      );

      final entries = BetEngine.computeAll(round);
      print('[O2.1] 4 hoyos A>B: ${entries.length} entradas');

      expect(entries.length, equals(4), reason: '1 cobro por hoyo × 4 hoyos');
      for (final e in entries) {
        expect(e.fromPlayerId, equals('B'));
        expect(e.toPlayerId,   equals('A'));
        expect(e.amount, closeTo(50, 0.01));
      }
    });

    test('O2.2 – 3 jugadores, 2 hoyos: acumulación correcta', () {
      // H3: [A,B,C] → 3 cobros. H6: [B,A,C] → 3 cobros. Total: 6.
      final mod = _oyesesMod(['A', 'B', 'C'], value: 30);
      final round = _makeRound(
        playerIds: ['A', 'B', 'C'],
        mod: mod,
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A', 'B', 'C']),
          6: OyeseRanking(hole: 6, ranking: ['B', 'A', 'C']),
        },
      );

      final entries = BetEngine.computeAll(round);
      print('[O2.2] 2 hoyos 3 jugadores: ${entries.length} entradas');
      expect(entries.length, equals(6), reason: '3 cobros × 2 hoyos = 6');

      // En H3: A es 1° → recibe de B y C; B es 2° → recibe de C
      final h3Entries = entries.where((e) => e.hole == 3).toList();
      expect(h3Entries.length, equals(3));
      expect(h3Entries.where((e) => e.toPlayerId == 'A').length, equals(2));
      expect(h3Entries.where((e) => e.toPlayerId == 'B').length, equals(1));

      // En H6: B es 1° → recibe de A y C; A es 2° → recibe de C
      final h6Entries = entries.where((e) => e.hole == 6).toList();
      expect(h6Entries.length, equals(3));
      expect(h6Entries.where((e) => e.toPlayerId == 'B').length, equals(2));
      expect(h6Entries.where((e) => e.toPlayerId == 'A').length, equals(1));
    });

    test('O2.3 – Mix: algunos hoyos con ranking, otros sin → solo los que tienen', () {
      // H3 tiene ranking, H6 no. Solo H3 genera cobro.
      final mod = _oyesesMod(['A', 'B'], value: 50);
      final round = _makeRound(
        playerIds: ['A', 'B'],
        mod: mod,
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A', 'B']),
          // H6 sin ranking
        },
      );

      final entries = BetEngine.computeAll(round);
      expect(entries.length, equals(1), reason: 'Solo H3 tiene ranking → 1 cobro');
      expect(entries.first.hole, equals(3));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // CASO 3 — Zapato onePot
  // ───────────────────────────────────────────────────────────────────────────
  group('O3 – Zapato onePot', () {

    test('O3.1 – A gana todos (3 de 3 par-3s): cobra zapato a B y C', () {
      // 3 hoyos par-3 en _courseF9 (H3, H6, y necesitamos 1 más → usamos courseF9 con par-3 en H3,H6).
      // Usamos _course18 que tiene 4 par-3s: H3,H6,H12,H15.
      // A gana todos → cobra zapato.
      // zapatoValue=0 → monto = totalEligible × value = 4 × 50 = 200.
      final mod = _oyesesMod(['A', 'B', 'C'],
        value: 50,
        zapatoEnabled: true,
        zapatoValue: 0,
        zapatoRequires18: false,
      );
      final round = _makeRound(
        playerIds: ['A', 'B', 'C'],
        mod: mod,
        oyeseRankings: {
          3:  OyeseRanking(hole: 3,  ranking: ['A', 'B', 'C']),
          6:  OyeseRanking(hole: 6,  ranking: ['A', 'B', 'C']),
          12: OyeseRanking(hole: 12, ranking: ['A', 'B', 'C']),
          15: OyeseRanking(hole: 15, ranking: ['A', 'B', 'C']),
        },
      );

      final entries = BetEngine.computeAll(round);
      print('[O3.1] Zapato 1Pot: ${entries.map((e) => '${e.fromPlayerId}→${e.toPlayerId} \$${e.amount} ${e.reason}').toList()}');

      final zapatoEntries = entries.where((e) => e.reason.contains('Zapato')).toList();
      expect(zapatoEntries.length, equals(2),
          reason: 'Un zapato: A cobra a B y C (2 entradas)');
      for (final e in zapatoEntries) {
        expect(e.toPlayerId,  equals('A'));
        expect(e.amount, closeTo(200, 0.01),
            reason: 'Zapato = 4 oyeses × \$50 = \$200');
      }
    });

    test('O3.2 – A no gana todos (empata en 1 hoyo con B): sin zapato', () {
      // En H6: [B, A, C] → B gana, no A. A solo gana 3 de 4 → sin zapato.
      final mod = _oyesesMod(['A', 'B', 'C'],
        value: 50, zapatoEnabled: true, zapatoValue: 0);
      final round = _makeRound(
        playerIds: ['A', 'B', 'C'],
        mod: mod,
        oyeseRankings: {
          3:  OyeseRanking(hole: 3,  ranking: ['A', 'B', 'C']),
          6:  OyeseRanking(hole: 6,  ranking: ['B', 'A', 'C']), // B gana H6
          12: OyeseRanking(hole: 12, ranking: ['A', 'B', 'C']),
          15: OyeseRanking(hole: 15, ranking: ['A', 'B', 'C']),
        },
      );

      final entries = BetEngine.computeAll(round);
      final zapatoEntries = entries.where((e) => e.reason.contains('Zapato')).toList();
      expect(zapatoEntries, isEmpty,
          reason: 'Ningún jugador ganó todos los oyeses → sin zapato');
    });

    test('O3.3 – zapatoValue fijo: monto fijo sin importar cantidad de hoyos', () {
      // zapatoValue=500 → cobra siempre $500 sin importar cuántos oyeses haya.
      final mod = _oyesesMod(['A', 'B'],
        value: 50, zapatoEnabled: true, zapatoValue: 500);
      final round = _makeRound(
        playerIds: ['A', 'B'],
        mod: mod,
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A', 'B']),
          6: OyeseRanking(hole: 6, ranking: ['A', 'B']),
        },
        course: _courseF9, totalHoles: 9,
      );

      final entries = BetEngine.computeAll(round);
      final zapatoEntries = entries.where((e) => e.reason.contains('Zapato')).toList();
      expect(zapatoEntries, isNotEmpty);
      expect(zapatoEntries.first.amount, closeTo(500, 0.01));
    });

    test('O3.4 – zapatoRequires18=true con 2 par-3s: sin zapato', () {
      // _courseF9 tiene 2 par-3s (H3, H6). zapatoRequires18=true exige ≥3.
      final mod = _oyesesMod(['A', 'B'],
        value: 50, zapatoEnabled: true, zapatoRequires18: true);
      final round = _makeRound(
        playerIds: ['A', 'B'],
        mod: mod,
        course: _courseF9,
        totalHoles: 9,
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A', 'B']),
          6: OyeseRanking(hole: 6, ranking: ['A', 'B']),
        },
      );

      final entries = BetEngine.computeAll(round);
      final zapatoEntries = entries.where((e) => e.reason.contains('Zapato')).toList();
      expect(zapatoEntries, isEmpty,
          reason: 'zapatoRequires18=true con solo 2 par-3s no debe generar zapato');
    });

    test('O3.5 – zapatoRequires18=false con 2 par-3s: sí genera zapato', () {
      final mod = _oyesesMod(['A', 'B'],
        value: 50, zapatoEnabled: true, zapatoRequires18: false);
      final round = _makeRound(
        playerIds: ['A', 'B'],
        mod: mod,
        course: _courseF9,
        totalHoles: 9,
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A', 'B']),
          6: OyeseRanking(hole: 6, ranking: ['A', 'B']),
        },
      );

      final entries = BetEngine.computeAll(round);
      final zapatoEntries = entries.where((e) => e.reason.contains('Zapato')).toList();
      expect(zapatoEntries, isNotEmpty,
          reason: 'zapatoRequires18=false con 2 par-3s sí debe generar zapato');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // CASO 4 — Zapato allVsAll
  // ───────────────────────────────────────────────────────────────────────────
  group('O4 – Zapato allVsAll', () {

    test('O4.1 – A gana todos vs B (2 jugadores): 1 zapato A→B', () {
      final mod = _oyesesMod(['A', 'B'],
        value: 50, allVsAll: true, zapatoEnabled: true, zapatoRequires18: false);
      final round = _makeRound(
        playerIds: ['A', 'B'],
        mod: mod,
        course: _courseF9, totalHoles: 9,
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A', 'B']),
          6: OyeseRanking(hole: 6, ranking: ['A', 'B']),
        },
      );

      final entries = BetEngine.computeAll(round);
      print('[O4.1] Zapato AvA: ${entries.map((e) => '${e.fromPlayerId}→${e.toPlayerId} ${e.reason} \$${e.amount}').toList()}');

      final zapatoEntries = entries.where((e) => e.reason.contains('Zapato')).toList();
      expect(zapatoEntries.length, equals(1));
      expect(zapatoEntries.first.toPlayerId,   equals('A'));
      expect(zapatoEntries.first.fromPlayerId, equals('B'));
      // monto = totalEligible × value = 2 × 50 = 100
      expect(zapatoEntries.first.amount, closeTo(100, 0.01));
    });

    test('O4.2 – 3 jugadores: A gana a B en todos, A gana a C en todos → 3 zapatos (incluye B vs C)', () {
      // Ranking [A,B,C] en todos los hoyos:
      //   A vs B: A gana → zapato B→A
      //   A vs C: A gana → zapato C→A
      //   B vs C: B gana → zapato C→B  ← el engine TAMBIÉN lo genera (correcto)
      // Total: 3 zapatos, todos hacia quien perdió todos sus duelos.
      final mod = _oyesesMod(['A', 'B', 'C'],
        value: 50, allVsAll: true, zapatoEnabled: true, zapatoRequires18: false);
      final round = _makeRound(
        playerIds: ['A', 'B', 'C'],
        mod: mod,
        course: _courseF9, totalHoles: 9,
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A', 'B', 'C']),
          6: OyeseRanking(hole: 6, ranking: ['A', 'B', 'C']),
        },
      );

      final entries = BetEngine.computeAll(round);
      final zapatoEntries = entries.where((e) => e.reason.contains('Zapato')).toList();
      print('[O4.2] Zapatos: ${zapatoEntries.map((e) => '${e.fromPlayerId}→${e.toPlayerId}').toList()}');

      // Con ranking A>B>C consistente en los 2 hoyos, todos los pares tienen un
      // dominador absoluto → el engine genera C(3,2)=3 zapatos.
      expect(zapatoEntries.length, equals(3),
          reason: 'Ranking A>B>C consistente → 3 pares con dominador: B→A, C→A, C→B');
      final toPlayers = zapatoEntries.map((e) => e.toPlayerId).toSet();
      expect(toPlayers, containsAll(['A', 'B']),
          reason: 'A recibe de B y C; B recibe de C');
    });

    test('O4.3 – Split de ganadores: A gana a B en todos, C gana a B en todos → 2 zapatos independientes', () {
      // H3: [A,C,B]. H6: [C,A,B].
      // A vs B: A gana ambos → zapato A vs B.
      // C vs B: C gana ambos → zapato C vs B.
      // A vs C: A gana 1 y C gana 1 → sin zapato.
      final mod = _oyesesMod(['A', 'B', 'C'],
        value: 50, allVsAll: true, zapatoEnabled: true, zapatoRequires18: false);
      final round = _makeRound(
        playerIds: ['A', 'B', 'C'],
        mod: mod,
        course: _courseF9, totalHoles: 9,
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A', 'C', 'B']),
          6: OyeseRanking(hole: 6, ranking: ['C', 'A', 'B']),
        },
      );

      final entries = BetEngine.computeAll(round);
      final zapatoEntries = entries.where((e) => e.reason.contains('Zapato')).toList();
      print('[O4.3] Zapatos split: ${zapatoEntries.map((e) => '${e.fromPlayerId}→${e.toPlayerId}').toList()}');

      // Debe haber exactamente 2 zapatos: A cobra a B, C cobra a B
      expect(zapatoEntries.length, equals(2));
      final zapatoAvsB = zapatoEntries.where((e) => e.toPlayerId == 'A' && e.fromPlayerId == 'B').toList();
      final zapatoCvsB = zapatoEntries.where((e) => e.toPlayerId == 'C' && e.fromPlayerId == 'B').toList();
      expect(zapatoAvsB.length, equals(1));
      expect(zapatoCvsB.length, equals(1));
    });

    test('O4.4 – hoyos incompletos: zapato NO se dispara si no todos están rankeados', () {
      // 2 par-3 elegibles, solo 1 con ranking → holesWithRanking(1) ≠ totalEligible(2) → sin zapato.
      final mod = _oyesesMod(['A', 'B'],
        value: 50, allVsAll: true, zapatoEnabled: true, zapatoRequires18: false);
      final round = _makeRound(
        playerIds: ['A', 'B'],
        mod: mod,
        course: _courseF9, totalHoles: 9,
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A', 'B']),
          // H6 sin ranking
        },
      );

      final entries = BetEngine.computeAll(round);
      final zapatoEntries = entries.where((e) => e.reason.contains('Zapato')).toList();
      expect(zapatoEntries, isEmpty,
          reason: 'Zapato requiere completar TODOS los oyeses elegibles');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // CASO 5 — Hoyos incompletos: no truena, no cobra de hoyos sin ranking
  // ───────────────────────────────────────────────────────────────────────────
  group('O5 – Hoyos incompletos', () {

    test('O5.1 – Sin oyeseRankings en absoluto: 0 entradas, sin crash', () {
      final mod = _oyesesMod(['A', 'B'], value: 50);
      final round = _makeRound(playerIds: ['A', 'B'], mod: mod);

      expect(() => BetEngine.computeAll(round), returnsNormally);
      expect(BetEngine.computeAll(round), isEmpty);
    });

    test('O5.2 – Ranking vacío en el hoyo: 0 entradas para ese hoyo', () {
      final mod = _oyesesMod(['A', 'B'], value: 50);
      final round = _makeRound(
        playerIds: ['A', 'B'],
        mod: mod,
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: []), // vacío
        },
      );

      expect(BetEngine.computeAll(round), isEmpty,
          reason: 'Ranking vacío equivale a hoyo sin datos');
    });

    test('O5.3 – Ranking con solo 1 jugador: sin cobros (necesita ≥2)', () {
      final mod = _oyesesMod(['A', 'B'], value: 50);
      final round = _makeRound(
        playerIds: ['A', 'B'],
        mod: mod,
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A']), // solo A
        },
      );

      expect(BetEngine.computeAll(round), isEmpty,
          reason: 'Con 1 jugador rankeado no hay cobros');
    });

    test('O5.4 – Jugador en ranking no pertenece al módulo: se ignora', () {
      // Ranking tiene a 'X' que no está en el módulo (A, B).
      // El engine filtra por pids → solo usa A y B si están en el ranking.
      final mod = _oyesesMod(['A', 'B'], value: 50);
      final round = _makeRound(
        playerIds: ['A', 'B'],
        mod: mod,
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['X', 'A', 'B']), // X no pertenece
        },
      );

      final entries = BetEngine.computeAll(round);
      print('[O5.4] Jugador externo en ranking: ${entries.map((e) => '${e.fromPlayerId}→${e.toPlayerId}').toList()}');

      // Solo A y B se filtran. A gana vs B → 1 cobro.
      // 'X' se descarta → no genera entradas con X.
      final xEntries = entries.where((e) =>
          e.fromPlayerId == 'X' || e.toPlayerId == 'X').toList();
      expect(xEntries, isEmpty,
          reason: 'X no pertenece al módulo → sus cobros se ignoran');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // CASO 6 — eligibleHoles: solo hoyos especificados
  // ───────────────────────────────────────────────────────────────────────────
  group('O6 – eligibleHoles', () {

    test('O6.1 – eligibleHoles=[3]: solo H3 cuenta, H6 ignorado', () {
      final mod = _oyesesMod(['A', 'B'], value: 50, eligibleHoles: [3]);
      final round = _makeRound(
        playerIds: ['A', 'B'],
        mod: mod,
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A', 'B']),
          6: OyeseRanking(hole: 6, ranking: ['B', 'A']), // B gana, pero H6 no es elegible
        },
      );

      final entries = BetEngine.computeAll(round);
      print('[O6.1] eligibleHoles=[3]: ${entries.map((e) => '${e.fromPlayerId}→${e.toPlayerId} H${e.hole}').toList()}');

      expect(entries.length, equals(1), reason: 'Solo H3 es elegible → 1 cobro');
      expect(entries.first.hole, equals(3));
      expect(entries.first.toPlayerId, equals('A'), reason: 'A gana H3');
    });

    test('O6.2 – eligibleHoles=[3,6]: ambos cuentan', () {
      final mod = _oyesesMod(['A', 'B'], value: 50, eligibleHoles: [3, 6]);
      final round = _makeRound(
        playerIds: ['A', 'B'],
        mod: mod,
        oyeseRankings: {
          3:  OyeseRanking(hole: 3,  ranking: ['A', 'B']),
          6:  OyeseRanking(hole: 6,  ranking: ['A', 'B']),
          12: OyeseRanking(hole: 12, ranking: ['B', 'A']), // H12 no elegible
          15: OyeseRanking(hole: 15, ranking: ['B', 'A']), // H15 no elegible
        },
      );

      final entries = BetEngine.computeAll(round);
      expect(entries.length, equals(2), reason: 'Solo H3 y H6 son elegibles → 2 cobros');
      expect(entries.every((e) => e.hole == 3 || e.hole == 6), isTrue);
    });

    test('O6.3 – eligibleHoles con hoyo no par-3: se ignora (solo par-3 válidos)', () {
      // H4 es par-4, no par-3 → aunque esté en eligibleHoles, no se procesa.
      final mod = _oyesesMod(['A', 'B'], value: 50, eligibleHoles: [4]);
      final round = _makeRound(
        playerIds: ['A', 'B'],
        mod: mod,
        oyeseRankings: {
          4: OyeseRanking(hole: 4, ranking: ['A', 'B']),
        },
      );

      expect(BetEngine.computeAll(round), isEmpty,
          reason: 'H4 es par-4, eligibleHoles solo aplica a par-3s');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // CASO 7 — Filtering par-3: solo usa hoyos par 3
  // ───────────────────────────────────────────────────────────────────────────
  group('O7 – Par-3 filtering', () {

    test('O7.1 – Curso sin par-3s: 0 entradas aunque haya rankings', () {
      final mod = _oyesesMod(['A', 'B'], value: 50);
      // Rankings en hoyos par-4 → no deben generar cobros
      final round = _makeRound(
        playerIds: ['A', 'B'],
        mod: mod,
        course: _courseNoPar3,
        totalHoles: 18,
        oyeseRankings: {
          1: OyeseRanking(hole: 1, ranking: ['A', 'B']),
          2: OyeseRanking(hole: 2, ranking: ['A', 'B']),
        },
      );

      expect(BetEngine.computeAll(round), isEmpty,
          reason: 'Sin par-3s no hay oyeses elegibles');
    });

    test('O7.2 – Par-3 en H3 con ranking, par-4 H4 con ranking: solo H3 cobra', () {
      final mod = _oyesesMod(['A', 'B'], value: 50);
      final round = _makeRound(
        playerIds: ['A', 'B'],
        mod: mod,
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A', 'B']), // par-3 → elegible
          4: OyeseRanking(hole: 4, ranking: ['B', 'A']), // par-4 → no elegible
        },
      );

      final entries = BetEngine.computeAll(round);
      expect(entries.length, equals(1));
      expect(entries.first.hole, equals(3));
      expect(entries.first.toPlayerId, equals('A'));
    });

    test('O7.3 – Solo hoyos par-3 del curso son procesados', () {
      // _course18 tiene par-3 en H3,H6,H12,H15.
      // Rankings en H1,H3,H6 → solo H3,H6 son par-3 → 2 cobros.
      final mod = _oyesesMod(['A', 'B'], value: 50);
      final round = _makeRound(
        playerIds: ['A', 'B'],
        mod: mod,
        oyeseRankings: {
          1: OyeseRanking(hole: 1,  ranking: ['A', 'B']), // par-4 → ignorado
          3: OyeseRanking(hole: 3,  ranking: ['A', 'B']), // par-3 → cuenta
          6: OyeseRanking(hole: 6,  ranking: ['A', 'B']), // par-3 → cuenta
        },
      );

      final entries = BetEngine.computeAll(round);
      expect(entries.length, equals(2));
      final holes = entries.map((e) => e.hole).toSet();
      expect(holes, equals({3, 6}));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // CASO 8 — startingNine / cursos parciales
  // ───────────────────────────────────────────────────────────────────────────
  group('O8 – startingNine y cursos parciales', () {

    test('O8.1 – Curso B9 (H10-18), par-3 en H12,H15: se procesan correctamente', () {
      final mod = _oyesesMod(['A', 'B'], value: 50);
      final round = _makeRound(
        playerIds: ['A', 'B'],
        mod: mod,
        course: _courseB9,
        totalHoles: 9,
        startingNine: StartingNine.back,
        oyeseRankings: {
          12: OyeseRanking(hole: 12, ranking: ['A', 'B']),
          15: OyeseRanking(hole: 15, ranking: ['A', 'B']),
        },
      );

      final entries = BetEngine.computeAll(round);
      print('[O8.1] B9 oyeses: ${entries.map((e) => '${e.fromPlayerId}→${e.toPlayerId} H${e.hole}').toList()}');

      expect(entries.length, equals(2), reason: 'H12 y H15 son par-3 de B9 → 2 cobros');
      expect(entries.every((e) => e.hole == 12 || e.hole == 15), isTrue);
    });

    test('O8.2 – Curso parcial F9 (H1-9): no accede a hoyos 10-18', () {
      final mod = _oyesesMod(['A', 'B'], value: 50);
      // Intentar poner rankings en H10-18 que no existen en _courseF9
      final round = _makeRound(
        playerIds: ['A', 'B'],
        mod: mod,
        course: _courseF9,
        totalHoles: 9,
        oyeseRankings: {
          3:  OyeseRanking(hole: 3,  ranking: ['A', 'B']),
          12: OyeseRanking(hole: 12, ranking: ['A', 'B']), // H12 no existe en F9
        },
      );

      expect(() => BetEngine.computeAll(round), returnsNormally,
          reason: 'Acceso a hoyo no existente en el curso no debe causar crash');

      final entries = BetEngine.computeAll(round);
      // H12 no está en _courseF9 → solo H3 es par-3 elegible
      expect(entries.length, equals(1));
      expect(entries.first.hole, equals(3));
    });

    test('O8.3 – Sin hoyos jugados (oyeseRankings vacío): 0 entradas, sin crash', () {
      final mod = _oyesesMod(['A', 'B'], value: 50);
      final round = _makeRound(
        playerIds: ['A', 'B'],
        mod: mod,
        course: _courseB9,
        totalHoles: 9,
        startingNine: StartingNine.back,
      );

      expect(() => BetEngine.computeAll(round), returnsNormally);
      expect(BetEngine.computeAll(round), isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // CASO 9 — AUDITORÍA: Oyeses NO usa gross scores ni eventos
  // ───────────────────────────────────────────────────────────────────────────
  group('O9 – AUDITORÍA: Oyeses ignora gross scores y eventos', () {

    test('O9.1 – Ranking diferente del score: el ranking manda, no el gross', () {
      // A tiene mejor score (gross=2 en H3) pero el ranking dice B>A.
      // El engine debe usar el ranking, no el score.
      final mod = _oyesesMod(['A', 'B'], value: 50);
      final scores = {
        'A': {3: HoleScore(playerId: 'A', hole: 3, grossScore: 2, putts: 0)}, // hole in one
        'B': {3: HoleScore(playerId: 'B', hole: 3, grossScore: 4, putts: 1)}, // bogey
      };
      final rPlayers = [
        RoundPlayer(playerId: 'A', handicapEnRonda: 0),
        RoundPlayer(playerId: 'B', handicapEnRonda: 0),
      ];
      final group = BetGroup(
        id: 'g1', name: 'G1', format: PartidaFormat.allInOnePot,
        playerIds: ['A', 'B'], modules: [mod],
      );
      final round = Round(
        id: 'test', name: 'Test',
        course: _course18,
        players: [Player(id:'A',name:'A',handicapBase:0), Player(id:'B',name:'B',handicapBase:0)],
        roundPlayers: rPlayers,
        betGroups: [group],
        scores: scores,
        events: const {},
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['B', 'A']), // B primero, aunque A tiene mejor score
        },
        sliding: const [],
        createdAt: DateTime(2025),
        totalHoles: 18,
      );

      final entries = BetEngine.computeAll(round);
      print('[O9.1] Score A=2(HiO), B=4, ranking B>A: ${entries.map((e) => '${e.fromPlayerId}→${e.toPlayerId}').toList()}');

      // El engine respeta el RANKING, no el score → B gana
      expect(entries.length, equals(1));
      expect(entries.first.toPlayerId, equals('B'),
          reason: 'El engine usa el ranking manual, no el gross score');
      expect(entries.first.fromPlayerId, equals('A'));
    });

    test('O9.2 – Sin oyeseRankings pero con scores en par-3: 0 entradas', () {
      // A tiene mejor score en H3 pero no hay ranking → sin cobros.
      final mod = _oyesesMod(['A', 'B'], value: 50);
      final scores = {
        'A': {3: HoleScore(playerId: 'A', hole: 3, grossScore: 3, putts: 1)},
        'B': {3: HoleScore(playerId: 'B', hole: 3, grossScore: 4, putts: 1)},
      };
      final rPlayers = [
        RoundPlayer(playerId: 'A', handicapEnRonda: 0),
        RoundPlayer(playerId: 'B', handicapEnRonda: 0),
      ];
      final group = BetGroup(
        id: 'g1', name: 'G1', format: PartidaFormat.allInOnePot,
        playerIds: ['A', 'B'], modules: [mod],
      );
      final round = Round(
        id: 'test', name: 'Test',
        course: _course18,
        players: [Player(id:'A',name:'A',handicapBase:0), Player(id:'B',name:'B',handicapBase:0)],
        roundPlayers: rPlayers,
        betGroups: [group],
        scores: scores,
        events: const {},
        oyeseRankings: const {}, // SIN RANKINGS
        sliding: const [],
        createdAt: DateTime(2025),
        totalHoles: 18,
      );

      expect(BetEngine.computeAll(round), isEmpty,
          reason: 'Sin rankings Oyeses no genera cobros aunque haya scores en par-3');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // CASO 10 — Correctness del cálculo (verificación matemática)
  // ───────────────────────────────────────────────────────────────────────────
  group('O10 – Correctness matemática', () {

    test('O10.1 – N=4 jugadores en 1 hoyo: C(4,2)=6 cobros', () {
      // [A,B,C,D]: 6 pares, cada uno un cobro.
      final mod = _oyesesMod(['A','B','C','D'], value: 25);
      final round = _makeRound(
        playerIds: ['A','B','C','D'],
        mod: mod,
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A','B','C','D']),
        },
      );

      final entries = BetEngine.computeAll(round);
      print('[O10.1] 4 jugadores H3: ${entries.length} cobros');

      expect(entries.length, equals(6),
          reason: 'C(4,2)=6 pares → 6 cobros');
      // A recibe de B, C, D (3 cobros)
      expect(entries.where((e) => e.toPlayerId == 'A').length, equals(3));
      // D paga a A, B, C (3 cobros)
      expect(entries.where((e) => e.fromPlayerId == 'D').length, equals(3));
    });

    test('O10.2 – Monto unitario correcto: cada cobro es exactamente cfg.value', () {
      final mod = _oyesesMod(['A','B','C'], value: 75);
      final round = _makeRound(
        playerIds: ['A','B','C'],
        mod: mod,
        oyeseRankings: {3: OyeseRanking(hole: 3, ranking: ['A','B','C'])},
      );

      final entries = BetEngine.computeAll(round);
      for (final e in entries) {
        expect(e.amount, closeTo(75, 0.01),
            reason: 'Cada cobro es exactamente cfg.value=\$75');
      }
    });

    test('O10.3 – Total cobrado por A en H3 con 4 jugadores = 3 × value', () {
      // A es 1°, recibe de B, C, D → total = 3 × value.
      final mod = _oyesesMod(['A','B','C','D'], value: 50);
      final round = _makeRound(
        playerIds: ['A','B','C','D'],
        mod: mod,
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A','B','C','D']),
        },
      );

      final entries = BetEngine.computeAll(round);
      final aReceives = entries
          .where((e) => e.toPlayerId == 'A')
          .fold<double>(0, (s, e) => s + e.amount);
      expect(aReceives, closeTo(150, 0.01), reason: '3 × \$50 = \$150');
    });

    test('O10.4 – Dirección de cobro: winner=posición menor recibe del loser=posición mayor', () {
      // ranking = [X, Y] → X(pos0) gana, Y(pos1) pierde → Y paga a X
      final mod = _oyesesMod(['X','Y'], value: 100);
      final round = _makeRound(
        playerIds: ['X','Y'],
        mod: mod,
        oyeseRankings: {6: OyeseRanking(hole: 6, ranking: ['X','Y'])},
      );

      final entries = BetEngine.computeAll(round);
      expect(entries.length, equals(1));
      expect(entries.first.fromPlayerId, equals('Y'));
      expect(entries.first.toPlayerId,   equals('X'));
    });
  });
}
