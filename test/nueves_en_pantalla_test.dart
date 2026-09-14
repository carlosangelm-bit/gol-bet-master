// ─────────────────────────────────────────────────────────────────────────────
// LOS NUEVES, EN LA PANTALLA QUE EXPLICA EL ÍNDICE
//
// El motor ya emparejaba dos nueves en un diferencial de dieciocho —hay
// diecisiete pruebas de ello— y la pantalla de Ajustes seguía marcándolos como
// que NO cuentan. Comparaba ids, y un diferencial combinado lleva el id de las
// DOS rondas: `r1+r2` no es igual a `r1` ni a `r2`.
//
// El efecto en pantalla era el peor posible para este punto: quien sumara a
// mano vería ocho checks sobre los diferenciales equivocados, con un índice
// correcto. Un índice mal explicado se nota tan poco como uno mal calculado.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/providers/handicap_provider.dart';
import 'package:golf_bet_master/providers/perfil_provider.dart';
import 'package:golf_bet_master/providers/torneo_provider.dart';
import 'package:golf_bet_master/providers/user_profile_provider.dart';
import 'package:golf_bet_master/screens/settings/settings_screen.dart';
import 'package:golf_bet_master/services/handicap_service.dart';
import 'package:provider/provider.dart';

ScoreDifferential _d(String id, String nombre, int dia, double diff,
        {int hoyos = 18}) =>
    ScoreDifferential(
      roundId: id,
      roundName: nombre,
      playedAt: DateTime(2026, 7, dia),
      differential: diff,
      grossScore: hoyos == 9 ? 47 : 90,
      adjustedGrossScore: hoyos == 9 ? 47 : 90,
      courseRating: hoyos == 9 ? 35.9 : 71.7,
      slopeRating: 149,
      parTotal: hoyos == 9 ? 36 : 72,
      holesPlayed: hoyos,
      courseName: 'Los Encinos',
    );

/// Las dos mañanas de nueve del reporte de Carlos, más una de dieciocho.
final _manana = _d('r-a', '28 Jul · mañana', 28, 8.5, hoyos: 9);
final _tarde = _d('r-b', '29 Jul · tarde', 29, 8.5, hoyos: 9);
final _entera = _d('r-c', '30 Jul', 30, 12.0);

Future<String> _montar(WidgetTester tester) async {
  // La hoja es un DraggableScrollableSheet: con la ventana por defecto la
  // tercera fila se queda fuera y el texto no la lleva. Alto suficiente para
  // que las tres se pinten, que es justo lo que hay que leer.
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final combinado = HandicapService.combinarNueves(_manana, _tarde);
  final hp = HandicapProvider()
    ..sembrar(
      HandicapIndexResult(
        index: 10.0,
        totalRounds: 3,
        // El índice usa el COMBINADO: ningún id de la lista coincide con él.
        usedDifferentials: [combinado],
        allDifferentials: [_manana, _tarde, _entera],
      ),
    );
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<HandicapProvider>.value(value: hp),
      ChangeNotifierProvider<PerfilProvider>(
          create: (_) => PerfilProvider()..sembrar(const [])),
      ChangeNotifierProvider<TorneoProvider>(
          create: (_) => TorneoProvider()..sembrar(const [])),
      ChangeNotifierProvider<UserProfileProvider>(
          create: (_) => UserProfileProvider()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: HandicapTrackerSheet(t: GolfTheme.dark),
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
  testWidgets('CLAVE: los dos nueves que el índice usa salen como que cuentan',
      (tester) async {
    final texto = await _montar(tester);

    // El motivo por el que NO contaría es lo que se enseñaba antes. Si sigue
    // ahí, es que el check volvió a fallar.
    expect(texto, isNot(contains('No está entre')),
        reason: 'los dos nueves SÍ están entre los que el índice usa');

    // Y se dice con quién cuenta cada uno, por NOMBRE: un check sobre un 8.5
    // mientras el índice usa 17.0 son dos cifras sin relación visible.
    // En la FILA, con la suma hecha: «8.5 + el otro = 17.0» es lo que enlaza
    // el check de abajo con el 17.0 de arriba.
    expect(texto, contains('+ «29 Jul · tarde» = 17.0'));
    expect(texto, contains('+ «28 Jul · mañana» = 17.0'));
  });

  testWidgets('CONTRAPESO: y el de dieciocho que NO cuenta sigue diciéndolo',
      (tester) async {
    final texto = await _montar(tester);
    // Sin esto, "todo cuenta" pasaría la prueba de arriba.
    expect(texto, contains('30 Jul'));
    expect(texto, isNot(contains('+ «30 Jul»')));
  });
}
