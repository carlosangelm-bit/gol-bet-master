// =============================================================================
// BetScope — alcance declarado de una apuesta.
//
// Verifica que:
//   1. Los módulos legacy (sin scope) se comportan EXACTAMENTE igual que antes.
//   2. Un alcance `everyone` resuelve participantes contra los jugadores
//      presentes → el jugador que se suma tarde entra solo.
//   3. Los alcances fijos (pair/subset/teams) NO absorben jugadores nuevos.
//   4. La serialización va y vuelve sin perder información.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';

final _course18 = CourseInfo(
  name: '18',
  holes: List.generate(18, (i) {
    final si = (i % 9) * 2 + (i < 9 ? 1 : 2);
    return CourseHole(hole: i + 1, par: 4, strokeIndex: si);
  }),
);

BetModuleInstance _mod(
  BetModuleType type,
  List<String> pids, {
  BetScope? scope,
}) =>
    BetModuleInstance.defaultFor(type, pids).copyWith(scope: scope);

Round _round({
  required List<String> playerIds,
  required List<String> groupPlayerIds,
  required List<BetModuleInstance> modules,
  required Map<String, int> perHoleScore, // pid -> gross por hoyo
}) {
  LedgerEngine.invalidateCache();
  return Round(
    id: 't', name: 't', course: _course18,
    players: playerIds
        .map((id) => Player(id: id, name: id, handicapBase: 0))
        .toList(),
    roundPlayers: playerIds
        .map((id) => RoundPlayer(playerId: id, handicapEnRonda: 0))
        .toList(),
    betGroups: [
      BetGroup(
        id: 'g', name: 'Partida', format: PartidaFormat.allInOnePot,
        playerIds: groupPlayerIds, modules: modules,
      ),
    ],
    scores: {
      for (final e in perHoleScore.entries)
        e.key: {
          for (int h = 1; h <= 18; h++)
            h: HoleScore(playerId: e.key, hole: h, grossScore: e.value, putts: 2)
        }
    },
    events: const {}, oyeseRankings: const {},
    sliding: const [], createdAt: DateTime(2025),
  );
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  group('Retrocompatibilidad — módulos sin scope', () {
    test('S1 – participantIds poblado se infiere como alcance fijo', () {
      final m = _mod(BetModuleType.nassau, ['A', 'B', 'C']);
      expect(m.scope, isNull);
      expect(m.effectiveScope.kind, BetScopeKind.subset);
      expect(m.resolveParticipants(['A', 'B', 'C', 'D']), ['A', 'B', 'C'],
          reason: 'D no debe colarse en una apuesta con participantes fijos');
    });

    test('S2 – dos participantes se infieren como duelo', () {
      final m = _mod(BetModuleType.skins, ['A', 'B']);
      expect(m.effectiveScope.kind, BetScopeKind.pair);
      expect(m.effectiveScope.isPair, isTrue);
    });

    test('S3 – participantIds vacío sigue significando "todo el grupo"', () {
      final m = BetModuleInstance.defaultFor(BetModuleType.medal, const [])
          .copyWith(participantIds: const []);
      expect(m.effectiveScope.kind, BetScopeKind.everyone);
      expect(m.resolveParticipants(['A', 'B', 'C']), ['A', 'B', 'C']);
    });

    test('S4 – módulo con sides se infiere como equipos', () {
      final m = _mod(BetModuleType.nassau, ['A1', 'A2', 'B1', 'B2']).copyWith(
        sides: [
          BetSide(id: 's1', name: 'A', playerIds: ['A1', 'A2']),
          BetSide(id: 's2', name: 'B', playerIds: ['B1', 'B2']),
        ],
      );
      expect(m.effectiveScope.kind, BetScopeKind.teams);
      expect(m.resolveParticipants(['A1', 'A2', 'B1', 'B2', 'X']),
          ['A1', 'A2', 'B1', 'B2'],
          reason: 'X no entra en un duelo por equipos');
    });

    test('S5 – effectivePids sigue devolviendo lo mismo que antes', () {
      final fijo = _mod(BetModuleType.nassau, ['A', 'B']);
      expect(fijo.effectivePids(['A', 'B', 'C']), ['A', 'B']);

      final abierto = BetModuleInstance.defaultFor(BetModuleType.nassau, const [])
          .copyWith(participantIds: const []);
      expect(abierto.effectivePids(['A', 'B', 'C']), ['A', 'B', 'C']);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('Alcance everyone — el jugador que llega tarde entra solo', () {
    test('E1 – resolveParticipants sigue a los jugadores presentes', () {
      final m = _mod(BetModuleType.nassau, ['A', 'B'],
          scope: const BetScope.everyone());
      expect(m.resolveParticipants(['A', 'B']), ['A', 'B']);
      expect(m.resolveParticipants(['A', 'B', 'C']), ['A', 'B', 'C'],
          reason: 'C entra sin tocar la configuración del módulo');
    });

    test('E2 – el motor cobra al jugador nuevo sin reconfigurar', () {
      final nassau = _mod(
        BetModuleType.nassau, ['A', 'B'],
        scope: const BetScope.everyone(),
      ).copyWith(
        nassauConfig: const NassauConfig(
          frontValue: 100, backValue: 100, totalValue: 200,
          mode: GrossNetMode.gross,
        ),
      );

      // Antes de que entre C
      final r1 = _round(
        playerIds: ['A', 'B'], groupPlayerIds: ['A', 'B'],
        modules: [nassau],
        perHoleScore: {'A': 4, 'B': 5},
      );
      expect(LedgerEngine.playerBalances(r1)['A'], 400.0);

      // Entra C (peor que A, mejor que B) — mismo módulo, sin editar nada
      final r2 = _round(
        playerIds: ['A', 'B', 'C'], groupPlayerIds: ['A', 'B', 'C'],
        modules: [nassau],
        perHoleScore: {'A': 4, 'B': 6, 'C': 5},
      );
      final bal = LedgerEngine.playerBalances(r2);
      expect(bal.keys, containsAll(['A', 'B', 'C']));

      // C sí juega: pierde con A y gana a B. Su balance NETO es 0 justamente
      // porque ambos duelos se compensan, así que hay que mirar los duelos.
      expect(LedgerEngine.breakdownBetween(r2, 'C', 'A')[BetModuleType.nassau],
          -400.0, reason: 'C pierde los 3 segmentos con A');
      expect(LedgerEngine.breakdownBetween(r2, 'C', 'B')[BetModuleType.nassau],
          400.0, reason: 'C gana los 3 segmentos a B');

      expect(bal['A'], 800.0, reason: 'A gana los 3 segmentos a B y a C');
      expect(bal['B'], -800.0);
      expect(bal.values.reduce((a, b) => a + b), 0.0,
          reason: 'el ledger siempre cuadra a cero');
    });

    test('E3 – un alcance fijo NO absorbe al jugador nuevo', () {
      final duelo = _mod(BetModuleType.nassau, ['A', 'B'],
              scope: BetScope.pair('A', 'B'))
          .copyWith(
        nassauConfig: const NassauConfig(
          frontValue: 100, backValue: 100, totalValue: 200,
          mode: GrossNetMode.gross,
        ),
      );
      final r = _round(
        playerIds: ['A', 'B', 'C'], groupPlayerIds: ['A', 'B', 'C'],
        modules: [duelo],
        perHoleScore: {'A': 4, 'B': 6, 'C': 5},
      );
      final bal = LedgerEngine.playerBalances(r);
      expect(bal['C'], 0.0,
          reason: 'C no fue parte del duelo acordado entre A y B');
      expect(bal['A'], 400.0);
    });

    test('E4 – convivencia: una apuesta abierta y un duelo fijo a la vez', () {
      final abierta = _mod(BetModuleType.nassau, ['A', 'B'],
              scope: const BetScope.everyone())
          .copyWith(
        nassauConfig: const NassauConfig(
          frontValue: 100, backValue: 100, totalValue: 200,
          mode: GrossNetMode.gross,
        ),
      );
      final duelo = _mod(BetModuleType.medal, ['A', 'B'],
              scope: BetScope.pair('A', 'B'))
          .copyWith(medalConfig: const MedalConfig(value: 50, mode: GrossNetMode.gross));

      final r = _round(
        playerIds: ['A', 'B', 'C'], groupPlayerIds: ['A', 'B', 'C'],
        modules: [abierta, duelo],
        perHoleScore: {'A': 4, 'B': 6, 'C': 5},
      );
      final bd = LedgerEngine.breakdownBetween(r, 'A', 'C');
      expect(bd[BetModuleType.nassau], isNotNull,
          reason: 'la apuesta abierta sí alcanza a C');
      expect(bd[BetModuleType.medal], isNull,
          reason: 'el Medal era un duelo cerrado A-B');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('Serialización', () {
    test('J1 – ida y vuelta conserva el alcance', () {
      for (final scope in <BetScope>[
        const BetScope.everyone(),
        const BetScope.teams(),
        const BetScope.subset(['A', 'B', 'C']),
        BetScope.pair('A', 'B'),
      ]) {
        final m = _mod(BetModuleType.skins, ['A', 'B'], scope: scope);
        final back = BetModuleInstance.fromJson(m.toJson());
        expect(back.scope, scope, reason: 'roundtrip de ${scope.kind.name}');
      }
    });

    test('J2 – un módulo sin scope no escribe la clave', () {
      final m = _mod(BetModuleType.skins, ['A', 'B']);
      expect(m.toJson().containsKey('scope'), isFalse,
          reason: 'no ensuciar el JSON de rondas que no declaran alcance');
    });

    test('J3 – JSON legacy (sin scope) deserializa a scope null', () {
      final json = _mod(BetModuleType.skins, ['A', 'B']).toJson();
      final back = BetModuleInstance.fromJson(json);
      expect(back.scope, isNull);
      expect(back.effectiveScope.kind, BetScopeKind.pair,
          reason: 'se infiere, no se persiste');
    });

    test('J4 – un scope corrupto cae a subset sin lanzar', () {
      final back = BetScope.fromJson({'kind': 'basura', 'playerIds': ['A']});
      expect(back.kind, BetScopeKind.subset);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('Robustez de resolveParticipants', () {
    test('R1 – filtra jugadores que ya no están en la partida', () {
      final m = _mod(BetModuleType.nassau, ['A', 'B', 'C'],
          scope: const BetScope.subset(['A', 'B', 'C']));
      expect(m.resolveParticipants(['A', 'B']), ['A', 'B'],
          reason: 'C salió de la partida');
    });

    test('R2 – si el filtro dejaría menos de 2, devuelve la lista original', () {
      // Protege rondas cuyo BetGroup.playerIds no esté bien poblado: sin esta
      // salvaguarda la apuesta desaparecería en vez de liquidarse.
      final m = _mod(BetModuleType.nassau, ['A', 'B'],
          scope: BetScope.pair('A', 'B'));
      expect(m.resolveParticipants(['A']), ['A', 'B']);
      expect(m.resolveParticipants([]), ['A', 'B']);
    });

    test('R3 – containsPair respeta el alcance abierto', () {
      final abierta = _mod(BetModuleType.nassau, ['A', 'B'],
          scope: const BetScope.everyone());
      expect(abierta.containsPair('A', 'Z'), isTrue,
          reason: 'con alcance abierto aplica a cualquier par presente');

      final fija = _mod(BetModuleType.nassau, ['A', 'B'],
          scope: BetScope.pair('A', 'B'));
      expect(fija.containsPair('A', 'Z'), isFalse);
    });
  });
}
