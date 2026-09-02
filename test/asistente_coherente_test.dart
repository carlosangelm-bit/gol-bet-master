// ─────────────────────────────────────────────────────────────────────────────
// EL ASISTENTE DICE EL MISMO NÚMERO EN LOS CUATRO PASOS
//
// Este es el test que faltaba, y el hallazgo lo demostró: los tests verificaban
// que el modelo produjera tres módulos —y los producía— mientras cuatro
// pantallas contaban otra cosa. Compiten decía 3, Quién juega 10, Montos 1 y
// Revisar otra. Cada paso por separado parecía correcto; solo puestos en fila se
// veía que no cuadraban.
//
// Así que lo que se prueba no es un paso: es el RECORRIDO. Se avanza el
// asistente entero con cada formación que define lados y se exige que la cifra
// de enfrentamientos sea la misma en todos.
//
// Y no se prueba contra un número escrito a mano, sino contra el que dice el
// catálogo: si mañana una formación cambia de reparto, el test sigue midiendo lo
// que tiene que medir.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:golf_bet_master/models/formaciones.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/providers/organizador_provider.dart';
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

const gente = [
  ('Rafa', 4.0),
  ('Alan', 9.0),
  ('Memo', 18.0),
  ('Toño', 20.0),
  ('Beto', 22.0),
];

List<Player> _jugadores(int cuantos) => [
      for (final g in gente.take(cuantos))
        Player(id: 'pid_${g.$1.toLowerCase()}', name: g.$1, handicapBase: g.$2)
    ];

/// Abre el asistente con [cuantos] jugadores elegidos, en Compiten.
Future<List<String>> _hastaCompiten(WidgetTester tester, int cuantos) async {
  tester.view.physicalSize = const Size(390, 2200);
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
      // La marca de organizador: el logo de Inicio la consulta, así que un
      // harness sin ella no monta. Sembrada en false —una cuenta normal—
      // porque lo que estos tests miran es la app del jugador.
      ChangeNotifierProvider<OrganizadorProvider>(
          create: (_) => OrganizadorProvider()..sembrar(false)),
      ChangeNotifierProvider(create: (_) => TorneoProvider()),
      ChangeNotifierProvider(create: (_) => PerfilProvider()),
      ChangeNotifierProvider<PlayerProvider>.value(
          value: PlayerProvider()
            ..sembrar([
              for (final p in _jugadores(gente.length))
                PlayerWithLink(player: p)
            ])),
    ],
    child: const MaterialApp(home: SetupScreen()),
  ));
  await tester.pump(const Duration(milliseconds: 150));

  await tester.tap(find.text('Siguiente →'));
  await tester.pumpAndSettle();
  for (final g in gente.take(cuantos)) {
    final fila = find.text(g.$1);
    if (fila.evaluate().isEmpty) continue;
    await tester.ensureVisible(fila.first);
    await tester.pump();
    await tester.tap(fila.first);
    await tester.pump();
  }
  final sig = find.text('Siguiente →');
  await tester.ensureVisible(sig);
  await tester.pump();
  await tester.tap(sig);
  await tester.pumpAndSettle();

  FlutterError.onError = anterior;
  return errores;
}

/// Avanza al paso siguiente tantas veces como haga falta hasta encontrar
/// [titulo], o falla diciendo dónde se quedó.
Future<void> _avanzarHasta(WidgetTester tester, String titulo) async {
  for (var i = 0; i < 10; i++) {
    if (find.text(titulo).evaluate().isNotEmpty) return;
    // El paso Montos solo existe si hay alguna apuesta elegida, así que al
    // pasar por "¿Qué se cuenta?" se elige una. Es lo que haría un usuario.
    final atajo = find.text('Nassau');
    if (find.text('¿Qué se cuenta?').evaluate().isNotEmpty &&
        atajo.evaluate().isNotEmpty) {
      await tester.ensureVisible(atajo.first);
      await tester.pump();
      await tester.tap(atajo.first);
      await tester.pumpAndSettle();
    }
    final sig = find.text('Siguiente →');
    if (sig.evaluate().isEmpty) break;
    await tester.ensureVisible(sig.first);
    await tester.pump();
    await tester.tap(sig.first);
    await tester.pumpAndSettle();
  }
  expect(find.text(titulo), findsOneWidget,
      reason: 'no se llegó al paso "$titulo"');
}

/// Todos los textos de la pantalla, para buscar cifras.
String _pantalla(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .join(' · ');

void main() {
  // Las formaciones que definen lados, con cuántos enfrentamientos dan con
  // cinco jugadores. El número sale del catálogo, no escrito a mano.
  final casos = <(String, Formacion)>[
    ('Por equipos', Formacion.manual),
    ('High and Low', Formacion.highAndLow),
    ('Pair vs Field', Formacion.parejaVsResto),
    ('Pareja base contra el campo', Formacion.parejaBaseVsCampo),
  ];

  for (final caso in casos) {
    final esperados =
        enfrentamientosDe(caso.$2, _jugadores(5), parejaBase: const []).length;

    group('${caso.$1} · $esperados enfrentamiento(s) en todos los pasos', () {
      testWidgets('Compiten los enumera', (tester) async {
        final errores = await _hastaCompiten(tester, 5);
        expect(errores, isEmpty);
        await tester.tap(find.text(caso.$1));
        await tester.pumpAndSettle();
        expect(find.text('EQUIPO A'), findsOneWidget);
        if (esperados > 1) {
          expect(find.text('LOS ENFRENTAMIENTOS'), findsOneWidget);
          expect(find.textContaining('  vs  '), findsNWidgets(esperados));
        }
      });

      testWidgets('Montos dice la misma cifra, no "un enfrentamiento"',
          (tester) async {
        await _hastaCompiten(tester, 5);
        await tester.tap(find.text(caso.$1));
        await tester.pumpAndSettle();
        await _avanzarHasta(tester, 'Montos');

        final txt = _pantalla(tester);
        if (esperados == 1) {
          expect(txt, contains('Un enfrentamiento'));
        } else {
          expect(txt, contains('$esperados enfrentamientos'),
              reason: 'Montos no dice $esperados: $txt');
          expect(txt, isNot(contains('Un enfrentamiento')));
        }
      });

      testWidgets('Quién juega dice la misma cifra, no los cruces 1v1',
          (tester) async {
        await _hastaCompiten(tester, 5);
        await tester.tap(find.text(caso.$1));
        await tester.pumpAndSettle();
        await _avanzarHasta(tester, 'Montos');
        // El paso de participantes va antes de Montos cuando existe; si no
        // apareció, se busca hacia atrás.
        final atras = find.text('← Atrás');
        if (find.textContaining('jugadores · ').evaluate().isEmpty &&
            atras.evaluate().isNotEmpty) {
          await tester.tap(atras.first);
          await tester.pumpAndSettle();
        }
        final txt = _pantalla(tester);
        if (txt.contains('jugadores · ')) {
          expect(txt, contains('$esperados enfrentamiento'),
              reason: 'Quién juega no dice $esperados: $txt');
          // Y no enumera los diez cruces individuales.
          if (esperados < 10) {
            expect(txt, isNot(contains('10 enfrentamientos')));
          }
        }
      });

      testWidgets('Revisar enumera los enfrentamientos', (tester) async {
        await _hastaCompiten(tester, 5);
        await tester.tap(find.text(caso.$1));
        await tester.pumpAndSettle();
        await _avanzarHasta(
            tester, 'Toca una apuesta para cambiar sus reglas o sus montos.');

        final txt = _pantalla(tester);
        // El bloque de equipos nombra los enfrentamientos por sus jugadores.
        expect(txt, contains('Rafa'), reason: txt);
        if (esperados > 1) {
          expect(txt, contains('$esperados apuestas'), reason: txt);
        }
      });
    });
  }

  group('y con cuatro jugadores la pareja base no se ofrece', () {
    testWidgets('sale atenuada, así que no puede descuadrar nada',
        (tester) async {
      await _hastaCompiten(tester, 4);
      expect(
          find.textContaining('Pareja base contra el campo se juega con 5'),
          findsOneWidget);
    });
  });
}
