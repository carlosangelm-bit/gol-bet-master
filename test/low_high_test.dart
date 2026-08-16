// ─────────────────────────────────────────────────────────────────────────────
// low_high_test.dart — Bola Baja / Bola Alta (2 vs 2)
//
// Cubre los casos obligatorios del spec:
//   1-2   Reparto de puntos por hoyo (barrida y 1-1)
//   3     Las tres políticas de empate
//   4-5   Carryover: se otorga acumulado, y las dos bolas corren por separado
//   6     Segmento empatado no paga nada
//   7     El Overall se calcula aparte, no como suma de Front y Back
//   8-10  Cada modalidad de liquidación por separado y las dos juntas
//   11-13 Los tres alcances de la apuesta por punto
//   14    Handicap neto aplicado por hoyo ANTES de comparar bolas
//   15    Hoyos incompletos no se liquidan
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';

// ══════════════════════════════════════════════════════════════════════════════
// FIXTURES
// ══════════════════════════════════════════════════════════════════════════════

const a1 = 'a1', a2 = 'a2', b1 = 'b1', b2 = 'b2';

CourseInfo _course() => CourseInfo(
      name: 'Test',
      holes: List.generate(
          18, (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)),
    );

Round _round({
  required Map<String, Map<int, int>> gross,
  Map<String, double> hcps = const {a1: 0, a2: 0, b1: 0, b2: 0},
  int totalHoles = 18,
}) {
  final c = _course();
  final scores = <String, Map<int, HoleScore>>{};
  for (final e in gross.entries) {
    scores[e.key] = {
      for (final h in e.value.entries)
        h.key: HoleScore(playerId: e.key, hole: h.key, grossScore: h.value),
    };
  }
  return Round(
    id: 'r', name: 'R', course: c,
    players: hcps.keys
        .map((id) => Player(id: id, name: id, handicapBase: hcps[id]!))
        .toList(),
    roundPlayers: hcps.keys
        .map((id) => RoundPlayer(playerId: id, handicapEnRonda: hcps[id]!))
        .toList(),
    betGroups: const [], scores: scores,
    events: const {}, oyeseRankings: const {}, sliding: const [],
    createdAt: DateTime(2024, 1, 1),
    totalHoles: totalHoles,
  );
}

BetModuleInstance _mod(NassauLowHighConfig cfg) => BetModuleInstance(
      id: 'lh',
      type: BetModuleType.nassauLowHigh,
      name: 'Bola Baja/Alta',
      participantIds: const [a1, a2, b1, b2],
      sides: const [
        BetSide(id: 'A', name: 'Equipo A', playerIds: [a1, a2]),
        BetSide(id: 'B', name: 'Equipo B', playerIds: [b1, b2]),
      ],
      nassauLowHighConfig: cfg,
    );

BetGroup _group() => BetGroup(
      id: 'g', name: 'G',
      format: PartidaFormat.allInOnePot,
      playerIds: const [a1, a2, b1, b2],
      modules: const [],
    );

List<LedgerEntry> _run(Round r, NassauLowHighConfig cfg) =>
    BetEngine.computeModule(r, _group(), _mod(cfg));

/// Saldo neto del equipo A: lo que recibe menos lo que paga.
double _netA(List<LedgerEntry> es) {
  var net = 0.0;
  for (final e in es) {
    if (e.toPlayerId == a1 || e.toPlayerId == a2) net += e.amount;
    if (e.fromPlayerId == a1 || e.fromPlayerId == a2) net -= e.amount;
  }
  return net;
}

/// Score plano para los 18 hoyos.
Map<int, int> _flat(int v) => {for (var h = 1; h <= 18; h++) h: v};

/// Score plano con hoyos concretos sobrescritos.
Map<int, int> _with(int base, Map<int, int> overrides) =>
    {..._flat(base), ...overrides};

void main() {
  // Config base: solo apuesta fija por segmento, para aislar el conteo.
  const soloSegmento = NassauLowHighConfig(
    mode: GrossNetMode.gross,
    tieRule: LowHighTieRule.noPoint,
    segmentBetEnabled: true,
    pointBetEnabled: false,
    segmentAmount: 100,
  );

  // ════════════════════════════════════════════════════════════════════════
  group('1-2 · reparto de puntos por hoyo', () {
    test('A gana las dos bolas del hoyo: suma 2 puntos', () {
      // A: 3 y 4 · B: 5 y 6 → baja 3<5 (A), alta 4<6 (A)
      final r = _round(gross: {
        a1: _with(4, {1: 3}), a2: _flat(4),
        b1: _with(4, {1: 5}), b2: _with(4, {1: 6}),
      });
      // Solo el hoyo 1 decide; el resto empata a 4 y con noPoint no suma.
      final es = _run(r, soloSegmento);
      // Front, Back y Overall: solo Front y Overall tienen el hoyo 1.
      // Back queda 0-0 → no paga.
      expect(_netA(es), 200); // Front 100 + Overall 100
    });

    test('A gana la baja y B la alta: 1-1, segmento empatado', () {
      // A: 3 y 7 · B: 4 y 6 → baja 3<4 (A), alta 7>6 (B)
      final r = _round(gross: {
        a1: _with(4, {1: 3}), a2: _with(4, {1: 7}),
        b1: _flat(4), b2: _with(4, {1: 6}),
      });
      final es = _run(r, soloSegmento);
      expect(_netA(es), 0); // 1-1 en todos los segmentos
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  group('3 · políticas de empate', () {
    // Hoyo 1: baja empatada (3 vs 3), alta la gana A (4 vs 6).
    Round r() => _round(gross: {
          a1: _with(4, {1: 3}), a2: _flat(4),
          b1: _with(4, {1: 3}), b2: _with(4, {1: 6}),
        });

    test('noPoint: nadie suma por la baja, A gana por la alta', () {
      final es = _run(r(), soloSegmento);
      expect(_netA(es), 200); // Front + Overall
    });

    test('split: medio punto cada uno, no mueve la diferencia', () {
      final es = _run(
          r(), soloSegmento.copyWith(tieRule: LowHighTieRule.split));
      // A: 0.5 baja + 1 alta = 1.5 · B: 0.5 → diff 1 → A gana igual.
      expect(_netA(es), 200);
    });

    test('carryover: la baja empatada no da punto ese hoyo', () {
      final es = _run(
          r(), soloSegmento.copyWith(tieRule: LowHighTieRule.carryover));
      // El acumulado queda pendiente y nunca se resuelve (resto empatado),
      // así que solo cuenta la alta.
      expect(_netA(es), 200);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  group('4-5 · carryover', () {
    // Para aislar la bola baja, las altas se mantienen SIEMPRE empatadas en 5
    // (a2 y b2 juegan 5 todo el tiempo). Un fixture con a2 y b2 en 4 haría que
    // la alta empatara y también acumulara, y A se llevaría las dos bolas.
    const soloCarryBaja = NassauLowHighConfig(
      mode: GrossNetMode.gross,
      tieRule: LowHighTieRule.carryover,
      carryAppliesTo: LowHighCarryTarget.lowBall,
      segmentBetEnabled: false,
      pointBetEnabled: true,
      amountPerPoint: 10,
      pointScope: PointBetScope.perSegment,
      segmentAmount: 100,
    );

    test('empate y luego victoria: se cobra el acumulado', () {
      // Hoyo 1: baja empatada (4-4) → acumula, vale 2.
      // Hoyo 2: A gana la baja (3 vs 4) → se lleva los 2 puntos.
      final r = _round(gross: {
        a1: _with(4, {2: 3}), a2: _flat(5),
        b1: _flat(4), b2: _flat(5),
      });
      final es = _run(r, soloCarryBaja.copyWith(segmentBetEnabled: true));
      // Front: A +2 → fijo 100 + 2×10 = 120.
      // Overall: mismo resultado → fijo 100 (perSegment excluye sus puntos).
      expect(_netA(es), 220);
    });

    test('el acumulado de la baja no afecta a la alta', () {
      // Baja: empate en el 1 → acumula; A gana en el 2 con valor 2.
      // Alta: B la gana en el 1 (6 vs 5) y empata el resto.
      final r = _round(gross: {
        a1: _with(4, {2: 3}), a2: _with(5, {1: 6}),
        b1: _flat(4), b2: _flat(5),
      });
      final es = _run(r, soloCarryBaja);
      // Front: A 2 (baja) vs B 1 (alta) → diferencia 1 → A cobra 10.
      expect(_netA(es), 10);
    });

    test('el acumulado expira al cerrar el segmento', () {
      // Solo se juegan los hoyos 9 y 10 para que el acumulado no arrastre
      // empates de los hoyos anteriores y el número quede legible.
      // Hoyo 9 (último del Front): baja empatada → acumula y expira ahí.
      // Hoyo 10: A gana la baja; en el Back debe valer 1, no 2.
      final r = _round(gross: {
        a1: {9: 4, 10: 3}, a2: {9: 5, 10: 5},
        b1: {9: 4, 10: 4}, b2: {9: 5, 10: 5},
      });
      final es = _run(r, soloCarryBaja);
      // Front: solo el hoyo 9, empatado → nada. Back: A +1 → 10.
      expect(_netA(es), 10);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  group('6-7 · segmentos', () {
    test('segmento empatado no paga ni fijo ni por puntos', () {
      final r = _round(gross: {
        a1: _flat(4), a2: _flat(4), b1: _flat(4), b2: _flat(4),
      });
      final es = _run(
          r,
          soloSegmento.copyWith(
              pointBetEnabled: true, amountPerPoint: 10));
      expect(es, isEmpty);
    });

    test('el Overall se calcula aparte, no como suma de Front y Back', () {
      // Es la prueba de que no basta con sumar los dos segmentos.
      // Solo se juegan los hoyos 9 y 10; la alta siempre empatada en 5.
      //   Hoyo 9  → baja empatada
      //   Hoyo 10 → A gana la baja
      // Front: el empate del 9 acumula y expira al cerrar → 0 puntos.
      // Back:  el 10 arranca con acumulado limpio → A +1.
      // Overall: recorre los dos, así que el acumulado del 9 sigue vivo y el
      // hoyo 10 paga 2. Sumar Front + Back daría 1, no 2.
      final r = _round(gross: {
        a1: {9: 4, 10: 3}, a2: {9: 5, 10: 5},
        b1: {9: 4, 10: 4}, b2: {9: 5, 10: 5},
      });
      final es = _run(
          r,
          soloSegmento.copyWith(
              tieRule: LowHighTieRule.carryover,
              carryAppliesTo: LowHighCarryTarget.lowBall,
              segmentBetEnabled: false,
              pointBetEnabled: true,
              amountPerPoint: 10,
              pointScope: PointBetScope.all));
      // Back 1×10 + Overall 2×10 = 30.
      expect(_netA(es), 30);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  group('8-10 · modalidades de liquidación', () {
    // A gana la baja del hoyo 1; todo lo demás empatado.
    Round r() => _round(gross: {
          a1: _with(4, {1: 3}), a2: _flat(4),
          b1: _flat(4), b2: _flat(4),
        });

    test('solo apuesta por segmento', () {
      final es = _run(r(), soloSegmento);
      expect(_netA(es), 200); // Front + Overall
    });

    test('solo apuesta por punto', () {
      final es = _run(
          r(),
          soloSegmento.copyWith(
              segmentBetEnabled: false,
              pointBetEnabled: true,
              amountPerPoint: 20,
              pointScope: PointBetScope.all));
      expect(_netA(es), 40); // Front 20 + Overall 20
    });

    test('las dos se suman, no se excluyen', () {
      final es = _run(
          r(),
          soloSegmento.copyWith(
              pointBetEnabled: true,
              amountPerPoint: 20,
              pointScope: PointBetScope.all));
      expect(_netA(es), 240); // (100+20) × 2 segmentos
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  group('11-13 · alcance de la apuesta por punto', () {
    // A gana una bola en el Front y otra en el Back.
    Round r() => _round(gross: {
          a1: _with(4, {1: 3, 10: 3}), a2: _flat(4),
          b1: _flat(4), b2: _flat(4),
        });

    const base = NassauLowHighConfig(
      mode: GrossNetMode.gross,
      segmentBetEnabled: false,
      pointBetEnabled: true,
      amountPerPoint: 10,
    );

    test('perSegment: no cobra en Overall', () {
      final es = _run(r(), base.copyWith(pointScope: PointBetScope.perSegment));
      expect(_netA(es), 20); // Front 10 + Back 10
    });

    test('overallOnly: no cobra en Front ni Back', () {
      final es = _run(r(), base.copyWith(pointScope: PointBetScope.overallOnly));
      expect(_netA(es), 20); // Overall: A +2 → 20
    });

    test('all: cobra en los tres', () {
      final es = _run(r(), base.copyWith(pointScope: PointBetScope.all));
      expect(_netA(es), 40); // 10 + 10 + 20
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  group('14-15 · handicap y datos incompletos', () {
    test('el neto se aplica por hoyo ANTES de comparar bolas', () {
      // Bruto: A 5/5 · B 4/4 → B gana las dos en bruto.
      // Con HCP 18 para el equipo A, cada jugador de A recibe 1 stroke por
      // hoyo → neto 4/4 vs 4/4 → todo empatado y nadie cobra.
      final gross = {
        a1: _flat(5), a2: _flat(5), b1: _flat(4), b2: _flat(4),
      };
      final rBruto = _round(gross: gross);
      final esBruto = _run(rBruto, soloSegmento);
      expect(_netA(esBruto), -300, reason: 'en bruto B gana los 3 segmentos');

      final rNeto = _round(
          gross: gross, hcps: const {a1: 18, a2: 18, b1: 0, b2: 0});
      final esNeto = _run(rNeto, soloSegmento.copyWith(mode: GrossNetMode.net));
      expect(_netA(esNeto), 0, reason: 'en neto todo empata');
    });

    test('un hoyo sin los cuatro scores no se disputa', () {
      // A ganaría la baja del hoyo 1, pero b2 no anotó: sin bola alta de B no
      // hay hoyo. El resto de la ronda está completa y empatada.
      final r = _round(gross: {
        a1: _with(4, {1: 3}), a2: _flat(4),
        b1: _flat(4),
        b2: {for (var h = 2; h <= 18; h++) h: 4}, // sin hoyo 1
      });
      expect(_run(r, soloSegmento), isEmpty);
    });

    test('el acumulado sobrevive a un hoyo incompleto', () {
      // Hoyo 1: baja empatada → acumula, vale 2.
      // Hoyo 2: b2 no anotó → el hoyo no se disputa y el acumulado NO se toca.
      // Hoyo 3: A gana la baja → cobra los 2 puntos pendientes.
      final r = _round(gross: {
        a1: {1: 4, 2: 4, 3: 3}, a2: {1: 5, 2: 5, 3: 5},
        b1: {1: 4, 2: 4, 3: 4}, b2: {1: 5, 3: 5}, // sin hoyo 2
      });
      final es = _run(
          r,
          soloSegmento.copyWith(
              tieRule: LowHighTieRule.carryover,
              carryAppliesTo: LowHighCarryTarget.lowBall,
              segmentBetEnabled: false,
              pointBetEnabled: true,
              amountPerPoint: 10,
              pointScope: PointBetScope.perSegment));
      expect(_netA(es), 20); // 2 puntos × 10 en el Front
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  group('validaciones', () {
    test('exige exactamente 2 jugadores por lado', () {
      final r = _round(gross: {
        a1: _flat(4), a2: _flat(4), b1: _flat(4), b2: _flat(4),
      });
      final mod = BetModuleInstance(
        id: 'lh', type: BetModuleType.nassauLowHigh, name: 'LH',
        participantIds: const [a1, a2, b1],
        sides: const [
          BetSide(id: 'A', name: 'A', playerIds: [a1, a2]),
          BetSide(id: 'B', name: 'B', playerIds: [b1]), // solo uno
        ],
        nassauLowHighConfig: soloSegmento,
      );
      expect(() => BetEngine.computeModule(r, _group(), mod), throwsStateError);
    });

    test('sin lados configurados avisa en vez de callar', () {
      // Regresión: el formato aparecía configurado pero nadie cobraba, porque
      // el editor no ofrecía la sección de equipos para este tipo y el módulo
      // llegaba sin lados. Ahora falla visible.
      final r = _round(gross: {
        a1: _with(4, {1: 3}), a2: _flat(4), b1: _flat(4), b2: _flat(4),
      });
      final sinLados = BetModuleInstance(
        id: 'lh', type: BetModuleType.nassauLowHigh, name: 'LH',
        participantIds: const [a1, a2, b1, b2],
        nassauLowHighConfig: soloSegmento,
      );
      expect(() => BetEngine.computeModule(r, _group(), sinLados),
          throwsStateError);
    });

    test('sin ninguna modalidad activa no liquida nada', () {
      final r = _round(gross: {
        a1: _with(4, {1: 3}), a2: _flat(4), b1: _flat(4), b2: _flat(4),
      });
      final es = _run(
          r,
          soloSegmento.copyWith(
              segmentBetEnabled: false, pointBetEnabled: false));
      expect(es, isEmpty);
    });

    test('segmento desactivado no se cobra', () {
      final r = _round(gross: {
        a1: _with(4, {1: 3}), a2: _flat(4), b1: _flat(4), b2: _flat(4),
      });
      final es = _run(r, soloSegmento.copyWith(overallEnabled: false));
      expect(_netA(es), 100); // solo Front
    });

    test('el importe se reparte entre los cruces de ambos lados', () {
      // 2v2 → 4 cruces. El segmento vale 100 en total, no 100 por cruce.
      final r = _round(gross: {
        a1: _with(4, {1: 3}), a2: _flat(4), b1: _flat(4), b2: _flat(4),
      });
      final es = _run(r, soloSegmento.copyWith(overallEnabled: false));
      expect(es.length, 4);
      expect(es.first.amount, 25);
      expect(_netA(es), 100);
    });
  });
}
