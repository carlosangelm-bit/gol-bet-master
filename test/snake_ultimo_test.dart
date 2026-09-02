// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';
// SNAKE — QUIÉN SE LA QUEDA CON DOS 3-PUTTS
//
// «Es el último en la secuencia del hoyo.» Y eso no se podía saber: la app
// registra QUIÉN hizo tres putts, no en qué orden.
//
// ── El criterio que decide si esto estorba ──────────────────────────────────
//
// «Snake se juega en rondas normales donde la mayoría de los hoyos no tienen ni
// un 3-putt. Si la pregunta asoma cuando no toca, el remedio es peor que la
// regla que falta.»
//
// Por eso el grupo 1 no prueba la pregunta: prueba que NO ESTÁ. Es el que
// decide si la entrega vale.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/engines/snake_engine.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/screens/capture/capture_screen.dart';

const _cuatro = ['ana', 'beto', 'caro', 'dani'];
const _nombres = {
  'ana': 'Ana Robles',
  'beto': 'Beto Lara',
  'caro': 'Caro Díaz',
  'dani': 'Dani Sosa',
};

CourseInfo _campo() => CourseInfo(
      name: 'Los Encinos',
      holes: List.generate(
          18, (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)),
    );

/// Una ronda con Snake pactado y los putts que se digan.
///
/// [putts] es hoyo → (jugador → putts). Lo que no esté va a un putt, que no
/// pasa ningún umbral.
Round _ronda({
  required Map<int, Map<String, int>> putts,
  Map<int, String> ultimo = const {},
  bool conSnake = true,
  int umbral = 3,
}) {
  final ps = _cuatro.map((i) => Player(id: i, name: _nombres[i]!)).toList();
  return Round(
    id: 'r',
    name: 'Sábado',
    course: _campo(),
    players: ps,
    roundPlayers:
        ps.map((p) => RoundPlayer(playerId: p.id, handicapEnRonda: 0)).toList(),
    betGroups: [
      BetGroup(
        id: 'g',
        name: 'G',
        format: PartidaFormat.allInOnePot,
        playerIds: _cuatro,
        modules: [
          if (conSnake)
            BetModuleInstance.defaultFor(BetModuleType.snake, _cuatro, id: 'sn')
                .copyWith(snakeConfig: SnakeConfig(value: 100, umbral: umbral)),
          BetModuleInstance.defaultFor(BetModuleType.skins, _cuatro, id: 'sk'),
        ],
      ),
    ],
    scores: {
      for (final p in ps)
        p.id: {
          for (var h = 1; h <= 18; h++)
            h: HoleScore(
                playerId: p.id,
                hole: h,
                grossScore: 4,
                putts: putts[h]?[p.id] ?? 1),
        },
    },
    events: const {},
    oyeseRankings: const {},
    sliding: const [],
    createdAt: DateTime(2026, 9, 2),
    totalHoles: 18,
    ultimoEnPasarElUmbral: ultimo,
  );
}

Future<RoundProvider> _montar(WidgetTester tester, Round r) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final prov = RoundProvider()..startRound(r);
  await tester.pumpWidget(MultiProvider(
    providers: [ChangeNotifierProvider<RoundProvider>.value(value: prov)],
    child: MaterialApp(
      home: Scaffold(
        body: SnakeUltimoSection(hole: 7, t: GolfTheme.classic),
      ),
    ),
  ));
  await tester.pump();
  return prov;
}

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('1 · CRITERIO 2: fuera del caso raro no aparece nada', () {
    testWidgets('CLAVE: sin ningún 3-putt, ni un píxel', (tester) async {
      // La mayoría de los hoyos de una ronda normal. Si aquí hay algo, la
      // funcionalidad estorba dieciséis veces por ronda para servir dos.
      await _montar(tester, _ronda(putts: const {}));
      expect(find.byType(Wrap), findsNothing);
      expect(find.textContaining('último'), findsNothing);
    });

    testWidgets('CLAVE: con UNO solo tampoco — ya se sabe de quién es',
        (tester) async {
      await _montar(tester, _ronda(putts: const {7: {'ana': 3}}));
      expect(find.textContaining('último'), findsNothing);
    });

    testWidgets('CLAVE: y sin Snake pactado, nada — aunque haya cinco',
        (tester) async {
      // La pregunta existe para resolver una apuesta. Sin la apuesta no hay
      // nada que resolver, y preguntar sería pedir un dato que no se usa.
      await _montar(
          tester,
          _ronda(
              conSnake: false,
              putts: const {
                7: {'ana': 3, 'beto': 4, 'caro': 3}
              }));
      expect(find.textContaining('último'), findsNothing);
    });

    testWidgets('CONTRAPESO: y con DOS sí aparece', (tester) async {
      // Sin esto, una sección que nunca se pinta pasaría los tres de arriba.
      await _montar(
          tester,
          _ronda(putts: const {
            7: {'ana': 3, 'beto': 3}
          }));
      expect(find.textContaining('¿Quién fue el último?'), findsOneWidget);
      expect(find.text('Ana Robles'), findsOneWidget);
      expect(find.text('Beto Lara'), findsOneWidget);
      // Y no ofrece a quien no pasó el umbral.
      expect(find.text('Caro Díaz'), findsNothing);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('2 · la pregunta, y lo que dice', () {
    testWidgets('CLAVE: dice CUÁNTOS y con qué umbral', (tester) async {
      await _montar(
          tester,
          _ronda(putts: const {
            7: {'ana': 3, 'beto': 4}
          }));
      expect(find.textContaining('2 con 3 putts o más'), findsOneWidget);
    });

    testWidgets('CLAVE: y con TRES sigue siendo una línea de nombres',
        (tester) async {
      // El criterio 3 del encargo. Wrap y no Row: tres nombres largos en una
      // fila se salen por la derecha.
      await _montar(
          tester,
          _ronda(putts: const {
            7: {'ana': 3, 'beto': 3, 'caro': 3}
          }));
      expect(find.textContaining('3 con 3 putts o más'), findsOneWidget);
      for (final n in ['Ana Robles', 'Beto Lara', 'Caro Díaz']) {
        final r = tester.getRect(find.text(n));
        expect(r.right, lessThanOrEqualTo(390.0), reason: '$n se sale');
      }
    });

    testWidgets('CLAVE: CRITERIO 4 — dice qué pasa si nadie contesta',
        (tester) async {
      // Es lo que sustituye a la opción que salió de la configuración. Se dice
      // en el momento de la pregunta, no se pacta antes.
      await _montar(
          tester,
          _ronda(putts: const {
            7: {'ana': 3, 'beto': 3}
          }));
      expect(find.textContaining('Si no lo dices'), findsOneWidget);
      expect(find.textContaining('cada uno paga completo'), findsOneWidget);
    });

    testWidgets('CLAVE: al contestar, lo dice — y se puede deshacer',
        (tester) async {
      final prov = await _montar(
          tester,
          _ronda(putts: const {
            7: {'ana': 3, 'beto': 3}
          }));
      await tester.tap(find.text('Beto Lara'));
      await tester.pump();
      expect(prov.round!.ultimoEnPasarElUmbral[7], 'beto');
      expect(find.textContaining('es de Beto Lara'), findsOneWidget);

      // Volver a tocarlo lo deselecciona: contestar mal y no poder deshacerlo
      // sería peor que la pregunta.
      await tester.tap(find.text('Beto Lara'));
      await tester.pump();
      expect(prov.round!.ultimoEnPasarElUmbral.containsKey(7), isFalse);
      expect(find.textContaining('Si no lo dices'), findsOneWidget);
    });

    testWidgets('CLAVE: y se puede contestar DESPUÉS — no es un modal',
        (tester) async {
      // En el campo la pregunta se queda sin responder. Volviendo al hoyo tiene
      // que seguir ahí: descubrirlo al cerrar sin poder arreglarlo sería peor
      // que no preguntar.
      final prov = await _montar(
          tester,
          _ronda(putts: const {
            7: {'ana': 3, 'beto': 3}
          }));
      // Se vuelve a montar la misma pantalla: la pregunta sigue.
      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider<RoundProvider>.value(value: prov)],
        child: MaterialApp(
          home: Scaffold(
              body: SnakeUltimoSection(hole: 7, t: GolfTheme.classic)),
        ),
      ));
      await tester.pump();
      expect(find.textContaining('¿Quién fue el último?'), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('3 · el motor: con el orden dicho, el empate desaparece', () {
    SnakeConfig cfg({SnakeEmpate empate = SnakeEmpate.ambosPagan}) =>
        SnakeConfig(value: 100, umbral: 3, empate: empate);

    test('CLAVE: sin respuesta, la serpiente es de los DOS', () {
      // Es el comportamiento del criterio 4, y el que ya existía: sin saber el
      // orden, el empate es real.
      final r = _ronda(putts: const {
        7: {'ana': 3, 'beto': 3}
      });
      final res = SnakeEngine.buscar(r, _cuatro, cfg());
      expect(res.hoyo, 7);
      expect(res.duenos, ['ana', 'beto']);
      expect(res.empatada, isTrue);
    });

    test('CLAVE: con respuesta, es de UNO — el que se dijo', () {
      final r = _ronda(
          putts: const {
            7: {'ana': 3, 'beto': 3}
          },
          ultimo: const {7: 'beto'});
      final res = SnakeEngine.buscar(r, _cuatro, cfg());
      expect(res.duenos, ['beto']);
      expect(res.empatada, isFalse, reason: 'ya no hay empate que resolver');
    });

    test('CLAVE: y paga uno solo, no los dos', () {
      // La consecuencia en dinero, que es lo que importa: con cuatro jugadores
      // y 100, un dueño paga 300 y dos pagan 600 entre los dos.
      final sinDecir = _ronda(putts: const {
        7: {'ana': 3, 'beto': 3}
      });
      final diciendo = _ronda(
          putts: const {
            7: {'ana': 3, 'beto': 3}
          },
          ultimo: const {7: 'beto'});

      // Se liquida con el MISMO método que la ronda de verdad: un cálculo
      // propio aquí probaría otra cosa.
      final mod = BetModuleInstance.defaultFor(
              BetModuleType.snake, _cuatro, id: 'sn')
          .copyWith(snakeConfig: cfg());
      double total(Round r) => SnakeEngine.liquidar(r, _cuatro, mod)
          .fold(0.0, (s, e) => s + e.amount);

      expect(total(diciendo), 300, reason: 'un dueño paga a los otros tres');
      expect(total(sinDecir), greaterThan(total(diciendo)),
          reason: 'dos dueños pagan más que uno');
    });

    test('CLAVE: una respuesta que ya no aplica se ignora', () {
      // Se contestó «beto» y luego se corrigió su score a dos putts. La
      // respuesta guardada no puede seguir mandando sobre un hoyo que ya no le
      // toca.
      final r = _ronda(
          putts: const {
            7: {'ana': 3, 'caro': 3}
          },
          ultimo: const {7: 'beto'});
      final res = SnakeEngine.buscar(r, _cuatro, cfg());
      expect(res.duenos, ['ana', 'caro']);
    });

    test('CONTRAPESO: con UNO solo, la respuesta no cambia nada', () {
      // La respuesta existe para deshacer empates. Con un solo culpable no hay
      // nada que deshacer, y una respuesta rara no puede robarle la serpiente.
      final r = _ronda(
          putts: const {
            7: {'ana': 3}
          },
          ultimo: const {7: 'beto'});
      expect(SnakeEngine.buscar(r, _cuatro, cfg()).duenos, ['ana']);
    });

    test('CLAVE: y la respuesta sobrevive al viaje por Firestore', () {
      // `saveRound` escribe con merge:false: sin serializar el mapa, la
      // respuesta se daría una vez y se perdería al anotar el hoyo siguiente.
      final r = _ronda(
          putts: const {
            7: {'ana': 3, 'beto': 3}
          },
          ultimo: const {7: 'beto'});
      final vuelta = roundFromJson(roundToJson(r));
      expect(vuelta.ultimoEnPasarElUmbral[7], 'beto');
      expect(SnakeEngine.buscar(vuelta, _cuatro, cfg()).duenos, ['beto']);
    });

    test('una ronda sin respuestas no gana la clave', () {
      final r = _ronda(putts: const {});
      expect(roundToJson(r).containsKey('ultimoEnPasarElUmbral'), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('4 · CRITERIO 3: la opción de empate ya no se configura', () {
    test('CLAVE: no está en los campos de configuración', () {
      // «Pactar de antemano algo que se te va a preguntar en el momento es
      // preguntar dos veces.»
      final codigo =
          File('lib/widgets/format_config_fields.dart').readAsStringSync();
      final vivas = codigo
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .where((l) => l.contains('SnakeEmpate'))
          .toList();
      expect(vivas, isEmpty, reason: 'ya no se pacta: se pregunta');
      // Y en su sitio se dice la regla.
      expect(codigo, contains('último en la secuencia del hoyo'));
    });

    test('CONTRAPESO: pero el enum SIGUE, y su default', () {
      // Es lo que pasa cuando nadie contesta, y lo que hace que las rondas
      // guardadas con la otra opción se sigan leyendo igual.
      expect(SnakeEmpate.values.length, 2);
      expect(const SnakeConfig(value: 100).empate, SnakeEmpate.ambosPagan);
      final leida = SnakeConfig.fromJson(
          const {'value': 100.0, 'umbral': 3, 'empate': 'dividen'});
      expect(leida.empate, SnakeEmpate.dividen);
    });
  });
}
