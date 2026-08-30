// ─────────────────────────────────────────────────────────────────────────────
// EL PORTAL DE ORGANIZADOR — punto 1: el armazón y la tabla de inscritos
//
// Tres cosas se prueban aquí, y las tres son criterios del encargo:
//
//   2 · buscar, ordenar y editar sin salir de la tabla
//   3 · funciona en escritorio y se degrada a algo usable en móvil, POR ANCHO
//   4 · nada de lo que ya funciona se rompe
//
// El criterio 3 es el que decide si esto sirve. Un portal que solo funcione en
// escritorio deja al organizador sin nada el día del torneo, que es cuando está
// en el campo con el teléfono. Por eso los cortes son una función pura y con
// pruebas: para que nadie pueda convertirlos en `if (kIsWeb)` sin que salte.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/ancho.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/core/escuchas.dart';
import 'package:golf_bet_master/main.dart';
import 'package:golf_bet_master/models/inscritos.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/torneo.dart';
import 'package:golf_bet_master/providers/auth_provider.dart';
import 'package:golf_bet_master/providers/betting_group_provider.dart';
import 'package:golf_bet_master/providers/handicap_provider.dart';
import 'package:golf_bet_master/providers/perfil_provider.dart';
import 'package:golf_bet_master/providers/player_provider.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/providers/user_profile_provider.dart';
import 'package:golf_bet_master/providers/torneo_provider.dart';
import 'package:golf_bet_master/screens/organizador/inscritos_tabla.dart';
import 'package:golf_bet_master/screens/organizador/organizador_screen.dart';
import 'package:golf_bet_master/services/player_service.dart';
import 'package:provider/provider.dart';

PlayerWithLink _pw(String id, String nombre, double hcp) => PlayerWithLink(
    player: Player(id: id, name: nombre, handicapBase: hcp), link: null);

final _directorio = [
  _pw('p1', 'Luis Herrera', 12),
  _pw('p2', 'Ana Ruiz', 4),
  _pw('p3', 'Dani Sotó', 12),
  _pw('p4', 'Álvaro Núñez', 21),
];

Torneo _torneo({
  List<String>? participantes,
  List<String> siembra = const [],
  String id = 't1',
}) =>
    Torneo(
      id: id,
      nombre: 'Copa de Primavera',
      fuente: FuenteDeRondas.marcadas,
      metodo: MetodoDePuntuacion.posicion,
      participantes: participantes ?? const ['p1', 'p2', 'p3', 'p4'],
      siembra: siembra,
    );

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('1 · el layout sale del ANCHO, no de la plataforma', () {
    test('los tres tramos', () {
      expect(anchoDe(1440), Ancho.amplio);
      expect(anchoDe(1100), Ancho.amplio, reason: 'el corte entra en el tramo');
      expect(anchoDe(1099), Ancho.medio);
      expect(anchoDe(720), Ancho.medio);
      expect(anchoDe(719), Ancho.estrecho);
      expect(anchoDe(390), Ancho.estrecho, reason: 'un teléfono en el campo');
    });

    test('CLAVE: la misma URL sirve en las dos puntas', () {
      // Es el criterio 3. En el portátil de la casa club por la mañana y en el
      // teléfono desde el estacionamiento a mediodía.
      expect(anchoDe(1440).esTabla, isTrue);
      expect(anchoDe(390).esTabla, isFalse);
      expect(anchoDe(390).anchoDeContenido, lessThan(anchoDe(1440).anchoDeContenido));
    });

    test('las columnas accesorias solo caben en el tramo ancho', () {
      expect(anchoDe(1440).columnasCompletas, isTrue);
      expect(anchoDe(900).columnasCompletas, isFalse,
          reason: 'tabla sí, pero sin # ni acciones sueltas');
      expect(anchoDe(390).columnasCompletas, isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('2 · buscar', () {
    test('por trozo del nombre', () {
      final f = filasDeInscritos(_torneo(), _directorio, busca: 'ruiz');
      expect(f.map((x) => x.nombre), ['Ana Ruiz']);
    });

    test('CLAVE: ignora acentos y mayúsculas, como el resto del sistema', () {
      // Usa nombreComparable, la MISMA normalización que la importación por
      // pegado y el reparto de resultados. Dos normalizaciones distintas darían
      // un fallo silencioso: el nombre coincide para el ojo y no para el código.
      expect(filasDeInscritos(_torneo(), _directorio, busca: 'ALVARO').length, 1);
      expect(filasDeInscritos(_torneo(), _directorio, busca: 'sotó').length, 1);
      expect(filasDeInscritos(_torneo(), _directorio, busca: 'soto').length, 1);
    });

    test('sin coincidencias devuelve vacío, no todo', () {
      expect(filasDeInscritos(_torneo(), _directorio, busca: 'zzz'), isEmpty);
    });

    test('y sin búsqueda están todos', () {
      expect(filasDeInscritos(_torneo(), _directorio), hasLength(4));
    });
  });

  group('2 · ordenar', () {
    List<String> orden(OrdenDeInscritos o, {bool desc = false}) =>
        filasDeInscritos(_torneo(), _directorio, orden: o, descendente: desc)
            .map((f) => f.nombre)
            .toList();

    test('por inscripción es el orden en que los metió el organizador', () {
      expect(orden(OrdenDeInscritos.inscripcion),
          ['Luis Herrera', 'Ana Ruiz', 'Dani Sotó', 'Álvaro Núñez']);
    });

    test('por nombre, con los acentos donde tocan', () {
      // Álvaro va con la A, no al final: es lo que espera quien lo busca.
      expect(orden(OrdenDeInscritos.nombre).first, 'Álvaro Núñez');
    });

    test('por handicap, de menos a más', () {
      expect(orden(OrdenDeInscritos.handicap).first, 'Ana Ruiz');
      expect(orden(OrdenDeInscritos.handicap).last, 'Álvaro Núñez');
    });

    test('CLAVE: a igual handicap desempata el nombre', () {
      // Luis y Dani van los dos a 12. Sin desempate, reordenar barajaba a los
      // quince que van a 12 y parecía que cambiaban de sitio solos.
      final doceA = orden(OrdenDeInscritos.handicap).sublist(1, 3);
      final doceB = orden(OrdenDeInscritos.handicap).sublist(1, 3);
      expect(doceA, doceB);
      expect(doceA, ['Dani Sotó', 'Luis Herrera']);
    });

    test('invertir da la vuelta a la lista entera', () {
      expect(orden(OrdenDeInscritos.nombre, desc: true),
          orden(OrdenDeInscritos.nombre).reversed.toList());
    });
  });

  group('2 · el inscrito sin ficha', () {
    test('CLAVE: se ve, no desaparece', () {
      // Pasa de verdad: se borra una ficha del directorio y el id se queda
      // inscrito. Si la fila desapareciera, el recuento no cuadraría con la
      // lista guardada y sería una diferencia que nadie explica.
      final t = _torneo(participantes: const ['p1', 'fantasma']);
      final f = filasDeInscritos(t, _directorio);
      expect(f, hasLength(2));
      expect(f.last.huerfano, isTrue);
      expect(f.last.nombre, contains('no encontrada'));
    });

    test('y no se cuela en una búsqueda de otro', () {
      final t = _torneo(participantes: const ['p1', 'fantasma']);
      expect(filasDeInscritos(t, _directorio, busca: 'luis'), hasLength(1));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('3 · añadir y quitar', () {
    test('quitar lo saca de la lista', () {
      final t = sinInscrito(_torneo(), 'p2');
      expect(t.participantes, ['p1', 'p3', 'p4']);
    });

    test('CLAVE: y también del cuadro', () {
      // Dejarlo en la siembra cruzaba en el cuadro a alguien que ya no juega.
      final t = _torneo(siembra: const ['p1', 'p2', 'p3', 'p4']);
      expect(sinInscrito(t, 'p2').siembra, ['p1', 'p3', 'p4']);
    });

    test('quitar a quien no está devuelve el mismo objeto', () {
      // Así quien llama no comprueba nada y no se guarda una escritura idéntica.
      final t = _torneo();
      expect(identical(sinInscrito(t, 'nadie'), t), isTrue);
    });

    test('añadir respeta el orden y no duplica', () {
      final t = conInscritos(_torneo(participantes: const ['p1']), ['p2', 'p1']);
      expect(t.participantes, ['p1', 'p2']);
    });

    test('añadir solo a quien ya está devuelve el mismo objeto', () {
      final t = _torneo();
      expect(identical(conInscritos(t, ['p1', 'p2']), t), isTrue);
    });

    test('deshacer devuelve al FINAL, no a su sitio de antes', () {
      // El orden de inscripción es un hecho de cuándo entró cada uno; fingir
      // que nunca salió sería inventarse ese hecho.
      final quitado = sinInscrito(_torneo(), 'p1');
      expect(conInscritos(quitado, ['p1']).participantes,
          ['p2', 'p3', 'p4', 'p1']);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('4 · la tabla en pantalla, en las dos puntas', () {
    Future<void> montar(WidgetTester tester, Size tamano,
        {Torneo? torneo}) async {
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final t = torneo ?? _torneo();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(
              create: (_) => PlayerProvider()..sembrar(_directorio)),
          ChangeNotifierProvider(
              create: (_) => TorneoProvider()..sembrar([t])),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: LayoutBuilder(
              builder: (_, c) => InscritosTabla(
                  torneo: t, ancho: anchoDe(c.maxWidth), t: GolfTheme.classic),
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('en escritorio: tabla con cabeceras y los cuatro nombres',
        (tester) async {
      await montar(tester, const Size(1440, 900));
      expect(find.text('NOMBRE'), findsOneWidget);
      expect(find.text('HANDICAP'), findsOneWidget);
      expect(find.text('#'), findsOneWidget, reason: 'columna del tramo ancho');
      for (final n in ['Luis Herrera', 'Ana Ruiz', 'Dani Sotó', 'Álvaro Núñez']) {
        expect(find.text(n), findsOneWidget);
      }
    });

    testWidgets('CLAVE: en móvil no hay tabla, pero sí están todos',
        (tester) async {
      // El criterio 3. Degradarse no es desaparecer.
      await montar(tester, const Size(390, 844));
      expect(find.text('NOMBRE'), findsNothing);
      expect(find.text('#'), findsNothing);
      for (final n in ['Luis Herrera', 'Ana Ruiz', 'Dani Sotó', 'Álvaro Núñez']) {
        expect(find.text(n), findsOneWidget);
      }
      // Y el orden se puede cambiar igual, con chips en vez de cabeceras.
      //
      // Los TRES visibles sin arrastrar. Con la etiqueta larga, "Handicap" se
      // salía de los 390 px y solo aparecía al arrastrar — un control que hay
      // que descubrir arrastrando es un control que no está.
      for (final o in OrdenDeInscritos.values) {
        expect(find.text(o.labelCorto), findsOneWidget, reason: o.name);
      }
    });

    testWidgets('en tableta: tabla, pero sin las columnas accesorias',
        (tester) async {
      await montar(tester, const Size(900, 700));
      expect(find.text('NOMBRE'), findsOneWidget);
      expect(find.text('#'), findsNothing);
    });

    testWidgets('buscar filtra en pantalla, sin salir de la tabla',
        (tester) async {
      await montar(tester, const Size(1440, 900));
      await tester.enterText(find.byType(TextField).first, 'ruiz');
      await tester.pump();
      expect(find.text('Ana Ruiz'), findsOneWidget);
      expect(find.text('Luis Herrera'), findsNothing);
    });

    testWidgets('pulsar la cabecera ordena, y volver a pulsarla invierte',
        (tester) async {
      await montar(tester, const Size(1440, 900));
      Future<void> pulsar() async {
        await tester.tap(find.text('NOMBRE'));
        await tester.pump();
      }

      List<String> visibles() => tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .where((s) => s.contains(' '))
          .toList();

      await pulsar();
      expect(visibles().indexWhere((s) => s.startsWith('Álvaro')),
          lessThan(visibles().indexWhere((s) => s.startsWith('Luis'))));
      await pulsar();
      expect(visibles().indexWhere((s) => s.startsWith('Luis')),
          lessThan(visibles().indexWhere((s) => s.startsWith('Álvaro'))));
    });

    testWidgets('sin inscritos lo dice, y no deja la pantalla vacía',
        (tester) async {
      await montar(tester, const Size(1440, 900),
          torneo: _torneo(participantes: const []));
      expect(find.textContaining('Todavía no hay nadie'), findsOneWidget);
      expect(find.textContaining('pega la lista'), findsOneWidget);
    });

    testWidgets('buscando sin resultados dice otra cosa distinta',
        (tester) async {
      await montar(tester, const Size(1440, 900));
      await tester.enterText(find.byType(TextField).first, 'zzz');
      await tester.pump();
      expect(find.textContaining('Nadie con ese nombre'), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('5 · el portal arranca lo mismo que la app', () {
    // El portal NO pasa por AppShell, y los streams de Firestore no arrancan
    // solos: los arrancaba AppShell. Sin arrancarlos, el portal habría abierto
    // siempre con "este torneo no está en tu cuenta" para su propio dueño.
    //
    // La lista está una sola vez, en core/escuchas.dart. Esto comprueba que
    // sigue estando una sola vez: una copia se separa el día que se añada un
    // provider, y lo que falla entonces es una pantalla vacía sin motivo.
    /// El código, SIN comentarios.
    ///
    /// Sin quitarlos, esta prueba se cazaba a sí misma: la línea de un
    /// comentario que explica por qué NO se llama a startListening() contiene
    /// literalmente `startListening()`. Ya pasó antes en este proyecto —un
    /// contrapeso que aprobaba leyendo un comentario— y el modo de fallo es el
    /// peor: la prueba sigue verde y deja de mirar lo que decía mirar.
    String codigo(String ruta) => File(ruta)
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('las dos raíces llaman a la MISMA función', () {
      for (final ruta in [
        'lib/app_shell.dart',
        'lib/screens/organizador/organizador_screen.dart',
      ]) {
        expect(codigo(ruta), contains('iniciarEscuchas(context)'), reason: ruta);
      }
    });

    test('CLAVE: y ninguna arranca providers por su cuenta', () {
      for (final ruta in [
        'lib/app_shell.dart',
        'lib/screens/organizador/organizador_screen.dart',
      ]) {
        expect(codigo(ruta).contains('.startListening()'), isFalse,
            reason: '$ruta: la composición se define en core/escuchas.dart');
      }
    });

    test('y la única definición arranca los siete', () {
      final src = codigo('lib/core/escuchas.dart');
      for (final p in escuchasQueArrancan) {
        expect(src.contains('<$p>()'), isTrue, reason: p);
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // 6 · LA PUERTA DEL PORTAL
  //
  // Esta capa no se podía probar: AuthProvider se construía contra Firebase.
  // Es exactamente donde han caído los últimos fallos de este proyecto, y el
  // último fue este: /organizador/{id} con la sesión del dueño y un torneo
  // suyo enseñaba "este torneo no está en tu cuenta", y no se corregía.
  //
  // La causa es que "todavía no lo sé" y "no es tuyo" se pintaban igual.
  // `loading` no los separa: nace en false, así que entre montar la pantalla y
  // que alguien se suscriba hay un hueco con la lista vacía y sin cargar. Ese
  // hueco se leía como un permiso denegado.
  // ═════════════════════════════════════════════════════════════════════════
  group('6 · la puerta del portal', () {
    Future<TorneoProvider> montarPortal(
      WidgetTester tester, {
      required AuthStatus sesion,
      required TorneoProvider torneos,
      String id = 't1',
    }) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        // Los SIETE, como en producción. Montar con menos habría escondido el
        // caso que importa: aquí se llama a iniciarEscuchas de verdad.
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider.sembrado(sesion)),
          ChangeNotifierProvider(create: (_) => RoundProvider()),
          ChangeNotifierProvider(
              create: (_) => PlayerProvider()..sembrar(_directorio)),
          ChangeNotifierProvider(create: (_) => UserProfileProvider()),
          ChangeNotifierProvider(create: (_) => HandicapProvider()),
          ChangeNotifierProvider(create: (_) => PerfilProvider()),
          ChangeNotifierProvider(create: (_) => BettingGroupProvider()),
          ChangeNotifierProvider<TorneoProvider>.value(value: torneos),
        ],
        child: MaterialApp(home: OrganizadorScreen(torneoId: id)),
      ));
      await tester.pump();
      return torneos;
    }

    testWidgets('REGRESIÓN: sin cargar todavía NO dice que no es tuyo',
        (tester) async {
      // El fallo reportado, reproducido: provider recién creado —nadie se ha
      // suscrito— y el portal montándose. Antes de esto se pintaba el mensaje
      // de permiso; ahora se pinta que está cargando.
      final prov = await montarPortal(tester,
          sesion: AuthStatus.authenticated, torneos: TorneoProvider());
      expect(find.textContaining('no está en tu cuenta'), findsNothing,
          reason: 'una lista sin cargar no es una respuesta');
      expect(find.textContaining('Cargando'), findsOneWidget);
      prov.stopListening();
    });

    testWidgets('y cuando llegan los datos, abre el torneo', (tester) async {
      // La otra mitad: el estado de carga no puede quedarse pegado.
      final prov = TorneoProvider();
      await montarPortal(tester, sesion: AuthStatus.authenticated, torneos: prov);
      prov.sembrar([_torneo()]);
      await tester.pump();
      expect(find.text('Copa de Primavera'), findsOneWidget);
      expect(find.text('Luis Herrera'), findsOneWidget);
      expect(find.textContaining('Cargando'), findsNothing);
      prov.stopListening();
    });

    testWidgets('CRITERIO 1: con la sesión del dueño abre el torneo',
        (tester) async {
      final prov = await montarPortal(tester,
          sesion: AuthStatus.authenticated,
          torneos: TorneoProvider()..sembrar([_torneo()]));
      expect(find.text('Copa de Primavera'), findsOneWidget);
      expect(find.text('4 inscritos · Por posición'), findsOneWidget);
      prov.stopListening();
    });

    testWidgets('CRITERIO 3: con un torneo ajeno sigue diciendo lo que decía',
        (tester) async {
      // Cargado, con torneos dentro, y el id pedido no está. AHORA sí.
      final prov = await montarPortal(tester,
          sesion: AuthStatus.authenticated,
          torneos: TorneoProvider()..sembrar([_torneo()]),
          id: 'de-otra-cuenta');
      expect(find.textContaining('no está en tu cuenta'), findsOneWidget);
      expect(find.textContaining('organizas tú'), findsOneWidget);
      prov.stopListening();
    });

    testWidgets('CRITERIO 2: y ENSEÑA lo que encontró, no solo cuánto',
        (tester) async {
      // Dos veces seguidas esta pantalla dijo una frase fija y costó una ronda
      // entera de ida y vuelta averiguar qué pasaba de verdad. El id que busca,
      // los que tiene, sus nombres y las longitudes tienen que estar EN LA
      // PANTALLA.
      final prov = await montarPortal(tester,
          sesion: AuthStatus.authenticated,
          torneos: TorneoProvider()..sembrar([_torneo()]),
          id: 'de-otra-cuenta');

      // El id que se buscaba, con su longitud.
      expect(find.textContaining('de-otra-cuenta'), findsWidgets);
      expect(find.textContaining('(14 car.)'), findsOneWidget);
      // Y el que sí llegó, con nombre e id.
      expect(find.textContaining('Copa de Primavera · t1'), findsOneWidget);
      expect(find.textContaining('1 torneo en esta cuenta'), findsOneWidget);
      prov.stopListening();
    });

    testWidgets('CRITERIO 2: y el id casi igual se marca como tal',
        (tester) async {
      // El caso que costó esta ronda: dos ids que se leen igual. La pantalla
      // tiene que decir que se parecen, no que el torneo es de otro.
      // Con un id de verdad: la pista del prefijo pide al menos ocho
      // caracteres, porque dos ids cortos que empiezan igual son ruido.
      const uuid = '190f64da-955c-4f7c-87a3-d64c5b160884';
      final prov = await montarPortal(tester,
          sesion: AuthStatus.authenticated,
          torneos: TorneoProvider()..sembrar([_torneo(id: uuid)]),
          id: '$uuid/');
      expect(find.textContaining('no está en tu cuenta'), findsNothing,
          reason: 'no es de otra cuenta y decirlo manda a buscar donde no es');
      expect(find.textContaining('No pude abrir'), findsOneWidget);
      expect(find.textContaining('barra final'), findsOneWidget);
      prov.stopListening();
    });

    testWidgets('y con cero torneos el mensaje no culpa al enlace',
        (tester) async {
      // Si no llegó NADA, decir "es de otra cuenta" manda a buscar el problema
      // al sitio equivocado. Es lo que pasó esta vez.
      final prov = await montarPortal(tester,
          sesion: AuthStatus.authenticated,
          torneos: TorneoProvider()..sembrar([]));
      expect(find.textContaining('No llegó ningún torneo'), findsOneWidget);
      expect(find.textContaining('0 torneos en esta cuenta'), findsOneWidget);
      prov.stopListening();
    });

    testWidgets('mientras Firebase no contesta, tampoco acusa a nadie',
        (tester) async {
      final prov = await montarPortal(tester,
          sesion: AuthStatus.unknown, torneos: TorneoProvider());
      expect(find.textContaining('no está en tu cuenta'), findsNothing);
      expect(find.textContaining('Abriendo el portal'), findsOneWidget);
      prov.stopListening();
    });
  });

  group('7 · el arranque dice si prendió', () {
    test('CLAVE: un provider sin suscribir no es un arranque hecho', () {
      // El latch decía "ya está" sobre algo que aún no había pasado:
      // startListening() se rinde en silencio sin uid, y quien lo llamaba no
      // volvía a intentarlo nunca.
      expect(TorneoProvider().escuchando, isFalse);
      expect(TorneoProvider().cargado, isFalse);
    });

    test('y una lista vacía sembrada SÍ es una respuesta', () {
      // El contrapeso: si `cargado` no se pusiera nunca, la pantalla se
      // quedaría en "cargando…" para siempre, que es el otro extremo.
      final p = TorneoProvider()..sembrar([]);
      expect(p.cargado, isTrue);
      expect(p.torneos, isEmpty);
    });

    testWidgets('CLAVE: sin sesión de Firebase, iniciarEscuchas devuelve FALSE',
        (tester) async {
      // Aquí no hay uid, así que startListening() se rinde en silencio: es
      // EXACTAMENTE la situación que dejaba la sesión sin torneos. Lo que se
      // fija es que el arranque lo ADMITA en vez de decir que sí — sin esto,
      // quien llama marca "ya está" y no vuelve a intentarlo nunca.
      late bool prendio;
      late BuildContext capturado;
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => RoundProvider()),
          ChangeNotifierProvider(create: (_) => PlayerProvider()),
          ChangeNotifierProvider(create: (_) => UserProfileProvider()),
          ChangeNotifierProvider(create: (_) => HandicapProvider()),
          ChangeNotifierProvider(create: (_) => PerfilProvider()),
          ChangeNotifierProvider(create: (_) => TorneoProvider()),
          ChangeNotifierProvider(create: (_) => BettingGroupProvider()),
        ],
        child: Builder(builder: (ctx) {
          capturado = ctx;
          return const SizedBox();
        }),
      ));
      // FUERA del build: la propia función lo dice, porque los start* llaman a
      // notifyListeners() de forma síncrona.
      prendio = iniciarEscuchas(capturado);
      expect(prendio, isFalse,
          reason: 'no se suscribió nada: decir que sí es la mentira que costó '
              'el fallo');
    });

    testWidgets('CLAVE: un provider que falta no se lleva por delante al resto',
        (tester) async {
      // El aislamiento. TorneoProvider es el SEXTO de la lista: si el
      // `context.read` de cualquiera de los cinco anteriores escapa del try, se
      // lo lleva sin dejar rastro y el síntoma es el mismo de siempre —una
      // pantalla vacía sin motivo—.
      //
      // Falta UserProfileProvider, que es el tercero.
      final torneos = TorneoProvider();
      late bool prendio;
      late BuildContext capturado;
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => RoundProvider()),
          ChangeNotifierProvider(create: (_) => PlayerProvider()),
          ChangeNotifierProvider(create: (_) => HandicapProvider()),
          ChangeNotifierProvider(create: (_) => PerfilProvider()),
          ChangeNotifierProvider<TorneoProvider>.value(value: torneos),
          ChangeNotifierProvider(create: (_) => BettingGroupProvider()),
        ],
        child: Builder(builder: (ctx) {
          capturado = ctx;
          return const SizedBox();
        }),
      ));
      // Lo que se comprueba es que NO LANZA. Antes, el `context.read` iba como
      // argumento —o sea, fuera del try— y la excepción se escapaba.
      prendio = iniciarEscuchas(capturado);
      expect(prendio, isFalse);
      expect(tester.takeException(), isNull,
          reason: 'el fallo de uno es problema de ese uno');
      torneos.stopListening();
    });

    testWidgets('CLAVE: sin uid no se rinde — vuelve a intentarlo', (tester) async {
      // La cuarta vez que aparece este patrón. Sin esto, un intento medio
      // segundo pronto quedaba como definitivo, y el reintento tenía que
      // ponerlo cada pantalla por su cuenta — o sea, esperar a la quinta.
      final p = TorneoProvider();
      p.startListening();
      expect(p.escuchando, isFalse, reason: 'sin uid no hay a qué suscribirse');
      expect(p.reintentando, isTrue, reason: 'pero no se ha rendido');
      p.stopListening();
      expect(p.reintentando, isFalse, reason: 'y cerrar sesión lo apaga');
    });

    test('el reintento está acotado: una sesión cerrada no gira para siempre',
        () {
      final p = TorneoProvider();
      for (var i = 0; i < 40; i++) {
        p.startListening();
      }
      expect(p.reintentando, isFalse,
          reason: 'pasado el tope deja de intentarlo');
      p.stopListening();
    });
  });

  // ── EL BARRIDO ─────────────────────────────────────────────────────────────
  //
  // Cuatro veces el mismo patrón: algo que AppShell hace y que las rutas
  // propias no heredan. La pregunta era si queda alguna ruta más con el hueco.
  //
  // La respuesta es que el hueco no era de las rutas: era de
  // TorneoProvider.startListening(), que se rendía en silencio. Se tapó ahí, así
  // que las tres pantallas que lo llaman lo heredan. Esto comprueba que sigue
  // habiendo un solo sitio donde arrancarlo.
  group('8 · ninguna ruta propia se queda sin lo que AppShell hacía', () {
    final rutasPropias = [
      'lib/screens/organizador/organizador_screen.dart',
      'lib/screens/torneos/torneo_enlace_screen.dart',
      'lib/screens/torneos/leaderboard_tv_screen.dart',
    ];

    String codigoDe(String ruta) => File(ruta)
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('las que necesitan torneos los arrancan', () {
      for (final ruta in rutasPropias) {
        final src = codigoDe(ruta);
        final losUsa = src.contains('TorneoProvider>');
        if (!losUsa) continue;
        expect(
            src.contains('iniciarEscuchas(context)') ||
                src.contains('startListening()'),
            isTrue,
            reason: '$ruta lee TorneoProvider y no lo arranca');
      }
    });

    test('CLAVE: y el reintento vive en el provider, no copiado en cada una',
        () {
      // Si esto empieza a fallar es que alguien volvió a poner un reloj de
      // reintento en una pantalla. El sitio es el provider.
      expect(codigoDe('lib/providers/torneo_provider.dart'),
          contains('_maxIntentos'));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // 9 · DOS FORMAS DE LEER LA MISMA URL
  //
  // El fallo: `home:` sacaba el id con Uri.pathSegments —limpio— y
  // onGenerateRoute con `name.replaceFirst('/organizador/', '')`, que se queda
  // con TODO lo que venga detrás. La misma dirección daba dos ids según por
  // dónde entrara la app, y el segundo no coincidía con ninguno de los que
  // llegan de Firestore.
  // ═════════════════════════════════════════════════════════════════════════
  group('9 · el id del enlace, leído igual por los dos caminos', () {
    const id = '190f64da-955c-4f7c-87a3-d64c5b160884';

    test('CLAVE: la barra final no se cuela en el id', () {
      // El caso más fácil de provocar: el navegador la añade solo.
      expect(GolfBetApp.tokenDeNombre('/organizador/$id/', 'organizador'), id);
      expect('/organizador/$id/'.replaceFirst('/organizador/', ''), '$id/',
          reason: 'así es como fallaba antes');
    });

    test('ni la query', () {
      expect(GolfBetApp.tokenDeNombre('/organizador/$id?x=1', 'organizador'), id);
    });

    test('ni el porcentaje sin decodificar', () {
      expect(GolfBetApp.tokenDeNombre('/organizador/a%20b', 'organizador'), 'a b');
    });

    test('CLAVE: los dos caminos dan LO MISMO', () {
      // Es la propiedad que faltaba. Dos formas de leer una URL en el mismo
      // archivo, y la pantalla se comportaba distinto según cómo hubieras
      // llegado a ella.
      for (final url in [
        '/organizador/$id',
        '/organizador/$id/',
        '/organizador/$id?x=1',
      ]) {
        expect(GolfBetApp.tokenDeNombre(url, 'organizador'),
            GolfBetApp.tokenDeRuta(Uri.parse(url).pathSegments, 'organizador'),
            reason: url);
      }
    });

    test('y sigue sin cruzarse con las otras cuatro rutas', () {
      expect(GolfBetApp.tokenDeNombre('/tv/abc', 'organizador'), isNull);
      expect(GolfBetApp.tokenDeNombre('/organizador/abc', 'tv'), isNull);
      expect(GolfBetApp.tokenDeNombre('/app', 'organizador'), isNull);
      expect(GolfBetApp.tokenDeNombre('/torneo/abc/', 'torneo'), 'abc',
          reason: 'y el enlace del torneo se arregla de paso');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // 10 · SI NO LO ENCUENTRA, QUE DIGA QUÉ ENCONTRÓ
  //
  // Dos veces seguidas esta pantalla dijo "no está en tu cuenta" cuando el
  // problema era otro, y las dos costaron una ronda de ida y vuelta.
  // ═════════════════════════════════════════════════════════════════════════
  group('10 · el diagnóstico de la búsqueda', () {
    const id = '190f64da-955c-4f7c-87a3-d64c5b160884';
    Torneo conId(String x, String nombre) => Torneo(
        id: x,
        nombre: nombre,
        fuente: FuenteDeRondas.marcadas,
        metodo: MetodoDePuntuacion.posicion,
        formato: FormatoDeTorneo.eliminacion);

    test('lo encuentra cuando está', () {
      expect(buscarTorneo(id, [conId(id, 'Match Play Anual')]).hallazgo,
          Hallazgo.encontrado);
    });

    test('CLAVE: la barra final se diagnostica como recorte, no como ajeno', () {
      // Justo el fallo reportado. Antes decía "es de otra cuenta" y mandaba a
      // mirar la sesión, que era el sitio equivocado.
      final d = buscarTorneo('$id/', [conId(id, 'Match Play Anual')]);
      expect(d.hallazgo, Hallazgo.recortado);
      expect(d.parecido, id);
      expect(d.explicacion, contains('barra final'));
      expect(d.hallazgo, isNot(Hallazgo.invisible),
          reason: 'una barra SE VE: señalarla es más útil que decir que hay '
              'algo invisible');
    });

    test('y un id con espacios o mayúsculas, como casi igual', () {
      final d = buscarTorneo(' $id ', [conId(id, 'Match Play Anual')]);
      expect(d.hallazgo, Hallazgo.casiIgual);
    });

    test('CONTRAPESO: un torneo de verdad ajeno sigue siendo ajeno', () {
      // Sin esto, todo lo de arriba se podría satisfacer diciendo siempre que
      // el id llegó mal, que es el otro extremo del mismo error.
      final d = buscarTorneo('de-otra-cuenta-del-todo',
          [conId(id, 'Match Play Anual')]);
      expect(d.hallazgo, Hallazgo.ajeno);
      expect(d.parecido, isNull);
      expect(d.explicacion, contains('organizas tú'));
    });

    test('CONTRAPESO: dos ids cortos que empiezan igual NO son un recorte', () {
      // Un prefijo de tres letras es ruido, no una pista.
      expect(buscarTorneo('ab', [conId('abc', 'X')]).hallazgo, Hallazgo.ajeno);
    });

    test('CLAVE: el carácter que no se ve tiene su propio diagnóstico', () {
      // El único caso que no se puede resolver mirando la pantalla: los dos
      // ids se leen idénticos. Sin nombrarlo, el reporte diría "son iguales y
      // no los encuentra" y no habría por dónde seguir.
      final d = buscarTorneo('$id\u200b', [conId(id, 'Match Play Anual')]);
      expect(d.hallazgo, Hallazgo.invisible);
      expect(d.parecido, id);
      expect(d.explicacion, contains('no se ve'));
    });

    test('la lista vacía se distingue de todo lo anterior', () {
      final d = buscarTorneo(id, []);
      expect(d.hallazgo, Hallazgo.listaVacia);
      expect(d.explicacion, contains('no sea el enlace'));
    });

    test('siempre lleva los ids y los nombres que sí llegaron', () {
      final d = buscarTorneo('otro', [
        conId('a', 'Liga por Score'),
        conId('b', 'Match Play Anual'),
      ]);
      expect(d.disponibles, ['a', 'b']);
      expect(d.nombres, ['Liga por Score', 'Match Play Anual']);
    });
  });
}
