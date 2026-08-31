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
import 'package:golf_bet_master/models/resultados_del_torneo.dart';
import 'package:golf_bet_master/models/round_result.dart';
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
              torneo: t,
              ancho: anchoDe(c.maxWidth),
              t: GolfTheme.classic,
              tabla: tablaDe(t, const []),
              lista: true),
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

  // ───────────────────────────────────────────────────────────────────────────
  // 5 · REPUBLICAR NO PIERDE NADA
  //
  // «Ya van tres reconstrucciones donde un campo se cae: el par dos veces, y
  // ahora el nombre. Un test que compruebe que republicar no pierde nada
  // —comparando el documento entero, no campo a campo— cerraría la familia.»
  //
  // Eso es lo que hace este grupo, y por eso compara DOCUMENTOS y no campos:
  // añadir un campo nuevo mañana no exige acordarse de añadir su aserción. Si
  // se cae, el documento deja de ser igual.
  //
  // El fallo concreto fue peor que los nombres. Al republicar desde el portal
  // la tabla se reconstruyó llamando a `tablaDe` con los resultados PROPIOS y
  // sin el directorio: en un torneo de 153 inscritos, donde casi todas las
  // rondas son de otros, salió una tabla entera a cero. Los guiones eran el
  // síntoma que se veía.
  // ───────────────────────────────────────────────────────────────────────────
  group('5 · republicar deja el documento igual, salvo la fecha', () {
    LeaderboardPublico publicar(Torneo t, TablaDelTorneo tabla, DateTime cuando) =>
        Tele.instantanea(
            token: 'tv_abc',
            ownerUid: 'uid',
            torneo: t,
            tabla: tabla,
            cuando: cuando);

    /// El documento sin la fecha, que es lo ÚNICO que puede cambiar.
    Map<String, dynamic> sinFecha(LeaderboardPublico lb) {
      final j = Map<String, dynamic>.from(lb.toJson());
      j.remove('publicadoEn');
      return j;
    }

    Torneo lleno() => _torneo(
        encendida: true,
        identidad: const IdentidadDeTorneo(
            plantilla: 'corporativa', profundidad: 1, acento: 0xFF4FA8FF),
        inventario: const InventarioProyectado(
            cabecera: PiezaDePatrocinio(
                etiqueta: 'PATROCINADOR OFICIAL',
                titular: 'Moving health into the future',
                logoUrl: 'https://x/l.png',
                cta: 'Visítanos')));

    TablaDelTorneo tablaBuena(Torneo t) => tablaCompletaDe(
          torneo: t,
          propios: const [],
          publicados: const [],
          nombres: const {'ana': 'Ana Robles', 'beto': 'Beto Lara'},
        );

    // ── EL INVENTARIO DE CLAVES ──────────────────────────────────────────
    //
    // Es lo que hace que este grupo cierre la familia en vez de este caso.
    //
    // La primera versión comparaba el documento de antes con el de después, y
    // TRES contrapesos no mordieron: quitar una clave del `toJson` la quitaba
    // de los dos lados por igual. Comparar dos cosas construidas igual solo
    // caza la NO-DETERMINACIÓN; para cazar la OMISIÓN hace falta una
    // referencia de fuera, y esta es la lista escrita a mano.
    //
    // Añadir un campo obliga a tocar esta lista, que es la idea: es la única
    // línea del proyecto donde alguien decide qué se proyecta.
    const clavesDelDocumento = {
      'ownerUid', 'nombre', 'emoji', 'publicadoEn', 'comoSePuntua',
      'rondas', 'tabla', 'inventario', 'identidad',
    };
    // Una fila lleva SIEMPRE estas, y puede llevar las opcionales: la medida
    // se calla cuando es dinero, y el bajo par cuando el método no lo produce.
    const siempreEnUnaFila = {'puesto', 'nombre', 'jugadas'};
    const puedeLlevarUnaFila = {'medida', 'bajoPar'};

    test('CLAVE: el documento lleva TODAS sus claves, no las que queden', () {
      final doc = publicar(lleno(), tablaBuena(lleno()), DateTime(2026, 8, 30));
      expect(doc.toJson().keys.toSet(), equals(clavesDelDocumento));
    });

    test('CLAVE: y cada fila las suyas', () {
      final doc = publicar(lleno(), tablaBuena(lleno()), DateTime(2026, 8, 30));
      for (final f in doc.toJson()['tabla'] as List) {
        final claves = (f as Map).keys.map((k) => '$k').toSet();
        expect(claves, containsAll(siempreEnUnaFila));
        // Y nada de fuera del catálogo: una clave nueva que se cuele en el
        // documento público es lo que hay que ver antes de proyectarla.
        expect(claves.difference(siempreEnUnaFila.union(puedeLlevarUnaFila)),
            isEmpty);
      }
    });

    test('CLAVE: y el viaje por Firestore no se come ninguna', () {
      // Una clave que se escribe pero no se lee entra por aquí: al volver a
      // serializar, el documento sale más corto que el que se guardó.
      final ida = publicar(lleno(), tablaBuena(lleno()), DateTime(2026, 8, 30));
      final leido = LeaderboardPublico.fromJson('tv_abc', ida.toJson());
      expect(sinFecha(leido), equals(sinFecha(ida)));
    });

    test('CLAVE: cambiar SOLO el diseño no toca nada más', () {
      // El caso reportado. Con el inventario de claves de arriba delante, esta
      // comparación ya sí significa algo: sabemos que el documento está
      // entero, y esto comprueba que republicar no lo mueve.
      final antes = lleno();
      final tabla = tablaBuena(antes);
      final doc1 = publicar(antes, tabla, DateTime(2026, 8, 30, 10));

      final despues = antes.copyWith(
          identidad: const IdentidadDeTorneo(plantilla: 'atardecer'));
      final doc2 = publicar(despues, tabla, DateTime(2026, 8, 30, 11));

      final a = sinFecha(doc1)..remove('identidad');
      final b = sinFecha(doc2)..remove('identidad');
      expect(b, equals(a), reason: 'solo el diseño podía cambiar');
      expect(doc2.identidad.plantilla, 'atardecer');
      expect(doc1.identidad.plantilla, isNot('atardecer'));
    });

    test('CLAVE: y los NOMBRES siguen ahí — el guion de la pared', () {
      // 153 filas con `—`. El nombre de un inscrito que todavía no ha jugado
      // NO está en ningún resultado: solo en el directorio.
      final doc =
          publicar(lleno(), tablaBuena(lleno()), DateTime(2026, 8, 30));
      expect(doc.tabla.map((f) => f.nombre),
          containsAll(['Ana Robles', 'Beto Lara']));
      expect(doc.tabla.map((f) => f.nombre), isNot(contains('—')));
    });

    test('CONTRAPESO: sin el directorio salen los guiones, como salieron', () {
      // La reproducción exacta del fallo. Si esto NO diera guiones, el test de
      // arriba pasaría con cualquier implementación.
      final t = lleno();
      final sinDirectorio = tablaCompletaDe(
          torneo: t, propios: const [], publicados: const [], nombres: const {});
      final doc = publicar(t, sinDirectorio, DateTime(2026, 8, 30));
      expect(doc.tabla.map((f) => f.nombre), everyElement('—'),
          reason: 'es lo que se proyectó en la pared');
    });

    test('CLAVE: la receta une lo PROPIO con lo que publicaron otros', () {
      // El otro medio fallo, y el que de verdad vació la tabla: en un torneo
      // de 153 inscritos casi todas las rondas son de otra gente. Quedarse con
      // los resultados propios deja la clasificación a cero, con los guiones
      // como único síntoma visible.
      final t = lleno();
      final mia = _resultado('r_mia', 'ana', 'Ana Robles');
      final suya = _publicado('r_suya', 'beto', 'Beto Lara');

      final soloMias = tablaCompletaDe(
          torneo: t,
          propios: [mia],
          publicados: const [],
          nombres: const {'ana': 'Ana Robles', 'beto': 'Beto Lara'});
      final ambas = tablaCompletaDe(
          torneo: t,
          propios: [mia],
          publicados: [suya],
          nombres: const {'ana': 'Ana Robles', 'beto': 'Beto Lara'});

      int jugadasDe(TablaDelTorneo tb, String nombre) =>
          [...tb.filas, ...tb.bajoMinimo]
              .firstWhere((f) => f.nombre == nombre)
              .jugadas;

      expect(jugadasDe(soloMias, 'Beto Lara'), 0,
          reason: 'sin lo de otros, Beto no ha jugado nada');
      expect(jugadasDe(ambas, 'Beto Lara'), 1,
          reason: 'con lo de otros, su ronda cuenta');
      expect(jugadasDe(ambas, 'Ana Robles'), 1);
    });

    test('CONTRAPESO: una tabla vacía NO sustituye a una con gente', () {
      // El otro lado del fallo. Si la carga de lo que publicaron otros no ha
      // llegado, publicar borraría la pared en vez de dejarla como estaba.
      final vacia = tablaDe(
          Torneo(id: 't1', nombre: 'Copa', tokenTele: 'tv_abc'), const []);
      expect(vacia.sinListaDeParticipantes, isTrue);
      expect(Tele.debeRefrescar(lleno()), isTrue,
          reason: 'la pantalla SÍ está encendida: lo que frena es la tabla');
    });
  });
}

/// Un resultado propio: una ronda de [pid] marcada para el torneo.
RoundResult _resultado(String id, String pid, String nombre) => RoundResult(
      roundId: id,
      roundName: 'Sábado',
      courseName: 'Los Encinos',
      playedAt: DateTime(2026, 5, 10),
      holesPlayed: 18,
      parDeLaRonda: 72,
      playerIds: [pid],
      playerNames: {pid: nombre},
      balances: {pid: 100},
      pairBalances: const {},
      grossByPlayer: {pid: 74},
      netByPlayer: {pid: 70},
      torneoIds: const ['t1'],
    );

/// Lo mismo, pero como lo publica OTRO jugador del torneo.
ResultadoPublicado _publicado(String id, String pid, String nombre) =>
    ResultadoPublicado(
      resultado: _resultado(id, pid, nombre),
      jugadorId: pid,
      jugadorNombre: nombre,
    );
