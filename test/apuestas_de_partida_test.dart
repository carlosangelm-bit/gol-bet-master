// ─────────────────────────────────────────────────────────────────────────────
// UN GRUPO GUARDADO PUEDE LLEVAR APUESTAS DE PARTIDA
//
// El hueco: BettingGroup solo tenía pairRules, y toBetModuleInstancesForToday
// crea CADA módulo con exactamente dos participantes. Así que Snake, Rabbit,
// Wolf, Oyes y Unidades no cabían en un grupo guardado, y el atajo de "Lo de
// siempre" dejaba de ser lo de siempre: había que añadirlas a mano cada ronda.
//
// Lo que se decidió, y es lo que estos tests fijan:
//
//   · Una apuesta de partida sale con TODOS los presentes, no con una pareja.
//   · Puede DEJAR DE SER JUGABLE según quién venga. Eso no pasa con los duelos
//     —un duelo simplemente no se activa si falta uno de los dos— y es la
//     diferencia que obligó a un concepto nuevo.
//   · No se prohíbe guardar los formatos con requisito de tamaño. El grupo de
//     los viernes puede ser de seis y jugar Wolf casi todos los sábados porque
//     suelen faltar dos; prohibirlo por lo que pasa cuando vienen todos sería
//     quitarle el formato el resto de las veces. Se guarda, y se avisa.
//   · Lo NO jugable se queda fuera de la ronda en vez de entrar y no liquidar.
//     Es el fallo que Medal y Putts tenían con los equipos.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/providers/player_provider.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/providers/auth_provider.dart';
import 'package:golf_bet_master/screens/setup/quick_start_screen.dart';

const a = 'a', b = 'b', c = 'c', d = 'd', e = 'e', f = 'f';
const seis = [a, b, c, d, e, f];
const cuatro = [a, b, c, d];

BettingGroup _grupo({
  List<String> habituales = cuatro,
  List<BetModuleType> dePartida = const [],
  bool conDuelos = true,
}) {
  final reglas = <PairBetRule>[];
  if (conDuelos) {
    for (var i = 0; i < habituales.length; i++) {
      for (var j = i + 1; j < habituales.length; j++) {
        reglas.add(PairBetRule(
          id: 'r${habituales[i]}${habituales[j]}',
          playerAId: habituales[i],
          playerBId: habituales[j],
          modules: [BetModuleTemplate.defaultFor(BetModuleType.skins)],
        ));
      }
    }
  }
  return BettingGroup(
    id: 'g', name: 'Los viernes',
    playerIds: habituales,
    pairRules: reglas,
    modulosDePartida:
        dePartida.map((t) => BetModuleTemplate.defaultFor(t)).toList(),
    updatedAt: DateTime(2026, 1, 1),
  );
}

List<BetModuleInstance> _modulos(BettingGroup g, List<String> presentes) =>
    g.toBetModuleInstancesForToday(
        presentes: presentes, betGroupId: 'bg', betGroupName: g.name);

void main() {
  _enElArranqueRapido();

  group('1 · lo aditivo no cambia nada de lo que había', () {
    test('un grupo sin apuestas de partida se comporta igual', () {
      final g = _grupo();
      expect(g.modulosDePartida, isEmpty);
      // C(4,2) = 6 duelos con una skins cada uno.
      expect(_modulos(g, cuatro), hasLength(6));
      expect(_modulos(g, cuatro).every((m) => m.participantIds.length == 2),
          isTrue);
    });

    test('el JSON de un grupo sin ellas no gana una clave vacía', () {
      expect(_grupo().toJson().containsKey('modulosDePartida'), isFalse);
    });

    test('un grupo guardado ANTES de que existiera el campo se lee igual', () {
      // Es el criterio 3: los grupos existentes no tienen la clave.
      final viejo = {
        'id': 'g', 'name': 'Los viernes', 'emoji': '⛳',
        'playerIds': cuatro,
        'pairRules': const [],
        'updatedAt': '2026-01-01T00:00:00.000',
      };
      final g = BettingGroup.fromJson(Map<String, dynamic>.from(viejo));
      expect(g.modulosDePartida, isEmpty);
      expect(_modulos(g, cuatro), isEmpty);
    });
  });

  group('2 · una apuesta de partida sale con TODOS los presentes', () {
    test('Snake entra con los cuatro, no con una pareja', () {
      final g = _grupo(dePartida: [BetModuleType.snake]);
      final snake = _modulos(g, cuatro)
          .where((m) => m.type == BetModuleType.snake);
      expect(snake, hasLength(1), reason: 'UNA serpiente, no una por pareja');
      expect(snake.single.participantIds.toSet(), cuatro.toSet());
    });

    test('y con los presentes de hoy, no con los habituales', () {
      // Si tomara playerIds del grupo, un ausente entraría en la serpiente y su
      // score faltante dejaría el hoyo sin capturar para siempre.
      final g = _grupo(habituales: seis, dePartida: [BetModuleType.snake]);
      final snake = _modulos(g, cuatro)
          .where((m) => m.type == BetModuleType.snake)
          .single;
      expect(snake.participantIds.toSet(), cuatro.toSet());
    });

    test('varias a la vez, y conviven con los duelos', () {
      final g = _grupo(dePartida: [
        BetModuleType.snake,
        BetModuleType.rabbit,
        BetModuleType.oyeses,
        BetModuleType.units,
      ]);
      final mods = _modulos(g, cuatro);
      expect(mods.where((m) => m.participantIds.length == 4), hasLength(4));
      expect(mods.where((m) => m.participantIds.length == 2), hasLength(6));
    });

    test('los ids de los módulos no colisionan', () {
      // Con un id repetido, el segundo sobreescribiría al primero al guardarse.
      final g = _grupo(dePartida: [
        BetModuleType.snake, BetModuleType.rabbit, BetModuleType.oyeses,
      ]);
      final ids = _modulos(g, cuatro).map((m) => m.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('un grupo con SOLO apuestas de partida funciona', () {
      // Sin esto, un grupo sin duelos no produciría nada y el arranque diría
      // "no hay duelos activos" teniendo una serpiente guardada.
      final g = _grupo(conDuelos: false, dePartida: [BetModuleType.snake]);
      expect(_modulos(g, cuatro), hasLength(1));
    });
  });

  group('3 · la config guardada viaja con la apuesta', () {
    test('el monto de Snake sobrevive el guardado y la vuelta', () {
      final tpl = BetModuleTemplate.fromInstance(BetModuleInstance
          .defaultFor(BetModuleType.snake, cuatro, id: 'x')
          .copyWith(snakeConfig: const SnakeConfig(value: 250, umbral: 4)));
      final g = BettingGroup(
          id: 'g', name: 'G', playerIds: cuatro,
          modulosDePartida: [tpl], updatedAt: DateTime(2026, 1, 1));

      final vuelta =
          BettingGroup.fromJson(Map<String, dynamic>.from(g.toJson()));
      expect(vuelta.modulosDePartida, hasLength(1));

      final mod = _modulos(vuelta, cuatro)
          .where((m) => m.type == BetModuleType.snake)
          .single;
      expect(mod.snake.value, 250);
      expect(mod.snake.umbral, 4);
    });
  });

  group('4 · puede dejar de ser jugable según quién venga', () {
    test('Wolf con seis presentes NO entra en la ronda', () {
      // El caso delicado. Entrar y no liquidar es el fallo que Medal y Putts
      // tenían con los equipos: la apuesta aparece configurada, con su monto, y
      // no paga nada.
      final g = _grupo(habituales: seis, dePartida: [BetModuleType.wolf]);
      expect(_modulos(g, seis).where((m) => m.type == BetModuleType.wolf),
          isEmpty);
    });

    test('y con cuatro sí', () {
      final g = _grupo(habituales: seis, dePartida: [BetModuleType.wolf]);
      final wolf = _modulos(g, cuatro)
          .where((m) => m.type == BetModuleType.wolf);
      expect(wolf, hasLength(1));
      expect(wolf.single.participantIds, hasLength(4));
    });

    test('con cinco también: el rango es 4 o 5', () {
      final g = _grupo(habituales: seis, dePartida: [BetModuleType.wolf]);
      expect(_modulos(g, const [a, b, c, d, e])
          .where((m) => m.type == BetModuleType.wolf), hasLength(1));
    });

    test('el motivo se puede leer, y es el MISMO que atenúa el selector', () {
      final g = _grupo(habituales: seis, dePartida: [BetModuleType.wolf]);
      final hoy = g.modulosDePartidaHoy(seis).single;
      expect(hoy.jugable, isFalse);
      expect(hoy.motivo, BetModuleType.wolf.motivoNoDisponible(6),
          reason: 'una sola respuesta a "se puede jugar con esta gente"');
      expect(hoy.motivo, contains('4 o 5'));
    });

    test('Snake, Rabbit, Oyes y Unidades no tienen requisito de tamaño', () {
      // El contrapeso: si todo se filtrara, los tests de arriba pasarían igual
      // y ninguna apuesta de partida llegaría nunca.
      final g = _grupo(habituales: seis, dePartida: [
        BetModuleType.snake, BetModuleType.rabbit,
        BetModuleType.oyeses, BetModuleType.units,
      ]);
      expect(g.modulosDePartidaHoy(seis).every((x) => x.jugable), isTrue);
      expect(g.modulosDePartidaHoy(const [a, b]).every((x) => x.jugable),
          isTrue);
    });

    test('quitar un jugador puede VOLVER jugable un Wolf', () {
      // Es lo que hace que avisar sea mejor que prohibir: el mismo grupo
      // guardado sirve los días que falta gente.
      final g = _grupo(habituales: seis, dePartida: [BetModuleType.wolf]);
      expect(g.modulosDePartidaHoy(seis).single.jugable, isFalse);
      expect(g.modulosDePartidaHoy(const [a, b, c, d, e]).single.jugable,
          isTrue);
    });
  });

  group('5 · el recuento del grupo las incluye', () {
    test('totalModules suma duelos y partida', () {
      final g = _grupo(dePartida: [BetModuleType.snake, BetModuleType.rabbit]);
      // 6 duelos × 1 skins + 2 de partida.
      expect(g.totalModules, 8);
    });
  });

  group('6 · qué tipos pueden ir aquí sale de la marca', () {
    test('los candidatos son exactamente los que declaran deLaPartida', () {
      // El criterio 5: la sección del editor consume la marca, no una lista. Si
      // mañana entra otro formato de partida, aparece solo.
      final candidatos =
          creatableBetTypes.where((t) => t.rules.deLaPartida).toSet();
      expect(candidatos, {
        BetModuleType.oyeses,
        BetModuleType.units,
        BetModuleType.snake,
        BetModuleType.rabbit,
        BetModuleType.wolf,
      });
    });

    test('y son justo los que la hoja de duelos atenúa por ser de partida', () {
      // Las dos superficies leen la misma marca, así que no pueden discrepar:
      // lo que una manda a "ponla en la partida" es lo que la otra ofrece.
      for (final t in creatableBetTypes) {
        if (!t.rules.deLaPartida) continue;
        expect(t.sePactaPorDuelo, isFalse, reason: t.label);
      }
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Y SE DICE EN EL ARRANQUE RÁPIDO, ANTES DE EMPEZAR
//
// Los tests de arriba comprueban la decisión; esto comprueba que la pantalla la
// cuenta. Es el criterio que no se puede cubrir con lógica: que una apuesta
// guardada y hoy no jugable se lea ANTES del primer hoyo y no se descubra en el
// tee del uno.
//
// Es el mismo criterio de las tarjetas de punto de partida: decir qué falta por
// decidir en vez de encontrarlo después.
// ─────────────────────────────────────────────────────────────────────────────
void _enElArranqueRapido() {
  Future<void> montar(WidgetTester tester, BettingGroup g) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PlayerProvider()),
        ChangeNotifierProvider(create: (_) => RoundProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: MaterialApp(home: QuickStartScreen(grupo: g)),
    ));
    await tester.pump(const Duration(milliseconds: 200));
  }

  group('7 · el arranque rápido lo cuenta', () {
    testWidgets('las jugables salen en el resumen, con su nombre',
        (tester) async {
      await montar(tester,
          _grupo(dePartida: [BetModuleType.snake, BetModuleType.rabbit]));
      expect(find.textContaining('2 de partida'), findsOneWidget);
      expect(find.textContaining('Snake'), findsWidgets);
      expect(find.textContaining('Rabbit'), findsWidgets);
      // Y NO hay aviso: con cuatro las dos entran.
      expect(find.text('HOY NO ENTRA'), findsNothing);
    });

    testWidgets('la que hoy no entra se dice, con su motivo', (tester) async {
      // Grupo de seis con Wolf guardado: hoy vienen los seis y no es jugable.
      await montar(tester,
          _grupo(habituales: seis, dePartida: [BetModuleType.wolf]));
      expect(find.text('HOY NO ENTRA'), findsOneWidget);
      expect(find.textContaining('4 o 5'), findsWidgets,
          reason: 'el motivo, no solo que no entra');
      expect(find.textContaining('Sigue guardada en el grupo'), findsOneWidget,
          reason: 'y que no se pierde, que es la otra mitad del aviso');
    });

    testWidgets('con una jugable y otra no, se dicen las dos cosas',
        (tester) async {
      // El contrapeso: si el aviso tapara el resumen, o al revés, uno de los dos
      // tests de arriba pasaría igual y el usuario perdería la mitad.
      await montar(
          tester,
          _grupo(
              habituales: seis,
              dePartida: [BetModuleType.snake, BetModuleType.wolf]));
      expect(find.textContaining('1 de partida'), findsOneWidget);
      expect(find.text('HOY NO ENTRA'), findsOneWidget);
    });

    testWidgets('un grupo sin apuestas de partida no enseña nada de esto',
        (tester) async {
      await montar(tester, _grupo());
      expect(find.textContaining('de partida'), findsNothing);
      expect(find.text('HOY NO ENTRA'), findsNothing);
    });
  });
}
