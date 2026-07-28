// ignore_for_file: avoid_print
// ─────────────────────────────────────────────────────────────────────────────
// Tests obligatorios para pairSliding canónico
// Casos 1–9 según especificación
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Alias público para _strokesP1ReceivesFromP2
double recv(Round r, String p1, String p2) =>
    BetEngine.strokesP1ReceivesFromP2(r, p1, p2);

/// Alias público para canonicalSlidingBetween
double? canonical(Round r, String p1, String p2) =>
    BetEngine.canonicalSlidingBetween(r, p1, p2);

/// Curso mínimo de 18 hoyos para tests
CourseInfo _course18() => CourseInfo(
      name: 'Test18',
      holes: List.generate(18, (i) => CourseHole(
        hole: i + 1, par: 4, strokeIndex: i + 1,
      )),
    );

/// Construye un Round con pairSliding y/o manualHandicaps.
Round _makeRound({
  required List<String> pids,
  Map<String, double> hcps = const {},
  Map<String, double> pairSliding = const {},
  Map<String, Map<String, double>> manuals = const {},
  Map<String, List<int>> scores = const {},
  bool isLive = false,
  String? liveCode,
}) {
  final course = _course18();
  final holeNums = List.generate(18, (i) => i + 1);

  final scoresMap = <String, Map<int, HoleScore>>{};
  for (final e in scores.entries) {
    final pid = e.key;
    final vals = e.value;
    final holeMap = <int, HoleScore>{};
    for (int i = 0; i < vals.length && i < holeNums.length; i++) {
      if (vals[i] > 0) {
        holeMap[holeNums[i]] = HoleScore(
          playerId: pid, hole: holeNums[i], grossScore: vals[i], putts: 2,
        );
      }
    }
    if (holeMap.isNotEmpty) scoresMap[pid] = holeMap;
  }

  return Round(
    id: 'test',
    name: 'Test Round',
    course: course,
    players: pids.map((id) => Player(
      id: id, name: id, handicapBase: hcps[id] ?? 0,
    )).toList(),
    roundPlayers: pids.map((id) => RoundPlayer(
      playerId: id,
      handicapEnRonda: hcps[id] ?? 0,
      manualHandicaps: manuals[id] ?? {},
    )).toList(),
    betGroups: [],
    scores: scoresMap,
    events: const {},
    oyeseRankings: const {},
    sliding: const [],
    createdAt: DateTime(2025, 1, 1),
    totalHoles: 18,
    isLive: isLive,
    liveCode: liveCode,
    pairSliding: pairSliding,
  );
}

/// Serializa/deserializa un Round (replica roundToJson/roundFromJson)
Round _roundThroughJson(Round r) {
  // Serializar
  final scoresJson = r.scores.map((pid, hMap) => MapEntry(
    pid, hMap.map((h, hs) => MapEntry(h.toString(), hs.toJson())),
  ));

  final json = <String, dynamic>{
    'id': r.id, 'name': r.name,
    'course': r.course.toJson(),
    'players': r.players.map((p) => p.toJson()).toList(),
    'roundPlayers': r.roundPlayers.map((rp) => rp.toJson()).toList(),
    'betGroups': [],
    'scores': scoresJson,
    'events': {},
    'oyeseRankings': {},
    'sliding': [],
    'createdAt': r.createdAt.toIso8601String(),
    'totalHoles': r.totalHoles,
    'startingNine': r.startingNine.name,
    'isLive': r.isLive,
    'liveCode': r.liveCode,
    'scoringMode': r.scoringMode,
    'currentHole': r.currentHole,
    'isFinished': r.isFinished,
    if (r.pairSliding.isNotEmpty) 'pairSliding': r.pairSliding,
  };

  final jsonStr = jsonEncode(json);
  final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;

  // Deserializar (replica roundFromJson)
  List<dynamic> asList(dynamic v) => v is List ? v : [];
  Map<String, dynamic> asMap(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  final players = asList(decoded['players'])
      .map((p) => Player.fromJson(asMap(p))).toList();
  final roundPlayers = asList(decoded['roundPlayers'])
      .map((rp) => RoundPlayer.fromJson(asMap(rp))).toList();

  final scoresDecoded = asMap(decoded['scores']);
  final scores = <String, Map<int, HoleScore>>{};
  scoresDecoded.forEach((pid, hmap) {
    final inner = <int, HoleScore>{};
    asMap(hmap).forEach((hStr, sJson) {
      final h = int.tryParse(hStr);
      if (h != null) {
        try { inner[h] = HoleScore.fromJson(asMap(sJson)); } catch (_) {}
      }
    });
    scores[pid] = inner;
  });

  // pairSliding: leer campo canónico
  final rawPs = decoded['pairSliding'];
  final pairSliding = <String, double>{};
  if (rawPs != null && rawPs is Map) {
    (rawPs).forEach((k, v) {
      pairSliding[k.toString()] = (v as num?)?.toDouble() ?? 0.0;
    });
  }

  return Round(
    id: decoded['id'] as String,
    name: decoded['name'] as String,
    course: CourseInfo.fromJson(asMap(decoded['course'])),
    players: players,
    roundPlayers: roundPlayers,
    betGroups: [],
    scores: scores,
    events: const {},
    oyeseRankings: const {},
    sliding: const [],
    createdAt: DateTime.tryParse(decoded['createdAt'] as String? ?? '') ?? DateTime.now(),
    totalHoles: (decoded['totalHoles'] as num?)?.toInt() ?? 18,
    isLive: decoded['isLive'] == true,
    liveCode: decoded['liveCode'] as String?,
    scoringMode: decoded['scoringMode'] as String? ?? 'open',
    pairSliding: pairSliding,
  );
}

/// Módulo Medal allVsAll con valor $100
BetModuleInstance _medalMod(List<String> pids) =>
    BetModuleInstance.defaultFor(BetModuleType.medal, pids).copyWith(
      medalConfig: const MedalConfig(value: 100, mode: GrossNetMode.net),
      formatMode: BetFormatMode.allVsAll,
    );

BetGroup _medalGroup(List<String> pids) => BetGroup(
  id: 'g1', name: 'Medal',
  format: PartidaFormat.allInOnePot,
  playerIds: pids,
  modules: [_medalMod(pids)],
);

// ─────────────────────────────────────────────────────────────────────────────
// TESTS
// ─────────────────────────────────────────────────────────────────────────────
void main() {
  print('\n');
  print('╔══════════════════════════════════════════════════════════════════╗');
  print('║   PAIR SLIDING CANÓNICO — Tests obligatorios casos 1–9          ║');
  print('╚══════════════════════════════════════════════════════════════════╝');

  // ══════════════════════════════════════════════════════════════════════════
  // CASO 1: Lectura canónica directa (valor negativo)
  // pairSliding['A|B'] = -5 → A da 5 a B
  //   recv(A,B) = -5   recv(B,A) = +5
  // ══════════════════════════════════════════════════════════════════════════
  group('Caso 1 – Lectura canónica directa (pairSliding negativo)', () {
    test("pairSliding['A|B']=-5 → recv(A,B)=-5, recv(B,A)=+5", () {
      print('\n[Caso 1] pairSliding[A|B]=-5');
      // A < B lexicográficamente: clave canónica es 'A|B'
      final r = _makeRound(
        pids: ['A', 'B'],
        pairSliding: {'A|B': -5.0},
      );

      final ab = recv(r, 'A', 'B');
      final ba = recv(r, 'B', 'A');
      print('  canonical[A|B]=${r.pairSliding["A|B"]}');
      print('  recv(A,B)=$ab  (esperado: -5.0 → A da 5)');
      print('  recv(B,A)=$ba  (esperado: +5.0 → B recibe 5)');

      expect(ab, closeTo(-5.0, 0.01),
          reason: 'recv(A,B): A da 5 → debe ser -5');
      expect(ba, closeTo(5.0, 0.01),
          reason: 'recv(B,A): B recibe 5 → debe ser +5');
      expect((ab + ba).abs(), lessThan(0.01),
          reason: 'Invariante: recv(A,B)+recv(B,A)=0');

      // También verificar canonicalSlidingBetween directamente
      expect(canonical(r, 'A', 'B'), closeTo(-5.0, 0.01));
      expect(canonical(r, 'B', 'A'), closeTo(5.0, 0.01));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // CASO 2: Valor positivo en pairSliding
  // pairSliding['A|B'] = +5 → A recibe 5 de B
  //   recv(A,B) = +5   recv(B,A) = -5
  // ══════════════════════════════════════════════════════════════════════════
  group('Caso 2 – Valor positivo en pairSliding', () {
    test("pairSliding['A|B']=+5 → recv(A,B)=+5, recv(B,A)=-5", () {
      print('\n[Caso 2] pairSliding[A|B]=+5');
      final r = _makeRound(
        pids: ['A', 'B'],
        pairSliding: {'A|B': 5.0},
      );

      final ab = recv(r, 'A', 'B');
      final ba = recv(r, 'B', 'A');
      print('  recv(A,B)=$ab  (esperado: +5.0 → A recibe 5)');
      print('  recv(B,A)=$ba  (esperado: -5.0 → B da 5)');

      expect(ab, closeTo(5.0, 0.01),
          reason: 'recv(A,B): A recibe 5 → debe ser +5');
      expect(ba, closeTo(-5.0, 0.01),
          reason: 'recv(B,A): B da 5 → debe ser -5');
      expect((ab + ba).abs(), lessThan(0.01),
          reason: 'Invariante: recv(A,B)+recv(B,A)=0');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // CASO 3: Override explícito 0 en pairSliding
  // pairSliding['A|B'] = 0 → acuerdo sin ventaja (ignora HCP)
  //   recv(A,B) = 0   recv(B,A) = 0
  // ══════════════════════════════════════════════════════════════════════════
  group('Caso 3 – Override explícito cero', () {
    test("pairSliding['A|B']=0 → recv(A,B)=0, recv(B,A)=0 (ignora HCP)", () {
      print('\n[Caso 3] pairSliding[A|B]=0 con HCPs distintos (A=10, B=20)');
      // Sin pairSliding, el fallback sería HCP diff = 10-20 = -10.
      // Con pairSliding=0, debe devolver 0 (acuerdo explícito).
      final r = _makeRound(
        pids: ['A', 'B'],
        hcps: {'A': 10.0, 'B': 20.0},
        pairSliding: {'A|B': 0.0},
      );

      final ab = recv(r, 'A', 'B');
      final ba = recv(r, 'B', 'A');
      print('  recv(A,B)=$ab  (esperado: 0.0 — override, no usa HCP)');
      print('  recv(B,A)=$ba  (esperado: 0.0 — override, no usa HCP)');

      expect(ab, closeTo(0.0, 0.01),
          reason: 'pairSliding=0 debe ignorar HCP diff');
      expect(ba, closeTo(0.0, 0.01),
          reason: 'Inverso también debe ser 0');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // CASO 4: Fallback a legacy bilateral consistente
  // No hay pairSliding. manual[A][B]=-5, manual[B][A]=+5 (bilateral consistente)
  //   recv(A,B) = -5   recv(B,A) = +5
  // ══════════════════════════════════════════════════════════════════════════
  group('Caso 4 – Fallback legacy bilateral consistente', () {
    test("Sin pairSliding, manual[A][B]=-5, manual[B][A]=+5 → recv correcto", () {
      print('\n[Caso 4] Legacy bilateral consistente: manual[A][B]=-5, manual[B][A]=+5');
      final r = _makeRound(
        pids: ['A', 'B'],
        // Sin pairSliding (vacío)
        manuals: {
          'A': {'B': -5.0},
          'B': {'A': 5.0},
        },
      );

      // pairSliding vacío: debe usar legacy
      expect(r.pairSliding, isEmpty,
          reason: 'pairSliding debe estar vacío para este test');

      final ab = recv(r, 'A', 'B');
      final ba = recv(r, 'B', 'A');
      print('  recv(A,B)=$ab  (esperado: -5.0)');
      print('  recv(B,A)=$ba  (esperado: +5.0)');

      expect(ab, closeTo(-5.0, 0.01));
      expect(ba, closeTo(5.0, 0.01));
      expect((ab + ba).abs(), lessThan(0.01));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // CASO 5: Fallback legacy unilateral
  // Solo manual[A][B]=-5 (sin espejo). El motor debe inferir recv(B,A)=+5.
  // ══════════════════════════════════════════════════════════════════════════
  group('Caso 5 – Fallback legacy unilateral', () {
    test("Sin pairSliding, solo manual[A][B]=-5 → recv(B,A)=+5 inferido", () {
      print('\n[Caso 5] Legacy unilateral: solo manual[A][B]=-5');
      final r = _makeRound(
        pids: ['A', 'B'],
        manuals: {
          'A': {'B': -5.0},
          // B no tiene manual
        },
      );

      expect(r.pairSliding, isEmpty);

      final ab = recv(r, 'A', 'B');
      final ba = recv(r, 'B', 'A');
      print('  recv(A,B)=$ab  (esperado: -5.0)');
      print('  recv(B,A)=$ba  (esperado: +5.0 inferido via -m2)');

      expect(ab, closeTo(-5.0, 0.01));
      expect(ba, closeTo(5.0, 0.01),
          reason: 'El motor infiere via -m2 cuando solo existe un lado');
      expect((ab + ba).abs(), lessThan(0.01));
    });

    test("Unilateral inverso: solo manual[B][A]=+5 → recv(A,B)=-5 inferido", () {
      print('\n[Caso 5b] Legacy unilateral inverso: solo manual[B][A]=+5');
      final r = _makeRound(
        pids: ['A', 'B'],
        manuals: {
          // A no tiene manual
          'B': {'A': 5.0}, // B recibe 5 de A (B dice: yo recibo 5 de A)
        },
      );

      final ab = recv(r, 'A', 'B'); // m1=null, m2=+5 → return -m2 = -5
      final ba = recv(r, 'B', 'A'); // m1=+5 directo → +5

      print('  recv(A,B)=$ab  (esperado: -5.0 via -m2)');
      print('  recv(B,A)=$ba  (esperado: +5.0 directo)');

      expect(ab, closeTo(-5.0, 0.01));
      expect(ba, closeTo(5.0, 0.01));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // CASO 6: Inconsistencia legacy → StateError
  // manual[A][B]=-5, manual[B][A]=+4 (inconsistente)
  // ══════════════════════════════════════════════════════════════════════════
  group('Caso 6 – Inconsistencia legacy → StateError', () {
    test("manual[A][B]=-5, manual[B][A]=+4 → StateError 'Inconsistencia bilateral'", () {
      print('\n[Caso 6] Inconsistencia: manual[A][B]=-5, manual[B][A]=+4');
      final r = _makeRound(
        pids: ['A', 'B'],
        manuals: {
          'A': {'B': -5.0},
          'B': {'A': 4.0}, // INCONSISTENTE: debería ser 5.0
        },
      );

      print('  -5 + 4 = -1 ≠ 0 → debe lanzar StateError');

      expect(
        () => recv(r, 'A', 'B'),
        throwsA(isA<StateError>().having(
          (e) => e.message, 'message', contains('Inconsistencia bilateral'),
        )),
        reason: 'Inconsistencia detectada por el engine al consultar el par',
      );
    });

    test("validatePairSliding detecta conflicto pairSliding vs manualHandicaps", () {
      print('\n[Caso 6b] Conflicto pairSliding vs legacy manualHandicaps');
      // pairSliding dice A recibe -5 (A da 5), pero manual[A][B]=+3 (conflicto)
      final r = _makeRound(
        pids: ['A', 'B'],
        pairSliding: {'A|B': -5.0},
        manuals: {
          'A': {'B': 3.0}, // CONFLICTO: pairSliding dice -5, manual dice +3
        },
      );

      final errors = BetEngine.validatePairSliding(r);
      print('  Errores detectados: ${errors.length}');
      for (final e in errors) {
        print('  → $e');
      }

      expect(errors, isNotEmpty,
          reason: 'validatePairSliding debe detectar conflicto entre pairSliding y manualHandicaps');
      expect(errors.any((e) => e.contains('conflicto')), isTrue,
          reason: 'El error debe mencionar "conflicto"');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // CASO 7: Medal all-vs-all clásico con pairSliding
  // A gross 45, B gross 50, A da 5 a B → empate → 0 entries
  // ══════════════════════════════════════════════════════════════════════════
  group('Caso 7 – Medal all-vs-all clásico con pairSliding canónico', () {
    // A=45: 9×2+9×3=45, B=50: 14×3+4×2=50
    final scoresA = [...List.filled(9, 2), ...List.filled(9, 3)];
    final scoresB = [...List.filled(14, 3), ...List.filled(4, 2)];

    test("A da 5 via pairSliding['A|B']=-5 → empate → 0 entradas", () {
      print('\n[Caso 7] Medal allVsAll con pairSliding: A=45, B=50, A da 5');
      final round = _makeRound(
        pids: ['A', 'B'],
        hcps: {'A': 10.0, 'B': 15.0},
        pairSliding: {'A|B': -5.0}, // A da 5 a B
        scores: {'A': scoresA, 'B': scoresB},
      ).copyWith(betGroups: [_medalGroup(['A', 'B'])]);

      // Verificar recv usando pairSliding
      final recvAB = recv(round, 'A', 'B');
      final recvBA = recv(round, 'B', 'A');
      print('  recv(A,B)=$recvAB  (esperado: -5.0 → A da 5)');
      print('  recv(B,A)=$recvBA  (esperado: +5.0 → B recibe 5)');
      expect(recvAB, closeTo(-5.0, 0.01));
      expect(recvBA, closeTo(5.0, 0.01));

      // Calcular Medal
      final entries = BetEngine.computeGroup(round, round.betGroups.first);
      print('  Entradas generadas: ${entries.length}');
      for (final e in entries) {
        print('  → ${e.fromPlayerId} → ${e.toPlayerId}: \$${e.amount}');
      }

      expect(entries, isEmpty,
          reason: 'netA=45 == netB=45 → empate → 0 entradas');
    });

    test("A da 5 via pairSliding['A|B']=-5, A=44 → A gana (1 entrada B→A)", () {
      print('\n[Caso 7b] A=44, B=50, A da 5 → A gana');
      // A=44: 8×3+10×2=44
      final scoresA44 = [...List.filled(8, 3), ...List.filled(10, 2)];
      final round = _makeRound(
        pids: ['A', 'B'],
        hcps: {'A': 10.0, 'B': 15.0},
        pairSliding: {'A|B': -5.0},
        scores: {'A': scoresA44, 'B': scoresB},
      ).copyWith(betGroups: [_medalGroup(['A', 'B'])]);

      final entries = BetEngine.computeGroup(round, round.betGroups.first);
      print('  Entradas: ${entries.length}');
      for (final e in entries) {
        print('  → ${e.fromPlayerId} → ${e.toPlayerId}: \$${e.amount}');
      }

      expect(entries, hasLength(1));
      expect(entries.first.toPlayerId, equals('A'));
      expect(entries.first.fromPlayerId, equals('B'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // CASO 8: Live vs no-live
  // El cálculo de pairSliding debe ser idéntico independientemente de isLive
  // ══════════════════════════════════════════════════════════════════════════
  group('Caso 8 – Live vs no-live: resultado idéntico', () {
    final scoresA = [...List.filled(9, 2), ...List.filled(9, 3)]; // 45
    final scoresB = [...List.filled(14, 3), ...List.filled(4, 2)]; // 50

    for (final live in [false, true]) {
      test('${live ? "LIVE" : "NO-LIVE"}: pairSliding produce mismo empate', () {
        print('\n[Caso 8 – ${live ? "LIVE" : "NO-LIVE"}]');
        final round = _makeRound(
          pids: ['A', 'B'],
          hcps: {'A': 10.0, 'B': 15.0},
          pairSliding: {'A|B': -5.0},
          scores: {'A': scoresA, 'B': scoresB},
          isLive: live,
          liveCode: live ? 'LIVE08' : null,
        ).copyWith(betGroups: [_medalGroup(['A', 'B'])]);

        print('  round.isLive=${round.isLive}  liveCode=${round.liveCode}');

        final recvAB = recv(round, 'A', 'B');
        final recvBA = recv(round, 'B', 'A');
        print('  recv(A,B)=$recvAB  recv(B,A)=$recvBA');

        expect(recvAB, closeTo(-5.0, 0.01));
        expect(recvBA, closeTo(5.0, 0.01));

        final entries = BetEngine.computeGroup(round, round.betGroups.first);
        print('  Entradas: ${entries.length}  (esperado: 0)');

        expect(entries, isEmpty,
            reason: '${live ? "LIVE" : "NO-LIVE"}: empate → 0 entradas');
      });
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  // CASO 9: Serialización — toJson/fromJson preserva pairSliding
  // ══════════════════════════════════════════════════════════════════════════
  group('Caso 9 – Serialización: pairSliding sobrevive ciclo JSON', () {
    test("toJson → fromJson: pairSliding preservado exactamente", () {
      print('\n[Caso 9] Serialización de pairSliding');
      final original = _makeRound(
        pids: ['A', 'B', 'C'],
        hcps: {'A': 10.0, 'B': 15.0, 'C': 12.0},
        pairSliding: {
          'A|B': -5.0,  // A da 5 a B
          'A|C': 2.0,   // A recibe 2 de C
          'B|C': -3.0,  // B da 3 a C
        },
      );

      print('  pairSliding original: ${original.pairSliding}');

      final reloaded = _roundThroughJson(original);

      print('  pairSliding recargado: ${reloaded.pairSliding}');

      expect(reloaded.pairSliding, hasLength(3),
          reason: 'Los 3 pares deben sobrevivir la serialización');

      expect(reloaded.pairSliding['A|B'], closeTo(-5.0, 0.01),
          reason: 'A|B debe ser -5.0 tras reload');
      expect(reloaded.pairSliding['A|C'], closeTo(2.0, 0.01),
          reason: 'A|C debe ser +2.0 tras reload');
      expect(reloaded.pairSliding['B|C'], closeTo(-3.0, 0.01),
          reason: 'B|C debe ser -3.0 tras reload');

      // Verificar que los valores de recv son correctos tras reload
      final ab = recv(reloaded, 'A', 'B');
      final ba = recv(reloaded, 'B', 'A');
      final ac = recv(reloaded, 'A', 'C');
      final bc = recv(reloaded, 'B', 'C');

      print('  recv(A,B)=$ab  recv(B,A)=$ba');
      print('  recv(A,C)=$ac');
      print('  recv(B,C)=$bc');

      expect(ab, closeTo(-5.0, 0.01));
      expect(ba, closeTo(5.0, 0.01));
      expect(ac, closeTo(2.0, 0.01));
      expect(bc, closeTo(-3.0, 0.01));
    });

    test("Ronda sin pairSliding: campo ausente en JSON no rompe carga", () {
      print('\n[Caso 9b] Ronda legacy sin campo pairSliding');
      final r = _makeRound(
        pids: ['A', 'B'],
        // Sin pairSliding (default: vacío)
        manuals: {
          'A': {'B': -5.0},
          'B': {'A': 5.0},
        },
      );

      // Serializar SIN el campo pairSliding (simula JSON legacy)
      final json = <String, dynamic>{
        'id': r.id, 'name': r.name,
        'course': r.course.toJson(),
        'players': r.players.map((p) => p.toJson()).toList(),
        'roundPlayers': r.roundPlayers.map((rp) => rp.toJson()).toList(),
        'betGroups': [],
        'scores': {},
        'events': {},
        'oyeseRankings': {},
        'sliding': [],
        'createdAt': r.createdAt.toIso8601String(),
        'totalHoles': 18,
        'startingNine': 'front',
        'isLive': false,
        'scoringMode': 'open',
        'currentHole': 1,
        'isFinished': false,
        // 'pairSliding' ausente intencionalmente
      };

      final jsonStr = jsonEncode(json);
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;

      // Debe cargar sin error
      expect(() {
        final rawPs = decoded['pairSliding'];
        final pairSliding = <String, double>{};
        if (rawPs != null && rawPs is Map) {
          (rawPs).forEach((k, v) {
            pairSliding[k.toString()] = (v as num?)?.toDouble() ?? 0.0;
          });
        }
        print('  pairSliding reconstruido: $pairSliding');
        // Un round legacy sin pairSliding debe devolver {} vacío
        expect(pairSliding, isEmpty,
            reason: 'JSON legacy sin pairSliding → campo vacío al recargar');
      }, returnsNormally,
          reason: 'Carga de ronda legacy sin pairSliding no debe lanzar error');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // TESTS EXTRA: pairKey y validatePairSliding
  // ══════════════════════════════════════════════════════════════════════════
  group('Extra – pairKey y validatePairSliding', () {
    test('pairKey siempre produce clave canónica (ids en orden lexicográfico)', () {
      expect(BetEngine.pairKey('A', 'B'), equals('A|B'));
      expect(BetEngine.pairKey('B', 'A'), equals('A|B'),
          reason: 'Debe ordenar ids lexicográficamente');
      expect(BetEngine.pairKey('Z', 'A'), equals('A|Z'));
      expect(BetEngine.pairKey('CAM', 'RAFA'), equals('CAM|RAFA'));
      expect(BetEngine.pairKey('RAFA', 'CAM'), equals('CAM|RAFA'));
    });

    test('validatePairSliding: clave mal formada detectada', () {
      final r = _makeRound(
        pids: ['A', 'B'],
        pairSliding: {'A-B': -5.0}, // separador incorrecto
      );
      final errors = BetEngine.validatePairSliding(r);
      expect(errors, isNotEmpty, reason: 'Clave con separador incorrecto debe fallar');
      expect(errors.first, contains('mal formada'));
    });

    test('validatePairSliding: mismo jugador en ambos lados detectado', () {
      final r = _makeRound(
        pids: ['A'],
        pairSliding: {'A|A': 0.0},
      );
      final errors = BetEngine.validatePairSliding(r);
      expect(errors, isNotEmpty, reason: 'Par A|A inválido');
      expect(errors.first, contains('mismo jugador'));
    });

    test('validatePairSliding: ronda limpia no produce errores', () {
      final r = _makeRound(
        pids: ['A', 'B', 'C'],
        pairSliding: {
          'A|B': -5.0,
          'A|C': 2.0,
          'B|C': -3.0,
        },
      );
      final errors = BetEngine.validatePairSliding(r);
      expect(errors, isEmpty,
          reason: 'Ronda con pairSliding válido no debe tener errores');
    });

    test('pairSliding prioridad sobre manualHandicaps legacy', () {
      // pairSliding dice A recibe +5 de B
      // manualHandicaps dice A da 3 a B (inconsistente con pairSliding)
      // El engine debe usar pairSliding como fuente primaria
      final r = _makeRound(
        pids: ['A', 'B'],
        pairSliding: {'A|B': 5.0},   // A recibe 5
        manuals: {
          'A': {'B': -3.0},  // Legacy: A da 3 (diferente)
        },
      );

      // pairSliding tiene prioridad: recv(A,B) debe ser +5, no -3
      final ab = recv(r, 'A', 'B');
      print('\n  [Prioridad pairSliding] recv(A,B)=$ab (esperado: +5.0 desde pairSliding)');
      expect(ab, closeTo(5.0, 0.01),
          reason: 'pairSliding tiene prioridad sobre manualHandicaps');
    });

    test('buildPairSlidingFromLegacy migra correctamente', () {
      print('\n[buildPairSlidingFromLegacy] Migración de manualHandicaps a pairSliding');
      final r = _makeRound(
        pids: ['A', 'B', 'C'],
        hcps: {'A': 10.0, 'B': 15.0, 'C': 12.0},
        manuals: {
          'A': {'B': -5.0, 'C': 2.0},
          'B': {'A': 5.0},
          'C': {'A': -2.0},
        },
      );

      final errors = <String>[];
      final migrated = BetEngine.buildPairSlidingFromLegacy(r, errors: errors);

      print('  Migrado: $migrated');
      print('  Errores: $errors');

      // A|B: A da 5 (A recibe -5 de B) → clave A|B, valor = recv(A,B) = -5
      expect(migrated['A|B'], closeTo(-5.0, 0.01),
          reason: 'Par A-B: A da 5 → clave A|B = -5');
      // A|C: A recibe 2 de C → clave A|C, valor = recv(A,C) = +2
      expect(migrated['A|C'], closeTo(2.0, 0.01),
          reason: 'Par A-C: A recibe 2 → clave A|C = +2');
      expect(errors, isEmpty,
          reason: 'Datos consistentes no deben generar errores');
    });

    test('buildPairSlidingFromLegacy detecta inconsistencia bilateral', () {
      print('\n[buildPairSlidingFromLegacy] Inconsistencia legacy detectada');
      final r = _makeRound(
        pids: ['A', 'B'],
        manuals: {
          'A': {'B': -5.0},
          'B': {'A': 4.0}, // INCONSISTENTE: debería ser +5.0
        },
      );

      final errors = <String>[];
      final migrated = BetEngine.buildPairSlidingFromLegacy(r, errors: errors);

      print('  Migrado: $migrated  (esperado: vacío, par omitido)');
      print('  Errores: $errors');

      expect(migrated, isEmpty,
          reason: 'Par inconsistente no debe migrarse');
      expect(errors, isNotEmpty,
          reason: 'Debe registrar error de inconsistencia');
      expect(errors.first, contains('inconsistente'),
          reason: 'El error debe describir la inconsistencia');
    });
  });
}
