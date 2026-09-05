// ─────────────────────────────────────────────────────────────────────────────
// EL CARRY EN PANTALLA — la ronda de cinco
//
// «Verificado en pantalla, con una ronda de 5 jugadores.»
//
// Los cinco son los de la ronda real que Carlos revisó: CAM, RICH, KAWA, AAM y
// Dylan. Lo que se comprueba aquí no es la cuenta —eso lo fija
// carry_pedido_test— sino que la PANTALLA enseñe la regla que toca:
//
//   · F9 empatado  → se cuenta el carry natural, y NO hay botón que pulsar.
//   · F9 con dueño → el botón sale, con el nombre del que va perdiendo.
//   · Ya pedido    → dice que son DOS apuestas, no una a doble precio.
//
// El panel ofrecía justo lo contrario: un botón «Activar Carry ×2» cuando el F9
// empataba, y un aviso atenuado cuando lo ganaba alguien.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/screens/scorecard/scorecard_screen.dart';

const _cinco = {
  'cam': 'CAM',
  'rich': 'RICH',
  'kawa': 'KAWA',
  'aam': 'AAM',
  'dylan': 'Dylan',
};

CourseInfo _campo() => CourseInfo(
      name: 'Los Encinos',
      holes: List.generate(18,
          (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)),
    );

/// La ronda de los cinco. [pierdeCam] son los hoyos que CAM pierde contra
/// Dylan; el resto se empatan.
Round _ronda({
  List<int> pierdeCam = const [],
  List<int> pierdeDylan = const [],
  Map<String, String> carryPedido = const {},
}) {
  final cfg = NassauConfig(
    frontValue: 50,
    backValue: 50,
    totalValue: 100,
    carryEnabled: true,
    carryPedidoByPair: carryPedido,
  );
  int golpe(String p, int h) {
    if (p == 'cam' && pierdeCam.contains(h)) return 5;
    if (p == 'dylan' && pierdeDylan.contains(h)) return 5;
    return 4;
  }

  return Round(
    id: 'r',
    name: 'Ronda de cinco',
    course: _campo(),
    isFinished: false,
    players: [
      for (final e in _cinco.entries) Player(id: e.key, name: e.value)
    ],
    roundPlayers: [
      for (final id in _cinco.keys) RoundPlayer(playerId: id, handicapEnRonda: 0)
    ],
    betGroups: [
      BetGroup(
          id: 'g',
          name: 'G',
          format: PartidaFormat.oneVsOne,
          playerIds: _cinco.keys.toList(),
          modules: [
            BetModuleInstance(
                id: 'n',
                type: BetModuleType.nassau,
                name: 'Nassau',
                participantIds: _cinco.keys.toList(),
                nassauConfig: cfg),
          ])
    ],
    scores: {
      for (final id in _cinco.keys)
        id: {
          for (int h = 1; h <= 18; h++)
            h: HoleScore(playerId: id, hole: h, grossScore: golpe(id, h), putts: 2)
        }
    },
    events: const {},
    oyeseRankings: const {},
    sliding: const [],
    createdAt: DateTime(2026, 9, 2),
    totalHoles: 18,
    startingNine: StartingNine.front,
  );
}

Future<List<String>> _montar(WidgetTester tester, Round r,
    {void Function(String)? alPedir}) async {
  final mod = r.betGroups.first.modules.first;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: CarryPanel(
          round: r,
          p1: r.players.firstWhere((p) => p.id == 'cam'),
          p2: r.players.firstWhere((p) => p.id == 'dylan'),
          t: GolfTheme.dark,
          nassauModules: [mod],
          matchPressModules: const [],
          onPedirCarry: alPedir ?? (_) {},
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data ?? '')
      .toList();
}

void main() {
  testWidgets('CLAVE: F9 EMPATADO → se cuenta el carry natural, sin botón',
      (tester) async {
    // Los nueve primeros en tablas; CAM pierde tres del B9.
    final textos = await _montar(
        tester, _ronda(pierdeCam: const [10, 11, 12]));

    expect(textos.any((x) => x.contains('CARRY NATURAL')), isTrue);
    // Los dos números que Carlos corrigió, en pantalla.
    expect(textos.any((x) => x.contains('el B9 vale \$100')), isTrue,
        reason: '50 propios + 50 del F9');
    expect(textos.any((x) => x.contains('Total 18 sigue en \$100')), isTrue,
        reason: 'la apuesta aparte que no se toca');
    // Y NO hay nada que pedir.
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets('CLAVE: F9 CON DUEÑO → el botón sale, y con el nombre del que pierde',
      (tester) async {
    // CAM gana el hoyo 1 → Dylan perdió la primera vuelta.
    final textos = await _montar(tester, _ronda(pierdeDylan: const [1]));

    expect(find.byType(ElevatedButton), findsOneWidget);
    expect(textos.any((x) => x.contains('Dylan pide carry')), isTrue);
    expect(textos.any((x) => x.contains('CAM pide carry')), isFalse,
        reason: 'CAM ganó el F9: no lo puede pedir');
    expect(textos.any((x) => x.contains('Solo el que va perdiendo')), isTrue);
  });

  testWidgets('CLAVE: y dice cuántos golpes, no solo que hay carry',
      (tester) async {
    // Parejos: Dylan recibe 0 en el B9, y con el carry recibiría 1.
    final textos = await _montar(tester, _ronda(pierdeDylan: const [1]));
    final t = textos.join(' · ');
    expect(t, contains('1 golpe de ventaja en vez de 0'));
    // Y que son DOS apuestas, no una a doble precio: es la confusión que la
    // regla vieja creaba.
    expect(t, contains('SEGUNDA apuesta'));
    expect(t, contains('Son dos, no una a doble precio'));
  });

  testWidgets('CLAVE: pulsarlo pide el carry PARA EL QUE PIERDE',
      (tester) async {
    String? pedido;
    await _montar(tester, _ronda(pierdeDylan: const [1]),
        alPedir: (q) => pedido = q);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expect(pedido, 'dylan');
  });

  testWidgets('CLAVE: ya pedido → cuenta que se juegan DOS apuestas',
      (tester) async {
    final textos = await _montar(
        tester,
        _ronda(
            pierdeDylan: const [1],
            carryPedido: const {'cam|dylan': 'dylan'}));
    final t = textos.join(' · ');
    expect(t, contains('CARRY PEDIDO'));
    expect(t, contains('DOS apuestas'));
    expect(t, contains('\$50 cada una'), reason: 'la del carry vale lo mismo');
    expect(t, contains('Dylan'), reason: 'de quién es el golpe extra');
    expect(find.byType(ElevatedButton), findsNothing,
        reason: 'no se pide dos veces');
  });

  testWidgets('CONTRAPESO: con el primer nueve a medias no se ofrece nada',
      (tester) async {
    // Un F9 sin terminar va 0-0 casi siempre: sin esta guarda la pantalla
    // anunciaría un carry en el hoyo 2.
    final r = _ronda();
    final aMedias = r.copyWith(scores: {
      for (final id in _cinco.keys)
        id: {
          for (int h = 1; h <= 5; h++)
            h: HoleScore(playerId: id, hole: h, grossScore: 4, putts: 2)
        }
    });
    final textos = await _montar(tester, aMedias);
    expect(textos.where((x) => x.trim().isNotEmpty), isEmpty);
  });
}
