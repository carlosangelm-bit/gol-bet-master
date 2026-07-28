// =============================================================================
// Proyección «Reglas + Excepciones» de la pestaña Apuestas.
//
// La vista no introduce modelo nuevo: reinterpreta BetGroup.modules en dos
// listas cortas. Estos tests fijan qué acaba en cada una — es lo que decide
// si el admin ve 3 filas o 28.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/screens/bets/bets_screen.dart';

final _course = CourseInfo(
  name: '18',
  holes: List.generate(18, (i) =>
      CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)),
);

Round _round(List<BetModuleInstance> modules, List<String> groupIds) => Round(
      id: 'r', name: 'Ronda', course: _course,
      players: groupIds
          .map((i) => Player(id: i, name: i, handicapBase: 0))
          .toList(),
      roundPlayers: groupIds
          .map((i) => RoundPlayer(playerId: i, handicapEnRonda: 0))
          .toList(),
      betGroups: [
        BetGroup(
          id: 'g', name: 'Partida', format: PartidaFormat.allInOnePot,
          playerIds: groupIds, modules: modules,
        )
      ],
      scores: {for (final i in groupIds) i: {}},
      events: const {}, oyeseRankings: const {},
      sliding: const [], createdAt: DateTime(2025),
    );

BetModuleInstance _mod(
  BetModuleType type,
  List<String> pids, {
  BetScope? scope,
  Map<String, Map<String, dynamic>>? overrides,
}) =>
    BetModuleInstance.defaultFor(type, pids)
        .copyWith(scope: scope, pairConfigOverrides: overrides);

void main() {
  const abcd = ['A', 'B', 'C', 'D'];

  test('R1 – una apuesta de toda la partida es UNA regla, no 6 duelos', () {
    // 4 jugadores todos-vs-todos serían 6 duelos en la vista antigua.
    final r = _round([
      _mod(BetModuleType.nassau, abcd, scope: const BetScope.everyone()),
    ], abcd);

    final p = describeBetProjection(r);
    expect(p.rules, ['nassau:everyone'], reason: 'una sola fila');
    expect(p.exceptions, isEmpty);
  });

  test('R2 – varias apuestas de partida = varias reglas', () {
    final r = _round([
      _mod(BetModuleType.nassau, abcd, scope: const BetScope.everyone()),
      _mod(BetModuleType.skins,  abcd, scope: const BetScope.everyone()),
      _mod(BetModuleType.oyeses, abcd, scope: const BetScope.everyone()),
    ], abcd);

    expect(describeBetProjection(r).rules,
        ['nassau:everyone', 'skins:everyone', 'oyeses:everyone']);
  });

  test('E1 – un duelo suelto es una EXCEPCIÓN, no una regla', () {
    final r = _round([
      _mod(BetModuleType.nassau, abcd, scope: const BetScope.everyone()),
      _mod(BetModuleType.medal, ['A', 'B'], scope: BetScope.pair('A', 'B')),
    ], abcd);

    final p = describeBetProjection(r);
    expect(p.rules, ['nassau:everyone'],
        reason: 'el duelo suelto no ensucia la lista de reglas');
    expect(p.exceptions, ['medal:extraBet:A-B']);
  });

  test('E2 – un importe distinto para un par es una excepción de la regla', () {
    final pk = BetModuleInstance.pairKey('A', 'C');
    final r = _round([
      _mod(BetModuleType.skins, abcd,
          scope: const BetScope.everyone(),
          overrides: {pk: {'value': 50.0}}),
    ], abcd);

    final p = describeBetProjection(r);
    expect(p.rules, ['skins:everyone'],
        reason: 'la regla sigue siendo una sola');
    expect(p.exceptions, ['skins:differentValue:A-C']);
  });

  test('E3 – varios overrides sobre la misma regla se listan por separado', () {
    final r = _round([
      _mod(BetModuleType.skins, abcd,
          scope: const BetScope.everyone(),
          overrides: {
            BetModuleInstance.pairKey('A', 'B'): {'value': 50.0},
            BetModuleInstance.pairKey('C', 'D'): {'value': 25.0},
          }),
    ], abcd);

    final p = describeBetProjection(r);
    expect(p.rules, hasLength(1));
    expect(p.exceptions,
        containsAll(['skins:differentValue:A-B', 'skins:differentValue:C-D']));
    expect(p.exceptions, hasLength(2));
  });

  test('E4 – un override de un par que ya no está en la partida se ignora', () {
    final r = _round([
      _mod(BetModuleType.skins, abcd,
          scope: const BetScope.everyone(),
          overrides: {
            BetModuleInstance.pairKey('A', 'Z'): {'value': 50.0}, // Z no juega
          }),
    ], abcd);

    expect(describeBetProjection(r).exceptions, isEmpty,
        reason: 'no mostrar excepciones de jugadores ausentes');
  });

  test('T1 – un módulo de equipos es una regla, no una excepción', () {
    final mod = _mod(BetModuleType.nassau, abcd).copyWith(
      sides: [
        BetSide(id: 's1', name: 'A', playerIds: ['A', 'B']),
        BetSide(id: 's2', name: 'B', playerIds: ['C', 'D']),
      ],
    );
    final p = describeBetProjection(_round([mod], abcd));
    expect(p.rules, ['nassau:teams']);
    expect(p.exceptions, isEmpty);
  });

  test('L1 – módulos legacy (sin scope) se clasifican correctamente', () {
    final r = _round([
      _mod(BetModuleType.nassau, abcd),          // cubre la partida → subset
      _mod(BetModuleType.skins, ['A', 'B']),     // 2 jugadores      → pair
    ], abcd);

    final p = describeBetProjection(r);
    expect(p.rules, ['nassau:subset'],
        reason: 'un módulo legacy de toda la partida sigue siendo regla');
    expect(p.exceptions, ['skins:extraBet:A-B'],
        reason: 'un módulo legacy de 2 jugadores es un duelo suelto');
  });

  test('V1 – ronda sin apuestas: ambas listas vacías', () {
    final p = describeBetProjection(_round([], abcd).copyWith(betGroups: []));
    expect(p.rules, isEmpty);
    expect(p.exceptions, isEmpty);
  });

  // ═════════════════════════════════════════════════════════════════════════
  // Jugadores fuera de las apuestas
  //
  // Regresión encontrada probando en Chrome: en una ronda Best Ball se
  // marcaban como "fuera" los 4 jugadores reales, cuando compiten a través de
  // su equipo. Añadirlos habría creado apuestas individuales encima de la
  // apuesta de equipo.
  // ═════════════════════════════════════════════════════════════════════════
  group('Jugadores fuera de las apuestas', () {
    /// Ronda Best Ball: los reales NO están en group.playerIds; los equipos sí.
    Round bestBallRound() {
      final mod = BetModuleInstance.defaultFor(
              BetModuleType.nassau, ['teamA', 'teamB'])
          .copyWith(sides: [
        BetSide(id: 'sA', name: 'Equipo A', playerIds: ['CAM', 'CAV'],
            playMode: TeamPlayMode.bestBall),
        BetSide(id: 'sB', name: 'Equipo B', playerIds: ['AAM', 'RAFA'],
            playMode: TeamPlayMode.bestBall),
      ]);
      final reales = ['CAM', 'CAV', 'AAM', 'RAFA'];
      return Round(
        id: 'r', name: 'BB', course: _course,
        players: [
          ...reales.map((i) => Player(id: i, name: i, handicapBase: 0)),
          Player(id: 'teamA', name: 'Equipo A', handicapBase: 3,
              isVirtual: true, teamMemberIds: const ['CAM', 'CAV']),
          Player(id: 'teamB', name: 'Equipo B', handicapBase: 8,
              isVirtual: true, teamMemberIds: const ['AAM', 'RAFA']),
        ],
        roundPlayers: [
          ...reales.map((i) => RoundPlayer(playerId: i, handicapEnRonda: 0)),
          RoundPlayer(playerId: 'teamA', handicapEnRonda: 3),
          RoundPlayer(playerId: 'teamB', handicapEnRonda: 8),
        ],
        betGroups: [
          BetGroup(
            id: 'g', name: 'Partida', format: PartidaFormat.teams2v2,
            playerIds: const ['teamA', 'teamB'], modules: [mod],
          )
        ],
        scores: {for (final i in [...reales, 'teamA', 'teamB']) i: {}},
        events: const {}, oyeseRankings: const {},
        sliding: const [], createdAt: DateTime(2025),
      );
    }

    test('O1 – en Best Ball nadie está "fuera"', () {
      expect(playersOutsideBetsForTest(bestBallRound()), isEmpty,
          reason: 'los reales compiten a través de su lado; los equipos '
                  'virtuales SÍ están en la partida');
    });

    test('O2 – un jugador realmente suelto sí se detecta', () {
      final base = bestBallRound();
      final r = base.copyWith(
        players: [...base.players, Player(id: 'Z', name: 'Zoe', handicapBase: 5)],
        scores: {...base.scores, 'Z': {}},
      );
      expect(playersOutsideBetsForTest(r), ['Z'],
          reason: 'Z no está en la partida ni en ningún equipo');
    });

    test('O3 – ronda individual: quien no está en la partida se detecta', () {
      final r = Round(
        id: 'r', name: 'Ind', course: _course,
        players: ['A', 'B', 'C']
            .map((i) => Player(id: i, name: i, handicapBase: 0)).toList(),
        roundPlayers: ['A', 'B', 'C']
            .map((i) => RoundPlayer(playerId: i, handicapEnRonda: 0)).toList(),
        betGroups: [
          BetGroup(
            id: 'g', name: 'Partida', format: PartidaFormat.allInOnePot,
            playerIds: const ['A', 'B'],
            modules: [BetModuleInstance.defaultFor(BetModuleType.nassau, ['A', 'B'])],
          )
        ],
        scores: {for (final i in ['A', 'B', 'C']) i: {}},
        events: const {}, oyeseRankings: const {},
        sliding: const [], createdAt: DateTime(2025),
      );
      expect(playersOutsideBetsForTest(r), ['C']);
    });

    test('O4 – sin score capturado no cuenta como jugador activo', () {
      final base = bestBallRound();
      final r = base.copyWith(
        players: [...base.players, Player(id: 'Z', name: 'Zoe', handicapBase: 5)],
        // sin entrada en scores
      );
      expect(playersOutsideBetsForTest(r), isEmpty);
    });
  });
}
