// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────────────────────

final _course = CourseInfo.standard;

Round _makeRound({
  required List<Map<String, dynamic>> players, // {id, name, hcp}
  required List<BetGroup> groups,
  required Map<String, List<int>> scores,      // playerId → [s1..s18], 0=sin score
  int totalHoles = 18,
}) {
  final rPlayers = players
      .map((p) => RoundPlayer(
            playerId: p['id'] as String,
            handicapEnRonda: (p['hcp'] as num).toDouble(),
          ))
      .toList();

  final pObjects = players
      .map((p) => Player(
            id: p['id'] as String,
            name: p['name'] as String,
            handicapBase: (p['hcp'] as num).toDouble(),
          ))
      .toList();

  // Construir Map<String, Map<int, HoleScore>>
  final scoresMap = <String, Map<int, HoleScore>>{};
  for (final entry in scores.entries) {
    final pid = entry.key;
    final holeMap = <int, HoleScore>{};
    for (int h = 0; h < entry.value.length; h++) {
      final s = entry.value[h];
      if (s > 0) {
        holeMap[h + 1] = HoleScore(playerId: pid, hole: h + 1, grossScore: s);
      }
    }
    if (holeMap.isNotEmpty) scoresMap[pid] = holeMap;
  }

  return Round(
    id: 'test_26mar',
    name: 'Ronda 26 Mar',
    course: _course,
    players: pObjects,
    roundPlayers: rPlayers,
    betGroups: groups,
    scores: scoresMap,
    events: const {},
    oyeseRankings: const {},
    sliding: const [],
    createdAt: DateTime(2025, 3, 26),
    totalHoles: totalHoles,
  );
}

BetModuleInstance _medalMod(List<String> pids, {bool net = true, int holes = 18}) =>
    BetModuleInstance.defaultFor(BetModuleType.medal, pids).copyWith(
      medalConfig: MedalConfig(
        value: 100,
        mode: net ? GrossNetMode.net : GrossNetMode.gross,
        holes: holes,
      ),
    );

// ──────────────────────────────────────────────────────────────────────────────
// Scores de 18 hoyos realistas para 4 jugadores
// A: gross 80, hcp 18 → strokes en campo estándar
// B: gross 71, hcp 10
// C: gross 86, hcp 26
// D: gross 74, hcp 14
// ──────────────────────────────────────────────────────────────────────────────
final _sA = [5,6,3,5,5,4,5,3,5, 5,4,3,5,5,4,5,3,5]; // gross 80
final _sB = [4,5,3,4,4,4,4,3,4, 4,5,3,4,4,4,4,3,4]; // gross 71
final _sC = [5,5,4,5,5,5,5,4,5, 5,5,4,5,5,5,5,4,5]; // gross 86
final _sD = [4,6,3,4,5,4,4,3,4, 4,6,3,4,5,4,4,3,4]; // gross 74

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  group('M1 – Medal 1v1 básico', () {
    test('M1a: duelo A vs B net → B gana (net menor)', () {
      final round = _makeRound(
        players: [
          {'id': 'A', 'name': 'Alice', 'hcp': 18},
          {'id': 'B', 'name': 'Bob', 'hcp': 10},
        ],
        groups: [
          BetGroup(
            id: 'g1',
            name: 'Duelo 1',
            format: PartidaFormat.oneVsOne,
            playerIds: ['A', 'B'],
            modules: [_medalMod(['A', 'B'])],
          ),
        ],
        scores: {'A': _sA, 'B': _sB},
      );

      final entries = BetEngine.computeAll(round);
      final m = entries.where((e) => e.betType == BetModuleType.medal).toList();
      print('[M1a] entries: $m');
      print('[M1a] breakdown A-perspective: ${LedgerEngine.breakdownBetween(round, "A", "B")}');

      expect(m, isNotEmpty, reason: 'Medal 1v1 debe generar al menos 1 entry');
      // B net < A net → A paga a B
      expect(m.any((e) => e.fromPlayerId == 'A' && e.toPlayerId == 'B'), isTrue,
          reason: 'B gana la medal en net');
    });

    test('M1b: duelo A vs B gross → B gana (gross menor)', () {
      final round = _makeRound(
        players: [
          {'id': 'A', 'name': 'Alice', 'hcp': 18},
          {'id': 'B', 'name': 'Bob', 'hcp': 10},
        ],
        groups: [
          BetGroup(
            id: 'g1',
            name: 'Duelo 1',
            format: PartidaFormat.oneVsOne,
            playerIds: ['A', 'B'],
            modules: [_medalMod(['A', 'B'], net: false)],
          ),
        ],
        scores: {'A': _sA, 'B': _sB},
      );

      final entries = BetEngine.computeAll(round);
      final m = entries.where((e) => e.betType == BetModuleType.medal).toList();
      print('[M1b] entries gross: $m');

      expect(m, isNotEmpty, reason: 'Medal gross debe generar entry');
      // B gross 71 < A gross 80 → B gana
      expect(m.any((e) => e.fromPlayerId == 'A' && e.toPlayerId == 'B'), isTrue);
    });

    test('M1c: empate real — verifica sin crash', () {
      // Mismos scores para ambos
      final round = _makeRound(
        players: [
          {'id': 'A', 'name': 'Alice', 'hcp': 10},
          {'id': 'B', 'name': 'Bob', 'hcp': 10},
        ],
        groups: [
          BetGroup(
            id: 'g1',
            name: 'Duelo 1',
            format: PartidaFormat.oneVsOne,
            playerIds: ['A', 'B'],
            modules: [_medalMod(['A', 'B'])],
          ),
        ],
        scores: {'A': _sB, 'B': _sB}, // mismos scores + mismo hcp → empate
      );

      expect(() => BetEngine.computeAll(round), returnsNormally);
      final m = BetEngine.computeAll(round)
          .where((e) => e.betType == BetModuleType.medal)
          .toList();
      print('[M1c] entries empate: $m');
      expect(m, isEmpty, reason: 'Empate neto no debe generar entries');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('M2 – Múltiples duelos (4 jugadores, 2 grupos)', () {
    test('M2a: 2 grupos independientes A+B y C+D — ambos calculan medal', () {
      final round = _makeRound(
        players: [
          {'id': 'A', 'name': 'Alice', 'hcp': 18},
          {'id': 'B', 'name': 'Bob', 'hcp': 10},
          {'id': 'C', 'name': 'Carol', 'hcp': 26},
          {'id': 'D', 'name': 'Dan', 'hcp': 14},
        ],
        groups: [
          BetGroup(
            id: 'g1',
            name: 'Duelo 1',
            format: PartidaFormat.oneVsOne,
            playerIds: ['A', 'B'],
            modules: [_medalMod(['A', 'B'])],
          ),
          BetGroup(
            id: 'g2',
            name: 'Duelo 2',
            format: PartidaFormat.oneVsOne,
            playerIds: ['C', 'D'],
            modules: [_medalMod(['C', 'D'])],
          ),
        ],
        scores: {'A': _sA, 'B': _sB, 'C': _sC, 'D': _sD},
      );

      final entries = BetEngine.computeAll(round);
      final m = entries.where((e) => e.betType == BetModuleType.medal).toList();
      print('[M2a] entries totales: ${m.length}');
      for (final e in m) {
        print('  ${e.fromPlayerId} → ${e.toPlayerId} \$${e.amount}');
      }

      // Grupo A+B: B tiene menor net → debe haber entry A→B
      final ab = m.where((e) =>
          (e.fromPlayerId == 'A' && e.toPlayerId == 'B') ||
          (e.fromPlayerId == 'B' && e.toPlayerId == 'A')).toList();
      expect(ab, isNotEmpty, reason: 'Duelo A+B debe producir entry de medal');

      // Grupo C+D: también debe producir entry (a menos que sea empate real)
      final cd = m.where((e) =>
          (e.fromPlayerId == 'C' && e.toPlayerId == 'D') ||
          (e.fromPlayerId == 'D' && e.toPlayerId == 'C')).toList();
      print('[M2a] entries C+D: $cd');
      // Si C y D tienen nets distintos, debe haber entry
    });

    test('M2b: participantIds vacíos → fallback a group.playerIds', () {
      // Simula módulo antiguo sin participantIds
      final modVacio = BetModuleInstance.defaultFor(BetModuleType.medal, []).copyWith(
        medalConfig: const MedalConfig(value: 50),
        participantIds: [],
      );

      final round = _makeRound(
        players: [
          {'id': 'A', 'name': 'Alice', 'hcp': 18},
          {'id': 'B', 'name': 'Bob', 'hcp': 10},
        ],
        groups: [
          BetGroup(
            id: 'g1',
            name: 'Duelo 1',
            format: PartidaFormat.oneVsOne,
            playerIds: ['A', 'B'],
            modules: [modVacio],
          ),
        ],
        scores: {'A': _sA, 'B': _sB},
      );

      final m = BetEngine.computeAll(round)
          .where((e) => e.betType == BetModuleType.medal)
          .toList();
      print('[M2b] entries con participantIds=[]: $m');
      expect(m, isNotEmpty,
          reason: 'participantIds vacío debe hacer fallback a group.playerIds');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('M3 – Medal con hoyos incompletos', () {
    test('M3a: solo F9 jugado — calcula con lo que hay', () {
      final sA9 = [5,6,3,5,5,4,5,3,5, 0,0,0,0,0,0,0,0,0];
      final sB9 = [4,5,3,4,4,4,4,3,4, 0,0,0,0,0,0,0,0,0];

      final round = _makeRound(
        players: [
          {'id': 'A', 'name': 'Alice', 'hcp': 18},
          {'id': 'B', 'name': 'Bob', 'hcp': 10},
        ],
        groups: [
          BetGroup(
            id: 'g1',
            name: 'Duelo 1',
            format: PartidaFormat.oneVsOne,
            playerIds: ['A', 'B'],
            modules: [_medalMod(['A', 'B'], holes: 9)],
          ),
        ],
        scores: {'A': sA9, 'B': sB9},
        totalHoles: 18,
      );

      expect(() => BetEngine.computeAll(round), returnsNormally);
      final m = BetEngine.computeAll(round)
          .where((e) => e.betType == BetModuleType.medal)
          .toList();
      print('[M3a] entries F9 parcial: $m');
      // B gross F9 = 35, A gross F9 = 40 → B gana
      expect(m, isNotEmpty, reason: 'Medal debe calcularse aunque haya hoyos sin jugar');
    });

    test('M3b: B sin scores — no debe crashear', () {
      final round = _makeRound(
        players: [
          {'id': 'A', 'name': 'Alice', 'hcp': 18},
          {'id': 'B', 'name': 'Bob', 'hcp': 10},
        ],
        groups: [
          BetGroup(
            id: 'g1',
            name: 'Duelo 1',
            format: PartidaFormat.oneVsOne,
            playerIds: ['A', 'B'],
            modules: [_medalMod(['A', 'B'])],
          ),
        ],
        scores: {'A': _sA, 'B': List.filled(18, 0)},
      );

      expect(() => BetEngine.computeAll(round), returnsNormally,
          reason: 'No debe crashear con un jugador sin scores');
      final m = BetEngine.computeAll(round)
          .where((e) => e.betType == BetModuleType.medal)
          .toList();
      print('[M3b] entries B sin scores: $m');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('M4 – Medal allVsAll (3 jugadores)', () {
    test('M4a: 3 jugadores allVsAll — entries para cada par', () {
      final round = _makeRound(
        players: [
          {'id': 'A', 'name': 'Alice', 'hcp': 18},
          {'id': 'B', 'name': 'Bob', 'hcp': 10},
          {'id': 'C', 'name': 'Carol', 'hcp': 26},
        ],
        groups: [
          BetGroup(
            id: 'g1',
            name: 'Grupo',
            format: PartidaFormat.allInOnePot,
            playerIds: ['A', 'B', 'C'],
            modules: [
              BetModuleInstance.defaultFor(BetModuleType.medal, ['A', 'B', 'C']).copyWith(
                medalConfig: const MedalConfig(value: 100),
                formatMode: BetFormatMode.allVsAll,
              ),
            ],
          ),
        ],
        scores: {'A': _sA, 'B': _sB, 'C': _sC},
      );

      final m = BetEngine.computeAll(round)
          .where((e) => e.betType == BetModuleType.medal)
          .toList();
      print('[M4a] allVsAll 3 jugadores:');
      for (final e in m) {
        print('  ${e.fromPlayerId} → ${e.toPlayerId} \$${e.amount}');
      }
      // 3 pares: A-B, A-C, B-C — al menos 2 deben tener ganador (el 3ro puede ser empate real)
      // Los strokes se calculan hoyo a hoyo con strokesReceivedVs, no simplemente diff*1
      expect(m.length, greaterThanOrEqualTo(2),
          reason: 'allVsAll 3 jugadores debe generar ≥2 entries (al menos 2 pares con ganador)');
      // Además verificar que A y B específicamente tienen entry (B net < A net)
      final abEntry = m.where((e) =>
          (e.fromPlayerId == 'A' && e.toPlayerId == 'B') ||
          (e.fromPlayerId == 'B' && e.toPlayerId == 'A')).toList();
      expect(abEntry, isNotEmpty, reason: 'Par A-B debe tener ganador en allVsAll');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('M5 – Visibilidad en la UI (breakdownBetween / byBetType)', () {
    late Round round;
    setUp(() {
      round = _makeRound(
        players: [
          {'id': 'A', 'name': 'Alice', 'hcp': 18},
          {'id': 'B', 'name': 'Bob', 'hcp': 10},
        ],
        groups: [
          BetGroup(
            id: 'g1',
            name: 'Duelo 1',
            format: PartidaFormat.oneVsOne,
            playerIds: ['A', 'B'],
            modules: [_medalMod(['A', 'B'])],
          ),
        ],
        scores: {'A': _sA, 'B': _sB},
      );
    });

    test('M5a: breakdownBetween incluye medal en la UI', () {
      final bd = LedgerEngine.breakdownBetween(round, 'A', 'B');
      print('[M5a] breakdown A-B: $bd');
      expect(bd.containsKey(BetModuleType.medal), isTrue,
          reason: 'La UI debe ver medal en el breakdown entre A y B');
    });

    test('M5b: byBetType incluye medal', () {
      final bt = LedgerEngine.byBetType(round);
      print('[M5b] byBetType keys: ${bt.keys.toList()}');
      expect(bt.containsKey(BetModuleType.medal), isTrue,
          reason: 'byBetType debe listar medal');
    });

    test('M5c: playerBalances refleja medal', () {
      final bal = LedgerEngine.playerBalances(round);
      print('[M5c] balances: $bal');
      // B gana → B positivo, A negativo
      expect((bal['B'] ?? 0) > 0, isTrue, reason: 'B debe tener balance positivo');
      expect((bal['A'] ?? 0) < 0, isTrue, reason: 'A debe tener balance negativo');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('M6 – Serialización: useHandicap / mode round-trip', () {
    test('M6a: MedalConfig.fromJson mode=net → useHandicap=true', () {
      final j = {'value': 100, 'mode': 'net', 'holes': 18, 'payoutRule': 'winnerTakesAll'};
      final cfg = MedalConfig.fromJson(j);
      print('[M6a] mode: ${cfg.mode}');
      expect(cfg.mode, equals(GrossNetMode.net));
    });

    test('M6b: BetModuleInstance medal net → useHandicap=true', () {
      final mod = _medalMod(['A', 'B'], net: true);
      print('[M6b] useHandicap=${mod.useHandicap}, medal.mode=${mod.medal.mode}');
      expect(mod.useHandicap, isTrue);
    });

    test('M6c: round-trip JSON preserva mode net', () {
      final mod = _medalMod(['A', 'B'], net: true);
      final mod2 = BetModuleInstance.fromJson(mod.toJson());
      print('[M6c] original=${mod.medal.mode}, restaurado=${mod2.medal.mode}');
      expect(mod2.medal.mode, equals(GrossNetMode.net));
    });

    test('M6d: round-trip JSON preserva mode gross', () {
      final mod = _medalMod(['A', 'B'], net: false);
      final mod2 = BetModuleInstance.fromJson(mod.toJson());
      print('[M6d] original=${mod.medal.mode}, restaurado=${mod2.medal.mode}');
      expect(mod2.medal.mode, equals(GrossNetMode.gross));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('M7 – useHandicap getter: fuente de verdad en BetModuleInstance', () {
    test('M7a: useHandicap usa medal.mode cuando es módulo medal', () {
      final modNet   = _medalMod(['A'], net: true);
      final modGross = _medalMod(['A'], net: false);
      expect(modNet.useHandicap,   isTrue,  reason: 'medal net → useHandicap true');
      expect(modGross.useHandicap, isFalse, reason: 'medal gross → useHandicap false');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('M8 – onePot 3+ jugadores con manualHandicaps (escenario 26 Mar)', () {
    // Replica el escenario real: 5 jugadores en un grupo onePot con ventajas manuales
    // CAM (hcp 6) es la base — da strokes a todos.
    // KAWA recibe 7 de CAM, FRANK recibe 14, RICH recibe 9, ALEX recibe 9
    // Gross: CAM=77, KAWA=81, FRANK=91, RICH=97, ALEX=86
    // Net esperado (con base CAM):
    //   CAM:  77 (base, juega en bruto)
    //   KAWA: 81 - 7  = 74 ← GANADOR (menor net)
    //   FRANK:91 - 14 = 77
    //   RICH: 97 - 9  = 88
    //   ALEX: 86 - 9  = 77
    // Ganador: KAWA con net 74 (único)
    final sCam   = [4,4,5,4,5,4,4,4,4, 4,5,4,4,5,4,4,5,4]; // gross 77
    final sKawa  = [5,5,4,4,5,4,5,4,5, 5,5,4,4,5,4,5,4,4]; // gross 81
    final sFrank = [5,5,5,5,5,5,5,5,5, 5,5,5,5,5,5,5,5,6]; // gross 91
    final sRich  = [6,6,5,5,6,5,5,6,5, 6,6,5,5,6,5,5,6,6]; // gross 97
    final sAlex  = [5,5,5,4,5,5,5,5,5, 5,5,5,4,5,5,5,5,5]; // gross 86

    Round make26Mar() {
      final rPlayers = [
        RoundPlayer(
          playerId: 'CAM',
          handicapEnRonda: 6.0,
          manualHandicaps: {}, // CAM es la base, no recibe de nadie
        ),
        RoundPlayer(
          playerId: 'KAWA',
          handicapEnRonda: 13.0,
          manualHandicaps: {'CAM': 7}, // KAWA recibe 7 de CAM
        ),
        RoundPlayer(
          playerId: 'FRANK',
          handicapEnRonda: 20.0,
          manualHandicaps: {'CAM': 14}, // FRANK recibe 14 de CAM
        ),
        RoundPlayer(
          playerId: 'RICH',
          handicapEnRonda: 15.0,
          manualHandicaps: {'CAM': 9}, // RICH recibe 9 de CAM
        ),
        RoundPlayer(
          playerId: 'ALEX',
          handicapEnRonda: 15.0,
          manualHandicaps: {'CAM': 9}, // ALEX recibe 9 de CAM
        ),
      ];

      final pObjects = [
        Player(id: 'CAM',   name: 'CAM',   handicapBase: 6.0),
        Player(id: 'KAWA',  name: 'KAWA',  handicapBase: 13.0),
        Player(id: 'FRANK', name: 'FRANK', handicapBase: 20.0),
        Player(id: 'RICH',  name: 'RICH',  handicapBase: 15.0),
        Player(id: 'ALEX',  name: 'ALEX',  handicapBase: 15.0),
      ];

      final scoresMap = <String, Map<int, HoleScore>>{};
      final rawScores = {
        'CAM': sCam, 'KAWA': sKawa, 'FRANK': sFrank,
        'RICH': sRich, 'ALEX': sAlex,
      };
      for (final entry in rawScores.entries) {
        final pid = entry.key;
        final holeMap = <int, HoleScore>{};
        for (int h = 0; h < entry.value.length; h++) {
          final s = entry.value[h];
          if (s > 0) {
            holeMap[h + 1] = HoleScore(playerId: pid, hole: h + 1, grossScore: s);
          }
        }
        scoresMap[pid] = holeMap;
      }

      final pids = ['CAM', 'KAWA', 'FRANK', 'RICH', 'ALEX'];
      final mod = BetModuleInstance.defaultFor(BetModuleType.medal, pids).copyWith(
        medalConfig: const MedalConfig(value: 100, mode: GrossNetMode.net),
      );

      return Round(
        id: 'test_26mar_real',
        name: 'Ronda 26 Mar (real)',
        course: _course,
        players: pObjects,
        roundPlayers: rPlayers,
        betGroups: [
          BetGroup(
            id: 'g1',
            name: 'Grupo Principal',
            format: PartidaFormat.allInOnePot,
            playerIds: pids,
            modules: [mod],
          ),
        ],
        scores: scoresMap,
        events: const {},
        oyeseRankings: const {},
        sliding: const [],
        createdAt: DateTime(2025, 3, 26),
        totalHoles: 18,
      );
    }

    test('M8a: onePot 5 jugadores con manualHandicaps — debe generar entries', () {
      final round = make26Mar();
      final entries = BetEngine.computeAll(round);
      final m = entries.where((e) => e.betType == BetModuleType.medal).toList();

      print('[M8a] entries: ${m.length}');
      for (final e in m) {
        print('  ${e.fromPlayerId} → ${e.toPlayerId} \$${e.amount}');
      }

      // Debe haber entries (no vacío) — el bug anterior generaba 0
      expect(m, isNotEmpty,
          reason: 'Con 5 jugadores y manualHandicaps, debe haber entries de medal (bug: generaba 0)');

      // Un único ganador — todos pagan al mismo jugador
      final winners = m.map((e) => e.toPlayerId).toSet();
      expect(winners.length, equals(1),
          reason: 'Debe haber exactamente un ganador en onePot');

      // Los 4 no-ganadores pagan al ganador
      expect(m.length, equals(4),
          reason: 'Los 4 jugadores no-ganadores deben pagar al ganador');

      // KAWA debería ganar (menor net con manualHandicap vs base)
      // El net exacto depende del SI hoyo a hoyo, pero KAWA debe ser el ganador
      // dado que su gross - strokes es menor que el de la base (CAM)
      final winner = winners.first;
      print('[M8a] Ganador: $winner');
      expect(winner, equals('KAWA'), reason: 'KAWA tiene menor net con manualHandicap aplicado');
    });

    test('M8b: diagnoseMedal muestra la base correcta', () {
      final round = make26Mar();
      final diag = BetEngine.diagnoseMedal(round);

      expect(diag, isNotEmpty);
      final d = diag.first;
      print('[M8b] reason: ${d['reason']}');
      print('[M8b] nets: ${d['nets']}');
      print('[M8b] entries: ${d['entries']}');

      expect(d['entries'], greaterThan(0),
          reason: 'diagnoseMedal debe reportar entries > 0');
      expect((d['reason'] as String).contains('CAM'), isTrue,
          reason: 'El reason debe mencionar a CAM como base');
      expect((d['reason'] as String).contains('KAWA'), isTrue,
          reason: 'El reason debe mencionar a KAWA como ganador');
    });

    test('M8c: gross mode — ignora manualHandicaps, gana quien menor gross', () {
      final round = make26Mar();
      // Reemplazar módulo con gross mode
      final pids = ['CAM', 'KAWA', 'FRANK', 'RICH', 'ALEX'];
      final modGross = BetModuleInstance.defaultFor(BetModuleType.medal, pids).copyWith(
        medalConfig: const MedalConfig(value: 100, mode: GrossNetMode.gross),
      );
      final roundGross = Round(
        id: 'test_26mar_gross',
        name: 'Ronda 26 Mar gross',
        course: _course,
        players: round.players,
        roundPlayers: round.roundPlayers,
        betGroups: [
          BetGroup(
            id: 'g1',
            name: 'Grupo Principal',
            format: PartidaFormat.allInOnePot,
            playerIds: pids,
            modules: [modGross],
          ),
        ],
        scores: round.scores,
        events: const {},
        oyeseRankings: const {},
        sliding: const [],
        createdAt: DateTime(2025, 3, 26),
        totalHoles: 18,
      );

      final entries = BetEngine.computeAll(roundGross);
      final m = entries.where((e) => e.betType == BetModuleType.medal).toList();

      print('[M8c] gross entries: ${m.length}');
      for (final e in m) {
        print('  ${e.fromPlayerId} → ${e.toPlayerId} \$${e.amount}');
      }

      // En gross, CAM tiene el menor score (75) → debe ganar
      expect(m, isNotEmpty, reason: 'Gross mode también debe generar entries');
      expect(m.every((e) => e.toPlayerId == 'CAM'), isTrue,
          reason: 'CAM gana en gross (menor score bruto)');
    });
  });
}
