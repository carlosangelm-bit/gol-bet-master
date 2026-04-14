// ignore_for_file: avoid_print
// =============================================================================
// Auditoría de Oyeses — Parte 2
//
// CONCLUSIÓN ANTICIPADA (documentada aquí para el lector):
//
// Oyeses es un juego de RANKING POR HOYO (closest-to-pin / posición relativa),
// NO de eventos especiales. El engine usa:
//   - round.getOyese(hole) → OyeseRanking{hole, ranking: List<String>}
//   - El ranking es asignado manualmente por el scorer en la UI
//   - No usa gross/net scores, ni detección automática de birdie/eagle/GIR
//   - Cada posición distinta cobra a las posiciones inferiores (1° cobra a 2°,3°; 2° cobra a 3°...)
//   - El zapato requiere que un jugador sea 1° en TODOS los oyeses elegibles
//
// Hipótesis confirmada: HIPÓTESIS A (ranking por hoyo) — no B (eventos especiales).
//
// Estructura de cobros por par de posiciones (i < j):
//   rank[i] gana vs rank[j] → entrada rank[j] → rank[i] por cfg.value
//   Con 3 jugadores (A,B,C) en 1 hoyo → 3 entradas: A→B, A→C, B→C
//   Con 2 jugadores (A,B)              → 1 entrada: A→B
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Cursos de test
// ─────────────────────────────────────────────────────────────────────────────

/// 18 hoyos: hoyos 3, 7, 12, 16 son par-3. Resto par-4.
final _coursePar3x4 = CourseInfo(
  name: 'Course 4xPar3',
  holes: List.generate(18, (i) {
    final h = i + 1;
    final isPar3 = [3, 7, 12, 16].contains(h);
    return CourseHole(hole: h, par: isPar3 ? 3 : 4, strokeIndex: i + 1);
  }),
);

/// 18 hoyos: solo hoyo 5 es par-3.
final _course1Par3 = CourseInfo(
  name: 'Course 1xPar3',
  holes: List.generate(18, (i) {
    final h = i + 1;
    return CourseHole(hole: h, par: h == 5 ? 3 : 4, strokeIndex: i + 1);
  }),
);

/// 18 hoyos: hoyos 2, 8, 15 son par-3.
final _course3Par3 = CourseInfo(
  name: 'Course 3xPar3',
  holes: List.generate(18, (i) {
    final h = i + 1;
    final isPar3 = [2, 8, 15].contains(h);
    return CourseHole(hole: h, par: isPar3 ? 3 : 4, strokeIndex: i + 1);
  }),
);

/// 9 hoyos (back nine, 10-18): hoyo 13 es par-3.
final _courseB9par3 = CourseInfo(
  name: 'B9 1xPar3',
  holes: List.generate(9, (i) {
    final h = i + 10;
    return CourseHole(hole: h, par: h == 13 ? 3 : 4, strokeIndex: i + 1);
  }),
);

/// 18 hoyos todos par-4 (sin par-3 → no hay oyeses).
final _courseNoPar3 = CourseInfo(
  name: 'No Par3 Course',
  holes: List.generate(18, (i) =>
      CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)),
);

// ─────────────────────────────────────────────────────────────────────────────
// Factory
// ─────────────────────────────────────────────────────────────────────────────

Round _makeRound({
  required List<String> pids,
  required List<BetGroup> groups,
  Map<int, OyeseRanking> oyeseRankings = const {},
  CourseInfo? course,
  int totalHoles = 18,
  StartingNine startingNine = StartingNine.front,
}) {
  final c = course ?? _coursePar3x4;
  return Round(
    id: 'oyese-test',
    name: 'Oyeses Audit',
    course: c,
    players: pids.map((id) => Player(id: id, name: id, handicapBase: 0)).toList(),
    roundPlayers: pids.map((id) => RoundPlayer(playerId: id, handicapEnRonda: 0)).toList(),
    betGroups: groups,
    scores: const {},
    events: const {},
    oyeseRankings: oyeseRankings,
    sliding: const [],
    createdAt: DateTime(2025, 1, 1),
    totalHoles: totalHoles,
    startingNine: startingNine,
  );
}

BetModuleInstance _oyesesMod(
  List<String> pids, {
  double value = 50,
  bool zapato = false,
  double zapatoValue = 0,
  bool zapatoRequires18 = false,
  List<int> eligibleHoles = const [],
  BetFormatMode formatMode = BetFormatMode.onePot,
}) {
  final base = BetModuleInstance.defaultFor(BetModuleType.oyeses, pids).copyWith(
    oyesesConfig: OyesesConfig(
      value: value,
      zapatoEnabled: zapato,
      zapatoValue: zapatoValue,
      zapatoRequires18: zapatoRequires18,
      eligibleHoles: eligibleHoles,
    ),
    formatMode: formatMode,
  );
  return base;
}

BetGroup _group(List<String> pids, BetModuleInstance mod) => BetGroup(
      id: 'g1',
      name: 'Oyeses Group',
      format: PartidaFormat.allInOnePot,
      playerIds: pids,
      modules: [mod],
    );

// Helper: extrae entradas de Oyeses del ledger completo
List<LedgerEntry> _oyesEntries(List<LedgerEntry> all) =>
    all.where((e) => e.betType == BetModuleType.oyeses).toList();

// Helper: entradas de un hoyo concreto
List<LedgerEntry> _entriesForHole(List<LedgerEntry> entries, int hole) =>
    entries.where((e) => e.hole == hole).toList();

// Helper: entry de ganador → perdedor
LedgerEntry? _find(List<LedgerEntry> entries, String from, String to) =>
    entries.where((e) => e.fromPlayerId == from && e.toPlayerId == to).firstOrNull;

// =============================================================================
// SUITE
// =============================================================================

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // AUDITORÍA: qué calcula Oyeses
  // ─────────────────────────────────────────────────────────────────────────
  group('AUDIT – Qué calcula realmente Oyeses', () {

    test('AUDIT.1 – usa ranking por hoyo, NO gross/net scores automáticos', () {
      // Si Oyeses fuera por gross/net, necesitaría scores.
      // Si es por ranking manual, funciona sin scores y SOLO depende de oyeseRankings.
      final pids = ['A', 'B', 'C'];
      final mod  = _oyesesMod(pids);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        // Sin scores → si fuera por score, no habría entradas
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A', 'B', 'C']),
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      print('[AUDIT.1] Entries sin scores: ${entries.map((e) => '${e.fromPlayerId}→${e.toPlayerId} H${e.hole}').toList()}');

      // Con ranking manual pero SIN gross scores → el engine SIGUE generando entradas
      // Esto confirma: Oyeses es por ranking manual, no por score automático.
      expect(entries, isNotEmpty,
          reason: 'CONFIRMADO: Oyeses usa ranking manual, no gross scores. '
              'Sin scores pero con oyeseRankings → entradas generadas.');
    });

    test('AUDIT.2 – sin oyeseRankings → 0 entradas (no hay ranking qué usar)', () {
      final pids = ['A', 'B'];
      final mod  = _oyesesMod(pids);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        // oyeseRankings vacío
        oyeseRankings: const {},
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      expect(entries, isEmpty,
          reason: 'Sin oyeseRankings → 0 entradas (confirma dependencia del ranking manual)');
    });

    test('AUDIT.3 – ranking con solo 1 jugador en hoyo elegible → no genera entrada', () {
      // El engine requiere ≥ 2 jugadores en el ranking para liquidar
      final pids = ['A', 'B', 'C'];
      final mod  = _oyesesMod(pids);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A']), // solo 1 → no se liquida
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      expect(entries, isEmpty,
          reason: 'Ranking con 1 jugador no genera cobros');
    });

    test('AUDIT.4 – NO usa eventos especiales (birdie/eagle/GIR): son módulo Units separado', () {
      // Oyeses no registra eventos como birdie/eagle. Eso es módulo Units.
      // Confirmado por code: _oyeses() solo lee round.getOyese(hole).ranking,
      // nunca round.getEvents() ni gross comparison vs par.
      //
      // Este test documenta que si ponemos eventos en el round pero no ranking,
      // Oyeses produce 0 entradas.
      final pids = ['A', 'B'];
      final mod  = _oyesesMod(pids);
      final round = Round(
        id: 'oyese-test',
        name: 'Oyeses Audit',
        course: _course1Par3,
        players: pids.map((id) => Player(id: id, name: id, handicapBase: 0)).toList(),
        roundPlayers: pids.map((id) => RoundPlayer(playerId: id, handicapEnRonda: 0)).toList(),
        betGroups: [_group(pids, mod)],
        scores: const {},
        // Evento de birdie en hoyo 5 (par-3)
        events: {
          'A': {
            5: [HoleEvent(playerId: 'A', hole: 5, type: UnitEventType.birdie)],
          },
        },
        oyeseRankings: const {}, // sin ranking manual
        sliding: const [],
        createdAt: DateTime(2025),
        totalHoles: 18,
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      expect(entries, isEmpty,
          reason: 'CONFIRMADO: Oyeses ignora eventos de birdie/eagle. '
              'Solo lee oyeseRankings. Eventos especiales = módulo Units.');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // CASO 1 — Ranking simple, 3 jugadores, 1 hoyo
  // ─────────────────────────────────────────────────────────────────────────
  group('O1 – Ranking simple: 3 jugadores, 1 hoyo elegible', () {

    test('O1.1 – ranking A > B > C: 3 entradas correctas (todas las combinaciones de pares)', () {
      // En hoyo H3 (par-3): A=1°, B=2°, C=3°
      // Cobros esperados: B→A $50, C→A $50, C→B $50
      final pids = ['A', 'B', 'C'];
      final mod  = _oyesesMod(pids, value: 50);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A', 'B', 'C']),
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      print('[O1.1] 3 jugadores 1 hoyo: ${entries.map((e) => '${e.fromPlayerId}→${e.toPlayerId} \$${e.amount}').toList()}');

      expect(entries.length, equals(3),
          reason: '3 jugadores → C(3,2)=3 pares → 3 entradas');

      // B paga a A
      final bToA = _find(entries, 'B', 'A');
      expect(bToA, isNotNull);
      expect(bToA!.amount, closeTo(50, 0.01));

      // C paga a A
      final cToA = _find(entries, 'C', 'A');
      expect(cToA, isNotNull);
      expect(cToA!.amount, closeTo(50, 0.01));

      // C paga a B
      final cToB = _find(entries, 'C', 'B');
      expect(cToB, isNotNull);
      expect(cToB!.amount, closeTo(50, 0.01));
    });

    test('O1.2 – ranking B > A > C: cobros en dirección correcta', () {
      // H3: B=1°, A=2°, C=3°
      // Esperado: A→B, C→B, C→A
      final pids = ['A', 'B', 'C'];
      final mod  = _oyesesMod(pids, value: 50);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['B', 'A', 'C']),
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      expect(entries.length, equals(3));

      expect(_find(entries, 'A', 'B'), isNotNull, reason: 'A paga a B (2° vs 1°)');
      expect(_find(entries, 'C', 'B'), isNotNull, reason: 'C paga a B (3° vs 1°)');
      expect(_find(entries, 'C', 'A'), isNotNull, reason: 'C paga a A (3° vs 2°)');
    });

    test('O1.3 – 2 jugadores, 1 hoyo: exactamente 1 entrada', () {
      final pids = ['A', 'B'];
      final mod  = _oyesesMod(pids, value: 75);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A', 'B']),
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      expect(entries.length, equals(1));
      expect(entries.first.fromPlayerId, equals('B'));
      expect(entries.first.toPlayerId,   equals('A'));
      expect(entries.first.amount, closeTo(75, 0.01));
      expect(entries.first.hole, equals(3));
    });

    test('O1.4 – hoyo en el reporte tiene el número correcto', () {
      final pids = ['A', 'B'];
      final mod  = _oyesesMod(pids);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        oyeseRankings: {
          7: OyeseRanking(hole: 7, ranking: ['B', 'A']),
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      expect(entries.length, equals(1));
      expect(entries.first.hole, equals(7), reason: 'El hole number debe ser 7');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // CASO 2 — Múltiples hoyos elegibles
  // ─────────────────────────────────────────────────────────────────────────
  group('O2 – Múltiples hoyos elegibles', () {

    test('O2.1 – 4 par-3, todos con ranking: 4×C(2,1)=4 entradas para 2 jugadores', () {
      final pids = ['A', 'B'];
      final mod  = _oyesesMod(pids, value: 50);
      // A gana todos los hoyos
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        oyeseRankings: {
          3:  OyeseRanking(hole: 3,  ranking: ['A', 'B']),
          7:  OyeseRanking(hole: 7,  ranking: ['A', 'B']),
          12: OyeseRanking(hole: 12, ranking: ['A', 'B']),
          16: OyeseRanking(hole: 16, ranking: ['A', 'B']),
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      print('[O2.1] 4 hoyos 2 jugadores: ${entries.length} entradas');

      expect(entries.length, equals(4),
          reason: '4 hoyos × 1 par = 4 entradas');
      // Todas de B hacia A
      expect(entries.every((e) => e.fromPlayerId == 'B' && e.toPlayerId == 'A'), isTrue);
      // Todas por $50
      expect(entries.every((e) => (e.amount - 50).abs() < 0.01), isTrue);
    });

    test('O2.2 – hoyos alternados entre A y B: entradas en ambas direcciones', () {
      final pids = ['A', 'B'];
      final mod  = _oyesesMod(pids, value: 50);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        oyeseRankings: {
          3:  OyeseRanking(hole: 3,  ranking: ['A', 'B']), // A gana
          7:  OyeseRanking(hole: 7,  ranking: ['B', 'A']), // B gana
          12: OyeseRanking(hole: 12, ranking: ['A', 'B']), // A gana
          16: OyeseRanking(hole: 16, ranking: ['B', 'A']), // B gana
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      expect(entries.length, equals(4));

      final bToA = entries.where((e) => e.fromPlayerId == 'B' && e.toPlayerId == 'A').length;
      final aToB = entries.where((e) => e.fromPlayerId == 'A' && e.toPlayerId == 'B').length;
      expect(bToA, equals(2), reason: 'A gana 2 hoyos → 2 entradas B→A');
      expect(aToB, equals(2), reason: 'B gana 2 hoyos → 2 entradas A→B');
    });

    test('O2.3 – 3 jugadores, 2 hoyos: 2×3=6 entradas totales', () {
      final pids = ['A', 'B', 'C'];
      final mod  = _oyesesMod(pids, value: 50);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        oyeseRankings: {
          3: OyeseRanking(hole: 3,  ranking: ['A', 'B', 'C']),
          7: OyeseRanking(hole: 7,  ranking: ['A', 'B', 'C']),
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      print('[O2.3] 3J 2H: ${entries.length} entradas');
      expect(entries.length, equals(6),
          reason: '2 hoyos × 3 pares C(3,2) = 6 entradas');
    });

    test('O2.4 – monto total correcto (suma de todas las entradas)', () {
      // 3 jugadores, 2 hoyos, $50/oyés → total = 6 entradas × $50 = $300
      final pids = ['A', 'B', 'C'];
      final mod  = _oyesesMod(pids, value: 50);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A', 'B', 'C']),
          7: OyeseRanking(hole: 7, ranking: ['A', 'B', 'C']),
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      final totalAmount = entries.fold(0.0, (sum, e) => sum + e.amount);
      expect(totalAmount, closeTo(300, 0.01),
          reason: '6 entradas × \$50 = \$300');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // CASO 3 — Zapato onePot
  // ─────────────────────────────────────────────────────────────────────────
  group('O3 – Zapato onePot', () {

    test('O3.1 – A gana todos los oyeses: zapato de A cobra a B y C', () {
      // 3 par-3, A gana todos. zapatoEnabled=true, zapatoRequires18=false.
      // zapato automático = 3 oyeses × $50 = $150 por jugador.
      final pids = ['A', 'B', 'C'];
      final mod  = _oyesesMod(pids, value: 50, zapato: true, zapatoRequires18: false);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        course: _course3Par3, // hoyos 2, 8, 15 son par-3
        oyeseRankings: {
          2:  OyeseRanking(hole: 2,  ranking: ['A', 'B', 'C']),
          8:  OyeseRanking(hole: 8,  ranking: ['A', 'B', 'C']),
          15: OyeseRanking(hole: 15, ranking: ['A', 'B', 'C']),
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      print('[O3.1] Zapato onePot: ${entries.map((e) => '${e.fromPlayerId}→${e.toPlayerId} ${e.reason} \$${e.amount}').toList()}');

      // Entradas normales: 3 hoyos × C(3,2) = 9
      // + zapato: B→A $150, C→A $150 = 2 entradas de zapato
      final zapatoEntries = entries.where((e) => e.reason.contains('Zapato')).toList();
      expect(zapatoEntries.length, equals(2),
          reason: '2 jugadores pagan zapato a A (B→A y C→A)');

      final bZapato = zapatoEntries.where((e) => e.fromPlayerId == 'B' && e.toPlayerId == 'A').firstOrNull;
      final cZapato = zapatoEntries.where((e) => e.fromPlayerId == 'C' && e.toPlayerId == 'A').firstOrNull;
      expect(bZapato, isNotNull);
      expect(cZapato, isNotNull);
      // Monto del zapato = 3 oyeses × $50 = $150
      expect(bZapato!.amount, closeTo(150, 0.01));
      expect(cZapato!.amount, closeTo(150, 0.01));
    });

    test('O3.2 – zapato no se dispara si no gana TODOS los oyeses', () {
      // A gana 2 de 3 oyeses → no hay zapato
      final pids = ['A', 'B', 'C'];
      final mod  = _oyesesMod(pids, value: 50, zapato: true, zapatoRequires18: false);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        course: _course3Par3,
        oyeseRankings: {
          2:  OyeseRanking(hole: 2,  ranking: ['A', 'B', 'C']),
          8:  OyeseRanking(hole: 8,  ranking: ['A', 'B', 'C']),
          15: OyeseRanking(hole: 15, ranking: ['B', 'A', 'C']), // B gana H15
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      final zapatoEntries = entries.where((e) => e.reason.contains('Zapato')).toList();
      expect(zapatoEntries, isEmpty,
          reason: 'Sin zapato: A no ganó TODOS los oyeses');
    });

    test('O3.3 – zapatoValue fijo: usa ese monto en lugar del automático', () {
      final pids = ['A', 'B'];
      final mod  = _oyesesMod(pids, value: 50, zapato: true,
          zapatoValue: 500, zapatoRequires18: false);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        course: _course1Par3,
        oyeseRankings: {
          5: OyeseRanking(hole: 5, ranking: ['A', 'B']),
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      final zapatoE = entries.where((e) => e.reason.contains('Zapato')).toList();
      expect(zapatoE, isNotEmpty);
      expect(zapatoE.first.amount, closeTo(500, 0.01),
          reason: 'zapatoValue fijo debe usarse en lugar del automático');
    });

    test('O3.4 – zapato disabled: no se genera aunque A gane todo', () {
      final pids = ['A', 'B'];
      final mod  = _oyesesMod(pids, value: 50, zapato: false);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        course: _course1Par3,
        oyeseRankings: {
          5: OyeseRanking(hole: 5, ranking: ['A', 'B']),
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      final zapatoE = entries.where((e) => e.reason.contains('Zapato')).toList();
      expect(zapatoE, isEmpty, reason: 'zapatoEnabled=false → sin zapato');
    });

    test('O3.5 – zapatoRequires18=true con solo 1 par-3 → NO zapato', () {
      // zapatoRequires18=true exige ≥ 3 par-3. Con 1 par-3 → no aplica.
      final pids = ['A', 'B'];
      final mod  = _oyesesMod(pids, value: 50, zapato: true, zapatoRequires18: true);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        course: _course1Par3, // solo 1 par-3
        oyeseRankings: {
          5: OyeseRanking(hole: 5, ranking: ['A', 'B']),
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      final zapatoE = entries.where((e) => e.reason.contains('Zapato')).toList();
      expect(zapatoE, isEmpty,
          reason: 'zapatoRequires18 con solo 1 par-3 → no hay zapato');
    });

    test('O3.6 – zapatoRequires18=true con 3 par-3 → SÍ zapato', () {
      final pids = ['A', 'B'];
      final mod  = _oyesesMod(pids, value: 50, zapato: true, zapatoRequires18: true);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        course: _course3Par3, // 3 par-3: hoyos 2, 8, 15
        oyeseRankings: {
          2:  OyeseRanking(hole: 2,  ranking: ['A', 'B']),
          8:  OyeseRanking(hole: 8,  ranking: ['A', 'B']),
          15: OyeseRanking(hole: 15, ranking: ['A', 'B']),
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      final zapatoE = entries.where((e) => e.reason.contains('Zapato')).toList();
      expect(zapatoE, isNotEmpty,
          reason: 'zapatoRequires18 con 3 par-3 → SÍ hay zapato');
      expect(zapatoE.first.amount, closeTo(150, 0.01),
          reason: 'Monto zapato = 3 oyeses × \$50 = \$150');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // CASO 4 — Zapato allVsAll
  // ─────────────────────────────────────────────────────────────────────────
  group('O4 – Zapato allVsAll', () {

    test('O4.1 – A gana todos los oyeses vs B y C: zapato de A vs B y A vs C', () {
      // 3 par-3, A siempre 1°. En allVsAll: A hace zapato vs B y vs C por separado.
      final pids = ['A', 'B', 'C'];
      final mod  = _oyesesMod(pids, value: 50, zapato: true,
          zapatoRequires18: false,
          formatMode: BetFormatMode.allVsAll);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        course: _course3Par3,
        oyeseRankings: {
          2:  OyeseRanking(hole: 2,  ranking: ['A', 'B', 'C']),
          8:  OyeseRanking(hole: 8,  ranking: ['A', 'B', 'C']),
          15: OyeseRanking(hole: 15, ranking: ['A', 'B', 'C']),
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      final zapatoE = entries.where((e) => e.reason.contains('Zapato AvA')).toList();
      print('[O4.1] Zapato AvA: ${zapatoE.map((e) => '${e.fromPlayerId}→${e.toPlayerId} \$${e.amount}').toList()}');

      // Con A=1°, B=2°, C=3° en los 3 hoyos:
      //   A ganó todos los oyeses vs B → zapato B→A
      //   A ganó todos los oyeses vs C → zapato C→A
      //   B ganó todos los oyeses vs C (siempre B=2°, C=3°) → zapato C→B
      // El engine AvA genera 3 zapatos totales (C(3,2) = 3 pares posibles).
      expect(zapatoE.length, equals(3),
          reason: 'Con 3 jugadores ordenados siempre igual, hay 3 pares con zapato');
      final bToA = zapatoE.where((e) => e.fromPlayerId == 'B' && e.toPlayerId == 'A');
      final cToA = zapatoE.where((e) => e.fromPlayerId == 'C' && e.toPlayerId == 'A');
      final cToB = zapatoE.where((e) => e.fromPlayerId == 'C' && e.toPlayerId == 'B');
      expect(bToA, isNotEmpty, reason: 'A hace zapato vs B');
      expect(cToA, isNotEmpty, reason: 'A hace zapato vs C');
      expect(cToB, isNotEmpty, reason: 'B hace zapato vs C (B siempre 2°, C siempre 3°)');
      expect(zapatoE.every((e) => (e.amount - 150).abs() < 0.01), isTrue);
    });

    test('O4.2 – A gana vs B pero no vs C: zapato solo A vs B', () {
      // H2: A>B>C, H8: A>B>C, H15: C>A>B → A perdió vs C en H15
      // A hizo zapato vs B (ganó todos A-vs-B), pero NO vs C (perdió H15)
      final pids = ['A', 'B', 'C'];
      final mod  = _oyesesMod(pids, value: 50, zapato: true,
          zapatoRequires18: false,
          formatMode: BetFormatMode.allVsAll);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        course: _course3Par3,
        oyeseRankings: {
          2:  OyeseRanking(hole: 2,  ranking: ['A', 'B', 'C']),
          8:  OyeseRanking(hole: 8,  ranking: ['A', 'B', 'C']),
          15: OyeseRanking(hole: 15, ranking: ['C', 'A', 'B']), // C gana
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      final zapatoE = entries.where((e) => e.reason.contains('Zapato AvA')).toList();
      print('[O4.2] Zapato selectivo AvA: ${zapatoE.map((e) => '${e.fromPlayerId}→${e.toPlayerId}').toList()}');

      // Solo 1 zapato: B→A (A ganó los 3 vs B)
      final bToA = zapatoE.where((e) => e.fromPlayerId == 'B' && e.toPlayerId == 'A').toList();
      final cToA = zapatoE.where((e) => e.fromPlayerId == 'C' && e.toPlayerId == 'A').toList();
      expect(bToA.length, equals(1), reason: 'B paga zapato a A');
      expect(cToA, isEmpty, reason: 'C no paga zapato: A no ganó todos vs C');
    });

    test('O4.3 – empate en oyeses allVsAll: sin zapatos si nadie gana todos vs otro', () {
      // H3: A>B, H7: B>A → cada uno ganó 1 vs el otro → no hay zapato
      final pids = ['A', 'B'];
      final mod  = _oyesesMod(pids, value: 50, zapato: true,
          zapatoRequires18: false,
          formatMode: BetFormatMode.allVsAll);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A', 'B']),
          7: OyeseRanking(hole: 7, ranking: ['B', 'A']),
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      final zapatoE = entries.where((e) => e.reason.contains('Zapato')).toList();
      expect(zapatoE, isEmpty,
          reason: 'Nadie ganó todos vs el otro → sin zapato');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // CASO 5 — Hoyos incompletos (sin ranking en algunos par-3)
  // ─────────────────────────────────────────────────────────────────────────
  group('O5 – Hoyos incompletos', () {

    test('O5.1 – hoyo par-3 sin ranking: se ignora, no truena', () {
      final pids = ['A', 'B'];
      final mod  = _oyesesMod(pids);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        // H3 sin ranking, H7 con ranking
        oyeseRankings: {
          7: OyeseRanking(hole: 7, ranking: ['A', 'B']),
        },
      );

      expect(() => BetEngine.computeAll(round), returnsNormally);
      final entries = _oyesEntries(BetEngine.computeAll(round));
      expect(entries.length, equals(1), reason: 'Solo H7 tiene ranking → 1 entrada');
      expect(entries.first.hole, equals(7));
    });

    test('O5.2 – ningún hoyo con ranking: 0 entradas, no truena', () {
      final pids = ['A', 'B', 'C'];
      final mod  = _oyesesMod(pids);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        oyeseRankings: const {},
      );

      expect(() => BetEngine.computeAll(round), returnsNormally);
      expect(_oyesEntries(BetEngine.computeAll(round)), isEmpty);
    });

    test('O5.3 – ranking parcial (falta un jugador): solo liquida los que aparecen', () {
      // H3: ranking solo tiene A y B, falta C. C no participa en ese hoyo.
      final pids = ['A', 'B', 'C'];
      final mod  = _oyesesMod(pids);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A', 'B']), // C ausente
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      print('[O5.3] Ranking parcial: ${entries.map((e) => '${e.fromPlayerId}→${e.toPlayerId}').toList()}');

      // Solo 1 par (A vs B) → 1 entrada
      expect(entries.length, equals(1));
      // C no aparece en ningún lado
      expect(entries.any((e) => e.fromPlayerId == 'C' || e.toPlayerId == 'C'), isFalse);
    });

    test('O5.4 – zapato no se dispara si no están todos los hoyos con ranking', () {
      // 3 par-3 elegibles, solo 2 tienen ranking → holesWithRanking(2) ≠ totalEligible(3)
      final pids = ['A', 'B'];
      final mod  = _oyesesMod(pids, value: 50, zapato: true, zapatoRequires18: false);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        course: _course3Par3, // 3 par-3: 2, 8, 15
        oyeseRankings: {
          2: OyeseRanking(hole: 2, ranking: ['A', 'B']),
          8: OyeseRanking(hole: 8, ranking: ['A', 'B']),
          // H15 sin ranking
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      final zapatoE = entries.where((e) => e.reason.contains('Zapato')).toList();
      expect(zapatoE, isEmpty,
          reason: 'Zapato requiere TODOS los hoyos elegibles con ranking');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // CASO 6 — eligibleHoles (filtro de hoyos específicos)
  // ─────────────────────────────────────────────────────────────────────────
  group('O6 – eligibleHoles: solo cuentan los hoyos permitidos', () {

    test('O6.1 – eligibleHoles=[3]: solo H3 cuenta, H7 ignorado aunque sea par-3', () {
      final pids = ['A', 'B'];
      final mod  = _oyesesMod(pids, eligibleHoles: [3]);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A', 'B']),
          7: OyeseRanking(hole: 7, ranking: ['B', 'A']), // ignorado
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      expect(entries.length, equals(1));
      expect(entries.first.hole, equals(3), reason: 'Solo H3 cuenta');
      // A gana H3 → B→A
      expect(entries.first.toPlayerId, equals('A'));
    });

    test('O6.2 – eligibleHoles vacío: todos los par-3 son elegibles', () {
      final pids = ['A', 'B'];
      final mod  = _oyesesMod(pids, eligibleHoles: []); // vacío = todos
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        oyeseRankings: {
          3:  OyeseRanking(hole: 3,  ranking: ['A', 'B']),
          7:  OyeseRanking(hole: 7,  ranking: ['A', 'B']),
          12: OyeseRanking(hole: 12, ranking: ['A', 'B']),
          16: OyeseRanking(hole: 16, ranking: ['A', 'B']),
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      // 4 hoyos elegibles → 4 entradas
      expect(entries.length, equals(4));
    });

    test('O6.3 – eligibleHoles=[3,7]: hoyo no-par3 en lista se ignora de todas formas', () {
      // Si eligibleHoles=[3,7] pero H7 no es par-3 en el curso → se intersecta con par3
      // Nota: el engine filtra primero par3Holes, LUEGO intersecta con eligibleHoles.
      final courseConH7nopar3 = CourseInfo(
        name: 'H3par3 H7par4',
        holes: List.generate(18, (i) {
          final h = i + 1;
          return CourseHole(hole: h, par: h == 3 ? 3 : 4, strokeIndex: i + 1);
        }),
      );

      final pids = ['A', 'B'];
      final mod  = _oyesesMod(pids, eligibleHoles: [3, 7]);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        course: courseConH7nopar3,
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A', 'B']),
          7: OyeseRanking(hole: 7, ranking: ['B', 'A']), // H7 es par-4 → ignorado
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      // Solo H3 es par3 Y está en eligibleHoles → 1 entrada
      expect(entries.length, equals(1));
      expect(entries.first.hole, equals(3));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // CASO 7 — Filtro par-3
  // ─────────────────────────────────────────────────────────────────────────
  group('O7 – Filtro par-3: solo cuenta hoyos par-3', () {

    test('O7.1 – ranking en hoyo par-4: completamente ignorado', () {
      // El engine solo procesa hoyos donde ch.isPar3 == true.
      // Si ponemos ranking en un par-4, debe ignorarse.
      final pids = ['A', 'B'];
      final mod  = _oyesesMod(pids);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        // H1 es par-4 (course18 todos son par-4 menos los que configuramos)
        // _coursePar3x4 tiene par-3 en H3,H7,H12,H16
        oyeseRankings: {
          1: OyeseRanking(hole: 1, ranking: ['A', 'B']), // par-4 → ignorado
          2: OyeseRanking(hole: 2, ranking: ['A', 'B']), // par-4 → ignorado
          3: OyeseRanking(hole: 3, ranking: ['A', 'B']), // par-3 → cuenta
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      expect(entries.length, equals(1), reason: 'Solo H3 (par-3) genera entrada');
      expect(entries.first.hole, equals(3));
    });

    test('O7.2 – curso sin par-3: 0 entradas siempre', () {
      final pids = ['A', 'B'];
      final mod  = _oyesesMod(pids);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        course: _courseNoPar3,
        oyeseRankings: {
          // aunque pongamos rankings en todos los hoyos, ninguno es par-3
          for (int h = 1; h <= 18; h++)
            h: OyeseRanking(hole: h, ranking: ['A', 'B']),
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      expect(entries, isEmpty,
          reason: 'Curso sin par-3 → 0 entradas de Oyeses');
    });

    test('O7.3 – confirmar que par-3 se detecta por ch.par == 3', () {
      // Curso custom con par-3 en hoyo 10 (back nine)
      final customCourse = CourseInfo(
        name: 'Custom B9 Par3',
        holes: List.generate(18, (i) {
          final h = i + 1;
          return CourseHole(hole: h, par: h == 10 ? 3 : 4, strokeIndex: i + 1);
        }),
      );

      final pids = ['A', 'B'];
      final mod  = _oyesesMod(pids);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        course: customCourse,
        oyeseRankings: {
          10: OyeseRanking(hole: 10, ranking: ['A', 'B']),
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      expect(entries.length, equals(1), reason: 'H10 par-3 debe generar entrada');
      expect(entries.first.hole, equals(10));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // CASO 8 — startingNine / cursos parciales
  // ─────────────────────────────────────────────────────────────────────────
  group('O8 – startingNine y cursos parciales', () {

    test('O8.1 – curso back-nine con par-3 (H13): no accede a hoyos inexistentes', () {
      final pids = ['A', 'B'];
      final mod  = _oyesesMod(pids);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        course: _courseB9par3, // hoyos 10-18, H13 par-3
        totalHoles: 9,
        startingNine: StartingNine.back,
        oyeseRankings: {
          13: OyeseRanking(hole: 13, ranking: ['A', 'B']),
        },
      );

      expect(() => BetEngine.computeAll(round), returnsNormally,
          reason: 'No debe crashear con curso B9');

      final entries = _oyesEntries(BetEngine.computeAll(round));
      expect(entries.length, equals(1));
      expect(entries.first.hole, equals(13));
    });

    test('O8.2 – ranking en hoyo fuera del curso: ignorado, no truena', () {
      // Curso B9 (hoyos 10-18) pero ranking en H3 (que no existe en el curso)
      // El engine itera round.course.holes, por lo que H3 nunca se alcanza.
      final pids = ['A', 'B'];
      final mod  = _oyesesMod(pids);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        course: _courseB9par3,
        totalHoles: 9,
        startingNine: StartingNine.back,
        oyeseRankings: {
          3:  OyeseRanking(hole: 3,  ranking: ['A', 'B']), // fuera del curso B9
          13: OyeseRanking(hole: 13, ranking: ['A', 'B']), // en el curso
        },
      );

      expect(() => BetEngine.computeAll(round), returnsNormally);
      final entries = _oyesEntries(BetEngine.computeAll(round));
      // Solo H13 es par-3 en _courseB9par3
      expect(entries.length, equals(1));
      expect(entries.first.hole, equals(13));
    });

    test('O8.3 – ronda sin ningún hoyo jugado: 0 entradas Oyeses, no truena', () {
      final pids = ['A', 'B'];
      final mod  = _oyesesMod(pids);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        // sin oyeseRankings y sin scores
      );

      expect(() => BetEngine.computeAll(round), returnsNormally);
      expect(_oyesEntries(BetEngine.computeAll(round)), isEmpty);
    });

    test('O8.4 – varios módulos en misma ronda: Oyeses no interfiere con Nassau', () {
      final pids = ['A', 'B'];
      final nassauMod = BetModuleInstance.defaultFor(BetModuleType.nassau, pids).copyWith(
        nassauConfig: const NassauConfig(frontValue: 50, backValue: 50, totalValue: 100),
      );
      final oyesesModInst = _oyesesMod(pids);

      final group = BetGroup(
        id: 'g1',
        name: 'Multi',
        format: PartidaFormat.allInOnePot,
        playerIds: pids,
        modules: [nassauMod, oyesesModInst],
      );

      // Scores para Nassau
      final scoresA = List.generate(18, (_) => 3);
      final scoresB = List.generate(18, (_) => 4);
      final holeNums = List.generate(18, (i) => i + 1);
      final scoresMap = {
        'A': {for (int i = 0; i < 18; i++) holeNums[i]: HoleScore(playerId: 'A', hole: holeNums[i], grossScore: scoresA[i], putts: 2)},
        'B': {for (int i = 0; i < 18; i++) holeNums[i]: HoleScore(playerId: 'B', hole: holeNums[i], grossScore: scoresB[i], putts: 2)},
      };

      final round = Round(
        id: 'test',
        name: 'Multi',
        course: _coursePar3x4,
        players: pids.map((id) => Player(id: id, name: id, handicapBase: 0)).toList(),
        roundPlayers: pids.map((id) => RoundPlayer(playerId: id, handicapEnRonda: 0)).toList(),
        betGroups: [group],
        scores: scoresMap,
        events: const {},
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A', 'B']),
        },
        sliding: const [],
        createdAt: DateTime(2025),
        totalHoles: 18,
      );

      expect(() => BetEngine.computeAll(round), returnsNormally);
      final all = BetEngine.computeAll(round);
      final nassauE  = all.where((e) => e.betType == BetModuleType.nassau).toList();
      final oyesesE  = all.where((e) => e.betType == BetModuleType.oyeses).toList();

      expect(nassauE, isNotEmpty, reason: 'Nassau debe generar entradas');
      expect(oyesesE.length, equals(1), reason: 'Oyeses debe generar 1 entrada (H3)');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // AUDITORÍA FINAL — resumen de invariantes
  // ─────────────────────────────────────────────────────────────────────────
  group('AUDIT.FINAL – Invariantes del modelo de Oyeses', () {

    test('INV.1 – N jugadores en 1 hoyo → C(N,2) entradas = N*(N-1)/2', () {
      for (final n in [2, 3, 4]) {
        final pids = List.generate(n, (i) => 'P$i');
        final ranking = List<String>.from(pids); // P0 > P1 > ... > P(n-1)
        final mod  = _oyesesMod(pids);
        final round = _makeRound(
          pids: pids,
          groups: [_group(pids, mod)],
          oyeseRankings: {
            3: OyeseRanking(hole: 3, ranking: ranking),
          },
        );

        final entries = _oyesEntries(BetEngine.computeAll(round));
        final expected = n * (n - 1) ~/ 2;
        expect(entries.length, equals(expected),
            reason: '$n jugadores → C($n,2)=$expected entradas. Got ${entries.length}');
      }
    });

    test('INV.2 – el primer jugador del ranking SIEMPRE recibe de todos los demás', () {
      final pids = ['A', 'B', 'C', 'D'];
      final mod  = _oyesesMod(pids);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A', 'B', 'C', 'D']),
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      // A (1°) recibe de B, C, D → 3 entradas a A
      final toA = entries.where((e) => e.toPlayerId == 'A').toList();
      expect(toA.length, equals(3), reason: '1° recibe de todos los demás');
    });

    test('INV.3 – el último jugador del ranking SIEMPRE paga a todos los demás', () {
      final pids = ['A', 'B', 'C', 'D'];
      final mod  = _oyesesMod(pids);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A', 'B', 'C', 'D']),
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      // D (último) paga a A, B, C → 3 entradas de D
      final fromD = entries.where((e) => e.fromPlayerId == 'D').toList();
      expect(fromD.length, equals(3), reason: 'Último paga a todos los demás');
    });

    test('INV.4 – valor por entrada = cfg.value (constante por par)', () {
      final pids = ['A', 'B', 'C'];
      const myValue = 75.0;
      final mod  = _oyesesMod(pids, value: myValue);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A', 'B', 'C']),
          7: OyeseRanking(hole: 7, ranking: ['B', 'C', 'A']),
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      expect(entries.every((e) => (e.amount - myValue).abs() < 0.01), isTrue,
          reason: 'Cada entrada debe ser exactamente cfg.value=$myValue');
    });

    test('INV.5 – reason de cada entrada contiene "Oyés H{n}" con número correcto', () {
      final pids = ['A', 'B'];
      final mod  = _oyesesMod(pids);
      final round = _makeRound(
        pids: pids,
        groups: [_group(pids, mod)],
        oyeseRankings: {
          3: OyeseRanking(hole: 3, ranking: ['A', 'B']),
          7: OyeseRanking(hole: 7, ranking: ['A', 'B']),
        },
      );

      final entries = _oyesEntries(BetEngine.computeAll(round));
      final holeNumbers = entries.map((e) => e.hole).toSet();
      expect(holeNumbers, containsAll([3, 7]),
          reason: 'Las entradas deben referenciar los hoyos correctos');
      expect(entries.every((e) => e.reason.contains('Oyés H')), isTrue,
          reason: 'El reason debe contener "Oyés H"');
    });
  });
}
