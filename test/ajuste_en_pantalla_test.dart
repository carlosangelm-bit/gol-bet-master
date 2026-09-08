// ─────────────────────────────────────────────────────────────────────────────
// EL AJUSTE AL B9 EN PANTALLA, CON DIFERENCIA IMPAR
//
// «El criterio 5 pide diferencia impar a propósito — es el único caso donde el
//  medio golpe existe, y es el que nadie prueba.»
//
// F9 ganado por 5 → el otro recibe 2.5 en el B9: dos enteros en los hoyos 10 y
// 11 —los más difíciles de esa vuelta— y el medio en el 12.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/screens/scorecard/scorecard_screen.dart';
import 'package:provider/provider.dart';

final _curso = CourseInfo(name: 'P72', holes: [
  for (int i = 1; i <= 18; i++) CourseHole(hole: i, par: 4, strokeIndex: i),
]);

Round _r({
  required List<int> ganaCam,
  List<int> ganaCav = const [],
  bool ajuste = true,
  Map<String, Map<String, List<int>>> presiones = const {},
}) =>
    Round(
      id: 'r',
      name: 'Primera vez',
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
            modules: [
              BetModuleInstance(
                  id: 'n',
                  type: BetModuleType.nassau,
                  name: 'Nassau',
                  participantIds: const ['cam', 'cav'],
                  nassauConfig: NassauConfig(
                      frontValue: 50,
                      backValue: 50,
                      totalValue: 100,
                      ajusteEnB9: ajuste,
                      carryEnabled: true,
                      aperturaB9ByPair: const {'cam|cav': true},
                      presionesPedidasByPair: presiones)),
            ])
      ],
      scores: {
        for (final p in ['cam', 'cav'])
          p: {
            for (int h = 1; h <= 18; h++)
              h: HoleScore(
                  playerId: p,
                  hole: h,
                  grossScore: (ganaCam.contains(h) && p == 'cav') ||
                          (ganaCav.contains(h) && p == 'cam')
                      ? 5
                      : 4,
                  putts: 2)
          }
      },
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2026, 9, 7),
      totalHoles: 18,
    );

Future<String> _pinta(WidgetTester tester, Round r) async {
  await tester.pumpWidget(ChangeNotifierProvider<RoundProvider>.value(
    value: RoundProvider()..startRound(r),
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: NassauLivePanel(
              round: r,
              p1: r.players[0],
              p2: r.players[1],
              mod: r.betGroups.first.modules.first,
              t: GolfTheme.dark),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data ?? '')
      .join('  ‖  ');
}

/// El MISMO código que la pantalla ejecuta al pulsar «pedir presión».
void _pedirPresion(RoundProvider p, String apuesta) {
  final r = p.round!;
  final seg = BetEngine.segmentsOf(r);
  final desde = seg.secondNine.firstWhere(
      (h) =>
          !r.getScore('cam', h).hasScore || !r.getScore('cav', h).hasScore,
      orElse: () => -1);
  if (desde < 0) return;
  final clave = NassauConfig.carryPairKey('cam', 'cav');
  p.updateBetGroups(r.betGroups.map((g) {
    final mods = g.modules.map((m) {
      if (m.type != BetModuleType.nassau) return m;
      final porPareja = {
        for (final e in m.nassau.presionesPedidasByPair.entries)
          e.key: {for (final x in e.value.entries) x.key: [...x.value]}
      };
      final delPar = porPareja.putIfAbsent(clave, () => {});
      final hoyos = delPar.putIfAbsent(apuesta, () => []);
      if (!hoyos.contains(desde)) hoyos.add(desde);
      return m.copyWith(
          nassauConfig: m.nassau.copyWith(presionesPedidasByPair: porPareja));
    }).toList();
    return g.copyWith(modules: mods);
  }).toList());
}

void main() {
  testWidgets('CLAVE: con F9 por 5, la tarjeta dice los 2.5 y el medio golpe',
      (tester) async {
    final txt = await _pinta(tester, _r(ganaCam: const [1, 2, 3, 4, 5]));

    expect(txt, contains('VENTAJA AJUSTADA EN EL B9'));
    expect(txt, contains('El F9 se decidió por 5 hoyos'));
    expect(txt, contains('CAV recibe 2.5 golpes'));
    // ── Lo que nadie sabe explicar en el tee ─────────────────────────────
    expect(txt, contains('MEDIO GOLPE en el H12'));
    expect(txt, contains('rompe el empate'));
    expect(txt, contains('Si el H12 queda igualado, lo gana CAV'));
    // Y qué NO se toca.
    expect(txt, contains('El F9 y el Total 18 se pagan con la ventaja original'));
  });

  testWidgets('CLAVE: con diferencia PAR no promete un medio golpe que no hay',
      (tester) async {
    final txt = await _pinta(tester, _r(ganaCam: const [1, 2, 3, 4]));
    expect(txt, contains('CAV recibe 2.0 golpes'));
    expect(txt.contains('MEDIO GOLPE'), isFalse);
  });

  testWidgets('CONTRAPESO: apagado, el bloque no aparece', (tester) async {
    final txt =
        await _pinta(tester, _r(ganaCam: const [1, 2, 3, 4, 5], ajuste: false));
    expect(txt.contains('VENTAJA AJUSTADA'), isFalse);
  });

  testWidgets('CLAVE: y una presión PEDIDA sale con su recuadro y su nota',
      (tester) async {
    // Sobre la apertura, desde el hoyo 10, con CAM ganando el 13 para que
    // tenga dueño.
    final txt = await _pinta(
        tester,
        _r(
            ganaCam: const [1, 2, 3, 4, 5, 13],
            presiones: const {
              'cam|cav': {'apertura': [10]}
            }));
    expect(txt, contains('PEDIDAS'));
    expect(txt, contains('presión pedida sobre Apertura, desde el hoyo 10'));
  });

  testWidgets('CRITERIO 1 · pulsar «pedir presión» la crea desde el hoyo en curso',
      (tester) async {
    // Once hoyos capturados: el siguiente sin las dos tarjetas es el 12.
    final r = _r(ganaCam: const [1, 2, 3, 4, 5]).copyWith(scores: {
      for (final p in ['cam', 'cav'])
        p: {
          for (int h = 1; h <= 11; h++)
            h: HoleScore(
                playerId: p,
                hole: h,
                grossScore:
                    const [1, 2, 3, 4, 5].contains(h) && p == 'cav' ? 5 : 4,
                putts: 2)
        }
    });
    final prov = RoundProvider()..startRound(r);
    _pedirPresion(prov, NassauConfig.claveApertura);
    expect(
        prov.round!.betGroups.first.modules.first.nassau
            .presionesPedidasDe('cam', 'cav', 'apertura'),
        [12],
        reason: 'arranca en el hoyo en curso, como una automática');
  });

  testWidgets('CONTRAPESO: con el nueve terminado no se crea ninguna',
      (tester) async {
    // No hay tramo que cubrir, así que pedirla no haría nada — y no debe
    // guardar un hoyo inventado.
    final prov = RoundProvider()..startRound(_r(ganaCam: const [1, 2, 3, 4, 5]));
    _pedirPresion(prov, NassauConfig.claveApertura);
    expect(
        prov.round!.betGroups.first.modules.first.nassau
            .presionesPedidasDe('cam', 'cav', 'apertura'),
        isEmpty);
  });

  testWidgets('CLAVE: el F9 sigue enseñando su marcador original',
      (tester) async {
    // «La primera vuelta ya quedó como quedó»: su recuadro no se recalcula.
    final txt = await _pinta(tester, _r(ganaCam: const [1, 2, 3, 4, 5]));
    expect(txt, contains('F9'));
    expect(txt, contains('CAM'));
  });
}
