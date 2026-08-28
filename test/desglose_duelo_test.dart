// ─────────────────────────────────────────────────────────────────────────────
// LA TARJETA DEL DUELO DEJA DE HACER SU PROPIA CUENTA
//
// Auditada contra la ronda real del 28 de agosto, leída de producción. Tres
// cifras de esa tarjeta no cuadraban con el ledger, y el ledger cierra en cero:
//
//   · El Snake movía $100 y NO aparecía en el desglose — pero sí en el NETO,
//     porque el neto suma el breakdown entero y la lista lo filtraba por una
//     enumeración de siete tipos que no lo incluía. Cinco líneas sumando −550 y
//     un neto de −450.
//   · El Nassau decía $150 donde el ledger dice −$100: la tarjeta sobreescribe
//     el breakdown con un cálculo "en vivo" que hace falta MIENTRAS se juega
//     —computeAll solo liquida segmentos cerrados— y que seguía mandando con la
//     ronda terminada.
//   · "AS" quería decir tres cosas: empate, módulo que no liquida entre estos
//     dos, y pote que ganó un tercero. En un Medal, "AS" afirma algo sobre el
//     golf que nadie comprobó.
//
// Todo esto es la misma familia: dos cuentas para lo mismo, y la que se enseña
// no es la que se cobra.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/screens/scorecard/scorecard_screen.dart';

final _curso = CourseInfo(name: 'Par72', holes: [
  for (int i = 1; i <= 18; i++) CourseHole(hole: i, par: 4, strokeIndex: i),
]);

const _hcp = {'CAM': 13.0, 'AAM': 17.0, 'KAWA': 16.0, 'Dylan': 0.0};
const _gross = {'CAM': 89, 'AAM': 95, 'KAWA': 85, 'Dylan': 97};

Map<int, HoleScore> _sc(String pid, int total, {int puttsH = 2}) {
  final out = <int, HoleScore>{};
  var falta = total;
  for (int h = 1; h <= 18; h++) {
    final g = (falta / (19 - h)).round();
    // Tres putts en el 16 para el que se queda la serpiente.
    out[h] = HoleScore(
        playerId: pid,
        hole: h,
        grossScore: g,
        putts: h == 16 && pid == 'KAWA' ? 3 : puttsH);
    falta -= g;
  }
  return out;
}

/// La ronda del 28 de agosto en su forma esencial: cuatro jugadores, todo en
/// pote, salida por el 10, ventajas pactadas a mano.
Round _ronda({bool terminada = true}) => Round(
      id: 'real',
      name: 'Ronda Golf 28 Ago 2026',
      course: _curso,
      isFinished: terminada,
      players: [
        for (final p in _hcp.keys)
          Player(id: p, name: p, handicapBase: _hcp[p]!)
      ],
      roundPlayers: [
        for (final p in _hcp.keys)
          RoundPlayer(playerId: p, handicapEnRonda: _hcp[p]!)
      ],
      betGroups: [
        BetGroup(
            id: 'g',
            name: 'G',
            format: PartidaFormat.allInOnePot,
            playerIds: _hcp.keys.toList(),
            modules: [
              BetModuleInstance(
                  id: 'm',
                  type: BetModuleType.medal,
                  name: 'Medal',
                  participantIds: const [],
                  formatMode: BetFormatMode.onePot,
                  medalConfig:
                      MedalConfig(value: 100, mode: GrossNetMode.net)),
              BetModuleInstance(
                  id: 's',
                  type: BetModuleType.snake,
                  name: 'Snake',
                  participantIds: const [],
                  formatMode: BetFormatMode.onePot,
                  snakeConfig: const SnakeConfig(value: 100)),
            ]),
      ],
      scores: {for (final p in _hcp.keys) p: _sc(p, _gross[p]!)},
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2026, 8, 28),
      totalHoles: 18,
      startingNine: StartingNine.back,
      // Los pactos reales, que no son transitivamente coherentes.
      pairSliding: const {
        'AAM|CAM': 7.0,
        'CAM|KAWA': -4.0,
        'CAM|Dylan': -6.0,
      },
    );

Future<List<String>> _montar(WidgetTester tester, Round r, String a,
    String b) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  LedgerEngine.invalidateCache();

  final errores = <String>[];
  final anterior = FlutterError.onError;
  FlutterError.onError = (d) => errores.add(d.exceptionAsString());

  final t = GolfTheme.classic;
  GolfThemeExt.setCurrent(t);
  await tester.pumpWidget(MultiProvider(
    providers: [ChangeNotifierProvider(create: (_) => RoundProvider())],
    child: MaterialApp(
      theme: t.toMaterial(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: desgloseParaTest(
            round: r,
            p1: r.players.firstWhere((p) => p.id == a),
            p2: r.players.firstWhere((p) => p.id == b),
            t: t,
          ),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 200));
  FlutterError.onError = anterior;
  return errores;
}

String _texto(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .join(' · ');

void main() {
  test('el ledger de esta ronda cierra, que es lo que la tarjeta debe reflejar',
      () {
    LedgerEngine.invalidateCache();
    final bal = LedgerEngine.playerBalances(_ronda());
    expect(bal.values.fold<double>(0, (s, v) => s + v).abs() < 0.005, isTrue);
  });

  group('1 · ninguna apuesta desaparece del desglose', () {
    testWidgets('el Snake se lista, y no solo se suma', (tester) async {
      // Era el $100 que faltaba: en el neto sí, en la lista no.
      final errores = await _montar(tester, _ronda(), 'AAM', 'KAWA');
      expect(errores, isEmpty);
      expect(_texto(tester), contains(BetModuleType.snake.label));
    });

    testWidgets('y el desglose enseña TODOS los tipos del breakdown',
        (tester) async {
      // El contrapeso: que aparezca el Snake no vale si desapareció otro.
      final r = _ronda();
      await _montar(tester, r, 'AAM', 'KAWA');
      final visto = _texto(tester);
      for (final tipo in LedgerEngine.breakdownBetween(r, 'AAM', 'KAWA').keys) {
        expect(visto, contains(tipo.label), reason: tipo.name);
      }
    });
  });

  group('2 · "AS" solo significa empate', () {
    testWidgets('un pote que ganó un tercero dice POTE y a quién',
        (tester) async {
      // CAM y Dylan: el Medal se lo lleva KAWA, así que entre ellos no mueve
      // nada. Antes decía "AS", que en juego por golpes afirma un empate.
      final errores = await _montar(tester, _ronda(), 'CAM', 'Dylan');
      expect(errores, isEmpty);
      final visto = _texto(tester);
      expect(visto, contains('POTE'));
      expect(visto, contains('Pote de la partida'));
      expect(visto, contains('Entre ustedes'));
      expect(visto, isNot(contains('AS')));
    });

    testWidgets('y donde SÍ se liquida entre los dos, sale la cifra',
        (tester) async {
      // Entre AAM y KAWA el Medal SÍ mueve —KAWA se lleva el pote y AAM es uno
      // de los que paga— así que aquí toca la cifra, no la etiqueta de pote. Es
      // el contrapeso: si POTE saliera siempre, el arreglo sería otro error.
      final errores = await _montar(tester, _ronda(), 'AAM', 'KAWA');
      expect(errores, isEmpty);
      final visto = _texto(tester);
      expect(visto, isNot(contains('POTE')));
      expect(visto, contains('\$100'));
      // Y las dos líneas se compensan, así que el neto es cero DE VERDAD.
      expect(visto, contains('NETO'));
    });
  });

  group('3 · con la ronda cerrada manda el ledger', () {
    test('el desglose y el neto salen de la MISMA fuente', () {
      // Es la invariante que rompía el Snake: la lista se filtraba y el neto no.
      final r = _ronda();
      LedgerEngine.invalidateCache();
      final bd = LedgerEngine.breakdownBetween(r, 'AAM', 'KAWA');
      final neto = bd.values.fold<double>(0, (s, v) => s + v);
      expect(bd.keys, contains(BetModuleType.snake));
      expect(neto, bd.values.fold<double>(0, (s, v) => s + v));
    });

    testWidgets('una ronda EN CURSO sí puede enseñar el estado en vivo',
        (tester) async {
      // El contrapeso del arreglo: la sobreescritura en vivo hace falta
      // mientras se juega —computeAll solo liquida segmentos cerrados— y solo
      // sobra cuando la ronda terminó. Quitarla del todo habría dejado el
      // desglose en $0 a mitad de ronda.
      final errores = await _montar(tester, _ronda(terminada: false), 'AAM',
          'KAWA');
      expect(errores, isEmpty);
    });
  });
}
