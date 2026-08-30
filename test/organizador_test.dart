// ─────────────────────────────────────────────────────────────────────────────
// EL PORTAL DE ORGANIZADOR — punto 1: el armazón y la tabla de inscritos
//
// Tres cosas se prueban aquí, y las tres son criterios del encargo:
//
//   2 · buscar, ordenar y editar sin salir de la tabla
//   3 · funciona en escritorio y se degrada a algo usable en móvil, POR ANCHO
//   4 · nada de lo que ya funciona se rompe
//
// El criterio 3 es el que decide si esto sirve. Un portal que solo funcione en
// escritorio deja al organizador sin nada el día del torneo, que es cuando está
// en el campo con el teléfono. Por eso los cortes son una función pura y con
// pruebas: para que nadie pueda convertirlos en `if (kIsWeb)` sin que salte.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/ancho.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/core/escuchas.dart';
import 'package:golf_bet_master/models/inscritos.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/torneo.dart';
import 'package:golf_bet_master/providers/player_provider.dart';
import 'package:golf_bet_master/providers/torneo_provider.dart';
import 'package:golf_bet_master/screens/organizador/inscritos_tabla.dart';
import 'package:golf_bet_master/services/player_service.dart';
import 'package:provider/provider.dart';

PlayerWithLink _pw(String id, String nombre, double hcp) => PlayerWithLink(
    player: Player(id: id, name: nombre, handicapBase: hcp), link: null);

final _directorio = [
  _pw('p1', 'Luis Herrera', 12),
  _pw('p2', 'Ana Ruiz', 4),
  _pw('p3', 'Dani Sotó', 12),
  _pw('p4', 'Álvaro Núñez', 21),
];

Torneo _torneo({List<String>? participantes, List<String> siembra = const []}) =>
    Torneo(
      id: 't1',
      nombre: 'Copa de Primavera',
      fuente: FuenteDeRondas.marcadas,
      metodo: MetodoDePuntuacion.posicion,
      participantes: participantes ?? const ['p1', 'p2', 'p3', 'p4'],
      siembra: siembra,
    );

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('1 · el layout sale del ANCHO, no de la plataforma', () {
    test('los tres tramos', () {
      expect(anchoDe(1440), Ancho.amplio);
      expect(anchoDe(1100), Ancho.amplio, reason: 'el corte entra en el tramo');
      expect(anchoDe(1099), Ancho.medio);
      expect(anchoDe(720), Ancho.medio);
      expect(anchoDe(719), Ancho.estrecho);
      expect(anchoDe(390), Ancho.estrecho, reason: 'un teléfono en el campo');
    });

    test('CLAVE: la misma URL sirve en las dos puntas', () {
      // Es el criterio 3. En el portátil de la casa club por la mañana y en el
      // teléfono desde el estacionamiento a mediodía.
      expect(anchoDe(1440).esTabla, isTrue);
      expect(anchoDe(390).esTabla, isFalse);
      expect(anchoDe(390).anchoDeContenido, lessThan(anchoDe(1440).anchoDeContenido));
    });

    test('las columnas accesorias solo caben en el tramo ancho', () {
      expect(anchoDe(1440).columnasCompletas, isTrue);
      expect(anchoDe(900).columnasCompletas, isFalse,
          reason: 'tabla sí, pero sin # ni acciones sueltas');
      expect(anchoDe(390).columnasCompletas, isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('2 · buscar', () {
    test('por trozo del nombre', () {
      final f = filasDeInscritos(_torneo(), _directorio, busca: 'ruiz');
      expect(f.map((x) => x.nombre), ['Ana Ruiz']);
    });

    test('CLAVE: ignora acentos y mayúsculas, como el resto del sistema', () {
      // Usa nombreComparable, la MISMA normalización que la importación por
      // pegado y el reparto de resultados. Dos normalizaciones distintas darían
      // un fallo silencioso: el nombre coincide para el ojo y no para el código.
      expect(filasDeInscritos(_torneo(), _directorio, busca: 'ALVARO').length, 1);
      expect(filasDeInscritos(_torneo(), _directorio, busca: 'sotó').length, 1);
      expect(filasDeInscritos(_torneo(), _directorio, busca: 'soto').length, 1);
    });

    test('sin coincidencias devuelve vacío, no todo', () {
      expect(filasDeInscritos(_torneo(), _directorio, busca: 'zzz'), isEmpty);
    });

    test('y sin búsqueda están todos', () {
      expect(filasDeInscritos(_torneo(), _directorio), hasLength(4));
    });
  });

  group('2 · ordenar', () {
    List<String> orden(OrdenDeInscritos o, {bool desc = false}) =>
        filasDeInscritos(_torneo(), _directorio, orden: o, descendente: desc)
            .map((f) => f.nombre)
            .toList();

    test('por inscripción es el orden en que los metió el organizador', () {
      expect(orden(OrdenDeInscritos.inscripcion),
          ['Luis Herrera', 'Ana Ruiz', 'Dani Sotó', 'Álvaro Núñez']);
    });

    test('por nombre, con los acentos donde tocan', () {
      // Álvaro va con la A, no al final: es lo que espera quien lo busca.
      expect(orden(OrdenDeInscritos.nombre).first, 'Álvaro Núñez');
    });

    test('por handicap, de menos a más', () {
      expect(orden(OrdenDeInscritos.handicap).first, 'Ana Ruiz');
      expect(orden(OrdenDeInscritos.handicap).last, 'Álvaro Núñez');
    });

    test('CLAVE: a igual handicap desempata el nombre', () {
      // Luis y Dani van los dos a 12. Sin desempate, reordenar barajaba a los
      // quince que van a 12 y parecía que cambiaban de sitio solos.
      final doceA = orden(OrdenDeInscritos.handicap).sublist(1, 3);
      final doceB = orden(OrdenDeInscritos.handicap).sublist(1, 3);
      expect(doceA, doceB);
      expect(doceA, ['Dani Sotó', 'Luis Herrera']);
    });

    test('invertir da la vuelta a la lista entera', () {
      expect(orden(OrdenDeInscritos.nombre, desc: true),
          orden(OrdenDeInscritos.nombre).reversed.toList());
    });
  });

  group('2 · el inscrito sin ficha', () {
    test('CLAVE: se ve, no desaparece', () {
      // Pasa de verdad: se borra una ficha del directorio y el id se queda
      // inscrito. Si la fila desapareciera, el recuento no cuadraría con la
      // lista guardada y sería una diferencia que nadie explica.
      final t = _torneo(participantes: const ['p1', 'fantasma']);
      final f = filasDeInscritos(t, _directorio);
      expect(f, hasLength(2));
      expect(f.last.huerfano, isTrue);
      expect(f.last.nombre, contains('no encontrada'));
    });

    test('y no se cuela en una búsqueda de otro', () {
      final t = _torneo(participantes: const ['p1', 'fantasma']);
      expect(filasDeInscritos(t, _directorio, busca: 'luis'), hasLength(1));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('3 · añadir y quitar', () {
    test('quitar lo saca de la lista', () {
      final t = sinInscrito(_torneo(), 'p2');
      expect(t.participantes, ['p1', 'p3', 'p4']);
    });

    test('CLAVE: y también del cuadro', () {
      // Dejarlo en la siembra cruzaba en el cuadro a alguien que ya no juega.
      final t = _torneo(siembra: const ['p1', 'p2', 'p3', 'p4']);
      expect(sinInscrito(t, 'p2').siembra, ['p1', 'p3', 'p4']);
    });

    test('quitar a quien no está devuelve el mismo objeto', () {
      // Así quien llama no comprueba nada y no se guarda una escritura idéntica.
      final t = _torneo();
      expect(identical(sinInscrito(t, 'nadie'), t), isTrue);
    });

    test('añadir respeta el orden y no duplica', () {
      final t = conInscritos(_torneo(participantes: const ['p1']), ['p2', 'p1']);
      expect(t.participantes, ['p1', 'p2']);
    });

    test('añadir solo a quien ya está devuelve el mismo objeto', () {
      final t = _torneo();
      expect(identical(conInscritos(t, ['p1', 'p2']), t), isTrue);
    });

    test('deshacer devuelve al FINAL, no a su sitio de antes', () {
      // El orden de inscripción es un hecho de cuándo entró cada uno; fingir
      // que nunca salió sería inventarse ese hecho.
      final quitado = sinInscrito(_torneo(), 'p1');
      expect(conInscritos(quitado, ['p1']).participantes,
          ['p2', 'p3', 'p4', 'p1']);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('4 · la tabla en pantalla, en las dos puntas', () {
    Future<void> montar(WidgetTester tester, Size tamano,
        {Torneo? torneo}) async {
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final t = torneo ?? _torneo();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(
              create: (_) => PlayerProvider()..sembrar(_directorio)),
          ChangeNotifierProvider(
              create: (_) => TorneoProvider()..sembrar([t])),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: LayoutBuilder(
              builder: (_, c) => InscritosTabla(
                  torneo: t, ancho: anchoDe(c.maxWidth), t: GolfTheme.classic),
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('en escritorio: tabla con cabeceras y los cuatro nombres',
        (tester) async {
      await montar(tester, const Size(1440, 900));
      expect(find.text('NOMBRE'), findsOneWidget);
      expect(find.text('HANDICAP'), findsOneWidget);
      expect(find.text('#'), findsOneWidget, reason: 'columna del tramo ancho');
      for (final n in ['Luis Herrera', 'Ana Ruiz', 'Dani Sotó', 'Álvaro Núñez']) {
        expect(find.text(n), findsOneWidget);
      }
    });

    testWidgets('CLAVE: en móvil no hay tabla, pero sí están todos',
        (tester) async {
      // El criterio 3. Degradarse no es desaparecer.
      await montar(tester, const Size(390, 844));
      expect(find.text('NOMBRE'), findsNothing);
      expect(find.text('#'), findsNothing);
      for (final n in ['Luis Herrera', 'Ana Ruiz', 'Dani Sotó', 'Álvaro Núñez']) {
        expect(find.text(n), findsOneWidget);
      }
      // Y el orden se puede cambiar igual, con chips en vez de cabeceras.
      //
      // Los TRES visibles sin arrastrar. Con la etiqueta larga, "Handicap" se
      // salía de los 390 px y solo aparecía al arrastrar — un control que hay
      // que descubrir arrastrando es un control que no está.
      for (final o in OrdenDeInscritos.values) {
        expect(find.text(o.labelCorto), findsOneWidget, reason: o.name);
      }
    });

    testWidgets('en tableta: tabla, pero sin las columnas accesorias',
        (tester) async {
      await montar(tester, const Size(900, 700));
      expect(find.text('NOMBRE'), findsOneWidget);
      expect(find.text('#'), findsNothing);
    });

    testWidgets('buscar filtra en pantalla, sin salir de la tabla',
        (tester) async {
      await montar(tester, const Size(1440, 900));
      await tester.enterText(find.byType(TextField).first, 'ruiz');
      await tester.pump();
      expect(find.text('Ana Ruiz'), findsOneWidget);
      expect(find.text('Luis Herrera'), findsNothing);
    });

    testWidgets('pulsar la cabecera ordena, y volver a pulsarla invierte',
        (tester) async {
      await montar(tester, const Size(1440, 900));
      Future<void> pulsar() async {
        await tester.tap(find.text('NOMBRE'));
        await tester.pump();
      }

      List<String> visibles() => tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .where((s) => s.contains(' '))
          .toList();

      await pulsar();
      expect(visibles().indexWhere((s) => s.startsWith('Álvaro')),
          lessThan(visibles().indexWhere((s) => s.startsWith('Luis'))));
      await pulsar();
      expect(visibles().indexWhere((s) => s.startsWith('Luis')),
          lessThan(visibles().indexWhere((s) => s.startsWith('Álvaro'))));
    });

    testWidgets('sin inscritos lo dice, y no deja la pantalla vacía',
        (tester) async {
      await montar(tester, const Size(1440, 900),
          torneo: _torneo(participantes: const []));
      expect(find.textContaining('Todavía no hay nadie'), findsOneWidget);
      expect(find.textContaining('pega la lista'), findsOneWidget);
    });

    testWidgets('buscando sin resultados dice otra cosa distinta',
        (tester) async {
      await montar(tester, const Size(1440, 900));
      await tester.enterText(find.byType(TextField).first, 'zzz');
      await tester.pump();
      expect(find.textContaining('Nadie con ese nombre'), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('5 · el portal arranca lo mismo que la app', () {
    // El portal NO pasa por AppShell, y los streams de Firestore no arrancan
    // solos: los arrancaba AppShell. Sin arrancarlos, el portal habría abierto
    // siempre con "este torneo no está en tu cuenta" para su propio dueño.
    //
    // La lista está una sola vez, en core/escuchas.dart. Esto comprueba que
    // sigue estando una sola vez: una copia se separa el día que se añada un
    // provider, y lo que falla entonces es una pantalla vacía sin motivo.
    String fuente(String ruta) => File(ruta).readAsStringSync();

    test('las dos raíces llaman a la MISMA función', () {
      for (final ruta in [
        'lib/app_shell.dart',
        'lib/screens/organizador/organizador_screen.dart',
      ]) {
        expect(fuente(ruta), contains('iniciarEscuchas(context)'), reason: ruta);
      }
    });

    test('CLAVE: y ninguna arranca providers por su cuenta', () {
      for (final ruta in [
        'lib/app_shell.dart',
        'lib/screens/organizador/organizador_screen.dart',
      ]) {
        expect(fuente(ruta).contains('.startListening()'), isFalse,
            reason: '$ruta: la composición se define en core/escuchas.dart');
      }
    });

    test('y la única definición arranca los siete', () {
      final src = fuente('lib/core/escuchas.dart');
      for (final p in escuchasQueArrancan) {
        expect(src.contains('<$p>()'), isTrue, reason: p);
      }
    });
  });
}
