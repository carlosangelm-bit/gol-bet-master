// ─────────────────────────────────────────────────────────────────────────────
// setup_teams_test.dart — la decisión de ronda tiene que LLEGAR al modelo
//
// El fallo que motiva estos tests: elegir "Por equipos" y una bola cambiaba
// qué pantallas se veían —el paso "Bola" aparecía en la barra— pero la ronda
// se creaba individual. El módulo salía sin lados y sin playMode.
//
// Es el mismo modo de fallo que el filtro de compañeros: la parte visible
// funcionando y la que resuelve el problema sin conectar. No lo encuentra un
// test de la UI ni uno del motor; lo encuentra uno que compruebe que el estado
// de la pantalla llega al objeto que se guarda.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/bet_recipe.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';

const a = ['a1', 'a2'], b = ['b1', 'b2'];

BetModuleInstance _mod(BetModuleType t) =>
    BetModuleInstance.defaultFor(t, [...a, ...b], id: 'm');

BetModuleInstance _aplicar(BetModuleType t,
        {bool equipos = true, TeamBall? bola, List<BetSide>? yaTiene}) =>
    BetRecipe.conEquiposDeRonda(
      yaTiene == null ? _mod(t) : _mod(t).copyWith(sides: yaTiene),
      porEquipos: equipos, equipoA: a, equipoB: b, bola: bola,
    );

void main() {
  group('la elección de equipos llega al módulo', () {
    test('un Nassau por equipos sale con dos lados', () {
      final m = _aplicar(BetModuleType.nassau, bola: TeamBall.mejor);
      expect(m.sides, isNotNull, reason: 'la ronda se crearía individual');
      expect(m.sides!.length, 2);
      expect(m.sides![0].playerIds, a);
      expect(m.sides![1].playerIds, b);
    });

    test('y con los participantes de ambos lados', () {
      final m = _aplicar(BetModuleType.nassau, bola: TeamBall.mejor);
      expect(m.participantIds.toSet(), {...a, ...b});
    });

    test('hasTeamSides queda en true: es lo que mira el motor', () {
      // BetEngine.computeModule enruta al motor de equipo por hasTeamSides.
      // Sin esto los lados serían decorativos.
      expect(_aplicar(BetModuleType.nassau, bola: TeamBall.mejor).hasTeamSides,
          isTrue);
    });
  });

  group('la bola llega como playMode', () {
    test('una sola bola es scramble', () {
      expect(BetRecipe.playModeDe(TeamBall.unaSola), TeamPlayMode.scramble);
      final m = _aplicar(BetModuleType.nassau, bola: TeamBall.unaSola);
      expect(m.sides!.every((s) => s.playMode == TeamPlayMode.scramble), isTrue);
    });

    test('la mejor bola es best ball', () {
      expect(BetRecipe.playModeDe(TeamBall.mejor), TeamPlayMode.bestBall);
    });

    test('la mejor y la peor también es best ball', () {
      // Cada jugador juega SU bola: hacen falta las dos para sacar la baja y
      // la alta. Lo que cambia frente a "la mejor" es cuántos puntos reparte
      // el hoyo, no cómo se juega.
      expect(BetRecipe.playModeDe(TeamBall.mejorYPeor), TeamPlayMode.bestBall);
    });

    test('sin bola elegida cae en best ball, no en un lado sin modo', () {
      final m = _aplicar(BetModuleType.nassau);
      expect(m.sides!.every((s) => s.playMode == TeamPlayMode.bestBall), isTrue);
    });
  });

  group('lo que NO debe tocar', () {
    test('en individual no pone lados', () {
      expect(_aplicar(BetModuleType.nassau, equipos: false).sides, isNull);
    });

    test('no pisa unos lados configurados a mano', () {
      // La decisión de la hoja de la apuesta es más específica que la de la
      // ronda: pisarla sería perder trabajo del usuario.
      final propios = [
        const BetSide(id: 'x', name: 'Los míos', playerIds: ['a1', 'b1']),
        const BetSide(id: 'y', name: 'Los otros', playerIds: ['a2', 'b2']),
      ];
      final m = _aplicar(BetModuleType.nassau,
          bola: TeamBall.unaSola, yaTiene: propios);
      expect(m.sides!.first.name, 'Los míos');
    });

    test('no pone lados en un conteo sin motor de equipo', () {
      // Medal, Putts, Oyes y Unidades caen al fallback individual: darles
      // lados no los haría de equipo, solo dejaría una config que miente.
      for (final t in [BetModuleType.medal, BetModuleType.putts,
                       BetModuleType.oyeses, BetModuleType.units]) {
        expect(_aplicar(t, bola: TeamBall.mejor).sides, isNull,
            reason: '${t.label} no tiene motor de equipo');
      }
    });

    test('sí los pone en los que sí lo tienen', () {
      for (final t in [BetModuleType.nassau, BetModuleType.skins,
                       BetModuleType.nassauLowHigh]) {
        expect(_aplicar(t, bola: TeamBall.mejor).sides, isNotNull,
            reason: '${t.label} tiene motor de equipo');
      }
    });

    test('no cambia el tipo del módulo', () {
      // Que "la mejor y la peor" implique Bola Baja / Bola Alta es cosa del
      // paso de qué se cuenta, no de aquí.
      final m = _aplicar(BetModuleType.nassau, bola: TeamBall.mejorYPeor);
      expect(m.type, BetModuleType.nassau);
    });

    test('con un equipo vacío no hace nada', () {
      // Dos lados donde uno no tiene jugadores no es una apuesta.
      final m = BetRecipe.conEquiposDeRonda(_mod(BetModuleType.nassau),
          porEquipos: true, equipoA: a, equipoB: const [],
          bola: TeamBall.mejor);
      expect(m.sides, isNull);
    });
  });

  group('el módulo resultante liquida de verdad', () {
    test('un Nassau por equipos produce asientos entre lados', () {
      // La prueba de que los lados no son decorativos: se liquida una ronda y
      // el dinero se mueve entre equipos, no entre compañeros.
      final mod = _aplicar(BetModuleType.nassau, bola: TeamBall.mejor);
      final course = CourseInfo(name: 'T',
          holes: List.generate(18, (i) =>
              CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)));
      final gross = {'a1': 3, 'a2': 4, 'b1': 5, 'b2': 6};
      final round = Round(
        id: 'r', name: 'R', course: course,
        players: [...a, ...b].map((i) => Player(id: i, name: i)).toList(),
        roundPlayers: [...a, ...b]
            .map((i) => RoundPlayer(playerId: i, handicapEnRonda: 0)).toList(),
        betGroups: [BetGroup(id: 'g', name: 'G',
            format: PartidaFormat.teams2v2,
            playerIds: [...a, ...b], modules: [mod])],
        scores: {
          for (final e in gross.entries)
            e.key: {for (var h = 1; h <= 18; h++)
              h: HoleScore(playerId: e.key, hole: h, grossScore: e.value)},
        },
        events: const {}, oyeseRankings: const {}, sliding: const [],
        createdAt: DateTime(2026, 1, 1), totalHoles: 18,
      );
      final entries = BetEngine.computeAll(round);
      expect(entries, isNotEmpty, reason: 'la apuesta por equipos no pagó');
      final entreCompaneros = entries.any((e) =>
          (a.contains(e.fromPlayerId) && a.contains(e.toPlayerId)) ||
          (b.contains(e.fromPlayerId) && b.contains(e.toPlayerId)));
      expect(entreCompaneros, isFalse, reason: 'cobró entre compañeros');
    });
  });
}
