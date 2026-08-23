// ─────────────────────────────────────────────────────────────────────────────
// LAS FORMACIONES EN PANTALLA
//
// El catálogo se prueba puro en formaciones_test. Esto prueba lo que aquello no
// puede: que el atajo esté ALCANZABLE desde el asistente, que arme los lados de
// verdad, que diga su criterio, y que fuera de rango se atenúe con su motivo.
//
// Tres veces en esta sesión escribí código correcto al que la app no llegaba por
// ningún sitio, así que el recorrido es el de un usuario: elegir jugadores en el
// paso 2 y llegar a Compiten.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/providers/auth_provider.dart';
import 'package:golf_bet_master/providers/betting_group_provider.dart';
import 'package:golf_bet_master/providers/handicap_provider.dart';
import 'package:golf_bet_master/providers/perfil_provider.dart';
import 'package:golf_bet_master/providers/player_provider.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/providers/torneo_provider.dart';
import 'package:golf_bet_master/providers/user_profile_provider.dart';
import 'package:golf_bet_master/screens/setup/setup_screen.dart';
import 'package:golf_bet_master/services/player_service.dart';

/// Cinco jugadores con handicaps separados, en el orden en que se capturan.
const gente = [
  ('Rafa', 4.0),
  ('Alan', 9.0),
  ('Memo', 18.0),
  ('Toño', 20.0),
  ('Beto', 22.0),
];

/// Abre el asistente con [cuantos] jugadores elegidos y llega a Compiten.
Future<List<String>> _hastaCompiten(WidgetTester tester, int cuantos,
    {Size tamano = const Size(390, 1600)}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final errores = <String>[];
  final anterior = FlutterError.onError;
  FlutterError.onError = (d) => errores.add(d.exceptionAsString());

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => RoundProvider()),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => HandicapProvider()),
      ChangeNotifierProvider(create: (_) => UserProfileProvider()),
      ChangeNotifierProvider(create: (_) => BettingGroupProvider()),
      ChangeNotifierProvider(create: (_) => TorneoProvider()),
      ChangeNotifierProvider(create: (_) => PerfilProvider()),
      ChangeNotifierProvider<PlayerProvider>.value(
          value: PlayerProvider()
            ..sembrar([
              for (final g in gente)
                PlayerWithLink(
                    player: Player(
                        id: 'pid_${g.$1.toLowerCase()}',
                        name: g.$1,
                        handicapBase: g.$2)),
            ])),
    ],
    child: const MaterialApp(home: SetupScreen()),
  ));
  await tester.pump(const Duration(milliseconds: 150));

  // Paso 1 → 2.
  await tester.tap(find.text('Siguiente →'));
  await tester.pumpAndSettle();

  // Elegir jugadores del directorio.
  for (final g in gente.take(cuantos)) {
    final fila = find.text(g.$1);
    if (fila.evaluate().isEmpty) continue;
    await tester.ensureVisible(fila.first);
    await tester.pump();
    await tester.tap(fila.first);
    await tester.pump();
  }

  // Paso 2 → 3 (Compiten).
  final siguiente = find.text('Siguiente →');
  await tester.ensureVisible(siguiente);
  await tester.pump();
  await tester.tap(siguiente);
  await tester.pumpAndSettle();

  FlutterError.onError = anterior;
  return errores;
}

/// Los nombres que aparecen dentro del panel del equipo [cual] (0 = A, 1 = B).
List<String> _delPanel(WidgetTester tester, String etiqueta) {
  final panel = find.ancestor(
      of: find.text(etiqueta), matching: find.byType(Column));
  final textos = tester
      .widgetList<Text>(find.descendant(of: panel.first, matching: find.byType(Text)))
      .map((w) => w.data)
      .whereType<String>()
      .toList();
  return [for (final g in gente) if (textos.contains(g.$1)) g.$1];
}

void main() {
  group('1 · el atajo está en Compiten y es alcanzable', () {
    testWidgets('las tres formaciones salen del catálogo', (tester) async {
      final errores = await _hastaCompiten(tester, 5);
      expect(errores, isEmpty);
      expect(find.text('¿Quiénes compiten?'), findsOneWidget);
      expect(find.text('Cada quien por su cuenta'), findsOneWidget);
      expect(find.text('Por equipos'), findsOneWidget);
      expect(find.text('High and Low'), findsOneWidget);
      expect(find.text('Pair vs Field'), findsOneWidget);
    });

    testWidgets('cada una anuncia el reparto antes de elegirla',
        (tester) async {
      await _hastaCompiten(tester, 5);
      expect(find.text('2 contra 3, por handicap.'), findsOneWidget);
      expect(find.text('2 contra 3.'), findsOneWidget);
    });
  });

  group('2 · High and Low arma los lados por handicap', () {
    testWidgets('los dos más bajos contra los tres más altos', (tester) async {
      final errores = await _hastaCompiten(tester, 5);
      expect(errores, isEmpty);
      await tester.tap(find.text('High and Low'));
      await tester.pumpAndSettle();

      expect(_delPanel(tester, 'EQUIPO A'), ['Rafa', 'Alan']);
      expect(_delPanel(tester, 'EQUIPO B'), ['Memo', 'Toño', 'Beto']);
    });

    testWidgets('dice su criterio y el handicap que usa', (tester) async {
      // Un atajo que reparte a la gente en silencio deja la sospecha de que lo
      // hizo mal.
      await _hastaCompiten(tester, 5);
      await tester.tap(find.text('High and Low'));
      await tester.pumpAndSettle();

      expect(find.text('CÓMO SE REPARTIÓ'), findsOneWidget);
      expect(find.textContaining('el que va antes en la lista'), findsOneWidget);
      expect(find.textContaining('handicap registrado'), findsOneWidget);
      expect(find.textContaining('no se rearman solos'), findsOneWidget);
      expect(find.text('Rearmar por handicap'), findsOneWidget);
    });

    testWidgets('los handicaps están a la vista', (tester) async {
      // Sin ellos, "por handicap" es una promesa.
      await _hastaCompiten(tester, 5);
      await tester.tap(find.text('High and Low'));
      await tester.pumpAndSettle();
      expect(find.text('Rafa 4.0'), findsOneWidget);
      expect(find.text('Beto 22.0'), findsOneWidget);
    });

    testWidgets('y se puede cambiar a mano después: es atajo, no carril',
        (tester) async {
      await _hastaCompiten(tester, 5);
      await tester.tap(find.text('High and Low'));
      await tester.pumpAndSettle();

      // Tocar a Alan en el panel A lo manda al B.
      final enA = find.descendant(
          of: find.ancestor(
              of: find.text('EQUIPO A'), matching: find.byType(Column)).first,
          matching: find.text('Alan'));
      await tester.tap(enA.first);
      await tester.pumpAndSettle();
      expect(_delPanel(tester, 'EQUIPO A'), ['Rafa']);
      expect(_delPanel(tester, 'EQUIPO B'), contains('Alan'));
    });
  });

  group('3 · Pair vs Field: la pareja contra el resto', () {
    testWidgets('propone la pareja de handicap combinado más bajo',
        (tester) async {
      final errores = await _hastaCompiten(tester, 5);
      expect(errores, isEmpty);
      await tester.tap(find.text('Pair vs Field'));
      await tester.pumpAndSettle();

      expect(_delPanel(tester, 'EQUIPO A'), ['Rafa', 'Alan']);
      expect(_delPanel(tester, 'EQUIPO B'), ['Memo', 'Toño', 'Beto']);
      expect(find.textContaining('handicap combinado más bajo'), findsOneWidget);
      expect(find.textContaining('no rota'), findsOneWidget);
    });
  });

  group('4 · fuera de rango se atenúa con su motivo', () {
    testWidgets('con tres jugadores High and Low no se puede elegir',
        (tester) async {
      final errores = await _hastaCompiten(tester, 3);
      expect(errores, isEmpty);
      expect(find.textContaining('High and Low se juega con 4, 5 o 6'),
          findsOneWidget);
      expect(find.textContaining('esta ronda tiene 3'), findsOneWidget);

      // Y tocarla no hace nada: sigue sin equipos.
      await tester.tap(find.text('High and Low'));
      await tester.pumpAndSettle();
      expect(find.text('CÓMO SE REPARTIÓ'), findsNothing);
      expect(find.text('EQUIPO A'), findsNothing);
    });

    testWidgets('pero Pair vs Field SÍ, porque con tres es 2 contra 1',
        (tester) async {
      // El contrapeso: si el motivo saliera siempre, el test de arriba pasaría
      // sin probar nada.
      await _hastaCompiten(tester, 3);
      expect(find.textContaining('Pair vs Field se juega con'), findsNothing);
      await tester.tap(find.text('Pair vs Field'));
      await tester.pumpAndSettle();
      expect(_delPanel(tester, 'EQUIPO A'), hasLength(2));
      expect(_delPanel(tester, 'EQUIPO B'), hasLength(1));
    });
  });

  group('5 · cabe a 320 px', () {
    testWidgets('con cinco jugadores y la formación armada', (tester) async {
      final errores =
          await _hastaCompiten(tester, 5, tamano: const Size(320, 1800));
      expect(errores, isEmpty);
      await tester.tap(find.text('High and Low'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
