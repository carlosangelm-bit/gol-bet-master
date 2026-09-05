// ─────────────────────────────────────────────────────────────────────────────
// «SOLO EL MATCH» EN PANTALLA
//
// Un Nassau con los dos nueves a cero es lo que era Match + Press. Lo que se
// comprueba aquí es el criterio 3: que lo que NO aplica se diga, en vez de
// desaparecer.
//
//   · el carry natural no existe — no hay F9 del que trasladar
//   · el carry pedido tampoco — no hay segundo nueve sobre el que pedirlo
//   · la presión de la 2ª vuelta valdría cero
//   · las presiones automáticas SÍ se juegan, y hay que decirlo también
//
// Un bloque que desaparece sin motivo se lee como un fallo.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/screens/scorecard/scorecard_screen.dart';
import 'package:provider/provider.dart';

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

/// La ronda de los cinco, con el primer nueve terminado.
Round _ronda(NassauConfig cfg, {List<int> ganaCam = const []}) => Round(
      id: 'r',
      name: 'Ronda de cinco',
      course: _campo(),
      isFinished: false,
      players: [for (final e in _cinco.entries) Player(id: e.key, name: e.value)],
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
            for (int h = 1; h <= 10; h++)
              h: HoleScore(
                  playerId: id,
                  hole: h,
                  grossScore:
                      id == 'dylan' && ganaCam.contains(h) ? 5 : 4,
                  putts: 2)
          }
      },
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2026, 9, 2),
      totalHoles: 18,
      startingNine: StartingNine.front,
    );

/// El match sobre los 18: los dos nueves a cero.
const _soloMatch = NassauConfig(
  frontValue: 0,
  backValue: 0,
  totalValue: 100,
  carryEnabled: true,
  pressEnabled: true,
  autoPressTrigger: 2,
  frontPressValue: 50,
  backPressValue: 50,
  aperturaB9ByPair: {'cam|dylan': true},
);

Future<String> _pinta(WidgetTester tester, Widget w, Round r) async {
  await tester.pumpWidget(ChangeNotifierProvider<RoundProvider>.value(
    value: RoundProvider()..startRound(r),
    child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w))),
  ));
  await tester.pumpAndSettle();
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data ?? '')
      .join('  ‖  ');
}

CarryPanel _carry(Round r) => CarryPanel(
      round: r,
      p1: r.players.firstWhere((p) => p.id == 'cam'),
      p2: r.players.firstWhere((p) => p.id == 'dylan'),
      t: GolfTheme.dark,
      nassauModules: r.betGroups.first.modules,
      onPedirCarry: (_) {},
    );

void main() {
  testWidgets('CLAVE: el carry DICE por qué no aplica, no desaparece',
      (tester) async {
    // El F9 quedó empatado, que es justo cuando el carry natural correría.
    final r = _ronda(_soloMatch);
    final txt = await _pinta(tester, _carry(r), r);
    expect(txt, contains('CARRY'));
    expect(txt, contains('match sobre los 18 hoyos'));
    expect(txt, contains('sin '));
    // Y no ofrece nada que pulsar.
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets('CONTRAPESO: con los nueves EN VALOR, el carry sí corre',
      (tester) async {
    // Si no, el test de arriba no probaría que lo apagan los ceros.
    final r = _ronda(_soloMatch.copyWith(frontValue: 50, backValue: 50));
    final txt = await _pinta(tester, _carry(r), r);
    expect(txt, contains('CARRY NATURAL'));
    expect(txt, contains('el B9 vale \$100'));
  });

  testWidgets('CLAVE: y tampoco se puede PEDIR con el F9 ganado',
      (tester) async {
    // CAM gana el hoyo 1: hay un perdedor, pero no hay segundo nueve sobre el
    // que jugar la apuesta paralela.
    final r = _ronda(_soloMatch, ganaCam: const [1]);
    final txt = await _pinta(tester, _carry(r), r);
    expect(txt, contains('match sobre los 18 hoyos'));
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets('CLAVE: la cabecera sigue cantando la línea, y solo del match',
      (tester) async {
    // Las presiones se juegan: eso es lo que hace que siga siendo Match+Press.
    final r = _ronda(_soloMatch, ganaCam: const [1, 2, 3, 4, 5]);
    final txt = await _pinta(
        tester,
        MatchStatusCard(
          round: r,
          p1: r.players.firstWhere((p) => p.id == 'cam'),
          p2: r.players.firstWhere((p) => p.id == 'dylan'),
          t: GolfTheme.dark,
          skinsModules: const [],
          nassauModules: r.betGroups.first.modules,
          oyesModules: const [],
        ),
        r);
    // DOS números y no tres: el default del grupo es UNA presión por nueve
    // —`allowMultiplePresses` en false—, así que la cadena no se encadena.
    expect(txt, contains('F9 +5 +3'),
        reason: 'la línea se hereda: no hubo que escribirla dos veces');
    expect(txt, contains('B9 0'), reason: 'el segundo nueve, recién empezado');
    expect(txt, contains('Presiones desde H3'));
  });
}
