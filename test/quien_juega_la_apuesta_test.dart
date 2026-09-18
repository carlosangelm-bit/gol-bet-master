// ─────────────────────────────────────────────────────────────────────────────
// DOS OPCIONES IGUALES, Y UNA LISTA QUE NO SE PUEDE EDITAR
//
// Paso 5 · Detalle → Editar Nassau, con cuatro jugadores:
//
//     ○ Todos los de la partida (4)
//       …Quien se sume después entra automáticamente.
//     ● Solo 4 jugadores seleccionados
//       …La lista es parte del acuerdo y no cambia.
//
//     «No tiene mucho sentido que muestre «quién juega la apuesta» y «todos los
//      de la partida» / «solo los 4 jugadores» cuando es lo mismo. No permite
//      seleccionar menos jugadores.»
//
// Dos cosas:
//
//   1 · Con 4 de 4 las dos opciones describen el mismo conjunto. Lo que las
//       separa es el futuro —quien se sume después— y eso no se lee.
//   2 · «Solo los seleccionados» no deja seleccionar: `newParticipants` sale de
//       `_current.participantIds` y nada en la hoja los toca.
//
// Y una tercera que no estaba en el reporte: en el asistente, lo que se elija
// aquí se DESCARTA. `_sincronizarModulos` reconstruye el módulo desde
// `_quienJuega` —el paso 6— y `conservandoAjustes` solo conserva las configs.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/models/bet_recipe.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/widgets/bet_module_edit_sheet.dart';

const _cuatro = ['cam', 'kawa', 'jose', 'aam'];

BetGroup _grupo(List<BetModuleInstance> mods) => BetGroup(
      id: 'g',
      name: 'G',
      format: PartidaFormat.oneVsOne,
      playerIds: _cuatro,
      modules: mods,
    );

BetModuleInstance _nassau({List<String>? participantes, BetScope? scope}) =>
    BetModuleInstance(
      id: 'flujo_puntos',
      type: BetModuleType.nassau,
      name: 'Nassau',
      participantIds: participantes ?? _cuatro,
      scope: scope,
      nassauConfig: const NassauConfig(
          frontValue: 50, backValue: 50, totalValue: 100),
    );

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  group('1 · la tercera superficie, y por qué perdía', () {
    test('CLAVE: el asistente RECONSTRUYE el módulo desde el paso 6', () {
      // `conservandoAjustes` conserva las CONFIGS y nada más. Así que el módulo
      // que sale del sincronizado lleva los participantes de
      // `_participantesDe(cuenta)` —el paso 6— y lo elegido en la hoja se
      // pierde. Esto NO se cambia: que el paso 6 sea la fuente está bien.
      final delSheet = _nassau(
          participantes: const ['cam', 'kawa'],
          scope: BetScope.pair('cam', 'kawa'));
      final delPaso6 = _nassau();

      final resultado = BetRecipe.conservandoAjustes(delSheet, delPaso6);
      expect(resultado.participantIds, _cuatro);
      expect(resultado.scope, isNull);
      expect(resultado.nassau.frontValue, 50, reason: 'las configs sí');
    });

    test('CLAVE (criterio 3): por eso la hoja escribe en el paso 6', () {
      // Lo que se arregla es el otro extremo: al guardar, la hoja lleva su
      // «quién juega» a `_quienJuega`, que es de donde el sincronizado
      // reconstruye. Así las tres superficies leen del mismo sitio.
      //
      // Se comprueba la regla que decide, que es la que puede equivocarse: con
      // alcance ABIERTO se borra la entrada en vez de congelar los de hoy.
      final abierta = _nassau(scope: const BetScope.everyone());
      expect(abierta.effectiveScope.isEveryone, isTrue,
          reason: 'quien se sume después entra: no se guarda lista');

      final acotada = _nassau(
          participantes: const ['cam', 'kawa', 'jose'],
          scope: BetScope.subset(const ['cam', 'kawa', 'jose']));
      expect(acotada.effectiveScope.isEveryone, isFalse);
      expect(acotada.participantIds, ['cam', 'kawa', 'jose'],
          reason: 'y esta lista es la que va a `_quienJuega`');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('2 · la hoja, en pantalla, con cuatro jugadores', () {
    BetModuleInstance? guardado;

    Future<String> montar(
      WidgetTester tester, {
      required BetModuleInstance mod,
    }) async {
      guardado = null;
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BetModuleEditSheet(
            group: _grupo([mod]),
            mod: mod,
            t: GolfTheme.dark,
            embedded: true,
            players: [
              for (final p in _cuatro) Player(id: p, name: p.toUpperCase()),
            ],
            onSave: (m) => guardado = m,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .join('  ‖  ');
    }

    testWidgets('CLAVE (criterio 2): la lista se puede editar', (tester) async {
      await montar(tester, mod: _nassau());

      // Se elige «solo estos» y se quita a uno.
      // El título de la opción, que es lo que se toca. `textContaining` casa
      // también con la consecuencia y con el aviso de abajo.
      await tester.tap(find.textContaining('Solo ').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('AAM'));
      await tester.pumpAndSettle();

      final texto = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .join('  ‖  ');
      expect(texto, contains('3 de 4'));

      // ── Y LO QUE SE GUARDA, que es lo que la ronda se lleva ────────────
      //
      // Sin esto la prueba solo miraba la etiqueta: un contrapeso que hacía
      // guardar `_current.participantIds` —la lista que ENTRÓ— pasaba en verde
      // con el rótulo diciendo «3 de 4».
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();
      expect(guardado, isNotNull);
      expect(guardado!.participantIds, ['cam', 'kawa', 'jose']);
      expect(guardado!.effectiveScope.isEveryone, isFalse);
    });

    testWidgets('CONTRAPESO: no se puede bajar de dos', (tester) async {
      await montar(tester, mod: _nassau());
      await tester.tap(find.textContaining('Solo ').first);
      await tester.pumpAndSettle();

      // Se quitan dos: quedan dos, y el tercero ya no se deja quitar.
      for (final n in ['AAM', 'JOSE']) {
        await tester.tap(find.text(n));
        await tester.pumpAndSettle();
      }
      var texto = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .join('  ‖  ');
      expect(texto, contains('Hacen falta dos como mínimo'));

      await tester.tap(find.text('KAWA'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();
      expect(guardado!.participantIds, ['cam', 'kawa'],
          reason: 'el tercer toque no quita a nadie');
    });

    testWidgets('CLAVE (criterio 1): las dos opciones dicen en qué se '
        'diferencian', (tester) async {
      final texto = await montar(tester, mod: _nassau());
      // Lo que las separa es el futuro, y ahora lo dicen las dos.
      expect(texto, contains('Quien se sume después entra'));
      expect(texto, contains('Quien se sume después NO entra'));
    });
  });
}
