// ─────────────────────────────────────────────────────────────────────────────
// home_layout_test.dart — un test de widget SÍ caza los fallos de geometría
//
// La nota del encargo decía que ningún test habría cazado que los dos iconos de
// la cabecera no se vieran, porque "el widget está en el árbol, la condición se
// cumple, la función existe: falla la geometría".
//
// Eso es cierto para un test de lógica. Un test de WIDGET a un ancho concreto sí
// lo caza: montar la pantalla a 390 px y capturar FlutterError.onError da los
// desbordamientos de RenderFlex, que es exactamente esa clase de fallo.
//
// Es el único mecanismo automático que cubre lo que hasta ahora solo aparecía
// usando la app.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/providers/auth_provider.dart';
import 'package:golf_bet_master/providers/player_provider.dart';
import 'package:golf_bet_master/providers/handicap_provider.dart';
import 'package:golf_bet_master/providers/perfil_provider.dart';
import 'package:golf_bet_master/providers/user_profile_provider.dart';
import 'package:golf_bet_master/screens/home/home_screen.dart';

/// Monta Inicio a un ancho de teléfono y devuelve los errores de layout.
Future<List<String>> _montar(WidgetTester tester, Size tamano) async {
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
      ChangeNotifierProvider(create: (_) => PlayerProvider()),
      // El tablero de Inicio los necesita. Sin ellos la pantalla lanzaba
      // ProviderNotFound y este test seguía pasando —ver _sinErroresGraves—.
      ChangeNotifierProvider(create: (_) => HandicapProvider()),
      ChangeNotifierProvider(create: (_) => PerfilProvider()),
      ChangeNotifierProvider(create: (_) => UserProfileProvider()),
    ],
    child: const MaterialApp(home: HomeScreen()),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  FlutterError.onError = anterior;
  return errores;
}

/// Falla si el árbol lanzó algo que no sea un desbordamiento conocido.
///
/// El recolector de _montar captura FlutterError.onError, así que se queda con
/// TODO lo que la pantalla lance. Los tests de abajo solo miraban los
/// desbordamientos, y eso dejaba pasar el fallo más gordo posible: una pantalla
/// que no se construye. Se descubrió al añadir el tablero —Inicio lanzaba
/// ProviderNotFound en tres widgets y la suite seguía en verde—.
///
/// Mira TODO, desbordamientos incluidos. Se pudo apretar así al arreglar el de
/// los badges del hero —110 px, que llevaba tiempo saliendo—, y conviene que
/// siga apretado: una lista de excepciones toleradas crece hasta que el test
/// deja de decir nada.
void _sinErroresGraves(List<String> errores) {
  expect(errores, isEmpty,
      reason: 'la pantalla lanzó:\n${errores.join('\n---\n')}');
}

void main() {
  testWidgets('Inicio se construye sin lanzar nada', (tester) async {
    // El test que faltaba, y el que habría cazado esto solo. Los de abajo miran
    // geometría, así que una pantalla que no llega a construirse los pasaba.
    _sinErroresGraves(await _montar(tester, const Size(390, 844)));
  });

  testWidgets('los dos destinos de la cabecera están y caben', (tester) async {
    _sinErroresGraves(await _montar(tester, const Size(390, 844)));

    for (final tip in ['Historial', 'Ajustes']) {
      final f = find.byTooltip(tip);
      expect(f, findsOneWidget,
          reason: '$tip salió de la barra y tiene que estar aquí');
      final r = tester.getRect(f.first);
      // Dentro del viewport: un widget en el árbol pero fuera de pantalla es
      // indistinguible de uno que no existe, y es lo que pasó.
      expect(r.right, lessThanOrEqualTo(390),
          reason: '$tip se sale por la derecha');
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.top, greaterThanOrEqualTo(0));
      // Área de toque suficiente: se usa con guante y a una mano.
      expect(r.width, greaterThanOrEqualTo(40));
      expect(r.height, greaterThanOrEqualTo(40));
    }
  });

  testWidgets('el selector de tema ya no está duplicado en la cabecera',
      (tester) async {
    await _montar(tester, const Size(390, 844));
    // Ajustes ya tenía su sección de tema, así que el chip de la cabecera era
    // un duplicado. Y llevaba icono MÁS etiqueta, que es ancho que la fila no
    // tiene.
    for (final etiqueta in ['Clásico', 'Oscuro', 'Claro']) {
      expect(find.text(etiqueta), findsNothing, reason: etiqueta);
    }
  });

  testWidgets('caben también en una pantalla estrecha', (tester) async {
    // 320 px es el suelo razonable. Si a ese ancho se salen, en algún teléfono
    // real también.
    _sinErroresGraves(await _montar(tester, const Size(320, 640)));
    for (final tip in ['Historial', 'Ajustes']) {
      final r = tester.getRect(find.byTooltip(tip).first);
      expect(r.right, lessThanOrEqualTo(320), reason: '$tip a 320 px');
    }
  });
}
