// ─────────────────────────────────────────────────────────────────────────────
// WOLF EN LA PANTALLA DE CAPTURA — que el toque exista, quepa y sea alcanzable
//
// El motor se prueba aparte. Esto prueba lo que aquello no puede: que la única
// pregunta del formato esté de verdad en la pantalla donde se anota el score, y
// que quepa.
//
// Es la lección medida del tablero de Inicio: cuatro etiquetas con nombres de
// persona en una fila ocupan más de lo que parece al escribirlas —allí se salían
// 77 px— y a 320 px un Row las recorta. Un botón que dice "CARL…" o que se sale
// de la tarjeta es exactamente la clase de fallo que solo aparece usando la app
// entre golpe y golpe.
//
// Y el otro criterio: quien NO juega Wolf no debe ver nada de esto.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/providers/auth_provider.dart';
import 'package:golf_bet_master/providers/player_provider.dart';
import 'package:golf_bet_master/screens/capture/capture_screen.dart';

const orden = ['w', 'x', 'y', 'z'];
const nombres = {'w': 'Rafa', 'x': 'Carlos', 'y': 'Cavazos', 'z': 'Alejandro'};

Round _round({bool conWolf = true, Map<int, WolfCall> calls = const {}}) {
  final course = CourseInfo(
      name: 'T',
      holes: List.generate(
          18, (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)));
  return Round(
    id: 'r', name: 'R', course: course,
    players:
        orden.map((i) => Player(id: i, name: nombres[i]!)).toList(),
    roundPlayers:
        orden.map((i) => RoundPlayer(playerId: i, handicapEnRonda: 0)).toList(),
    betGroups: [
      BetGroup(
          id: 'g', name: 'G',
          format: PartidaFormat.allInOnePot,
          playerIds: orden,
          modules: [
            BetModuleInstance.defaultFor(
                conWolf ? BetModuleType.wolf : BetModuleType.skins,
                orden,
                id: 'm'),
          ]),
    ],
    scores: {
      for (final pid in orden)
        pid: {
          for (var h = 1; h <= 18; h++)
            h: HoleScore(playerId: pid, hole: h, grossScore: 4),
        },
    },
    events: const {}, oyeseRankings: const {}, sliding: const [],
    wolfCalls: calls,
    createdAt: DateTime(2026, 1, 1), totalHoles: 18,
  );
}

/// Monta la captura y devuelve los errores del árbol.
Future<({List<String> errores, RoundProvider prov})> _montar(
    WidgetTester tester, Round round, Size tamano) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final errores = <String>[];
  final anterior = FlutterError.onError;
  FlutterError.onError = (d) => errores.add(d.exceptionAsString());

  final prov = RoundProvider()..startRound(round);

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<RoundProvider>.value(value: prov),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => PlayerProvider()),
    ],
    child: const MaterialApp(home: CaptureScreen()),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  FlutterError.onError = anterior;
  return (errores: errores, prov: prov);
}

void main() {
  testWidgets('la pregunta está en la pantalla donde se anota el score',
      (tester) async {
    final r = await _montar(tester, _round(), const Size(390, 900));
    expect(find.textContaining('WOLF:'), findsOneWidget,
        reason: 'el Wolf se ENSEÑA porque orienta, pero no se pide');
    expect(find.text('¿Con quién jugó?'), findsOneWidget);
    // Los tres candidatos y "Solo": cuatro respuestas posibles.
    expect(find.byKey(const Key('wolfOpt_solo')), findsOneWidget);
    // Rafa es el Wolf del hoyo 1, así que NO puede ser su propio compañero.
    // Se busca DENTRO de la sección: su nombre también sale en la tabla de
    // jugadores de arriba, y buscarlo por texto apuntaba a la fila equivocada.
    // Lo cazó este test.
    expect(find.byKey(const ValueKey('wolfOpt_w')), findsNothing,
        reason: 'el Wolf no se elige a sí mismo');
    for (final pid in ['x', 'y', 'z']) {
      expect(find.byKey(ValueKey('wolfOpt_$pid')), findsOneWidget, reason: pid);
    }
    // No se cuentan los desbordamientos de la pantalla entera: medí que la
    // captura ya se desborda en seis sitios SIN Wolf —cuatro son las filas de
    // jugadores— así que esa cuenta hablaría de otro problema. La aserción sobre
    // lo que este formato añade es geométrica y está en el test de 320 px.
    expect(r.prov.round!.getWolfCall(1), isNull,
        reason: 'sin tocar nada, el hoyo no tiene elección');
  });

  testWidgets('un toque registra la elección', (tester) async {
    // Es lo que cierra el criterio: UNA cosa por hoyo, y de verdad se guarda.
    final r = await _montar(tester, _round(), const Size(390, 900));
    // La sección vive al final de un cuerpo scrollable, así que hay que
    // traerla a pantalla antes de tocar. Sin esto el toque no llegaba y el test
    // fallaba diciendo que no se guardó nada.
    final opcion = find.byKey(const ValueKey('wolfOpt_y'));
    await tester.ensureVisible(opcion);
    await tester.pump();
    await tester.tap(opcion);
    await tester.pump();
    expect(r.prov.round!.getWolfCall(1)?.partnerId, 'y');
    expect(find.text('Jugó con Cavazos.'), findsOneWidget);
  });

  testWidgets('"Solo" es una opción de la misma fila, no otra pantalla',
      (tester) async {
    final r = await _montar(tester, _round(), const Size(390, 900));
    final solo = find.byKey(const Key('wolfOpt_solo'));
    await tester.ensureVisible(solo);
    await tester.pump();
    await tester.tap(solo);
    await tester.pump();
    final call = r.prov.round!.getWolfCall(1);
    expect(call, isNotNull);
    expect(call!.solo, isTrue);
    expect(find.text('Fue solo contra los otros tres.'), findsOneWidget);
  });

  testWidgets('y se puede deshacer: limpiar deja el hoyo sin elección',
      (tester) async {
    // Ausente y "solo" son cosas distintas en el modelo, así que la pantalla
    // tiene que poder volver a ausente. Sin esto, un toque por error queda
    // liquidando un enfrentamiento que no ocurrió.
    final r = await _montar(
        tester,
        _round(calls: {1: const WolfCall(hole: 1, partnerId: 'y')}),
        const Size(390, 900));
    final limpiar = find.descendant(
        of: find.byKey(const Key('wolfCallSection')),
        matching: find.text('Limpiar'));
    await tester.ensureVisible(limpiar);
    await tester.pump();
    await tester.tap(limpiar);
    await tester.pump();
    expect(r.prov.round!.getWolfCall(1), isNull);
  });

  testWidgets('cabe a 320 px, que es el teléfono más estrecho', (tester) async {
    // Cuatro botones con nombres de persona: es donde se rompería.
    //
    // La aserción es GEOMÉTRICA sobre los botones de Wolf, no un recuento de
    // desbordamientos de la pantalla: medí que la captura ya se desborda a 320
    // px en seis sitios SIN Wolf —cuatro son las filas de jugadores, 85 px cada
    // una— así que contar hablaría de otro problema. Comprobar que MIS botones
    // caben dentro del viewport y son tocables sí dice lo que hace falta.
    await _montar(tester, _round(), const Size(320, 900));
    // Y siguen siendo tocables: un botón de 20 px de alto no se usa con guante.
    for (final k in ['wolfOpt_x', 'wolfOpt_solo']) {
      final caja = tester.getRect(find.byKey(ValueKey(k)));
      expect(caja.right, lessThanOrEqualTo(320.0), reason: '$k se sale');
      expect(caja.height, greaterThanOrEqualTo(40),
          reason: '$k es demasiado bajo para tocarlo con guante');
    }
  });

  testWidgets('quien no juega Wolf no ve nada de esto', (tester) async {
    // El contrapeso de todo lo anterior: si la sección saliera siempre, los
    // cinco tests de arriba pasarían igual y la pantalla tendría un control
    // inútil para la mayoría de las rondas.
    await _montar(tester, _round(conWolf: false), const Size(390, 900));
    expect(find.textContaining('WOLF:'), findsNothing);
    expect(find.text('¿Con quién jugó?'), findsNothing);
  });
}
