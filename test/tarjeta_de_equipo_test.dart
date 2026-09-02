// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';
// LA TARJETA DE UN EQUIPO TIENE UNA FILA
//
// «Cuatro filas, una por jugador. Y debería haber una sola.»
//
// ── Por qué ninguna prueba lo cazó ──────────────────────────────────────────
//
// El mecanismo estaba y estaba probado: `scoringPlayers` respeta el `equipoId`
// que la ronda declara, y hay un test que lo fija. La captura del jugador ya lo
// usaba en sus seis sitios.
//
// Lo que no había era una prueba de LA HOJA. El camino real para abrirla pasa
// por Firestore —`cargarRondaEnVivo`— así que ningún test de widget llegaba, y
// el único trozo sin cubrir es justo donde vivía el fallo.
//
// Por eso la hoja dejó de ser privada. Montarla con una ronda cualquiera es
// barato, y es lo que convierte "el mecanismo funciona" en "la pantalla lo usa".
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/models/correccion_de_score.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/shotgun.dart';
import 'package:golf_bet_master/screens/organizador/scores_seccion.dart';

const _cuatro = ['ana', 'beto', 'caro', 'dani'];
const _nombres = {
  'ana': 'Luis Herrera',
  'beto': 'Mauricio Figueroa',
  'caro': 'Guillermo Fuentes',
  'dani': 'Maximiliano Bustamante',
};

CourseInfo _campo() => CourseInfo(
      name: 'Los Encinos',
      holes: List.generate(
          18,
          (i) => CourseHole(
              hole: i + 1,
              par: const {3, 7, 12, 16}.contains(i + 1) ? 3 : 4,
              strokeIndex: i + 1)),
    );

/// Una ronda del shotgun, con equipos o sin ellos. Sale del MISMO camino que
/// usa el portal: `planDeShotgun` → `equiposDelPlan` → `rondasDelPlan`.
Round _ronda({required bool porEquipos}) {
  final plan =
      planDeShotgun(padron: _cuatro, campo: _campo(), tamano: 4);
  return rondasDelPlan(
    plan: plan,
    torneoId: 't1',
    campo: _campo(),
    porId: {
      for (final e in _nombres.entries) e.key: Player(id: e.key, name: e.value),
    },
    cuando: DateTime(2026, 9, 1),
    equipos: porEquipos
        ? equiposDelPlan(plan, nombresPuestos: {1: 'Sierra'})
        : const [],
  ).single;
}

Future<void> _montar(WidgetTester tester, Round r) async {
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: HojaDeTarjeta(ronda: r, t: GolfTheme.classic)),
  ));
  await tester.pump(const Duration(milliseconds: 200));
}

String _texto(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .join(' · ');

void main() {
  group('1 · con equipos, UNA fila', () {
    testWidgets('CLAVE: la tarjeta enseña el equipo y no a los cuatro',
        (tester) async {
      await _montar(tester, _ronda(porEquipos: true));
      final txt = _texto(tester);

      // La fila es la del equipo.
      expect(txt, contains('Equipo 01 · Sierra'));
      // Y NO hay una por miembro: es exactamente lo que el modo equipos viene
      // a evitar —cuatro personas anotando cuatro scores de una bola—.
      for (final n in _nombres.values) {
        expect(find.text(n), findsNothing, reason: n);
      }
    });

    testWidgets('CLAVE: y la promesa del interruptor se cumple',
        (tester) async {
      // «Los cuatro comparten una tarjeta». Una fila de score, dieciocho
      // casillas.
      final r = _ronda(porEquipos: true);
      expect(r.scoringPlayers.length, 1);
      expect(r.scoringPlayers.single.id, 'e01');
      await _montar(tester, r);
      // Las casillas vacías se pintan con un punto, no con un cero: «todavía
      // no» y «cero golpes» no son lo mismo.
      final puntos = tester
          .widgetList<Text>(find.byType(Text))
          .where((w) => w.data == '·')
          .length;
      expect(puntos, 18, reason: 'una fila × 18 hoyos, no cuatro × 18');
    });
  });

  group('2 · sin equipos, una fila por persona — como siempre', () {
    testWidgets('CLAVE: los cuatro con su tarjeta', (tester) async {
      // El criterio que protege lo construido: en una ronda individual esto no
      // puede haber cambiado.
      final r = _ronda(porEquipos: false);
      expect(r.equipoId, isNull);
      await _montar(tester, r);
      for (final n in _nombres.values) {
        expect(find.text(n), findsOneWidget, reason: n);
      }
      final puntos = tester
          .widgetList<Text>(find.byType(Text))
          .where((w) => w.data == '·')
          .length;
      expect(puntos, 72, reason: 'cuatro filas × 18 hoyos');
    });
  });

  group('3 · la corrección va al equipo, no a una persona', () {
    test('CLAVE: el rastro nombra al EQUIPO', () {
      // Si la corrección se anotara contra un miembro, el registro diría que
      // alguien cambió el score de Luis cuando lo que se cambió es el del
      // equipo. Y el score corregido caería en una clave que no clasifica.
      final r = _ronda(porEquipos: true);
      final corregida = conCorreccion(
        r,
        jugadorId: r.scoringPlayers.single.id,
        hoyo: 7,
        nuevo: 4,
        porUid: 'org',
        porNombre: 'Carlos',
        cuando: DateTime(2026, 9, 1, 11),
      );
      expect(corregida.correcciones.single.jugadorNombre,
          'Equipo 01 · Sierra');
      expect(corregida.scores['e01']![7]!.grossScore, 4);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 4 · LA CAPTURA DEL JUGADOR
  //
  // «Determina si afecta también a la captura del jugador. Si los cuatro abren
  // la app y ven cuatro filas, cada uno anotaría la suya.»
  //
  // No afecta: la captura ya usaba `scoringPlayers` en sus seis sitios, así que
  // los cuatro ven UNA fila. Pero decirlo no basta —era exactamente lo que se
  // podía decir de la hoja del portal hasta ayer— así que va probado.
  // ───────────────────────────────────────────────────────────────────────────
  group('4 · la captura del jugador ya lo respeta, y sigue así', () {
    test('CLAVE: los cuatro miembros ven UNA fila, la del equipo', () {
      // Es la misma lista que la captura usa para pintar sus filas. Si esto
      // devolviera cuatro, los cuatro anotarían su propio score de una bola.
      final r = _ronda(porEquipos: true);
      expect(r.scoringPlayers.map((p) => p.id), ['e01']);
      // Y los cuatro SIGUEN en la ronda: son quienes pueden entrar a editar.
      expect(r.realPlayers.length, 4);
      expect(r.players.length, 5, reason: 'los cuatro más el equipo');
    });

    test('CLAVE: y la pantalla de captura no reimplementa la lista', () {
      // La regresión que puede pasar: alguien "arregla" la captura poniendo
      // realPlayers para ver nombres de personas, y los cuatro vuelven a
      // anotar por separado.
      final codigo =
          File('lib/screens/capture/capture_screen.dart').readAsStringSync();
      expect(codigo, contains('round.scoringPlayers.asMap()'),
          reason: 'las filas de la tabla salen de quién lleva tarjeta');
      // El único `realPlayers` legítimo aquí es el ranking de oyes: un equipo
      // no pega un tiro de aproximación.
      final vivas = codigo
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .where((l) => l.contains('realPlayers'))
          .toList();
      expect(vivas.length, 1, reason: 'solo el ranking de oyes');
      expect(vivas.single, contains('unranked'));
    });
  });

  group('5 · y la superficie usa el mecanismo, no lo reimplementa', () {
    test('CLAVE: la hoja NO lee realPlayers para sus filas', () {
      // El fallo era una línea: `realPlayers` donde tocaba `scoringPlayers`.
      // El mecanismo estaba probado; lo que faltaba era que la pantalla lo
      // usara. Esto lo fija sin depender de montar nada.
      final codigo = File('lib/screens/organizador/scores_seccion.dart')
          .readAsStringSync();
      final vivas = codigo
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .where((l) => l.contains('realPlayers'))
          .toList();
      expect(vivas, isEmpty,
          reason: 'quién ANOTA no es quién juega: usa scoringPlayers');
    });
  });
}
