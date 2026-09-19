// ─────────────────────────────────────────────────────────────────────────────
// MARCAR UNA APUESTA MANUAL, EN LA PANTALLA DE ANOTAR
//
//     «Marcar un fairway son 18 toques por jugador; si cada uno cuesta abrir
//      algo, nadie lo usa y volverán a apuntarlo en una servilleta.»
//
// Por eso los chips van EN LÍNEA y no en una hoja como Units: una manual es UNA
// pregunta por hoyo, y la respuesta es un toque.
//
// Y el ranking se resuelve con el mismo gesto: se tocan los nombres en orden y
// el chip enseña la posición. Sin teclear números.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/screens/capture/capture_screen.dart';
import 'package:provider/provider.dart';

final _curso = CourseInfo(name: 'P72', holes: [
  for (int i = 1; i <= 18; i++) CourseHole(hole: i, par: 4, strokeIndex: i),
]);

const _cinco = ['cam', 'kawa', 'jose', 'aam', 'rich'];

BetModuleInstance _manual(String id, String nombre, ModoManual modo) =>
    BetModuleInstance(
      id: id,
      type: BetModuleType.manual,
      name: nombre,
      participantIds: _cinco,
      formatMode: BetFormatMode.allVsAll,
      manualConfig: ManualConfig(nombre: nombre, modo: modo),
    );

Round _ronda() => Round(
      id: 'r',
      name: 'Hoy',
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
            modules: [
              _manual('fw', 'Fairways', ModoManual.siNo),
              _manual('pen', 'Penaltis', ModoManual.siNoInvertido),
              _manual('drive', 'Drive', ModoManual.ranking),
            ])
      ],
      scores: {for (final p in _cinco) p: {}},
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2026, 9, 20),
      totalHoles: 18,
    );

void main() {
  Future<RoundProvider> montar(WidgetTester tester, String pid) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final r = _ronda();
    final prov = RoundProvider()..startRound(r);
    await tester.pumpWidget(ChangeNotifierProvider<RoundProvider>.value(
      value: prov,
      child: MaterialApp(
        home: Scaffold(
          body: Consumer<RoundProvider>(
            builder: (_, p, __) => ManualCapture(
              manuales: ManualCapture.apuestasDe(p.round!, pid),
              round: p.round!,
              playerId: pid,
              hole: 7,
              t: GolfTheme.dark,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return prov;
  }

  testWidgets('CLAVE (criterio 2): las tres están, y marcar es UN toque',
      (tester) async {
    final prov = await montar(tester, 'cam');

    // Las tres apuestas del grupo, con su nombre. Sin abrir nada.
    expect(find.text('Fairways'), findsOneWidget);
    expect(find.text('Penaltis'), findsOneWidget);
    expect(find.text('Drive'), findsOneWidget);

    await tester.tap(find.text('Fairways'));
    await tester.pumpAndSettle();
    expect(prov.round!.marcadosEn('fw', 7), ['cam']);

    // Y destocar lo quita: el mismo gesto en los dos sentidos.
    await tester.tap(find.text('Fairways'));
    await tester.pumpAndSettle();
    expect(prov.round!.marcadosEn('fw', 7), isEmpty);
  });

  testWidgets('CLAVE (criterio 4): el ranking sale del ORDEN en que se toca',
      (tester) async {
    // Tres jugadores en el mismo hoyo, tocados en orden. Cada uno tiene su
    // propia fila en la pantalla real; aquí se montan uno tras otro.
    final r = _ronda();
    final prov = RoundProvider()..startRound(r);
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final pid in ['kawa', 'cam', 'jose']) {
      await tester.pumpWidget(ChangeNotifierProvider<RoundProvider>.value(
        value: prov,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer<RoundProvider>(
              builder: (_, p, __) => ManualCapture(
                manuales: ManualCapture.apuestasDe(p.round!, pid),
                round: p.round!,
                playerId: pid,
                hole: 7,
                t: GolfTheme.dark,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Drive'));
      await tester.pumpAndSettle();
    }

    expect(prov.round!.marcadosEn('drive', 7), ['kawa', 'cam', 'jose']);
    // Y el chip de JOSE, que es el último, enseña su posición: 3º.
    expect(find.text('3º'), findsOneWidget);
  });

  testWidgets('CONTRAPESO: un jugador fuera de la apuesta no la ve',
      (tester) async {
    // Quien no juega fairways no tiene por qué tener el chip delante.
    final r = _ronda();
    final sinCam = r.copyWith(betGroups: [
      r.betGroups.first.copyWith(modules: [
        _manual('fw', 'Fairways', ModoManual.siNo)
            .copyWith(participantIds: const ['kawa', 'jose']),
      ])
    ]);
    expect(ManualCapture.apuestasDe(sinCam, 'cam'), isEmpty);
    expect(ManualCapture.apuestasDe(sinCam, 'kawa'), hasLength(1));
  });
}
