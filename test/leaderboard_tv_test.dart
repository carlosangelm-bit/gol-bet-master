// ─────────────────────────────────────────────────────────────────────────────
// LA PANTALLA DE LA CASA CLUB
//
// Dos exigencias que no tiene ninguna otra pantalla del proyecto, y las dos son
// del sitio donde vive: una TV a diez metros, encendida ocho horas, sin nadie
// que la toque.
//
//   1 · SE VE DE LEJOS. El tamaño no se fija en píxeles: sale de una fracción
//       del alto de la pantalla, para que la misma proporción funcione en un
//       monitor de 24" y en una tele de 65". Los tests fijan el SUELO de esa
//       fracción, porque encogerla es lo que nadie notaría al hacerlo y todo el
//       mundo notaría en el club.
//
//   2 · NUNCA SE QUEDA EN BLANCO. Una pantalla proyectada en blanco no se
//       distingue de una tele apagada, y un volcado de Flutter delante de los
//       socios es peor. Sin datos, con el enlace apagado o con un error, siempre
//       hay algo escrito.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/leaderboard_publico.dart';
import 'package:golf_bet_master/main.dart';
import 'package:golf_bet_master/screens/torneos/leaderboard_tv_screen.dart';

LeaderboardPublico _lb({
  int jugadores = 4,
  bool ocultaLaMedida = false,
  bool activo = true,
  InventarioProyectado inventario = const InventarioProyectado(),
}) =>
    LeaderboardPublico(
      token: 'tok',
      ownerUid: 'uid',
      nombre: 'Copa de Primavera',
      emoji: '🏆',
      publicadoEn: DateTime(2026, 8, 29, 14),
      comoSePuntua: 'Por posición',
      rondas: 3,
      ocultaLaMedida: ocultaLaMedida,
      activo: activo,
      tabla: [
        for (var i = 1; i <= jugadores; i++)
          FilaProyectada(
              puesto: i,
              nombre: 'Jugador $i',
              jugadas: 3,
              medida: ocultaLaMedida ? null : (100 - i).toDouble()),
      ],
      inventario: inventario,
    );

Future<List<String>> _montar(WidgetTester tester, LeaderboardPublico? datos,
    {Size tamano = const Size(1920, 1080)}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final errores = <String>[];
  final anterior = FlutterError.onError;
  FlutterError.onError = (d) => errores.add(d.exceptionAsString());
  final builderPrevio = ErrorWidget.builder;
  addTearDown(() => ErrorWidget.builder = builderPrevio);

  await tester.pumpWidget(MaterialApp(
    home: LeaderboardTvScreen(
        token: 'tok', modoDePrueba: true, datosDePrueba: datos),
  ));
  await tester.pump(const Duration(milliseconds: 200));
  FlutterError.onError = anterior;
  return errores;
}

String _texto(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .join(' · ');

/// El tamaño de fuente más grande que se está pintando.
double _mayorFuente(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.style?.fontSize ?? 0)
    .fold<double>(0, (a, b) => a > b ? a : b);

void main() {
  group('1 · se ve desde diez metros', () {
    test('la unidad sale del alto, no de un número fijo', () {
      // Es lo que hace que la misma proporción sirva en un monitor y en una TV.
      expect(LeaderboardTvScreen.unidadDe(1080), 1080 / 16);
      expect(LeaderboardTvScreen.unidadDe(2160),
          LeaderboardTvScreen.unidadDe(1080) * 2);
    });

    testWidgets('en 1080p el texto principal no baja de 40 px', (tester) async {
      // El suelo. A diez metros, por debajo de esto hay que levantarse a mirar.
      final errores = await _montar(tester, _lb());
      expect(errores, isEmpty);
      expect(_mayorFuente(tester), greaterThanOrEqualTo(40));
    });

    testWidgets('y en una pantalla del doble de alto, el doble de grande',
        (tester) async {
      // La prueba de que escala de verdad y no está fijado en píxeles.
      await _montar(tester, _lb(), tamano: const Size(1920, 1080));
      final enFullHd = _mayorFuente(tester);
      await _montar(tester, _lb(), tamano: const Size(3840, 2160));
      final en4k = _mayorFuente(tester);
      expect(en4k, closeTo(enFullHd * 2, 1));
    });

    testWidgets('caben doce filas: de ahí sale el tamaño', (tester) async {
      final errores = await _montar(tester, _lb(jugadores: 12));
      expect(errores, isEmpty);
      expect(LeaderboardTvScreen.filasPorPagina, 12);
      for (var i = 1; i <= 12; i++) {
        expect(find.text('Jugador $i'), findsOneWidget);
      }
    });
  });

  group('2 · nunca en blanco', () {
    testWidgets('sin datos dice qué pasa, no se queda vacía', (tester) async {
      final errores = await _montar(tester, null);
      expect(errores, isEmpty);
      expect(find.byType(Text), findsWidgets);
      expect(_texto(tester), contains('todavía no tiene tabla publicada'));
    });

    testWidgets('con el enlace apagado lo dice', (tester) async {
      final errores = await _montar(tester, _lb(activo: false));
      expect(errores, isEmpty);
      expect(_texto(tester), contains('apagó esta pantalla'));
    });

    testWidgets('y nunca enseña un volcado técnico', (tester) async {
      // ErrorWidget.builder se sustituye mientras esta pantalla vive: un stack
      // trace proyectado en la pared del club es peor que la tele apagada.
      await _montar(tester, _lb());
      final w = ErrorWidget.builder(FlutterErrorDetails(
          exception: Exception('algo se rompió'), library: 'test'));
      expect(w, isNotNull);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: w)));
      await tester.pump();
      final visto = _texto(tester);
      expect(visto, isNot(contains('algo se rompió')));
      expect(visto, contains('Actualizando'));
    });
  });

  group('3 · 150 jugadores no caben, así que rota', () {
    testWidgets('pagina y lo dice', (tester) async {
      final errores = await _montar(tester, _lb(jugadores: 150));
      expect(errores, isEmpty);
      // 150 / 12 = 13 páginas.
      expect(_texto(tester), contains('1 / 13'));
      expect(find.text('Jugador 1'), findsOneWidget);
      expect(find.text('Jugador 13'), findsNothing);
    });

    testWidgets('y pasa sola a la siguiente', (tester) async {
      // Nadie va a tocar esta pantalla: si no rota sola, los últimos 138 no
      // existen.
      await _montar(tester, _lb(jugadores: 150));
      await tester.pump(const Duration(seconds: 13));
      expect(_texto(tester), contains('2 / 13'));
      expect(find.text('Jugador 13'), findsOneWidget);
      // Y la anterior se va, no se queda debajo.
      //
      // Hace falta pasar el cruce: desde que las filas animan el cambio de
      // posición, las dos conviven durante la transición. Es lo que hace que un
      // adelantamiento se vea, y aquí lo que se comprueba es que TERMINA.
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Jugador 1'), findsNothing);
    });

    testWidgets('con pocos jugadores no hay paginación ni indicador',
        (tester) async {
      await _montar(tester, _lb(jugadores: 4));
      expect(_texto(tester), isNot(contains('/ 1')));
      await tester.pump(const Duration(seconds: 13));
      expect(find.text('Jugador 1'), findsOneWidget,
          reason: 'sin páginas, no se va a ninguna parte');
    });
  });

  group('4 · el dinero no está, y el hueco se explica', () {
    testWidgets('con la medida oculta lo dice en vez de dejar un vacío',
        (tester) async {
      final errores = await _montar(tester, _lb(ocultaLaMedida: true));
      expect(errores, isEmpty);
      expect(_texto(tester), contains('no muestra importes'));
    });

    testWidgets('y con medida visible no aparece esa frase', (tester) async {
      await _montar(tester, _lb());
      expect(_texto(tester), isNot(contains('no muestra importes')));
      expect(find.text('99'), findsOneWidget, reason: 'el primero, 99 puntos');
    });
  });

  group('5 · el patrocinio', () {
    testWidgets('sin patrocinador no se enseña un hueco', (tester) async {
      // §13.2 del anexo: un torneo sin patrocinador para ese espacio no debe
      // mostrar un hueco ni un placeholder.
      final errores = await _montar(tester, _lb());
      expect(errores, isEmpty);
      expect(_texto(tester), isNot(contains('PATROCINADOR')));
      expect(_texto(tester), isNot(contains('Patrocinado')));
    });

    testWidgets('con cabecera, la etiqueta comercial es visible',
        (tester) async {
      // §6 del manual: la naturaleza comercial tiene que ser clara.
      final errores = await _montar(
          tester,
          _lb(
              inventario: const InventarioProyectado(
                  cabecera: PiezaDePatrocinio(
                      etiqueta: 'Patrocinador oficial',
                      titular: 'Eleva cada gran ronda',
                      logoUrl: 'https://x/l.svg',
                      cta: 'Conoce la experiencia'))));
      expect(errores, isEmpty);
      final visto = _texto(tester);
      expect(visto, contains('PATROCINADOR OFICIAL'));
      expect(visto, contains('Eleva cada gran ronda'));
      expect(visto, contains('Conoce la experiencia'));
    });

    testWidgets('el pie rota entre los socios', (tester) async {
      // §14.2: aquí la rotación SÍ se permite — en una TV es lo esperado.
      await _montar(
          tester,
          _lb(inventario: const InventarioProyectado(pie: [
            PiezaDePatrocinio(etiqueta: 'Socio', titular: 'Marca A'),
            PiezaDePatrocinio(etiqueta: 'Socio', titular: 'Marca B'),
          ])));
      expect(_texto(tester), contains('Marca A'));
      await tester.pump(const Duration(seconds: 13));
      await tester.pump(const Duration(milliseconds: 500));
      expect(_texto(tester), contains('Marca B'));
    });

    testWidgets('el lateral solo con ancho suficiente', (tester) async {
      // §7 del manual: la columna desaparece antes de comprimir el contenido.
      const inv = InventarioProyectado(
          lateral: PiezaDePatrocinio(
              etiqueta: 'Marca destacada', titular: 'Precisión dentro y fuera'));
      await _montar(tester, _lb(inventario: inv),
          tamano: const Size(1024, 768));
      expect(_texto(tester), isNot(contains('Precisión dentro y fuera')));

      await _montar(tester, _lb(inventario: inv),
          tamano: const Size(1920, 1080));
      expect(_texto(tester), contains('Precisión dentro y fuera'));
    });
  });

  group('6 · el enlace llega a la pantalla', () {
    // El fallo que más veces se ha repetido en este proyecto es "la lógica
    // existe, la capa siguiente no la lee". Aquí la capa siguiente es el
    // enrutado, y sin esto solo se comprobaría abriendo el navegador.
    test('/tv/{token} da el token', () {
      expect(GolfBetApp.tokenDeRuta(const ['tv', 'abc123'], 'tv'), 'abc123');
    });

    test('y no se confunde con /torneo/{token}, que sí lleva dinero', () {
      // Son dos documentos distintos: uno pide cuenta y lleva botes; el otro se
      // ve sin sesión. Cruzarlos publicaría importes en la pantalla más
      // expuesta del sistema.
      expect(GolfBetApp.tokenDeRuta(const ['torneo', 'abc'], 'tv'), isNull);
      expect(GolfBetApp.tokenDeRuta(const ['tv', 'abc'], 'torneo'), isNull);
    });

    test('sin token no hay pantalla', () {
      expect(GolfBetApp.tokenDeRuta(const ['tv'], 'tv'), isNull);
      expect(GolfBetApp.tokenDeRuta(const ['tv', '  '], 'tv'), isNull);
      expect(GolfBetApp.tokenDeRuta(const [], 'tv'), isNull);
    });

    test('los enlaces de siempre siguen resolviendo igual', () {
      // El contrapeso del refactor: cuatro extractores pasaron a ser uno.
      expect(GolfBetApp.tokenDeRuta(const ['guest', 'g1'], 'guest'), 'g1');
      expect(GolfBetApp.tokenDeRuta(const ['caddie', 'c1'], 'caddie'), 'c1');
      expect(GolfBetApp.tokenDeRuta(const ['torneo', 't1'], 'torneo'), 't1');
    });

    // ── EL PORTAL DE ORGANIZADOR ──────────────────────────────────────────
    //
    // Mismo extractor, quinto prefijo. Lo que sigue a /organizador/ NO es un
    // token: es el id del torneo, y no hace falta que sea secreto —un torneo
    // vive en users/{uid}/torneos y la regla ya dice que solo su dueño lo lee—.
    // Es la diferencia con /tv/ y /torneo/, donde el token ES la credencial.
    test('/organizador/{id} da el id del torneo', () {
      expect(GolfBetApp.tokenDeRuta(const ['organizador', 'tor_1'], 'organizador'),
          'tor_1');
    });

    test('y no se cruza con ninguno de los otros cuatro', () {
      for (final otro in ['tv', 'torneo', 'guest', 'caddie']) {
        expect(GolfBetApp.tokenDeRuta(const ['organizador', 'x'], otro), isNull,
            reason: otro);
        expect(GolfBetApp.tokenDeRuta([otro, 'x'], 'organizador'), isNull,
            reason: otro);
      }
    });

    test('sin id no hay portal', () {
      expect(GolfBetApp.tokenDeRuta(const ['organizador'], 'organizador'), isNull);
    });
  });
}
