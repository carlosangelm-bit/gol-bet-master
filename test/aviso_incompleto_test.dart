// ─────────────────────────────────────────────────────────────────────────────
// EL AVISO DE SCORE INCOMPLETO — tercera vuelta, y no era la cuenta
//
// «Merece la pena preguntarse por qué el barrido no lo encuentra.»
//
// Porque no había nada que encontrar. La cuenta estaba bien: con nueve hoyos
// declarados y nueve anotados el aviso NO aparece — es lo primero que este
// fichero comprueba, y lo que las dos veces anteriores faltaba.
//
// ── Lo que pasaba de verdad ─────────────────────────────────────────────────
//
// La ronda tenía DIECIOCHO hoyos en juego. `singleNine` es
// `totalHoles <= 9 && !secondPlayed`, así que hay dos maneras de que una ronda
// «de nueve» tenga dieciocho en juego:
//
//   · se creó como de dieciocho y se dejó en nueve
//   · hay un score suelto en el segundo segmento
//
// En los dos casos el aviso decía LA VERDAD. Lo que estaba mal era cómo:
// nombraba jugadores cuando lo que falta son hoyos, y lo repetía seis veces
// para una sola causa.
//
// ── Y LAS TRES FORMAS DE CONTAR, enumeradas ─────────────────────────────────
//
// El barrido anterior buscaba dos: `course.holes` y `hoyosEnJuego`. La tercera
// es esta —contar JUGADORES sin score— y no es una forma equivocada: es la
// pregunta correcta para otro caso. Lo que hacía falta era distinguir cuándo se
// hace cada una, y eso es lo que fija el grupo 3.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/models/models.dart';

const _tres = ['cam', 'rich', 'dylan'];
const _nombres = {'cam': 'CAM', 'rich': 'RICH', 'dylan': 'Dylan'};

/// Una ronda con los hoyos anotados que se digan, por jugador.
Round _ronda({
  required int totalHoles,
  Map<String, List<int>> porJugador = const {},
  List<int> todos = const [],
}) {
  final ps = _tres.map((i) => Player(id: i, name: _nombres[i]!)).toList();
  return Round(
    id: 'r',
    name: 'Nueve del sábado',
    course: CourseInfo(
        name: 'C',
        holes: List.generate(
            18, (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1))),
    players: ps,
    roundPlayers:
        ps.map((p) => RoundPlayer(playerId: p.id, handicapEnRonda: 0)).toList(),
    betGroups: [
      BetGroup(
          id: 'g',
          name: 'G',
          format: PartidaFormat.allInOnePot,
          playerIds: _tres,
          modules: [
            BetModuleInstance.defaultFor(BetModuleType.nassau, _tres, id: 'n'),
            BetModuleInstance.defaultFor(BetModuleType.medal, _tres, id: 'm'),
          ]),
    ],
    scores: {
      for (final p in ps)
        p.id: {
          for (final h in porJugador[p.id] ?? todos)
            h: HoleScore(playerId: p.id, hole: h, grossScore: 4),
        },
    },
    events: const {},
    oyeseRankings: const {},
    sliding: const [],
    createdAt: DateTime(2026, 9, 2),
    totalHoles: totalHoles,
  );
}

const _nueve = [1, 2, 3, 4, 5, 6, 7, 8, 9];

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('1 · CRITERIO 1: una ronda de nueve completa no avisa de nada', () {
    test('CLAVE: nueve declarados y nueve anotados son NUEVE en juego', () {
      // Es la sonda que dice que la cuenta está bien. Las dos veces anteriores
      // este era el fallo; esta vez no lo era.
      final s = BetEngine.segmentsOf(_ronda(totalHoles: 9, todos: _nueve));
      expect(s.singleNine, isTrue);
      expect(s.hoyosEnJuego.length, 9);
      // Y por tanto no hay hoyo sin anotar: nada que avisar.
      for (final h in s.hoyosEnJuego) {
        expect(_tres.every((p) => _ronda(totalHoles: 9, todos: _nueve).getScore(p, h).hasScore),
            isTrue);
      }
    });

    test('CLAVE: y las DOS maneras de que una «de nueve» tenga dieciocho', () {
      // `singleNine` es `totalHoles <= 9 && !secondPlayed`. Las dos puertas.
      final creadaDe18 = BetEngine.segmentsOf(
          _ronda(totalHoles: 18, todos: _nueve));
      expect(creadaDe18.singleNine, isFalse);
      expect(creadaDe18.hoyosEnJuego.length, 18,
          reason: 'se creó de dieciocho y se dejó en nueve');

      final conSuelto = BetEngine.segmentsOf(
          _ronda(totalHoles: 9, todos: [..._nueve, 12]));
      expect(conSuelto.singleNine, isFalse);
      expect(conSuelto.hoyosEnJuego.length, 18,
          reason: 'un score suelto en el segundo segmento');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 2 · LA GUARDA QUE NO MORDIÓ, Y POR QUÉ
  //
  // Aquí había dos grupos más. Comprobaban el TEXTO FUENTE de
  // `results_screen.dart`: que contuviera «hoyos en juego y», que la línea del
  // `continue` estuviera escrita, que existiera `_rango`. Todos en verde
  // mientras el aviso volvía por cuarta vez.
  //
  // No es mala suerte: una prueba que lee el código no puede contradecirlo.
  // Comprueba que una decisión está ESCRITA, no que sea CIERTA — y la cuarta
  // vuelta no fue una decisión que se borrara, fue un caso que ninguna de ellas
  // cubría (un score suelto en el hoyo 10). Se escribieron así porque la cuenta
  // vivía dentro de un `build()` y no había forma de llamarla.
  //
  // Ya la hay: `avisosDeScoreIncompleto`. Lo que decían estos dos grupos está
  // ahora en `aviso_score_incompleto_test.dart` y `aviso_en_pantalla_test.dart`,
  // ejecutando la cuenta en vez de leerla.
  //
  // Queda una sola comprobación estructural, y es la que sí puede ganar algo:
  // que no nazca OTRA superficie contando los dieciocho del campo. Eso no es
  // una decisión que se pueda ejecutar — es la ausencia de código.
  // ───────────────────────────────────────────────────────────────────────────
  group('2 · que no nazca otra cuenta de cobertura', () {
    test('CLAVE: nadie mide cobertura con los hoyos del CAMPO', () {
      // Lo que se busca es ESTRECHO a propósito: `course.holes.length` usado
      // como denominador de algo que mira scores. «9 de 18» en una ronda de
      // nueve es exactamente lo que trajo el aviso las dos primeras veces, y
      // se acaba de encontrar otra vez en el volcado de diagnóstico.
      //
      // No se busca `course.holes` a secas. Recorrer los hoyos del campo
      // saltándose los que no tienen score da el mismo resultado se jueguen
      // nueve o dieciocho, y ensanchar esto para cazarlos llena la lista de
      // casos correctos —se probó: siete, y solo uno era un fallo—. Un barrido
      // que grita siempre se termina ignorando.
      final sospechosas = <String>[];
      var vistos = 0;
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        vistos++;
        final lineas = f.readAsLinesSync();
        for (var i = 0; i < lineas.length; i++) {
          if (!lineas[i].contains('hasScore')) continue;
          if (lineas[i].trimLeft().startsWith('//')) continue;
          final desde = i - 5 < 0 ? 0 : i - 5;
          final hasta = i + 5 >= lineas.length ? lineas.length - 1 : i + 5;
          for (var j = desde; j <= hasta; j++) {
            if (lineas[j].trimLeft().startsWith('//')) continue;
            if (lineas[j].contains('course.holes.length')) {
              sospechosas.add('${f.path}:${j + 1}  ${lineas[j].trim()}');
            }
          }
        }
      }
      expect(vistos, greaterThan(50),
          reason: 'si el barrido deja de ver ficheros, deja de valer');
      expect(sospechosas, isEmpty,
          reason: 'los dieciocho del campo no son los que juega la ronda');
    });
  });
}
