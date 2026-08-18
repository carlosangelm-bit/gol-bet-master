// ─────────────────────────────────────────────────────────────────────────────
// navegacion_ronda_test.dart — arrancar la ronda vuelve al shell, no a la mitad
//
// El bug: iniciar la ronda desde una plantilla devolvía a "Mis Plantillas". No
// era la pestaña —startRound ya pone tabIndex en Score— sino la PILA:
// _createAndStartRound hacía UN pop, que basta desde Nueva Ronda y no desde una
// plantilla, donde hay dos pantallas encima.
//
// Es la misma forma que el doble pop del sheet de apuesta: un número fijo de
// pops solo funciona para el camino desde el que se escribió.
//
// Lo que estos tests fijan es la profundidad: la convención tiene que valer para
// CUALQUIER pila, porque una entrada nueva no debe volver a descuadrarla.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/widgets/app_navigation.dart';

/// Monta [profundidad] pantallas encima del shell y devuelve al shell.
Future<void> _apilarYVolver(WidgetTester tester, int profundidad) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            child: const Text('SHELL'),
            onPressed: () {
              for (var i = 1; i <= profundidad; i++) {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (c) => Scaffold(
                    body: Center(
                      child: ElevatedButton(
                        child: Text('NIVEL $i'),
                        onPressed: () => volverAlShell(c),
                      ),
                    ),
                  ),
                ));
              }
            },
          ),
        ),
      ),
    ),
  ));

  await tester.tap(find.text('SHELL'));
  await tester.pumpAndSettle();
  // Se pulsa en la última apilada, que es la que queda arriba.
  await tester.tap(find.text('NIVEL $profundidad'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('desde Nueva Ronda: una pantalla encima', (tester) async {
    // [Shell, Setup] — el caso que ya funcionaba con un pop.
    await _apilarYVolver(tester, 1);
    expect(find.text('SHELL'), findsOneWidget);
    expect(find.text('NIVEL 1'), findsNothing);
  });

  testWidgets('desde una plantilla: DOS pantallas encima', (tester) async {
    // [Shell, Plantillas, Setup] — el bug. Con un solo pop quedaba "NIVEL 1",
    // que es "Mis Plantillas".
    await _apilarYVolver(tester, 2);
    expect(find.text('SHELL'), findsOneWidget,
        reason: 'un pop habría dejado la pantalla intermedia');
    expect(find.text('NIVEL 1'), findsNothing,
        reason: 'aquí quedaba "Mis Plantillas"');
    expect(find.text('NIVEL 2'), findsNothing);
  });

  testWidgets('y con tres o más, que es la entrada que no existe todavía',
      (tester) async {
    // Lo que hace que la convención no vuelva a romperse: no depende de cuántas
    // pantallas haya, así que un atajo nuevo no la descuadra.
    await _apilarYVolver(tester, 4);
    expect(find.text('SHELL'), findsOneWidget);
    for (var i = 1; i <= 4; i++) {
      expect(find.text('NIVEL $i'), findsNothing, reason: 'nivel $i');
    }
  });

  testWidgets('llamarlo con la pila ya en el shell no la vacía',
      (tester) async {
    // Un popUntil de más no puede dejar la app sin pantallas.
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              child: const Text('SHELL'),
              onPressed: () => volverAlShell(context),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('SHELL'));
    await tester.pumpAndSettle();
    expect(find.text('SHELL'), findsOneWidget);
  });
}
