// ─────────────────────────────────────────────────────────────────────────────
// LA PAREJA BASE EN CAPTURA — quién juega contra quién, sin deducirlo
//
// Con tres enfrentamientos a la vez, mirar la lista de apuestas y reconstruir
// mentalmente quién está contra quién es trabajo. Aquí la pareja base va
// destacada —es la constante de la ronda— y los tres rivales como chips.
//
// Y se DERIVA de los módulos, no de un campo nuevo. Eso vale doble: hay un test
// que lo comprueba con las tres apuestas montadas A MANO, que es como este
// formato ya se podía jugar antes de que el atajo existiera.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/providers/auth_provider.dart';
import 'package:golf_bet_master/providers/player_provider.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/screens/capture/capture_screen.dart';

const pa = 'a', pb = 'b', pc = 'c', pd = 'd', pe = 'e';
const cinco = [pa, pb, pc, pd, pe];
const nombres = {
  pa: 'Rafael',
  pb: 'Alan',
  pc: 'Guillermo',
  pd: 'Alejandro',
  pe: 'Bernardo',
};

BetModuleInstance _mod(String id, List<String> a, List<String> b) =>
    BetModuleInstance(
      id: id,
      type: BetModuleType.nassau,
      name: 'Nassau $id',
      participantIds: [...a, ...b],
      nassauConfig: const NassauConfig(
          frontValue: 100, backValue: 0, totalValue: 0, mode: GrossNetMode.gross),
      sides: [
        BetSide(id: '${id}_a', name: 'A', playerIds: a),
        BetSide(id: '${id}_b', name: 'B', playerIds: b),
      ],
    );

/// Los tres enfrentamientos, o lo que se le pase.
Round _round({List<BetModuleInstance>? mods, List<String> pids = cinco}) {
  final course = CourseInfo(
      name: 'T',
      holes: List.generate(
          18, (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)));
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
          modules: mods ??
              [
                _mod('1', const [pa, pb], const [pc, pd]),
                _mod('2', const [pa, pb], const [pc, pe]),
                _mod('3', const [pa, pb], const [pd, pe]),
              ]),
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
    totalHoles: 18,
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

String _texto(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(
        of: find.byKey(const Key('parejaBaseSection')),
        matching: find.byType(Text)))
    .map((w) => w.data ?? '')
    .join(' · ');

void main() {
  group('1 · la pareja base y sus tres rivales se ven', () {
    testWidgets('con los tres enfrentamientos montados', (tester) async {
      final errores = await _montar(tester, _round(), const Size(390, 1000));
      expect(errores, isEmpty);
      final txt = _texto(tester);
      expect(txt, contains('PAREJA BASE: RAFAEL + ALAN'));
      expect(txt, contains('vs GUILLERMO + ALEJANDRO'));
      expect(txt, contains('vs GUILLERMO + BERNARDO'));
      expect(txt, contains('vs ALEJANDRO + BERNARDO'));
    });

    testWidgets('y dice que la base juega los tres', (tester) async {
      await _montar(tester, _round(), const Size(390, 1000));
      expect(_texto(tester), contains('gana más y pierde más'));
      expect(_texto(tester), contains('Juegan los 3 a la vez'));
    });

    testWidgets('cabe a 320 px con nombres largos', (tester) async {
      // Tres parejas de nombres en una fila es la forma que ya desbordó cinco
      // veces en esta app. Se mide ESTE bloque: la fila de la tabla de captura
      // sigue sin caber a 320 y es deuda anterior.
      await _montar(tester, _round(), const Size(320, 1200));
      final f = find.byKey(const Key('parejaBaseSection'));
      expect(f, findsOneWidget);
      expect(tester.getSize(f).width, lessThanOrEqualTo(320.0));
      expect(_texto(tester), contains('vs ALEJANDRO + BERNARDO'));
    });
  });

  group('2 · se deriva, así que sirve a quien lo montó a mano', () {
    testWidgets('con los lados escritos al revés lo reconoce igual',
        (tester) async {
      final errores = await _montar(
          tester,
          _round(mods: [
            _mod('1', const [pa, pb], const [pc, pd]),
            _mod('2', const [pc, pe], const [pa, pb]), // al revés
            _mod('3', const [pd, pe], const [pb, pa]), // al revés y desordenado
          ]),
          const Size(390, 1000));
      expect(errores, isEmpty);
      expect(_texto(tester), contains('PAREJA BASE: RAFAEL + ALAN'));
    });

    testWidgets('con dos enfrentamientos también, no hacen falta tres',
        (tester) async {
      // El patrón es "un lado que se repite", no "exactamente tres apuestas".
      await _montar(
          tester,
          _round(mods: [
            _mod('1', const [pa, pb], const [pc, pd]),
            _mod('2', const [pa, pb], const [pc, pe]),
          ]),
          const Size(390, 1000));
      expect(_texto(tester), contains('PAREJA BASE: RAFAEL + ALAN'));
      expect(_texto(tester), contains('Juegan los 2 a la vez'));
    });
  });

  group('3 · sin ese patrón no se enseña nada', () {
    testWidgets('una ronda por equipos normal no lo dispara', (tester) async {
      // Un solo módulo con dos lados no tiene pareja base que enseñar. Decir
      // algo aquí sería inventarlo.
      final errores = await _montar(
          tester,
          _round(mods: [_mod('1', const [pa, pb], const [pc, pd])]),
          const Size(390, 1000));
      expect(errores, isEmpty);
      expect(find.byKey(const Key('parejaBaseSection')), findsNothing);
    });

    testWidgets('una ronda individual tampoco', (tester) async {
      await _montar(
          tester,
          _round(mods: [
            BetModuleInstance.defaultFor(BetModuleType.skins, cinco, id: 'm')
          ]),
          const Size(390, 1000));
      expect(find.byKey(const Key('parejaBaseSection')), findsNothing);
    });
  });
}
