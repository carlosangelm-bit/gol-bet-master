// ─────────────────────────────────────────────────────────────────────────────
// EL TABLERO DE INICIO EN PANTALLA
//
// El resumen se prueba puro en perfil_resumen_test. Esto prueba lo que aquello
// no puede: que la pantalla enseñe el estado que toca, y que quepa.
//
// Los dos que importan:
//
//   · Sin identidad NO aparece un "$0". Es la diferencia entre una pantalla que
//     dice "falta decir quién eres" y una que afirma que vas en tablas. La
//     lógica ya distingue los dos casos; esto comprueba que la pantalla no los
//     vuelve a juntar al pintarlos.
//   · La fila de contadores no se desborda. Son cuatro cifras con separadores
//     en un Row sin Expanded: a 320 px con números de tres dígitos es
//     exactamente la clase de fallo que solo se ve usando la app.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/models/round_result.dart';
import 'package:golf_bet_master/providers/handicap_provider.dart';
import 'package:golf_bet_master/providers/perfil_provider.dart';
import 'package:golf_bet_master/providers/user_profile_provider.dart';
import 'package:golf_bet_master/screens/home/tablero_inicio.dart';
import 'package:golf_bet_master/services/user_profile_service.dart';

const yo = 'yo', otro = 'otro';

RoundResult _r(int dia, double neto, {int? gross}) => RoundResult(
      roundId: 'r$dia',
      roundName: 'Ronda $dia',
      courseName: 'Los Encinos',
      playedAt: DateTime(2026, 8, dia),
      holesPlayed: 18,
      playerIds: const [yo, otro],
      playerNames: const {yo: 'Yo', otro: 'Beto'},
      balances: {yo: neto, otro: -neto},
      pairBalances: {'otro|yo': -neto},
      grossByPlayer: gross == null ? const {} : {yo: gross},
    );

/// Monta el histórico con los resultados dados y devuelve los errores de layout.
Future<List<String>> _montar(
  WidgetTester tester, {
  required List<RoundResult> resultados,
  required String? identidad,
  Size tamano = const Size(390, 844),
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  UserProfileService.identidadDePrueba(identidad);
  addTearDown(() => UserProfileService.olvidaIdentidad());

  final errores = <String>[];
  final anterior = FlutterError.onError;
  FlutterError.onError = (d) => errores.add(d.exceptionAsString());

  final perfil = PerfilProvider()..sembrar(resultados);

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<PerfilProvider>.value(value: perfil),
      ChangeNotifierProvider(create: (_) => HandicapProvider()),
      ChangeNotifierProvider(create: (_) => UserProfileProvider()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: HistoricoInicio(t: GolfTheme.classic),
          ),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  FlutterError.onError = anterior;
  return errores;
}

void main() {
  group('1 · sin identidad la pantalla PREGUNTA, no afirma cero', () {
    testWidgets('sale el aviso y no sale ninguna cifra', (tester) async {
      // Hay resultados en la colección; lo que falta es saber cuál eres tú.
      // Sumarlos y enseñarlos sería enseñar el balance de otra persona.
      // Un solo resultado, para que el total no coincida por casualidad con
      // ninguna otra cifra de la pantalla.
      await _montar(tester, resultados: [_r(1, 100)], identidad: null);

      expect(find.textContaining('Falta decir quién eres'), findsOneWidget);
      expect(find.text('\$0'), findsNothing,
          reason: 'un cero aquí afirma que vas en tablas');
      expect(find.text('+\$100'), findsNothing,
          reason: 'y esto sería el balance de otro');
      expect(find.textContaining('BALANCE HISTÓRICO'), findsNothing);
    });

    testWidgets('y con identidad SÍ sale la cifra', (tester) async {
      // El contrapeso: sin este, el aviso podría estar saliendo siempre y el
      // test de arriba pasaría igual.
      await _montar(tester, resultados: [_r(1, 100)], identidad: yo);

      expect(find.textContaining('BALANCE HISTÓRICO'), findsOneWidget);
      expect(find.text('+\$100'), findsWidgets);
      expect(find.textContaining('Falta decir quién eres'), findsNothing);
    });
  });

  group('2 · el estado vacío no miente', () {
    testWidgets('identificado y sin resultados: no promete un histórico',
        (tester) async {
      // HandicapProvider arranca en cero rondas, así que este es el caso de
      // "de verdad no has jugado".
      await _montar(tester, resultados: const [], identidad: yo);
      expect(find.textContaining('Aún no has cerrado una ronda'), findsOneWidget);
      expect(find.text('\$0'), findsNothing);
    });
  });

  group('3 · lo que se enseña de cada ronda', () {
    testWidgets('el rival, con el signo de tu lado', (tester) async {
      // 'otro' < 'yo', así que el par guarda la vista de 'otro'. Si el signo se
      // leyera mal, aquí diría que Beto te gana.
      await _montar(tester, resultados: [_r(1, 100)], identidad: yo);
      expect(find.text('Beto'), findsOneWidget);
      expect(find.text('le ganas'), findsOneWidget);
    });

    testWidgets('un score ausente se dibuja como raya, no como cero',
        (tester) async {
      await _montar(tester, resultados: [_r(1, 100)], identidad: yo);
      expect(find.text('–'), findsOneWidget);
      // Mirar toda la pantalla no vale: el contador de "perdidas" es un 0
      // legítimo. La aserción es sobre la COLUMNA del score, que es la que
      // leería un 0 como "hizo 0 golpes".
      final raya = tester.getRect(find.text('–'));
      final ceros = find.text('0').evaluate().map((e) => tester.getRect(find.byWidget(e.widget)));
      for (final c in ceros) {
        expect((c.center.dx - raya.center.dx).abs() > 4, isTrue,
            reason: 'un 0 en la columna del score se lee como "hizo 0"');
      }
    });

    testWidgets('y presente se dibuja tal cual', (tester) async {
      await _montar(tester,
          resultados: [_r(1, 100, gross: 82)], identidad: yo);
      expect(find.text('82'), findsOneWidget);
    });
  });

  group('4 · cabe', () {
    testWidgets('a 390 px con cuatro contadores y cifras de tres dígitos',
        (tester) async {
      final errores = await _montar(tester,
          resultados: [
            for (var i = 1; i <= 12; i++) _r(i, i.isEven ? 150 : -120, gross: 88),
            _r(20, 0, gross: 90), // unas tablas, para que salga el 4º contador
          ],
          identidad: yo);
      expect(errores.where((e) => e.contains('overflowed')), isEmpty,
          reason: errores.join('\n'));
    });

    testWidgets('y a 320 px, que es el teléfono más estrecho que existe',
        (tester) async {
      // El caso que de verdad aprieta: cuatro _Dato con tres _Sep en un Row
      // sin Expanded. Si esto pasa a 390 pero no a 320, el fallo aparecería
      // solo en el teléfono de alguien.
      final errores = await _montar(tester,
          resultados: [
            for (var i = 1; i <= 12; i++) _r(i, i.isEven ? 150 : -120, gross: 88),
            _r(20, 0, gross: 90),
          ],
          identidad: yo,
          tamano: const Size(320, 700));
      expect(errores.where((e) => e.contains('overflowed')), isEmpty,
          reason: errores.join('\n'));
    });
  });
}
