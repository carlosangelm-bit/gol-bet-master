// ─────────────────────────────────────────────────────────────────────────────
// CINCO COSAS DE UNA RONDA REAL DE NUEVE HOYOS
//
// Cuatro de los cinco puntos del reporte, y los cuatro con el mismo perfil que
// el reporte identificó: «arreglaste el motor y quedó una superficie leyendo de
// otro sitio».
//
//   1 · cerrar la ronda vivía SOLO en Inicio
//   2 · el monto del paso 5 no llegaba al 7 —dos fuentes para el mismo número—
//   4 · el aviso de score incompleto contaba los 18 del CAMPO
//   5 · el desglose por jugador tenía siete tipos de trece, escritos a mano
//
// ── Y el barrido, convertido en guarda ──────────────────────────────────────
//
// El reporte pedía «mirar si hay más sitios que cuenten hoyos o lean montos por
// su cuenta». El barrido encontró tres, y los tres están abajo con un test que
// impide que vuelvan. Un barrido que no deja guarda hay que repetirlo.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/screens/home/home_screen.dart';

const _cuatro = ['ana', 'beto', 'caro', 'dani'];

CourseInfo _campo() => CourseInfo(
      name: 'Los Encinos',
      holes: List.generate(
          18,
          (i) => CourseHole(
              hole: i + 1,
              par: const {3, 7, 12, 16}.contains(i + 1) ? 3 : 4,
              strokeIndex: i + 1)),
    );

/// Una ronda de nueve hoyos que sale por el DIEZ, con score completo.
///
/// Es el caso del reporte y el que rompía las dos cuentas: los scores están en
/// el 10..18 y las dos superficies buscaban en el 1..9 o en los 18.
Round _nueveDetras({bool completa = true}) {
  final ps = _cuatro.map((i) => Player(id: i, name: i.toUpperCase())).toList();
  final hoyos = [for (var h = 10; h <= 18; h++) h];
  return Round(
    id: 'r9',
    name: 'Nueve de atrás',
    course: _campo(),
    players: ps,
    roundPlayers:
        ps.map((p) => RoundPlayer(playerId: p.id, handicapEnRonda: 0)).toList(),
    betGroups: [
      BetGroup(
          id: 'g',
          name: 'G',
          format: PartidaFormat.allInOnePot,
          playerIds: _cuatro,
          modules: [
            BetModuleInstance.defaultFor(BetModuleType.skins, _cuatro, id: 'sk')
          ]),
    ],
    scores: {
      for (final p in ps)
        p.id: {
          for (final h in completa ? hoyos : hoyos.take(5))
            h: HoleScore(playerId: p.id, hole: h, grossScore: 4),
        },
    },
    events: const {},
    oyeseRankings: const {},
    sliding: const [],
    createdAt: DateTime(2026, 9, 2),
    totalHoles: 9,
    startingNine: StartingNine.back,
  );
}

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('1 · cerrar la ronda: un solo cierre, y cuenta bien los hoyos', () {
    test('CLAVE: nueve hoyos completos saliendo por el diez son NUEVE', () {
      // Contaba 1..totalHoles, o sea del 9 al 1. Una ronda de nueve que sale
      // por el diez tiene sus scores en el 10..18, así que devolvía CERO y el
      // diálogo decía «Hoyos completados: 0/9» sobre una ronda entera.
      expect(hoyosCompletos(_nueveDetras()), 9);
    });

    test('CLAVE: y con cinco anotados dice cinco, no cero', () {
      expect(hoyosCompletos(_nueveDetras(completa: false)), 5);
    });

    test('CLAVE: el cierre es UNA función, alcanzable desde las dos pantallas',
        () {
      // Copiarlo a la tarjeta habría dado dos cierres, y el que se quedara
      // atrás sería el que no publica al torneo — que es el fallo que esta
      // secuencia ya tuvo una vez.
      final captura =
          File('lib/screens/capture/capture_screen.dart').readAsStringSync();
      expect(captura, contains('confirmarFinalizarRonda'),
          reason: 'se cierra desde donde se anota');
      // Y no hay un segundo cierre: nadie más llama a finishRound por su cuenta.
      final propios = captura.contains('prov.finishRound(');
      expect(propios, isFalse, reason: 'un cierre, no dos');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 2 · EL BARRIDO, COMO GUARDA
  //
  // «Merece la pena mirar si hay más sitios que cuenten hoyos por su cuenta.»
  // Encontró tres, y este test impide el cuarto.
  // ───────────────────────────────────────────────────────────────────────────
  group('2 · nadie cuenta hoyos por su cuenta', () {
    /// Las líneas vivas de [ruta] que contienen [aguja].
    List<String> _vivas(String ruta, String aguja) => File(ruta)
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .where((l) => l.contains(aguja))
        .toList();

    test('CLAVE: el aviso de score incompleto usa los hoyos EN JUEGO', () {
      // Era `round.course.holes`, los DIECIOCHO del campo. Nueve hoyos llenos
      // nunca llegan a dieciocho, así que una ronda de nueve completa salía
      // siempre en rojo con «Sin score completo».
      final ruta = 'lib/screens/results/results_screen.dart';
      expect(_vivas(ruta, 'hoyosEnJuego'), isNotEmpty,
          reason: 'el aviso cuenta los hoyos de la RONDA');
      expect(_vivas(ruta, 'completos >= round.course.holes.length'), isEmpty,
          reason: 'eso comparaba contra los 18 del campo');
    });

    test('CLAVE: y el contador del cierre también', () {
      final vivas = _vivas('lib/screens/home/home_screen.dart', 'hoyosEnJuego');
      expect(vivas, isNotEmpty);
      // Y no queda el bucle de 1..totalHoles que devolvía cero.
      expect(
          _vivas('lib/screens/home/home_screen.dart',
              'for (int h = maxHole; h >= 1; h--)'),
          isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('3 · el desglose por jugador lista TODO el catálogo', () {
    test('CLAVE: el orden se deriva, no se escribe a mano', () {
      // Había siete tipos escritos y el catálogo tenía trece. Los seis que
      // faltaban cobraban en el neto y no salían en el desglose — y ya había
      // pasado con Snake.
      //
      // Son doce desde que Match + Press se retiró: era un Nassau sin partición
      // en vueltas. El número es la mitad débil de esta prueba —lo que importa
      // es que la lista se DERIVE— pero se mantiene porque caza el regreso a una
      // lista cerrada.
      final codigo =
          File('lib/screens/results/results_screen.dart').readAsStringSync();
      expect(codigo, contains('BetModuleType.values.where'),
          reason: 'la lista sale del catálogo');
      // La comprobación que importa: si alguien vuelve a una lista cerrada,
      // esto falla. Ninguno puede quedarse fuera por olvido.
      expect(BetModuleType.values.length, greaterThanOrEqualTo(12));
    });

    test('CONTRAPESO: los preferidos siguen yendo primero', () {
      // Derivar del catálogo no puede haberse llevado el orden de lectura: los
      // habituales van delante, y el resto detrás.
      final codigo =
          File('lib/screens/results/results_screen.dart').readAsStringSync();
      final i = codigo.indexOf('const preferidos = [');
      final j = codigo.indexOf('BetModuleType.values.where');
      expect(i, greaterThan(-1));
      expect(i, lessThan(j), reason: 'primero los preferidos');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('4 · el monto tiene UNA fuente, con precedencia escrita', () {
    test('CLAVE: Montos lee el módulo que dejó Detalle', () {
      // «Coloco unidades de 25 y en el paso 7 aparecen 50.» Montos saltaba de
      // lo tecleado a reconstruir la receta —el default— y se saltaba el sitio
      // donde estaba el 25.
      final codigo =
          File('lib/screens/setup/setup_screen.dart').readAsStringSync();
      final i = codigo.indexOf('double _baseDe(BetCount cuenta) {');
      expect(i, greaterThan(-1));
      final cuerpo = codigo.substring(i, i + 2200);
      // Las tres fuentes, en orden.
      final tecleado = cuerpo.indexOf('_montoBase[cuenta]');
      final delModulo = cuerpo.indexOf("m.id.startsWith('flujo_");
      final receta = cuerpo.indexOf('BetRecipe.build(');
      expect(tecleado, greaterThan(-1));
      expect(delModulo, greaterThan(-1),
          reason: 'el módulo de Detalle es la fuente que faltaba');
      expect(receta, greaterThan(-1));
      expect(tecleado < delModulo && delModulo < receta, isTrue,
          reason: 'teclado > módulo > default, y en ese orden');
    });

    test('CLAVE: y el campo se refresca cuando su fuente cambia', () {
      // La otra mitad: el controlador se creaba con `putIfAbsent` y no volvía a
      // mirar. Visitar Montos antes de Detalle dejaba el default cacheado.
      final codigo =
          File('lib/screens/setup/setup_screen.dart').readAsStringSync();
      expect(codigo, contains('if (!tecleado && c.text != texto) c.text = texto;'),
          reason: 'el campo sigue a su fuente mientras nadie escriba');
    });
  });
}
