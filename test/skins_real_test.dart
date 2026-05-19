// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/game_engine.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';

// Campo B9 real (hoyos 10-18)
final _courseB9real = CourseInfo(
  name: 'B9 Real',
  holes: [
    // SI tipo real campo de golf
    CourseHole(hole: 10, par: 4, strokeIndex: 2),
    CourseHole(hole: 11, par: 4, strokeIndex: 8),
    CourseHole(hole: 12, par: 3, strokeIndex: 16),
    CourseHole(hole: 13, par: 4, strokeIndex: 4),
    CourseHole(hole: 14, par: 5, strokeIndex: 14),
    CourseHole(hole: 15, par: 4, strokeIndex: 6),
    CourseHole(hole: 16, par: 3, strokeIndex: 18),
    CourseHole(hole: 17, par: 4, strokeIndex: 10),
    CourseHole(hole: 18, par: 5, strokeIndex: 12),
  ],
);

// Campo de 9 hoyos numerados 1-9 (como muchos campos reales de 9H)  
final _course9H_1to9 = CourseInfo(
  name: '9H campo 1-9',
  holes: [
    CourseHole(hole: 1, par: 4, strokeIndex: 2),
    CourseHole(hole: 2, par: 4, strokeIndex: 8),
    CourseHole(hole: 3, par: 3, strokeIndex: 16),
    CourseHole(hole: 4, par: 4, strokeIndex: 4),
    CourseHole(hole: 5, par: 5, strokeIndex: 14),
    CourseHole(hole: 6, par: 4, strokeIndex: 6),
    CourseHole(hole: 7, par: 3, strokeIndex: 18),
    CourseHole(hole: 8, par: 4, strokeIndex: 10),
    CourseHole(hole: 9, par: 5, strokeIndex: 12),
  ],
);

Round makeRoundCAM_RAFA({
  required CourseInfo course,
  required StartingNine startingNine,
  required Map<String, List<int>> rawScores,
  double pairSlidingVal = 10.0, // positivo = RAFA recibe de CAM
  Map<String, Map<String, double>>? manualHcps,
}) {
  final allHoleNums = course.holes.map((h) => h.hole).toList()..sort();
  
  final scoresMap = <String, Map<int, HoleScore>>{};
  for (final entry in rawScores.entries) {
    final pid = entry.key;
    final vals = entry.value;
    final holeMap = <int, HoleScore>{};
    for (int i = 0; i < vals.length && i < allHoleNums.length; i++) {
      final s = vals[i];
      if (s > 0) {
        holeMap[allHoleNums[i]] = HoleScore(playerId: pid, hole: allHoleNums[i], grossScore: s, putts: 2);
      }
    }
    if (holeMap.isNotEmpty) scoresMap[pid] = holeMap;
  }
  
  final rpCAM = RoundPlayer(
    playerId: 'CAM', 
    handicapEnRonda: 10.0,
    manualHandicaps: manualHcps?['CAM'] ?? {},
  );
  final rpRAFA = RoundPlayer(
    playerId: 'RAFA', 
    handicapEnRonda: 20.0,
    manualHandicaps: manualHcps?['RAFA'] ?? {},
  );

  // pairSliding: 'CAM|RAFA' (C < R lexicográficamente)
  // valor positivo = CAM recibe
  // valor negativo = RAFA recibe (CAM da)
  // CAM hcp10, RAFA hcp20 → RAFA recibe → valor negativo para CAM|RAFA
  final pairKey = 'CAM'.compareTo('RAFA') <= 0 ? 'CAM|RAFA' : 'RAFA|CAM';
  print('  pairKey: $pairKey, valor: $pairSlidingVal (negativo = RAFA recibe de CAM)');
  
  return Round(
    id: 'cam-rafa-test',
    name: 'CAM vs RAFA',
    course: course,
    players: [
      Player(id: 'CAM', name: 'CAM', handicapBase: 10.0),
      Player(id: 'RAFA', name: 'RAFA', handicapBase: 20.0),
    ],
    roundPlayers: [rpCAM, rpRAFA],
    betGroups: [],
    scores: scoresMap,
    events: const {},
    oyeseRankings: const {},
    sliding: const [],
    createdAt: DateTime(2025, 1, 1),
    totalHoles: 9,
    startingNine: startingNine,
    pairSliding: {pairKey: pairSlidingVal},
  );
}

BetModuleInstance skinsMod({double val = 10, bool carry = false}) =>
    BetModuleInstance(
      id: 'ski1', type: BetModuleType.skins, name: 'Skins',
      participantIds: const [],
      formatMode: BetFormatMode.allVsAll,
      skinsConfig: SkinsConfig(valuePerSkin: val, carryOver: carry, mode: GrossNetMode.net),
    );

BetGroup skinsGroup(BetModuleInstance mod) => BetGroup(
  id: 'g1', name: 'G', format: PartidaFormat.allInOnePot,
  playerIds: const ['CAM', 'RAFA'], modules: [mod],
);

void main() {

  // Primero verificar la semántica de pairSliding
  test('SEMÁNTICA: CAM|RAFA con valor negativo = RAFA recibe', () {
    final course = _courseB9real;
    // 'CAM'.compareTo('RAFA') → 'C' < 'R' → clave = 'CAM|RAFA'
    // valor = -10 → CAM (low id) recibe -10 → CAM DA 10 a RAFA → RAFA recibe 10
    final round = Round(
      id: 't', name: 't', course: course,
      players: [Player(id:'CAM', name:'CAM', handicapBase:10), Player(id:'RAFA', name:'RAFA', handicapBase:20)],
      roundPlayers: [RoundPlayer(playerId:'CAM', handicapEnRonda:10), RoundPlayer(playerId:'RAFA', handicapEnRonda:20)],
      betGroups: [], scores: {},
      events: const {}, oyeseRankings: const {}, sliding: const [],
      createdAt: DateTime(2025,1,1), totalHoles: 9,
      startingNine: StartingNine.back,
      pairSliding: {'CAM|RAFA': -10.0}, // negativo → CAM da 10 a RAFA
    );
    final recvCAM = BetEngine.canonicalSlidingBetween(round, 'CAM', 'RAFA');
    final recvRAFA = BetEngine.canonicalSlidingBetween(round, 'RAFA', 'CAM');
    print('\nCAM recibe: $recvCAM (debe ser -10 = CAM da)');
    print('RAFA recibe: $recvRAFA (debe ser +10 = RAFA recibe)');
    expect(recvCAM, -10.0, reason: 'CAM da 10');
    expect(recvRAFA, 10.0, reason: 'RAFA recibe 10');
  });

  // Test principal: CAM vs RAFA, B9, RAFA recibe 10 strokes (5 en B9)
  test('SR1: CAM(10) vs RAFA(20) B9 — RAFA recibe 5 strokes en B9', () {
    print('\n=== SR1: CAM vs RAFA, B9 real (H10-18), diff18=10, RAFA recibe 5 ===');
    
    // Mostrar distribución de strokes
    final b9holes = _courseB9real.holes.toList();
    print('\nDistribución de strokes (diff18=10, B9, startingNine=back):');
    int totalStrokes = 0;
    for (final ch in b9holes) {
      final s = GameEngine.strokesReceivedFromOfficial18Sliding(
        diff18: 10, ch: ch, playedHolesInSameNine: b9holes,
        startingNine: StartingNine.back,
      );
      totalStrokes += s;
      print('  H${ch.hole} (SI${ch.strokeIndex}): $s stroke(s)');
    }
    print('  TOTAL strokes B9: $totalStrokes (debe ser 5 = ceil(10/2))');
    expect(totalStrokes, 5, reason: 'B9 debe recibir ceil(10/2)=5 strokes');
    
    // Escenario: CAM hace 4 en todos, RAFA hace 5 en todos
    // Hoyos con stroke (5 hoyos): RAFA net=5-1=4 = CAM=4 → EMPATE
    // Hoyos sin stroke (4 hoyos): RAFA net=5, CAM=4 → CAM GANA
    // CAM debe ganar 4 skins sin carry
    
    final mod = skinsMod(val: 10, carry: false);
    final group = skinsGroup(mod);
    
    final round = Round(
      id: 'cam-rafa-b9', name: 'CAM vs RAFA B9',
      course: _courseB9real,
      players: [Player(id:'CAM', name:'CAM', handicapBase:10), Player(id:'RAFA', name:'RAFA', handicapBase:20)],
      roundPlayers: [
        RoundPlayer(playerId:'CAM', handicapEnRonda:10),
        RoundPlayer(playerId:'RAFA', handicapEnRonda:20),
      ],
      betGroups: [group],
      scores: {
        'CAM':  {10:HoleScore(playerId:'CAM',  hole:10, grossScore:4, putts:2),
                 11:HoleScore(playerId:'CAM',  hole:11, grossScore:4, putts:2),
                 12:HoleScore(playerId:'CAM',  hole:12, grossScore:4, putts:2),
                 13:HoleScore(playerId:'CAM',  hole:13, grossScore:4, putts:2),
                 14:HoleScore(playerId:'CAM',  hole:14, grossScore:4, putts:2),
                 15:HoleScore(playerId:'CAM',  hole:15, grossScore:4, putts:2),
                 16:HoleScore(playerId:'CAM',  hole:16, grossScore:4, putts:2),
                 17:HoleScore(playerId:'CAM',  hole:17, grossScore:4, putts:2),
                 18:HoleScore(playerId:'CAM',  hole:18, grossScore:4, putts:2)},
        'RAFA': {10:HoleScore(playerId:'RAFA', hole:10, grossScore:5, putts:2),
                 11:HoleScore(playerId:'RAFA', hole:11, grossScore:5, putts:2),
                 12:HoleScore(playerId:'RAFA', hole:12, grossScore:5, putts:2),
                 13:HoleScore(playerId:'RAFA', hole:13, grossScore:5, putts:2),
                 14:HoleScore(playerId:'RAFA', hole:14, grossScore:5, putts:2),
                 15:HoleScore(playerId:'RAFA', hole:15, grossScore:5, putts:2),
                 16:HoleScore(playerId:'RAFA', hole:16, grossScore:5, putts:2),
                 17:HoleScore(playerId:'RAFA', hole:17, grossScore:5, putts:2),
                 18:HoleScore(playerId:'RAFA', hole:18, grossScore:5, putts:2)},
      },
      events: const {}, oyeseRankings: const {}, sliding: const [],
      createdAt: DateTime(2025,1,1), totalHoles: 9,
      startingNine: StartingNine.back,
      pairSliding: {'CAM|RAFA': -10.0}, // RAFA recibe 10
    );
    
    final entries = BetEngine.computeGroup(round, group);
    print('\nSkins entries:');
    for (final e in entries) print('  H${e.hole}: ${e.fromPlayerId}→${e.toPlayerId} \$${e.amount}');
    
    final toCAM  = entries.where((e) => e.toPlayerId == 'CAM').toList();
    final toRAFA = entries.where((e) => e.toPlayerId == 'RAFA').toList();
    print('CAM gana: ${toCAM.length}, RAFA gana: ${toRAFA.length}');
    
    expect(toRAFA.length, 0, reason: 'RAFA no gana ningún skin (gross siempre mayor)');
    expect(toCAM.length, 4, reason: 'CAM gana 4 hoyos sin stroke');
  });

  // Test con carry
  test('SR2: CAM vs RAFA B9 — carry acumula en empates netos', () {
    print('\n=== SR2: CAM vs RAFA, B9 real, carry=true, RAFA recibe 5 ===');
    
    final mod = skinsMod(val: 10, carry: true);
    final group = skinsGroup(mod);
    
    final round = Round(
      id: 'cam-rafa-b9-carry', name: 'CAM vs RAFA B9 carry',
      course: _courseB9real,
      players: [Player(id:'CAM', name:'CAM', handicapBase:10), Player(id:'RAFA', name:'RAFA', handicapBase:20)],
      roundPlayers: [
        RoundPlayer(playerId:'CAM', handicapEnRonda:10),
        RoundPlayer(playerId:'RAFA', handicapEnRonda:20),
      ],
      betGroups: [group],
      scores: {
        'CAM':  {10:HoleScore(playerId:'CAM',  hole:10, grossScore:4, putts:2),
                 11:HoleScore(playerId:'CAM',  hole:11, grossScore:4, putts:2),
                 12:HoleScore(playerId:'CAM',  hole:12, grossScore:4, putts:2),
                 13:HoleScore(playerId:'CAM',  hole:13, grossScore:4, putts:2),
                 14:HoleScore(playerId:'CAM',  hole:14, grossScore:4, putts:2),
                 15:HoleScore(playerId:'CAM',  hole:15, grossScore:4, putts:2),
                 16:HoleScore(playerId:'CAM',  hole:16, grossScore:4, putts:2),
                 17:HoleScore(playerId:'CAM',  hole:17, grossScore:4, putts:2),
                 18:HoleScore(playerId:'CAM',  hole:18, grossScore:4, putts:2)},
        'RAFA': {10:HoleScore(playerId:'RAFA', hole:10, grossScore:5, putts:2),
                 11:HoleScore(playerId:'RAFA', hole:11, grossScore:5, putts:2),
                 12:HoleScore(playerId:'RAFA', hole:12, grossScore:5, putts:2),
                 13:HoleScore(playerId:'RAFA', hole:13, grossScore:5, putts:2),
                 14:HoleScore(playerId:'RAFA', hole:14, grossScore:5, putts:2),
                 15:HoleScore(playerId:'RAFA', hole:15, grossScore:5, putts:2),
                 16:HoleScore(playerId:'RAFA', hole:16, grossScore:5, putts:2),
                 17:HoleScore(playerId:'RAFA', hole:17, grossScore:5, putts:2),
                 18:HoleScore(playerId:'RAFA', hole:18, grossScore:5, putts:2)},
      },
      events: const {}, oyeseRankings: const {}, sliding: const [],
      createdAt: DateTime(2025,1,1), totalHoles: 9,
      startingNine: StartingNine.back,
      pairSliding: {'CAM|RAFA': -10.0},
    );
    
    // Mostrar el orden en que se procesan los hoyos y los strokes
    final b9holes = _courseB9real.holes.toList();
    // Ordenar por SI para identificar dónde van los strokes
    final sorted = [...b9holes]..sort((a,b) => a.strokeIndex.compareTo(b.strokeIndex));
    print('\nOrden de hoyos por SI (strokes van en SI 1-5 para 5 strokes en B9):');
    for (int i = 0; i < sorted.length; i++) {
      final ch = sorted[i];
      final gets = i < 5 ? 1 : 0;
      print('  H${ch.hole} SI${ch.strokeIndex}: ${gets > 0 ? "STROKE" : "-"}');
    }
    
    final entries = BetEngine.computeGroup(round, group);
    print('\nSkins entries con carry:');
    for (final e in entries) print('  H${e.hole}: ${e.fromPlayerId}→${e.toPlayerId} \$${e.amount} [pot=${e.amount}]');
    
    final toCAM = entries.where((e) => e.toPlayerId == 'CAM').toList();
    final totalCAM = toCAM.fold<double>(0, (s, e) => s + e.amount);
    print('CAM gana: ${toCAM.length} skins, total=\$$totalCAM (esperado: 4 skins × 10 = \$40)');
    
    // Con carry=true: los 5 empates se acumulan, pero el orden de hoyos
    // determina cuándo se acumula el carry.
    // Los strokes van en los 5 hoyos de menor SI: H10(SI2), H13(SI4), H15(SI6), H11(SI8), H17(SI10)
    // Orden de la ronda B9 back-start: H10,H11,H12,...,H18
    // H10(SI2=stroke): empate → carry
    // H11(SI8=stroke): empate → carry (pot=30)
    // H12(SI16=no stroke): CAM gana → pot=30=3 skins... wait, SI16 no recibe stroke
    // Veamos: con 5 strokes en 9 hoyos B9, los strokes van en SI 1-5 (menor=más difícil en golf)
    // En este campo B9: SI2=H10, SI4=H13, SI6=H15, SI8=H11, SI10=H17 → 5 hoyos con stroke
    // Hoyos sin stroke: SI12=H18, SI14=H14, SI16=H12, SI18=H16
    // Orden de ronda: H10(S),H11(S),H12(N),H13(S),H14(N),H15(S),H16(N),H17(S),H18(N)
    // H10: empate(stroke) → pot=20
    // H11: empate(stroke) → pot=30
    // H12: CAM gana → toma 30, pot→10
    // H13: empate(stroke) → pot=20
    // H14: CAM gana → toma 20, pot→10
    // H15: empate(stroke) → pot=20
    // H16: CAM gana → toma 20, pot→10
    // H17: empate(stroke) → pot=20
    // H18: CAM gana → toma 20, pot→10
    // Total CAM: 30+20+20+20 = 90
    expect(totalCAM, 90.0, reason: 'CAM gana 4 hoyos con carry acumulado = 90');
  });
  
  // Test con campo 1-9 numerado como B9 (bug original del usuario)
  test('SR3: B9 campo numerado 1-9, startingNine=back — strokes correctos', () {
    print('\n=== SR3: B9 campo 1-9, startingNine=back, diff18=10 ===');
    
    final b9holes1to9 = _course9H_1to9.holes.toList();
    print('\nDistribución de strokes (diff18=10, campo 1-9 como B9):');
    int total = 0;
    for (final ch in b9holes1to9) {
      final s = GameEngine.strokesReceivedFromOfficial18Sliding(
        diff18: 10, ch: ch, playedHolesInSameNine: b9holes1to9,
        startingNine: StartingNine.back,
      );
      total += s;
      print('  H${ch.hole} (SI${ch.strokeIndex}): $s stroke(s)');
    }
    print('  TOTAL: $total (debe ser 5)');
    expect(total, 5, reason: 'Campo 1-9 como B9 debe recibir 5 strokes (ceil(10/2))');
    
    // Ejecutar skins engine
    final mod = skinsMod(val: 10, carry: false);
    final group = skinsGroup(mod);
    
    final holeNums = b9holes1to9.map((h) => h.hole).toList()..sort();
    final camScores = {for (final h in holeNums) h: HoleScore(playerId:'CAM', hole:h, grossScore:4, putts:2)};
    final rafaScores = {for (final h in holeNums) h: HoleScore(playerId:'RAFA', hole:h, grossScore:5, putts:2)};
    
    final round = Round(
      id: 'sr3', name: 'SR3',
      course: _course9H_1to9,
      players: [Player(id:'CAM', name:'CAM', handicapBase:10), Player(id:'RAFA', name:'RAFA', handicapBase:20)],
      roundPlayers: [
        RoundPlayer(playerId:'CAM', handicapEnRonda:10),
        RoundPlayer(playerId:'RAFA', handicapEnRonda:20),
      ],
      betGroups: [group],
      scores: {'CAM': camScores, 'RAFA': rafaScores},
      events: const {}, oyeseRankings: const {}, sliding: const [],
      createdAt: DateTime(2025,1,1), totalHoles: 9,
      startingNine: StartingNine.back,
      pairSliding: {'CAM|RAFA': -10.0},
    );
    
    final entries = BetEngine.computeGroup(round, group);
    print('\nSkins entries:');
    for (final e in entries) print('  H${e.hole}: ${e.fromPlayerId}→${e.toPlayerId} \$${e.amount}');
    
    final toCAM  = entries.where((e) => e.toPlayerId == 'CAM').toList();
    final toRAFA = entries.where((e) => e.toPlayerId == 'RAFA').toList();
    print('CAM gana: ${toCAM.length}, RAFA gana: ${toRAFA.length}');
    
    expect(toCAM.length, 4, reason: 'CAM gana 4 hoyos sin stroke');
    expect(toRAFA.length, 0);
  });
}
