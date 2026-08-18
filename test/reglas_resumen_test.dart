// ─────────────────────────────────────────────────────────────────────────────
// reglas_resumen_test.dart — la pestaña Reglas sirve a los DOS modelos
//
// "No entiendo la pantalla de reglas, no la entiendo y no veo su funcionalidad."
//
// La pantalla está diseñada para "una apuesta para todos, con excepciones". Una
// ronda creada desde un grupo de apuesta es TODA reglas por duelo, así que la
// mitad de arriba quedaba vacía y la de abajo tenía 30 líneas planas que no son
// excepciones de nada.
//
// Lo que estos tests fijan es que el caso original NO empeore, que es lo que se
// rompe fácil al rediseñar para el caso nuevo: los dos modelos conviven y una
// ronda puede tener apuestas de partida Y excepciones.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
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

/// Módulo de duelo, como los que produce un grupo de apuesta.
BetModuleInstance _duelo(BetModuleType t, String a, String b, {String? fam}) =>
    BetModuleInstance.defaultFor(t, [a, b], id: '${t.name}_${a}_$b')
        .copyWith(scope: BetScope.pair(a, b), betGroupId: fam ?? '${t.name}_${a}_$b');

void main() {
  group('una ronda que viene de un grupo', () {
    /// Como Viernes CGM: cada pareja con sus tipos, ninguna apuesta de partida.
    Round deGrupo() {
      final mods = <BetModuleInstance>[];
      for (var i = 0; i < cuatro.length; i++) {
        for (var j = i + 1; j < cuatro.length; j++) {
          for (final t in [BetModuleType.nassau, BetModuleType.medal,
                           BetModuleType.putts]) {
            mods.add(_duelo(t, cuatro[i], cuatro[j]));
          }
        }
      }
      return _round(mods);
    }

    test('no tiene NINGUNA apuesta de partida', () {
      // Es la condición que dispara el resumen por tipo.
      final p = projectRulesForTest(deGrupo());
      expect(p.rules, isEmpty);
      expect(p.exceptions.length, 18, reason: '6 duelos × 3 tipos');
    });

    test('las familias no agrupan aquí, y por eso hacía falta otro eje', () {
      // El betGroupId de un grupo es único por DUELO y por TIPO, así que cada
      // familia tiene UN miembro y la proyección la salta. Las familias agrupan
      // "una apuesta partida en parejas"; esto es agrupar por tipo entre duelos.
      final r = deGrupo();
      final fams = <String>{};
      for (final m in r.betGroups.single.modules) {
        fams.add(m.betGroupId!);
      }
      expect(fams.length, 18, reason: 'una familia por módulo: no agrupan');
    });

    test('agrupado por tipo son TRES líneas, no 18', () {
      final tipos = deGrupo()
          .betGroups
          .single
          .modules
          .map((m) => m.type)
          .toSet();
      expect(tipos.length, 3);
    });

    test('y cada tipo cubre los 6 duelos', () {
      final porTipo = <BetModuleType, int>{};
      for (final m in deGrupo().betGroups.single.modules) {
        porTipo[m.type] = (porTipo[m.type] ?? 0) + 1;
      }
      expect(porTipo.values.every((n) => n == 6), isTrue);
    });
  });

  _filtro();

  group('el caso original no empeora', () {
    test('una apuesta de partida sigue siendo una REGLA', () {
      final p = projectRulesForTest(
          _round([BetModuleInstance.defaultFor(BetModuleType.nassau, cuatro, id: 'm')]));
      expect(p.rules.length, 1);
      expect(p.exceptions, isEmpty);
    });

    test('partida MÁS excepción se sigue viendo como antes', () {
      // El punto que se rompe fácil: los dos modelos conviven.
      final base =
          BetModuleInstance.defaultFor(BetModuleType.nassau, cuatro, id: 'm');
      final suelto = _duelo(BetModuleType.skins, 'j1', 'j2', fam: null);
      final p = projectRulesForTest(_round([base, suelto]));
      expect(p.rules.length, 1, reason: 'la de partida sigue arriba');
      expect(p.exceptions.length, 1, reason: 'el duelo suelto sigue abajo');
    });

    test('con reglas presentes NO se dispara el resumen por tipo', () {
      // La condición es rules.isEmpty: si hay una apuesta de partida, la vista
      // de siempre. Rediseñarla para el caso del grupo dejaría peor el original.
      final base =
          BetModuleInstance.defaultFor(BetModuleType.nassau, cuatro, id: 'm');
      final p = projectRulesForTest(_round([base]));
      expect(p.rules.isEmpty, isFalse);
    });
  });
}

// ── El filtro por jugador ────────────────────────────────────────────────────
//
// Con 6 jugadores hay 15 duelos y con 9 llegan a 36. El selector es EL de la
// pestaña 1v1 de la Tarjeta, extraído a PlayerFilterBar: dos selectores de
// jugador divergen en cuanto uno gane un comportamiento.
void _filtro() {
  group('filtrar duelos por jugador', () {
    /// Réplica del filtro de la vista: solo los duelos que tocan a ese jugador.
    List<({String a, String b})> filtrar(
        List<({String a, String b})> duelos, String? pid) {
      if (pid == null) return duelos;
      return duelos.where((d) => d.a == pid || d.b == pid).toList();
    }

    final seis = [
      for (var i = 0; i < cuatro.length; i++)
        for (var j = i + 1; j < cuatro.length; j++)
          (a: cuatro[i], b: cuatro[j]),
    ];

    test('sin filtro se ven todos', () {
      expect(seis.length, 6);
      expect(filtrar(seis, null).length, 6);
    });

    test('con un jugador quedan solo los suyos', () {
      // Cuatro jugadores: cada uno juega contra los otros tres.
      expect(filtrar(seis, 'j1').length, 3);
      for (final d in filtrar(seis, 'j1')) {
        expect([d.a, d.b], contains('j1'));
      }
    });

    test('el filtrado nunca incluye duelos ajenos', () {
      for (final pid in cuatro) {
        for (final d in filtrar(seis, pid)) {
          expect(d.a == pid || d.b == pid, isTrue, reason: '$pid');
        }
      }
    });

    test('la suma de los filtros es el doble del total', () {
      // Cada duelo aparece en el filtro de sus DOS jugadores. Si no cuadrara,
      // el filtro estaría perdiendo o duplicando duelos.
      final suma =
          cuatro.fold<int>(0, (s, pid) => s + filtrar(seis, pid).length);
      expect(suma, seis.length * 2);
    });

    test('un jugador que no juega nada da lista vacía, no todos', () {
      // El fallo típico de un filtro mal escrito: sin coincidencias devuelve la
      // lista entera y parece que no filtra.
      expect(filtrar(seis, 'nadie'), isEmpty);
    });
  });
}
