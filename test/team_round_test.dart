import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';

void main() {
  group('Team Format Functionality', () {
    late List<Player> players;
    late CourseInfo course;
    late List<RoundPlayer> roundPlayers;
    late Map<String, Map<int, HoleScore>> scores;
    late BetSide sideA;
    late BetSide sideB;

    setUp(() {
      // 4 jugadores: Carlos (10), Alan (15), Samuel (8), Guillermo (12)
      players = [
        Player(id: 'p1', name: 'Carlos', handicapBase: 10.0, colorIndex: 0),
        Player(id: 'p2', name: 'Alan', handicapBase: 15.0, colorIndex: 1),
        Player(id: 'p3', name: 'Samuel', handicapBase: 8.0, colorIndex: 2),
        Player(id: 'p4', name: 'Guillermo', handicapBase: 12.0, colorIndex: 3),
      ];

      // Cancha estándar de 9 hoyos
      course = CourseInfo(
        name: 'Test Course',
        holes: [
          CourseHole(hole: 1, par: 4, strokeIndex: 5),
          CourseHole(hole: 2, par: 5, strokeIndex: 11),
          CourseHole(hole: 3, par: 3, strokeIndex: 15),
          CourseHole(hole: 4, par: 4, strokeIndex: 1),
          CourseHole(hole: 5, par: 4, strokeIndex: 9),
          CourseHole(hole: 6, par: 3, strokeIndex: 17),
          CourseHole(hole: 7, par: 4, strokeIndex: 3),
          CourseHole(hole: 8, par: 5, strokeIndex: 13),
          CourseHole(hole: 9, par: 4, strokeIndex: 7),
        ],
      );

      // RoundPlayers con handicaps congelados
      roundPlayers = [
        RoundPlayer(playerId: 'p1', handicapEnRonda: 10.0),
        RoundPlayer(playerId: 'p2', handicapEnRonda: 15.0),
        RoundPlayer(playerId: 'p3', handicapEnRonda: 8.0),
        RoundPlayer(playerId: 'p4', handicapEnRonda: 12.0),
      ];

      // Scores para los 9 hoyos
      scores = {
        'p1': {
          1: HoleScore(playerId: 'p1', hole: 1, grossScore: 5),
          2: HoleScore(playerId: 'p1', hole: 2, grossScore: 6),
          3: HoleScore(playerId: 'p1', hole: 3, grossScore: 4),
          4: HoleScore(playerId: 'p1', hole: 4, grossScore: 5),
          5: HoleScore(playerId: 'p1', hole: 5, grossScore: 5),
          6: HoleScore(playerId: 'p1', hole: 6, grossScore: 3),
          7: HoleScore(playerId: 'p1', hole: 7, grossScore: 4),
          8: HoleScore(playerId: 'p1', hole: 8, grossScore: 6),
          9: HoleScore(playerId: 'p1', hole: 9, grossScore: 5),
        },
        'p2': {
          1: HoleScore(playerId: 'p2', hole: 1, grossScore: 6),
          2: HoleScore(playerId: 'p2', hole: 2, grossScore: 7),
          3: HoleScore(playerId: 'p2', hole: 3, grossScore: 3),
          4: HoleScore(playerId: 'p2', hole: 4, grossScore: 6),
          5: HoleScore(playerId: 'p2', hole: 5, grossScore: 4),
          6: HoleScore(playerId: 'p2', hole: 6, grossScore: 4),
          7: HoleScore(playerId: 'p2', hole: 7, grossScore: 5),
          8: HoleScore(playerId: 'p2', hole: 8, grossScore: 7),
          9: HoleScore(playerId: 'p2', hole: 9, grossScore: 6),
        },
        'p3': {
          1: HoleScore(playerId: 'p3', hole: 1, grossScore: 4),
          2: HoleScore(playerId: 'p3', hole: 2, grossScore: 5),
          3: HoleScore(playerId: 'p3', hole: 3, grossScore: 3),
          4: HoleScore(playerId: 'p3', hole: 4, grossScore: 4),
          5: HoleScore(playerId: 'p3', hole: 5, grossScore: 5),
          6: HoleScore(playerId: 'p3', hole: 6, grossScore: 3),
          7: HoleScore(playerId: 'p3', hole: 7, grossScore: 4),
          8: HoleScore(playerId: 'p3', hole: 8, grossScore: 5),
          9: HoleScore(playerId: 'p3', hole: 9, grossScore: 4),
        },
        'p4': {
          1: HoleScore(playerId: 'p4', hole: 1, grossScore: 5),
          2: HoleScore(playerId: 'p4', hole: 2, grossScore: 6),
          3: HoleScore(playerId: 'p4', hole: 3, grossScore: 4),
          4: HoleScore(playerId: 'p4', hole: 4, grossScore: 5),
          5: HoleScore(playerId: 'p4', hole: 5, grossScore: 4),
          6: HoleScore(playerId: 'p4', hole: 6, grossScore: 4),
          7: HoleScore(playerId: 'p4', hole: 7, grossScore: 5),
          8: HoleScore(playerId: 'p4', hole: 8, grossScore: 6),
          9: HoleScore(playerId: 'p4', hole: 9, grossScore: 5),
        },
      };

      // Equipos: Team Eagles (Carlos + Alan) vs Team Birdies (Samuel + Guillermo)
      sideA = const BetSide(
        id: 'side_a',
        name: 'Team Eagles',
        playerIds: ['p1', 'p2'],
      );

      sideB = const BetSide(
        id: 'side_b',
        name: 'Team Birdies',
        playerIds: ['p3', 'p4'],
      );
    });

    test('Un MATCH sobre 18 por equipos', () {
      // Era `BetModuleType.matchAutoPress`, retirado por ser un Nassau con los
      // dos nueves a cero.
      //
      // ── Y esta ronda es de NUEVE hoyos ──────────────────────────────────
      //
      // «Los dos nueves a cero y el total con el importe» es la forma de un
      // match sobre DIECIOCHO. En nueve no hay total: la vuelta única cobra por
      // `frontValue`, y un 0/0/X ahí no pagaría nada.
      //
      // No es un caso que haya que resolver — un match a nueve es un Nassau de
      // nueve, con su importe — pero se escribe aquí porque la forma no es la
      // misma y confundirlas deja una apuesta muda.
      //
      // Sin presiones: el motor de equipos no las tiene, y eso está escrito en
      // engine_team_test.
      final matchMod = BetModuleInstance(
        id: 'match_mod',
        type: BetModuleType.nassau,
        name: 'Match Team 2v2',
        participantIds: ['p1', 'p2', 'p3', 'p4'],
        status: BetModuleStatus.active,
        sides: [sideA, sideB],
        nassauConfig: const NassauConfig(
          frontValue: 10.0,
          backValue: 0,
          totalValue: 0,
          mode: GrossNetMode.net,
        ),
      );

      final group = BetGroup(
        id: 'group1',
        name: 'Grupo 2v2',
        format: PartidaFormat.oneVsOne,
        playerIds: ['p1', 'p2', 'p3', 'p4'],
        modules: [matchMod],
      );

      final round = Round(
        id: 'round1',
        name: 'Test Round - Match Team',
        course: course,
        players: players,
        roundPlayers: roundPlayers,
        betGroups: [group],
        scores: scores,
        events: {},
        oyeseRankings: {},
        sliding: [],
        createdAt: DateTime.now(),
        currentHole: 9,
        totalHoles: 9,
        isFinished: true,
      );

      final ledger = BetEngine.computeAll(round);

      print('Match por equipos:');
      for (final entry in ledger) {
        print('  ${entry.fromPlayerId} → ${entry.toPlayerId}: \$${entry.amount.toStringAsFixed(2)} (${entry.reason})');
      }

      // Verificar que el ledger tiene entradas y que el equipo ganador (p3/p4) cobra
      expect(ledger.isNotEmpty, true, reason: 'Ledger debe tener entradas');
      // Los pagos van del equipo perdedor al ganador; amount es siempre positivo
      final toP3orP4 = ledger.where((e) => e.toPlayerId == 'p3' || e.toPlayerId == 'p4').toList();
      expect(toP3orP4.isNotEmpty, true, reason: 'El equipo ganador (p3/p4) debe cobrar');
    });

    test('Nassau Team', () {
      final nassauMod = BetModuleInstance(
        id: 'nassau_mod',
        type: BetModuleType.nassau,
        name: 'Nassau Team 2v2',
        participantIds: ['p1', 'p2', 'p3', 'p4'],
        status: BetModuleStatus.active,
        sides: [sideA, sideB],
        nassauConfig: const NassauConfig(
          frontValue: 10.0,
          backValue: 10.0,
          totalValue: 10.0,
          mode: GrossNetMode.net,
        ),
      );

      final group = BetGroup(
        id: 'group1',
        name: 'Grupo 2v2',
        format: PartidaFormat.allInOnePot,
        playerIds: ['p1', 'p2', 'p3', 'p4'],
        modules: [nassauMod],
      );

      final round = Round(
        id: 'round1',
        name: 'Test Round - Nassau Team',
        course: course,
        players: players,
        roundPlayers: roundPlayers,
        betGroups: [group],
        scores: scores,
        events: {},
        oyeseRankings: {},
        sliding: [],
        createdAt: DateTime.now(),
        currentHole: 9,
        totalHoles: 9,
        isFinished: false, // Nassau live status solo funciona en rondas activas
      );

      final status = BetEngine.nassauLiveStatusTeam(round, nassauMod);

      print('🏌️ Nassau Team Live Status:');
      print('  Front: ${status.front} (played: ${status.frontPlayed})');
      print('  Back: ${status.back} (played: ${status.backPlayed})');
      print('  Total: ${status.total}');
      print('  Presses: ${status.presses.length}');

      // Verificar que el status tiene datos coherentes
      expect(status.frontPlayed, greaterThan(0), reason: 'Debe haber jugado al menos 1 hoyo');
    });

    test('Skins Team', () {
      final skinsMod = BetModuleInstance(
        id: 'skins_mod',
        type: BetModuleType.skins,
        name: 'Skins Team 2v2',
        participantIds: ['p1', 'p2', 'p3', 'p4'],
        status: BetModuleStatus.active,
        sides: [sideA, sideB],
        skinsConfig: const SkinsConfig(
          valuePerSkin: 5.0,
          mode: GrossNetMode.net,
          carryOver: true,
        ),
      );

      final group = BetGroup(
        id: 'group1',
        name: 'Grupo 2v2',
        format: PartidaFormat.allInOnePot,
        playerIds: ['p1', 'p2', 'p3', 'p4'],
        modules: [skinsMod],
      );

      final round = Round(
        id: 'round1',
        name: 'Test Round - Skins Team',
        course: course,
        players: players,
        roundPlayers: roundPlayers,
        betGroups: [group],
        scores: scores,
        events: {},
        oyeseRankings: {},
        sliding: [],
        createdAt: DateTime.now(),
        currentHole: 9,
        totalHoles: 9,
        isFinished: true,
      );

      final ledger = BetEngine.computeAll(round);

      print('🏌️ Skins Team Results:');
      for (final entry in ledger) {
        print('  ${entry.fromPlayerId} → ${entry.toPlayerId}: \$${entry.amount.toStringAsFixed(2)} (${entry.reason})');
      }

      // Verificar que hay entradas y que alguien cobró (skins no nulos)
      expect(ledger.isNotEmpty, true, reason: 'Ledger debe tener entradas de skins');
      // El total de montos positivos debe ser > 0
      final totalAmount = ledger.fold(0.0, (sum, e) => sum + e.amount);
      expect(totalAmount, greaterThan(0), reason: 'Debe haber montos positivos en el ledger');
    });

    test('Sides Validation', () {
      // Validación de lados vacíos
      expect(
        BetSide.validateDuel([]),
        'Se requieren exactamente 2 lados',
      );

      // Validación de solo 1 lado
      expect(
        BetSide.validateDuel([sideA]),
        'Se requieren exactamente 2 lados',
      );

      // Validación de lados sin jugadores
      final emptySide = const BetSide(id: 'empty', name: 'Empty', playerIds: []);
      expect(
        BetSide.validateDuel([emptySide, sideB]),
        'El lado "Empty" no tiene jugadores',
      );

      // Validación de jugador duplicado
      final duplicateSide = const BetSide(
        id: 'dup',
        name: 'Duplicate',
        playerIds: ['p1', 'p2'], // p1 ya está en sideA
      );
      expect(
        BetSide.validateDuel([sideA, duplicateSide]),
        'El jugador p1 aparece en ambos lados',
      );

      // Validación correcta
      expect(
        BetSide.validateDuel([sideA, sideB]),
        null,
        reason: 'Lados válidos deben pasar la validación',
      );
    });
  });
}
