// ─────────────────────────────────────────────────────────────────────────────
// SNAKE EN PANTALLA, CON CINCO JUGADORES
//
// La ronda del 15 Sep tiene DIEZ módulos de Snake guardados —uno por duelo— y
// no hay migración, así que sigue teniéndolos. Lo que se comprueba aquí es lo
// que Carlos ve al abrirla:
//
//   · en Apuestas, UN aviso en vez de diez
//   · en el Resumen, una LÍNEA, no un párrafo — y los resultados a la vista
//   · y lo que dice es cierto para la partida
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test/flutter_test.dart' as ft;
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/engines/settlement_notes.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/screens/results/results_screen.dart';
import 'package:golf_bet_master/widgets/notas_liquidacion_card.dart';
import 'package:provider/provider.dart';

final _curso = CourseInfo(name: 'P72', holes: [
  for (int i = 1; i <= 18; i++) CourseHole(hole: i, par: 4, strokeIndex: i),
]);

/// El orden importa, y por eso está escrito así.
///
/// El primer duelo que sale de C(5,2) es (CAM, AAM), y ninguno de los dos hace
/// tres putts. Con RAFA y CAV delante, quedarse con los participantes del
/// PRIMER módulo daba por casualidad la respuesta correcta y la unión no se
/// probaba — un contrapeso pasó por eso.
const _cinco = ['cam', 'aam', 'kawa', 'rafa', 'cav'];

/// Los diez módulos 1v1 que esa ronda tiene guardados.
List<BetModuleInstance> _diezGuardados() => [
      for (int i = 0; i < _cinco.length; i++)
        for (int k = i + 1; k < _cinco.length; k++)
          BetModuleInstance.defaultFor(
              BetModuleType.snake, [_cinco[i], _cinco[k]],
              id: 'snake_${_cinco[i]}_${_cinco[k]}'),
    ];

/// La ronda del 15 Sep: RAFA 3 putts en el 17, CAV en el 15, nueve anotados.
Round _ronda() => Round(
      id: 'r',
      name: '15 Sep',
      course: _curso,
      isFinished: false,
      players: [for (final p in _cinco) Player(id: p, name: p.toUpperCase())],
      roundPlayers: [
        for (final p in _cinco) RoundPlayer(playerId: p, handicapEnRonda: 0),
      ],
      betGroups: [
        BetGroup(
            id: 'g',
            name: 'G',
            format: PartidaFormat.oneVsOne,
            playerIds: _cinco,
            modules: _diezGuardados())
      ],
      scores: {
        for (final p in _cinco)
          p: {
            for (final h in const [1, 2, 3, 4, 5, 6, 7, 15, 17])
              h: HoleScore(
                  playerId: p,
                  hole: h,
                  grossScore: 4,
                  putts: (p == 'cav' && h == 15) || (p == 'rafa' && h == 17)
                      ? 3
                      : 2)
          }
      },
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2026, 9, 15),
      totalHoles: 18,
    );

String _texto(WidgetTester tester) => tester
    .widgetList<Text>(ft.find.byType(Text))
    .map((w) => w.data ?? '')
    .join('  ‖  ');

/// Todo el texto pintado, incluido el de los RichText —la tarjeta de notas
/// usa spans, así que `Text.data` viene vacío y sin esto no se lee nada.
String _todo(WidgetTester tester) {
  final b = StringBuffer(_texto(tester));
  for (final r in tester.widgetList<RichText>(ft.find.byType(RichText))) {
    b.write('  ‖  ${r.text.toPlainText()}');
  }
  return b.toString();
}

void main() {
  testWidgets('CLAVE (criterios 1 y 3): en Apuestas, UN aviso y cierto',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final round = _ronda();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NotasLiquidacionCard(
            notas: notasDeLiquidacion(round), t: GolfTheme.dark),
      ),
    ));
    await tester.pumpAndSettle();

    final texto = _todo(tester);
    // Uno, no diez.
    expect('Snake · '.allMatches(texto).length, 1);
    // Y con el detalle, que es para lo que está esta pantalla.
    expect(texto, contains('RAFA la agarró en el hoyo 17 con 3 putts'));
    expect(texto, contains('Provisional'));
    // Lo que era falso: tres duelos decían esto mientras dos ya la habían
    // tenido.
    expect(texto, isNot(contains('Nadie ha llegado')));
  });

  testWidgets('CLAVE (criterio 2): en el Resumen, una línea y los resultados '
      'a la vista', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // `ResultsScreen`, no `ResultsBody`: la tarjeta de notas vive en la
    // primera. Monté la segunda y no encontré nada — son dos superficies, y la
    // que Carlos mira es esta.
    final round = _ronda();
    final prov = RoundProvider()..startRound(round);
    await tester.pumpWidget(ChangeNotifierProvider<RoundProvider>.value(
      value: prov,
      // `embedded: true` la deja sin Scaffold —vive dentro de una pestaña— así
      // que el Scaffold lo pone el test, igual que la app.
      child: const MaterialApp(
          home: Scaffold(body: ResultsScreen(embedded: true))),
    ));
    await tester.pumpAndSettle();

    final texto = _todo(tester);
    expect('Snake · '.allMatches(texto).length, 1);
    // La línea corta, que es la que Carlos propuso.
    expect(texto, contains('la tiene RAFA (H17), provisional'));
    // Y NO el párrafo: es lo que empujaba los resultados fuera de pantalla.
    expect(texto, isNot(contains('quedan 9 hoyos por capturar')));
    expect(texto, isNot(contains('un 3-putt posterior se la lleva')));
    // Los resultados siguen ahí.
    expect(texto, contains('APUESTAS DE ESTA RONDA'));
  });
}
