// ─────────────────────────────────────────────────────────────────────────────
// LA FILA DE UNIDADES EN PANTALLA, CON DOS DUELOS DE IMPORTES DISTINTOS
//
// «Verificado en pantalla, con dos duelos de importes distintos.»
//
// Es el caso que hace imposible una cifra sola: Birdie único vale $100 contra
// RAFA y $25 contra CAV. La fila tiene que decir la verdad para los dos.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/screens/capture/capture_screen.dart';

Future<String> _pinta(WidgetTester tester,
    {required List<double> importes, bool activa = true}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: UnitRow(
          evt: UnitEventType.birdieUnico,
          isActive: activa,
          importes: importes,
          t: GolfTheme.dark,
          onToggle: () {},
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data ?? '')
      .join('  ‖  ');
}

void main() {
  testWidgets('CLAVE: con DOS importes distintos enseña el rango, no una cifra',
      (tester) async {
    // $25 contra CAV y $100 contra RAFA. Cualquiera de los dos números solo
    // sería mentira para el otro duelo.
    final txt = await _pinta(tester, importes: const [25.0, 100.0]);
    expect(txt, contains(r'$25–$100'));
    expect(txt, contains('Cada duelo tiene su importe'));
    // Y NO se promete uno solo.
    expect(txt.contains(r'Valor: $25'), isFalse);
    expect(txt.contains('se configura en la apuesta'), isFalse);
  });

  testWidgets('CLAVE: con UN solo importe lo dice a secas — ese sí es cierto',
      (tester) async {
    // Cuando todos los duelos coinciden, el número es verdad y un rango sería
    // ruido.
    final txt = await _pinta(tester, importes: const [100.0]);
    expect(txt, contains(r'$100'));
    expect(txt.contains('–'), isFalse);
    expect(txt.contains('Cada duelo tiene su importe'), isFalse);
  });

  testWidgets('CONTRAPESO: sin marcar, la fila no promete nada',
      (tester) async {
    final txt = await _pinta(tester, importes: const [25.0, 100.0], activa: false);
    expect(txt.contains(r'$'), isFalse,
        reason: 'el importe solo aparece en lo que se marcó');
  });

  testWidgets('CLAVE: quien no juega unidades no ve un cero inventado',
      (tester) async {
    final txt = await _pinta(tester, importes: const []);
    expect(txt, contains('—'));
    expect(txt.contains(r'$0'), isFalse);
  });
}
