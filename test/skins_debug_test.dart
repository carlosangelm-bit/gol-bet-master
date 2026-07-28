// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/game_engine.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';

// Cursos de test
final _course18 = CourseInfo(
  name: '18H Test',
  holes: [
    for (int i = 0; i < 9; i++)
      CourseHole(hole: i + 1, par: 4, strokeIndex: (i * 2) + 1),
    for (int i = 0; i < 9; i++)
      CourseHole(hole: i + 10, par: 4, strokeIndex: (i * 2) + 2),
  ],
);

final _courseB9 = CourseInfo(
  name: 'B9 Only',
  holes: [
    for (int i = 0; i < 9; i++)
      CourseHole(hole: i + 10, par: 4, strokeIndex: (i * 2) + 2),
  ],
);

final _courseF9 = CourseInfo(
  name: 'F9 Only',
  holes: [
    for (int i = 0; i < 9; i++)
      CourseHole(hole: i + 1, par: 4, strokeIndex: (i * 2) + 1),
  ],
);

// Curso de 9 hoyos numerados 1-9 con startingNine=back (como campos reales)
final _course9holes1to9 = CourseInfo(
  name: '9H (1-9)',
  holes: [
    for (int i = 0; i < 9; i++)
      CourseHole(hole: i + 1, par: 4, strokeIndex: (i * 2) + 1),
  ],
);

Round _makeRound({
  required List<Map<String, dynamic>> players,
  required List<BetGroup> groups,
  required Map<String, List<int>> scores,
  int totalHoles = 18,
  StartingNine startingNine = StartingNine.front,
  CourseInfo? course,
  Map<String, double>? pairSlid,
}) {
  final c = course ?? _course18;
  final List<int> holeNums;
  if (totalHoles <= 9) {
    holeNums = c.holes.map((ch) => ch.hole).toList()..sort();
  } else {
    holeNums = startingNine == StartingNine.back
        ? [...List.generate(9, (i) => i + 10), ...List.generate(9, (i) => i + 1)]
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

  final rPlayers = players.map((p) {
    final pid = p['id'] as String;
    final hcp = (p['hcp'] as num).toDouble();
    return RoundPlayer(playerId: pid, handicapEnRonda: hcp);
  }).toList();

  final pObjects = players
      .map((p) => Player(
            id: p['id'] as String,
            name: (p['name'] as String?) ?? (p['id'] as String),
            handicapBase: (p['hcp'] as num).toDouble(),
          ))
      .toList();

  return Round(
    id: 'skins-test',
    name: 'Skins Debug Test',
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

BetModuleInstance _skinsMod({
  double valuePerSkin = 10,
  bool carryOver = false,
  GrossNetMode mode = GrossNetMode.net,
  BetFormatMode formatMode = BetFormatMode.allVsAll,
}) =>
    BetModuleInstance(
      id: 'ski1',
      type: BetModuleType.skins,
      name: 'Skins',
      participantIds: const [],
      formatMode: formatMode,
      skinsConfig: SkinsConfig(
        valuePerSkin: valuePerSkin,
        carryOver: carryOver,
        mode: mode,
      ),
    );

void main() {
  // ===== S1: Skins 1v1 sin handicap — ganador claro en cada hoyo =====
  test('S1: Skins 1v1 gross — 18H, A gana todos los hoyos', () {
    // A siempre hace 4, B siempre hace 5 → A gana los 18 hoyos → 18 skins
    final mod = _skinsMod(valuePerSkin: 10, carryOver: false, mode: GrossNetMode.gross);
    final group = BetGroup(
      id: 'g1', name: 'G', format: PartidaFormat.allInOnePot,
      playerIds: const ['A', 'B'], modules: [mod],
    );
    final round = _makeRound(
      players: [{'id': 'A', 'hcp': 0}, {'id': 'B', 'hcp': 0}],
      groups: [group],
      scores: {
        'A': List.filled(18, 4),
        'B': List.filled(18, 5),
      },
      pairSlid: const {'A|B': 0.0},
    );

    final entries = BetEngine.computeGroup(round, group);
    print('\nS1: Skins gross sin HCP, A gana todos');
    for (final e in entries) {
      print('  H${e.hole}: ${e.fromPlayerId}→${e.toPlayerId} \$${e.amount}');
    }
    
    final toA = entries.where((e) => e.toPlayerId == 'A').toList();
    expect(toA.length, 18, reason: 'A debe ganar los 18 skins');
    expect(toA.every((e) => e.amount == 10), isTrue, reason: 'Cada skin = 10');
  });

  // ===== S2: Skins 1v1 sin handicap — empates acumulan carry =====
  test('S2: Skins 1v1 — empates con carry-over acumulan', () {
    // Hoyos 1-3: empate (4 vs 4) → carry acumula 3 skins
    // Hoyo 4: A gana (3 vs 4) → toma pot de 4 skins = 40
    // Hoyos 5-18: empate (sin carry en los restantes pq carryOver=false... 
    // pero acá lo ponemos con carryOver=true)
    final mod = _skinsMod(valuePerSkin: 10, carryOver: true, mode: GrossNetMode.gross);
    final group = BetGroup(
      id: 'g1', name: 'G', format: PartidaFormat.allInOnePot,
      playerIds: const ['A', 'B'], modules: [mod],
    );
    
    // Scores: hoyos 1-3 empatan, hoyo 4 A gana, resto empatan
    final aScores = List.filled(18, 4); // todo 4
    final bScores = List.filled(18, 4); // todo 4
    aScores[3] = 3; // hoyo 4 (índice 3): A hace 3

    final round = _makeRound(
      players: [{'id': 'A', 'hcp': 0}, {'id': 'B', 'hcp': 0}],
      groups: [group],
      scores: {'A': aScores, 'B': bScores},
      pairSlid: const {'A|B': 0.0},
    );

    final entries = BetEngine.computeGroup(round, group);
    print('\nS2: Carry-over — H1-3 empatan, H4 A gana');
    for (final e in entries) {
      print('  H${e.hole}: ${e.fromPlayerId}→${e.toPlayerId} \$${e.amount}');
    }
    
    final toA = entries.where((e) => e.toPlayerId == 'A').toList();
    expect(toA.length, 1, reason: 'Solo un skin ganado (H4)');
    expect(toA.first.hole, 4, reason: 'Ganado en H4');
    expect(toA.first.amount, 40.0, reason: 'H4 lleva carry de H1+H2+H3+H4 = 4 skins × 10 = 40');
  });

  // ===== S3: Skins 1v1 con handicap — ventaja aplicada correctamente =====
  test('S3: Skins 1v1 net — diff18=10, B9, A(HCP10) da 5 a B(HCP20)', () {
    // A(HCP10) da 10 a B(HCP20) en 18H → B9 share = ceil(10/2)=5
    // SEMÁNTICA pairSlid 'A|B': valor negativo = A (id menor) DA strokes = B recibe
    // 'A|B': -10.0 → A da 10 a B → B recibe 10 en 18H → 5 en B9
    // B recibe 1 stroke en los 5 hoyos de mejor SI (más difíciles)
    // A gross=4 en todos, B gross=5 en todos
    // En hoyos con stroke: B net=5-1=4 = A=4 → EMPATE
    // En hoyos sin stroke: B net=5, A=4 → A GANA
    // Con 5 strokes en 9 hoyos: 5 hoyos empatan, 4 hoyos A gana
    // Sin carry: A debe ganar 4 skins de 10 cada uno
    
    final mod = _skinsMod(valuePerSkin: 10, carryOver: false);
    final group = BetGroup(
      id: 'g1', name: 'G', format: PartidaFormat.allInOnePot,
      playerIds: const ['A', 'B'], modules: [mod],
    );
    final round = _makeRound(
      players: [{'id': 'A', 'hcp': 10}, {'id': 'B', 'hcp': 20}],
      groups: [group],
      scores: {
        'A': List.filled(9, 4), // todos 4 en B9
        'B': List.filled(9, 5), // todos 5 en B9
      },
      totalHoles: 9,
      startingNine: StartingNine.back,
      course: _courseB9,
      pairSlid: const {'A|B': -10.0}, // A da 10 a B (B recibe 10 = 5 en B9)
    );

    final entries = BetEngine.computeGroup(round, group);
    print('\nS3: B9, diff18=10, B recibe 5 strokes (A da)');
    for (final e in entries) {
      print('  H${e.hole}: ${e.fromPlayerId}→${e.toPlayerId} \$${e.amount} [${e.reason}]');
    }
    
    final toA = entries.where((e) => e.toPlayerId == 'A').toList();
    final toB = entries.where((e) => e.toPlayerId == 'B').toList();
    print('  A gana: ${toA.length} skins, B gana: ${toB.length} skins');
    
    expect(toB.length, 0, reason: 'B no gana ningún skin (B gross=5 incluso neto > A gross=4)');
    expect(toA.length, 4, reason: 'A gana los 4 hoyos sin stroke');
  });

  // ===== S4: Skins 1v1 — empate total (nadie gana) =====
  test('S4: Skins 1v1 gross — empate en todos los hoyos, sin entries', () {
    final mod = _skinsMod(valuePerSkin: 10, carryOver: false, mode: GrossNetMode.gross);
    final group = BetGroup(
      id: 'g1', name: 'G', format: PartidaFormat.allInOnePot,
      playerIds: const ['A', 'B'], modules: [mod],
    );
    final round = _makeRound(
      players: [{'id': 'A', 'hcp': 0}, {'id': 'B', 'hcp': 0}],
      groups: [group],
      scores: {
        'A': List.filled(18, 4),
        'B': List.filled(18, 4), // todos empatan
      },
      pairSlid: const {'A|B': 0.0},
    );

    final entries = BetEngine.computeGroup(round, group);
    print('\nS4: Empate total — sin carry');
    print('  Entries: ${entries.length}');
    expect(entries.isEmpty, isTrue, reason: 'Sin winner en ningún hoyo y sin carryOver → 0 entries');
  });

  // ===== S5: Skins 1v1 — empate total CON carry, pot acumulado pero sin ganador final =====
  test('S5: Skins 1v1 — empate en todos + carryOver, nadie cobra el pot final', () {
    final mod = _skinsMod(valuePerSkin: 10, carryOver: true, mode: GrossNetMode.gross);
    final group = BetGroup(
      id: 'g1', name: 'G', format: PartidaFormat.allInOnePot,
      playerIds: const ['A', 'B'], modules: [mod],
    );
    final round = _makeRound(
      players: [{'id': 'A', 'hcp': 0}, {'id': 'B', 'hcp': 0}],
      groups: [group],
      scores: {
        'A': List.filled(18, 4),
        'B': List.filled(18, 4),
      },
      pairSlid: const {'A|B': 0.0},
    );

    final entries = BetEngine.computeGroup(round, group);
    print('\nS5: Empate total con carryOver — pot acumulado sin cobrar');
    print('  Entries: ${entries.length}');
    expect(entries.isEmpty, isTrue, reason: 'Pot acumulado pero nadie gana → 0 cobros');
  });

  // ===== S6: Skins 1v1 — alternancia, A gana hoyos impares, B pares =====
  test('S6: Skins alternados — A gana hoyos impares (1,3,5...), B gana pares (2,4,6...)', () {
    final mod = _skinsMod(valuePerSkin: 10, carryOver: false, mode: GrossNetMode.gross);
    final group = BetGroup(
      id: 'g1', name: 'G', format: PartidaFormat.allInOnePot,
      playerIds: const ['A', 'B'], modules: [mod],
    );
    
    final aScores = <int>[];
    final bScores = <int>[];
    for (int h = 1; h <= 18; h++) {
      if (h.isOdd) { aScores.add(3); bScores.add(4); } // A gana
      else         { aScores.add(4); bScores.add(3); } // B gana
    }

    final round = _makeRound(
      players: [{'id': 'A', 'hcp': 0}, {'id': 'B', 'hcp': 0}],
      groups: [group],
      scores: {'A': aScores, 'B': bScores},
      pairSlid: const {'A|B': 0.0},
    );

    final entries = BetEngine.computeGroup(round, group);
    print('\nS6: Skins alternados A/B');
    for (final e in entries) {
      print('  H${e.hole}: ${e.fromPlayerId}→${e.toPlayerId} \$${e.amount}');
    }
    
    final toA = entries.where((e) => e.toPlayerId == 'A').toList();
    final toB = entries.where((e) => e.toPlayerId == 'B').toList();
    
    expect(toA.length, 9, reason: 'A gana 9 hoyos (impares)');
    expect(toB.length, 9, reason: 'B gana 9 hoyos (pares)');
    expect(toA.map((e) => e.hole).toSet(), {1,3,5,7,9,11,13,15,17});
    expect(toB.map((e) => e.hole).toSet(), {2,4,6,8,10,12,14,16,18});
  });

  // ===== S7: Skins 1v1 carry-over — H1 empata, H2 B gana, lleva carry de H1 =====
  test('S7: Carry-over — H1 empata, H2 B gana, toma pot = 2 skins', () {
    final mod = _skinsMod(valuePerSkin: 10, carryOver: true, mode: GrossNetMode.gross);
    final group = BetGroup(
      id: 'g1', name: 'G', format: PartidaFormat.allInOnePot,
      playerIds: const ['A', 'B'], modules: [mod],
    );
    
    // H1: empate (4vs4), H2: B gana (5vs4), resto empatan
    final aScores = List.filled(18, 4);
    final bScores = List.filled(18, 4);
    bScores[1] = 3; // B hace 3 en H2 (índice 1)

    final round = _makeRound(
      players: [{'id': 'A', 'hcp': 0}, {'id': 'B', 'hcp': 0}],
      groups: [group],
      scores: {'A': aScores, 'B': bScores},
      pairSlid: const {'A|B': 0.0},
    );

    final entries = BetEngine.computeGroup(round, group);
    print('\nS7: H1 empate → carry; H2 B gana pot = 20');
    for (final e in entries) {
      print('  H${e.hole}: ${e.fromPlayerId}→${e.toPlayerId} \$${e.amount}');
    }
    
    final toB = entries.where((e) => e.toPlayerId == 'B').toList();
    expect(toB.length, 1, reason: 'Solo H2 con skin para B');
    expect(toB.first.hole, 2);
    expect(toB.first.amount, 20.0, reason: 'H1(carry) + H2 = 2 skins × 10 = 20');
  });

  // ===== S8: Skins onePot grupal 3 jugadores =====
  test('S8: Skins onePot 3 jugadores — cada perdedor paga valuePerSkin al ganador', () {
    // 3 jugadores, A siempre gana
    // Por hoyo: B paga 10 a A, C paga 10 a A → 2 × 10 = 20 total recibe A
    // (cada perdedor paga valuePerSkin=10, no pot/(n-1)=5)
    final mod = _skinsMod(valuePerSkin: 10, carryOver: false, mode: GrossNetMode.gross, formatMode: BetFormatMode.onePot);
    final group = BetGroup(
      id: 'g1', name: 'G', format: PartidaFormat.allInOnePot,
      playerIds: const ['A', 'B', 'C'], modules: [mod],
    );
    final round = _makeRound(
      players: [
        {'id': 'A', 'hcp': 0},
        {'id': 'B', 'hcp': 0},
        {'id': 'C', 'hcp': 0},
      ],
      groups: [group],
      scores: {
        'A': List.filled(18, 3), // A siempre gana
        'B': List.filled(18, 4),
        'C': List.filled(18, 4),
      },
      pairSlid: const {},
    );

    final entries = BetEngine.computeGroup(round, group);
    print('\nS8: OnePot 3 jugadores, A gana todo');
    for (final e in entries.take(4)) {
      print('  H${e.hole}: ${e.fromPlayerId}→${e.toPlayerId} \$${e.amount}');
    }
    
    // Por hoyo ganado: B→A y C→A (2 entries × 10)
    final toA = entries.where((e) => e.toPlayerId == 'A').toList();
    print('  Total entries para A: ${toA.length} (esperado: 36 = 18 hoyos × 2 pagos)');
    expect(toA.length, 36, reason: '18 hoyos × 2 pagadores = 36 entries');
    // Cada perdedor paga valuePerSkin=10 (no 5)
    expect(toA.every((e) => e.amount == 10), isTrue, reason: 'Cada pago = 10 (valuePerSkin)');
  });

  // ===== S9: Skins 1v1 net — ventaja correcta en B9 con campo 1-9 numerado como B9 =====
  test('S9: Skins B9 campo 1-9 numerado, startingNine=back, diff18=10', () {
    // Campo de 9 hoyos numerados 1-9 pero se juega como B9
    // A(HCP10) da 10 a B(HCP20) → B9 share = ceil(10/2)=5
    // pairSlid 'A|B': -10.0 → A da 10 a B (B recibe, id menor A da)
    // B recibe 5 strokes en los 5 hoyos de menor SI
    // A gross=4, B gross=5 → sin stroke A gana (4<5), con stroke empata (4 vs 5-1=4)
    final mod = _skinsMod(valuePerSkin: 10, carryOver: false);
    final group = BetGroup(
      id: 'g1', name: 'G', format: PartidaFormat.allInOnePot,
      playerIds: const ['A', 'B'], modules: [mod],
    );
    final round = _makeRound(
      players: [{'id': 'A', 'hcp': 10}, {'id': 'B', 'hcp': 20}],
      groups: [group],
      scores: {
        'A': List.filled(9, 4),
        'B': List.filled(9, 5),
      },
      totalHoles: 9,
      startingNine: StartingNine.back,
      course: _course9holes1to9,
      pairSlid: const {'A|B': -10.0}, // A da 10 a B (B recibe = id mayor recibe cuando valor negativo)
    );

    final entries = BetEngine.computeGroup(round, group);
    print('\nS9: B9 campo 1-9, diff18=10, B recibe 5');
    for (final e in entries) {
      print('  H${e.hole}: ${e.fromPlayerId}→${e.toPlayerId} \$${e.amount}');
    }
    
    final toA = entries.where((e) => e.toPlayerId == 'A').toList();
    final toB = entries.where((e) => e.toPlayerId == 'B').toList();
    print('  A gana: ${toA.length}, B gana: ${toB.length}');
    
    // Con diff18=10 y 9 hoyos, share=5 → 5 hoyos con stroke (empate) + 4 sin stroke (A gana)
    expect(toA.length, 4, reason: 'A gana 4 hoyos sin stroke');
    expect(toB.length, 0, reason: 'B no gana ninguno (gross siempre mayor)');
  });

  // ===== S10: Skins 1v1 carry + ventaja — carry se acumula en empates netos =====
  test('S10: Skins 1v1 net + carry — empates netos acumulan carry', () {
    // B recibe 9 strokes de A en 18H (diff18=9)
    // Front-start: F9 share = ceil(9/2)=5
    // Los 5 hoyos de mayor SI (SI 1,3,5,7,9) reciben 1 stroke cada uno
    // A gross=4, B gross=5 en todos
    // Hoyos con stroke (5 hoyos): A=4, B net=5-1=4 → EMPATE → carry
    // Hoyos sin stroke (4 hoyos): A=4, B net=5 → A gana con pot acumulado
    // 
    // Con carryOver=true:
    // - Los hoyos con empate acumulan carry antes del siguiente sin stroke
    // - El orden de SI en _courseF9: H1=SI1, H2=SI3, H3=SI5, H4=SI7, H5=SI9, H6=SI11...
    // - Strokes van en H1,H2,H3,H4,H5 (SI 1,3,5,7,9 → los 5 más difíciles)
    // Orden de la ronda (front-start): H1,H2,...,H9
    // H1: empate (stroke) → carry
    // H2: empate (stroke) → carry
    // H3: empate (stroke) → carry  
    // H4: empate (stroke) → carry
    // H5: empate (stroke) → carry
    // H6: A gana (sin stroke) → toma pot = 6 skins = 60
    // H7: A gana → 10
    // H8: A gana → 10
    // H9: A gana → 10
    
    final mod = _skinsMod(valuePerSkin: 10, carryOver: true);
    final group = BetGroup(
      id: 'g1', name: 'G', format: PartidaFormat.allInOnePot,
      playerIds: const ['A', 'B'], modules: [mod],
    );
    final round = _makeRound(
      players: [{'id': 'A', 'hcp': 10}, {'id': 'B', 'hcp': 19}],
      groups: [group],
      scores: {
        'A': List.filled(9, 4),
        'B': List.filled(9, 5),
      },
      totalHoles: 9,
      startingNine: StartingNine.front,
      course: _courseF9,
      pairSlid: const {'A|B': 9.0},
    );

    final entries = BetEngine.computeGroup(round, group);
    print('\nS10: F9 carry + ventaja, diff18=9, B recibe 5 strokes en F9');
    
    // Mostrar strokes por hoyo
    final f9holes = _courseF9.holes.toList();
    final playedHoles = f9holes;
    print('  Strokes por hoyo (diff18=9, F9, front-start):');
    for (final ch in f9holes) {
      final s = GameEngine.strokesReceivedFromOfficial18Sliding(
        diff18: 9, ch: ch, playedHolesInSameNine: playedHoles,
        startingNine: StartingNine.front,
      );
      print('    H${ch.hole} SI${ch.strokeIndex}: $s stroke(s)');
    }
    
    for (final e in entries) {
      print('  H${e.hole}: ${e.fromPlayerId}→${e.toPlayerId} \$${e.amount} pot=${e.amount}');
    }
    
    final toA = entries.where((e) => e.toPlayerId == 'A').toList();
    final totalA = toA.fold<double>(0, (s, e) => s + e.amount);
    print('  A gana: ${toA.length} skins, total=\$$totalA');
    
    // A debe ganar 4 hoyos (los sin stroke), pero con carry acumulado de los 5 empates
    expect(toA.length, greaterThan(0), reason: 'A debe ganar al menos un skin');
    expect(totalA, 90.0, reason: '9 skins × 10 = 90 (5 empates llevan a los 4 ganados)');
  });
}
