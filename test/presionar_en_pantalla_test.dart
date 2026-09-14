// ─────────────────────────────────────────────────────────────────────────────
// «PRESIONAR», EN PANTALLA: PROPONER, ACEPTAR Y VER EL DINERO
//
// El motor tiene sus pruebas. Esto comprueba lo otro: que la pantalla ofrece
// el pacto cuando toca, que una propuesta sola no mueve nada, y que el desglose
// distingue una presión de \$50 de una de \$100 — que es el criterio 4, y no se
// puede ver sin pulsar.
//
// Se monta el panel y el desglose sobre el MISMO provider, como en la pantalla.
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

/// CAV gana 1, 2 y 5 (presión del F9 con ganador) y 10, 11 y 14 (la del B9).
const _guion = [1, 2, 5, 10, 11, 14];

const _cfg = NassauConfig(
  frontValue: 50,
  backValue: 50,
  totalValue: 100,
  pressEnabled: true,
  autoPressTrigger: 2,
  frontPressValue: 50,
  backPressValue: 50,
);

Round _ronda({required int hasta}) => Round(
      id: 'r',
      name: 'El turn',
      course: _curso,
      isFinished: hasta == 18,
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
                  nassauConfig: _cfg),
            ])
      ],
      scores: {
        for (final p in ['cam', 'cav'])
          p: {
            for (int h = 1; h <= hasta; h++)
              h: HoleScore(
                  playerId: p,
                  hole: h,
                  grossScore: _guion.contains(h) && p == 'cam' ? 5 : 4,
                  putts: 2)
          }
      },
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2026, 9, 13),
      totalHoles: 18,
    );

/// Guardar el pacto, que es LO ÚNICO que la pantalla hace con él.
///
/// Quién propone y si está aceptado lo decide el panel y viene ya dentro del
/// objeto. Antes esta función repetía esa decisión, y por eso un contrapeso que
/// hacía nacer las propuestas ya aceptadas no mordía: la prueba tenía su propia
/// copia del cableado y no ejercitaba el de la pantalla.
void _pactar(RoundProvider p, PrecioDePresion pacto) {
  final r = p.round!;
  final clave = NassauConfig.carryPairKey('cam', 'cav');
  p.updateBetGroups(r.betGroups.map((g) {
    final mods = g.modules.map((m) {
      if (m.type != BetModuleType.nassau) return m;
      final mapa =
          Map<String, PrecioDePresion>.from(m.nassau.precioPresionB9ByPair)
            ..[clave] = pacto;
      return m.copyWith(
          nassauConfig: m.nassau.copyWith(precioPresionB9ByPair: mapa));
    }).toList();
    return g.copyWith(modules: mods);
  }).toList());
}

Future<RoundProvider> _montar(WidgetTester tester, Round r) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final prov = RoundProvider()..startRound(r);
  await tester.pumpWidget(ChangeNotifierProvider<RoundProvider>.value(
    value: prov,
    child: MaterialApp(
      home: Scaffold(
        body: Consumer<RoundProvider>(builder: (ctx, p, _) {
          final round = p.round!;
          final mods = round.betGroups.first.modules;
          return SingleChildScrollView(
            child: Column(children: [
              PrecioPresionPanel(
                round: round,
                p1: round.players[0],
                p2: round.players[1],
                t: GolfTheme.dark,
                nassauModules: mods,
                onPactar: (pacto) => _pactar(p, pacto),
              ),
              FinancialBreakdown(
                  round: round,
                  p1: round.players[0],
                  p2: round.players[1],
                  t: GolfTheme.dark),
            ]),
          );
        }),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return prov;
}

/// Sigue jugando hasta el 18, hoyo a hoyo, como la captura.
///
/// Hace falta porque la ventana para pactar es el TURN: con los dieciocho
/// anotados el panel ya no ofrece nada, así que el pacto se hace en el 9 y
/// después se juega. Es el orden real, y es el único en el que se puede ver el
/// dinero que produce.
Future<void> _jugarHastaEl18(WidgetTester tester, RoundProvider p) async {
  for (int h = 10; h <= 18; h++) {
    p.updateScore('cam', h, _guion.contains(h) ? 5 : 4, 2);
    p.updateScore('cav', h, 4, 2);
  }
  await tester.pumpAndSettle();
}

String _texto(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .join('  ‖  ');

void main() {
  testWidgets('CLAVE: al terminar el F9 se ofrece, y los DOS pueden proponer',
      (tester) async {
    await _montar(tester, _ronda(hasta: 9));
    final texto = _texto(tester);
    expect(texto, contains('PRESIÓN DEL B9'));
    expect(texto, contains('CAM propone'));
    expect(texto, contains('CAV propone'));
    // Y dice lo que vale hoy, que es contra lo que se sube.
    expect(texto, contains(r'$50'));
  });

  testWidgets('CLAVE: a mitad del F9 dice por qué no, en vez de desaparecer',
      (tester) async {
    await _montar(tester, _ronda(hasta: 5));
    final texto = _texto(tester);
    expect(texto, contains('PRESIÓN DEL B9'));
    expect(texto, contains('Al terminar el F9'));
    expect(texto, isNot(contains('propone')));
  });

  testWidgets('CLAVE: propuesto no vale; aceptado sí, y el desglose lo enseña',
      (tester) async {
    // En el turn: es la única ventana para pactar.
    await _montar(tester, _ronda(hasta: 9));

    // Antes de nada: la presión del B9 vale 50, como la del F9.
    expect(_texto(tester), isNot(contains(r'CAM propone que')));

    // ── Uno propone ────────────────────────────────────────────────────────
    // Se PULSA, no se llama: la regla de que una propuesta nace sin aceptar
    // vive en el botón, y llamarla a mano la saltaría.
    await tester.enterText(find.byType(TextField), '100');
    await tester.tap(find.text('CAM propone'));
    await tester.pumpAndSettle();

    var texto = _texto(tester);
    expect(texto, contains('CAM propone'));
    expect(texto, contains('CAV acepta'), reason: 'le toca al otro');
    // Una propuesta sola no mueve dinero: la presión del B9 sigue en 50.
    expect(texto, contains('valen \$50'));

    // ── El otro acepta, pulsando ───────────────────────────────────────────
    await tester.tap(find.text('CAV acepta'));
    await tester.pumpAndSettle();

    texto = _texto(tester);
    expect(texto, contains('Pactado'));
    expect(texto, contains('cada presión del B9 vale \$100'));
    expect(texto, contains('Las del F9 siguen en \$50'),
        reason: 'es literalmente la condición de Carlos');
  });

  testWidgets('CLAVE (criterio 4): el desglose distingue la de \$50 de la de '
      '\$100', (tester) async {
    final prov = await _montar(tester, _ronda(hasta: 9));
    await tester.enterText(find.byType(TextField), '100');
    await tester.tap(find.text('CAM propone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CAV acepta'));
    await tester.pumpAndSettle();
    await _jugarHastaEl18(tester, prov);

    final texto = _texto(tester);
    // Las dos presiones están, cada una con SU importe. Sin esto el desglose
    // diría un solo número por tipo y habría que sumar a mano para saber que
    // una valió el doble — que es exactamente lo que ya pasó con el carry.
    expect(texto, contains('Press H3'), reason: 'la del F9');
    expect(texto, contains('Press H12'), reason: 'la del B9');
    // El signo es un MENOS de verdad (U+2212), no un guion: la app lo escribe
    // así en todo el desglose.
    expect(texto, contains('Press H3–H9 (Nassau Front 9)  ‖  −\$50'),
        reason: 'la del F9 se queda en 50');
    expect(texto, contains('Press H12–H18 (Nassau Back 9)  ‖  −\$100'),
        reason: 'la del B9, ya al precio pactado');
  });
}
