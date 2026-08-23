// ─────────────────────────────────────────────────────────────────────────────
// EL CUADRO EN PANTALLA
//
// El motor se prueba puro en llave_test. Esto prueba lo que aquello no puede:
// que el cuadro se PINTE, que quepa a 320 px y que un empate ofrezca resolverse.
//
// El caso de geometría es el que ya salió tres veces en esta app: figura y
// etiqueta en un Row con dos Text sin restringir. Aquí son el trofeo y el nombre
// del campeón, así que va con nombres largos —los reales lo son— y en el teléfono
// más estrecho.
//
// Y hay un test de alcanzabilidad: código correcto que la app no abre por ningún
// sitio ya me pasó tres veces en esta sesión.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:golf_bet_master/models/round_result.dart';
import 'package:golf_bet_master/models/torneo.dart';
import 'package:golf_bet_master/providers/auth_provider.dart';
import 'package:golf_bet_master/providers/betting_group_provider.dart';
import 'package:golf_bet_master/providers/handicap_provider.dart';
import 'package:golf_bet_master/providers/perfil_provider.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/providers/player_provider.dart';
import 'package:golf_bet_master/services/player_service.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/providers/torneo_provider.dart';
import 'package:golf_bet_master/providers/user_profile_provider.dart';
import 'package:golf_bet_master/screens/torneos/torneos_screen.dart';

const ana = 'pid_7f3a91', beto = 'pid_2c8e04';
const caro = 'pid_b5d117', dani = 'pid_9a4f22';

// Nombres largos de verdad: es como se llama la gente, y es donde reventaba.
const nombres = {
  ana: 'María Fernanda Villalobos',
  beto: 'Juan Carlos Betancourt',
  caro: 'Carolina Sanmartín',
  dani: 'Daniel Alejandro Ruiz',
};

RoundResult _r(String id, int dia, Map<String, double> dinero) => RoundResult(
      roundId: id,
      roundName: 'Sábado $dia',
      courseName: 'Los Encinos',
      playedAt: DateTime(2026, 3, dia),
      holesPlayed: 18,
      playerIds: dinero.keys.toList(),
      playerNames: {for (final k in dinero.keys) k: nombres[k] ?? k},
      balances: dinero,
      pairBalances: const {},
      grossByPlayer: const {},
      netByPlayer: const {},
      stablefordByPlayer: const {},
      bettingGroupIds: const [],
      torneoIds: const ['tor_1'],
    );

Torneo _t({
  List<String> participantes = const [ana, beto, caro, dani],
  Map<String, String> desempates = const {},
}) =>
    Torneo(
      id: 'tor_1',
      nombre: 'Match Play CGM',
      formato: FormatoDeTorneo.eliminacion,
      fuente: FuenteDeRondas.marcadas,
      metodo: MetodoDePuntuacion.dinero,
      participantes: participantes,
      desempates: desempates,
    );

/// Monta la pantalla del torneo y devuelve los errores de layout.
Future<List<String>> _montar(
  WidgetTester tester, {
  required Torneo torneo,
  List<RoundResult> res = const [],
  Size tamano = const Size(390, 1400),
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final errores = <String>[];
  final anterior = FlutterError.onError;
  // Cualquier error, no solo overflow: una pantalla que no construye pasaba en
  // verde cuando el filtro solo miraba desbordes.
  FlutterError.onError = (d) => errores.add(d.exceptionAsString());

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => RoundProvider()),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      // El directorio SEMBRADO: es de donde salen los nombres del cuadro. Con
      // uno vacío se probaría el camino de respaldo en vez del real, y un cuadro
      // recién creado —sin rondas todavía— saldría con guiones.
      ChangeNotifierProvider<PlayerProvider>.value(
          value: PlayerProvider()
            ..sembrar([
              for (final e in nombres.entries)
                PlayerWithLink(player: Player(id: e.key, name: e.value)),
            ])),
      ChangeNotifierProvider(create: (_) => HandicapProvider()),
      ChangeNotifierProvider(create: (_) => UserProfileProvider()),
      ChangeNotifierProvider(create: (_) => BettingGroupProvider()),
      ChangeNotifierProvider<PerfilProvider>.value(
          value: PerfilProvider()..sembrar(res)),
      ChangeNotifierProvider<TorneoProvider>.value(
          value: TorneoProvider()..sembrar([torneo])),
    ],
    child: MaterialApp(home: TorneoTablaScreen(torneo: torneo)),
  ));
  await tester.pump(const Duration(milliseconds: 150));
  FlutterError.onError = anterior;
  return errores;
}

void main() {
  group('1 · el cuadro se pinta', () {
    testWidgets('con cuatro inscritos salen los cruces y la final',
        (tester) async {
      final errores = await _montar(tester, torneo: _t());
      expect(errores, isEmpty);
      expect(find.text('EL CUADRO'), findsOneWidget);
      expect(find.text('SEMIFINALES'), findsOneWidget);
      expect(find.text('FINAL'), findsOneWidget);
      // Los dos cruces de la primera ronda, con los cuatro nombres.
      for (final n in nombres.values) {
        expect(find.text(n), findsWidgets, reason: n);
      }
      // Y la final espera: dos plazas por decidir.
      expect(find.text('Por decidir'), findsNWidgets(2));
    });

    testWidgets('a quién le toca va ARRIBA, con el botón de crear la ronda',
        (tester) async {
      // Es la pregunta que trae a alguien a esta pantalla. Un cuadro entero de
      // ocho no la responde de un vistazo.
      final errores = await _montar(tester, torneo: _t());
      expect(errores, isEmpty);
      expect(find.text('A QUIÉN LE TOCA'), findsOneWidget);
      expect(find.text('Crear la ronda de este partido'), findsNWidgets(2));

      final tocaY = tester.getTopLeft(find.text('A QUIÉN LE TOCA')).dy;
      final cuadroY = tester.getTopLeft(find.text('EL CUADRO')).dy;
      expect(tocaY, lessThan(cuadroY),
          reason: 'el cuadro entero es para consultar, no para empezar');
    });

    testWidgets('y el cuadro va antes de la tabla acumulada', (tester) async {
      final errores = await _montar(tester, torneo: _t());
      expect(errores, isEmpty);
      final cuadroY = tester.getTopLeft(find.text('EL CUADRO')).dy;
      final tablaY =
          tester.getTopLeft(find.text('Y LA CUENTA DE SIEMPRE')).dy;
      expect(cuadroY, lessThan(tablaY));
    });

    testWidgets('una liga no enseña cuadro ninguno', (tester) async {
      final errores = await _montar(tester,
          torneo: Torneo(
              id: 'tor_1',
              nombre: 'Liga',
              fuente: FuenteDeRondas.marcadas,
              participantes: const [ana, beto]));
      expect(errores, isEmpty);
      expect(find.text('EL CUADRO'), findsNothing);
      expect(find.text('A QUIÉN LE TOCA'), findsNothing);
    });
  });

  group('2 · el campeón, y que quepa', () {
    List<RoundResult> temporada() => [
          _r('c1', 7, {ana: 300, dani: -300}),
          _r('c2', 8, {beto: 200, caro: -200}),
          _r('fin', 20, {ana: 500, beto: -500}),
        ];

    testWidgets('sale el campeón cuando la final está jugada', (tester) async {
      final errores = await _montar(tester, torneo: _t(), res: temporada());
      expect(errores, isEmpty);
      expect(find.text('CAMPEÓN'), findsOneWidget);
      expect(find.text(nombres[ana]!), findsWidgets);
      // Y ya no queda nada por jugar.
      expect(find.text('A QUIÉN LE TOCA'), findsNothing);
    });

    testWidgets('cabe a 320 px con nombres largos', (tester) async {
      // El overflow de figura + etiqueta en un Row ya salió tres veces. El
      // trofeo con el nombre del campeón al lado es exactamente esa forma.
      final errores = await _montar(tester,
          torneo: _t(), res: temporada(), tamano: const Size(320, 1600));
      expect(errores, isEmpty,
          reason: 'a 320 px es donde se ve, y la gente se llama así');
    });

    testWidgets('se dice CON QUÉ RONDA pasó cada uno', (tester) async {
      // Un cuadro sin el motivo es un veredicto: hace discutir el número en vez
      // de la regla.
      final errores = await _montar(tester, torneo: _t(), res: temporada());
      expect(errores, isEmpty);
      expect(find.textContaining('Se resolvió en Sábado 20'), findsOneWidget);
    });
  });

  group('3 · el empate se ofrece resolver, no se resuelve solo', () {
    List<RoundResult> conEmpate() => [
          _r('c1', 7, {ana: 0, dani: 0}),
        ];

    testWidgets('sale el aviso y los dos botones', (tester) async {
      final errores =
          await _montar(tester, torneo: _t(), res: conEmpate());
      expect(errores, isEmpty);
      expect(find.text('HAY QUE DESEMPATAR'), findsOneWidget);
      expect(find.text('Pasa ${nombres[ana]}'), findsOneWidget);
      expect(find.text('Pasa ${nombres[dani]}'), findsOneWidget);
      // Y nadie ha pasado por su cuenta.
      expect(find.text('CAMPEÓN'), findsNothing);
    });

    testWidgets('el aviso va arriba de todo: bloquea el cuadro',
        (tester) async {
      await _montar(tester, torneo: _t(), res: conEmpate());
      final empateY = tester.getTopLeft(find.text('HAY QUE DESEMPATAR')).dy;
      final cuadroY = tester.getTopLeft(find.text('EL CUADRO')).dy;
      expect(empateY, lessThan(cuadroY));
    });

    testWidgets('resuelto a mano, el cuadro sigue y se dice que fue a mano',
        (tester) async {
      final errores = await _montar(tester,
          torneo: _t(desempates: {parKey(ana, dani): ana}),
          res: conEmpate());
      expect(errores, isEmpty);
      expect(find.text('HAY QUE DESEMPATAR'), findsNothing);
      expect(find.textContaining('Lo decidisteis vosotros'), findsOneWidget);
    });

    testWidgets('cabe a 320 px: dos nombres largos en dos botones',
        (tester) async {
      final errores = await _montar(tester,
          torneo: _t(), res: conEmpate(), tamano: const Size(320, 1600));
      expect(errores, isEmpty);
    });
  });

  group('4 · los byes se explican', () {
    testWidgets('con tres inscritos se dice cuántos pasan sin jugar',
        (tester) async {
      final errores = await _montar(tester,
          torneo: _t(participantes: const [ana, beto, caro]));
      expect(errores, isEmpty);
      expect(find.textContaining('Pasa sin jugar'), findsWidgets);
      expect(find.textContaining('sin jugar la primera ronda'), findsOneWidget);
    });
  });

  group('6 · el atajo lleva de verdad a configurar la ronda', () {
    // Tres veces en esta sesión escribí código correcto al que la app no llegaba
    // por ningún sitio. El botón tiene que ABRIR algo, no solo estar.
    testWidgets('abre el asistente con los dos del partido y el torneo marcado',
        (tester) async {
      await _montar(tester, torneo: _t());
      final boton = find.text('Crear la ronda de este partido');
      await tester.ensureVisible(boton.first);
      await tester.pump();
      await tester.tap(boton.first);
      await tester.pumpAndSettle();

      // El asistente, abierto en el primer paso.
      expect(find.text('Paso 1 de 7 · Campo'), findsOneWidget);

      // Y los DOS del partido ya dentro: el atajo trae la nómina, no solo abre
      // la pantalla. Se comprueba en el paso de jugadores, que es donde se ven.
      await tester.tap(find.text('Siguiente →'));
      await tester.pumpAndSettle();
      expect(find.text(nombres[ana]!), findsWidgets);
      expect(find.text(nombres[dani]!), findsWidgets);
    });
  });

  group('5 · sin inscritos se dice qué falta, no se enseña vacío', () {
    testWidgets('el motivo nombra los participantes', (tester) async {
      final errores =
          await _montar(tester, torneo: _t(participantes: const []));
      expect(errores, isEmpty);
      expect(find.textContaining('Define primero los participantes'),
          findsWidgets);
      expect(find.text('EL CUADRO'), findsNothing);
    });
  });
}
