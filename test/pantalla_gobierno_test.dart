// ─────────────────────────────────────────────────────────────────────────────
// LA PANTALLA, GOBERNADA DESDE UN SOLO SITIO
//
// «La función está partida en dos: el diseño en el portal, encender y apagar en
// la app. El organizador tiene que saltar entre dos superficies para gobernar
// una sola cosa.»
//
// Y la prueba de que ya causaba problemas: el color no llegó a la pared hasta
// republicar desde la app.
//
// ── La forma del fallo, que es la que hay que impedir ───────────────────────
//
// La tele no lee el torneo: lee una INSTANTÁNEA. En ella viajan TRES cosas —la
// tabla, el inventario de patrocinio y la identidad— y cada una tiene que
// tener quien la republique. La tabla ya lo tenía: al cerrar una ronda. Las
// otras dos no, y las dos se editan desde el portal.
//
// El caso del patrocinio nadie lo había reportado y estaba igual de roto desde
// antes: cambiar el banner de cabecera dejaba la pared con el de la semana
// pasada. Hay que mirar dos pantallas a la vez para verlo.
//
// Así que lo que más se comprueba aquí no es que republique: es que NADA que
// viaje en la instantánea se quede sin camino de vuelta.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:golf_bet_master/core/ancho.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/models/leaderboard_publico.dart';
import 'package:golf_bet_master/models/patrocinio.dart';
import 'package:golf_bet_master/models/torneo.dart';
import 'package:golf_bet_master/providers/auth_provider.dart';
import 'package:golf_bet_master/providers/betting_group_provider.dart';
import 'package:golf_bet_master/providers/handicap_provider.dart';
import 'package:golf_bet_master/providers/player_provider.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/providers/user_profile_provider.dart';
import 'package:golf_bet_master/screens/torneos/torneos_screen.dart';
import 'package:golf_bet_master/providers/perfil_provider.dart';
import 'package:golf_bet_master/providers/torneo_provider.dart';
import 'package:golf_bet_master/screens/organizador/pantalla_seccion.dart';
import 'package:golf_bet_master/screens/torneos/tele_sheet.dart';
import 'package:golf_bet_master/services/tele_service.dart';

Torneo _torneo({
  bool encendida = false,
  bool cerrado = false,
  IdentidadDeTorneo identidad = const IdentidadDeTorneo(),
  InventarioProyectado inventario = const InventarioProyectado(),
}) =>
    Torneo(
      id: 't1',
      nombre: 'Copa de Primavera',
      participantes: const ['ana', 'beto'],
      identidad: identidad,
      inventario: inventario,
      cerrado: cerrado,
      tokenTele: encendida ? 'tv_abc' : null,
      teleDesde: encendida ? DateTime(2026, 8, 30) : null,
    );

Future<void> _montarSeccion(WidgetTester tester, Torneo t) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => TorneoProvider()..sembrar([t])),
      ChangeNotifierProvider(create: (_) => PerfilProvider()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: LayoutBuilder(
          builder: (_, c) => PantallaSeccion(
              torneo: t, ancho: anchoDe(c.maxWidth), t: GolfTheme.classic),
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('1 · el portal lo gobierna todo, con el MISMO widget', () {
    testWidgets('CLAVE: la sección trae el bloque de encender y apagar',
        (tester) async {
      // No una copia: el mismo BloqueTele que usa la app. Dos copias serían dos
      // sitios donde arreglar el mismo fallo, que es cómo se llegó aquí.
      await _montarSeccion(tester, _torneo());
      expect(find.byType(BloqueTele), findsOneWidget);
    });

    testWidgets('CLAVE: con la pantalla encendida, el enlace está aquí',
        (tester) async {
      // El enlace copiable era lo que obligaba a volver a la app.
      await _montarSeccion(tester, _torneo(encendida: true));
      final textos = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .join(' · ');
      expect(textos, contains('Apagar la pantalla'));
      expect(textos, contains('Copiar enlace de la pantalla'));
      expect(find.text(enlaceDeTele('tv_abc')), findsOneWidget);
    });

    testWidgets('y apagada, el botón de encender', (tester) async {
      await _montarSeccion(tester, _torneo());
      final textos = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .join(' · ');
      expect(textos, contains('Encender la pantalla'));
    });

    testWidgets('CONTRAPESO: y el diseño no se ha ido de aquí', (tester) async {
      // Meter el gobierno no puede haberse llevado por delante lo que ya
      // estaba: las cuatro plantillas siguen elegibles en la misma sección.
      await _montarSeccion(tester, _torneo());
      for (final p in PlantillasDeTele.todas) {
        expect(find.text(p.nombre), findsOneWidget, reason: p.clave);
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('2 · un cambio llega a la pared sin ir a otra superficie', () {
    test('CLAVE: con la pantalla encendida, hay que republicar', () {
      // Es la decisión, y es pura: lo que decide si el cambio sale de aquí.
      expect(Tele.debeRefrescar(_torneo(encendida: true)), isTrue);
    });

    test('CLAVE: apagada NO se enciende sola al guardar un color', () {
      // Guardar un color no puede empezar a proyectar en una pared. Es la
      // misma línea que separa "encender" de "refrescar".
      expect(Tele.debeRefrescar(_torneo()), isFalse);
    });

    test('y un torneo cerrado no se toca: una instantánea final es final', () {
      expect(Tele.debeRefrescar(_torneo(encendida: true, cerrado: true)),
          isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 3 · LO QUE VIAJA, Y QUE NADA SE QUEDE SIN CAMINO
  //
  // El test que describe la FORMA del fallo en vez de un caso suyo. Si mañana
  // se añade un cuarto campo a la instantánea y se olvida su republicación,
  // el síntoma será el de siempre: se cambia algo, se mira la pared, y no
  // pasa nada. Esto no lo puede impedir del todo, pero deja escrito qué viaja.
  // ───────────────────────────────────────────────────────────────────────────
  group('3 · las tres cosas que viajan en la instantánea', () {
    LeaderboardPublico deTorneo(Torneo t) => Tele.instantanea(
          token: 'tv_abc',
          ownerUid: 'uid',
          torneo: t,
          tabla: tablaDe(t, const []),
          cuando: DateTime(2026, 8, 30),
        );

    test('CLAVE: la identidad viaja — el caso reportado', () {
      final lb = deTorneo(_torneo(
          encendida: true,
          identidad: const IdentidadDeTorneo(
              plantilla: 'corporativa', profundidad: 2, acento: 0xFF4FA8FF)));
      expect(lb.identidad.plantilla, 'corporativa');
      expect(lb.identidad.profundidad, 2);
      expect(lb.identidad.acento, 0xFF4FA8FF);
      // Y llega hasta el color que se pinta, que es lo único que se ve.
      expect(lb.identidad.piel.fondo,
          PlantillasDeTele.corporativa.fondos[2]);
    });

    test('CLAVE: el inventario también — el caso que nadie reportó', () {
      final lb = deTorneo(_torneo(
        encendida: true,
        inventario: const InventarioProyectado(
          cabecera: PiezaDePatrocinio(
              etiqueta: 'PATROCINADOR OFICIAL',
              titular: 'Los del sábado',
              logoUrl: 'https://x/l.png'),
        ),
      ));
      expect(lb.inventario.cabecera?.titular, 'Los del sábado');
    });

    test('y la tabla, que ya se refrescaba sola al cerrar una ronda', () {
      final lb = deTorneo(_torneo(encendida: true));
      expect(lb.nombre, 'Copa de Primavera');
      expect(lb.tabla, isNotEmpty, reason: 'los inscritos, aunque no jugaran');
    });

    test('CONTRAPESO: y el dinero sigue sin viajar', () {
      // El gobierno nuevo no puede haber abierto la puerta que este documento
      // existe para tener cerrada.
      final json = deTorneo(_torneo(encendida: true)).toJson().toString();
      for (final prohibido in ['bote', 'balance', 'recaudado', 'entrada']) {
        expect(json.contains(prohibido), isFalse, reason: prohibido);
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 4 · CÓMO SE LLEGA AL PORTAL
  //
  // «No hay ningún enlace en la app: hoy se entra escribiendo /organizador/{id}
  // con un id que solo se puede sacar de Firestore. Un organizador no puede
  // llegar a su propio portal.»
  //
  // Es la forma que más veces se ha repetido en este proyecto, otra vez: la
  // cosa existe, la capa siguiente no la alcanza. Se construyó el portal, se
  // construyó su ruta, y no había puerta.
  // ───────────────────────────────────────────────────────────────────────────
  group('4 · el portal tiene puerta', () {
    testWidgets('CLAVE: la pantalla del torneo lleva al portal',
        (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final t = _torneo();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => RoundProvider()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => PlayerProvider()..sembrar(const [])),
          ChangeNotifierProvider(create: (_) => HandicapProvider()),
          ChangeNotifierProvider(create: (_) => UserProfileProvider()),
          ChangeNotifierProvider(create: (_) => BettingGroupProvider()),
          ChangeNotifierProvider(create: (_) => PerfilProvider()),
          ChangeNotifierProvider(create: (_) => TorneoProvider()..sembrar([t])),
        ],
        child: MaterialApp(home: TorneoTablaScreen(torneo: t)),
      ));
      await tester.pump(const Duration(milliseconds: 150));

      // Y junto al de compartir, que es donde se busca: las dos cosas que se
      // hacen con un torneo hacia fuera.
      expect(find.byTooltip('Portal de organizador'), findsOneWidget);
      expect(find.byTooltip('Compartir'), findsOneWidget);
    });
  });
}
