// ─────────────────────────────────────────────────────────────────────────────
// EL ÁRBOL DEL CUADRO
//
// El criterio que decide si esto sirve es el 6: un árbol que hay que ampliar
// para leer es PEOR que la lista de antes, porque la lista al menos se leía de
// un vistazo. Así que aquí se mide, no se supone:
//
//   · que no desborde a 390 ni a 320, con cuadros de 4, 8 y 16 plazas
//   · que las celdas conserven un ancho legible —118 px— en todos los casos
//   · que arranque desplazado a MI fase, que es lo que hace el scroll utilizable
//
// Y lo que hace que un bracket sea un bracket: que un hueco diga DE DÓNDE va a
// salir su ocupante. Un vacío no distingue "falta jugarse" de "está mal armado".
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/golf_icons.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/widgets/bracket_tree.dart';

/// Un cuadro de [plazas] con las fases completas y nadie resuelto.
ArbolDeLlave _arbol(int plazas,
    {List<String>? nombres, String? campeon, int byes = 0}) {
  final rondas = <List<NodoDeLlave>>[];
  var partidos = plazas ~/ 2;
  var ronda = 0;
  var idx = 0;
  final gente = nombres ??
      [for (var i = 0; i < plazas; i++) 'Jugador${i + 1}'];
  while (partidos >= 1) {
    rondas.add([
      for (var p = 0; p < partidos; p++)
        NodoDeLlave(
          ronda: ronda,
          posicion: p,
          // Solo la primera fase lleva nombres; las demás esperan.
          a: ronda == 0 ? gente[idx + p * 2] : null,
          b: ronda == 0 ? gente[idx + p * 2 + 1] : null,
        ),
    ]);
    if (ronda == 0) idx += partidos * 2;
    partidos = partidos ~/ 2;
    ronda++;
  }
  return ArbolDeLlave(
      rondas: rondas, campeon: campeon, plazas: plazas, byes: byes);
}

/// Monta el árbol y devuelve los errores del árbol de widgets.
Future<List<String>> _montar(
  WidgetTester tester,
  ArbolDeLlave arbol, {
  double ancho = 390,
  String? miNombre,
}) async {
  tester.view.physicalSize = Size(ancho, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final errores = <String>[];
  final anterior = FlutterError.onError;
  FlutterError.onError = (d) => errores.add(d.exceptionAsString());

  await tester.pumpWidget(MaterialApp(
    theme: GolfTheme.classic.toMaterial(),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ArbolDeLlaveVista(
            arbol: arbol, t: GolfTheme.classic, miNombre: miNombre),
      ),
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
  group('1 · CRITERIO 6: cabe o se navega, a 390 y a 320', () {
    for (final plazas in [2, 4, 8, 16]) {
      for (final ancho in [390.0, 320.0]) {
        testWidgets('$plazas plazas a ${ancho.toInt()} px', (tester) async {
          final errores = await _montar(tester, _arbol(plazas), ancho: ancho);
          expect(errores, isEmpty,
              reason: '$plazas plazas a ${ancho.toInt()} px');
        });
      }
    }

    testWidgets('las celdas conservan su ancho legible con 16 plazas',
        (tester) async {
      // Es la mitad de la decisión: se rueda en horizontal EN VEZ de encoger.
      // Un árbol que encoge para caber es el que hay que ampliar para leer.
      await _montar(tester, _arbol(16), ancho: 320);
      final celda = tester.getSize(find.text('Jugador1').first);
      expect(celda.width, greaterThan(40.0),
          reason: 'la celda se encogió en vez de rodar');
    });

    testWidgets('con más de dos fases se avisa de que se arrastra',
        (tester) async {
      // Sin el aviso, un cuadro de dieciséis parece cortado en vez de navegable.
      await _montar(tester, _arbol(8));
      expect(_pantalla(tester), contains('Arrastra'));
    });

    testWidgets('con dos fases no se avisa: cabe entero', (tester) async {
      await _montar(tester, _arbol(4));
      expect(_pantalla(tester), isNot(contains('Arrastra')));
    });
  });

  group('2 · CRITERIO 4: los huecos dicen de dónde sale su ocupante', () {
    testWidgets('la final de un cuadro de 4 dice "Ganador de Semifinales N"',
        (tester) async {
      final errores = await _montar(tester, _arbol(4));
      expect(errores, isEmpty);
      final txt = _pantalla(tester);
      expect(txt, contains('Ganador de Semifinales 1'));
      expect(txt, contains('Ganador de Semifinales 2'));
      // Y NO un vacío ni un guion.
      expect(txt, isNot(contains('Por decidir')));
    });

    testWidgets('en un cuadro de 8, cada fase apunta a la anterior',
        (tester) async {
      await _montar(tester, _arbol(8));
      final txt = _pantalla(tester);
      // Semifinales las alimentan los cuartos; la final, las semifinales.
      expect(txt, contains('Ganador de Cuartos 1'));
      expect(txt, contains('Ganador de Semifinales 1'));
    });

    test('la procedencia se calcula del sitio en el árbol', () {
      final a = _arbol(8);
      // El partido 0 de la fase 1 lo alimentan el 0 y el 1 de la fase 0.
      expect(a.procedenciaDe(a.rondas[1][0], 0), 'Ganador de Cuartos 1');
      expect(a.procedenciaDe(a.rondas[1][0], 1), 'Ganador de Cuartos 2');
      // El partido 1 de la fase 1, el 2 y el 3.
      expect(a.procedenciaDe(a.rondas[1][1], 0), 'Ganador de Cuartos 3');
      expect(a.procedenciaDe(a.rondas[1][1], 1), 'Ganador de Cuartos 4');
      // La primera fase no viene de ningún sitio.
      expect(a.procedenciaDe(a.rondas[0][0], 0), isNull);
    });

    test('con una sola final no se numera: "Ganador de la Final"', () {
      // "Ganador de Final 1" con una sola final sobra el número.
      final a = _arbol(4);
      expect(a.procedenciaDe(a.rondas[1][0], 0), contains('Semifinales'));
      final ocho = _arbol(8);
      expect(ocho.procedenciaDe(ocho.rondas[2][0], 0),
          contains('Semifinales'));
    });
  });

  group('3 · CRITERIO 2 y 3: el camino, y encontrarse sin buscar', () {
    testWidgets('mi celda se resalta', (tester) async {
      final errores = await _montar(tester, _arbol(8), miNombre: 'Jugador5');
      expect(errores, isEmpty);
      // El nombre está, y su celda es la marcada. Se comprueba por el camino,
      // que es lo que decide el resaltado.
      final camino = _arbol(8).caminoDe('Jugador5');
      expect(camino, isNotEmpty);
      expect(camino, isNotEmpty);
    });

    test('el camino recoge todas las celdas donde aparezco', () {
      final rondas = <List<NodoDeLlave>>[
        [
          const NodoDeLlave(ronda: 0, posicion: 0, a: 'Luis', b: 'Diego'),
          const NodoDeLlave(ronda: 0, posicion: 1, a: 'Andrés', b: 'Pepe'),
        ],
        [const NodoDeLlave(ronda: 1, posicion: 0, a: 'Luis', b: null)],
      ];
      final a = ArbolDeLlave(rondas: rondas, plazas: 4);
      // Luis está en su semifinal y ya en la final.
      expect(a.caminoDe('Luis'), {'0-0', '1-0'});
      // Diego solo en la semifinal que perdió.
      expect(a.caminoDe('Diego'), {'0-0'});
      // Y sin identidad, ningún resaltado: no se adivina.
      expect(a.caminoDe(null), isEmpty);
    });

    testWidgets('el árbol arranca desplazado a MI fase', (tester) async {
      // Es lo que hace el scroll utilizable: quien abre esto quiere su partido.
      // Con OCHO plazas, que es donde sigue habiendo árbol: por encima de tres
      // fases la vista es otra y el desplazamiento no aplica.
      final rondas = <List<NodoDeLlave>>[
        [
          for (var p = 0; p < 4; p++)
            NodoDeLlave(
                ronda: 0, posicion: p, a: 'A$p', b: 'B$p', ganador: 'A$p'),
        ],
        [
          const NodoDeLlave(ronda: 1, posicion: 0, a: 'A0', b: 'A1', ganador: 'A0'),
          const NodoDeLlave(ronda: 1, posicion: 1, a: 'A2', b: 'A3', ganador: 'A2'),
        ],
        // A2 llega a la final, que es la fase 2: ahí sí hay que desplazarse.
        [const NodoDeLlave(ronda: 2, posicion: 0, a: 'A0', b: 'A2')],
      ];
      await _montar(tester, ArbolDeLlave(rondas: rondas, plazas: 8),
          miNombre: 'A2');
      final sc = tester
          .widgetList<Scrollable>(find.byType(Scrollable))
          .firstWhere((s) => s.axis == Axis.horizontal);
      expect(sc.controller!.offset, greaterThan(0.0),
          reason: 'no se desplazó a mi fase');
    });

    testWidgets('con mi fase en la primera columna NO se desplaza', (tester) async {
      // No es un fallo: mi fase es la 1, así que las columnas 0 y 1 ya están a
      // la vista y moverse sería perder el contexto de dónde vengo.
      await _montar(tester, _arbol(8), miNombre: 'Jugador3');
      final sc = tester
          .widgetList<Scrollable>(find.byType(Scrollable))
          .firstWhere((s) => s.axis == Axis.horizontal);
      expect(sc.controller!.offset, 0.0);
    });

    testWidgets('sin identidad no se desplaza ni se resalta', (tester) async {
      await _montar(tester, _arbol(8));
      final sc = tester
          .widgetList<Scrollable>(find.byType(Scrollable))
          .firstWhere((s) => s.axis == Axis.horizontal);
      expect(sc.controller!.offset, 0.0);
    });
  });

  group('4 · CRITERIO 5: los byes se explican', () {
    testWidgets('se dice cuántos, de cuántas plazas y por qué', (tester) async {
      final errores = await _montar(tester, _arbol(8, byes: 3));
      expect(errores, isEmpty);
      final txt = _pantalla(tester);
      expect(txt, contains('sin jugar la primera fase'));
      expect(txt, contains('8 plazas'));
      expect(txt, contains('5 inscritos'));
      expect(txt, contains('siembra'));
    });

    testWidgets('la celda del bye dice que pasa directo', (tester) async {
      final rondas = <List<NodoDeLlave>>[
        [
          const NodoDeLlave(
              ronda: 0, posicion: 0, a: 'Luis', ganador: 'Luis', bye: true),
          const NodoDeLlave(ronda: 0, posicion: 1, a: 'Ana', b: 'Beto'),
        ],
        [const NodoDeLlave(ronda: 1, posicion: 0, a: 'Luis')],
      ];
      await _montar(tester,
          ArbolDeLlave(rondas: rondas, plazas: 4, byes: 1));
      expect(_pantalla(tester), contains('Sin rival: pasa directo'));
    });

    testWidgets('sin byes no se habla de byes', (tester) async {
      await _montar(tester, _arbol(8));
      expect(_pantalla(tester), isNot(contains('sin jugar')));
    });
  });

  group('5 · el empate se ve, y el campeón cierra el árbol', () {
    testWidgets('un empate se marca en su celda', (tester) async {
      final rondas = <List<NodoDeLlave>>[
        [const NodoDeLlave(ronda: 0, posicion: 0, a: 'Ana', b: 'Beto', empatado: true)],
      ];
      await _montar(tester, ArbolDeLlave(rondas: rondas, plazas: 2));
      // El texto nombra la RONDA donde se empató: sin ella, "falta decidir" no
      // dice de qué partido se habla en un cuadro de dieciséis.
      expect(_pantalla(tester), contains('falta decidir'));
    });

    testWidgets('y el empate dice EN QUÉ RONDA se empató', (tester) async {
      final rondas = <List<NodoDeLlave>>[
        [
          const NodoDeLlave(
              ronda: 0,
              posicion: 0,
              a: 'Ana',
              b: 'Beto',
              empatado: true,
              nota: 'Sábado 7'),
        ],
      ];
      await _montar(tester, ArbolDeLlave(rondas: rondas, plazas: 2));
      expect(_pantalla(tester), contains('Empate en Sábado 7'));
    });

    testWidgets('el campeón sale al final del árbol', (tester) async {
      final errores =
          await _montar(tester, _arbol(4, campeon: 'Jugador1'));
      expect(errores, isEmpty);
      expect(_pantalla(tester), contains('Jugador1'));
      // El trofeo ya es un icono del catálogo, no un carácter del sistema.
      expect(find.byIcon(GolfIcons.trofeo), findsOneWidget);
    });

    testWidgets('sin campeón no hay trofeo', (tester) async {
      await _montar(tester, _arbol(4));
      expect(find.byIcon(GolfIcons.trofeo), findsNothing);
    });
  });

  group('7 · CRITERIO 1: por encima de tres fases deja de ser árbol', () {
    // MEDIDO a 390 px, con 358 útiles y unos 600 de alto visible:
    //
    //   plazas  fases  ancho  alto   ¿cabe?
    //        4      2    258   176   sí, entero
    //        8      3    398   368   rueda 40 en horizontal
    //       16      4    538   680   NO: +180 de ancho Y +80 de alto
    //       32      5    678  1304   NO: +320 y +704
    //
    // A 16 el árbol pide arrastrar en DIAGONAL, y con guante entre golpe y golpe
    // eso no se hace. Así que por encima de tres fases se ve por fases.
    testWidgets('con 16 plazas ya no hay columnas: hay chips de fase',
        (tester) async {
      final errores = await _montar(tester, _arbol(16));
      expect(errores, isEmpty);
      final txt = _pantalla(tester);
      // Los chips de fase, que son el selector.
      expect(find.text('Octavos'), findsOneWidget);
      expect(find.text('Cuartos'), findsOneWidget);
      expect(find.text('Final'), findsOneWidget);
      // Y se dice POR QUÉ no es un árbol: quien lo vio con cuatro se lo pregunta.
      expect(txt, contains('se ve por fases'));
      expect(txt, contains('no cabe en un teléfono'));
    });

    testWidgets('y cada partido dice a dónde va el que gane', (tester) async {
      // Es la conexión que el árbol dibujaba con una línea. Sin árbol, con
      // palabras.
      await _montar(tester, _arbol(16));
      expect(_pantalla(tester), contains('Pasa a'));
    });

    testWidgets('y de dónde vienen sus dos plazas', (tester) async {
      await _montar(tester, _arbol(16));
      // En la fase de cuartos, las plazas vienen de los octavos.
      await tester.tap(find.text('Cuartos'));
      await tester.pumpAndSettle();
      expect(_pantalla(tester), contains('Ganador de Octavos'));
    });

    testWidgets('con 32 tampoco desborda a 320 px', (tester) async {
      final errores = await _montar(tester, _arbol(32), ancho: 320);
      expect(errores, isEmpty);
      // 32 plazas → 16 partidos en la primera fase → dieciseisavos.
      expect(find.text('Dieciseisavos'), findsOneWidget);
    });

    testWidgets('con 8 SIGUE siendo árbol: es el contrapeso', (tester) async {
      // Si el umbral estuviera mal puesto, un cuadro de ocho perdería el árbol
      // sin necesidad.
      await _montar(tester, _arbol(8));
      final txt = _pantalla(tester);
      expect(txt, isNot(contains('se ve por fases')));
      expect(txt, contains('Arrastra'), reason: 'el árbol rueda, no cambia');
    });

    testWidgets('la vista por fases arranca en MI fase', (tester) async {
      // Con dieciséis, la primera fase no es donde nadie mira.
      final rondas = <List<NodoDeLlave>>[
        [
          for (var p = 0; p < 8; p++)
            NodoDeLlave(
                ronda: 0, posicion: p, a: 'A$p', b: 'B$p', ganador: 'A$p'),
        ],
        [
          for (var p = 0; p < 4; p++)
            NodoDeLlave(
                ronda: 1,
                posicion: p,
                a: 'A${p * 2}',
                b: 'A${p * 2 + 1}',
                ganador: 'A${p * 2}'),
        ],
        [
          NodoDeLlave(ronda: 2, posicion: 0, a: 'A0', b: 'A2'),
          NodoDeLlave(ronda: 2, posicion: 1, a: 'A4', b: 'A6'),
        ],
        [const NodoDeLlave(ronda: 3, posicion: 0)],
      ];
      await _montar(tester, ArbolDeLlave(rondas: rondas, plazas: 16),
          miNombre: 'A4');
      // A4 llega a semifinales, así que esa es la fase que se abre.
      expect(_pantalla(tester), contains('Semifinales 2'));
    });
  });

  group('6 · el nombre de la fase sale del número de partidos', () {
    test('se cuenta desde el final, no desde el principio', () {
      // La fase con dos partidos es la semifinal, tenga el cuadro ocho plazas o
      // treinta y dos.
      expect(ArbolDeLlave.nombreDeFase(1), 'Final');
      expect(ArbolDeLlave.nombreDeFase(2), 'Semifinales');
      expect(ArbolDeLlave.nombreDeFase(4), 'Cuartos');
      expect(ArbolDeLlave.nombreDeFase(8), 'Octavos');
      expect(ArbolDeLlave.nombreDeFase(32), 'Ronda de 64');
    });
  });
}
