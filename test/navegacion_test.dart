// ─────────────────────────────────────────────────────────────────────────────
// navegacion_test.dart — cuatro destinos, no siete
//
// Siete supera el techo cómodo y dos pares se solapaban:
//
//   · Tarjeta y Resultados responden la MISMA pregunta —"cómo va la cosa"— así
//     que tenerlas en dos destinos obligaba a elegir entre ellas sin saber cuál
//     tenía el dato. Se fusionan en un destino con pestañas.
//   · Historial y Ajustes no compiten por atención DURANTE una ronda, así que
//     no merecen sitio permanente: se abren desde Inicio.
//
// Lo que se puede comprobar sin pantalla es el CONTEO y la composición. Que los
// toques funcionen y que las pestañas se lean, no: eso va en la revisión.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/app_shell.dart';
import 'package:golf_bet_master/screens/scorecard/scorecard_screen.dart';

void main() {
  group('el conteo de destinos', () {
    test('con ronda son CUATRO, no siete', () {
      expect(mainDestinations(hasRound: true, hideScore: false).length, 4);
    });

    test('sin ronda solo queda Inicio', () {
      // Historial y Ajustes se abren desde ahí, así que no hacen falta en la
      // barra. Y con un solo destino la barra no se pinta: no decide nada y
      // roba alto.
      expect(mainDestinations(hasRound: false, hideScore: false)
              .map((d) => d.label),
          ['Inicio']);
    });

    test('y son estos, en este orden', () {
      // El orden es el del uso: se captura antes de consultar.
      expect(mainDestinations(hasRound: true, hideScore: false)
              .map((d) => d.label),
          ['Inicio', 'Score', 'Apuestas', 'Resultados']);
    });

    test('Tarjeta ya no es un destino', () {
      // Se fusionó dentro de Resultados como pestaña.
      expect(
          mainDestinations(hasRound: true, hideScore: false)
              .map((d) => d.label),
          isNot(contains('Tarjeta')));
    });

    test('Historial y Ajustes tampoco', () {
      final d = mainDestinations(hasRound: true, hideScore: false)
          .map((x) => x.label);
      expect(d, isNot(contains('Historial')));
      expect(d, isNot(contains('Ajustes')));
    });

    test('con score oculto quedan tres, y sigue estando Resultados', () {
      // Un invitado en ronda live con captura de admin no ve Score. Que la
      // barra se acorte está bien; que se caiga Resultados, no.
      final d = mainDestinations(hasRound: true, hideScore: true)
          .map((x) => x.label);
      expect(d, ['Inicio', 'Apuestas', 'Resultados']);
    });

    test('nunca se pasa de cuatro', () {
      // El techo de la fase. Si alguien añade un destino, este test lo para.
      for (final r in [true, false]) {
        for (final h in [true, false]) {
          expect(mainDestinations(hasRound: r, hideScore: h).length,
              lessThanOrEqualTo(4));
        }
      }
    });

    test('Inicio siempre está, y siempre primero', () {
      for (final r in [true, false]) {
        for (final h in [true, false]) {
          expect(mainDestinations(hasRound: r, hideScore: h).first.label,
              'Inicio');
        }
      }
    });
  });

  group('las pestañas de Resultados', () {
    test('son cuatro: el resumen y las tres vistas de la tarjeta', () {
      expect(resultsTabsForTest(), ['Resumen', 'Bruto', 'Neto', '1v1']);
    });

    test('Resumen va primero: es la respuesta corta', () {
      // Quién va ganando y cuánto. El detalle viene después.
      expect(resultsTabsForTest().first, 'Resumen');
    });
  });
}
