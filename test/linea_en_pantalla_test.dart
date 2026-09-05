// ─────────────────────────────────────────────────────────────────────────────
// LA LÍNEA «5 3 1» EN PANTALLA
//
// «Verificado en pantalla, con la ronda de cinco que tiene presiones en las dos
//  vueltas.»
//
// Los cinco son los de la ronda real: CAM, RICH, KAWA, AAM y Dylan. La cabecera
// decía «CAM +2 · F9: AS · B9: CAM 2UP · 3 presiones activas» — los mismos datos
// con otro vocabulario, y sin decir por cuánto va cada presión: para eso había
// que bajar al bloque.
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

/// La ronda de los cinco. CAM le gana a Dylan los hoyos [ganaCam]; el resto se
/// empatan. [hasta] son los hoyos capturados.
Round _ronda({required List<int> ganaCam, int hasta = 18}) {
  int golpe(String p, int h) {
    if (!ganaCam.contains(h)) return 4;
    return p == 'dylan' ? 5 : 4;
  }

  return Round(
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
                nassauConfig: const NassauConfig(
                  frontValue: 50,
                  backValue: 50,
                  totalValue: 100,
                  pressEnabled: true,
                  autoPressTrigger: 2,
                  frontPressValue: 50,
                  backPressValue: 50,
                  allowMultiplePresses: true,
                )),
          ])
    ],
    scores: {
      for (final id in _cinco.keys)
        id: {
          for (int h = 1; h <= hasta; h++)
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

Future<String> _cabecera(WidgetTester tester, Round r,
    {String miro = 'cam'}) async {
  final otro = miro == 'cam' ? 'dylan' : 'cam';
  // La cabecera lleva dentro el chip de balance, que lee la ronda del provider.
  await tester.pumpWidget(ChangeNotifierProvider<RoundProvider>.value(
    value: RoundProvider()..startRound(r),
    child: MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: MatchStatusCard(
          round: r,
          p1: r.players.firstWhere((p) => p.id == miro),
          p2: r.players.firstWhere((p) => p.id == otro),
          t: GolfTheme.dark,
          skinsModules: const [],
          nassauModules: r.betGroups.first.modules,
          oyesModules: const [],
        ),
      ),
    ),
  )));
  await tester.pumpAndSettle();
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data ?? '')
      .join('  ‖  ');
}

void main() {
  testWidgets('CLAVE: la cabecera canta la línea, «5 3 1»', (tester) async {
    // CAM le gana a Dylan los cinco primeros: es la secuencia del argot.
    final txt = await _cabecera(tester, _ronda(ganaCam: const [1, 2, 3, 4, 5], hasta: 5));
    expect(txt, contains('F9 +5 +3 +1'));
  });

  testWidgets('CLAVE: presiones en LAS DOS vueltas, una línea por nueve',
      (tester) async {
    // F9: CAM gana 1-5 → 5 3 1. B9: gana 10 y 11 → 2 0, con su propia presión.
    final txt = await _cabecera(
        tester,
        _ronda(ganaCam: const [1, 2, 3, 4, 5, 10, 11], hasta: 12));
    expect(txt, contains('F9 '));
    expect(txt, contains('B9 +2 0'),
        reason: 'la presión del B9 acaba de nacer y entra en 0');
    // Y las del F9 no se cuelan en la del B9.
    expect(txt.contains('B9 +2 0 +'), isFalse);
  });

  testWidgets('CLAVE: y dice DÓNDE nació cada presión, que es lo que la línea no dice',
      (tester) async {
    // Una presión recién abierta es 0, y una empatada a mitad también: son el
    // mismo 0 a propósito. Lo que las separa es el hoyo, y va en el subrótulo.
    final txt = await _cabecera(
        tester,
        _ronda(ganaCam: const [1, 2, 3, 4, 5, 10, 11], hasta: 12));
    expect(txt, contains('Presiones desde'));
    expect(txt, contains('H3'), reason: 'la primera del F9');
    expect(txt, contains('H12'), reason: 'la del B9');
    // Y ya NO dice «3 presiones activas»: eso la línea lo dice por su longitud.
    expect(txt.contains('presiones activas'), isFalse);
  });

  testWidgets('CLAVE: la línea es de QUIEN MIRA', (tester) async {
    final r = _ronda(ganaCam: const [1, 2, 3, 4, 5], hasta: 5);
    expect(await _cabecera(tester, r, miro: 'cam'), contains('F9 +5 +3 +1'));
    expect(await _cabecera(tester, r, miro: 'dylan'), contains('F9 −5 −3 −1'));
  });

  testWidgets('CLAVE: sustituye al vocabulario viejo, no convive con él',
      (tester) async {
    // «F9: AS · B9: CAM 2UP» decía lo mismo. Dos vocabularios en el mismo
    // renglón sería peor que uno.
    final txt = await _cabecera(tester, _ronda(ganaCam: const [1, 2], hasta: 2));
    expect(txt.contains('UP'), isFalse);
    expect(txt.contains('F9: AS'), isFalse);
    expect(txt, contains('F9 +2 0'));
  });

  testWidgets('CLAVE: la línea también sale con el duelo EMPATADO',
      (tester) async {
    // CAM y Dylan se reparten dos hoyos: van iguales en hoyos ganados, y la
    // cabecera entra por la rama «EMPATADO».
    final r = _ronda(ganaCam: const [1], hasta: 4);
    final conDylan = r.copyWith(scores: {
      for (final id in _cinco.keys)
        id: {
          for (int h = 1; h <= 4; h++)
            h: HoleScore(
                playerId: id,
                hole: h,
                grossScore: (h == 1 && id == 'dylan') || (h == 2 && id == 'cam')
                    ? 5
                    : 4,
                putts: 2)
        }
    });
    final txt = await _cabecera(tester, conDylan);
    expect(txt, contains('EMPATADO'));
    expect(txt, contains('F9 0'));
    expect(txt.contains('AS'), isFalse, reason: 'el vocabulario viejo se fue');
  });

  testWidgets('CONTRAPESO: sin hoyos capturados no se inventa una línea',
      (tester) async {
    final txt = await _cabecera(tester, _ronda(ganaCam: const [], hasta: 0));
    expect(txt, contains('Esperando scores'));
  });
}
