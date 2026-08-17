// ─────────────────────────────────────────────────────────────────────────────
// score_shape_test.dart — el score se distingue sin depender del color
//
// Cierra la deuda del skip de design_tokens_test. El criterio estaba escrito
// desde la fase 2 y no se podía cumplir: mientras el score se comunicara por
// color de fondo, quitarle el rojo al bogey lo dejaba indistinguible de un par.
// Token y forma tenían que cambiar juntos.
//
// La prueba de que ahora no depende del color: la FORMA es una función pura del
// score y el par, y las cinco categorías dan cinco formas distintas.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/widgets/score_shape.dart';
import 'package:golf_bet_master/screens/results/results_screen.dart';

const temas = [GolfTheme.light, GolfTheme.dark, GolfTheme.classic];

void main() {
  group('la forma dice el resultado', () {
    test('la convención de la tarjeta de papel, par 4', () {
      expect(scoreShapeFor(2, 4), ScoreShape.doubleCircle); // eagle
      expect(scoreShapeFor(3, 4), ScoreShape.circle);       // birdie
      expect(scoreShapeFor(4, 4), ScoreShape.none);         // par
      expect(scoreShapeFor(5, 4), ScoreShape.square);       // bogey
      expect(scoreShapeFor(6, 4), ScoreShape.doubleSquare); // doble
      expect(scoreShapeFor(9, 4), ScoreShape.doubleSquare); // y peor
    });

    test('funciona igual en par 3 y par 5', () {
      // La forma es relativa al par, no al número absoluto: un 4 es birdie en
      // un par 5 y bogey en un par 3.
      expect(scoreShapeFor(4, 5), ScoreShape.circle);
      expect(scoreShapeFor(4, 3), ScoreShape.square);
      expect(scoreShapeFor(1, 3), ScoreShape.doubleCircle); // hoyo en uno
    });

    test('un hoyo sin jugar no lleva forma', () {
      expect(scoreShapeFor(0, 4), ScoreShape.none);
      expect(scoreShapeFor(-1, 4), ScoreShape.none);
    });

    test('las cinco categorías dan cinco formas distintas', () {
      // Es la definición de "se distingue sin color": si dos categorías
      // compartieran forma, harían falta dos colores para separarlas.
      final formas = [
        scoreShapeFor(2, 4), scoreShapeFor(3, 4), scoreShapeFor(4, 4),
        scoreShapeFor(5, 4), scoreShapeFor(6, 4),
      ];
      expect(formas.toSet().length, 5);
    });

    test('bajo par son círculos y sobre par cuadros, sin solaparse', () {
      for (var g = 1; g <= 9; g++) {
        final f = scoreShapeFor(g, 4);
        if (g < 4) {
          expect(f.esCirculo, isTrue, reason: 'gross $g en par 4');
          expect(f.esCuadro, isFalse);
        } else if (g > 4) {
          expect(f.esCuadro, isTrue, reason: 'gross $g en par 4');
          expect(f.esCirculo, isFalse);
        } else {
          expect(f.esCirculo, isFalse);
          expect(f.esCuadro, isFalse);
        }
      }
    });

    test('cada forma tiene nombre en golf', () {
      for (final f in ScoreShape.values) {
        expect(f.label, isNotEmpty, reason: '$f');
      }
    });
  });

  group('el color del score ya no pisa el del dinero', () {
    test('ninguno de los dos tokens coincide con profit ni loss', () {
      // Antes lOver era EXACTAMENTE lLoss, y en clásico cUnder era cProfit y
      // cOver era cLoss: el mismo rojo decía "bogey" y "pagas".
      for (final t in temas) {
        expect(t.scoreUnder, isNot(t.profit));
        expect(t.scoreUnder, isNot(t.loss));
        expect(t.scoreOver, isNot(t.profit));
        expect(t.scoreOver, isNot(t.loss));
      }
    });

    test('y son de baja saturación: tiñen, no informan', () {
      // Un tono saturado en el canal del score volvería a competir con el
      // dinero por la atención, que es el problema que se está cerrando.
      for (final t in temas) {
        for (final c in [t.scoreUnder, t.scoreOver]) {
          final hsl = HSLColor.fromColor(c);
          expect(hsl.saturation, lessThan(0.45),
              reason: 'saturación ${hsl.saturation.toStringAsFixed(2)}');
        }
      }
    });

    test('bajo par y sobre par siguen siendo distinguibles entre sí', () {
      // Bajar la saturación no puede llegar a fundirlos: el trazo tiñe, y si
      // los dos tiñeran igual se perdería un matiz gratis.
      for (final t in temas) {
        expect(t.scoreUnder, isNot(t.scoreOver));
      }
    });
  });

  group('el chip de importe pertenece al canal del dinero', () {
    test('es el color de quien cobra, en los tres temas', () {
      // Antes era indigo #3D5AFE en oscuro y clásico: un color que no pertenecía
      // a ningún canal. Ahora el mismo elemento dice cuánto Y hacia dónde.
      for (final t in temas) {
        expect(transferAmountBgForTest(t).first, t.profit);
      }
    });

    test('no queda ni rastro del indigo', () {
      const indigo = Color(0xFF3D5AFE);
      for (final t in temas) {
        expect(transferAmountBgForTest(t), isNot(contains(indigo)));
      }
    });

    test('el texto contrasta con el chip en los tres temas', () {
      // En clásico el profit es dorado y el blanco encima no se leería.
      for (final t in temas) {
        final fondo = transferAmountBgForTest(t).first;
        final texto = transferAmountTextForTest(t);
        final dif =
            (fondo.computeLuminance() - texto.computeLuminance()).abs();
        expect(dif, greaterThan(0.4),
            reason: 'contraste ${dif.toStringAsFixed(2)} insuficiente');
      }
    });
  });
}
