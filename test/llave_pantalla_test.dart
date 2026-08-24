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
import 'package:golf_bet_master/screens/torneos/torneo_editor_screen.dart';
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
  MetodoDePuntuacion metodo = MetodoDePuntuacion.dinero,
}) =>
    Torneo(
      id: 'tor_1',
      nombre: 'Match Play CGM',
      formato: FormatoDeTorneo.eliminacion,
      fuente: FuenteDeRondas.marcadas,
      metodo: metodo,
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

/// Monta la LISTA de torneos, que es donde vive la tarjeta del resumen.
Future<List<String>> _montarLista(
  WidgetTester tester, {
  required Torneo torneo,
  List<RoundResult> res = const [],
  bool conDirectorio = true,
}) async {
  tester.view.physicalSize = const Size(390, 1200);
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
      ChangeNotifierProvider<PlayerProvider>.value(
          value: PlayerProvider()
            ..sembrar(conDirectorio
                ? [
                    for (final e in nombres.entries)
                      PlayerWithLink(player: Player(id: e.key, name: e.value)),
                  ]
                : const [])),
      ChangeNotifierProvider<PerfilProvider>.value(
          value: PerfilProvider()..sembrar(res)),
      ChangeNotifierProvider<TorneoProvider>.value(
          value: TorneoProvider()..sembrar([torneo])),
    ],
    child: const MaterialApp(home: TorneosScreen()),
  ));
  await tester.pump(const Duration(milliseconds: 150));
  FlutterError.onError = anterior;
  return errores;
}

/// Monta el EDITOR del torneo.
Future<List<String>> _montarEditor(
  WidgetTester tester, {
  required Torneo torneo,
  // Alto de mentira a propósito: el editor es una lista larga y lazy, así que
  // sin esto las secciones de abajo no se construyen y "no está" se confunde con
  // "no se ha pintado todavía". Subió a 3200 al entrar la sección 2, que añade
  // tres bloques arriba de todo lo demás.
  Size tamano = const Size(390, 3200),
}) async {
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
      ChangeNotifierProvider<PlayerProvider>.value(
          value: PlayerProvider()
            ..sembrar([
              for (final e in nombres.entries)
                PlayerWithLink(player: Player(id: e.key, name: e.value)),
            ])),
      ChangeNotifierProvider<PerfilProvider>.value(
          value: PerfilProvider()..sembrar(const [])),
      ChangeNotifierProvider<TorneoProvider>.value(
          value: TorneoProvider()..sembrar([torneo])),
    ],
    child: MaterialApp(home: TorneoEditorScreen(existente: torneo)),
  ));
  await tester.pump(const Duration(milliseconds: 150));
  FlutterError.onError = anterior;
  return errores;
}

void main() {
  group('9 · el cuadro es un ÁRBOL, y llega a la vista de invitado', () {
    testWidgets('en la app: fases como columnas, no como lista apilada',
        (tester) async {
      final errores = await _montar(tester, torneo: _t());
      expect(errores, isEmpty);
      // Un scroll horizontal es la firma del árbol: la lista de antes no tenía.
      final horizontales = tester
          .widgetList<Scrollable>(find.byType(Scrollable))
          .where((x) => x.axis == Axis.horizontal);
      expect(horizontales, isNotEmpty, reason: 'el cuadro no rueda: no es árbol');
    });

    testWidgets('los huecos de la final dicen de dónde salen', (tester) async {
      final errores = await _montar(tester, torneo: _t());
      expect(errores, isEmpty);
      expect(find.textContaining('Ganador de Semifinales'), findsWidgets);
    });

    testWidgets('"a quién le toca" SIGUE arriba del árbol', (tester) async {
      // La decisión de antes se conserva: lo primero es tu partido pendiente y
      // su botón; el árbol es para entender el torneo, no para jugarlo.
      await _montar(tester, torneo: _t());
      final tocaY = tester.getTopLeft(find.text('A QUIÉN LE TOCA')).dy;
      final cuadroY = tester.getTopLeft(find.text('EL CUADRO')).dy;
      expect(tocaY, lessThan(cuadroY));
      expect(find.text('Crear la ronda de este partido'), findsWidgets);
    });

    testWidgets('cabe a 320 px con nombres largos', (tester) async {
      final errores = await _montar(tester,
          torneo: _t(), tamano: const Size(320, 1800));
      expect(errores, isEmpty);
    });
  });


  group('8 · el editor solo enseña lo que aplica al formato', () {
    // Las secciones de liga son las que quedaron a la vista con eliminación
    // marcada. Ninguna aplica: ganas el partido y pasas.
    const deLiga = [
      'Puntos por puesto',
      'SI DOS EMPATAN EN UNA RONDA',
      // Los números subieron uno al entrar "2 · CÓMO SE JUEGA UNA RONDA", que
      // es la sección que el modelo no tenía y cuya ausencia produjo cinco
      // parches. Se fija el número, no solo el texto, porque el orden de las
      // preguntas del editor es parte de lo que se está probando.
      '6 · CÓMO SE ACUMULA',
      '7 · CUÁNTAS RONDAS PARA OPTAR AL PREMIO',
    ];

    testWidgets('con eliminación no sale ninguna sección de liga',
        (tester) async {
      final errores = await _montarEditor(tester, torneo: _t());
      expect(errores, isEmpty);
      for (final txt in deLiga) {
        expect(find.textContaining(txt), findsNothing, reason: txt);
      }
    });

    testWidgets('con liga sí salen todas', (tester) async {
      // El contrapeso: sin este, esconderlas siempre pasaría el test de arriba.
      final errores = await _montarEditor(
          tester,
          torneo: Torneo(
              id: 'tor_1',
              nombre: 'Liga CGM',
              fuente: FuenteDeRondas.marcadas,
              metodo: MetodoDePuntuacion.posicion,
              participantes: const [ana, beto]));
      expect(errores, isEmpty);
      for (final txt in deLiga) {
        expect(find.textContaining(txt), findsWidgets, reason: txt);
      }
    });

    testWidgets('lo que SÍ aplica se queda: método, siembra y bote',
        (tester) async {
      final errores = await _montarEditor(tester, torneo: _t());
      expect(errores, isEmpty);
      expect(find.text('5 · QUIÉN GANA EL PARTIDO'), findsOneWidget);
      expect(find.text('LA SIEMBRA'), findsOneWidget);
      expect(find.text('8 · EL BOTE'), findsOneWidget);
      expect(find.text('4 · QUIÉN PARTICIPA'), findsOneWidget);
      // Y la nueva, que es la que faltaba.
      expect(find.text('2 · CÓMO SE JUEGA UNA RONDA'), findsOneWidget);
    });

    testWidgets('"por posición" no se ofrece, y se dice qué pasa con el guardado',
        (tester) async {
      // Match Play CGM se creó con "por posición" antes de esta corrección. No
      // se migra el documento: se dice lo que está pasando de verdad.
      final errores = await _montarEditor(tester,
          torneo: _t(metodo: MetodoDePuntuacion.posicion));
      expect(errores, isEmpty);
      expect(find.text('Por posición'), findsNothing);
      expect(find.textContaining('se guardó con "por posición"'),
          findsOneWidget);
      // Y el que se usa de verdad aparece marcado.
      expect(find.text('Por dinero ganado'), findsOneWidget);
    });

    testWidgets('el bote del cuadro no ofrece podio: dice que es del campeón',
        (tester) async {
      final errores = await _montarEditor(
          tester,
          torneo: Torneo(
            id: 'tor_1',
            nombre: 'Match Play',
            formato: FormatoDeTorneo.eliminacion,
            fuente: FuenteDeRondas.marcadas,
            metodo: MetodoDePuntuacion.dinero,
            participantes: const [ana, beto, caro, dani],
            bote: const BoteConfig(entrada: 500),
          ));
      expect(errores, isEmpty);
      expect(find.text('CÓMO SE REPARTE'), findsNothing);
      expect(find.text('Los tres primeros'), findsNothing);
      // Hay que bajar: con la sección nueva arriba, el bote se sale del alto que
      // el ListView construye. No es un fallo de la pantalla —es lazy a
      // propósito— pero el test tiene que llegar hasta donde mira.
      await tester.dragUntilVisible(
          find.textContaining('quien gane la final'),
          find.byType(ListView),
          const Offset(0, -300));
      expect(find.textContaining('quien gane la final'), findsOneWidget);
    });
  });

  group('7 · la tarjeta de la lista: nombres y estado del cuadro', () {
    testWidgets('un inscrito sin rondas sale con su NOMBRE, nunca con su id',
        (tester) async {
      // "Va 6uX3jmCVlYNxCJxWBJQe" era esto: el inscrito venía del directorio y
      // no de una ronda jugada, así que no había playerNames donde buscarlo.
      final errores = await _montarLista(tester,
          torneo: Torneo(
              id: 'tor_1',
              nombre: 'Liga CGM',
              fuente: FuenteDeRondas.marcadas,
              participantes: const [ana, beto]));
      expect(errores, isEmpty);
      expect(find.textContaining(ana), findsNothing,
          reason: 'un id de Firestore en la primera pantalla');
      expect(find.textContaining(beto), findsNothing);
    });

    testWidgets('un cuadro NO se resume por rondas y posición', (tester) async {
      final errores = await _montarLista(tester, torneo: _t());
      expect(errores, isEmpty);
      expect(find.textContaining('Por posición'), findsNothing);
      expect(find.textContaining('0 rondas'), findsNothing);
      // Lo que sí: en qué punto está el cuadro.
      expect(find.textContaining('Semifinales'), findsOneWidget);
      expect(find.textContaining('Eliminación · 4 inscritos'), findsOneWidget);
    });

    testWidgets('y cuando termina, el campeón', (tester) async {
      final errores = await _montarLista(tester, torneo: _t(), res: [
        _r('s1', 7, {ana: 300, dani: -300}),
        _r('s2', 8, {beto: 200, caro: -200}),
        _r('fin', 20, {ana: 500, beto: -500}),
      ]);
      expect(errores, isEmpty);
      expect(find.textContaining('Campeón: ${nombres[ana]}'), findsOneWidget);
    });

    testWidgets('una liga se sigue resumiendo como liga', (tester) async {
      // El contrapeso: la rama nueva no puede haberse comido la vieja.
      final errores = await _montarLista(
          tester,
          torneo: Torneo(
              id: 'tor_1',
              nombre: 'Liga CGM',
              fuente: FuenteDeRondas.marcadas,
              participantes: const [ana, beto]),
          res: [_r('r1', 7, {ana: 100, beto: -100})]);
      expect(errores, isEmpty);
      expect(find.textContaining('1 ronda'), findsOneWidget);
      expect(find.textContaining('Va ${nombres[ana]}'), findsOneWidget);
    });

    testWidgets('sin directorio sale un guion, no el id', (tester) async {
      final errores = await _montarLista(tester,
          torneo: Torneo(
              id: 'tor_1',
              nombre: 'Liga CGM',
              fuente: FuenteDeRondas.marcadas,
              participantes: const [ana, beto]),
          conDirectorio: false);
      expect(errores, isEmpty);
      expect(find.textContaining(ana), findsNothing);
    });

    testWidgets('cabe a 320 px con nombres largos', (tester) async {
      final errores = await _montarLista(tester,
          torneo: _t(),
          res: [
            _r('s1', 7, {ana: 300, dani: -300}),
          ]);
      expect(errores, isEmpty);
      tester.view.physicalSize = const Size(320, 1200);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });


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
      // Y la final espera. El árbol no deja un hueco vacío: dice DE DÓNDE va a
      // salir cada plaza, que es lo que la lista de antes no decía.
      expect(find.textContaining('Ganador de Semifinales'), findsNWidgets(2));
      expect(find.text('Por decidir'), findsNothing);
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
      // El árbol lo dice en la celda —"sin rival"— y debajo explica cuántos y
      // por qué, que es el criterio 5.
      expect(find.textContaining('Sin rival: pasa directo'), findsWidgets);
      expect(find.textContaining('sin jugar la primera fase'), findsOneWidget);
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
