// ─────────────────────────────────────────────────────────────────────────────
// INICIO · LA PANTALLA DONDE APARECIÓ EL SÍNTOMA
//
// «Al crear la ronda aparece uno, pero ya iniciada la ronda, en la pestaña de
//  Inicio, aparece otro.»
//
// ── Y el fallo que ningún test de motor podía cazar ─────────────────────────
//
// La hoja de «Ventajas» se sembraba SOLO del formato viejo. Al guardar, el
// provider reconstruye el acuerdo como espejo exacto de ese formato: un sliding
// pactado en el asistente —que vive en `pairSliding` y no en el legacy— se
// BORRABA al pulsar «Guardar ventajas» sin tocar nada.
//
// Eso solo se ve montando la hoja y pulsando el botón. Y que costara montarla es
// justamente lo que dejó vivir aquí una cuenta paralela sin que nadie la viera.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/screens/home/home_screen.dart';
import 'package:provider/provider.dart';

final _curso = CourseInfo(name: 'P72', holes: [
  for (int i = 1; i <= 18; i++) CourseHole(hole: i, par: 4, strokeIndex: i),
]);

/// CAM (hcp 5) vs CAV (hcp 12). Sin acuerdo, CAV recibiría 7.
///
/// [acuerdo] es lo que el asistente escribe al editar el sliding: vive en
/// `pairSliding` y NO en el formato viejo. Ese es el caso del síntoma.
Round _r({Map<String, double> acuerdo = const {}}) => Round(
      id: 'r',
      name: 'Ronda',
      course: _curso,
      isFinished: false,
      players: [Player(id: 'cam', name: 'CAM'), Player(id: 'cav', name: 'CAV')],
      roundPlayers: [
        RoundPlayer(playerId: 'cam', handicapEnRonda: 5),
        RoundPlayer(playerId: 'cav', handicapEnRonda: 12),
      ],
      betGroups: const [],
      scores: {
        for (final p in ['cam', 'cav'])
          p: {
            for (int h = 1; h <= 9; h++)
              h: HoleScore(playerId: p, hole: h, grossScore: 4, putts: 2)
          }
      },
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2026, 9, 12),
      totalHoles: 18,
      pairSliding: acuerdo,
    );

Future<RoundProvider> _montar(WidgetTester tester, Round r) async {
  final prov = RoundProvider()..startRound(r);
  await tester.pumpWidget(ChangeNotifierProvider<RoundProvider>.value(
    value: prov,
    child: MaterialApp(
      home: Scaffold(
        body: Consumer<RoundProvider>(
          builder: (_, p, __) => ActiveRoundView(prov: p, t: GolfTheme.dark),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return prov;
}

/// Cuántas filas de ventaja están MARCADAS como acuerdo.
///
/// La marca es el fondo con el color de acento: es lo único que distingue «lo
/// pactaron» de «coincide por casualidad». Con un acuerdo de cero las dos dicen
/// «igualdad», así que el texto no basta para probarlo.
int _filasMarcadas(WidgetTester tester, GolfTheme t) {
  final marca = t.accent.withValues(alpha: 0.05);
  return tester
      .widgetList<Container>(find.byType(Container))
      .where((c) {
        final d = c.decoration;
        return d is BoxDecoration && d.color == marca;
      })
      .length;
}

String _texto(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .join('  ‖  ');

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIO 3 · Inicio dice lo mismo que la ronda aplica', () {
    testWidgets('CLAVE: con un acuerdo pactado, Inicio lo enseña', (t) async {
      // El síntoma exacto: el acuerdo dice 3, la resta de handicaps diría 7.
      // Inicio leía la resta.
      await _montar(t, _r(acuerdo: {'cam|cav': -3.0}));
      final txt = _texto(t);
      expect(txt, contains('CAV recibe 3 de CAM'));
      expect(txt.contains('recibe 7'), isFalse,
          reason: 'siete es la resta de handicaps, que aquí no manda');
    });

    testWidgets('CONTRAPESO: sin acuerdo, sí sale la resta', (t) async {
      // Si no, la prueba de arriba no probaría que el acuerdo es lo que manda.
      await _montar(t, _r());
      expect(_texto(t), contains('CAV recibe 7 de CAM'));
    });

    testWidgets('CLAVE: un acuerdo de CERO se lee como igualdad', (t) async {
      // «Jugar a la par» es un pacto. Si cayera a la resta, diría «recibe 7».
      await _montar(t, _r(acuerdo: {'cam|cav': 0.0}));
      final txt = _texto(t);
      expect(txt, contains('igualdad'));
      expect(txt.contains('recibe 7'), isFalse);
    });

    testWidgets('CLAVE: y se MARCA como acuerdo, no como coincidencia',
        (t) async {
      // Las dos dicen «igualdad», así que el texto no las distingue. Lo que las
      // distingue es la marca — y confundirlas haría creer que no se pactó
      // nada, que es justo lo que alguien «corregiría».
      await _montar(t, _r(acuerdo: {'cam|cav': 0.0}));
      expect(_filasMarcadas(t, GolfTheme.dark), 1,
          reason: 'un cero pactado es un acuerdo');
    });

    testWidgets('CONTRAPESO: sin acuerdo, la fila no se marca', (t) async {
      await _montar(t, _r());
      expect(_filasMarcadas(t, GolfTheme.dark), 0);
    });

    testWidgets('CLAVE: y coincide con lo que el motor aplica', (t) async {
      // La prueba de que la pantalla no lleva su propia cuenta: se compara
      // contra la fuente, no contra un número escrito a mano.
      final r = _r(acuerdo: {'cam|cav': -3.0});
      await _montar(t, r);
      final v = r.ventajaDe('cav', 'cam').round();
      expect(_texto(t), contains('CAV recibe $v de CAM'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('EL TERCER FALLO · guardar no puede borrar lo que no se tocó', () {
    testWidgets('CLAVE: «Guardar ventajas» sin cambiar nada CONSERVA el acuerdo',
        (t) async {
      // Solo se ve montando la hoja y pulsando. El provider reconstruye el
      // acuerdo como espejo del formato viejo, y la hoja se sembraba solo de
      // ese formato: lo pactado en el asistente desaparecía.
      final prov = await _montar(t, _r(acuerdo: {'cam|cav': -3.0}));
      expect(prov.round!.pairSliding['cam|cav'], -3.0);

      await t.tap(find.text('Editar'));
      await t.pumpAndSettle();
      expect(find.text('Guardar ventajas'), findsOneWidget,
          reason: 'la hoja se abrió');

      await t.tap(find.text('Guardar ventajas'));
      await t.pumpAndSettle();

      expect(prov.round!.pairSliding['cam|cav'], -3.0,
          reason: 'guardar sin tocar nada no puede mover el acuerdo');
      expect(prov.round!.ventajaDe('cav', 'cam'), 3.0);
    });

    testWidgets('CLAVE: y la hoja ABRE con el acuerdo, no con la resta',
        (t) async {
      // Si mostrara 7, quien lo viera «corregiría» a mano un número que ya
      // estaba bien — y esa corrección sí cambiaría el dinero.
      await _montar(t, _r(acuerdo: {'cam|cav': -3.0}));
      await t.tap(find.text('Editar'));
      await t.pumpAndSettle();
      final txt = _texto(t);
      expect(txt, contains('3'));
      expect(txt.contains('7'), isFalse,
          reason: 'siete es la resta de handicaps');
    });

    testWidgets('CONTRAPESO: y editando SÍ cambia', (t) async {
      // Guardar tiene que ser inocuo sin cambios y efectivo con ellos.
      final prov = await _montar(t, _r(acuerdo: {'cam|cav': -3.0}));
      await t.tap(find.text('Editar'));
      await t.pumpAndSettle();

      // La hoja sube y baja con botones rotulados, no con iconos.
      await t.tap(find.text('+1'));
      await t.pumpAndSettle();
      await t.tap(find.text('Guardar ventajas'));
      await t.pumpAndSettle();

      expect(prov.round!.pairSliding['cam|cav'], isNot(-3.0),
          reason: 'la edición sí tiene que llegar');
    });
  });
}
