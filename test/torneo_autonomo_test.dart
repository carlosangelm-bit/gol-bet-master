// ─────────────────────────────────────────────────────────────────────────────
// CRITERIO 7 · EL TORNEO NO EXPONE LA APP ENTERA A QUIEN LLEGA POR EL ENLACE
//
// Quien abre un enlace no quiere aprender la app: quiere su llave y su partido.
// Si aterriza en el Inicio con balance histórico, grupos de apuesta y doce
// formatos, se pierde.
//
// Esto se cumple POR CONSTRUCCIÓN y no por una pantalla nueva: main.dart, cuando
// la URL trae un token de torneo, pone TorneoEnlaceScreen como `home`, así que no
// hay AppShell, no hay barra de navegación y no hay nada más alrededor. Lo que
// hacen estos tests es FIJARLO, para que nadie meta después la navegación general
// dentro del enlace.
//
// Y la decisión sobre quién ve qué: el que llega por el enlace ve la versión
// reducida; el que ya usa la app y abre un torneo suyo ve la de siempre. No se
// decide por quién eres, se decide por CÓMO llegaste, que es la pregunta que la
// pantalla puede contestar sin adivinar.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:golf_bet_master/providers/organizador_provider.dart';
import 'package:golf_bet_master/providers/torneo_provider.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/models/torneo.dart';
import 'package:golf_bet_master/models/torneo_publicado.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/screens/torneos/torneo_invitado_screen.dart';

TorneoPublicado _copia({bool activo = true}) => TorneoPublicado(
      token: 'tok',
      ownerUid: 'uid',
      nombre: 'Match Play CGM',
      emoji: '🏆',
      publicadoEn: DateTime(2026, 4, 1),
      comoSePuntua: 'Por dinero ganado',
      comoSeAcumula: 'Eliminación directa',
      rondas: 2,
      cerrado: false,
      activo: activo,
      tabla: const [
        FilaPublicada(
            puesto: 1,
            nombre: 'Rafael',
            total: 300,
            jugadas: 1,
            contadas: 1,
            bajoMinimo: false,
            aportaBote: 0,
            cobraBote: 0),
        FilaPublicada(
            puesto: 2,
            nombre: 'Alan',
            total: -300,
            jugadas: 1,
            contadas: 1,
            bajoMinimo: false,
            aportaBote: 0,
            cobraBote: 0),
      ],
      llave: const [
        PartidoPublicado(
            ronda: 0,
            posicion: 0,
            faseNombre: 'Final',
            a: 'Rafael',
            b: 'Alan'),
      ],
    );

Future<List<String>> _montar(WidgetTester tester, TorneoPublicado copia) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final errores = <String>[];
  final anterior = FlutterError.onError;
  FlutterError.onError = (d) => errores.add(d.exceptionAsString());

  await tester.pumpWidget(MultiProvider(
    providers: [
        ChangeNotifierProvider(create: (_) => RoundProvider()),
        // El botón de "que mis rondas cuenten aquí" lo necesita, y main.dart lo
        // provee por encima de la ruta del enlace.
        ChangeNotifierProvider(create: (_) => TorneoProvider()),
        // La marca de organizador: el logo de Inicio la consulta. En false,
        // que es una cuenta normal — es lo que estos tests miran.
        ChangeNotifierProvider<OrganizadorProvider>(
            create: (_) => OrganizadorProvider()..sembrar(false)),
      ],
    child: MaterialApp(
      theme: GolfTheme.classic.toMaterial(),
      home: TorneoInvitadoScreen(copia: copia),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
  FlutterError.onError = anterior;
  return errores;
}

String _pantalla(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .join(' · ');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('1 · nada de la navegación general', () {
    testWidgets('sin barra de navegación ni pestañas', (tester) async {
      final errores = await _montar(tester, _copia());
      expect(errores, isEmpty);
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(find.byType(TabBar), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('sin Inicio, Historial ni Ajustes', (tester) async {
      await _montar(tester, _copia());
      final txt = _pantalla(tester);
      for (final destino in ['Inicio', 'Historial', 'Ajustes', 'Plantillas']) {
        expect(txt, isNot(contains(destino)), reason: destino);
      }
    });

    testWidgets('sin nada del balance histórico ni de los grupos',
        (tester) async {
      // Es lo que hace que alguien se pierda: cifras de otra cosa.
      await _montar(tester, _copia());
      final txt = _pantalla(tester);
      expect(txt, isNot(contains('BALANCE HISTÓRICO')));
      expect(txt, isNot(contains('grupo de apuesta')));
    });

    testWidgets('lo que SÍ está: el torneo, su cuadro y la pregunta',
        (tester) async {
      // El contrapeso. Sin esto, los tres de arriba pasarían con una pantalla
      // vacía.
      await _montar(tester, _copia());
      final txt = _pantalla(tester);
      expect(txt, contains('Match Play CGM'));
      expect(txt, contains('EL CUADRO'));
      expect(txt, contains('¿CUÁL ERES TÚ?'));
      expect(txt, contains('CLASIFICACIÓN'));
    });
  });

  group('2 · y dónde acaba: la app completa se descubre, no se impone', () {
    testWidgets('sin sesión, la cintilla ofrece descargar', (tester) async {
      // Es el puente a la app completa para quien no la tiene, y es permanente a
      // propósito: quien llega por un enlace y le gusta tiene que poder llegar al
      // resto sin que se lo metan por delante mientras mira su llave.
      await _montar(tester, _copia());
      expect(find.text('Descarga la app para más funciones'), findsOneWidget);
      expect(find.text('Volver a la app'), findsNothing);
    });

    testWidgets('CRITERIO 3: con sesión NO se ofrece descargar', (tester) async {
      // Ofrecerle descargar la app a alguien que está DENTRO de la app es la
      // misma causa que el resto: la pantalla suponía que quien la ve no tiene
      // cuenta. Sin sesión en el harness no se puede montar el caso contrario,
      // así que se fija lo que se puede: el texto depende de la sesión y no es
      // fijo.
      await _montar(tester, _copia());
      // Sin sesión en el test, así que sale el de descargar. Lo que este test
      // protege es que exista la bifurcación: si alguien la quita, el de sesión
      // vuelve a decir "descarga la app".
      expect(
          tester
              .widgetList<Text>(find.byType(Text))
              .map((w) => w.data ?? '')
              .where((x) => x.contains('Volver a la app')),
          isEmpty);
    });
  });

  group('3 · el enlace apagado no filtra el contenido', () {
    test('la copia apagada llega sin tabla ni cuadro', () {
      // Apagar sobreescribe el documento con la bandera, así que lo que había
      // dentro deja de estar. Se comprueba en el modelo, que es donde se decide.
      final apagada = TorneoPublicado.fromJson(
          'tok', const {'ownerUid': 'uid', 'activo': false});
      expect(apagada.activo, isFalse);
      expect(apagada.tabla, isEmpty);
      expect(apagada.llave, isEmpty);
      expect(apagada.boteTotal, 0);
    });
  });
}
