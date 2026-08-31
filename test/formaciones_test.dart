// ─────────────────────────────────────────────────────────────────────────────
// FORMACIONES — el atajo que arma los lados
//
// High and Low y Pair vs Field ya se podían jugar: BetSide admite lados de
// distinto tamaño y el best ball existe. Lo que se prueba aquí es el atajo, que
// es lógica pura a propósito —la pantalla no decide quién va con quién— y el
// criterio del empate de handicap, que es lo que se resolvía en silencio.
//
// El test que más protege es el de los empates en la frontera: con dos al mismo
// índice, alguien tiene que ir a cada lado, y si el criterio no es estable el
// mismo grupo sale repartido distinto cada vez que se toca el botón.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/formaciones.dart';
import 'package:golf_bet_master/models/models.dart';

/// Jugadores en el orden en que se capturaron, con su handicap.
List<Player> _js(List<(String, double)> gente) =>
    [for (final g in gente) Player(id: g.$1, name: g.$1.toUpperCase(), handicapBase: g.$2)];

void main() {
  group('1 · el catálogo está completo y genera sus motivos', () {
    test('cada formación tiene etiqueta, icono y descripción', () {
      for (final f in Formacion.values) {
        expect(f.reglas.label, isNotEmpty, reason: f.name);
        expect(() => f.reglas.icon, returnsNormally, reason: f.name);
        expect(f.reglas.descripcion, isNotEmpty, reason: f.name);
      }
    });

    test('el motivo se GENERA del conjunto admitido', () {
      // No es una lista literal: ampliar los tamaños no deja un texto hablando
      // de otro número. Es el fallo que ya salió ocho veces en esta app.
      final m = Formacion.highAndLow.motivoNoDisponible(3);
      expect(m, contains('4, 5 o 6'));
      expect(m, contains('esta ronda tiene 3'));
    });

    test('con pocos y con muchos el motivo es DISTINTO', () {
      // Son dos problemas distintos y decirlos juntos no informa.
      final pocos = Formacion.highAndLow.motivoNoDisponible(3);
      final muchos = Formacion.highAndLow.motivoNoDisponible(8);
      expect(pocos, isNot(muchos));
      expect(pocos, contains('dos mitades'));
      expect(muchos, contains('lado alto'));
    });

    test('dentro del rango no hay motivo', () {
      for (final n in [4, 5, 6]) {
        expect(Formacion.highAndLow.motivoNoDisponible(n), isNull, reason: '$n');
      }
      for (final n in [3, 4, 5, 6]) {
        expect(Formacion.parejaVsResto.motivoNoDisponible(n), isNull,
            reason: '$n');
      }
      // El reparto manual vale con cualquier número.
      for (final n in [2, 3, 4, 5, 6, 8]) {
        expect(Formacion.manual.motivoNoDisponible(n), isNull, reason: '$n');
      }
    });

    test('fuera del rango no se arma nada', () {
      expect(armarFormacion(Formacion.highAndLow, _js([('a', 10), ('b', 12), ('c', 14)])),
          isNull);
      expect(armarFormacion(Formacion.parejaVsResto, _js([('a', 10), ('b', 12)])),
          isNull);
    });

    test('el reparto se anuncia antes de elegir, y con el número real', () {
      expect(Formacion.highAndLow.reparto(5), '2 contra 3, por handicap.');
      expect(Formacion.highAndLow.reparto(4), '2 contra 2, por handicap.');
      expect(Formacion.highAndLow.reparto(6), '3 contra 3, por handicap.');
      expect(Formacion.parejaVsResto.reparto(5), '2 contra 3.');
      // Fuera de rango no se anuncia un reparto que no va a pasar.
      expect(Formacion.highAndLow.reparto(3), isEmpty);
    });

    test('la descripción explica por qué 2 contra 3 no desequilibra tanto', () {
      // El matiz del manual. Sin él, la primera reacción es que está roto.
      expect(Formacion.highAndLow.reglas.descripcion, contains('compensa'));
      expect(Formacion.highAndLow.reglas.descripcion, contains('mejor bola'));
    });
  });

  group('2 · High and Low: la mitad baja contra la mitad alta', () {
    test('con cinco sale 2 contra 3, y son los dos más bajos', () {
      final lados = armarFormacion(
          Formacion.highAndLow,
          // A propósito desordenados: el atajo ordena, no confía en la captura.
          _js([('c', 18), ('a', 4), ('e', 22), ('b', 9), ('d', 20)]))!;
      expect(lados.$1, ['a', 'b']);
      expect(lados.$2, ['c', 'd', 'e']);
    });

    test('con cuatro sale 2 contra 2', () {
      final lados = armarFormacion(Formacion.highAndLow,
          _js([('a', 4), ('b', 9), ('c', 18), ('d', 20)]))!;
      expect(lados.$1, ['a', 'b']);
      expect(lados.$2, ['c', 'd']);
    });

    test('con seis sale 3 contra 3, no 2 contra 4', () {
      // La regla es "la mitad de abajo contra la de arriba". Con seis, 2 contra
      // 4 daría al lado alto cuatro bolas y el best ball dejaría de compensar.
      final lados = armarFormacion(
          Formacion.highAndLow,
          _js([('a', 2), ('b', 5), ('c', 8), ('d', 15), ('e', 18), ('f', 24)]))!;
      expect(lados.$1, ['a', 'b', 'c']);
      expect(lados.$2, ['d', 'e', 'f']);
    });

    test('todos entran, y ninguno dos veces', () {
      for (final n in [4, 5, 6]) {
        final gente = _js([for (var i = 0; i < n; i++) ('p$i', i * 3.0)]);
        final lados = armarFormacion(Formacion.highAndLow, gente)!;
        final todos = [...lados.$1, ...lados.$2];
        expect(todos, hasLength(n), reason: '$n');
        expect(todos.toSet(), gente.map((p) => p.id).toSet(), reason: '$n');
      }
    });
  });

  group('3 · el empate de handicap en la frontera, con criterio', () {
    test('pasa el que va antes en la LISTA, no el que caiga', () {
      // Cinco jugadores, dos empatados a 12 justo en la frontera: uno va al
      // lado bajo y otro al alto. El criterio es el orden de la lista, que es
      // el que el usuario ve en la pantalla anterior.
      final lados = armarFormacion(Formacion.highAndLow,
          _js([('a', 5), ('empatado1', 12), ('empatado2', 12), ('d', 20), ('e', 22)]))!;
      expect(lados.$1, ['a', 'empatado1']);
      expect(lados.$2, ['empatado2', 'd', 'e']);
    });

    test('y al revés si se capturaron al revés: es el orden, no el nombre', () {
      // El contrapeso. Si el criterio fuera alfabético, este test daría lo
      // mismo que el anterior.
      final lados = armarFormacion(Formacion.highAndLow,
          _js([('a', 5), ('empatado2', 12), ('empatado1', 12), ('d', 20), ('e', 22)]))!;
      expect(lados.$1, ['a', 'empatado2']);
    });

    test('armar dos veces da lo MISMO: el criterio es estable', () {
      // Un sorteo daría un reparto distinto cada vez que se toca el botón, y
      // rearmar dejaría de ser seguro.
      final gente = _js([('a', 12), ('b', 12), ('c', 12), ('d', 12), ('e', 12)]);
      final una = armarFormacion(Formacion.highAndLow, gente)!;
      final otra = armarFormacion(Formacion.highAndLow, gente)!;
      expect(una.$1, otra.$1);
      expect(una.$2, otra.$2);
    });

    test('con TODOS al mismo handicap se parte por la lista', () {
      final lados = armarFormacion(Formacion.highAndLow,
          _js([('a', 15), ('b', 15), ('c', 15), ('d', 15), ('e', 15)]))!;
      expect(lados.$1, ['a', 'b']);
      expect(lados.$2, ['c', 'd', 'e']);
    });
  });

  group('4 · Pair vs Field: la pareja, y el resto', () {
    test('la propuesta es el handicap combinado más bajo', () {
      // Que son los dos más bajos: no hay que probar combinaciones.
      final lados = armarFormacion(Formacion.parejaVsResto,
          _js([('c', 18), ('a', 4), ('e', 22), ('b', 9), ('d', 20)]))!;
      expect(lados.$1, ['a', 'b']);
      expect(lados.$2, ['c', 'd', 'e']);
    });

    test('la pareja se puede fijar a mano y manda sobre la propuesta', () {
      final lados = armarFormacion(
          Formacion.parejaVsResto,
          _js([('a', 4), ('b', 9), ('c', 18), ('d', 20), ('e', 22)]),
          parejaBase: const ['d', 'e'])!;
      expect(lados.$1, ['d', 'e']);
      expect(lados.$2, ['a', 'b', 'c']);
    });

    test('una pareja con alguien que ya no juega se ignora', () {
      // Pasa al quitar un jugador y no tocar la pareja. Meter a quien no está
      // en la ronda dejaría un lado con un id fantasma.
      final lados = armarFormacion(
          Formacion.parejaVsResto,
          _js([('a', 4), ('b', 9), ('c', 18)]),
          parejaBase: const ['a', 'zz'])!;
      expect(lados.$1, ['a', 'b'], reason: 'vuelve a la propuesta');
      expect(lados.$2, ['c']);
    });

    test('con tres es 2 contra 1, que es un formato de verdad', () {
      final lados = armarFormacion(
          Formacion.parejaVsResto, _js([('a', 4), ('b', 9), ('c', 18)]))!;
      expect(lados.$1, hasLength(2));
      expect(lados.$2, ['c']);
    });

    test('la descripción dice que lo ganado se parte entre dos', () {
      expect(Formacion.parejaVsResto.reglas.descripcion, contains('entre dos'));
    });
  });

  group('5 · el reparto manual sigue siendo el alternado de siempre', () {
    test('alterna por orden de captura, sin mirar handicap', () {
      // Para que dos del mismo nivel no caigan juntos solo por cómo se
      // capturaron. Es lo que había, y no cambia.
      final lados = armarFormacion(
          Formacion.manual, _js([('a', 4), ('b', 5), ('c', 6), ('d', 7)]))!;
      expect(lados.$1, ['a', 'c']);
      expect(lados.$2, ['b', 'd']);
    });
  });
}
