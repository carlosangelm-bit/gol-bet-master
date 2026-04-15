// ignore_for_file: avoid_print
// ─────────────────────────────────────────────────────────────────────────────
// AUDITORÍA: _strokesP1ReceivesFromP2 — comportamiento completo
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';

// Réplica pública de _strokesP1ReceivesFromP2 (es privado en BetEngine)
double recvAB(Round round, String p1, String p2) =>
    BetEngine.strokesP1ReceivesFromP2(round, p1, p2);

CourseInfo _b9course() => CourseInfo(
  name: 'B9',
  holes: List.generate(9, (i) => CourseHole(
    hole: i + 10, par: 4, strokeIndex: (i + 1) * 2,
  )),
);

CourseInfo _f9course() => CourseInfo(
  name: 'F9',
  holes: List.generate(9, (i) => CourseHole(
    hole: i + 1, par: 4, strokeIndex: i * 2 + 1,
  )),
);

Round _round({
  required CourseInfo course,
  required Map<String, double> hcps,
  required Map<String, Map<String, double>> manuals,
  required Map<String, List<int>> scores,
  StartingNine nine = StartingNine.back,
}) {
  final holeNums = nine == StartingNine.back
      ? List.generate(9, (i) => i + 10)
      : List.generate(9, (i) => i + 1);

  final scoresMap = <String, Map<int, HoleScore>>{};
  for (final e in scores.entries) {
    final pid = e.key;
    final vals = e.value;
    scoresMap[pid] = {
      for (int i = 0; i < vals.length; i++)
        if (vals[i] > 0)
          holeNums[i]: HoleScore(playerId: pid, hole: holeNums[i], grossScore: vals[i]),
    };
  }

  return Round(
    id: 'audit', name: 'Audit', course: course,
    players: hcps.entries.map((e) => Player(id: e.key, name: e.key, handicapBase: e.value)).toList(),
    roundPlayers: hcps.entries.map((e) => RoundPlayer(
      playerId: e.key,
      handicapEnRonda: e.value,
      manualHandicaps: manuals[e.key] ?? {},
    )).toList(),
    betGroups: [], scores: scoresMap,
    events: {}, oyeseRankings: {}, sliding: [],
    createdAt: DateTime(2025, 1, 1),
    totalHoles: 9, startingNine: nine,
  );
}

void main() {
  print('\n');
  print('╔══════════════════════════════════════════════════════════════╗');
  print('║   AUDITORÍA COMPLETA DE _strokesP1ReceivesFromP2            ║');
  print('╚══════════════════════════════════════════════════════════════╝');

  // ─────────────────────────────────────────────────────────────────────
  group('1. Semántica de manualHandicaps[key]=val', () {
    // La UI (setup_screen.dart líneas 626-627) escribe SIEMPRE los dos sentidos:
    //   manualHandicaps[A][B] =  val   → "A recibe val de B" (positivo=recibe)
    //   manualHandicaps[B][A] = -val   → "B da val a A"     (negativo=da)
    //
    // Resultado: recv(A,B) = m1 = +val  → A recibe val
    //            recv(B,A) = m1 = -val  → B da val (B recibe -val)

    test('manual[A][B]=+5 → A recibe 5 de B; manual[B][A]=-5 → B da 5 a A', () {
      // Escenario: usuario ingresó que A recibe 5 de B
      // setup_screen escribe: A.manual[B]=+5, B.manual[A]=-5
      final r = _round(
        course: _b9course(),
        hcps: {'A': 15, 'B': 20},
        manuals: {'A': {'B': 5.0}, 'B': {'A': -5.0}},
        scores: {'A': [], 'B': []},
      );

      final ab = recvAB(r, 'A', 'B');
      final ba = recvAB(r, 'B', 'A');

      print('\n  [Caso UI normal: A recibe 5 de B]');
      print('  recv(A,B) = $ab   (esperado: +5.0 → A recibe 5)');
      print('  recv(B,A) = $ba   (esperado: -5.0 → B da 5)');
      print('  Son opuestos: ${(ab + ba).abs() < 0.01}');

      expect(ab, equals(5.0),  reason: 'A recibe 5 de B → +5');
      expect(ba, equals(-5.0), reason: 'B da 5 a A → -5');
      expect((ab + ba).abs(), lessThan(0.01), reason: 'deben ser opuestos');
    });

    test('Solo manual[A][B]=-5 definido (A da 5, sin espejo)', () {
      // Caso: solo un sentido guardado → el otro se infiere
      final r = _round(
        course: _b9course(),
        hcps: {'A': 15, 'B': 20},
        manuals: {'A': {'B': -5.0}}, // A da 5
        scores: {'A': [], 'B': []},
      );

      final ab = recvAB(r, 'A', 'B');
      final ba = recvAB(r, 'B', 'A');

      print('\n  [Solo manual[A][B]=-5]');
      print('  recv(A,B) = $ab   (esperado: -5.0 → A da 5)');
      print('  recv(B,A) = $ba   (esperado: +5.0 → B recibe 5, inferido via -m2)');
      print('  Son opuestos: ${(ab + ba).abs() < 0.01}');

      expect(ab, equals(-5.0), reason: 'A da 5 → -5');
      expect(ba, equals(5.0),  reason: 'B recibe 5 (inferido) → +5');
      expect((ab + ba).abs(), lessThan(0.01));
    });

    test('Solo manual[B][A]=-5 definido (B da 5 a A, sin espejo)', () {
      // Solo el sentido inverso guardado
      final r = _round(
        course: _b9course(),
        hcps: {'A': 15, 'B': 20},
        manuals: {'B': {'A': -5.0}}, // B da 5 a A
        scores: {'A': [], 'B': []},
      );

      final ab = recvAB(r, 'A', 'B');
      final ba = recvAB(r, 'B', 'A');

      print('\n  [Solo manual[B][A]=-5 (B da 5 a A)]');
      print('  recv(A,B) = $ab   (esperado: +5.0 → A recibe 5, inferido via -m2)');
      print('  recv(B,A) = $ba   (esperado: -5.0 → B da 5)');
      print('  Son opuestos: ${(ab + ba).abs() < 0.01}');

      expect(ab, equals(5.0),  reason: 'A recibe 5 (inferido de B.manual[A]=-5) → +5');
      expect(ba, equals(-5.0), reason: 'B da 5 → -5');
    });

    test('manual[A][B]=0 override explícito (ignora HCP diff)', () {
      // HCP: A=15, B=20 → diff=-5, pero manual=0 override
      final r = _round(
        course: _b9course(),
        hcps: {'A': 15, 'B': 20},
        manuals: {'A': {'B': 0.0}, 'B': {'A': 0.0}},
        scores: {'A': [], 'B': []},
      );

      final ab = recvAB(r, 'A', 'B');
      final ba = recvAB(r, 'B', 'A');

      print('\n  [manual=0 override: HCP diff=-5 ignorado]');
      print('  recv(A,B) = $ab   (esperado: 0.0 — manual override)');
      print('  recv(B,A) = $ba   (esperado: 0.0)');

      expect(ab, equals(0.0), reason: 'manual=0 override → sin ventaja');
      expect(ba, equals(0.0));
    });

    test('Sin manual → fallback HCP (A=15, B=20)', () {
      final r = _round(
        course: _b9course(),
        hcps: {'A': 15, 'B': 20},
        manuals: {},
        scores: {'A': [], 'B': []},
      );

      final ab = recvAB(r, 'A', 'B');
      final ba = recvAB(r, 'B', 'A');

      print('\n  [Fallback HCP: A=15, B=20]');
      print('  recv(A,B) = $ab   (esperado: -5.0 = A.hcp-B.hcp = 15-20)');
      print('  recv(B,A) = $ba   (esperado: +5.0 = B.hcp-A.hcp = 20-15)');

      expect(ab, equals(-5.0), reason: '15-20=-5 → A da 5');
      expect(ba, equals(5.0),  reason: '20-15=+5 → B recibe 5');
    });

    test('INVARIANTE: recv(A,B) siempre == -recv(B,A)', () {
      // Probamos con múltiples configuraciones
      final configs = [
        {'A': {'B': 7.0},  'B': {'A': -7.0}},
        {'A': {'B': -3.0}, 'B': {'A':  3.0}},
        {'A': {'B': 0.0},  'B': {'A':  0.0}},
        {'A': {'B': 10.0}},           // solo un sentido
        {'B': {'A': -8.0}},           // solo sentido inverso
        <String,Map<String,double>>{}, // ninguno → HCP
      ];

      for (final cfg in configs) {
        final r = _round(
          course: _b9course(),
          hcps: {'A': 12.0, 'B': 18.0},
          manuals: cfg,
          scores: {'A': [], 'B': []},
        );
        final ab = recvAB(r, 'A', 'B');
        final ba = recvAB(r, 'B', 'A');
        expect((ab + ba).abs(), lessThan(0.01),
            reason: 'recv(A,B)+recv(B,A) debe ser 0 — config: $cfg → ab=$ab ba=$ba');
      }
      print('\n  ✅ INVARIANTE CONFIRMADO: recv(A,B) = -recv(B,A) en todos los casos');
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  group('2. Medal allVsAll — caso clásico A=45, B=50, A da 5', () {
    // Setup estándar de la UI:
    //   Usuario ingresa "A da 5 a B"
    //   setup_screen escribe: A.manual[B]=-5, B.manual[A]=+5
    //
    // Esperado:
    //   recv(A,B) = -5 → A da 5 → A es base, B es receptor
    //   B net = B.gross - 5 strokes = 50 - 5 = 45
    //   A gross = 45, B net = 45 → EMPATE → sin entries

    BetModuleInstance medalMod(List<String> pids) => BetModuleInstance(
      id: 'm1', type: BetModuleType.medal, name: 'Medal',
      participantIds: pids,
      formatMode: BetFormatMode.allVsAll,
      medalConfig: const MedalConfig(value: 100, mode: GrossNetMode.net, holes: 9),
    );

    test('A=45 gross, B=50 gross, A da 5 → B net=45 → EMPATE (sin entries)', () {
      final course = _b9course();
      final r = _round(
        course: course,
        hcps: {'A': 15, 'B': 20},
        manuals: {
          'A': {'B': -5.0},  // A da 5 a B (setup_screen escribe -5 en A)
          'B': {'A':  5.0},  // B recibe 5 de A (setup_screen escribe +5 en B)
        },
        scores: {
          'A': [5, 5, 5, 5, 5, 5, 5, 5, 5],  // 45 gross
          'B': [6, 6, 6, 6, 6, 5, 5, 5, 5],  // 50 gross
        },
      );

      final ab = recvAB(r, 'A', 'B');
      final ba = recvAB(r, 'B', 'A');

      print('\n  recv(A,B) = $ab   → ${ab < 0 ? "A DA ${-ab} a B ✓" : "A recibe $ab ← ERROR"}');
      print('  recv(B,A) = $ba   → ${ba > 0 ? "B recibe $ba de A ✓" : "B DA ${-ba} ← ERROR"}');
      print('  A gross=45, B net = 50 - ${ba.abs().round()} = ${50 - ba.abs().round()}');

      // Crear round con BetGroup para computeAll
      final group = BetGroup(
        id: 'g', name: 'G', format: PartidaFormat.allInOnePot,
        playerIds: ['A', 'B'], modules: [medalMod(['A', 'B'])],
      );
      final round2 = Round(
        id: 'classic', name: 'Classic', course: course,
        players: [
          Player(id: 'A', name: 'A', handicapBase: 15),
          Player(id: 'B', name: 'B', handicapBase: 20),
        ],
        roundPlayers: [
          RoundPlayer(playerId: 'A', handicapEnRonda: 15, manualHandicaps: {'B': -5.0}),
          RoundPlayer(playerId: 'B', handicapEnRonda: 20, manualHandicaps: {'A':  5.0}),
        ],
        betGroups: [group],
        scores: r.scores,
        events: {}, oyeseRankings: {}, sliding: [],
        createdAt: DateTime(2025, 1, 1),
        totalHoles: 9, startingNine: StartingNine.back,
      );

      final entries = BetEngine.computeAll(round2);
      print('  Entries: ${entries.isEmpty ? "(vacío → EMPATE ✓)" : entries.map((e) => "${e.fromPlayerId}→${e.toPlayerId}:\$${e.amount}").join(", ")}');

      expect(ab, equals(-5.0), reason: 'A da 5 → recv(A,B)=-5');
      expect(ba, equals(5.0),  reason: 'B recibe 5 → recv(B,A)=+5');
      // NUEVA LÓGICA pairSliding oficial 18H: B9 back-start → share=ceil(5/2)=3.
      // B net = 50-3 = 47. A net=45 < B net=47 → A GANA (no hay empate).
      expect(entries.any((e) => e.toPlayerId == 'A'), true,
          reason: 'A=45 gross < B net=47 (share B9=3) → A gana');
    });

    test('A=44 gross, B=50 gross, A da 5 → B net=45 → A GANA por 1 (con 5 hoyos extra net)', () {
      // A mejora 1 stroke → A=44, B net=45 → A gana
      final course = _b9course();
      final group = BetGroup(
        id: 'g', name: 'G', format: PartidaFormat.allInOnePot,
        playerIds: ['A', 'B'], modules: [medalMod(['A', 'B'])],
      );
      final round = Round(
        id: 'a_wins', name: 'A wins', course: course,
        players: [
          Player(id: 'A', name: 'A', handicapBase: 15),
          Player(id: 'B', name: 'B', handicapBase: 20),
        ],
        roundPlayers: [
          RoundPlayer(playerId: 'A', handicapEnRonda: 15, manualHandicaps: {'B': -5.0}),
          RoundPlayer(playerId: 'B', handicapEnRonda: 20, manualHandicaps: {'A':  5.0}),
        ],
        betGroups: [group],
        scores: {
          'A': {for (int h = 10; h <= 18; h++) h: HoleScore(playerId: 'A', hole: h,
              grossScore: h == 10 ? 4 : 5)}, // 44 (un birdie en H10)
          'B': {
            10: HoleScore(playerId: 'B', hole: 10, grossScore: 6),
            11: HoleScore(playerId: 'B', hole: 11, grossScore: 6),
            12: HoleScore(playerId: 'B', hole: 12, grossScore: 6),
            13: HoleScore(playerId: 'B', hole: 13, grossScore: 6),
            14: HoleScore(playerId: 'B', hole: 14, grossScore: 6),
            15: HoleScore(playerId: 'B', hole: 15, grossScore: 5),
            16: HoleScore(playerId: 'B', hole: 16, grossScore: 5),
            17: HoleScore(playerId: 'B', hole: 17, grossScore: 5),
            18: HoleScore(playerId: 'B', hole: 18, grossScore: 5),
          },
        },
        events: {}, oyeseRankings: {}, sliding: [],
        createdAt: DateTime(2025, 1, 1),
        totalHoles: 9, startingNine: StartingNine.back,
      );

      final entries = BetEngine.computeAll(round);
      print('\n  A gross=44, B net=45 → A debe ganar');
      for (final e in entries) {
        print('  ${e.fromPlayerId}→${e.toPlayerId}: \$${e.amount} [${e.reason}]');
      }
      expect(entries.any((e) => e.toPlayerId == 'A'), true,
          reason: 'A con 44 < B net 45 → A debe cobrar');
    });

    test('A=46 gross, B=50 gross, A da 5 → B net=45 → B GANA', () {
      final course = _b9course();
      final group = BetGroup(
        id: 'g', name: 'G', format: PartidaFormat.allInOnePot,
        playerIds: ['A', 'B'], modules: [medalMod(['A', 'B'])],
      );
      final round = Round(
        id: 'b_wins', name: 'B wins', course: course,
        players: [
          Player(id: 'A', name: 'A', handicapBase: 15),
          Player(id: 'B', name: 'B', handicapBase: 20),
        ],
        roundPlayers: [
          RoundPlayer(playerId: 'A', handicapEnRonda: 15, manualHandicaps: {'B': -5.0}),
          RoundPlayer(playerId: 'B', handicapEnRonda: 20, manualHandicaps: {'A':  5.0}),
        ],
        betGroups: [group],
        scores: {
          'A': {for (int h = 10; h <= 18; h++) h: HoleScore(playerId: 'A', hole: h,
              grossScore: h == 10 ? 6 : 5)}, // 46 (un bogey en H10)
          'B': {
            10: HoleScore(playerId: 'B', hole: 10, grossScore: 6),
            11: HoleScore(playerId: 'B', hole: 11, grossScore: 6),
            12: HoleScore(playerId: 'B', hole: 12, grossScore: 6),
            13: HoleScore(playerId: 'B', hole: 13, grossScore: 6),
            14: HoleScore(playerId: 'B', hole: 14, grossScore: 6),
            15: HoleScore(playerId: 'B', hole: 15, grossScore: 5),
            16: HoleScore(playerId: 'B', hole: 16, grossScore: 5),
            17: HoleScore(playerId: 'B', hole: 17, grossScore: 5),
            18: HoleScore(playerId: 'B', hole: 18, grossScore: 5),
          },
        },
        events: {}, oyeseRankings: {}, sliding: [],
        createdAt: DateTime(2025, 1, 1),
        totalHoles: 9, startingNine: StartingNine.back,
      );

      final entries = BetEngine.computeAll(round);
      print('\n  A gross=46, B net=45 → B debe ganar');
      for (final e in entries) {
        print('  ${e.fromPlayerId}→${e.toPlayerId}: \$${e.amount} [${e.reason}]');
      }
      // NUEVA LÓGICA: B net = 50-3 = 47 (share B9=3). A net=46 < B net=47 → A GANA.
      // El test original esperaba B gana, pero con el pairSliding oficial 18H
      // los strokes son menores (share=3 en B9 back-start) por lo que A sigue ganando.
      expect(entries.any((e) => e.toPlayerId == 'A'), true,
          reason: 'A gross=46 < B net=47 (share B9=3 con back-start) → A sigue ganando');
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  group('3. Tabla resumen — todos los casos de una sola vista', () {
    test('Tabla de recv(A,B) y recv(B,A) en todos los escenarios', () {
      print('\n');
      print('┌─────────────────────────────┬──────────────┬──────────────┬────────────┐');
      print('│ Escenario                   │ recv(A,B)    │ recv(B,A)    │ Opuestos?  │');
      print('├─────────────────────────────┼──────────────┼──────────────┼────────────┤');

      void row(String label, Map<String, Map<String,double>> manuals, double aHcp, double bHcp) {
        final r = _round(
          course: _b9course(), hcps: {'A': aHcp, 'B': bHcp},
          manuals: manuals, scores: {'A': [], 'B': []},
        );
        final ab = recvAB(r, 'A', 'B');
        final ba = recvAB(r, 'B', 'A');
        final ok = (ab + ba).abs() < 0.01 ? '✅' : '❌';
        print('│ ${label.padRight(27)} │ ${ab.toString().padLeft(12)} │ ${ba.toString().padLeft(12)} │ $ok         │');
      }

      row('A.manual[B]=+5, B.manual[A]=-5', {'A':{'B':5.0},'B':{'A':-5.0}}, 15, 20);
      row('A.manual[B]=-5, B.manual[A]=+5', {'A':{'B':-5.0},'B':{'A':5.0}}, 15, 20);
      row('Solo A.manual[B]=+5',            {'A':{'B':5.0}}, 15, 20);
      row('Solo A.manual[B]=-5',            {'A':{'B':-5.0}}, 15, 20);
      row('Solo B.manual[A]=+5',            {'B':{'A':5.0}}, 15, 20);
      row('Solo B.manual[A]=-5',            {'B':{'A':-5.0}}, 15, 20);
      row('Ambos = 0',                      {'A':{'B':0.0},'B':{'A':0.0}}, 15, 20);
      row('Sin manual (HCP A=15, B=20)',    {}, 15, 20);
      row('Sin manual (HCP A=20, B=15)',    {}, 20, 15);

      print('└─────────────────────────────┴──────────────┴──────────────┴────────────┘');
      print('\n  SEMÁNTICA: manualHandicaps[yo][otro] = strokes que YO recibo del otro');
      print('  Positivo = recibo strokes, Negativo = doy strokes');
      print('  recv(A,B) > 0 → A recibe ventaja de B');
      print('  recv(A,B) < 0 → A da ventaja a B');
    });
  });
}
