// ─────────────────────────────────────────────────────────────────────────────
// QUITAR INSCRITOS EN BLOQUE
//
// «153 inscritos y 22 salidas: hay que bajar a 88. Sesenta y cinco fuera, y
// solo se puede de una en una.»
//
// Y no era solo lento. Tres síntomas de la misma causa —repetir una acción
// sobre una lista que se mueve debajo—:
//
//   1 · seis clics seguidos en la misma posición contaban UNO
//   2 · el aviso de «Deshacer» tapaba el botón de la fila siguiente
//   3 · no había forma de decir «estos veinte»
//
// La selección múltiple no los arregla uno a uno: los quita de raíz. Nada se
// mueve hasta confirmar, hay un solo aviso al final, y es una escritura.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:golf_bet_master/core/ancho.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/models/inscritos.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/torneo.dart';
import 'package:golf_bet_master/providers/player_provider.dart';
import 'package:golf_bet_master/providers/torneo_provider.dart';
import 'package:golf_bet_master/screens/organizador/inscritos_tabla.dart';
import 'package:golf_bet_master/services/player_service.dart';

List<String> _ids(int n) => [for (var i = 1; i <= n; i++) 'j$i'];

Torneo _torneo({int inscritos = 153}) => Torneo(
      id: 't1',
      nombre: 'Copa de Primavera',
      participantes: _ids(inscritos),
      siembra: _ids(inscritos),
    );

List<PlayerWithLink> _directorio(int n) => [
      for (var i = 1; i <= n; i++)
        PlayerWithLink(
            player: Player(id: 'j$i', name: 'Jugador $i', handicapBase: 12)),
    ];

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('1 · el modelo quita varios de una vez', () {
    test('CLAVE: sesenta y cinco fuera en una sola operación', () {
      // El caso literal: 153 inscritos, hay que bajar a 88.
      final t = _torneo();
      final fuera = _ids(153).skip(88).toSet();
      expect(fuera.length, 65);
      final nuevo = sinInscritos(t, fuera);
      expect(nuevo.participantes.length, 88);
      expect(nuevo.participantes, _ids(88));
    });

    test('CLAVE: y salen también de la SIEMBRA del cuadro', () {
      // Dejarlos ahí cruzaría a gente que ya no juega, igual que en singular.
      final nuevo = sinInscritos(_torneo(), _ids(153).skip(88).toSet());
      expect(nuevo.siembra.length, 88);
      expect(nuevo.siembra.any((p) => p == 'j100'), isFalse);
    });

    test('CLAVE: el orden de los que quedan NO cambia', () {
      // Es lo que hace que la lista sea reconocible después: el orden de
      // inscripción es un hecho de cuándo entró cada uno.
      final nuevo = sinInscritos(_torneo(inscritos: 10), {'j3', 'j7'});
      expect(nuevo.participantes,
          ['j1', 'j2', 'j4', 'j5', 'j6', 'j8', 'j9', 'j10']);
    });

    test('CONTRAPESO: quitar a quien no está no cambia nada', () {
      final t = _torneo(inscritos: 10);
      expect(identical(sinInscritos(t, {'nadie'}), t), isTrue);
      expect(identical(sinInscritos(t, const {}), t), isTrue);
    });

    test('y deshacer los devuelve al FINAL, que es donde entraron', () {
      final t = _torneo(inscritos: 10);
      final fuera = {'j3', 'j7'};
      final sin = sinInscritos(t, fuera);
      final vuelta = conInscritos(sin, fuera.toList());
      expect(vuelta.participantes.length, 10);
      expect(vuelta.participantes.last, anyOf('j3', 'j7'),
          reason: 'fingir que nunca salieron sería inventarse ese hecho');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('2 · en pantalla: marcar veinte y quitarlos de una vez', () {
    Future<TorneoProvider> montar(WidgetTester tester,
        {int inscritos = 153}) async {
      tester.view.physicalSize = const Size(1440, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final t = _torneo(inscritos: inscritos);
      final prov = TorneoProvider()..sembrar([t]);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(
              create: (_) =>
                  PlayerProvider()..sembrar(_directorio(inscritos))),
          ChangeNotifierProvider<TorneoProvider>.value(value: prov),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: LayoutBuilder(
              builder: (_, c) => InscritosTabla(
                  torneo: prov.torneos.first,
                  ancho: anchoDe(c.maxWidth),
                  t: GolfTheme.classic),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 200));
      return prov;
    }

    String texto(WidgetTester tester) => tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? '')
        .join(' · ');

    testWidgets('CLAVE: marcar VEINTE no quita a nadie por el camino',
        (tester) async {
      // El criterio 3, y el corazón del fallo: la lista NO se mueve mientras se
      // marca, así que veinte toques son veinte marcados.
      final prov = await montar(tester);
      final casillas = find.byIcon(Icons.check_box_outline_blank);
      expect(casillas, findsWidgets);

      for (var i = 0; i < 20; i++) {
        // SIEMPRE la primera casilla sin marcar. Es lo que hacía el reporte
        // —clics seguidos en la misma posición— y lo que contaba uno.
        await tester.tap(find.byIcon(Icons.check_box_outline_blank).first);
        await tester.pump();
      }

      expect(texto(tester), contains('20 marcados para quitar'));
      // Y ninguno ha salido todavía: marcar no guarda.
      expect(prov.torneos.first.participantes.length, 153);
    });

    testWidgets('CLAVE: y quitarlos es UNA acción, con su cifra',
        (tester) async {
      // El botón dice CUÁNTOS va a quitar antes de tocarlo: veinte marcados y
      // un botón que dice «Quitar» sin número deja al organizador contando.
      await montar(tester);
      for (var i = 0; i < 20; i++) {
        await tester.tap(find.byIcon(Icons.check_box_outline_blank).first);
        await tester.pump();
      }
      expect(find.text('Quitar 20'), findsOneWidget);

      // ── Y aquí acaba lo que un test de widget puede comprobar ────────────
      //
      // Tocarlo llama a `TorneoProvider.guardar`, que escribe en Firestore y
      // LANZA sin sesión: en el harness no hay ninguna. Lo que sí se comprueba
      // es que el fallo NO se lleva las marcas por delante — veinte toques no
      // se pierden porque la red falle—.
      await tester.tap(find.text('Quitar 20'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(texto(tester), contains('Siguen marcados'));
      expect(texto(tester), contains('20 marcados para quitar'),
          reason: 'las marcas se conservan para reintentar');
    });

    testWidgets('CLAVE: «Marcar los que se ven» respeta el BUSCADOR',
        (tester) async {
      // Es lo que convierte «quitar a los que no juegan» en dos gestos. Y marca
      // los VISIBLES: marcar los 153 sería lo contrario de lo que pide quien
      // acaba de filtrar.
      await montar(tester, inscritos: 30);
      await tester.enterText(find.byType(TextField), 'Jugador 1');
      await tester.pump(const Duration(milliseconds: 200));

      // Jugador 1, 10..19 → once.
      await tester.tap(find.textContaining('Marcar los '));
      await tester.pump();
      expect(texto(tester), contains('11 marcados para quitar'));
    });

    testWidgets('CONTRAPESO: sin nada marcado la barra no está',
        (tester) async {
      // Sin esto, una barra siempre visible pasaría los tests de arriba.
      await montar(tester);
      expect(texto(tester), isNot(contains('marcados para quitar')));
      expect(find.textContaining('Quitar '), findsNothing);
    });

    testWidgets('CLAVE: y desmarcar funciona — un toque de más no es fatal',
        (tester) async {
      await montar(tester);
      await tester.tap(find.byIcon(Icons.check_box_outline_blank).first);
      await tester.pump();
      expect(texto(tester), contains('1 marcado para quitar'));
      await tester.tap(find.byIcon(Icons.check_box_outlined).first);
      await tester.pump();
      expect(texto(tester), isNot(contains('marcado para quitar')));
    });

    testWidgets('CONTRAPESO: el aviso sale ABAJO y la barra ARRIBA',
        (tester) async {
      // Es el punto 2 del reporte: dos cosas peleándose por el mismo sitio.
      // La barra tiene que estar por encima de la primera fila.
      final prov = await montar(tester, inscritos: 30);
      await tester.tap(find.byIcon(Icons.check_box_outline_blank).first);
      await tester.pump();
      final barra = tester.getRect(find.text('1 marcado para quitar'));
      final primeraFila = tester.getRect(find.text('Jugador 1').first);
      expect(barra.bottom, lessThanOrEqualTo(primeraFila.top),
          reason: 'la barra no puede tapar ninguna fila');
      expect(prov.torneos.first.participantes.length, 30);
    });
  });
}
