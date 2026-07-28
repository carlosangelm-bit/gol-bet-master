// =============================================================================
// MÓDULO DE EQUIPOS — semántica de pago y best ball.
//
// Módulo nunca validado en juego real. Al probarlo en Chrome salieron:
//   • Scramble no cobraba NADA (sides con IDs reales que no capturan score)
//   • tres leyes de escalado distintas: Nassau ×n², Skins ×n, Match ×n²
//   • un compañero que levanta la bola anulaba el hoyo
//
// REGLA ACORDADA: un duelo por equipos se comporta como un jugador contra
// otro. Un Nassau F$50/B$50/T$100 mueve 50, 50 y 100 — no más.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/game_engine.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';

final _course = CourseInfo(
  name: '18',
  holes: List.generate(18, (i) =>
      CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)),
);

List<BetSide> _sides(List<String> a, List<String> b,
        {TeamPlayMode mode = TeamPlayMode.bestBall}) =>
    [
      BetSide(id: 'sA', name: 'Equipo A', playerIds: a, playMode: mode),
      BetSide(id: 'sB', name: 'Equipo B', playerIds: b, playMode: mode),
    ];

/// Ronda donde el lado A gana todos los hoyos, salvo los `sinScore` indicados.
Round _round({
  required List<String> a,
  required List<String> b,
  required BetModuleInstance mod,
  int holes = 18,
  Set<(String, int)> sinScore = const {},
}) {
  final ids = [...a, ...b];
  LedgerEngine.invalidateCache();
  return Round(
    id: 't', name: 't', course: _course,
    players: ids.map((i) => Player(id: i, name: i, handicapBase: 0)).toList(),
    roundPlayers:
        ids.map((i) => RoundPlayer(playerId: i, handicapEnRonda: 0)).toList(),
    betGroups: [
      BetGroup(
        id: 'g', name: 'Partida', format: PartidaFormat.teams2v2,
        playerIds: ids, modules: [mod],
      )
    ],
    scores: {
      for (final i in ids)
        i: {
          for (int h = 1; h <= holes; h++)
            if (!sinScore.contains((i, h)))
              h: HoleScore(
                  playerId: i, hole: h,
                  grossScore: a.contains(i) ? 4 : 5, putts: 2)
        }
    },
    events: const {}, oyeseRankings: const {},
    sliding: const [], createdAt: DateTime(2025), totalHoles: holes,
  );
}

BetModuleInstance _nassau(List<String> a, List<String> b,
        {TeamPlayMode mode = TeamPlayMode.bestBall}) =>
    BetModuleInstance.defaultFor(BetModuleType.nassau, [...a, ...b]).copyWith(
      sides: _sides(a, b, mode: mode),
      nassauConfig: const NassauConfig(
          frontValue: 50, backValue: 50, totalValue: 100,
          mode: GrossNetMode.gross),
    );

/// Suma de todos los balances positivos = dinero total que cambió de manos.
double _totalMovido(Round r) => LedgerEngine.playerBalances(r)
    .values
    .where((v) => v > 0)
    .fold(0.0, (s, v) => s + v);

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  group('El equipo se comporta como un jugador', () {
    test('P1 – Nassau 2v2 de 9 hoyos: un segmento de \$50 mueve \$50', () {
      final r = _round(
        a: ['A0', 'A1'], b: ['B0', 'B1'],
        mod: _nassau(['A0', 'A1'], ['B0', 'B1']), holes: 9,
      );
      expect(_totalMovido(r), 50.0,
          reason: 'ronda de 9 hoyos → un único segmento de \$50');
      final bal = LedgerEngine.playerBalances(r);
      expect(bal['A0'], 25.0, reason: '\$50 repartidos entre los 2 del equipo');
      expect(bal['B0'], -25.0);
    });

    test('P2 – Nassau 2v2 de 18 hoyos: 50 + 50 + 100 = \$200', () {
      final r = _round(
        a: ['A0', 'A1'], b: ['B0', 'B1'],
        mod: _nassau(['A0', 'A1'], ['B0', 'B1']),
      );
      expect(_totalMovido(r), 200.0);
      expect(LedgerEngine.playerBalances(r)['A0'], 100.0);
    });

    test('P3 – el importe NO depende del tamaño del equipo (3v3)', () {
      final a = ['A0', 'A1', 'A2'], b = ['B0', 'B1', 'B2'];
      final r = _round(a: a, b: b, mod: _nassau(a, b), holes: 9);
      expect(_totalMovido(r), closeTo(50.0, 0.05),
          reason: 'un 3v3 mueve lo mismo que un 2v2: la apuesta es del equipo');
      expect(LedgerEngine.playerBalances(r)['A0'], closeTo(16.67, 0.01));
    });

    test('P4 – equipos de distinto tamaño (2 vs 3) reparten bien', () {
      final a = ['A0', 'A1'], b = ['B0', 'B1', 'B2'];
      final r = _round(a: a, b: b, mod: _nassau(a, b), holes: 9);
      expect(_totalMovido(r), closeTo(50.0, 0.05));
      final bal = LedgerEngine.playerBalances(r);
      expect(bal['A0'], closeTo(25.0, 0.01), reason: '50 / 2 ganadores');
      expect(bal['B0'], closeTo(-16.67, 0.01), reason: '50 / 3 perdedores');
    });

    test('P5 – Skins equipo: 18 skins de \$10 mueven \$180, no \$360', () {
      final a = ['A0', 'A1'], b = ['B0', 'B1'];
      final mod = BetModuleInstance.defaultFor(BetModuleType.skins, [...a, ...b])
          .copyWith(
        sides: _sides(a, b),
        skinsConfig: const SkinsConfig(
            valuePerSkin: 10, carryOver: false, mode: GrossNetMode.gross),
      );
      final r = _round(a: a, b: b, mod: mod);
      expect(_totalMovido(r), 180.0);
      expect(LedgerEngine.playerBalances(r)['A0'], 90.0);
    });

    test('P6 – Match+Press equipo escala igual que Nassau', () {
      final a2 = ['A0', 'A1'], b2 = ['B0', 'B1'];
      final a3 = ['A0', 'A1', 'A2'], b3 = ['B0', 'B1', 'B2'];
      BetModuleInstance mk(List<String> a, List<String> b) =>
          BetModuleInstance.defaultFor(
                  BetModuleType.matchAutoPress, [...a, ...b])
              .copyWith(sides: _sides(a, b));

      final t2 = _totalMovido(_round(a: a2, b: b2, mod: mk(a2, b2)));
      final t3 = _totalMovido(_round(a: a3, b: b3, mod: mk(a3, b3)));
      expect(t3, closeTo(t2, 0.05),
          reason: 'el total no debe depender del tamaño del equipo');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('Best Ball con bola levantada', () {
    test('B1 – un compañero sin score no anula el hoyo', () {
      final a = ['A0', 'A1'], b = ['B0', 'B1'];
      // A1 levanta la bola en TODOS los hoyos; A0 juega y gana
      final r = _round(
        a: a, b: b, mod: _nassau(a, b), holes: 9,
        sinScore: {for (int h = 1; h <= 9; h++) ('A1', h)},
      );
      expect(_totalMovido(r), 50.0,
          reason: 'la mejor bola de A (la de A0) gana igual');
    });

    test('B2 – si NADIE del lado anota, no se liquida nada', () {
      final a = ['A0', 'A1'], b = ['B0', 'B1'];
      final r = _round(
        a: a, b: b, mod: _nassau(a, b), holes: 9,
        sinScore: {
          for (int h = 1; h <= 9; h++) ...{('A0', h), ('A1', h)}
        },
      );
      expect(LedgerEngine.entriesOf(r), isEmpty,
          reason: 'el lado A no jugó ningún hoyo');
    });

    test('B3 – bola levantada en un hoyo suelto no cambia el resultado', () {
      final a = ['A0', 'A1'], b = ['B0', 'B1'];
      final completo = _round(a: a, b: b, mod: _nassau(a, b), holes: 9);
      final conPickUp = _round(
        a: a, b: b, mod: _nassau(a, b), holes: 9,
        sinScore: {('A1', 5)},
      );
      expect(LedgerEngine.playerBalances(conPickUp),
          LedgerEngine.playerBalances(completo));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('Scramble', () {
    test('S1 – un side de Scramble con el jugador virtual SÍ cobra', () {
      // Tal y como lo deja el Setup arreglado: el side contiene el virtual,
      // que es quien captura el score del equipo.
      const vA = 'team_sA', vB = 'team_sB';
      final mod = BetModuleInstance.defaultFor(BetModuleType.nassau, [vA, vB])
          .copyWith(
        participantIds: const [vA, vB],
        sides: [
          BetSide(id: 'sA', name: 'Equipo A', playerIds: const [vA],
              playMode: TeamPlayMode.scramble),
          BetSide(id: 'sB', name: 'Equipo B', playerIds: const [vB],
              playMode: TeamPlayMode.scramble),
        ],
        nassauConfig: const NassauConfig(
            frontValue: 50, backValue: 50, totalValue: 100,
            mode: GrossNetMode.gross),
      );
      final r = _round(a: const [vA], b: const [vB], mod: mod, holes: 9);

      expect(LedgerEngine.entriesOf(r), isNotEmpty,
          reason: 'antes el Scramble no cobraba absolutamente nada');
      expect(_totalMovido(r), 50.0);
      expect(LedgerEngine.playerBalances(r)[vA], 50.0,
          reason: 'el equipo es un único jugador: se lleva los \$50 enteros');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('teamCrossAmount', () {
    test('X1 – reparte el valor entre todos los cruces', () {
      expect(BetEngine.teamCrossAmount(50, 2, 2), 12.5);
      expect(BetEngine.teamCrossAmount(50, 1, 1), 50.0);
      expect(BetEngine.teamCrossAmount(50, 2, 3), closeTo(8.333, 0.001));
    });

    test('X2 – lado vacío no revienta', () {
      expect(BetEngine.teamCrossAmount(50, 0, 2), 0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Allowance de handicap (WHS paso 2)
  // ═══════════════════════════════════════════════════════════════════════════
  group('TeamHandicapConfig — allowance', () {
    /// Ronda 2v2 en NETO con handicaps dispares.
    Round netRound(TeamHandicapConfig? cfg) {
      final a = ['A0', 'A1'], b = ['B0', 'B1'];
      final hcps = {'A0': 0.0, 'A1': 4.0, 'B0': 10.0, 'B1': 20.0};
      final mod = BetModuleInstance.defaultFor(BetModuleType.nassau, [...a, ...b])
          .copyWith(
        sides: _sides(a, b),
        teamHandicapConfig: cfg,
        nassauConfig: const NassauConfig(
            frontValue: 50, backValue: 50, totalValue: 100,
            mode: GrossNetMode.net),
      );
      final ids = [...a, ...b];
      LedgerEngine.invalidateCache();
      return Round(
        id: 't', name: 't', course: _course,
        players: ids.map((i) => Player(id: i, name: i, handicapBase: hcps[i]!)).toList(),
        roundPlayers:
            ids.map((i) => RoundPlayer(playerId: i, handicapEnRonda: hcps[i]!)).toList(),
        betGroups: [
          BetGroup(id: 'g', name: 'P', format: PartidaFormat.teams2v2,
              playerIds: ids, modules: [mod])
        ],
        scores: {
          for (final i in ids)
            i: {
              for (int h = 1; h <= 18; h++)
                h: HoleScore(playerId: i, hole: h, grossScore: 5, putts: 2)
            }
        },
        events: const {}, oyeseRankings: const {},
        sliding: const [], createdAt: DateTime(2025),
      );
    }

    test('H1 – sin config declarada se mantiene el comportamiento previo', () {
      final legacy = GameEngine.buildTeamHcpMap(
          netRound(null), ['A0', 'A1', 'B0', 'B1']);
      expect(legacy['A0'], 0.0, reason: 'el más bajo es scratch');
      expect(legacy['B1'], 20.0, reason: '100% del handicap, como hasta ahora');
    });

    test('H2 – al 90% (WHS Four-Ball) los golpes se reducen', () {
      final r = netRound(TeamHandicapConfig.fourBall);
      final m = GameEngine.buildTeamHcpMap(
          r, ['A0', 'A1', 'B0', 'B1'], cfg: TeamHandicapConfig.fourBall);
      expect(m['A0'], 0.0);
      expect(m['A1'], closeTo(3.6, 0.001), reason: '4 × 0.90');
      expect(m['B0'], closeTo(9.0, 0.001), reason: '10 × 0.90');
      expect(m['B1'], closeTo(18.0, 0.001), reason: '20 × 0.90');
    });

    test('H3 – al 75% se reducen más', () {
      final cfg = const TeamHandicapConfig(allowance: 0.75);
      final m = GameEngine.buildTeamHcpMap(
          netRound(cfg), ['A0', 'A1', 'B0', 'B1'], cfg: cfg);
      expect(m['B1'], closeTo(15.0, 0.001), reason: '20 × 0.75');
    });

    test('H4 – el jugador de menor handicap siempre es scratch', () {
      for (final a in [0.5, 0.75, 0.9, 1.0]) {
        final cfg = TeamHandicapConfig(allowance: a);
        final m = GameEngine.buildTeamHcpMap(
            netRound(cfg), ['A0', 'A1', 'B0', 'B1'], cfg: cfg);
        expect(m['A0'], 0.0, reason: 'allowance $a');
      }
    });

    test('H5 – el allowance cambia quién gana y por tanto el dinero', () {
      // Escenario diseñado para que el allowance VOLTEE el resultado:
      //   A0/A1/B0 scratch, B1 con HCP 18. Gross: A=4, B=5 en los 18 hoyos.
      //     · al 100% → B1 recibe 1 golpe en CADA hoyo → neta 4 → empate
      //                 en todos → nadie cobra.
      //     · al  50% → B1 solo recibe en SI 1-9 → A gana los 9 restantes.
      Round r(double allowance) {
        final a = ['A0', 'A1'], b = ['B0', 'B1'];
        final hcps = {'A0': 0.0, 'A1': 0.0, 'B0': 0.0, 'B1': 18.0};
        final mod = BetModuleInstance.defaultFor(
                BetModuleType.nassau, [...a, ...b])
            .copyWith(
          sides: _sides(a, b),
          teamHandicapConfig: TeamHandicapConfig(allowance: allowance),
          nassauConfig: const NassauConfig(
              frontValue: 50, backValue: 50, totalValue: 100,
              mode: GrossNetMode.net),
        );
        final ids = [...a, ...b];
        LedgerEngine.invalidateCache();
        return Round(
          id: 't', name: 't', course: _course,
          players: ids
              .map((i) => Player(id: i, name: i, handicapBase: hcps[i]!))
              .toList(),
          roundPlayers: ids
              .map((i) => RoundPlayer(playerId: i, handicapEnRonda: hcps[i]!))
              .toList(),
          betGroups: [
            BetGroup(id: 'g', name: 'P', format: PartidaFormat.teams2v2,
                playerIds: ids, modules: [mod])
          ],
          scores: {
            for (final i in ids)
              i: {
                for (int h = 1; h <= 18; h++)
                  h: HoleScore(
                      playerId: i, hole: h,
                      grossScore: i.startsWith('A') ? 4 : 5, putts: 2)
              }
          },
          events: const {}, oyeseRankings: const {},
          sliding: const [], createdAt: DateTime(2025),
        );
      }

      expect(LedgerEngine.entriesOf(r(1.0)), isEmpty,
          reason: 'al 100% B1 iguala todos los hoyos → nadie cobra');
      expect(_totalMovido(r(0.5)), greaterThan(0),
          reason: 'al 50% el equipo A gana el Back y el Total');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('TeamHandicapConfig — handicap combinado', () {
    test('C1 – Scramble reproduce el clásico 35% bajo + 15% alto', () {
      // combinedHandicap NO aplica allowance; el motor lo hace después.
      final combinado = TeamHandicapConfig.scramble.combinedHandicap([10, 20]);
      expect(combinado, closeTo(10 * 0.7 + 20 * 0.3, 0.001));
      // Con el allowance del preset (50%) sale el 35/15 de toda la vida
      final conAllowance = combinado * TeamHandicapConfig.scramble.allowance;
      expect(conAllowance, closeTo(10 * 0.35 + 20 * 0.15, 0.001));
    });

    test('C2 – Foursomes = 50% de la suma', () {
      final c = TeamHandicapConfig.foursomes;
      final v = c.combinedHandicap([10, 20]) * c.allowance;
      expect(v, closeTo(15.0, 0.001), reason: '(10+20) × 0.5');
    });

    test('C3 – Chapman = 60% del bajo + 40% del alto', () {
      final c = TeamHandicapConfig.chapman;
      final v = c.combinedHandicap([10, 20]) * c.allowance;
      expect(v, closeTo(10 * 0.6 + 20 * 0.4, 0.001));
    });

    test('C4 – el orden de los handicaps no importa', () {
      final c = TeamHandicapConfig.chapman;
      expect(c.combinedHandicap([20, 10]), c.combinedHandicap([10, 20]));
    });

    test('C5 – con 3+ jugadores reparte de forma decreciente', () {
      final c = TeamHandicapConfig.scramble;
      final v = c.combinedHandicap([5, 10, 15, 20]);
      expect(v, greaterThan(5.0), reason: 'no es solo el mejor');
      expect(v, lessThan(12.5), reason: 'pesa más el mejor que la media');
    });

    test('C6 – un solo jugador devuelve su propio handicap', () {
      expect(TeamHandicapConfig.scramble.combinedHandicap([12]), 12.0);
      expect(TeamHandicapConfig.scramble.combinedHandicap([]), 0.0);
    });

    test('C7 – defaultFor elige el preset según el modo de juego', () {
      expect(TeamHandicapConfig.defaultFor(TeamPlayMode.scramble),
          TeamHandicapConfig.scramble);
      expect(TeamHandicapConfig.defaultFor(TeamPlayMode.bestBall),
          TeamHandicapConfig.fourBall);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('Serialización de TeamHandicapConfig', () {
    test('J1 – ida y vuelta conserva los tres campos', () {
      for (final c in [
        TeamHandicapConfig.fourBall,
        TeamHandicapConfig.scramble,
        TeamHandicapConfig.foursomes,
        const TeamHandicapConfig(allowance: 0.85, lowWeight: 0.65),
      ]) {
        expect(TeamHandicapConfig.fromJson(c.toJson()), c);
      }
    });

    test('J2 – un módulo sin la clave deserializa a legacy 100%', () {
      final m = BetModuleInstance.defaultFor(BetModuleType.nassau, ['A', 'B']);
      expect(m.toJson().containsKey('teamHandicapConfig'), isFalse);
      final back = BetModuleInstance.fromJson(m.toJson());
      expect(back.teamHandicapConfig, isNull);
      expect(back.teamHandicap, TeamHandicapConfig.legacy);
      expect(back.teamHandicap.allowance, 1.0);
    });

    test('J3 – el módulo persiste la config declarada', () {
      final m = BetModuleInstance.defaultFor(BetModuleType.nassau, ['A', 'B'])
          .copyWith(teamHandicapConfig: TeamHandicapConfig.fourBall);
      final back = BetModuleInstance.fromJson(m.toJson());
      expect(back.teamHandicap, TeamHandicapConfig.fourBall);
    });
  });
}
