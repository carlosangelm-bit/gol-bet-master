// ─────────────────────────────────────────────────────────────────────────────
// proyeccion_familia_test.dart — N módulos expandidos son UNA apuesta
//
// La pantalla de Apuestas leía cada módulo de alcance `pair` como una
// excepción. Al expandir un Nassau en seis módulos 1v1 —porque un solo cruce
// pactó otro importe— decía:
//
//     APUESTAS DE LA RONDA · 0 — Sin apuestas de partida
//     EXCEPCIONES · 6
//
// Cinco de esos seis juegan el importe base: no son excepción de nada. Y decir
// que no hay apuestas de partida es directamente falso. La lectura verdadera es
// "un Nassau para todos, con una excepción".
//
// Es una regresión que introdujo la expansión, así que el test va con ella.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/bet_recipe.dart';
import 'package:golf_bet_master/screens/bets/bets_screen.dart';

const cuatro = ['j1', 'j2', 'j3', 'j4'];

Round _round(List<BetModuleInstance> mods) => Round(
      id: 'r', name: 'R',
      course: CourseInfo(name: 'T',
          holes: List.generate(18,
              (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1))),
      players: cuatro.map((i) => Player(id: i, name: i)).toList(),
      roundPlayers: cuatro
          .map((i) => RoundPlayer(playerId: i, handicapEnRonda: 0)).toList(),
      betGroups: [BetGroup(id: 'g', name: 'G',
          format: PartidaFormat.oneVsOne, playerIds: cuatro, modules: mods)],
      scores: const {}, events: const {}, oyeseRankings: const {},
      sliding: const [], createdAt: DateTime(2026, 1, 1), totalHoles: 18,
    );

BetModuleInstance _base() => BetModuleInstance.defaultFor(
    BetModuleType.nassau, cuatro, id: 'flujo_puntos');

void main() {
  group('una familia expandida se lee como una apuesta', () {
    test('un ajuste en un cruce: 1 regla y 1 excepción, no 6 excepciones', () {
      final mods = BetRecipe.conCrucesFuera(_base(),
          participantIds: cuatro,
          importes: {
            BetRecipe.cruceKey('j1', 'j2'):
                const MontoPorCruce(front: 100, back: 100, total: 200),
          });
      expect(mods.length, 6, reason: 'los 6 cruces de cuatro jugadores');

      final p = projectRulesForTest(_round(mods));
      expect(p.rules.length, 1, reason: 'la familia es UNA apuesta');
      expect(p.exceptions.length, 1, reason: 'solo uno se sale del importe');
    });

    test('la regla dice cuántos enfrentamientos cubre', () {
      final mods = BetRecipe.conCrucesFuera(_base(),
          participantIds: cuatro,
          importes: {
            BetRecipe.cruceKey('j1', 'j2'): const MontoPorCruce(front: 100),
          });
      final p = projectRulesForTest(_round(mods));
      expect(ruleMembersForTest(p.rules.first), 6);
    });

    test('la excepción es la que se desvía, no una de las que van al base', () {
      final mods = BetRecipe.conCrucesFuera(_base(),
          participantIds: cuatro,
          importes: {
            BetRecipe.cruceKey('j3', 'j4'):
                const MontoPorCruce(front: 999, back: 999, total: 999),
          });
      final p = projectRulesForTest(_round(mods));
      final ex = p.exceptions.single;
      expect({ex.p1Id, ex.p2Id}, {'j3', 'j4'});
    });

    test('solo exclusiones, sin ajustes: 1 regla y NINGUNA excepción', () {
      // Excluir un cruce no crea una excepción de importe: todos los que
      // quedan juegan lo mismo.
      final mods = BetRecipe.conCrucesFuera(_base(),
          participantIds: cuatro, fuera: {BetRecipe.cruceKey('j1', 'j2')});
      final p = projectRulesForTest(_round(mods));
      expect(p.rules.length, 1);
      expect(p.exceptions, isEmpty);
      expect(ruleMembersForTest(p.rules.first), 5);
    });
  });

  group('lo que no debe cambiar', () {
    test('un módulo de partida sigue siendo una regla', () {
      final p = projectRulesForTest(_round([_base()]));
      expect(p.rules.length, 1);
      expect(ruleMembersForTest(p.rules.first), 1);
      expect(p.exceptions, isEmpty);
    });

    test('un duelo suelto de verdad sigue siendo excepción', () {
      // Un solo módulo con alcance pair y sin familia: es una apuesta que
      // existe únicamente para ese cruce.
      final duelo = BetModuleInstance.defaultFor(
          BetModuleType.skins, const ['j1', 'j2'], id: 'duelo')
          .copyWith(scope: BetScope.pair('j1', 'j2'));
      final p = projectRulesForTest(_round([_base(), duelo]));
      expect(p.rules.length, 1);
      expect(p.exceptions.length, 1);
    });
  });
}
