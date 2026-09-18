// ─────────────────────────────────────────────────────────────────────────────
// EL RECUADRO DE 18 EN UNA RONDA DE NUEVE
//
// La tarjeta del duelo CAM vs KAWA, ronda del 16 Sep:
//
//     NASSAU  USTEDES DOS       9/18 hoyos    Press ON
//       F9  +1 CAM  \$50    B9  —  0/9 · \$50    18  +1 CAM  9/18 · \$100
//
// Y el desglose:
//
//     Nassau 9H                   +\$50
//     Press H3–H9 (Nassau 9H)     −\$50
//
// El recuadro de 18 anuncia ganador e importe de una apuesta que nadie va a
// cobrar. Y no es que falte cerrar el 18: «Nassau 9H» es la rama de ronda de
// NUEVE, donde el Nassau es UNA apuesta. El motor ya lo sabía —
// `apuestasVivasDelNassau` devuelve un solo segmento— y la tarjeta pintaba tres
// recuadros escritos a mano.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/screens/scorecard/scorecard_screen.dart';
import 'package:provider/provider.dart';

final _curso = CourseInfo(name: 'P72', holes: [
  for (int i = 1; i <= 18; i++) CourseHole(hole: i, par: 4, strokeIndex: i),
]);

const _cfg = NassauConfig(
  frontValue: 50,
  backValue: 50,
  totalValue: 100,
  pressEnabled: true,
  autoPressTrigger: 2,
  frontPressValue: 50,
  backPressValue: 50,
);

/// La ronda del 16 Sep: nueve hoyos, KAWA gana 1 y 2, CAM gana 4, 5 y 6.
///
/// Con eso CAM queda +1 en el nueve y la presión del hoyo 3 la gana KAWA, que
/// es exactamente el desglose que Carlos vio: +\$50 y −\$50.
Round _ronda({required int totalHoles}) => Round(
      id: 'r',
      name: '16 Sep',
      course: _curso,
      isFinished: false,
      players: [Player(id: 'cam', name: 'CAM'), Player(id: 'kawa', name: 'KAWA')],
      roundPlayers: [
        RoundPlayer(playerId: 'cam', handicapEnRonda: 0),
        RoundPlayer(playerId: 'kawa', handicapEnRonda: 0),
      ],
      betGroups: [
        BetGroup(
            id: 'g',
            name: 'G',
            format: PartidaFormat.oneVsOne,
            playerIds: const ['cam', 'kawa'],
            modules: [
              BetModuleInstance(
                  id: 'n',
                  type: BetModuleType.nassau,
                  name: 'Nassau',
                  participantIds: const ['cam', 'kawa'],
                  nassauConfig: _cfg),
            ])
      ],
      scores: {
        for (final p in ['cam', 'kawa'])
          p: {
            for (int h = 1; h <= 9; h++)
              h: HoleScore(
                  playerId: p,
                  hole: h,
                  grossScore: (const [1, 2].contains(h) && p == 'cam') ||
                          (const [4, 5, 6].contains(h) && p == 'kawa')
                      ? 5
                      : 4,
                  putts: 2)
          }
      },
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2026, 9, 16),
      totalHoles: totalHoles,
    );

BetModuleInstance _mod(Round r) => r.betGroups.first.modules.first;

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  group('1 · el motor ya lo sabía', () {
    test('CLAVE: en una ronda de nueve el Nassau es UNA apuesta', () {
      final r = _ronda(totalHoles: 9);
      final segs = BetEngine.apuestasVivasDelNassau(r, 'cam', 'kawa', _mod(r))
          .where((a) => a.clase == ClaseDeApuesta.segmento)
          .toList();
      expect(segs.map((s) => s.etiqueta), ['9H']);
      expect(segs.single.deCuantos, 9);
    });

    test('CLAVE: y el ledger paga eso y nada más', () {
      LedgerEngine.invalidateCache();
      final motivos = LedgerEngine.entriesOf(_ronda(totalHoles: 9))
          .map((e) => e.reason)
          .toList();
      expect(motivos, ['Nassau 9H', 'Press H3–H9 (Nassau 9H)']);
      expect(motivos.any((m) => m.contains('Total')), isFalse,
          reason: 'el recuadro de 18 prometía \$100 que nadie cobra');
    });

    test('CONTRAPESO: en una de dieciocho siguen siendo tres', () {
      final r = _ronda(totalHoles: 18);
      final segs = BetEngine.apuestasVivasDelNassau(r, 'cam', 'kawa', _mod(r))
          .where((a) => a.clase == ClaseDeApuesta.segmento)
          .toList();
      expect(segs.map((s) => s.etiqueta), ['F9', 'B9', '18']);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('2 · y ahora la tarjeta también', () {
    Future<String> montar(WidgetTester tester, Round r) async {
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final prov = RoundProvider()..startRound(r);
      await tester.pumpWidget(ChangeNotifierProvider<RoundProvider>.value(
        value: prov,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: NassauLivePanel(
                  round: r,
                  p1: r.players[0],
                  p2: r.players[1],
                  mod: _mod(r),
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

    testWidgets('CLAVE (criterio 3): un recuadro por apuesta que se paga',
        (tester) async {
      final texto = await montar(tester, _ronda(totalHoles: 9));
      expect(texto, contains('9H'));
      // Los dos que no existen, y que anunciaban ganador e importe.
      expect(texto, isNot(contains('B9')));
      expect(texto, isNot(contains(r'$100')));
      // Y la cuenta de hoyos deja de prometer media ronda pendiente.
      expect(texto, isNot(contains('9/18 hoyos')));
      expect(texto, contains('9/9 hoyos'));
    });

    testWidgets('CONTRAPESO: la de dieciocho sigue enseñando los tres',
        (tester) async {
      final texto = await montar(tester, _ronda(totalHoles: 18));
      expect(texto, contains('F9'));
      expect(texto, contains('B9'));
      expect(texto, contains(r'$100'));
    });
  });
}
