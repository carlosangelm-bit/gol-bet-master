// ─────────────────────────────────────────────────────────────────────────────
// ANOTAR DE CORRIDO — como rellenar una tarjeta de papel
//
// El organizador con 68 personas no consigue que las 68 instalen la app: anota
// él, con las tarjetas de papel que le entregan. Antes eran 306 aperturas de
// diálogo (18 hoyos × 17 equipos). Ahora se abre la fila y se teclea de corrido:
// el foco pasa al hoyo siguiente solo y PARA al 18 (no salta a otro jugador).
//
// Lo que fija esta prueba (los criterios del encargo):
//   1 · se teclean los 18 hoyos y el foco avanza solo, sin tocar el ratón;
//   2 · los números de dos cifras (10–20) se pueden escribir;
//   3 · al acabar la fila el foco no salta a otro jugador;
//   4 · el registro distingue RELLENAR ("se anotó 6") de CORREGIR ("6 → 4").
// El criterio 5 (que se sienta como papel) es de pantalla, con dedos.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/models/correccion_de_score.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/shotgun.dart';
import 'package:golf_bet_master/screens/organizador/scores_seccion.dart';

const _cuatro = ['ana', 'beto', 'caro', 'dani'];

CourseInfo _campo() => CourseInfo(
      name: 'Los Encinos',
      holes: List.generate(
          18, (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)),
    );

/// Una ronda POR EQUIPOS: una sola fila (el equipo), 18 hoyos — la tarjeta que
/// el organizador rellena. Mismo camino que el portal.
Round _rondaEquipo() {
  final plan = planDeShotgun(padron: _cuatro, campo: _campo(), tamano: 4);
  return rondasDelPlan(
    plan: plan,
    torneoId: 't1',
    campo: _campo(),
    porId: {for (final id in _cuatro) id: Player(id: id, name: id)},
    cuando: DateTime(2026, 9, 1),
    equipos: equiposDelPlan(plan, nombresPuestos: {1: 'Sierra'}),
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

bool _enfocado(WidgetTester tester, Finder campos, int i) =>
    tester.widget<TextField>(campos.at(i)).focusNode!.hasFocus;

String _texto(WidgetTester tester, Finder campos, int i) =>
    tester.widget<TextField>(campos.at(i)).controller!.text;

// La fila del equipo tiene una casilla editable por hoyo (18).
Finder _casillas() => find.descendant(
    of: find.byType(HojaDeTarjeta), matching: find.byType(TextField));

void main() {
  group('1 · se teclea la fila de corrido y el foco avanza solo', () {
    testWidgets('CLAVE: cada hoyo pasa el foco al siguiente; para en 18',
        (tester) async {
      await _montar(tester, _rondaEquipo());
      final campos = _casillas();
      expect(campos, findsNWidgets(18), reason: 'una fila × 18 hoyos');

      for (var i = 0; i < 18; i++) {
        await tester.enterText(campos.at(i), '4');
        await tester.pump();
        if (i < 17) {
          expect(_enfocado(tester, campos, i + 1), isTrue,
              reason: 'tras el hoyo ${i + 1} el foco va al ${i + 2}, solo');
        }
      }
      // Criterio 3: al 18 no hay hoyo siguiente y NO salta a otro jugador
      // (aquí solo hay una fila) — el foco se suelta.
      expect(_enfocado(tester, campos, 17), isFalse,
          reason: 'la fila terminó; el foco no se va a ningún lado');

      await tester.pump(const Duration(milliseconds: 800)); // debounce guardado
      await tester.pump();
    });
  });

  group('2 · los números de dos cifras se pueden escribir', () {
    testWidgets('CLAVE: un 12 entero queda como 12 y avanza', (tester) async {
      await _montar(tester, _rondaEquipo());
      final campos = _casillas();
      await tester.enterText(campos.at(0), '12');
      await tester.pump();
      expect(_texto(tester, campos, 0), '12');
      expect(_enfocado(tester, campos, 1), isTrue);
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();
    });

    testWidgets('CLAVE: un 1 solo NO lo come el auto-salto — espera y se guarda',
        (tester) async {
      await _montar(tester, _rondaEquipo());
      final campos = _casillas();
      await tester.enterText(campos.at(0), '1');
      await tester.pump();
      // Aún no avanza: un 1 puede ser el inicio de 10–19, así que espera.
      expect(_enfocado(tester, campos, 1), isFalse,
          reason: 'no salta al instante: podría venir un 2º dígito');
      await tester.pump(const Duration(milliseconds: 700)); // pasa la pausa
      expect(_enfocado(tester, campos, 1), isTrue,
          reason: 'sin 2º dígito, el 1 se guarda y avanza');
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();
    });
  });

  group('4 · el registro distingue rellenar de corregir', () {
    test('CLAVE: rellenar dice "se anotó N"; cambiar dice "N → M"', () {
      var r = _rondaEquipo();
      final id = r.scoringPlayers.single.id;
      // Rellenar un hueco vacío.
      r = conCorreccion(r,
          jugadorId: id,
          hoyo: 1,
          nuevo: 6,
          porUid: 'o',
          porNombre: 'Carlos',
          cuando: DateTime(2026, 9, 1, 10));
      expect(r.correcciones.last.frase, contains('se anotó 6'));
      expect(r.correcciones.last.antes, isNull, reason: 'era un hueco');
      // Cambiar el número ya anotado.
      r = conCorreccion(r,
          jugadorId: id,
          hoyo: 1,
          nuevo: 4,
          porUid: 'o',
          porNombre: 'Carlos',
          cuando: DateTime(2026, 9, 1, 11));
      expect(r.correcciones.last.frase, contains('6 → 4'));
      expect(r.correcciones.last.antes, 6, reason: 'ya no es un hueco');
    });
  });
}
