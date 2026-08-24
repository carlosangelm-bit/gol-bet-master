// ─────────────────────────────────────────────────────────────────────────────
// AÑADIR JUGADORES — la propiedad que falla no es "añadir", es "añadir OTRA VEZ"
//
// El bug: en el paso Jugadores, la lista dejaba de responder después del primer
// añadido. Un jugador por carga, y para meter cinco había que recargar cuatro
// veces. Es el primer paso de cualquier ronda, así que lo toca todo el mundo.
//
// Por qué sobrevivió: cualquier test que añada UN jugador pasa. Y los tests que
// añadían cinco también pasaban, porque sus jugadores no tenían PlayerLink —sin
// link no hay sliding predefinido y la rama que fallaba no se ejecutaba—. La
// diferencia entre el harness y la app era exactamente ese dato.
//
// Misma familia que el contador que retrocedía y el hueco tratado como bye:
// fallos de SECUENCIA que un test de un paso no ve.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/providers/auth_provider.dart';
import 'package:golf_bet_master/providers/betting_group_provider.dart';
import 'package:golf_bet_master/providers/handicap_provider.dart';
import 'package:golf_bet_master/providers/perfil_provider.dart';
import 'package:golf_bet_master/providers/player_provider.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/providers/torneo_provider.dart';
import 'package:golf_bet_master/providers/user_profile_provider.dart';
import 'package:golf_bet_master/screens/setup/setup_screen.dart';
import 'package:golf_bet_master/services/player_service.dart';

/// Los compañeros como son de verdad: favoritos, con apodo, con sliding
/// predefinido y alguno con handicap sobrescrito.
///
/// El sliding es LO QUE IMPORTA: es el dato que el harness no tenía y la app sí.
const compas = <(String, String, double, double)>[
  ('CAV', 'Cavazos', 12.0, -9.0),
  ('AAM', 'Alejandro', 18.0, -4.0),
  ('RAFA', 'Rafael', 8.0, 6.0),
  ('CAM', 'Carlos', 15.0, 0.0),
  ('RICH', 'Ricardo', 22.0, -2.0),
];

List<PlayerWithLink> _directorio({bool conLink = true}) {
  final ahora = DateTime(2026, 1, 1);
  return [
    for (final c in compas)
      PlayerWithLink(
        player: Player(
            id: 'pid_${c.$1.toLowerCase()}', name: c.$2, handicapBase: c.$3),
        link: conLink
            ? PlayerLink(
                playerId: 'pid_${c.$1.toLowerCase()}',
                isFavorite: true,
                defaultSlidingAdjustment: c.$4,
                // Uno con handicap sobrescrito, que es otra rama del añadido.
                defaultHandicapOverride: c.$1 == 'RAFA' ? 7.5 : null,
                createdAt: ahora,
                updatedAt: ahora,
              )
            : null,
      ),
  ];
}

/// Abre el asistente en el paso Jugadores.
Future<List<String>> _hastaJugadores(WidgetTester tester,
    {bool conLink = true, Size tamano = const Size(390, 2000)}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final errores = <String>[];
  final anterior = FlutterError.onError;
  // Cualquier error. Es la clave del bug: una excepción dentro del handler del
  // toque la caza el framework y el toque "no hace nada".
  FlutterError.onError = (d) => errores.add(d.exceptionAsString());

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => RoundProvider()),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => HandicapProvider()),
      ChangeNotifierProvider(create: (_) => UserProfileProvider()),
      ChangeNotifierProvider(create: (_) => BettingGroupProvider()),
      ChangeNotifierProvider(create: (_) => TorneoProvider()),
      ChangeNotifierProvider(create: (_) => PerfilProvider()),
      ChangeNotifierProvider<PlayerProvider>.value(
          value: PlayerProvider()..sembrar(_directorio(conLink: conLink))),
    ],
    child: const MaterialApp(home: SetupScreen()),
  ));
  await tester.pump(const Duration(milliseconds: 150));
  await tester.tap(find.text('Siguiente →'));
  await tester.pumpAndSettle();
  FlutterError.onError = anterior;
  return errores;
}

/// La fila del DIRECTORIO de [nombre].
///
/// Se busca dentro de la sección del directorio y no por nombre a secas: una vez
/// añadido, el nombre también aparece arriba en "EN ESTA RONDA", y
/// find.text(nombre).first apuntaría a ese chip.
Finder _filaDe(WidgetTester tester, String nombre) {
  final textos = find.text(nombre);
  // La del directorio es la que tiene un GestureDetector con AnimatedContainer
  // por encima: el chip de la ronda no lo tiene.
  for (var i = 0; i < textos.evaluate().length; i++) {
    final cand = find.ancestor(
        of: textos.at(i), matching: find.byType(AnimatedContainer));
    if (cand.evaluate().isNotEmpty) {
      return find.ancestor(of: textos.at(i), matching: find.byType(GestureDetector));
    }
  }
  return find.ancestor(of: textos.first, matching: find.byType(GestureDetector));
}

/// Toca [donde] dentro de la fila de [nombre] y devuelve los errores.
///
/// [donde] elige el punto:
///   · 'nombre' → el texto. Es lo que tocaban los tests, y siempre funcionó.
///   · 'mas'    → el círculo del + , que es la señal que la pantalla ofrece.
///   · 'hueco'  → el espacio vacío de la fila, entre el texto y el +.
Future<List<String>> _tocar(WidgetTester tester, String nombre,
    {String donde = 'nombre'}) async {
  final errores = <String>[];
  final anterior = FlutterError.onError;
  FlutterError.onError = (d) => errores.add(d.exceptionAsString());

  final texto = find.text(nombre);
  expect(texto, findsWidgets, reason: 'no está la fila de $nombre');
  await tester.ensureVisible(texto.first);
  await tester.pump();

  final fila = _filaDe(tester, nombre).first;
  if (donde == 'mas') {
    // El icono de ESTA fila. Tocar el widget y no una posición adivinada: es lo
    // que hace el usuario, y el círculo no está donde uno cree —mide 21 px y
    // vive a 50 px del borde, no pegado a él—.
    final mas = find.descendant(of: fila, matching: find.byIcon(Icons.add));
    final check =
        find.descendant(of: fila, matching: find.byIcon(Icons.check));
    final blanco = mas.evaluate().isNotEmpty ? mas : check;
    expect(blanco, findsOneWidget, reason: 'la fila de $nombre no tiene señal');
    await tester.tap(blanco, warnIfMissed: false);
  } else if (donde == 'hueco') {
    // El espacio vacío entre el texto y la señal. Una fila de lista se toca
    // donde caiga.
    final caja = tester.getRect(fila);
    await tester.tapAt(Offset(caja.right - 45, caja.center.dy));
  } else {
    await tester.tap(fila, warnIfMissed: false);
  }
  await tester.pump(const Duration(milliseconds: 200));

  FlutterError.onError = anterior;
  return errores;
}

/// Cuántos jugadores dice la PANTALLA que hay en la ronda.
///
/// Sale de la cabecera "EN ESTA RONDA (n/8)", que es lo que el usuario lee. Se
/// mide eso y no el estado interno: el bug era justamente que la pantalla no se
/// enteraba.
int _enLaRonda(WidgetTester tester) {
  for (final w in tester.widgetList<Text>(find.byType(Text))) {
    final m = RegExp(r'EN ESTA RONDA \((\d+)/8\)').firstMatch(w.data ?? '');
    if (m != null) return int.parse(m.group(1)!);
  }
  return -1;
}

void main() {
  group('0 · el + y el hueco de la fila responden al toque', () {
    // ESTE es el bug. El + es un círculo de 24 px con un glifo de 14 dentro, y
    // el GestureDetector de la fila era deferToChild: solo respondía donde
    // pintaban sus hijos. O sea que de la fila entera —unos 350×46— lo tocable
    // eran el texto del nombre y 14 px de glifo.
    //
    // Los tests tocaban find.text(nombre), que SÍ es tocable, y por eso pasaban
    // mientras la app no respondía: el usuario apunta al +, que es la señal que
    // la pantalla le ofrece.
    testWidgets('tocar el + añade al jugador', (tester) async {
      await _hastaJugadores(tester);
      expect(await _tocar(tester, 'Cavazos', donde: 'mas'), isEmpty);
      expect(_enLaRonda(tester), 1,
          reason: 'el círculo del + no respondió al toque');
    });

    testWidgets('y el hueco de la fila también', (tester) async {
      // Una fila de lista se toca donde caiga, no solo sobre las letras.
      await _hastaJugadores(tester);
      expect(await _tocar(tester, 'Cavazos', donde: 'hueco'), isEmpty);
      expect(_enLaRonda(tester), 1,
          reason: 'el hueco de la fila no respondió al toque');
    });

    testWidgets('CINCO seguidos tocando siempre el +', (tester) async {
      // El recorrido real: el usuario apunta al + cada vez.
      await _hastaJugadores(tester);
      for (var i = 0; i < compas.length; i++) {
        expect(await _tocar(tester, compas[i].$2, donde: 'mas'), isEmpty,
            reason: compas[i].$2);
        expect(_enLaRonda(tester), i + 1,
            reason: 'el toque ${i + 1} en el + no entró');
      }
    });
  });

  group('1 · se pueden añadir CINCO seguidos, sin recargar', () {
    testWidgets('los cinco entran, y ningún toque produce un error',
        (tester) async {
      final arranque = await _hastaJugadores(tester);
      expect(arranque, isEmpty, reason: 'la pantalla ya arranca con errores');

      // El corazón del test: se tocan los cinco EN SECUENCIA y se comprueba
      // cada toque. Un test que añada uno pasa hoy; lo que fallaba era repetir.
      for (final c in compas) {
        final errores = await _tocar(tester, c.$2);
        expect(errores, isEmpty,
            reason: 'el toque en ${c.$2} lanzó: ${errores.join(' | ')}');
      }

      // Y los cinco están dentro: la señal del paso lo dice.
      expect(_enLaRonda(tester), 5, reason: 'no llegaron los cinco');
    });

    testWidgets('el SEGUNDO toque es el que fallaba: se prueba aislado',
        (tester) async {
      // El primero funcionaba siempre porque el bucle del sliding no se
      // ejecuta con la ronda vacía. El segundo sí lo ejecuta.
      await _hastaJugadores(tester);
      expect(await _tocar(tester, 'Cavazos'), isEmpty);
      final segundo = await _tocar(tester, 'Alejandro');
      expect(segundo, isEmpty,
          reason: 'el segundo añadido lanzó: ${segundo.join(' | ')}');
      expect(_enLaRonda(tester), 2);
    });
  });

  group('2 · quitar y volver a añadir en la misma sesión', () {
    testWidgets('se quita el segundo y vuelve a entrar', (tester) async {
      await _hastaJugadores(tester);
      await _tocar(tester, 'Cavazos');
      await _tocar(tester, 'Alejandro');
      expect(_enLaRonda(tester), 2);

      // Tocar de nuevo lo quita.
      expect(await _tocar(tester, 'Alejandro'), isEmpty);
      expect(_enLaRonda(tester), 1);

      // Y vuelve a entrar.
      expect(await _tocar(tester, 'Alejandro'), isEmpty);
      expect(_enLaRonda(tester), 2);
    });

    testWidgets('quitar el primero y añadir otros dos sigue funcionando',
        (tester) async {
      await _hastaJugadores(tester);
      for (final n in ['Cavazos', 'Alejandro', 'Rafael']) {
        expect(await _tocar(tester, n), isEmpty);
      }
      expect(await _tocar(tester, 'Cavazos'), isEmpty); // lo quita
      for (final n in ['Carlos', 'Ricardo']) {
        expect(await _tocar(tester, n), isEmpty);
      }
      expect(_enLaRonda(tester), 4);
    });
  });

  group('3 · sin PlayerLink también, que es como estaba el harness', () {
    testWidgets('cinco seguidos sin link', (tester) async {
      // El contrapeso: si el arreglo dependiera del link, este test lo diría.
      await _hastaJugadores(tester, conLink: false);
      for (final c in compas) {
        expect(await _tocar(tester, c.$2), isEmpty, reason: c.$2);
      }
      expect(_enLaRonda(tester), 5);
    });
  });
}
