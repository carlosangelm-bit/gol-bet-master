// ─────────────────────────────────────────────────────────────────────────────
// sheet_navegacion_test.dart — la convención de quién cierra el sheet
//
// El bug: editar una apuesta en una ronda iniciada y pulsar Guardar dejaba la
// pantalla EN BLANCO. Sin excepción en consola, porque no había error: la lógica
// de guardado es correcta y el módulo se actualiza bien.
//
// BetModuleEditSheet._save hacía pop, y DOS de los ocho llamadores popeaban
// también. Los dos pops cerraban el sheet Y la pantalla de debajo: la pila
// quedaba vacía y Flutter pintaba blanco sobre un árbol sin nada.
//
// CONVENCIÓN ELEGIDA: el sheet cierra, ningún onSave lo repite. Seis de los ocho
// ya la asumían.
//
// Y sí es testeable, igual que los iconos fuera del viewport: se guarda y se
// comprueba que la pantalla anterior SIGUE MONTADA. Eso es exactamente lo que
// fallaba, y ningún test de lógica lo veía.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/widgets/bet_module_edit_sheet.dart';

const pids = ['a', 'b'];

BetGroup _grupo() => BetGroup(
      id: 'g', name: 'G', format: PartidaFormat.oneVsOne,
      playerIds: pids,
      modules: [BetModuleInstance.defaultFor(BetModuleType.nassau, pids, id: 'm')],
    );

/// Una pantalla con un botón que abre el sheet, como en la app.
///
/// [popEnCallback] simula el llamador descuadrado: el que además de dejar que el
/// sheet cierre, cerraba él. Es lo que producía el blanco.
Widget _app({required bool popEnCallback, required List<String> guardados}) {
  return MaterialApp(
    home: Builder(builder: (context) {
      return Scaffold(
        body: Center(
          child: ElevatedButton(
            // Texto de la pantalla de DEBAJO: si desaparece, se fue la pila.
            child: const Text('PANTALLA BASE'),
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (ctx) => BetModuleEditSheet(
                group: _grupo(),
                mod: _grupo().modules.single,
                t: GolfTheme.light,
                onSave: (saved) {
                  guardados.add(saved.id);
                  // El llamador descuadrado hacía esto.
                  if (popEnCallback) Navigator.pop(ctx);
                },
              ),
            ),
          ),
        ),
      );
    }),
  );
}

void main() {
  testWidgets('guardar deja la pantalla anterior montada', (tester) async {
    final guardados = <String>[];
    await tester.pumpWidget(_app(popEnCallback: false, guardados: guardados));

    await tester.tap(find.text('PANTALLA BASE'));
    await tester.pumpAndSettle();

    final botonGuardar = find.text('Guardar cambios');
    expect(botonGuardar, findsOneWidget, reason: 'el sheet no abrió');

    await tester.tap(botonGuardar);
    await tester.pumpAndSettle();

    // Lo que fallaba: la pila quedaba vacía y no había nada que pintar.
    expect(find.text('PANTALLA BASE'), findsOneWidget,
        reason: 'la pantalla de debajo se cerró: pila vacía, pantalla en blanco');
    // Y el guardado sí ocurrió: el bug no era de datos.
    expect(guardados, ['m']);
    // El sheet se cerró solo.
    expect(botonGuardar, findsNothing, reason: 'el sheet debe cerrarse');
  });

  testWidgets('un llamador que popea REPRODUCE el blanco', (tester) async {
    // El test que da valor al anterior: si el doble pop no rompiera nada, el
    // primero pasaría sin que la convención existiera.
    final guardados = <String>[];
    await tester.pumpWidget(_app(popEnCallback: true, guardados: guardados));

    await tester.tap(find.text('PANTALLA BASE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();

    // Dos pops: se va el sheet y se va la pantalla.
    expect(find.text('PANTALLA BASE'), findsNothing,
        reason: 'si esto sigue montado, el doble pop ya no rompe y el test de '
            'arriba no prueba nada');
  });

  testWidgets('cerrar sin guardar tampoco vacía la pila', (tester) async {
    final guardados = <String>[];
    await tester.pumpWidget(_app(popEnCallback: false, guardados: guardados));

    await tester.tap(find.text('PANTALLA BASE'));
    await tester.pumpAndSettle();
    // Descartar el sheet tocando fuera.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('PANTALLA BASE'), findsOneWidget);
    expect(guardados, isEmpty, reason: 'cerrar sin guardar no guarda');
  });
}
