// =============================================================================
// Lógica que respalda los remates de UI del alcance:
//   • _isOpenable / openableBetsCount / openAllWholeGroupBets
//   • addPlayerToGroupBets
//   • detección de jugadores fuera de las apuestas
//
// Se prueba la LÓGICA, no los widgets: es donde está el riesgo de cobrar mal.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';
import 'package:golf_bet_master/providers/round_provider.dart';

final _course18 = CourseInfo(
  name: '18',
  holes: List.generate(18, (i) {
    final si = (i % 9) * 2 + (i < 9 ? 1 : 2);
    return CourseHole(hole: i + 1, par: 4, strokeIndex: si);
  }),
);

BetModuleInstance _nassau(List<String> pids, {BetScope? scope}) =>
    BetModuleInstance.defaultFor(BetModuleType.nassau, pids).copyWith(
      scope: scope,
      nassauConfig: const NassauConfig(
        frontValue: 100, backValue: 100, totalValue: 200,
        mode: GrossNetMode.gross,
      ),
    );

Round _round({
  required List<String> roundPlayerIds,
  required List<BetGroup> groups,
  Map<String, int> perHole = const {},
}) {
  LedgerEngine.invalidateCache();
  return Round(
    id: 'r', name: 'Ronda', course: _course18,
    players: roundPlayerIds
        .map((id) => Player(id: id, name: id, handicapBase: 0))
        .toList(),
    roundPlayers: roundPlayerIds
        .map((id) => RoundPlayer(playerId: id, handicapEnRonda: 0))
        .toList(),
    betGroups: groups,
    scores: {
      for (final id in roundPlayerIds)
        id: {
          for (int h = 1; h <= 18; h++)
            h: HoleScore(
                playerId: id, hole: h,
                grossScore: perHole[id] ?? 4, putts: 2)
        }
    },
    events: const {}, oyeseRankings: const {},
    sliding: const [], createdAt: DateTime(2025),
  );
}

/// Provider con una ronda cargada, sin tocar Firestore (uid == null).
Future<RoundProvider> _provWith(Round r) async {
  SharedPreferences.setMockInitialValues({});
  final p = RoundProvider();
  p.startRound(r);
  return p;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════════
  group('openableBetsCount — qué apuestas se pueden abrir', () {
    test('O1 – una apuesta que cubre toda la partida es abrible', () async {
      final r = _round(
        roundPlayerIds: ['A', 'B', 'C'],
        groups: [
          BetGroup(
            id: 'g', name: 'Partida', format: PartidaFormat.allInOnePot,
            playerIds: ['A', 'B', 'C'],
            modules: [_nassau(['A', 'B', 'C'])], // sin scope → legacy fijo
          ),
        ],
      );
      final p = await _provWith(r);
      expect(p.openableBetsCount, 1);
    });

    test('O2 – un duelo suelto NO es abrible', () async {
      final r = _round(
        roundPlayerIds: ['A', 'B', 'C'],
        groups: [
          BetGroup(
            id: 'g', name: 'Partida', format: PartidaFormat.allInOnePot,
            playerIds: ['A', 'B', 'C'],
            modules: [_nassau(['A', 'B'])], // solo 2 de 3
          ),
        ],
      );
      final p = await _provWith(r);
      expect(p.openableBetsCount, 0,
          reason: 'abrir un duelo A-B a toda la partida cambiaría el acuerdo');
    });

    test('O3 – una apuesta ya abierta no se cuenta', () async {
      final r = _round(
        roundPlayerIds: ['A', 'B'],
        groups: [
          BetGroup(
            id: 'g', name: 'Partida', format: PartidaFormat.allInOnePot,
            playerIds: ['A', 'B'],
            modules: [_nassau(['A', 'B'], scope: const BetScope.everyone())],
          ),
        ],
      );
      final p = await _provWith(r);
      expect(p.openableBetsCount, 0);
    });

    test('O4 – un módulo de equipos nunca es abrible', () async {
      final mod = _nassau(['A1', 'A2', 'B1', 'B2']).copyWith(
        sides: [
          BetSide(id: 's1', name: 'A', playerIds: ['A1', 'A2']),
          BetSide(id: 's2', name: 'B', playerIds: ['B1', 'B2']),
        ],
      );
      final r = _round(
        roundPlayerIds: ['A1', 'A2', 'B1', 'B2'],
        groups: [
          BetGroup(
            id: 'g', name: 'Partida', format: PartidaFormat.teams2v2,
            playerIds: ['A1', 'A2', 'B1', 'B2'], modules: [mod],
          ),
        ],
      );
      final p = await _provWith(r);
      expect(p.openableBetsCount, 0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('openAllWholeGroupBets — abrir no cambia el dinero de hoy', () {
    test('OA1 – los balances son idénticos antes y después de abrir', () async {
      final r = _round(
        roundPlayerIds: ['A', 'B', 'C'],
        groups: [
          BetGroup(
            id: 'g', name: 'Partida', format: PartidaFormat.allInOnePot,
            playerIds: ['A', 'B', 'C'],
            modules: [_nassau(['A', 'B', 'C'])],
          ),
        ],
        perHole: {'A': 4, 'B': 5, 'C': 6},
      );
      final p = await _provWith(r);

      final antes = LedgerEngine.playerBalances(p.round!);
      expect(p.openAllWholeGroupBets(), 1);
      final despues = LedgerEngine.playerBalances(p.round!);

      expect(despues, antes,
          reason: 'abrir el alcance solo afecta a quien se sume DESPUÉS');
      expect(p.openableBetsCount, 0, reason: 'ya no queda nada por abrir');
    });

    test('OA2 – tras abrir, el módulo tiene alcance everyone', () async {
      final r = _round(
        roundPlayerIds: ['A', 'B'],
        groups: [
          BetGroup(
            id: 'g', name: 'Partida', format: PartidaFormat.allInOnePot,
            playerIds: ['A', 'B'], modules: [_nassau(['A', 'B'])],
          ),
        ],
      );
      final p = await _provWith(r);
      p.openAllWholeGroupBets();
      expect(p.round!.betGroups.first.modules.first.effectiveScope.isEveryone,
          isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('addPlayerToGroupBets — el jugador que llega tarde', () {
    Round baseRound({required bool abierta}) => _round(
          roundPlayerIds: ['A', 'B', 'C'], // C está en la ronda…
          groups: [
            BetGroup(
              id: 'g', name: 'Partida', format: PartidaFormat.allInOnePot,
              playerIds: ['A', 'B'], // …pero NO en la partida de apuestas
              modules: [
                _nassau(['A', 'B'],
                    scope: abierta ? const BetScope.everyone() : null),
              ],
            ),
          ],
          perHole: {'A': 4, 'B': 6, 'C': 5},
        );

    test('P1 – con apuesta abierta, entra y el motor le cobra', () async {
      final p = await _provWith(baseRound(abierta: true));

      expect(LedgerEngine.breakdownBetween(p.round!, 'C', 'A'), isEmpty,
          reason: 'antes de añadirlo no juega nada');

      final n = p.addPlayerToGroupBets('C', 'g');
      expect(n, 1, reason: '1 apuesta de alcance abierto lo incluye');

      expect(p.round!.betGroups.first.playerIds, containsAll(['A', 'B', 'C']));
      expect(LedgerEngine.breakdownBetween(p.round!, 'C', 'A')[BetModuleType.nassau],
          -400.0, reason: 'C pierde los 3 segmentos con A');
      expect(LedgerEngine.breakdownBetween(p.round!, 'C', 'B')[BetModuleType.nassau],
          400.0, reason: 'C gana los 3 segmentos a B');
    });

    test('P2 – con apuesta fija, se añade pero avisa que no lo incluye', () async {
      final p = await _provWith(baseRound(abierta: false));
      final n = p.addPlayerToGroupBets('C', 'g');
      expect(n, 0,
          reason: 'devuelve 0 para que la UI avise en vez de fingir que entró');
      expect(p.round!.betGroups.first.playerIds, contains('C'),
          reason: 'sí se añade a la partida, aunque no herede apuestas');
      expect(LedgerEngine.breakdownBetween(p.round!, 'C', 'A'), isEmpty);
    });

    test('P3 – grupo inexistente no rompe nada', () async {
      final p = await _provWith(baseRound(abierta: true));
      expect(p.addPlayerToGroupBets('C', 'no-existe'), 0);
      expect(p.round!.betGroups.first.playerIds, ['A', 'B']);
    });

    test('P4 – añadir dos veces es idempotente', () async {
      final p = await _provWith(baseRound(abierta: true));
      p.addPlayerToGroupBets('C', 'g');
      final antes = LedgerEngine.playerBalances(p.round!);
      p.addPlayerToGroupBets('C', 'g');
      expect(p.round!.betGroups.first.playerIds.where((i) => i == 'C').length, 1,
          reason: 'no debe duplicarse en la partida');
      expect(LedgerEngine.playerBalances(p.round!), antes);
    });

    test('P5 – se le crean scores, eventos y RoundPlayer', () async {
      final r = _round(
        roundPlayerIds: ['A', 'B'],
        groups: [
          BetGroup(
            id: 'g', name: 'Partida', format: PartidaFormat.allInOnePot,
            playerIds: ['A', 'B'],
            modules: [_nassau(['A', 'B'], scope: const BetScope.everyone())],
          ),
        ],
      );
      // Jugador nuevo que ni siquiera tenía contenedores
      final conNuevo = r.copyWith(
        players: [...r.players, Player(id: 'Z', name: 'Z', handicapBase: 12)],
      );
      final p = await _provWith(conNuevo);
      p.addPlayerToGroupBets('Z', 'g');

      expect(p.round!.scores.containsKey('Z'), isTrue);
      expect(p.round!.events.containsKey('Z'), isTrue);
      expect(p.round!.roundPlayers.any((rp) => rp.playerId == 'Z'), isTrue);
      expect(
          p.round!.roundPlayers
              .firstWhere((rp) => rp.playerId == 'Z')
              .handicapEnRonda,
          12.0,
          reason: 'toma el handicap base del jugador');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('Serialización tras abrir el alcance', () {
    test('S1 – el alcance abierto sobrevive a un guardado/carga', () {
      final mod = _nassau(['A', 'B'], scope: const BetScope.everyone());
      final r = _round(
        roundPlayerIds: ['A', 'B'],
        groups: [
          BetGroup(
            id: 'g', name: 'Partida', format: PartidaFormat.allInOnePot,
            playerIds: ['A', 'B'], modules: [mod],
          ),
        ],
      );
      final back = roundFromJson(roundToJson(r));
      expect(back.betGroups.first.modules.first.effectiveScope.isEveryone,
          isTrue);
    });
  });
}
