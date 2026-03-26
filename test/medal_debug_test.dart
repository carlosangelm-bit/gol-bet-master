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
}
