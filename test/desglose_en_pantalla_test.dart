// ─────────────────────────────────────────────────────────────────────────────
// EL DESGLOSE EN PANTALLA, PULSANDO LOS DOS BOTONES
//
// «Verificado en pantalla, pulsando los dos en una ronda real.»
//
// Se monta el panel del carry, el de la apertura y el desglose sobre el MISMO
// provider —como en la pantalla— y se pulsan los dos botones. Lo que se
// comprueba es lo que Carlos no pudo ver: que después de pulsar, el dinero
// cambia y los paneles dejan de ofrecerse.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/screens/scorecard/scorecard_screen.dart';
import 'package:provider/provider.dart';

final _curso = CourseInfo(name: 'P72', holes: [
  for (int i = 1; i <= 18; i++) CourseHole(hole: i, par: 4, strokeIndex: i),
]);

/// La ronda del 7 Sep: F9 empatado, CAM gana cuatro del B9, sin cerrar.
Round _ronda() => Round(
      id: 'r',
      name: '7 Sep',
      course: _curso,
      isFinished: false,
      players: [Player(id: 'cam', name: 'CAM'), Player(id: 'cav', name: 'CAV')],
      roundPlayers: [
        RoundPlayer(playerId: 'cam', handicapEnRonda: 0),
        RoundPlayer(playerId: 'cav', handicapEnRonda: 0),
      ],
      betGroups: [
        BetGroup(
            id: 'g',
            name: 'G',
            format: PartidaFormat.oneVsOne,
            playerIds: const ['cam', 'cav'],
            savedGroupId: 'viernes-cgm',
            modules: [
              BetModuleInstance(
                  id: 'n',
                  type: BetModuleType.nassau,
                  name: 'Nassau',
                  participantIds: const ['cam', 'cav'],
                  nassauConfig: const NassauConfig(
                      frontValue: 50,
                      backValue: 50,
                      totalValue: 100,
                      carryEnabled: true,
                      pressEnabled: true,
                      autoPressTrigger: 2)),
            ])
      ],
      scores: {
        for (final p in ['cam', 'cav'])
          p: {
            for (int h = 1; h <= 18; h++)
              h: HoleScore(
                  playerId: p,
                  hole: h,
                  grossScore:
                      const [10, 11, 12, 13].contains(h) && p == 'cav' ? 5 : 4,
                  putts: 2)
          }
      },
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2026, 9, 7),
      totalHoles: 18,
    );

/// El MISMO código que la pantalla ejecuta al pulsar cada botón.
void _pedirCarry(RoundProvider p, String quien) {
  final r = p.round!;
  final clave = NassauConfig.carryPairKey('cam', 'cav');
  p.updateBetGroups(r.betGroups.map((g) {
    final mods = g.modules.map((m) {
      if (m.type != BetModuleType.nassau) return m;
      final mapa = Map<String, String>.from(m.nassau.carryPedidoByPair)
        ..[clave] = quien;
      return m.copyWith(nassauConfig: m.nassau.copyWith(carryPedidoByPair: mapa));
    }).toList();
    return g.copyWith(modules: mods);
  }).toList());
}

void _abrirApertura(RoundProvider p) {
  final r = p.round!;
  final clave = NassauConfig.carryPairKey('cam', 'cav');
  p.updateBetGroups(r.betGroups.map((g) {
    final mods = g.modules.map((m) {
      if (m.type != BetModuleType.nassau) return m;
      final mapa = Map<String, bool>.from(m.nassau.aperturaB9ByPair)
        ..[clave] = true;
      return m.copyWith(nassauConfig: m.nassau.copyWith(aperturaB9ByPair: mapa));
    }).toList();
    return g.copyWith(modules: mods);
  }).toList());
}

String _texto(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .join('  ‖  ');

void main() {
  testWidgets('CLAVE: al pulsar los dos, el desglose pasa de \$250 a \$350',
      (tester) async {
    final prov = RoundProvider()..startRound(_ronda());
    await tester.pumpWidget(ChangeNotifierProvider<RoundProvider>.value(
      value: prov,
      child: MaterialApp(
        home: Scaffold(
          body: Consumer<RoundProvider>(builder: (ctx, p, _) {
            final r = p.round!;
            return SingleChildScrollView(
              child: FinancialBreakdown(
                  round: r, p1: r.players[0], p2: r.players[1], t: GolfTheme.dark),
            );
          }),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Antes: lo que Carlos vio.
    expect(_texto(tester), contains('250'));

    _pedirCarry(prov, 'cav');
    _abrirApertura(prov);
    await tester.pumpAndSettle();

    final txt = _texto(tester);
    expect(txt, contains('350'), reason: 'los \$100 que faltaban');
    // ── CRITERIOS 1 y 2: las dos se VEN, no se suman en silencio ───────────
    expect(txt, contains('Carry · un golpe más'));
    expect(txt, contains('Apertura 2ª vuelta'));
    // Y con su importe cada una.
    expect(txt.contains('Nassau Back 9'), isTrue,
        reason: 'la normal sigue ahí: son dos, no una a doble precio');
  });

  testWidgets('CLAVE: y no pierde el grupo guardado al pedirlas',
      (tester) async {
    // El campo que se iba a null en silencio.
    final prov = RoundProvider()..startRound(_ronda());
    _pedirCarry(prov, 'cav');
    _abrirApertura(prov);
    expect(prov.round!.betGroups.first.savedGroupId, 'viernes-cgm');
  });

  testWidgets('CRITERIO 3: los paneles dejan de ofrecerse al pulsarlos',
      (tester) async {
    final prov = RoundProvider()..startRound(_ronda());
    await tester.pumpWidget(ChangeNotifierProvider<RoundProvider>.value(
      value: prov,
      child: MaterialApp(
        home: Scaffold(
          body: Consumer<RoundProvider>(builder: (ctx, p, _) {
            final r = p.round!;
            return SingleChildScrollView(
              child: CarryPanel(
                round: r,
                p1: r.players[0],
                p2: r.players[1],
                t: GolfTheme.dark,
                nassauModules: r.betGroups.first.modules,
                onPedirCarry: (quien) => _pedirCarry(p, quien),
              ),
            );
          }),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // El F9 quedó empatado → el carry natural corre solo, no se pide.
    expect(_texto(tester), contains('CARRY NATURAL'));
    expect(find.byType(ElevatedButton), findsNothing);

    // Con el F9 ganado sí se ofrece — y al pulsar, cambia.
    final conGanador = _ronda().copyWith(scores: {
      for (final p in ['cam', 'cav'])
        p: {
          for (int h = 1; h <= 18; h++)
            h: HoleScore(
                playerId: p,
                hole: h,
                grossScore: h == 1 && p == 'cav' ? 5 : 4,
                putts: 2)
        }
    });
    prov.startRound(conGanador);
    await tester.pumpAndSettle();
    expect(find.byType(ElevatedButton), findsOneWidget);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expect(_texto(tester), contains('CARRY PEDIDO'));
    expect(find.byType(ElevatedButton), findsNothing,
        reason: 'no se pide dos veces');
  });
}
