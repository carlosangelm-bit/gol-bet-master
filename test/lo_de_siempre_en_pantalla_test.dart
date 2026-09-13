// ─────────────────────────────────────────────────────────────────────────────
// «LO DE SIEMPRE», MONTADA
//
// La pantalla del botón que faltaba. Se monta con el estado vacío —el que
// Carlos vio— y se comprueba que ahora se puede crear desde ahí.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/providers/betting_group_provider.dart';
import 'package:golf_bet_master/providers/player_provider.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/screens/templates/templates_screen.dart';
import 'package:provider/provider.dart';

Future<String> _montar(WidgetTester tester) async {
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => RoundProvider()),
      ChangeNotifierProvider(create: (_) => BettingGroupProvider()),
      // El editor de grupos lee el directorio para elegir a los habituales.
      ChangeNotifierProvider(create: (_) => PlayerProvider()),
    ],
    child: const MaterialApp(home: TemplatesScreen()),
  ));
  await tester.pumpAndSettle();
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data ?? '')
      .join('  ‖  ');
}

void main() {
  testWidgets('CLAVE: el estado vacío ofrece CREAR, no solo guardar desde una ronda',
      (t) async {
    final txt = await _montar(t);
    expect(txt, contains('Sin plantillas aún'));
    // El botón que faltaba.
    expect(txt, contains('Crear lo de siempre'));
    // Y dice qué es lo que se crea, que es la mitad de la decisión.
    expect(txt, contains('Los jugadores de siempre y sus apuestas, sin campo'));
  });

  testWidgets('CLAVE: y el camino de crear va ANTES que el de guardar',
      (t) async {
    // Lo natural es armarla una vez y usarla desde el principio. El texto de
    // guardar desde una ronda se queda como lo que es: un atajo.
    final txt = await _montar(t);
    final crear = txt.indexOf('Crear lo de siempre');
    final guardar = txt.indexOf('Guardar como plantilla');
    expect(crear, greaterThan(-1));
    expect(guardar, greaterThan(crear));
  });

  testWidgets('CLAVE: hay botón de crear también en la barra', (t) async {
    // Quien ya tiene plantillas guardadas nunca ve el estado vacío, y seguiría
    // sin poder crear.
    await _montar(t);
    expect(find.byTooltip('Crear lo de siempre'), findsOneWidget);
  });

  testWidgets('CLAVE: pulsarlo abre el editor, no cierra la pantalla',
      (t) async {
    await _montar(t);
    await t.tap(find.byTooltip('Crear lo de siempre'));
    await t.pumpAndSettle();
    // Se navegó a otra pantalla: «Lo de siempre» ya no está debajo del dedo.
    expect(find.text('Sin plantillas aún'), findsNothing);
  });
}
