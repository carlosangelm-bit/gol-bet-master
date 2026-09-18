// ─────────────────────────────────────────────────────────────────────────────
// SNAKE SE REPITE DIEZ VECES
//
// Ronda del 15 Sep, cinco jugadores. En Apuestas:
//
//   Snake · RAFA la agarró en el hoyo 17 con 3 putts. Provisional…   (×4)
//   Snake · CAV la agarró en el hoyo 15 con 3 putts. Provisional…    (×3)
//   Snake · Nadie ha llegado a 3 putts todavía. Quedan 9 hoyos…      (×3)
//
// Diez avisos, uno por duelo. Y tres de ellos dicen que nadie la tiene mientras
// dos jugadores ya la han tenido: cierto para esa pareja, FALSO para la ronda.
//
// ── Dónde estaba, que no es donde parecía ──────────────────────────────────
//
// No es la pantalla iterando pares: `notasDeLiquidacion(round)` se llama UNA
// vez, con la ronda entera. Los diez avisos son diez MÓDULOS de Snake.
//
// Los creó el selector de estructura: `expandBetModules` con `roundRobin` y
// cinco jugadores devuelve C(5,2)=10 módulos 1v1, y no mira el catálogo. La
// marca existe desde hace tiempo —`BetTypeRules.deLaPartida`— y dice
// exactamente esto: «pactar Snake por duelo daría una serpiente por pareja, que
// no es el juego». La leen el asistente de duelos y el editor de grupos
// guardados; el expansor, no.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/engines/settlement_notes.dart';
import 'package:golf_bet_master/models/models.dart';

final _curso = CourseInfo(name: 'P72', holes: [
  for (int i = 1; i <= 18; i++) CourseHole(hole: i, par: 4, strokeIndex: i),
]);

/// El orden importa, y por eso está escrito así.
///
/// El primer duelo que sale de C(5,2) es (CAM, AAM), y ninguno de los dos hace
/// tres putts. Con RAFA y CAV delante, quedarse con los participantes del
/// PRIMER módulo daba por casualidad la respuesta correcta y la unión no se
/// probaba — un contrapeso pasó por eso.
const _cinco = ['cam', 'aam', 'kawa', 'rafa', 'cav'];

/// La ronda del 15 Sep: RAFA hace 3 putts en el 17, CAV en el 15.
///
/// [anotados] los hoyos con tarjeta. Nueve, como en el reporte: por eso los
/// tres avisos decían «provisional» y «quedan 9 hoyos por capturar». El 15 y el
/// 17 están dentro porque ahí es donde la serpiente cambia de dueño.
Round _ronda({
  required List<BetModuleInstance> modulos,
  List<int> anotados = const [1, 2, 3, 4, 5, 6, 7, 15, 17],
}) =>
    Round(
      id: 'r',
      name: '15 Sep',
      course: _curso,
      isFinished: false,
      players: [for (final p in _cinco) Player(id: p, name: p.toUpperCase())],
      roundPlayers: [
        for (final p in _cinco) RoundPlayer(playerId: p, handicapEnRonda: 0),
      ],
      betGroups: [
        BetGroup(
            id: 'g',
            name: 'G',
            format: PartidaFormat.oneVsOne,
            playerIds: _cinco,
            modules: modulos)
      ],
      scores: {
        for (final p in _cinco)
          p: {
            for (final h in anotados)
              h: HoleScore(
                  playerId: p,
                  hole: h,
                  grossScore: 4,
                  putts: (p == 'cav' && h == 15) || (p == 'rafa' && h == 17)
                      ? 3
                      : 2)
          }
      },
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2026, 9, 15),
      totalHoles: 18,
    );

List<BetModuleInstance> _roundRobin(BetModuleType tipo) =>
    BetModuleInstance.expandBetModules(
        type: tipo, structure: BetStructure.roundRobin, participantIds: _cinco);

/// Los diez módulos 1v1 que la ronda del 15 Sep tiene GUARDADOS.
///
/// Se arman a mano porque el expansor ya no los produce. No es una prueba de
/// museo: esa ronda existe, con sus diez módulos dentro, y no hay migración —
/// así que la unión de las notas es lo único que la arregla.
List<BetModuleInstance> _diezGuardados(BetModuleType tipo) => [
      for (int i = 0; i < _cinco.length; i++)
        for (int k = i + 1; k < _cinco.length; k++)
          BetModuleInstance.defaultFor(tipo, [_cinco[i], _cinco[k]],
              id: '${tipo.name}_${_cinco[i]}_${_cinco[k]}'),
    ];

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  group('1 · lo que se veía', () {
    test('CLAVE (la raíz): el expansor ya no parte Snake en diez duelos', () {
      // C(5,2) = 10 era lo que devolvía. El catálogo decía desde antes que esto
      // no se pacta por duelo; el expansor no lo leía.
      expect(BetModuleType.snake.rules.deLaPartida, isTrue);
      final mods = _roundRobin(BetModuleType.snake);
      expect(mods.length, 1);
      expect(mods.single.participantIds, _cinco);
      // Y nace de grupo, no guardando un `roundRobin` que no ocurrió.
      expect(mods.single.structure, BetStructure.group);
    });

    test('CONTRAPESO: una apuesta de duelo SÍ se sigue partiendo', () {
      // Sin esto, «no partas nada» pasaría la prueba de arriba. Nassau se pacta
      // cruce a cruce y ahí diez módulos son diez apuestas de verdad.
      expect(BetModuleType.nassau.rules.deLaPartida, isFalse);
      expect(_roundRobin(BetModuleType.nassau).length, 10);
    });

    test('CLAVE (criterio 1): diez módulos dan UN aviso', () {
      // Eran diez: cuatro «la tiene RAFA», tres «la tiene CAV» y tres «nadie ha
      // llegado». Los módulos siguen siendo diez —no hay migración— y el aviso
      // es uno, porque los diez son la misma apuesta.
      final notas = notasDeLiquidacion(
          _ronda(modulos: _diezGuardados(BetModuleType.snake)));
      expect(notas.length, 1);
    });

    test('CLAVE (criterio 3): y lo que dice es cierto para la PARTIDA', () {
      // Lo que lo volvía falso: un módulo de dos solo ve a dos. En los tres
      // duelos donde no jugaban ni RAFA ni CAV, «nadie ha llegado a 3 putts»
      // era cierto para esa pareja mientras dos jugadores ya la habían tenido.
      //
      // La serpiente es del ÚLTIMO que la agarra, así que sobre los cinco es de
      // RAFA, en el 17 — el más tardío de los dos tripatadas.
      final notas = notasDeLiquidacion(
          _ronda(modulos: _diezGuardados(BetModuleType.snake)));
      expect(notas.single.texto, contains('RAFA la agarró en el hoyo 17'));
      expect(notas.single.texto, isNot(contains('Nadie ha llegado')));
      expect(notas.single.texto, isNot(contains('CAV')),
          reason: 'CAV la tuvo en el 15 y la perdió en el 17');
    });

    test('CONTRAPESO: el PRIMER duelo dice otra cosa, así que la unión cuenta',
        () {
      // (CAM, AAM) es el primero de los diez y ninguno hace tres putts: su
      // aviso solo diría «nadie ha llegado». Si la unión se quedara con los
      // participantes del primero, el aviso de la partida sería ese.
      final soloElPrimero = notasDeLiquidacion(_ronda(
          modulos: [_diezGuardados(BetModuleType.snake).first]));
      expect(soloElPrimero.single.texto, contains('Nadie ha llegado'));
    });

    test('CONTRAPESO: con un solo módulo de los cinco, lo mismo', () {
      // La unión no puede cambiar la respuesta de una apuesta bien creada: es
      // el mismo aviso que si nunca se hubiera partido.
      final unico = notasDeLiquidacion(_ronda(modulos: [
        BetModuleInstance.defaultFor(BetModuleType.snake, _cinco, id: 's')
      ]));
      final partido = notasDeLiquidacion(
          _ronda(modulos: _diezGuardados(BetModuleType.snake)));
      expect(partido.single.texto, unico.single.texto);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('2 · y no es solo Snake: el catálogo dice quiénes', () {
    test('CLAVE: seis tipos son de la partida, y salen de la marca', () {
      // Enumerado del catálogo, no de una lista escrita a mano: una lista a
      // mano es exactamente lo que ya costó seis superficies en la auditoría
      // de importes.
      final dePartida = BetModuleType.values
          .where((t) => t.rules.deLaPartida)
          .map((t) => t.name)
          .toList();
      expect(dePartida,
          ['oyeses', 'units', 'snake', 'rabbit', 'wolf', 'sixes']);
    });

    test('CLAVE: y los seis dejan de partirse, no solo Snake', () {
      // Snake es el que se veía porque es el único de los seis que además
      // habla. En los otros cinco lo que se multiplicaba no era un aviso: era
      // el dinero. Un Oyes en roundRobin eran diez potes.
      //
      // Recorrido del catálogo, así que un tipo nuevo marcado `deLaPartida`
      // entra en la guarda sin tocar esta prueba.
      for (final t in BetModuleType.values.where((t) => t.rules.deLaPartida)) {
        expect(_roundRobin(t).length, 1, reason: t.name);
        expect(_roundRobin(t).single.participantIds, _cinco, reason: t.name);
      }
    });
  });
}
