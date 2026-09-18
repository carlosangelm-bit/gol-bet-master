// ─────────────────────────────────────────────────────────────────────────────
// DÓNDE ATERRIZA APUESTAS
//
//     «¿Cuál es el punto de la pestaña de reglas una vez dentro de la ronda?»
//
// El punto es real: Reglas es el único sitio con la configuración pactada Y
// editable durante la ronda. Lo que sobraba era el aterrizaje — Apuestas abría
// siempre ahí, y a mitad de ronda uno entra a ver quién va ganando.
//
// Reglas antes de empezar, Duelos en cuanto hay un hoyo anotado.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/screens/bets/bets_screen.dart';
import 'package:provider/provider.dart';

final _curso = CourseInfo(name: 'P72', holes: [
  for (int i = 1; i <= 18; i++) CourseHole(hole: i, par: 4, strokeIndex: i),
]);

const _tres = ['cam', 'cav', 'aam'];

Round _ronda({required int anotados}) => Round(
      id: 'r',
      name: 'Hoy',
      course: _curso,
      isFinished: false,
      players: [for (final p in _tres) Player(id: p, name: p.toUpperCase())],
      roundPlayers: [
        for (final p in _tres) RoundPlayer(playerId: p, handicapEnRonda: 0),
      ],
      betGroups: [
        BetGroup(
            id: 'g',
            name: 'G',
            format: PartidaFormat.oneVsOne,
            playerIds: _tres,
            modules: [
              BetModuleInstance.defaultFor(BetModuleType.nassau, _tres,
                  id: 'n'),
            ])
      ],
      scores: {
        for (final p in _tres)
          p: {
            for (int h = 1; h <= anotados; h++)
              h: HoleScore(playerId: p, hole: h, grossScore: 4, putts: 2)
          }
      },
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2026, 9, 19),
      totalHoles: 18,
    );

Future<String> _montar(WidgetTester tester, Round r) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final prov = RoundProvider()..startRound(r);
  await tester.pumpWidget(ChangeNotifierProvider<RoundProvider>.value(
    value: prov,
    child: const MaterialApp(home: BetsScreen()),
  ));
  await tester.pumpAndSettle();
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data ?? '')
      .join('  ‖  ');
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  group('1 · «la ronda ya empezó», en un solo sitio', () {
    test('CLAVE: sin ningún score, no ha empezado', () {
      expect(_ronda(anotados: 0).haEmpezado, isFalse);
    });

    test('CLAVE: con uno, sí', () {
      expect(_ronda(anotados: 1).haEmpezado, isTrue);
    });

    test('CONTRAPESO: un mapa de scores VACÍO no cuenta como empezada', () {
      // Una ronda recién creada trae la estructura con los jugadores dentro y
      // ningún hoyo. Contar las claves en vez de los scores la daría empezada.
      final r = _ronda(anotados: 0);
      expect(r.scores.keys, isNotEmpty, reason: 'los tres están en el mapa');
      expect(r.haEmpezado, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('2 · y Apuestas aterriza donde toca', () {
    testWidgets('CLAVE: sin empezar, abre en Reglas', (tester) async {
      final texto = await _montar(tester, _ronda(anotados: 0));
      expect(texto, contains('APUESTAS DE LA RONDA'),
          reason: 'es donde se revisa y se corrige antes de salir');
    });

    testWidgets('CLAVE: con hoyos anotados, abre en Duelos', (tester) async {
      final texto = await _montar(tester, _ronda(anotados: 3));
      expect(texto, isNot(contains('APUESTAS DE LA RONDA')));
      // La vista de duelos enseña a los jugadores enfrentados.
      expect(texto, contains('CAM'));
      expect(texto, contains('CAV'));
    });

    testWidgets('CONTRAPESO: y el selector sigue estando, con las dos',
        (tester) async {
      // Aterrizar en una no puede esconder la otra: la configuración se
      // consulta a mitad de ronda cuando alguien discute un importe.
      final texto = await _montar(tester, _ronda(anotados: 3));
      expect(texto, contains('Reglas'));
      expect(texto, contains('Duelos'));
    });
  });
}
