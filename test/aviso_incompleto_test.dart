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
  group('2 · CRITERIO 2: la causa común se dice una vez', () {
    // Se lee del código porque el widget vive dentro de una pantalla que
    // necesita media app montada, y lo que hay que fijar es la DECISIÓN: una
    // línea por causa, no por apuesta.
    final codigo =
        File('lib/screens/results/results_screen.dart').readAsStringSync();

    test('CLAVE: hay una línea de causa común, con los dos números', () {
      // «18 hoyos en juego y 9 sin anotar» explica de golpe una ronda que se
      // creó de dieciocho. Es el dato que convierte el aviso en diagnóstico.
      expect(codigo, contains('hoyos en juego y'));
      expect(codigo, contains('sin anotar'));
    });

    test('CLAVE: y las apuestas cuya única falta son esos hoyos se callan', () {
      // Era seis veces el mismo ruido. Si a una apuesta solo le faltan los
      // hoyos que nadie anotó, su motivo es el de la ronda.
      expect(
          codigo,
          contains(
              'if (completos + hoyosVacios.length >= enJuego.length) continue;'),
          reason: 'sin esto, seis apuestas repiten una causa');
    });

    test('CONTRAPESO: pero si le falta a ALGUIEN en concreto, se nombra', () {
      // Es el caso para el que este aviso se escribió, y no puede perderse:
      // uno de los tres sin anotar un hoyo que los otros dos sí anotaron.
      expect(codigo, contains(r"falta ${e.value.faltan.join(', ')}"));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 3 · CRITERIO 3: LA GUARDA, con las TRES formas de contar
  //
  // El barrido anterior enumeraba dos. La tercera —contar jugadores— no es
  // errónea: es la pregunta correcta para otro caso. Lo que hay que fijar es
  // que cada una se use donde toca.
  // ───────────────────────────────────────────────────────────────────────────
  group('3 · las tres formas de contar, y cuál va dónde', () {
    List<String> vivas(String ruta, String aguja) => File(ruta)
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .where((l) => l.contains(aguja))
        .toList();

    test('CLAVE: 1 · cuántos HOYOS juega la ronda → hoyosEnJuego', () {
      // Nunca `course.holes`, que son los del campo. Las dos primeras vueltas
      // de este aviso fueron exactamente eso.
      const ruta = 'lib/screens/results/results_screen.dart';
      expect(vivas(ruta, 'segmentsOf(round).hoyosEnJuego'), isNotEmpty);
      expect(vivas(ruta, 'round.course.holes.length'), isEmpty,
          reason: 'los dieciocho del campo no son los de la ronda');
    });

    test('CLAVE: 2 · qué HOYOS no anotó nadie → el hoyo es lo que falta', () {
      const ruta = 'lib/screens/results/results_screen.dart';
      expect(vivas(ruta, 'hoyosVacios'), isNotEmpty,
          reason: 'la tercera forma, y la que faltaba distinguir');
    });

    test('CLAVE: 3 · a qué JUGADOR le falta → solo cuando no es a todos', () {
      // La forma que ya estaba, y que se estaba usando para contestar la
      // pregunta de los hoyos. Sigue, pero acotada.
      const ruta = 'lib/screens/results/results_screen.dart';
      expect(vivas(ruta, 'faltan.add(_nombreCorto(pid))'), isNotEmpty);
    });

    test('CONTRAPESO: y el rango se escribe como rango', () {
      // Nueve números seguidos no se leen. Es una consecuencia de decir los
      // hoyos en vez de los nombres, y merece su propia comprobación.
      final codigo =
          File('lib/screens/results/results_screen.dart').readAsStringSync();
      expect(codigo, contains('static String _rango(Set<int> hoyos)'));
      expect(codigo, contains("'\$desde–\$previo'"),
          reason: '10–18, no 10, 11, 12…');
    });
  });
}
