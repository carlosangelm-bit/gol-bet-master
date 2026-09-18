// ─────────────────────────────────────────────────────────────────────────────
// EL SLIDING DEL PASO 8 NO LLEGA AL PASO 9
//
// Paso 8 · Ventaja, lo que Carlos configura:
//
//     CAM vs KAWA   −1   acumulado −1.0
//     CAM vs Jose    0   acumulado  0.0
//     KAWA vs Jose   0   acumulado  0.0
//
// Paso 9 · Revisar, lo que aparece:
//
//     CAM vs KAWA   −1   Manual
//     CAM vs Jose   −4   Calculado por HCP automático
//     KAWA vs Jose  −1   Calculado por HCP automático
//
// Solo sobrevive el que se editó a mano. Y un cero es un acuerdo —jugar a la
// par— no una ausencia.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/screens/setup/setup_screen.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/models/bet_recipe.dart';
import 'package:golf_bet_master/models/models.dart';

const _cam = 'a_cam', _kawa = 'b_kawa', _jose = 'c_jose';
const _tres = [_cam, _kawa, _jose];

/// Lo que Carlos dejó en el paso 8: −1 entre CAM y KAWA, cero en los otros dos.
double _editadoEnElPaso8(String a, String b) {
  final k = BetEngine.pairKey(a, b);
  return k == BetEngine.pairKey(_cam, _kawa) ? -1.0 : 0.0;
}

/// El paso 9, montado con lo que la ronda se lleva de verdad.
Future<String> _montarPaso9(
  WidgetTester tester, {
  required SistemaDeVentaja ventaja,
  double Function(String a, String b)? editado,
}) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final r = _ronda(sliding: const {});
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: HandicapMatrix(
          players: r.players,
          playerTees: const {},
          manualHandicaps: const {},
          // Los INGREDIENTES, no un mapa ya hecho: la matriz lo deriva con la
          // misma función que construye la ronda, y por eso no puede enseñar
          // algo distinto de lo que se va a jugar.
          ventaja: ventaja,
          acumuladoDelGrupo: const {},
          editadoEnElPaso: editado,
          playingHcp: (p) =>
              r.roundPlayers.firstWhere((x) => x.playerId == p.id)
                  .handicapEnRonda.toDouble(),
          onEdit: (_, __, ___) {},
          t: GolfTheme.dark,
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

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  group('1 · lo que la RONDA se lleva', () {
    test('CLAVE: los tres cruces, incluidos los ceros', () {
      final mapa = slidingDeRonda(
        ventaja: SistemaDeVentaja.sliding,
        acumuladoDelGrupo: const {},
        participantIds: _tres,
        editadoEnElPaso: _editadoEnElPaso8,
      );
      expect(mapa[BetEngine.pairKey(_cam, _kawa)], -1.0);
      expect(mapa[BetEngine.pairKey(_cam, _jose)], 0.0,
          reason: 'un acuerdo de cero es un acuerdo, no una ausencia');
      expect(mapa[BetEngine.pairKey(_kawa, _jose)], 0.0);
    });

    test('CLAVE: y la ventaja que se aplica es cero, no la del handicap', () {
      // Es el punto que Carlos llama dinero: con HCP 4 de diferencia, si el
      // cero no llegara, Jose recibiría cuatro golpes que nadie pactó.
      final r = _ronda(sliding: slidingDeRonda(
        ventaja: SistemaDeVentaja.sliding,
        acumuladoDelGrupo: const {},
        participantIds: _tres,
        editadoEnElPaso: _editadoEnElPaso8,
      ));
      expect(r.ventajaDe(_cam, _jose), 0.0);
      expect(r.ventajaDe(_cam, _kawa), -1.0);
    });
  });

  _paso9();
  group('3 · la ventaja, que era lo único en dos sitios', _dosSitios);
}

/// Tres jugadores con handicaps DISTINTOS a propósito: si el acuerdo no
/// llegara, la diferencia de handicaps es lo que se aplicaría, y se nota.
Round _ronda({required Map<String, double> sliding}) => Round(
      id: 'r',
      name: '16 Sep',
      course: CourseInfo(name: 'P72', holes: [
        for (int i = 1; i <= 18; i++)
          CourseHole(hole: i, par: 4, strokeIndex: i),
      ]),
      isFinished: false,
      players: [
        Player(id: _cam, name: 'CAM'),
        Player(id: _kawa, name: 'KAWA'),
        Player(id: _jose, name: 'Jose'),
      ],
      roundPlayers: [
        RoundPlayer(playerId: _cam, handicapEnRonda: 6),
        RoundPlayer(playerId: _kawa, handicapEnRonda: 7),
        RoundPlayer(playerId: _jose, handicapEnRonda: 10),
      ],
      betGroups: const [],
      scores: const {},
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      pairSliding: sliding,
      createdAt: DateTime(2026, 9, 16),
      totalHoles: 18,
    );

// ─────────────────────────────────────────────────────────────────────────────
// 2 · LO QUE EL PASO 9 ENSEÑA
//
// Con el mapa que la ronda se lleva —−1, 0, 0— la matriz tiene que decir eso.
// Enseñaba −4 y −1 «Calculado por HCP automático» porque recibía el acumulado
// del GRUPO en vez de lo efectivo: los ceros no estaban ahí, y sin entrada la
// fila cae a la diferencia de handicaps.
// ─────────────────────────────────────────────────────────────────────────────
void _paso9() {
  testWidgets('CLAVE (criterio 1): el cero llega y se enseña como igualdad',
      (tester) async {
    final texto = await _montarPaso9(tester,
        ventaja: SistemaDeVentaja.sliding, editado: _editadoEnElPaso8);

    // Los dos ceros, como acuerdo de jugar a la par.
    expect('(igualdad)'.allMatches(texto).length, 2);
    // Y el −1 del cruce editado.
    expect(texto, contains('CAM da 1 golpes a KAWA'));
    // Lo que se veía: cuatro golpes que nadie pactó.
    expect(texto, isNot(contains('4 golpes')));
    expect(texto, isNot(contains('Calculado por HCP automático')),
        reason: 'los tres cruces tienen acuerdo, incluidos los de cero');
  });

  testWidgets('CONTRAPESO: sin acuerdo sí se calcula por HCP, y lo dice',
      (tester) async {
    // Sin esto, «no digas nunca calculado» pasaría la prueba de arriba.
    // Sin sliding elegido, lo del paso 8 no entra —es la regla de
    // `slidingDeRonda`— así que no hay acuerdo y manda el handicap.
    final texto = await _montarPaso9(tester,
        ventaja: SistemaDeVentaja.handicap, editado: _editadoEnElPaso8);
    expect(texto, contains('Calculado por HCP automático'));
    expect(texto, contains('4 golpes'), reason: 'HCP 6 vs 10');
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 3 · LA VENTAJA ERA LO ÚNICO CONFIGURADO EN DOS SITIOS
//
// El paso de Ventaja lista TODOS los cruces, también con equipos. Y la hoja
// del duelo —«¿alguien pactó algo aparte?»— tiene su propia ventaja. Las dos
// acaban en `slidingDeRonda`, donde `duelosConVentajaPropia` va la última y
// por tanto GANA: se podía teclear un número en el paso 8 y jugar otro.
//
// La precedencia vive en UN sitio y la pantalla la LEE con `ventajaDelCruce`,
// en vez de reproducirla.
// ─────────────────────────────────────────────────────────────────────────────
void _dosSitios() {
  Map<String, double> mapa({required double tecleado, double? delDuelo}) =>
      slidingDeRonda(
        ventaja: SistemaDeVentaja.sliding,
        acumuladoDelGrupo: const {},
        participantIds: _tres,
        editadoEnElPaso: (_, __) => tecleado,
        duelosConVentajaPropia: [
          if (delDuelo != null) (a: _cam, b: _jose, delta: delDuelo),
        ],
      );

  test('CLAVE (criterio 4): lo pactado en el duelo es lo que se lee', () {
    // Tecleado −1 en el paso 8, pactado −3 en el duelo de CAM y Jose.
    final m = mapa(tecleado: -1, delDuelo: -3);
    expect(ventajaDelCruce(_cam, _jose, m), -3,
        reason: 'el duelo manda al construir la ronda, así que también al leer');
    // Y los otros cruces siguen con lo tecleado.
    expect(ventajaDelCruce(_cam, _kawa, m), -1);
  });

  test('CLAVE: y se lee igual desde los dos lados del cruce', () {
    final m = mapa(tecleado: 0, delDuelo: -3);
    expect(ventajaDelCruce(_cam, _jose, m), -3);
    expect(ventajaDelCruce(_jose, _cam, m), 3,
        reason: 'golpes que recibe el primero del segundo');
  });

  test('CONTRAPESO: sin duelo pactado manda lo tecleado', () {
    // Sin esto, «devuelve siempre lo del duelo» pasaría la prueba de arriba.
    expect(ventajaDelCruce(_cam, _jose, mapa(tecleado: -1)), -1);
  });

  test('CONTRAPESO: el duelo pactado AL REVÉS guarda el signo correcto', () {
    // Los ids de este fichero van en orden —cam < jose— así que un duelo
    // (cam, jose) no ejercita la inversión de signo, y un contrapeso que la
    // quitaba pasó en verde. Declarado al revés sí: «Jose recibe −3 de CAM» es
    // «CAM recibe +3 de Jose», y el mapa guarda lo que recibe el id menor.
    final m = slidingDeRonda(
      ventaja: SistemaDeVentaja.sliding,
      acumuladoDelGrupo: const {},
      participantIds: _tres,
      editadoEnElPaso: (_, __) => 0,
      duelosConVentajaPropia: const [(a: _jose, b: _cam, delta: -3.0)],
    );
    expect(ventajaDelCruce(_cam, _jose, m), 3);
    expect(ventajaDelCruce(_jose, _cam, m), -3);
  });

  test('CONTRAPESO: un cruce sin acuerdo devuelve null, no cero', () {
    // Cero es un acuerdo —jugar a la par—; la ausencia es otra cosa, y es lo
    // que deja mandar a la diferencia de handicaps.
    expect(ventajaDelCruce(_cam, _jose, const {}), isNull);
    expect(ventajaDelCruce(_cam, _jose, mapa(tecleado: 0)), 0);
  });
}
