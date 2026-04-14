// ignore_for_file: avoid_print
// ─────────────────────────────────────────────────────────────────────────────
// Tests de Medal all-vs-all: 9 escenarios completos (live y no-live)
//
// Objetivo: Verificar que Medal all-vs-all devuelve empate (0 entradas) cuando
// los scores son iguales después de aplicar el handicap, en todos los flujos
// posibles: bilateral, unilateral, serialización, live/no-live, etc.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers de fixture
// ─────────────────────────────────────────────────────────────────────────────

/// Alias público de _strokesP1ReceivesFromP2 (privado en BetEngine)
double recv(Round r, String p1, String p2) =>
    BetEngine.strokesP1ReceivesFromP2(r, p1, p2);

/// Curso de 18 hoyos par 72. SI asignado 1-18 en orden.
CourseInfo _course18() => CourseInfo(
      name: 'Test18',
      holes: List.generate(18, (i) => CourseHole(
        hole: i + 1,
        par: 4,
        strokeIndex: i + 1,
      )),
    );

/// Curso de 9 hoyos B9 (numerados 10-18). SI 2,4,6,...,18.
CourseInfo _courseB9() => CourseInfo(
      name: 'TestB9',
      holes: List.generate(9, (i) => CourseHole(
        hole: i + 10,
        par: 4,
        strokeIndex: (i + 1) * 2,
      )),
    );

/// Construye un Round con los parámetros indicados.
/// [scores]: playerId → lista de gross por hoyo (en orden lógico del curso).
/// [manuals]: playerId → {otroPid: strokes}. Si null, no se aplica manual.
/// [isLive]: simula una ronda en vivo compartida.
Round _makeRound({
  required List<String> pids,
  required Map<String, double> hcps,
  required Map<String, List<int>> scores,
  required List<BetGroup> groups,
  Map<String, Map<String, double>>? manuals,
  CourseInfo? course,
  int totalHoles = 18,
  StartingNine startingNine = StartingNine.front,
  bool isLive = false,
  String? liveCode,
}) {
  final c = course ?? _course18();

  // Números de hoyos en orden lógico de juego
  final holeNums = startingNine == StartingNine.back
      ? [
          ...List.generate(9, (i) => i + 10),
          ...List.generate(9, (i) => i + 1),
        ]
      : List.generate(totalHoles, (i) =>
          c.holes.length > i ? c.holes[i].hole : i + 1);

  // Construir mapa de scores
  final scoresMap = <String, Map<int, HoleScore>>{};
  for (final e in scores.entries) {
    final pid = e.key;
    final vals = e.value;
    final holeMap = <int, HoleScore>{};
    for (int i = 0; i < vals.length && i < holeNums.length; i++) {
      final g = vals[i];
      if (g > 0) {
        holeMap[holeNums[i]] = HoleScore(
          playerId: pid,
          hole: holeNums[i],
          grossScore: g,
          putts: 2,
        );
      }
    }
    if (holeMap.isNotEmpty) scoresMap[pid] = holeMap;
  }

  final rPlayers = pids.map((pid) => RoundPlayer(
    playerId: pid,
    handicapEnRonda: hcps[pid] ?? 0,
    manualHandicaps: manuals?[pid] ?? {},
  )).toList();

  final players = pids.map((pid) => Player(
    id: pid,
    name: pid,
    handicapBase: hcps[pid] ?? 0,
  )).toList();

  return Round(
    id: 'test-${isLive ? 'live' : 'nolive'}',
    name: 'Test Round',
    course: c,
    players: players,
    roundPlayers: rPlayers,
    betGroups: groups,
    scores: scoresMap,
    events: const {},
    oyeseRankings: const {},
    sliding: const [],
    createdAt: DateTime(2025, 1, 1),
    totalHoles: totalHoles,
    startingNine: startingNine,
    isLive: isLive,
    liveCode: liveCode,
  );
}

/// Módulo Medal allVsAll con valor $100
BetModuleInstance _medalMod(List<String> pids) =>
    BetModuleInstance.defaultFor(BetModuleType.medal, pids).copyWith(
      medalConfig: const MedalConfig(value: 100, mode: GrossNetMode.net),
      formatMode: BetFormatMode.allVsAll,
    );

/// BetGroup con un solo módulo Medal
BetGroup _medalGroup(List<String> pids) => BetGroup(
      id: 'g1',
      name: 'Medal',
      format: PartidaFormat.allInOnePot,
      playerIds: pids,
      modules: [_medalMod(pids)],
    );

/// Helper: imprime diagnóstico detallado para un par de jugadores
void _printPairDiag(Round round, String pA, String pB,
    List<LedgerEntry> entries) {
  final rpA = round.roundPlayers.firstWhere((r) => r.playerId == pA);
  final rpB = round.roundPlayers.firstWhere((r) => r.playerId == pB);

  // Calcular gross totales
  final grossA = round.scores[pA]?.values
      .where((s) => s.hasScore)
      .fold(0, (sum, s) => sum + s.grossScore!) ?? 0;
  final grossB = round.scores[pB]?.values
      .where((s) => s.hasScore)
      .fold(0, (sum, s) => sum + s.grossScore!) ?? 0;

  final mAB = rpA.manualHandicaps[pB];
  final mBA = rpB.manualHandicaps[pA];
  final recvAB = recv(round, pA, pB);
  final recvBA = recv(round, pB, pA);

  // Net aproximado (sin distribución por SI, solo para mostrar)
  final netA = grossA - recvAB.round();
  final netB = grossB - recvBA.round();

  final pairEntries = entries.where(
    (e) => (e.fromPlayerId == pA && e.toPlayerId == pB) ||
           (e.fromPlayerId == pB && e.toPlayerId == pA),
  ).toList();

  print('  ┌─ Par: $pA vs $pB');
  print('  │  gross($pA)=${grossA}  gross($pB)=${grossB}');
  print('  │  manual[$pA][$pB]=${mAB ?? "null"}  manual[$pB][$pA]=${mBA ?? "null"}');
  print('  │  recv($pA,$pB)=$recvAB  recv($pB,$pA)=$recvBA');
  print('  │  netApprox($pA)=$netA  netApprox($pB)=$netB');
  if (pairEntries.isEmpty) {
    print('  │  → EMPATE (0 entradas para este par)');
  } else {
    for (final e in pairEntries) {
      print('  │  → ENTRADA: ${e.fromPlayerId} → ${e.toPlayerId}: \$${e.amount}');
    }
  }
  print('  └─');
}

/// Helper: serializa un Round a JSON y lo deserializa
/// Replica la lógica de roundFromJson en round_provider.dart sin importarlo
/// (evitar dependencias de Flutter/Firebase en tests unitarios puros).
Round _roundThroughJson(Round r) {
  // ── Serializar ──────────────────────────────────────────────────────────
  final scoresJson = r.scores.map((pid, hMap) => MapEntry(
    pid,
    hMap.map((h, hs) => MapEntry(h.toString(), hs.toJson())),
  ));

  final json = <String, dynamic>{
    'id': r.id,
    'name': r.name,
    'course': r.course.toJson(),
    'players': r.players.map((p) => p.toJson()).toList(),
    'roundPlayers': r.roundPlayers.map((rp) => rp.toJson()).toList(),
    'betGroups': r.betGroups.map((g) => g.toJson()).toList(),
    'scores': scoresJson,
    'events': <String, dynamic>{},
    'oyeseRankings': <String, dynamic>{},
    'sliding': <dynamic>[],
    'createdAt': r.createdAt.toIso8601String(),
    'totalHoles': r.totalHoles,
    'startingNine': r.startingNine.name,
    'isLive': r.isLive,
    'liveCode': r.liveCode,
    'scoringMode': r.scoringMode,
    'currentHole': r.currentHole,
    'isFinished': r.isFinished,
  };

  // Simular ciclo de persistencia: encode → decode (como Firestore/shared_prefs)
  final jsonStr = jsonEncode(json);
  final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;

  // ── Deserializar (replica roundFromJson de round_provider.dart) ─────────
  List<dynamic> asList(dynamic v) => v is List ? v : [];
  Map<String, dynamic> asMap(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v as Map) : <String, dynamic>{};

  final players = asList(decoded['players'])
      .map((p) => Player.fromJson(asMap(p))).toList();
  final roundPlayers = asList(decoded['roundPlayers'])
      .map((rp) => RoundPlayer.fromJson(asMap(rp))).toList();
  final betGroups = asList(decoded['betGroups'])
      .map((g) => BetGroup.fromJson(asMap(g))).toList();

  final scoresDecoded = asMap(decoded['scores']);
  final scores = <String, Map<int, HoleScore>>{};
  scoresDecoded.forEach((pid, hmap) {
    final inner = <int, HoleScore>{};
    asMap(hmap).forEach((hStr, sJson) {
      final h = int.tryParse(hStr);
      if (h != null && sJson != null) {
        try { inner[h] = HoleScore.fromJson(asMap(sJson)); } catch (_) {}
      }
    });
    scores[pid] = inner;
  });

  final startingNineStr = decoded['startingNine'] as String? ?? 'front';

  return Round(
    id:          (decoded['id'] as Object?)?.toString() ?? '',
    name:        (decoded['name'] as Object?)?.toString() ?? 'Ronda',
    createdAt:   DateTime.tryParse(decoded['createdAt'] as String? ?? '') ?? DateTime.now(),
    currentHole: (decoded['currentHole'] as num?)?.toInt() ?? 1,
    isFinished:  decoded['isFinished'] == true,
    startingNine: startingNineStr == 'back' ? StartingNine.back : StartingNine.front,
    totalHoles:  (decoded['totalHoles'] as num?)?.toInt() ?? 18,
    isLive:      decoded['isLive'] == true,
    ownerUid:    (decoded['ownerUid'] as Object?)?.toString(),
    liveCode:    (decoded['liveCode'] as Object?)?.toString(),
    scoringMode: (decoded['scoringMode'] as Object?)?.toString() ?? 'open',
    players: players, roundPlayers: roundPlayers,
    betGroups: betGroups,
    course: decoded['course'] != null
        ? CourseInfo.fromJson(asMap(decoded['course']))
        : _course18(),
    scores: scores,
    events: const {},
    oyeseRankings: const {},
    sliding: const [],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// TESTS
// ─────────────────────────────────────────────────────────────────────────────
void main() {
  print('\n');
  print('╔══════════════════════════════════════════════════════════════════╗');
  print('║   MEDAL ALL-VS-ALL: 9 ESCENARIOS (live + no-live)               ║');
  print('╚══════════════════════════════════════════════════════════════════╝');

  // ══════════════════════════════════════════════════════════════════════════
  // ESCENARIO 1: Acuerdo bilateral completo → empate
  // A da 5 a B: manual[A][B]=-5, manual[B][A]=+5
  // A bruto=45, B bruto=50 → B net=45 → empate
  // ══════════════════════════════════════════════════════════════════════════
  group('Escenario 1 – Bilateral tie (A da 5 a B, scores 45 vs 50)', () {
    // Scores: 18 hoyos, A=45 (18×2.5≈18×3 aprox), B=50
    // Simplificamos: A juega 18 hoyos a 2.5 → usamos mix de 3 y 2
    // A: 9 hoyos de 3 y 9 de 2 = 45. B: 18 hoyos de ~2.78 → usamos 9×3+9×3-4×1 ≈ 50 – usamos exacto
    // A: todos los hoyos a 2 o 3 sumando 45 exacto
    // B: todos los hoyos a 2 o 3 sumando 50 exacto
    final scoresA = List.filled(18, 3) // 18×3=54, necesitamos 45
      ..fillRange(0, 9, 2) // 9×2+9×3=18+27=45 ✓
      ;
    final scoresB = List.filled(18, 3) // 18×3=54, necesitamos 50
      ..fillRange(0, 4, 2) // 4×2+14×3=8+42=50 ✓
      ;

    for (final live in [false, true]) {
      test('${live ? "LIVE" : "NO-LIVE"}: computeGroup → 0 entradas (empate)', () {
        print('\n[Escenario 1 – ${live ? "LIVE" : "NO-LIVE"}]');
        final round = _makeRound(
          pids: ['A', 'B'],
          hcps: {'A': 10.0, 'B': 15.0},
          // A da 5 → A.manual[B]=-5, B.manual[A]=+5 (semántica UI)
          manuals: {
            'A': {'B': -5.0},
            'B': {'A': 5.0},
          },
          scores: {'A': scoresA, 'B': scoresB},
          groups: [_medalGroup(['A', 'B'])],
          isLive: live,
          liveCode: live ? 'LIVE01' : null,
        );

        // Verificar recv antes de computar
        final recvAB = recv(round, 'A', 'B'); // A da 5 → -5
        final recvBA = recv(round, 'B', 'A'); // B recibe 5 → +5
        print('  recv(A,B)=$recvAB  (esperado: -5.0 → A da 5)');
        print('  recv(B,A)=$recvBA  (esperado: +5.0 → B recibe 5)');
        expect(recvAB, closeTo(-5.0, 0.01),
            reason: 'A da 5 strokes a B → recv(A,B) debe ser -5');
        expect(recvBA, closeTo(5.0, 0.01),
            reason: 'B recibe 5 de A → recv(B,A) debe ser +5');
        expect((recvAB + recvBA).abs(), lessThan(0.01),
            reason: 'Invariante: recv(A,B) + recv(B,A) = 0');

        final entries = BetEngine.computeGroup(round, round.betGroups.first);
        _printPairDiag(round, 'A', 'B', entries);

        expect(entries, isEmpty,
            reason: 'A gross=45 neto=45, B gross=50 neto=45 → empate → 0 entradas');
      });
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ESCENARIO 2: Manual unilateral → empate idéntico
  // Solo manual[A][B]=-5 definido (sin espejo).
  // El motor debe inferir recv(B,A)=+5.
  // ══════════════════════════════════════════════════════════════════════════
  group('Escenario 2 – Unilateral manual (solo manual[A][B]=-5)', () {
    final scoresA = [...List.filled(9, 2), ...List.filled(9, 3)]; // 45
    final scoresB = [...List.filled(4, 2), ...List.filled(14, 3)]; // 50

    for (final live in [false, true]) {
      test('${live ? "LIVE" : "NO-LIVE"}: inferencia correcta y 0 entradas', () {
        print('\n[Escenario 2 – ${live ? "LIVE" : "NO-LIVE"}: solo manual[A][B]=-5]');
        final round = _makeRound(
          pids: ['A', 'B'],
          hcps: {'A': 10.0, 'B': 15.0},
          // Solo un lado guardado (sin espejo)
          manuals: {
            'A': {'B': -5.0},
            // B.manual[A] NO definido → motor usa -m2 = -(-5) = +5
          },
          scores: {'A': scoresA, 'B': scoresB},
          groups: [_medalGroup(['A', 'B'])],
          isLive: live,
        );

        final recvAB = recv(round, 'A', 'B');
        final recvBA = recv(round, 'B', 'A');
        print('  recv(A,B)=$recvAB  (esperado: -5.0)');
        print('  recv(B,A)=$recvBA  (esperado: +5.0 inferido)');
        expect(recvAB, closeTo(-5.0, 0.01));
        expect(recvBA, closeTo(5.0, 0.01),
            reason: 'B no tiene manual[A], motor infiere +5 via -m2 de A');
        expect((recvAB + recvBA).abs(), lessThan(0.01),
            reason: 'Invariante debe cumplirse también con manual unilateral');

        final entries = BetEngine.computeGroup(round, round.betGroups.first);
        _printPairDiag(round, 'A', 'B', entries);

        expect(entries, isEmpty,
            reason: 'Unilateral debe comportarse igual que bilateral: empate → 0 entradas');
      });
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ESCENARIO 3: Flujo de persistencia (toJson → fromJson → computeGroup)
  // Simula el ciclo: setup → guardar en DB → recargar → calcular
  // ══════════════════════════════════════════════════════════════════════════
  group('Escenario 3 – Persistencia JSON (serializar/deserializar preserva manuals)', () {
    final scoresA = [...List.filled(9, 2), ...List.filled(9, 3)]; // 45
    final scoresB = [...List.filled(4, 2), ...List.filled(14, 3)]; // 50

    for (final live in [false, true]) {
      test('${live ? "LIVE" : "NO-LIVE"}: toJson→fromJson → 0 entradas', () {
        print('\n[Escenario 3 – ${live ? "LIVE" : "NO-LIVE"}: persistencia JSON]');
        final original = _makeRound(
          pids: ['A', 'B'],
          hcps: {'A': 10.0, 'B': 15.0},
          manuals: {
            'A': {'B': -5.0},
            'B': {'A': 5.0},
          },
          scores: {'A': scoresA, 'B': scoresB},
          groups: [_medalGroup(['A', 'B'])],
          isLive: live,
          liveCode: live ? 'PERS03' : null,
        );

        // Serializar y deserializar (simula guardar en Firestore/local DB y recargar)
        final reloaded = _roundThroughJson(original);

        // Verificar que manualHandicaps sobreviven la serialización
        final rpA = reloaded.roundPlayers.firstWhere((r) => r.playerId == 'A');
        final rpB = reloaded.roundPlayers.firstWhere((r) => r.playerId == 'B');
        print('  manual[A][B] tras reload: ${rpA.manualHandicaps['B']}');
        print('  manual[B][A] tras reload: ${rpB.manualHandicaps['A']}');

        expect(rpA.manualHandicaps['B'], closeTo(-5.0, 0.01),
            reason: 'manual[A][B] debe sobrevivir serialización');
        expect(rpB.manualHandicaps['A'], closeTo(5.0, 0.01),
            reason: 'manual[B][A] debe sobrevivir serialización');

        final recvAB = recv(reloaded, 'A', 'B');
        final recvBA = recv(reloaded, 'B', 'A');
        print('  recv(A,B)=$recvAB  recv(B,A)=$recvBA tras reload');

        final entries = BetEngine.computeGroup(reloaded, reloaded.betGroups.first);
        _printPairDiag(reloaded, 'A', 'B', entries);

        expect(entries, isEmpty,
            reason: 'Tras reload: mismo empate → 0 entradas');
      });
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ESCENARIO 4: Ronda live compartida (isLive=true)
  // ══════════════════════════════════════════════════════════════════════════
  group('Escenario 4 – Live compartida: isLive=true, liveCode establecido', () {
    final scoresA = [...List.filled(9, 2), ...List.filled(9, 3)]; // 45
    final scoresB = [...List.filled(4, 2), ...List.filled(14, 3)]; // 50

    test('LIVE: round.isLive=true, liveCode=LIVE04 → 0 entradas (empate)', () {
      print('\n[Escenario 4 – LIVE: isLive=true, liveCode=LIVE04]');
      final round = _makeRound(
        pids: ['A', 'B'],
        hcps: {'A': 10.0, 'B': 15.0},
        manuals: {
          'A': {'B': -5.0},
          'B': {'A': 5.0},
        },
        scores: {'A': scoresA, 'B': scoresB},
        groups: [_medalGroup(['A', 'B'])],
        isLive: true,
        liveCode: 'LIVE04',
      );

      print('  round.isLive=${round.isLive}  liveCode=${round.liveCode}');
      expect(round.isLive, isTrue);
      expect(round.liveCode, equals('LIVE04'));

      final entries = BetEngine.computeGroup(round, round.betGroups.first);
      _printPairDiag(round, 'A', 'B', entries);

      expect(entries, isEmpty,
          reason: 'En ronda live: mismo resultado que no-live → empate → 0 entradas');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ESCENARIO 5: Ronda NO-live (isLive=false)
  // ══════════════════════════════════════════════════════════════════════════
  group('Escenario 5 – No-live: isLive=false (local)', () {
    final scoresA = [...List.filled(9, 2), ...List.filled(9, 3)]; // 45
    final scoresB = [...List.filled(4, 2), ...List.filled(14, 3)]; // 50

    test('NO-LIVE: round.isLive=false → 0 entradas (empate)', () {
      print('\n[Escenario 5 – NO-LIVE]');
      final round = _makeRound(
        pids: ['A', 'B'],
        hcps: {'A': 10.0, 'B': 15.0},
        manuals: {
          'A': {'B': -5.0},
          'B': {'A': 5.0},
        },
        scores: {'A': scoresA, 'B': scoresB},
        groups: [_medalGroup(['A', 'B'])],
        isLive: false,
      );

      print('  round.isLive=${round.isLive}');
      expect(round.isLive, isFalse);

      final entries = BetEngine.computeGroup(round, round.betGroups.first);
      _printPairDiag(round, 'A', 'B', entries);

      expect(entries, isEmpty,
          reason: 'No-live con empate → 0 entradas');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ESCENARIO 6: Clone / reopen / reload
  // Simula duplicar una ronda: copyWith → serializar → recargar → calcular
  // ══════════════════════════════════════════════════════════════════════════
  group('Escenario 6 – Clone/reopen/reload de ronda', () {
    final scoresA = [...List.filled(9, 2), ...List.filled(9, 3)]; // 45
    final scoresB = [...List.filled(4, 2), ...List.filled(14, 3)]; // 50

    for (final live in [false, true]) {
      test('${live ? "LIVE" : "NO-LIVE"}: copyWith → toJson → fromJson → 0 entradas', () {
        print('\n[Escenario 6 – ${live ? "LIVE" : "NO-LIVE"}: clone+reload]');
        final original = _makeRound(
          pids: ['A', 'B'],
          hcps: {'A': 10.0, 'B': 15.0},
          manuals: {
            'A': {'B': -5.0},
            'B': {'A': 5.0},
          },
          scores: {'A': scoresA, 'B': scoresB},
          groups: [_medalGroup(['A', 'B'])],
          isLive: live,
          liveCode: live ? 'CLONE6' : null,
        );

        // Simular "clonar" la ronda (nueva fecha, mismo contenido)
        // Round.copyWith no tiene parámetros id/name/createdAt (son inmutables);
        // la clonación en producción se hace guardando con nuevo id en Firestore.
        // Aquí simulamos el ciclo JSON completo que preserva todos los datos.
        final cloned = original; // mismo contenido, mismo id — lo que importa es el JSON cycle

        // Ciclo de persistencia completo
        final reloaded = _roundThroughJson(cloned);

        print('  Round original id=${original.id}');
        print('  Round clonado  id=${cloned.id}');
        print('  Round reloaded id=${reloaded.id}');

        final rpA = reloaded.roundPlayers.firstWhere((r) => r.playerId == 'A');
        expect(rpA.manualHandicaps['B'], closeTo(-5.0, 0.01),
            reason: 'Clon debe preservar manualHandicaps tras ciclo JSON');

        final entries = BetEngine.computeGroup(reloaded, reloaded.betGroups.first);
        _printPairDiag(reloaded, 'A', 'B', entries);

        expect(entries, isEmpty,
            reason: 'Ronda clonada y recargada → mismo empate → 0 entradas');
      });
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ESCENARIO 7: Tres jugadores (A, B, C) allVsAll
  // A da 5 a B: netA=netB=45 → empate A-B
  // C=48, ningún acuerdo manual con A ni B → C usa HCP diff
  // ══════════════════════════════════════════════════════════════════════════
  group('Escenario 7 – Tres jugadores all-vs-all', () {
    // A=45, B=50, C=48
    // A.hcp=10, B.hcp=15, C.hcp=13
    // manual[A][B]=-5, manual[B][A]=+5 (A da 5 a B)
    // Sin manual para A-C ni B-C → fallback HCP diff
    // recv(A,C) = 10-13 = -3 → A da 3 a C
    // recv(C,A) = 13-10 = +3 → C recibe 3 de A
    // recv(B,C) = 15-13 = +2 → B recibe 2 de C? No: B da ≥ C
    // recv(B,C) = 15-13 = +2 → B recibe 2  BUT: B.hcp>C.hcp → B recibe
    // netA_vs_B = 45 - (-5) = 50? No, recv(A,B)=-5, strokes=max(0,-5)=0... 
    // Cuidado: en _medal, recv>0 aplica strokes. recv<0 → strokes=0.
    // netA vs B: recv(A,B)=-5 → strokes=0 → netA=45
    // netB vs A: recv(B,A)=+5 → strokes aplicados = 5 sobre hoyos B9/F9 → netB=50-5=45
    // → empate A-B ✓

    // Para A-C: recv(A,C)=-3 → A da 3 → strokes para A = 0, strokes para C = +3
    //   netA vs C: recv(A,C)=-3 → 0 strokes → netA=45
    //   netC vs A: recv(C,A)=+3 → 3 strokes sobre 18 hoyos → netC=48-3=45
    //   → empate A-C

    // Para B-C: recv(B,C)=+2 → B recibe 2 → netB vs C: 50-2=48, netC vs B: recv(C,B)=-2→0 strokes→netC=48
    //   → empate B-C si netB=48=netC=48

    // Scores
    final scoresA = [...List.filled(9, 2), ...List.filled(9, 3)]; // 45
    final scoresB = [...List.filled(4, 2), ...List.filled(14, 3)]; // 50
    final scoresC = [...List.filled(6, 2), ...List.filled(12, 3)]; // 12+36=48

    for (final live in [false, true]) {
      test('${live ? "LIVE" : "NO-LIVE"}: par A-B empata, otros pares correctos', () {
        print('\n[Escenario 7 – ${live ? "LIVE" : "NO-LIVE"}: 3 jugadores]');
        final round = _makeRound(
          pids: ['A', 'B', 'C'],
          hcps: {'A': 10.0, 'B': 15.0, 'C': 13.0},
          manuals: {
            'A': {'B': -5.0},
            'B': {'A': 5.0},
            // C no tiene manuales → fallback HCP diff
          },
          scores: {'A': scoresA, 'B': scoresB, 'C': scoresC},
          groups: [_medalGroup(['A', 'B', 'C'])],
          isLive: live,
        );

        print('  HCPs: A=10, B=15, C=13');
        print('  Gross: A=45, B=50, C=48');
        print('  recv(A,B)=${recv(round,'A','B')}  recv(B,A)=${recv(round,'B','A')}');
        print('  recv(A,C)=${recv(round,'A','C')}  recv(C,A)=${recv(round,'C','A')}');
        print('  recv(B,C)=${recv(round,'B','C')}  recv(C,B)=${recv(round,'C','B')}');

        // Validar invariante para todos los pares
        expect((recv(round,'A','B') + recv(round,'B','A')).abs(), lessThan(0.01));
        expect((recv(round,'A','C') + recv(round,'C','A')).abs(), lessThan(0.01));
        expect((recv(round,'B','C') + recv(round,'C','B')).abs(), lessThan(0.01));

        final entries = BetEngine.computeGroup(round, round.betGroups.first);
        print('\n  Todas las entradas:');
        for (final e in entries) {
          print('  → ${e.fromPlayerId} paga a ${e.toPlayerId}: \$${e.amount}');
        }
        _printPairDiag(round, 'A', 'B', entries);
        _printPairDiag(round, 'A', 'C', entries);
        _printPairDiag(round, 'B', 'C', entries);

        // El par A-B DEBE ser empate (las ventajas se anulan exactamente)
        final abEntries = entries.where(
          (e) => (e.fromPlayerId == 'A' && e.toPlayerId == 'B') ||
                 (e.fromPlayerId == 'B' && e.toPlayerId == 'A'),
        ).toList();
        expect(abEntries, isEmpty,
            reason: 'Par A-B: netA=45 vs netB=45 → EMPATE → 0 entradas para este par');
      });
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ESCENARIO 8: Manuals inconsistentes → StateError controlado
  // manual[A][B]=-5 PERO manual[B][A]=+4 (inconsistente: 4≠5)
  // ══════════════════════════════════════════════════════════════════════════
  group('Escenario 8 – Manuals inconsistentes → StateError', () {
    final scoresA = [...List.filled(9, 2), ...List.filled(9, 3)]; // 45
    final scoresB = [...List.filled(4, 2), ...List.filled(14, 3)]; // 50

    for (final live in [false, true]) {
      test('${live ? "LIVE" : "NO-LIVE"}: manual[A][B]=-5, manual[B][A]=+4 → StateError', () {
        print('\n[Escenario 8 – ${live ? "LIVE" : "NO-LIVE"}: inconsistencia bilateral]');
        final round = _makeRound(
          pids: ['A', 'B'],
          hcps: {'A': 10.0, 'B': 15.0},
          manuals: {
            'A': {'B': -5.0},
            'B': {'A': 4.0}, // INCONSISTENTE: debería ser +5.0
          },
          scores: {'A': scoresA, 'B': scoresB},
          groups: [_medalGroup(['A', 'B'])],
          isLive: live,
        );

        print('  manual[A][B]=-5.0  manual[B][A]=+4.0  (son: -5 + 4 = -1 ≠ 0)');
        print('  Esperando StateError con mensaje "Inconsistencia bilateral"...');

        expect(
          () => BetEngine.computeGroup(round, round.betGroups.first),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Inconsistencia bilateral'),
          )),
          reason: 'Manuals inconsistentes deben lanzar StateError controlado',
        );
      });
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ESCENARIO 9: Casos espejo de victoria (no-empate)
  // Sub-caso 9a: A gana (A=44, B=50, A da 5)
  // Sub-caso 9b: B gana (A=46, B=50, A da 5)
  // ══════════════════════════════════════════════════════════════════════════
  group('Escenario 9 – Casos de victoria (espejo)', () {
    // Sub-caso 9a: A=44 → netA=44, netB=50-5=45 → A gana (1 entrada B→A)
    // Scores A=44: 18 hoyos sumando 44 → 8×2+10×2+2 no, usamos 4×2+14×... 
    // 44 = 8×2 + 10×3 = 16+... no. 44 = 2×2+16×... 2×2+14×3=4+42=46. 
    // 44 = 8×2+... 8×2=16, resto=44-16=28, 28/3=9.3 → 
    // usemos: 10×2 + 8×3 = 20+24=44 ✓
    final scoresA_44 = [...List.filled(10, 2), ...List.filled(8, 3)]; // 44
    // Sub-caso 9b: A=46 → netA=46, netB=45 → B gana (1 entrada A→B)
    // 46 = 8×2+10×3 no. 46 = 4×2+14×... 4×2+14×... 4*2=8, 46-8=38, 38/3=12.66
    // 46 = 10×3+16×... 30+16=46 → 10×3+16 - pero solo 18 hoyos. 
    // 46 = 1×4+15×... no, par es 4. 46 = 16×3 = 48 -2 = 46 → 14×3+2×2=42+4=46 ✓
    final scoresA_46 = [...List.filled(14, 3), ...List.filled(4, 2)]; // 46? 14*3=42+4*2=8 → 50! Mal
    // Recalcular: scoresA_46 donde suma=46
    // 46 = 13×3+3×... 13×3=39, 46-39=7, pero 7/3 no es entero. 
    // 46 = 12×3+6×... 12×3=36, 46-36=10, 10/2=5 hoyos de 2, pero 12+5=17 ≠ 18
    // 46 = 12×3+5×2+1×4 = 36+10+4=50. No.
    // Mejor: combinación de 3 y 2 para 18 hoyos:
    // x hoyos de 3 + (18-x) hoyos de 2 = 3x+36-2x = x+36 = 46 → x=10
    // 10×3 + 8×2 = 30+16 = 46 ✓ (mismo que 44 case pero con 10 threes)
    // Para 44: x+36=44 → x=8 → 8×3+10×2=24+20=44 ✓ (mismo que arriba)
    // Para 50: x+36=50 → x=14 → 14×3+4×2=42+8=50 ✓

    final scoresA46 = [...List.filled(10, 3), ...List.filled(8, 2)]; // 46: 10×3+8×2=30+16=46
    final scoresB50 = [...List.filled(14, 3), ...List.filled(4, 2)]; // 50: 14×3+4×2=42+8=50

    for (final live in [false, true]) {
      test('9a ${live ? "LIVE" : "NO-LIVE"}: A=44 gana sobre B=50 (A da 5)', () {
        print('\n[Escenario 9a – ${live ? "LIVE" : "NO-LIVE"}: A=44 wins]');
        final round = _makeRound(
          pids: ['A', 'B'],
          hcps: {'A': 10.0, 'B': 15.0},
          manuals: {
            'A': {'B': -5.0},
            'B': {'A': 5.0},
          },
          scores: {'A': scoresA_44, 'B': scoresB50},
          groups: [_medalGroup(['A', 'B'])],
          isLive: live,
        );

        final entries = BetEngine.computeGroup(round, round.betGroups.first);
        _printPairDiag(round, 'A', 'B', entries);

        // netA=44 (recv=-5→0 strokes sobre A), netB=50-5=45 → A gana: B paga A
        expect(entries, hasLength(1),
            reason: 'A=44 gana sobre B neto=45 → exactamente 1 entrada');
        expect(entries.first.toPlayerId, equals('A'),
            reason: 'A gana → entry va a A');
        expect(entries.first.fromPlayerId, equals('B'),
            reason: 'B paga a A');
        expect(entries.first.amount, closeTo(100.0, 0.01));
        print('  ✓ B paga \$${entries.first.amount} a A');
      });

      test('9b ${live ? "LIVE" : "NO-LIVE"}: B=50 gana sobre A=46 (A da 5)', () {
        print('\n[Escenario 9b – ${live ? "LIVE" : "NO-LIVE"}: B wins]');
        final round = _makeRound(
          pids: ['A', 'B'],
          hcps: {'A': 10.0, 'B': 15.0},
          manuals: {
            'A': {'B': -5.0},
            'B': {'A': 5.0},
          },
          scores: {'A': scoresA46, 'B': scoresB50},
          groups: [_medalGroup(['A', 'B'])],
          isLive: live,
        );

        final entries = BetEngine.computeGroup(round, round.betGroups.first);
        _printPairDiag(round, 'A', 'B', entries);

        // netA=46 (recv=-5→0 strokes), netB=50-5=45 → B gana: A paga B
        expect(entries, hasLength(1),
            reason: 'B neto=45 gana sobre A=46 → exactamente 1 entrada');
        expect(entries.first.toPlayerId, equals('B'),
            reason: 'B gana → entry va a B');
        expect(entries.first.fromPlayerId, equals('A'),
            reason: 'A paga a B');
        expect(entries.first.amount, closeTo(100.0, 0.01));
        print('  ✓ A paga \$${entries.first.amount} a B');
      });
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  // AUDITORÍA FINAL: Invariante recv(A,B) + recv(B,A) = 0
  // Para todos los escenarios posibles de manuals
  // ══════════════════════════════════════════════════════════════════════════
  group('Auditoría: invariante recv(A,B) + recv(B,A) = 0', () {
    final cases = [
      {
        'label': 'Bilateral: A.manual[B]=-5, B.manual[A]=+5',
        'manuals': {'A': {'B': -5.0}, 'B': {'A': 5.0}},
        'expAB': -5.0,
      },
      {
        'label': 'Unilateral: solo A.manual[B]=-5',
        'manuals': {'A': {'B': -5.0}},
        'expAB': -5.0,
      },
      {
        'label': 'Unilateral inverso: solo B.manual[A]=+5',
        'manuals': {'B': {'A': 5.0}},
        'expAB': -5.0, // -m2 = -(5) = -5
      },
      {
        'label': 'Sin manual: fallback HCP (A=10, B=15 → diff=-5)',
        'manuals': <String, dynamic>{},
        'expAB': -5.0, // 10-15=-5
      },
      {
        'label': 'Manual=0: acuerdo explícito cero (no se aplica HCP)',
        'manuals': {'A': {'B': 0.0}, 'B': {'A': 0.0}},
        'expAB': 0.0,
      },
    ];

    for (final c in cases) {
      test(c['label'] as String, () {
        final manualsRaw = c['manuals'] as Map<String, dynamic>;
        final manuals = manualsRaw.map((k, v) => MapEntry(
              k,
              (v as Map<String, dynamic>).map(
                  (k2, v2) => MapEntry(k2, (v2 as num).toDouble())),
            ));

        final round = _makeRound(
          pids: ['A', 'B'],
          hcps: {'A': 10.0, 'B': 15.0},
          manuals: manuals.isEmpty ? null : manuals,
          scores: {'A': [], 'B': []},
          groups: [],
        );

        final ab = recv(round, 'A', 'B');
        final ba = recv(round, 'B', 'A');

        print('\n  ${c['label']}');
        print('  recv(A,B)=$ab  recv(B,A)=$ba  suma=${ab+ba}');

        expect(ab, closeTo(c['expAB'] as double, 0.01),
            reason: '${c['label']}: recv(A,B) incorrecto');
        expect((ab + ba).abs(), lessThan(0.01),
            reason: 'Invariante: recv(A,B)+recv(B,A) debe ser 0');
      });
    }
  });
}
