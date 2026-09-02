// ─────────────────────────────────────────────────────────────────────────────
// UNIDADES: seis importes, uno a uno — o los seis de una
//
// El caso normal es que los seis eventos valgan lo mismo (se pone un valor de
// referencia y se ajustan dos o tres). Antes, poner $50 en los seis eran seis
// ediciones, y la caja "no respondía": el editor era estático y creaba
// TextEditingController nuevos en cada tecla (con un addListener que forzaba el
// rebuild), así que perdía el foco y se comía el 2º dígito.
//
// Ahora UnitsEditor tiene estado propio: los controllers viven en su State
// (initState/dispose) y no se recrean; y hay "Aplicar a todos".
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/screens/presets/game_presets_screen.dart';

BetModuleInstance _unitsMod() =>
    BetModuleInstance.defaultFor(BetModuleType.units, const ['a', 'b'], id: 'u1');

/// Anfitrión con estado, como el editor de prediseñadas real: al `onUpdate`
/// reconstruye UnitsEditor con el nuevo cfg (misma key) — que es justo donde el
/// editor viejo perdía los controllers.
class _Host extends StatefulWidget {
  const _Host();
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late BetModuleInstance cfg = _unitsMod();
  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: UnitsEditor(
              key: const ValueKey('u'),
              cfg: cfg,
              t: GolfTheme.classic,
              onUpdate: (c) => setState(() => cfg = c),
            ),
          ),
        ),
      );
}

Future<void> _montar(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const _Host());
  await tester.pump();
}

void main() {
  testWidgets('1 · "Aplicar a todos" pone el mismo importe en los seis',
      (tester) async {
    await _montar(tester);
    // El primer TextField es el de "mismo valor para todos".
    await tester.enterText(find.byType(TextField).first, '25');
    await tester.tap(find.text('Aplicar a todos'));
    await tester.pump();
    final host = tester.state<_HostState>(find.byType(_Host));
    for (final e in UnitEventType.values) {
      expect(host.cfg.units.valueFor(e), 25, reason: e.label);
    }
    expect(host.cfg.units.isUniform, isTrue);
  });

  testWidgets('2 · un importe de dos cifras entra, llega al config y se conserva',
      (tester) async {
    await _montar(tester);
    // Los seis campos de evento van tras el de "todos": birdie es el índice 1.
    final birdie = find.byType(TextField).at(1);
    await tester.enterText(birdie, '80');
    await tester.pump(); // onUpdate → el Host reconstruye UnitsEditor
    final host = tester.state<_HostState>(find.byType(_Host));
    expect(host.cfg.units.valueFor(UnitEventType.birdie), 80,
        reason: 'el valor tecleado llega al config');
    // El campo NO se reinició tras el rebuild (el bug recreaba el controller).
    expect(tester.widget<TextField>(birdie).controller!.text, '80');
  });

  test('3 · guarda del arreglo: estado propio, sin builder estático', () {
    final src = File('lib/screens/presets/game_presets_screen.dart')
        .readAsStringSync();
    expect(src, contains('class UnitsEditor extends StatefulWidget'));
    // Los controllers los POSEE el State (se crean en initState, se liberan en
    // dispose): esa es la diferencia con el editor que los recreaba en cada build.
    expect(src,
        contains('late final Map<UnitEventType, TextEditingController> _ctrls'));
    expect(src, contains('for (final c in _ctrls.values)'));
    expect(src.contains('static List<Widget> _unitsWidgets'), isFalse,
        reason: 'volver al builder estático reintroduce el foco perdido');
  });
}
