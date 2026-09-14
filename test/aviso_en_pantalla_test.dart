// ─────────────────────────────────────────────────────────────────────────────
// EL AVISO DE SCORE INCOMPLETO, EN LA PANTALLA DONDE CARLOS LO VIO
//
// La cuenta ya tiene pruebas propias. Esto comprueba la otra mitad: que la
// pantalla LEE esa cuenta. Es la separación que ha fallado tantas veces en esta
// app —«la lógica existe, la capa siguiente no la lee»— y aquí es más fácil que
// nunca, porque hasta hoy la cuenta vivía DENTRO del `build` de esta pantalla.
//
// Se monta `ResultsBody` con la ronda del caso real: nueve hoyos completos, un
// score suelto en el 10, cerrada y liquidada.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/screens/results/results_screen.dart';
import 'package:provider/provider.dart';

final _curso = CourseInfo(name: 'P72', holes: [
  for (int i = 1; i <= 18; i++) CourseHole(hole: i, par: 4, strokeIndex: i),
]);

const _cinco = ['cam', 'rich', 'kawa', 'aam', 'dylan'];

/// La ronda de Carlos: cinco jugadores, seis apuestas, nueve hoyos anotados.
///
/// [sueltoEn10] quiénes tienen además un score en el hoyo 10 — el accidente que
/// hace que `singleNine` deje de ser cierto.
Round _ronda({List<String> sueltoEn10 = const []}) => Round(
      id: 'r',
      name: '28 Jul',
      course: _curso,
      isFinished: true,
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
          modules: [
            for (final t in const [
              BetModuleType.nassau,
              BetModuleType.skins,
              BetModuleType.snake,
              BetModuleType.medal,
              BetModuleType.rabbit,
              BetModuleType.oyeses,
            ])
              BetModuleInstance(
                  id: t.name, type: t, name: t.label, participantIds: _cinco),
          ],
        )
      ],
      scores: {
        for (final p in _cinco)
          p: {
            for (int h = 1; h <= 9; h++)
              h: HoleScore(playerId: p, hole: h, grossScore: 4, putts: 2),
            if (sueltoEn10.contains(p))
              10: HoleScore(playerId: p, hole: 10, grossScore: 4, putts: 2),
          }
      },
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2026, 7, 28),
      totalHoles: 9,
    );

Future<String> _montar(WidgetTester tester, Round r) async {
  final prov = RoundProvider()..startRound(r);
  await tester.pumpWidget(ChangeNotifierProvider<RoundProvider>.value(
    value: prov,
    child: MaterialApp(home: Scaffold(body: ResultsBody(round: r))),
  ));
  await tester.pumpAndSettle();
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data ?? '')
      .join('  ‖  ');
}

void main() {
  testWidgets('CLAVE: la ronda del caso real ya no dice «falta CAM, RICH, DYLAN» '
      'seis veces', (tester) async {
    final texto = await _montar(tester, _ronda(sueltoEn10: ['kawa', 'aam']));

    // Lo que Carlos vio, seis veces seguidas.
    expect(texto, isNot(contains('falta CAM')));
    expect('falta '.allMatches(texto).length, 0);

    // Y lo que se dice en su lugar: una vez, con el hoyo delante.
    expect(texto, contains('Se cerró con 1 hoyo a medias (10)'));
    expect('Se cerró con'.allMatches(texto).length, 1,
        reason: 'una línea, no una por apuesta');
  });

  testWidgets('una ronda de nueve COMPLETA no enseña ningún aviso',
      (tester) async {
    final texto = await _montar(tester, _ronda());
    expect(texto, isNot(contains('Se cerró con')));
    expect(texto, isNot(contains('falta')));
    // Y no es que la pantalla no haya pintado: las apuestas están ahí.
    expect(texto, contains('APUESTAS DE ESTA RONDA'));
  });
}
