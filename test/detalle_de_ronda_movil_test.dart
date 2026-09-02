// ─────────────────────────────────────────────────────────────────────────────
// EL DETALLE DE UNA RONDA, EN UN IPHONE
//
// «La etiqueta SALIDA se parte letra por letra en vertical porque el valor es
// demasiado largo, y el texto se sale por la derecha.»
//
// Las dos cosas a la vez, y de la misma causa: el `Expanded` estaba en la
// ETIQUETA. El valor se quedaba con su ancho natural —sin límite— así que se
// salía por la derecha, y a la etiqueta le quedaban cero píxeles, así que
// envolvía carácter a carácter.
//
// ── Cómo se comprueba sin mirar ─────────────────────────────────────────────
//
// Con geometría, a 390 px de ancho, que es un iPhone. Dos medidas y las dos son
// exactas:
//
//   · el rectángulo del valor no puede pasarse del ancho disponible
//   · el de la etiqueta tiene que ser más ANCHO que ALTO — una etiqueta de seis
//     letras partida en vertical mide 10 px de ancho y 90 de alto, y eso se ve
//     en el número sin necesidad de mirar la pantalla
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/screens/settings/settings_screen.dart';

const _ancho = 390.0;

/// El valor largo del reporte, tal cual salía.
const _largo = 'no guardada · no coincide con ninguna de tus campos';

Future<void> _montar(WidgetTester tester, String valor) async {
  tester.view.physicalSize = const Size(_ancho, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Padding(
        // El mismo margen que la pantalla real.
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: DatoDeRonda(
            etiqueta: 'SALIDA', valor: valor, t: GolfTheme.classic),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  group('la fila de etiqueta y valor, a 390 px', () {
    testWidgets('CLAVE: la etiqueta no se parte en vertical', (tester) async {
      await _montar(tester, _largo);
      final r = tester.getRect(find.text('SALIDA'));
      expect(r.width, greaterThan(r.height),
          reason: 'SALIDA mide ${r.width.round()}×${r.height.round()}: '
              'partida letra a letra sería alta y estrecha');
    });

    testWidgets('CLAVE: y el valor no se sale por la derecha', (tester) async {
      await _montar(tester, _largo);
      final r = tester.getRect(find.text(_largo));
      // 20 px de margen a cada lado.
      expect(r.right, lessThanOrEqualTo(_ancho - 20 + 0.5),
          reason: 'acaba en ${r.right.round()} px y el margen está en '
              '${(_ancho - 20).round()}');
    });

    testWidgets('CLAVE: el valor largo BAJA DE LÍNEA en vez de desbordar',
        (tester) async {
      // Es lo que hace que quepa: dos líneas, no una recortada.
      await _montar(tester, _largo);
      final alto = tester.getRect(find.text(_largo)).height;
      await _montar(tester, 'Blancas');
      final altoCorto = tester.getRect(find.text('Blancas')).height;
      expect(alto, greaterThan(altoCorto),
          reason: 'el largo ocupa más de una línea');
    });

    testWidgets('CONTRAPESO: y un valor corto sigue en una sola línea',
        (tester) async {
      // Sin esto, una fila que siempre envolviera pasaría los tests de arriba.
      await _montar(tester, 'Blancas · deducida del CR y el Slope');
      final r = tester.getRect(find.text('SALIDA'));
      expect(r.width, greaterThan(r.height));
    });

    testWidgets('CLAVE: el CR y el Slope tienen su propia fila',
        (tester) async {
      // Eran el tercer y cuarto dato de la misma línea. Nada sobraba —los dos
      // números solo aparecen aquí— así que no se quitó nada: se separó.
      tester.view.physicalSize = const Size(_ancho, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(children: [
              DatoDeRonda(
                  etiqueta: 'SALIDA', valor: _largo, t: GolfTheme.classic),
              DatoDeRonda(
                  etiqueta: 'CR · SLOPE',
                  valor: '35.9 · 149',
                  t: GolfTheme.classic),
            ]),
          ),
        ),
      ));
      await tester.pump();
      expect(find.text('CR · SLOPE'), findsOneWidget);
      expect(find.text('35.9 · 149'), findsOneWidget);
      final r = tester.getRect(find.text('CR · SLOPE'));
      expect(r.width, greaterThan(r.height));
    });
  });
}
