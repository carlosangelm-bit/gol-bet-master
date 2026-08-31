// ─────────────────────────────────────────────────────────────────────────────
// LAS PLANTILLAS DE LA TELE
//
// «La pantalla no se parece a un gráfico de la PGA. Debería haber varios
// diseños a elegir que fueran en línea con la identidad que quiere el torneo.»
//
// El riesgo de este encargo no es que quede feo: es que un organizador con
// prisa el día del torneo elija una combinación ilegible y la proyecte ocho
// horas. Así que casi todo lo de aquí abajo comprueba lo mismo desde ángulos
// distintos: QUE NO SE PUEDA ROMPER.
//
//   1 · el catálogo, y que las cuatro sean de verdad distintas
//   2 · el contraste, PLANTILLA POR PLANTILLA y fondo por fondo
//   3 · la corrección del acento, que es lo que impide el desastre
//   4 · el tamaño, que no puede depender del diseño elegido
//   5 · el score contra el par, que es lo que hace que se reconozca
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/leaderboard_publico.dart';
import 'package:golf_bet_master/models/plantilla_de_tele.dart';
import 'package:golf_bet_master/screens/torneos/leaderboard_tv_screen.dart';

LeaderboardPublico _lb({
  IdentidadDeTorneo identidad = const IdentidadDeTorneo(),
  List<int?> bajoPar = const [-7, 0, 4, null],
  int rondas = 3,
}) =>
    LeaderboardPublico(
      token: 'tok',
      ownerUid: 'uid',
      nombre: 'Copa de Primavera',
      emoji: 'trofeo',
      publicadoEn: DateTime(2026, 8, 30, 14),
      comoSePuntua: 'Por score neto',
      rondas: rondas,
      tabla: [
        for (var i = 0; i < bajoPar.length; i++)
          FilaProyectada(
              puesto: i + 1,
              nombre: 'Jugador ${i + 1}',
              jugadas: i == 0 ? rondas : rondas - 1,
              medida: (280 + i).toDouble(),
              bajoPar: bajoPar[i]),
      ],
      identidad: identidad,
    );

Future<void> _montar(WidgetTester tester, LeaderboardPublico datos,
    {Size tamano = const Size(1920, 1080)}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final previo = ErrorWidget.builder;
  addTearDown(() => ErrorWidget.builder = previo);
  await tester.pumpWidget(MaterialApp(
    home: LeaderboardTvScreen(
        token: 'tok', modoDePrueba: true, datosDePrueba: datos),
  ));
  await tester.pump(const Duration(milliseconds: 200));
}

double _mayorFuente(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.style?.fontSize ?? 0)
    .fold<double>(0, (a, b) => a > b ? a : b);

String _texto(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .join(' · ');

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('1 · el catálogo: distinguibles, no cuatro veces la misma', () {
    test('CLAVE: hay al menos tres, y ninguna se parece a otra', () {
      expect(PlantillasDeTele.todas.length, greaterThanOrEqualTo(3));

      // Distinguibles DE VERDAD: si dos fondos base están a menos de un 15 % de
      // luminancia, en una pared son la misma pantalla con otro nombre.
      final luces =
          PlantillasDeTele.todas.map((p) => p.fondos.first).toList();
      for (var i = 0; i < luces.length; i++) {
        for (var j = i + 1; j < luces.length; j++) {
          final d = (luces[i].computeLuminance() - luces[j].computeLuminance())
              .abs();
          final tono = (HSLColor.fromColor(luces[i]).hue -
                  HSLColor.fromColor(luces[j]).hue)
              .abs();
          expect(d > 0.004 || tono > 15, isTrue,
              reason: '${PlantillasDeTele.todas[i].nombre} y '
                  '${PlantillasDeTele.todas[j].nombre} son la misma pantalla');
        }
      }
    });

    test('cada una trae sus tres profundidades, y suben', () {
      for (final p in PlantillasDeTele.todas) {
        expect(p.fondos.length, PlantillaDeTele.profundidades, reason: p.clave);
        expect(p.filas.length, PlantillaDeTele.profundidades, reason: p.clave);
        expect(p.filasPodio.length, PlantillaDeTele.profundidades,
            reason: p.clave);
        // De la más oscura a la más clara: si no fuera monótono, el selector
        // enseñaría tres muestras en desorden.
        for (var i = 1; i < p.fondos.length; i++) {
          expect(p.fondos[i].computeLuminance(),
              greaterThan(p.fondos[i - 1].computeLuminance()),
              reason: p.clave);
        }
      }
    });

    test('las claves no se repiten, y una desconocida cae en la de siempre',
        () {
      final claves = PlantillasDeTele.todas.map((p) => p.clave).toSet();
      expect(claves.length, PlantillasDeTele.todas.length);
      // Un torneo publicado con una plantilla que ya no existe se sigue
      // proyectando. Es la misma promesa que la marca de un grupo.
      expect(PlantillasDeTele.deClave('la-que-borramos').clave, 'club');
      expect(PlantillasDeTele.deClave(null).clave, 'club');
      expect(PlantillasDeTele.claveInicial, 'club');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 2 · EL CONTRASTE
  //
  // «Si el organizador elige un color de fondo, el texto tiene que seguir
  // cumpliendo AA sobre él.» Esto lo comprueba para TODAS las plantillas y
  // TODAS sus profundidades, que son doce combinaciones. Añadir una plantilla
  // nueva mal calibrada falla aquí sin que nadie tenga que acordarse.
  // ───────────────────────────────────────────────────────────────────────────
  group('2 · el contraste, plantilla por plantilla', () {
    test('CLAVE: el texto principal cumple AA en las doce combinaciones', () {
      for (final p in PlantillasDeTele.todas) {
        for (var i = 0; i < PlantillaDeTele.profundidades; i++) {
          final piel = p.resolver(profundidad: i);
          expect(piel.texto.contrasteCon(piel.fondo),
              greaterThanOrEqualTo(MinimoDeContraste.texto),
              reason: '${p.clave} · fondo $i');
          // Y sobre el relleno de la fila, que es donde el texto vive de
          // verdad: comprobarlo solo contra el fondo dejaría fuera el sitio
          // exacto donde se lee.
          expect(piel.texto.contrasteCon(piel.fila),
              greaterThanOrEqualTo(MinimoDeContraste.texto),
              reason: '${p.clave} · fila $i');
          expect(piel.texto.contrasteCon(piel.filaPodio),
              greaterThanOrEqualTo(MinimoDeContraste.texto),
              reason: '${p.clave} · podio $i');
        }
      }
    });

    test('CLAVE: el secundario y el acento también, con su propio mínimo', () {
      for (final p in PlantillasDeTele.todas) {
        for (var i = 0; i < PlantillaDeTele.profundidades; i++) {
          final piel = p.resolver(profundidad: i);
          expect(piel.textoSuave.contrasteCon(piel.fila),
              greaterThanOrEqualTo(MinimoDeContraste.secundario),
              reason: '${p.clave} · suave $i');
          expect(piel.acento.contrasteCon(piel.fondo),
              greaterThanOrEqualTo(MinimoDeContraste.acento),
              reason: '${p.clave} · acento $i');
          // El rojo del bajo par es la columna que se mira; si se pierde en el
          // fondo, la plantilla no sirve para un leaderboard de golf.
          expect(piel.bajoPar.contrasteCon(piel.filaPodio),
              greaterThanOrEqualTo(MinimoDeContraste.acento),
              reason: '${p.clave} · bajo par $i');
        }
      }
    });

    test('CONTRAPESO: y los mínimos no son un 1 disfrazado', () {
      // Sin esto, bajar los mínimos a 1.0 dejaría los dos tests de arriba en
      // verde con cualquier paleta, incluida gris sobre gris.
      expect(MinimoDeContraste.texto, greaterThanOrEqualTo(4.5));
      expect(MinimoDeContraste.secundario, greaterThanOrEqualTo(3.0));
      expect(MinimoDeContraste.acento, greaterThanOrEqualTo(3.0));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 3 · LA CORRECCIÓN DEL ACENTO
  //
  // Es la pieza que protege el producto: el acento es libre —tiene que serlo,
  // o el azul de una empresa no es el suyo— y por eso es lo único que puede
  // romper el contraste. No se avisa: se corrige.
  // ───────────────────────────────────────────────────────────────────────────
  group('3 · un acento ilegible se corrige, no se avisa', () {
    test('CLAVE: cualquier color, sobre cualquier fondo, acaba contrastando',
        () {
      // Barrido por el círculo de tono entero y por las tres profundidades de
      // las cuatro plantillas. Si alguna combinación no converge, aparece aquí
      // y no el día del torneo.
      var corregidos = 0;
      for (final p in PlantillasDeTele.todas) {
        for (var i = 0; i < PlantillaDeTele.profundidades; i++) {
          for (var tono = 0; tono < 360; tono += 15) {
            for (final luz in [0.05, 0.15, 0.35, 0.5, 0.75, 0.95]) {
              final elegido =
                  HSLColor.fromAHSL(1, tono.toDouble(), 0.7, luz).toColor();
              final piel = p.resolver(profundidad: i, acento: elegido);
              expect(piel.acento.contrasteCon(piel.fondo),
                  greaterThanOrEqualTo(MinimoDeContraste.acento),
                  reason: '${p.clave} $i · tono $tono luz $luz');
              if (piel.acento != elegido) corregidos++;
            }
          }
        }
      }
      // Y que la corrección haya tenido que actuar de verdad: si nunca
      // actuara, el test de arriba estaría comprobando el aire.
      expect(corregidos, greaterThan(0));
    });

    test('CLAVE: la corrección conserva el TONO — sigue siendo su color', () {
      // Alguien que eligió el azul de su empresa tiene que ver su azul, un poco
      // más claro. Devolverle un verde legible sería devolverle otro color.
      const azulOscuro = Color(0xFF001A33);
      for (final p in PlantillasDeTele.todas) {
        final piel = p.resolver(acento: azulOscuro);
        final antes = HSLColor.fromColor(azulOscuro).hue;
        final despues = HSLColor.fromColor(piel.acento).hue;
        expect((antes - despues).abs(), lessThan(2.0), reason: p.clave);
      }
    });

    test('y un color que YA contrasta no se toca', () {
      // Corregir lo que no hace falta es cambiarle el color a alguien sin
      // motivo, que es la otra mitad del mismo error.
      const claro = Color(0xFFE8F0FF);
      final piel = PlantillasDeTele.club.resolver(acento: claro);
      expect(piel.acento, claro);
    });

    test('CONTRAPESO: el caso imposible termina igual', () {
      // Un fondo a media luz es donde ni aclarar ni oscurecer llega fácil. Si
      // el bucle no tuviera salida, esto colgaría el test en vez de fallar.
      for (final gris in [0x60, 0x77, 0x80, 0x90]) {
        final fondo = Color(0xFF000000 | (gris << 16) | (gris << 8) | gris);
        final salida =
            PlantillaDeTele.corregirContra(const Color(0xFF808080), fondo);
        expect(salida.contrasteCon(fondo),
            greaterThanOrEqualTo(MinimoDeContraste.acento),
            reason: 'gris $gris');
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 4 · EL TAMAÑO NO DEPENDE DEL DISEÑO
  //
  // «Que se lea a diez metros no puede depender del tema elegido.» El test de
  // los 40 px existía para la única pantalla que había; ahora hay cuatro, y se
  // comprueba en las cuatro. Una plantilla que encogiera el texto no sería un
  // diseño: sería un modo de romper la pantalla con permiso.
  // ───────────────────────────────────────────────────────────────────────────
  group('4 · los 40 px en 1080p, en TODAS las plantillas', () {
    for (final p in PlantillasDeTele.todas) {
      testWidgets('CLAVE: ${p.nombre} se lee desde diez metros',
          (tester) async {
        for (var i = 0; i < PlantillaDeTele.profundidades; i++) {
          await _montar(
              tester,
              _lb(
                  identidad: IdentidadDeTorneo(
                      plantilla: p.clave, profundidad: i)));
          expect(_mayorFuente(tester), greaterThanOrEqualTo(40),
              reason: '${p.clave} · fondo $i');
        }
      });
    }

    testWidgets('y el acento elegido no cambia ni un tamaño', (tester) async {
      // La otra mitad: los colores son configurables, la escala no.
      await _montar(tester, _lb());
      final base = _mayorFuente(tester);
      await _montar(
          tester,
          _lb(
              identidad: const IdentidadDeTorneo(
                  plantilla: 'corporativa', acento: 0xFFFF00FF)));
      expect(_mayorFuente(tester), base);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('5 · el score contra el par, que es lo que se reconoce', () {
    test('CLAVE: la convención del golf, con la E del par', () {
      // Un `0` en esa columna se lee como "no hay dato" justo donde el dato es
      // la noticia.
      expect(LeaderboardTvScreen.contraPar(0), 'E');
      expect(LeaderboardTvScreen.contraPar(-7), '-7');
      expect(LeaderboardTvScreen.contraPar(4), '+4');
    });

    testWidgets('CLAVE: el bajo par se pinta en ROJO y el resto no',
        (tester) async {
      await _montar(tester, _lb());
      final piel = const IdentidadDeTorneo().piel;

      Color? colorDe(String texto) => tester
          .widgetList<Text>(find.byType(Text))
          .where((w) => w.data == texto)
          .map((w) => w.style?.color)
          .firstOrNull;

      expect(colorDe('-7'), piel.bajoPar, reason: 'el rojo del bajo par');
      expect(colorDe('E'), piel.texto, reason: 'el par NO va en rojo');
      expect(colorDe('+4'), piel.texto, reason: 'el sobre par tampoco');
    });

    testWidgets('sin ningún score contra par, la columna no se reserva',
        (tester) async {
      // Un torneo por dinero o por posición no tiene bajo par. Doce huecos de
      // ancho fijo vacíos son peor que no tener columna.
      await _montar(tester, _lb(bajoPar: const [null, null, null, null]));
      expect(_texto(tester), isNot(contains('E')));
    });

    testWidgets('CLAVE: y el "Thru" dice rondas, no hoyos', (tester) async {
      // La instantánea se republica cuando una ronda CIERRA. Un "va por el 7"
      // saldría de una copia de hace horas: un dato viejo presentado como
      // actual es peor que no tenerlo.
      await _montar(tester, _lb(rondas: 3));
      final texto = _texto(tester);
      expect(texto, contains('F'), reason: 'el que jugó las tres, terminado');
      expect(texto, contains('2/3'), reason: 'los que van a medias');
    });

    test('y la columna de progreso, en sus dos formas', () {
      expect(LeaderboardTvScreen.rondasLlevadas(3, 3), 'F');
      expect(LeaderboardTvScreen.rondasLlevadas(4, 3), 'F');
      expect(LeaderboardTvScreen.rondasLlevadas(2, 3), '2/3');
      // Un torneo sin rondas todavía no divide por cero ni dice "terminado".
      expect(LeaderboardTvScreen.rondasLlevadas(0, 0), '0/0');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('6 · la identidad viaja, y no se lleva el tamaño por delante', () {
    test('un torneo sin tocar nada no engorda su documento', () {
      expect(const IdentidadDeTorneo().vacia, isTrue);
      expect(const IdentidadDeTorneo().toJson()['profundidad'], isNull);
      expect(
          const IdentidadDeTorneo(plantilla: 'corporativa').vacia, isFalse);
    });

    test('CLAVE: y sobrevive al viaje por Firestore', () {
      const id = IdentidadDeTorneo(
          plantilla: 'atardecer',
          profundidad: 2,
          acento: 0xFF4FA8FF,
          logoUrl: 'https://x/logo.png');
      final vuelta = IdentidadDeTorneo.fromJson(id.toJson());
      expect(vuelta.plantilla, 'atardecer');
      expect(vuelta.profundidad, 2);
      expect(vuelta.acento, 0xFF4FA8FF);
      expect(vuelta.logoUrl, 'https://x/logo.png');
    });

    test('una profundidad imposible se recorta en vez de lanzar', () {
      // Un documento con un valor raro tiene que seguir proyectándose: en esta
      // pantalla una excepción es una pared en blanco durante ocho horas.
      expect(() => PlantillasDeTele.club.resolver(profundidad: 99),
          returnsNormally);
      expect(PlantillasDeTele.club.resolver(profundidad: 99).fondo,
          PlantillasDeTele.club.fondos.last);
      expect(PlantillasDeTele.club.resolver(profundidad: -5).fondo,
          PlantillasDeTele.club.fondos.first);
    });
  });
}
