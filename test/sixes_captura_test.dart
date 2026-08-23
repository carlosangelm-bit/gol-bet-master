// ─────────────────────────────────────────────────────────────────────────────
// SIXES EN LA PANTALLA DE CAPTURA — "¿con quién voy ahora?"
//
// Sixes no pregunta nada: las parejas se derivan del bloque, como el Wolf se
// deriva del orden de salida. Pero en el hoyo 7 alguien va a preguntar con quién
// juega, y contar bloques mentalmente es justo lo que la app está para evitar.
//
// Así que lo que se prueba aquí es que se VEA, y que cambie al cruzar de bloque.
// El motor ya está probado aparte; esto es lo que aquello no puede comprobar.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/providers/auth_provider.dart';
import 'package:golf_bet_master/providers/player_provider.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/screens/capture/capture_screen.dart';

const orden = ['w', 'x', 'y', 'z'];
const nombres = {'w': 'Rafa', 'x': 'Carlos', 'y': 'Cavazos', 'z': 'Alejandro'};

Round _round({
  bool conSixes = true,
  int hoyosPorBloque = 6,
  int totalHoles = 18,
  List<String> pids = orden,
}) {
  final course = CourseInfo(
      name: 'T',
      holes: List.generate(
          18, (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)));
  final mod = conSixes
      ? BetModuleInstance(
          id: 'm',
          type: BetModuleType.sixes,
          name: 'Sixes',
          participantIds: pids,
          sixesConfig: SixesConfig(hoyosPorBloque: hoyosPorBloque))
      : BetModuleInstance.defaultFor(BetModuleType.skins, pids, id: 'm');
  return Round(
    id: 'r',
    name: 'R',
    course: course,
    players: pids.map((i) => Player(id: i, name: nombres[i] ?? i)).toList(),
    roundPlayers:
        pids.map((i) => RoundPlayer(playerId: i, handicapEnRonda: 0)).toList(),
    betGroups: [
      BetGroup(
          id: 'g',
          name: 'G',
          format: PartidaFormat.allInOnePot,
          playerIds: pids,
          modules: [mod]),
    ],
    scores: {
      for (final pid in pids)
        pid: {
          for (var h = 1; h <= 18; h++)
            h: HoleScore(playerId: pid, hole: h, grossScore: 4),
        },
    },
    events: const {},
    oyeseRankings: const {},
    sliding: const [],
    createdAt: DateTime(2026, 1, 1),
    totalHoles: totalHoles,
  );
}

Future<List<String>> _montar(
    WidgetTester tester, Round round, Size tamano) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final errores = <String>[];
  final anterior = FlutterError.onError;
  FlutterError.onError = (d) => errores.add(d.exceptionAsString());

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<RoundProvider>.value(
          value: RoundProvider()..startRound(round)),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => PlayerProvider()),
    ],
    child: const MaterialApp(home: CaptureScreen()),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  FlutterError.onError = anterior;
  return errores;
}

/// Avanza [n] hoyos tocando el botón de siguiente.
Future<void> _avanzar(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    final btn = find.textContaining('→');
    await tester.ensureVisible(btn.first);
    await tester.pump();
    await tester.tap(btn.first);
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// El texto del bloque que hay en pantalla.
String _bloqueTexto(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(
        of: find.byKey(const Key('sixesBloqueSection')),
        matching: find.byType(Text)))
    .map((w) => w.data ?? '')
    .join(' · ');

void main() {
  group('1 · la pareja del bloque se ve, sin preguntar nada', () {
    testWidgets('en el hoyo 1 sale el bloque 1 con sus dos parejas',
        (tester) async {
      final errores = await _montar(tester, _round(), const Size(390, 900));
      expect(errores, isEmpty);
      final txt = _bloqueTexto(tester);
      expect(txt, contains('BLOQUE 1'));
      expect(txt, contains('HOYOS 1-6'));
      expect(txt, contains('RAFA + CARLOS'));
      expect(txt, contains('CAVAZOS + ALEJANDRO'));
    });

    testWidgets('quien no juega Sixes no ve nada de esto', (tester) async {
      final errores =
          await _montar(tester, _round(conSixes: false), const Size(390, 900));
      expect(errores, isEmpty);
      expect(find.byKey(const Key('sixesBloqueSection')), findsNothing);
    });

    testWidgets('el bloque cabe a 320 px con nombres reales', (tester) async {
      // Dos parejas de nombres con el "vs" en medio es la forma que ya desbordó
      // cuatro veces en esta app.
      //
      // Se mide ESTE bloque y no el árbol entero a propósito: a 320 px la fila
      // de la tabla de captura sigue sin caber —los dos steppers y el divisor no
      // dejan sitio— y esa es deuda anterior, aplazada dos veces. Afirmar que el
      // árbol está limpio a 320 sería afirmar que la arreglé.
      await _montar(tester, _round(), const Size(320, 1000));
      final f = find.byKey(const Key('sixesBloqueSection'));
      expect(f, findsOneWidget);
      expect(tester.getSize(f).width, lessThanOrEqualTo(320.0));
      final txt = _bloqueTexto(tester);
      expect(txt, contains('RAFA + CARLOS'));
      expect(txt, contains('CAVAZOS + ALEJANDRO'));
    });
  });

  group('2 · al cruzar de bloque, cambia la pareja', () {
    testWidgets('en el hoyo 7 la pareja es OTRA, y lo dice', (tester) async {
      // Es la pregunta del formato. Si esto no cambiara, la app estaría
      // enseñando una pareja que ya no juega.
      final errores = await _montar(tester, _round(), const Size(390, 900));
      expect(errores, isEmpty);
      expect(_bloqueTexto(tester), contains('RAFA + CARLOS'));

      await _avanzar(tester, 6);
      final txt = _bloqueTexto(tester);
      expect(txt, contains('BLOQUE 2'));
      expect(txt, contains('HOYOS 7-12'));
      expect(txt, contains('RAFA + CAVAZOS'));
      expect(txt, isNot(contains('RAFA + CARLOS')));
    });

    testWidgets('y en el 13 la tercera', (tester) async {
      await _montar(tester, _round(), const Size(390, 900));
      await _avanzar(tester, 12);
      final txt = _bloqueTexto(tester);
      expect(txt, contains('BLOQUE 3'));
      expect(txt, contains('HOYOS 13-18'));
      expect(txt, contains('RAFA + ALEJANDRO'));
    });
  });

  group('3 · los hoyos que no cuentan se dicen', () {
    testWidgets('con bloques de 3, del hoyo 10 en adelante no cuenta',
        (tester) async {
      // Callarlo dejaría anotando scores que no alimentan la apuesta.
      final errores = await _montar(
          tester, _round(hoyosPorBloque: 3), const Size(390, 900));
      expect(errores, isEmpty);
      expect(_bloqueTexto(tester), contains('BLOQUE 1'));

      await _avanzar(tester, 9);
      final txt = _bloqueTexto(tester);
      expect(txt, contains('no cuenta para Sixes'));
      expect(txt, contains('acaban en el 9'));
    });
  });

  group('4 · una ronda a la que le falta un jugador lo dice', () {
    testWidgets('con tres jugadores sale el motivo del catálogo',
        (tester) async {
      // No debería pasar —el selector lo atenúa— pero una ronda guardada llega
      // aquí, y quedarse mudo sería peor. El texto sale de la misma tabla.
      final errores = await _montar(
          tester, _round(pids: const ['w', 'x', 'y']), const Size(390, 900));
      expect(errores, isEmpty);
      expect(_bloqueTexto(tester), contains('se juega con 4 jugadores'));
    });
  });
}
