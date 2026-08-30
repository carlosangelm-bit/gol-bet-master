// ─────────────────────────────────────────────────────────────────────────────
// MOTION
//
// Dos cosas se prueban aquí, y la segunda es la que decide si esto suma o resta:
//
//   · Que las duraciones y las curvas salgan de UN sitio, como el color y la
//     tipografía. Antes eran 72 valores a mano con diez cifras distintas.
//
//   · Que ANOTAR UN SCORE no se sienta más lento. Es la pantalla donde esta app
//     compite con un lápiz y una tarjeta de papel: una animación que hace
//     esperar ahí es peor que ninguna animación.
//
// Y una tercera que no es preferencia: con "reducir movimiento" activado, nada
// se mueve. Hay gente a la que el movimiento en pantalla le produce mareo.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/widgets/entrada_animada.dart';

/// Monta [child] con o sin el ajuste de accesibilidad del sistema.
Future<void> montar(WidgetTester tester, Widget child,
    {bool reducirMovimiento = false}) async {
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reducirMovimiento),
      child: Scaffold(body: child),
    ),
  ));
}

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('1 · una sola fuente, y una escala con criterio', () {
    test('CLAVE: cuanto más se repite, más corta', () {
      // Es el criterio que resuelve la tensión de fondo: lo frecuente y lo
      // mirado piden cosas opuestas. 300 ms por 72 scores son veinte segundos
      // de espera acumulada en una ronda.
      final escala = [
        GolfMotion.instantaneo,
        GolfMotion.rapido,
        GolfMotion.normal,
        GolfMotion.pausado,
        GolfMotion.escena,
      ];
      for (var i = 1; i < escala.length; i++) {
        expect(escala[i], greaterThan(escala[i - 1]),
            reason: 'la escala tiene que ser monótona para significar algo');
      }
    });

    test('CLAVE: lo que se repite decenas de veces no llega a 100 ms', () {
      // El tramo donde una animación deja de sumar y empieza a estorbar.
      expect(GolfMotion.instantaneo.inMilliseconds, lessThan(100));
      // Y setenta y dos de ellas no llegan a siete segundos de ronda.
      expect(GolfMotion.instantaneo * 72, lessThan(const Duration(seconds: 7)));
    });

    test('y lo que pasa una vez puede permitirse presencia', () {
      expect(GolfMotion.escena.inMilliseconds, greaterThanOrEqualTo(400));
    });

    test('CONTRAPESO: pero nada dura más de medio segundo', () {
      // Sin tope, "presencia" se convierte en espera.
      for (final d in [
        GolfMotion.instantaneo,
        GolfMotion.rapido,
        GolfMotion.normal,
        GolfMotion.pausado,
        GolfMotion.escena,
      ]) {
        expect(d, lessThanOrEqualTo(const Duration(milliseconds: 500)));
      }
    });

    test('las curvas dicen tres cosas distintas, no una', () {
      // Entrar, salir y moverse no son lo mismo, y una curva única los pinta
      // igual.
      final curvas = {GolfMotion.entrada, GolfMotion.salida, GolfMotion.cambio};
      expect(curvas, hasLength(3));
    });

    test('y ninguna es lineal', () {
      // Nada en el mundo físico arranca y para de golpe.
      for (final c in [GolfMotion.entrada, GolfMotion.salida, GolfMotion.cambio]) {
        expect(c, isNot(Curves.linear));
        expect(c.transform(0.5), isNot(closeTo(0.5, 0.001)));
      }
    });

    test('CLAVE: la de énfasis se pasa de largo y vuelve', () {
      // Es lo que la distingue: rebota. Y por eso solo se usa en lo que se
      // celebra — llamar la atención en cada toque es ruido.
      var maximo = 0.0;
      for (var i = 0; i <= 100; i++) {
        final v = GolfMotion.enfasis.transform(i / 100);
        if (v > maximo) maximo = v;
      }
      expect(maximo, greaterThan(1.0));
      expect(GolfMotion.enfasis.transform(1.0), closeTo(1.0, 0.001),
          reason: 'y acaba donde tiene que acabar');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('2 · reducir movimiento', () {
    testWidgets('CLAVE: con el ajuste puesto, cero', (tester) async {
      late BuildContext ctx;
      await montar(tester, Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }), reducirMovimiento: true);
      expect(GolfMotion.quieto(ctx), isTrue);
      expect(GolfMotion.de(ctx, GolfMotion.escena), Duration.zero);
      expect(GolfMotion.retraso(ctx, 5), Duration.zero);
    });

    testWidgets('CONTRAPESO: y sin él, las duraciones son las de verdad',
        (tester) async {
      // Sin esto, un `de()` que devolviera siempre cero pasaría lo de arriba y
      // no habría animación en ninguna parte.
      late BuildContext ctx;
      await montar(tester, Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }));
      expect(GolfMotion.quieto(ctx), isFalse);
      expect(GolfMotion.de(ctx, GolfMotion.escena), GolfMotion.escena);
      expect(GolfMotion.retraso(ctx, 3), greaterThan(Duration.zero));
    });

    testWidgets('la entrada coreografiada no anima nada', (tester) async {
      await montar(
          tester, const EntradaAnimada(child: Text('hola')),
          reducirMovimiento: true);
      // Visible desde el primer frame, sin transición que esperar.
      expect(find.text('hola'), findsOneWidget);
      expect(find.byType(AnimatedOpacity), findsNothing);
      expect(find.byType(AnimatedSlide), findsNothing);
    });

    testWidgets('y la cifra enseña su valor final de golpe', (tester) async {
      await montar(
          tester,
          CifraAnimada(
              valor: 350,
              estilo: const TextStyle(),
              formato: (v) => '\$${v.round()}'),
          reducirMovimiento: true);
      expect(find.text('\$350'), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('3 · el escalonado tiene tope', () {
    testWidgets('CLAVE: veinte filas no son dos segundos de espera',
        (tester) async {
      // Sin tope, la última llega cuando ya nadie mira.
      late BuildContext ctx;
      await montar(tester, Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }));
      expect(GolfMotion.retraso(ctx, 20), GolfMotion.retraso(ctx, 6),
          reason: 'a partir del tope, todas entran juntas');
      expect(GolfMotion.retraso(ctx, 20),
          lessThan(const Duration(milliseconds: 400)));
    });

    testWidgets('pero los primeros SÍ se escalonan', (tester) async {
      // El contrapeso: un retraso siempre cero no es una secuencia.
      late BuildContext ctx;
      await montar(tester, Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }));
      expect(GolfMotion.retraso(ctx, 0), Duration.zero);
      expect(GolfMotion.retraso(ctx, 1), greaterThan(Duration.zero));
      expect(GolfMotion.retraso(ctx, 3),
          greaterThan(GolfMotion.retraso(ctx, 1)));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 4 · EL CRITERIO QUE DECIDE
  //
  // Una animación bonita que hace que anotar un score se sienta pesado es peor
  // que ninguna. Lo que hay que garantizar no es que sea corta: es que NO
  // BLOQUEE.
  // ───────────────────────────────────────────────────────────────────────────
  group('4 · anotar seguido no espera a la animación anterior', () {
    testWidgets('CLAVE: dos toques seguidos cuentan los dos', (tester) async {
      var toques = 0;
      var activo = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (ctx, setSt) => GestureDetector(
              onTap: () => setSt(() {
                toques++;
                activo = !activo;
              }),
              // Como la celda de score: animación IMPLÍCITA. No hay controlador
              // al que esperar; el segundo toque redirige la animación en
              // curso desde donde esté.
              child: AnimatedContainer(
                duration: GolfMotion.rapido,
                color: activo ? Colors.green : Colors.grey,
                width: 100,
                height: 100,
              ),
            ),
          ),
        ),
      ));

      // Dos toques dentro de la duración de la animación.
      await tester.tap(find.byType(AnimatedContainer));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.byType(AnimatedContainer));
      await tester.pump(const Duration(milliseconds: 20));

      expect(toques, 2,
          reason: 'si la animación bloqueara, el segundo toque se perdería');
    });

    testWidgets('y setenta y dos seguidos tampoco', (tester) async {
      // Una ronda entera de cuatro jugadores, sin dejar terminar ninguna.
      var toques = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (ctx, setSt) => GestureDetector(
              onTap: () => setSt(() => toques++),
              child: AnimatedContainer(
                duration: GolfMotion.instantaneo,
                color: toques.isEven ? Colors.green : Colors.grey,
                width: 100,
                height: 100,
              ),
            ),
          ),
        ),
      ));
      for (var i = 0; i < 72; i++) {
        await tester.tap(find.byType(AnimatedContainer));
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(toques, 72);
    });

    testWidgets('CLAVE: y la entrada coreografiada se puede tocar mientras entra',
        (tester) async {
      // La entrada es opacidad y desplazamiento: el widget ya está ahí, con su
      // sitio y su tamaño, desde el primer frame. Es la diferencia entre
      // acompañar y hacer esperar.
      var pulsado = false;
      await montar(
          tester,
          EntradaAnimada(
            child: ElevatedButton(
                onPressed: () => pulsado = true, child: const Text('Guardar')),
          ));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.tap(find.text('Guardar'), warnIfMissed: false);
      await tester.pump();
      expect(pulsado, isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('5 · la cifra que se cuenta', () {
    testWidgets('CLAVE: empieza en cero y acaba en el valor', (tester) async {
      await montar(
          tester,
          CifraAnimada(
              valor: 350,
              estilo: const TextStyle(),
              formato: (v) => '\$${v.round()}'));
      await tester.pump();
      expect(find.text('\$0'), findsOneWidget, reason: 'arranca en cero');
      await tester.pump(GolfMotion.escena);
      expect(find.text('\$350'), findsOneWidget);
    });

    test('el formato viene de fuera, no se inventa aquí', () {
      // El formato del dinero ya está decidido en otro sitio y no puede haber
      // dos. Que sea un parámetro es lo que lo impide.
      const c = CifraAnimada(
          valor: 1, estilo: TextStyle(), formato: _formatoDePrueba);
      expect(c.formato(12.4), '12');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 6 · LA MIGRACIÓN, MEDIDA
  //
  // Los tokens existen; las 72 duraciones escritas a mano no desaparecen solas.
  // Migrarlas todas de golpe cambiaría el ritmo de pantallas que este encargo no
  // toca —un 120 pasa a 150, un 600 a 450— y eso no se puede comprobar con un
  // test: se comprueba mirando.
  //
  // Así que se migran las de este encargo y se CUENTA el resto. Este test no
  // exige que el número baje; exige que no SUBA. Escribir una duración nueva a
  // mano falla aquí, y ahí es donde se decide, no seis meses después.
  // ───────────────────────────────────────────────────────────────────────────
  group('6 · las duraciones que quedan a mano', () {
    /// Cuántas hay fuera del propio archivo de tokens.
    int aMano() {
      var n = 0;
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        // app_theme.dart es donde VIVEN: ahí no son valores sueltos.
        if (f.path.endsWith('core/app_theme.dart')) continue;
        n += RegExp(r'Duration\(milliseconds: \d+\)')
            .allMatches(f.readAsStringSync())
            .length;
      }
      return n;
    }

    test('CLAVE: no suben de donde están', () {
      // El día que este número crezca, alguien escribió una duración a mano
      // teniendo la escala delante. Bajarlo es bienvenido: se ajusta el tope.
      expect(aMano(), lessThanOrEqualTo(66),
          reason: 'hay una escala en GolfMotion: úsala en vez de un número');
    });

    test('CLAVE: y la pantalla de captura no tiene ninguna', () {
      // Es la que este encargo tenía que dejar en su sitio: la más tocada y
      // donde el criterio decide.
      final captura =
          File('lib/screens/capture/capture_screen.dart').readAsStringSync();
      expect(RegExp(r'Duration\(milliseconds: \d+\)').allMatches(captura),
          isEmpty);
      expect(captura, contains('GolfMotion.'));
    });
  });
}

String _formatoDePrueba(double v) => v.round().toString();
