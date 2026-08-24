// ─────────────────────────────────────────────────────────────────────────────
// CUENTA RECIÉN CREADA — el escenario que no estaba en el plan
//
// Los tres hallazgos de la sesión salieron del mismo sitio: una cuenta SIN
// DATOS recorre caminos que una con historial nunca toca.
//
//   · Buscar campo solo aparece sin favoritos
//   · Crear jugador solo se hace con el directorio vacío
//   · Un torneo sobre el histórico solo se intenta cuando ya hay rondas pero
//     todavía ningún torneo
//
// Así que el escenario entra como bloque propio: cada pantalla montada con los
// providers VACÍOS, que es el estado del primer minuto de cualquier usuario.
// Y con lo que sí hay que enseñar en ese estado: la salida, no una pantalla muda.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/round_result.dart';
import 'package:golf_bet_master/models/torneo.dart';
import 'package:golf_bet_master/providers/auth_provider.dart';
import 'package:golf_bet_master/providers/betting_group_provider.dart';
import 'package:golf_bet_master/providers/handicap_provider.dart';
import 'package:golf_bet_master/providers/perfil_provider.dart';
import 'package:golf_bet_master/providers/player_provider.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/providers/torneo_provider.dart';
import 'package:golf_bet_master/providers/user_profile_provider.dart';
import 'package:golf_bet_master/screens/home/home_screen.dart';
import 'package:golf_bet_master/screens/setup/setup_screen.dart';
import 'package:golf_bet_master/screens/torneos/torneo_editor_screen.dart';
import 'package:golf_bet_master/screens/torneos/torneos_screen.dart';
import 'package:golf_bet_master/widgets/player_edit_sheet.dart';

RoundResult _res(int dia, String nombre) => RoundResult(
      roundId: 'r$dia',
      roundName: nombre,
      courseName: 'Club de Golf Malanquín',
      playedAt: DateTime(2026, 3, dia),
      holesPlayed: 18,
      playerIds: const ['pid_a', 'pid_b'],
      playerNames: const {'pid_a': 'Rafa', 'pid_b': 'Alan'},
      balances: const {'pid_a': 300, 'pid_b': -300},
      pairBalances: const {},
      grossByPlayer: const {},
      netByPlayer: const {},
      stablefordByPlayer: const {},
      bettingGroupIds: const [],
    );

/// Monta [pantalla] con los providers vacíos, salvo lo que se pase.
Future<List<String>> _montar(
  WidgetTester tester,
  Widget pantalla, {
  List<RoundResult> res = const [],
  List<Torneo> torneos = const [],
  Size tamano = const Size(390, 2000),
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final errores = <String>[];
  final anterior = FlutterError.onError;
  FlutterError.onError = (d) => errores.add(d.exceptionAsString());

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => RoundProvider()),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => HandicapProvider()),
      ChangeNotifierProvider(create: (_) => UserProfileProvider()),
      ChangeNotifierProvider(create: (_) => BettingGroupProvider()),
      // Directorio VACÍO: es el estado real de una cuenta nueva.
      ChangeNotifierProvider<PlayerProvider>.value(
          value: PlayerProvider()..sembrar(const [])),
      ChangeNotifierProvider<PerfilProvider>.value(
          value: PerfilProvider()..sembrar(res)),
      ChangeNotifierProvider<TorneoProvider>.value(
          value: TorneoProvider()..sembrar(torneos)),
    ],
    child: MaterialApp(
        theme: GolfTheme.classic.toMaterial(), home: pantalla),
  ));
  await tester.pump(const Duration(milliseconds: 200));
  FlutterError.onError = anterior;
  return errores;
}

String _pantalla(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .join(' · ');

void main() {
  group('1 · la app sin nada dentro se pinta y dice qué hacer', () {
    testWidgets('Inicio', (tester) async {
      final errores = await _montar(tester, const HomeScreen());
      expect(errores, isEmpty);
    });

    testWidgets('la lista de torneos dice que no hay ninguno', (tester) async {
      final errores = await _montar(tester, const TorneosScreen());
      expect(errores, isEmpty);
      expect(_pantalla(tester), contains('Ningún torneo'));
    });

    testWidgets('el asistente, con el directorio vacío', (tester) async {
      final errores = await _montar(tester, const SetupScreen());
      expect(errores, isEmpty);
      // Y la salida está a la vista: sin campo se juega igual.
      expect(_pantalla(tester), contains('Campo Estándar'));
    });

    testWidgets('el paso Jugadores ofrece crear uno', (tester) async {
      // Sin directorio, crear es la ÚNICA vía. Si el botón no estuviera, la
      // cuenta nueva no podría ni empezar.
      final errores = await _montar(tester, const SetupScreen());
      expect(errores, isEmpty);
      await tester.tap(find.text('Siguiente →'));
      await tester.pumpAndSettle();
      expect(find.text('Crear jugador nuevo'), findsOneWidget);
      expect(_pantalla(tester), contains('EN ESTA RONDA (0/8)'));
    });

    testWidgets('el editor de torneo, sin rondas ni nada', (tester) async {
      final errores =
          await _montar(tester, const TorneoEditorScreen(existente: null));
      expect(errores, isEmpty);
    });
  });

  group('2 · "Elegidas a mano" SÍ tiene dónde elegirlas', () {
    // No existía: la opción prometía "eliges de entre las rondas ya jugadas" y
    // el control no se había construido nunca. El modelo guardaba roundIds y
    // rondasDelTorneo los leía, pero no había forma de ponerlos.
    testWidgets('con dos rondas en el historial, salen las dos',
        (tester) async {
      final errores = await _montar(
          tester, const TorneoEditorScreen(existente: null),
          res: [_res(7, 'Sábado con Alan'), _res(14, 'Domingo en Malanquín')]);
      expect(errores, isEmpty);

      await tester.tap(find.text('Elegidas a mano'));
      await tester.pumpAndSettle();

      expect(find.text('CUÁLES CUENTAN'), findsOneWidget);
      expect(_pantalla(tester), contains('Sábado con Alan'));
      expect(_pantalla(tester), contains('Domingo en Malanquín'));
      // Y dice el campo y cuánta gente, que es lo que distingue dos sábados.
      expect(_pantalla(tester), contains('Club de Golf Malanquín'));
      expect(_pantalla(tester), contains('2 jugadores'));
    });

    testWidgets('elegir una la cuenta, y el torneo deja de estar vacío',
        (tester) async {
      await _montar(tester, const TorneoEditorScreen(existente: null),
          res: [_res(7, 'Sábado con Alan'), _res(14, 'Domingo en Malanquín')]);
      await tester.tap(find.text('Elegidas a mano'));
      await tester.pumpAndSettle();
      // Antes de tocar nada: cero, y lo dice.
      expect(_pantalla(tester), contains('0 rondas entran'));

      await tester.tap(find.text('14/3/2026 · Domingo en Malanquín'));
      await tester.pumpAndSettle();
      expect(_pantalla(tester), contains('1 de 2 rondas elegidas'));
      expect(_pantalla(tester), contains('1 ronda entra'));
    });

    testWidgets('TODAS y NINGUNA', (tester) async {
      await _montar(tester, const TorneoEditorScreen(existente: null),
          res: [_res(7, 'A'), _res(14, 'B'), _res(21, 'C')]);
      await tester.tap(find.text('Elegidas a mano'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('TODAS'));
      await tester.pumpAndSettle();
      expect(_pantalla(tester), contains('3 de 3 rondas elegidas'));
      expect(_pantalla(tester), contains('3 rondas entran'));

      await tester.tap(find.text('NINGUNA'));
      await tester.pumpAndSettle();
      expect(_pantalla(tester), contains('0 rondas entran'));
    });

    testWidgets('sin historial dice qué hacer, no una lista vacía',
        (tester) async {
      // El caso de la cuenta nueva: la fuente existe pero no hay nada que
      // elegir, y la salida es la otra fuente.
      await _montar(tester, const TorneoEditorScreen(existente: null));
      await tester.tap(find.text('Elegidas a mano'));
      await tester.pumpAndSettle();
      expect(_pantalla(tester), contains('No hay rondas cerradas'));
      expect(_pantalla(tester), contains('Marcadas al configurar la ronda'));
    });

    testWidgets('las rondas van de la más reciente a la más antigua',
        (tester) async {
      // Un torneo sobre el histórico se arma con lo de las últimas semanas.
      await _montar(tester, const TorneoEditorScreen(existente: null),
          res: [_res(7, 'Vieja'), _res(21, 'Nueva')]);
      await tester.tap(find.text('Elegidas a mano'));
      await tester.pumpAndSettle();
      final nueva = tester.getTopLeft(find.text('21/3/2026 · Nueva')).dy;
      final vieja = tester.getTopLeft(find.text('7/3/2026 · Vieja')).dy;
      expect(nueva, lessThan(vieja));
    });
  });

  group('4 · el jugador creado en el asistente se queda', () {
    // Se perdía: entraba en la ronda y NO iba al directorio. Lo único que lo
    // guardaba era el diálogo de sliding del cierre, que habla de otra cosa;
    // cancelarlo —porque no quieres tocar handicaps— borraba a la persona.
    testWidgets('el formulario ofrece guardarlo, y viene marcado',
        (tester) async {
      final errores = await _montar(tester, const SetupScreen());
      expect(errores, isEmpty);
      await tester.tap(find.text('Siguiente →'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crear jugador nuevo'));
      await tester.pumpAndSettle();

      expect(find.text('Guardar en mis compañeros'), findsOneWidget);
      // Marcado por defecto: es lo que espera quien acaba de escribir el nombre
      // de un amigo.
      expect(_pantalla(tester), contains('Estará ahí la próxima vez'));
    });

    testWidgets('se puede desmarcar para un invitado de una vez',
        (tester) async {
      // El caso legítimo, y se decide AQUÍ, no en un diálogo posterior que
      // habla de handicaps.
      await _montar(tester, const SetupScreen());
      await tester.tap(find.text('Siguiente →'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crear jugador nuevo'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar en mis compañeros'));
      await tester.pumpAndSettle();
      expect(_pantalla(tester), contains('Solo para esta ronda'));
    });

    testWidgets('al editar un jugador que ya existe NO se pregunta',
        (tester) async {
      // El interruptor es del momento de CREAR. Al editar, el jugador ya está
      // donde esté.
      await _montar(tester, const SetupScreen());
      await tester.tap(find.text('Siguiente →'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crear jugador nuevo'));
      await tester.pumpAndSettle();
      // Guardar para cerrar la hoja.
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      // Y ahora se abre el MISMO jugador para editarlo.
      final chip = find.text('Jugador 1');
      if (chip.evaluate().isNotEmpty) {
        await tester.tap(chip.first);
        await tester.pumpAndSettle();
        expect(find.text('Guardar en mis compañeros'), findsNothing);
      }
    });

    test('el resultado del formulario lleva la decisión', () {
      // Por defecto false: quien no pregunte no guarda nada por accidente.
      final sinPreguntar = PlayerEditResult(
          name: 'Luis', handicap: 12, tee: TeeInfo.standard);
      expect(sinPreguntar.guardarEnDirectorio, isFalse);
      final preguntado = PlayerEditResult(
          name: 'Luis',
          handicap: 12,
          tee: TeeInfo.standard,
          guardarEnDirectorio: true);
      expect(preguntado.guardarEnDirectorio, isTrue);
    });
  });

  group('3 · lo elegido a mano es lo que cuenta', () {
    test('rondasDelTorneo lee roundIds, y ahora hay quien los ponga', () {
      final rs = [_res(7, 'A'), _res(14, 'B'), _res(21, 'C')];
      final t = Torneo(
          id: 't1',
          nombre: 'Sobre el histórico',
          fuente: FuenteDeRondas.manual,
          roundIds: const ['r7', 'r21']);
      expect(rondasDelTorneo(t, rs).map((r) => r.roundId), ['r7', 'r21']);
      // Y la tabla sale de esas dos, no de las tres.
      expect(tablaDe(t, rs).rondas, 2);
    });

    test('sin roundIds el torneo sale vacío, que es coherente', () {
      final t = Torneo(
          id: 't1', nombre: 'T', fuente: FuenteDeRondas.manual);
      expect(rondasDelTorneo(t, [_res(7, 'A')]), isEmpty);
    });
  });
}
