// ─────────────────────────────────────────────────────────────────────────────
// CIENTO CINCUENTA
//
// Es el tamaño que este producto dice soportar, y hasta ahora todo se probaba
// con cuatro. Dos rondas seguidas de reportes salieron de ahí:
//
//   · "el botón se ve atenuado aunque funcione"
//   · "con 150 líneas, revisar no hace nada"
//
// Y eran EL MISMO defecto: el `onChanged` del campo solo reconstruía si ya
// había un resumen, así que al PEGAR sobre el campo vacío el botón conservaba
// el `onTap: null` de cuando no había texto. Apagado de verdad, y pintado como
// apagado, con las 150 líneas delante.
//
// Nunca fue volumen. Pero el volumen sí destapó lo que faltaba después: la hoja
// no cabía y guardar 150 fichas no decía nada mientras tanto.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/ancho.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/models/importar_jugadores.dart' hide nombreComparable;
import 'package:golf_bet_master/models/inscritos.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/torneo.dart';
import 'package:golf_bet_master/providers/player_provider.dart';
import 'package:golf_bet_master/providers/torneo_provider.dart';
import 'package:golf_bet_master/screens/organizador/inscritos_tabla.dart';
import 'package:golf_bet_master/services/player_service.dart';
import 'package:golf_bet_master/widgets/importar_jugadores_sheet.dart';
import 'package:provider/provider.dart';

/// 150 nombres, con acentos y handicaps decimales como los de un Excel real.
String pegado(int n) => [
      for (var i = 1; i <= n; i++)
        'Jugador Núñez $i\t${(i % 30) + (i.isEven ? 0.5 : 0)}',
    ].join('\n');

List<PlayerWithLink> directorio(int n) => [
      for (var i = 1; i <= n; i++)
        PlayerWithLink(
            player: Player(
                id: 'p$i',
                name: 'Jugador Núñez $i',
                handicapBase: (i % 30).toDouble()))
    ];

Torneo torneoCon(int n) => Torneo(
      id: 't1',
      nombre: 'Copa de Primavera',
      fuente: FuenteDeRondas.marcadas,
      metodo: MetodoDePuntuacion.posicion,
      participantes: [for (var i = 1; i <= n; i++) 'p$i'],
    );

void main() {
  group('1 · el parseo aguanta 150 sin despeinarse', () {
    test('las lee todas', () {
      final r = parsearJugadores(pegado(150), existentes: const {});
      expect(r.todos.length, 150);
      expect(r.rechazadas, isEmpty);
      expect(r.nuevos.length, 150);
    });

    test('con los handicaps que traía cada una', () {
      final r = parsearJugadores(pegado(150), existentes: const {});
      expect(r.todos.first.nombre, 'Jugador Núñez 1');
      expect(r.todos.first.handicap, 1);
      expect(r.todos[1].handicap, 2.5, reason: 'los pares llevan decimal');
    });

    test('y reconoce a los que ya están, sin duplicarlos', () {
      // La mitad del encargo original: reutilizar, no crear otra vez.
      final existentes = {
        for (final pw in directorio(50))
          nombreComparable(pw.displayName): pw.player.id
      };
      final r = parsearJugadores(pegado(150), existentes: existentes);
      expect(r.existentes.length, 50);
      expect(r.nuevos.length, 100);
    });

    test('CONTRAPESO: y sigue rechazando lo que no se puede leer', () {
      // Sin esto, un parser que aceptara cualquier cosa pasaría todo lo de
      // arriba.
      final r = parsearJugadores(
          '${pegado(10)}\nAna Ruiz\tzzz\nJugador Núñez 3\t9',
          existentes: const {});
      expect(r.rechazadas, hasLength(2));
      expect(r.rechazadas.map((x) => x.motivo).join(' '),
          allOf(contains('no es un handicap'), contains('ya sale antes')));
      expect(r.todos.length, 10, reason: 'las diez buenas siguen entrando');
    });
  });

  group('2 · el botón refleja lo que hay en el campo', () {
    Future<void> abrir(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      GolfThemeExt.setCurrent(GolfTheme.classic);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => PlayerProvider()..sembrar([])),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () =>
                      showImportarJugadoresSheet(ctx, t: GolfTheme.classic),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('REGRESIÓN: al pegar 150 líneas el botón se activa y responde',
        (tester) async {
      // El fallo reportado, reproducido. `enterText` es lo que hace un pegado:
      // dispara onChanged y nada más. Antes de esto, onChanged no reconstruía
      // —el `if (_res != null)`— y el botón se quedaba apagado con las 150
      // líneas ya en el campo.
      await abrir(tester);
      await tester.enterText(find.byType(TextField), pegado(150));
      await tester.pump();

      expect(find.text('Revisar 150 líneas'), findsOneWidget,
          reason: 'el botón tiene que reflejar lo que hay en el campo');
      expect(find.textContaining('150 líneas pegadas'), findsOneWidget);

      await tester.tap(find.text('Revisar 150 líneas'));
      await tester.pumpAndSettle();

      // Y produce un resumen. Esto es el criterio 1.
      expect(find.textContaining('Importar 150'), findsOneWidget);
    });

    testWidgets('con una sola línea también, que es lo que ya funcionaba',
        (tester) async {
      await abrir(tester);
      await tester.enterText(find.byType(TextField), 'Ana Ruiz\t12');
      await tester.pump();
      expect(find.text('Revisar 1 línea'), findsOneWidget);
    });

    testWidgets('CONTRAPESO: con el campo vacío sigue apagado, y lo dice',
        (tester) async {
      // El otro extremo: un botón siempre activo tampoco sirve.
      await abrir(tester);
      expect(find.text('Revisar la lista'), findsOneWidget);
      expect(find.textContaining('Pega la lista para empezar'), findsOneWidget);
    });

    testWidgets('CRITERIO 2: pasado el tope se dice ANTES de pulsar',
        (tester) async {
      await abrir(tester);
      await tester.enterText(find.byType(TextField), pegado(501));
      await tester.pump();
      expect(find.textContaining('el máximo por importación es 500'),
          findsOneWidget);
      expect(find.textContaining('segunda tanda'), findsOneWidget);
      // Y no se ofrece un botón que no va a hacer nada.
      expect(find.text('Revisar 501 líneas'), findsOneWidget);
    });

    testWidgets('y 500 justas sí entran: el tope no estorba a un uso real',
        (tester) async {
      await abrir(tester);
      await tester.enterText(find.byType(TextField), pegado(500));
      await tester.pump();
      expect(find.textContaining('máximo por importación'), findsNothing);
    });
  });

  group('3 · la hoja cabe con el resumen de 150', () {
    // ── LO QUE ESTA PRUEBA NO DEMUESTRA ─────────────────────────────────────
    //
    // La sospecha era que con 150 reutilizados el resumen crece, la columna se
    // sale y lo que queda fuera es justo el botón de importar. Se le añadió
    // scroll a la hoja por eso.
    //
    // Pero el contrapeso NO muerde: quitando ese scroll, esto sigue en verde,
    // porque la hoja modal ya desplaza por su cuenta. Así que el scroll añadido
    // es precaución, no un arreglo demostrado, y el desbordamiento nunca se ha
    // reproducido.
    //
    // Lo que sí comprueba: que con 150 el resumen sale y se llega al botón.
    testWidgets('con 150, el resumen sale y se llega al botón', (tester) async {
      tester.view.physicalSize = const Size(420, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      GolfThemeExt.setCurrent(GolfTheme.classic);

      final errores = <String>[];
      final anterior = FlutterError.onError;
      FlutterError.onError = (d) => errores.add(d.exceptionAsString());

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(
              create: (_) => PlayerProvider()..sembrar(directorio(150))),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () =>
                      showImportarJugadoresSheet(ctx, t: GolfTheme.classic),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), pegado(150));
      await tester.pump();
      await tester.tap(find.text('Revisar 150 líneas'));
      await tester.pumpAndSettle();

      FlutterError.onError = anterior;
      expect(errores.where((e) => e.contains('overflow')), isEmpty,
          reason: 'la hoja se desborda: lo que se sale es el botón');

      // Y se llega a él desplazándose.
      await tester.dragUntilVisible(find.textContaining('Importar 150'),
          find.byType(SingleChildScrollView), const Offset(0, -120));
      final r = tester.getRect(find.textContaining('Importar 150'));
      expect(r.bottom, lessThanOrEqualTo(760),
          reason: 'y acabar dentro de la pantalla');
    });
  });

  group('4 · la tabla con 150 inscritos', () {
    Future<void> montar(WidgetTester tester, Size tamano) async {
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final t = torneoCon(150);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(
              create: (_) => PlayerProvider()..sembrar(directorio(150))),
          ChangeNotifierProvider(create: (_) => TorneoProvider()..sembrar([t])),
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

    testWidgets('CRITERIO 4: se dibuja, y solo las filas visibles',
        (tester) async {
      // Lo que hace que 150 no atasque: la lista es perezosa y solo monta las
      // filas que caben. Lo que esto protege en concreto es que no se cambie
      // por un Column dentro de un scroll —que monta las 150 de golpe—; entre
      // ListView.builder y ListView(children:) no distingue, y no hace falta,
      // porque las dos son perezosas al montar.
      await montar(tester, const Size(1440, 900));
      expect(find.textContaining('Buscar entre 150 inscritos'), findsOneWidget);
      expect(find.text('Jugador Núñez 1'), findsOneWidget);
      final pintadas = tester
          .widgetList<Text>(find.byType(Text))
          .where((w) => (w.data ?? '').startsWith('Jugador Núñez'))
          .length;
      expect(pintadas, lessThan(60),
          reason: 'con 150 construidas de golpe, la tabla se arrastra');
    });

    testWidgets('se desplaza hasta el último sin romperse', (tester) async {
      await montar(tester, const Size(1440, 900));
      await tester.dragUntilVisible(find.text('Jugador Núñez 150'),
          find.byType(ListView), const Offset(0, -400));
      expect(find.text('Jugador Núñez 150'), findsOneWidget);
    });

    testWidgets('buscar entre 150 deja solo los que coinciden',
        (tester) async {
      await montar(tester, const Size(1440, 900));
      await tester.enterText(find.byType(TextField).first, 'Núñez 77');
      await tester.pump();
      expect(find.text('Jugador Núñez 77'), findsOneWidget);
      expect(find.text('Jugador Núñez 1'), findsNothing);
    });

    testWidgets('y en móvil, lo mismo', (tester) async {
      await montar(tester, const Size(390, 844));
      expect(find.text('Jugador Núñez 1'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Núñez 120');
      await tester.pump();
      expect(find.text('Jugador Núñez 120'), findsOneWidget);
    });

    test('ordenar 150 no depende del orden de llegada', () {
      final t = torneoCon(150);
      final dir = directorio(150);
      final a = filasDeInscritos(t, dir, orden: OrdenDeInscritos.handicap);
      final b = filasDeInscritos(t, dir.reversed.toList(),
          orden: OrdenDeInscritos.handicap);
      expect(a.map((f) => f.nombre), b.map((f) => f.nombre),
          reason: 'con cinco por handicap, sin desempate esto bailaría');
    });
  });
}
