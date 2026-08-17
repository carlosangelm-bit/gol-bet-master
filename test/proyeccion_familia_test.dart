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

  _avisos();
}

// ── Los avisos de score incompleto colapsan ─────────────────────────────────
//
// Una apuesta expandida en módulos 1v1 daba seis líneas casi idénticas:
// "Nassau · falta CAM, CAV", "Nassau · falta CAM, AAM"… Seis avisos del mismo
// problema no informan seis veces mejor: entierran el resto de la pantalla.
//
// Mismo colapso que la ficha de la regla, en otra superficie.
void _avisos() {
  group('los avisos se agrupan por tipo', () {
    /// Réplica del cálculo de results_screen: una línea por TIPO, no por módulo.
    List<String> avisos(Round r, List<BetModuleInstance> mods) {
      final porTipo = <BetModuleType, ({int duelos, Set<String> faltan})>{};
      for (final m in mods) {
        final pids = r.scoreCarriersOfModule(m, r.betGroups.first.playerIds);
        final faltan = <String>{};
        var completos = 0;
        for (final ch in r.course.holes) {
          var lleno = true;
          for (final pid in pids) {
            if (!r.getScore(pid, ch.hole).hasScore) {
              lleno = false;
              faltan.add(pid);
            }
          }
          if (lleno) completos++;
        }
        if (completos >= r.course.holes.length) continue;
        final previo = porTipo[m.type];
        porTipo[m.type] = (
          duelos: (previo?.duelos ?? 0) + 1,
          faltan: {...?previo?.faltan, ...faltan},
        );
      }
      return [
        for (final e in porTipo.entries)
          e.value.duelos > 1
              ? '${e.key.label} · sin score en ${e.value.duelos} duelos'
              : '${e.key.label} · falta ${e.value.faltan.join(', ')}',
      ];
    }

    test('seis módulos sin score dan UNA línea, no seis', () {
      final mods = BetRecipe.conCrucesFuera(_base(), participantIds: cuatro,
          importes: {
            BetRecipe.cruceKey('j1', 'j2'): const MontoPorCruce(front: 100),
          });
      expect(mods.length, 6);
      final r = _round(mods); // sin scores: todos incompletos
      final a = avisos(r, mods);
      expect(a.length, 1);
      expect(a.single, 'Nassau · sin score en 6 duelos');
    });

    test('con un solo módulo se sigue nombrando a quién falta', () {
      // Colapsar no puede costar el dato útil cuando hay UN duelo: ahí el nombre
      // es lo que distingue "sigue capturando" de "está mal armada".
      final mods = [_base()];
      final a = avisos(_round(mods), mods);
      expect(a.single, contains('falta'));
      expect(a.single, contains('j1'));
    });

    test('tipos distintos siguen dando líneas distintas', () {
      // Agrupar por tipo no es agrupar todo: dos apuestas distintas incompletas
      // son dos problemas distintos.
      final skins = BetModuleInstance.defaultFor(
          BetModuleType.skins, cuatro, id: 'flujo_skins');
      final mods = [_base(), skins];
      expect(avisos(_round(mods), mods).length, 2);
    });

    test('lo completo no genera aviso', () {
      final mods = [_base()];
      final r = _round(mods).copyWith(scores: {
        for (final i in cuatro)
          i: {for (var h = 1; h <= 18; h++)
            h: HoleScore(playerId: i, hole: h, grossScore: 4)},
      });
      expect(avisos(r, mods), isEmpty);
    });
  });
}
