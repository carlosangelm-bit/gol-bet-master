// ─────────────────────────────────────────────────────────────────────────────
// LAS PRESIONES SE CORTAN UNAS A OTRAS
//
// Ronda del 18 Sep, CAM vs KAWA. La línea del B9:
//
//     B9  −3  +1  −1  −1        Presiones desde H12 · H14 · H16
//
// Y el desglose:
//
//     Press H12–H13 (Nassau Back 9)   +\$50
//     Press H14–H15 (Nassau Back 9)   −\$50
//     Press H16–H18 (Nassau Back 9)   −\$50
//
// Tres presiones troceadas, cada una cortada donde nace la siguiente.
//
//     «¿En qué momento yo dije que las presiones se mueren? ¿Dónde está esa
//      configuración?»
//
// No lo dijo y no hay configuración. Es una diferencia de implementación que
// quedó al retirar Match + Press: allí cada presión corría hasta el 18 y todas
// convivían; el motor de Nassau cierra donde nace la siguiente.
//
// Y hay una segunda cosa, que es la que Carlos señala con el dedo: la LÍNEA y
// el DESGLOSE ni siquiera se cortan en el mismo sitio. El desglose etiqueta
// «H12–H13» y paga sobre dos hoyos; la línea enseña +1, que es un hoyo. Dos
// cuentas del mismo número, otra vez.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/screens/scorecard/scorecard_screen.dart';
import 'package:provider/provider.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';
import 'package:golf_bet_master/models/models.dart';

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
  // Tres presiones en un nueve: el módulo de Carlos las encadena. Con el
  // default —una por segmento— este fallo no se ve.
  allowMultiplePresses: true,
);

/// El B9 del 18 Sep, hoyo a hoyo, en perspectiva de CAM.
///
/// KAWA gana 10 y 11 → presión en H12. CAM gana 12 y 13 → presión en H14.
/// KAWA gana 14 y 15 → presión en H16. KAWA gana el 16; 17 y 18 empatados.
/// El B9 queda −3, que es el primer número de la línea de Carlos.
const _ganaKawa = [10, 11, 14, 15, 16];
const _ganaCam = [12, 13];

Round _ronda({int hasta = 18}) => Round(
      id: 'r',
      name: '18 Sep',
      course: _curso,
      isFinished: hasta == 18,
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
            for (int h = 1; h <= hasta; h++)
              h: HoleScore(
                  playerId: p,
                  hole: h,
                  grossScore: (_ganaKawa.contains(h) && p == 'cam') ||
                          (_ganaCam.contains(h) && p == 'kawa')
                      ? 5
                      : 4,
                  putts: 2)
          }
      },
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2026, 9, 18),
      totalHoles: 18,
    );

BetModuleInstance _mod(Round r) => r.betGroups.first.modules.first;

List<String> _presionesDelB9(Round r) {
  LedgerEngine.invalidateCache();
  return LedgerEngine.entriesOf(r)
      .where((e) => e.reason.contains('Press') && e.reason.contains('Back 9'))
      .map((e) =>
          '${e.reason} ${e.toPlayerId == 'cam' ? '+' : '−'}\$${e.amount.toStringAsFixed(0)}')
      .toList();
}

LineaDelDuelo _lineaB9(Round r) =>
    BetEngine.lineasDelDuelo(r, 'cam', 'kawa', _mod(r))
        .firstWhere((l) => l.etiqueta == 'B9');

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  group('1 · una presión corre hasta el final de su segmento', () {
    test('CLAVE (criterio 1): las tres cubren hasta el 18', () {
      // Antes: H12–H13, H14–H15, H16–H18. Cada una cortada donde nace la
      // siguiente, que es un comportamiento que nadie pidió ni configuró.
      expect(_presionesDelB9(_ronda()), [
        'Press H12–H18 (Nassau Back 9) −\$50',
        'Press H14–H18 (Nassau Back 9) −\$50',
        'Press H16–H18 (Nassau Back 9) −\$50',
      ]);
    });

    test('CLAVE (criterio 2): conviven, cada una con SU marcador', () {
      // Los tres marcadores son distintos entre sí porque cada presión empieza
      // en un hoyo distinto y llega al mismo final:
      //   H12 → desde −2, acaba en −3 → −1
      //   H14 → desde  0, acaba en −3 → −3
      //   H16 → desde −2, acaba en −3 → −1
      final linea = _lineaB9(_ronda());
      expect(linea.numeros, [-3, -1, -3, -1]);
      expect(linea.presiones, 3);
    });

    test('CONTRAPESO: y la línea dice lo MISMO que el ledger', () {
      // Aquí estaba la segunda mitad del fallo. El desglose etiquetaba
      // «H12–H13» y pagaba sobre dos hoyos; la línea enseñaba +1, que es uno.
      // Se cortaban en sitios distintos —una por el hoyo donde saltó el
      // disparo, otra por el hoyo donde empieza la presión— así que el número
      // de la pantalla no era el que se cobraba.
      final linea = _lineaB9(_ronda());
      final signos = _presionesDelB9(_ronda())
          .map((s) => s.contains('+\$') ? 1 : -1)
          .toList();
      for (var i = 0; i < signos.length; i++) {
        expect(linea.numeros[i + 1].sign, signos[i],
            reason: 'la presión ${i + 1} de la línea y la del desglose');
      }
    });
  });

  _enPantalla();

  // ═══════════════════════════════════════════════════════════════════════════
  group('2 · el «5 3 1» vuelve a ser lo que Carlos describió', () {
    test('CLAVE (criterio 3): un número por apuesta viva, y todas avanzan', () {
      // El ejemplo del docstring, que solo tiene sentido si las presiones
      // conviven:
      //
      //     Gana el 1º   1
      //     Gana el 2º   2 0      ← nace una presión
      //     Gana el 3º   3 1
      //     Gana el 4º   4 2 0    ← nace otra
      //     Gana el 5º   5 3 1
      //
      // Se construye ganando los cinco primeros del F9, que es como se canta.
      final r = _cincoSeguidos();
      final f9 = BetEngine.lineasDelDuelo(r, 'cam', 'kawa', _mod(r))
          .firstWhere((l) => l.etiqueta == 'F9');
      expect(f9.numeros, [5, 3, 1]);
      expect(f9.texto, '+5 +3 +1');
    });

    test('CONTRAPESO: el matiz de «puede quedar en +5 +1 +1» desaparece', () {
      // Estaba escrito como una propiedad del juego —«en vivo una cosa, al
      // cerrar otra»— y era la inconsistencia: la rama abierta ya corría hasta
      // el final y la cerrada cortaba. Ahora el nueve a medias y el nueve
      // terminado dan la misma línea sobre los mismos hoyos.
      final medias = BetEngine.lineasDelDuelo(
              _cincoSeguidos(hasta: 5), 'cam', 'kawa', _mod(_cincoSeguidos()))
          .firstWhere((l) => l.etiqueta == 'F9');
      expect(medias.numeros, [5, 3, 1]);
    });
  });
}

/// CAM gana los cinco primeros hoyos. [hasta] los hoyos anotados.
Round _cincoSeguidos({int hasta = 9}) {
  final base = _ronda();
  return base.copyWith(
    isFinished: false,
    scores: {
      for (final p in ['cam', 'kawa'])
        p: {
          for (int h = 1; h <= hasta; h++)
            h: HoleScore(
                playerId: p,
                hole: h,
                grossScore: h <= 5 && p == 'kawa' ? 5 : 4,
                putts: 2)
        }
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// 3 · EN PANTALLA, LA RONDA DEL 18 SEP
//
// Es donde Carlos lo vio: la línea del B9 y los hoyos de nacimiento debajo.
// ─────────────────────────────────────────────────────────────────────────────
void _enPantalla() {
  testWidgets('CLAVE (criterio 4): la línea del B9 del 18 Sep, en la tarjeta',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final r = _ronda();
    final prov = RoundProvider()..startRound(r);
    await tester.pumpWidget(ChangeNotifierProvider<RoundProvider>.value(
      value: prov,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MatchStatusCard(
              round: r,
              p1: r.players[0],
              p2: r.players[1],
              t: GolfTheme.dark,
              skinsModules: const [],
              nassauModules: [_mod(r)],
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final texto = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? '')
        .join('  ‖  ');

    // Lo que Carlos veía: «−3 +1 −1 −1», con la primera presión en positivo
    // porque se cerraba en el hoyo 12.
    expect(texto, isNot(contains('−3 +1 −1 −1')));
    // Lo que dice ahora: las tres corren hasta el 18 desde su propio hoyo.
    expect(texto, contains('−3 −1 −3 −1'));
    // Y los tres nacimientos siguen anunciándose.
    expect(texto, contains('H12'));
    expect(texto, contains('H14'));
    expect(texto, contains('H16'));
  });
}
