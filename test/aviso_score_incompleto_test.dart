// ─────────────────────────────────────────────────────────────────────────────
// EL AVISO DE SCORE INCOMPLETO — la cuarta vez
//
// Vuelve desde una ronda REAL de nueve hoyos, cerrada y liquidada:
//
//     ⊘ Sin score completo: Nassau · falta CAM, RICH, Dylan   (×6, una por
//                                                              apuesta)
//
// Y los tres que nombra son los mismos que aparecen LIQUIDADOS justo debajo.
//
// Las tres veces anteriores se arreglaron contando hoyos mejor. Esta no va de
// contar: va de que la cuenta vivía dentro de un `build()`, donde ninguna
// prueba llega y ningún barrido por estructura la reconoce como una cuenta.
// Por eso estas pruebas existen: la cuenta ya está fuera.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/score_incompleto.dart';

final _curso = CourseInfo(name: 'P72', holes: [
  for (int i = 1; i <= 18; i++) CourseHole(hole: i, par: 4, strokeIndex: i),
]);

const _cinco = ['cam', 'rich', 'kawa', 'aam', 'dylan'];

/// La ronda de Carlos: cinco jugadores, seis apuestas, nueve hoyos anotados.
///
/// [totalHoles] es la pregunta del caso: se declaró de 18 o de 9.
/// [hasta] los hoyos con score.
Round _r({
  int totalHoles = 18,
  int hasta = 9,
  bool isFinished = true,
  List<String> sinScore = const [],
}) =>
    Round(
      id: 'r',
      name: '28 Jul',
      course: _curso,
      isFinished: isFinished,
      players: [
        for (final p in _cinco) Player(id: p, name: p.toUpperCase()),
      ],
      roundPlayers: [
        for (final p in _cinco) RoundPlayer(playerId: p, handicapEnRonda: 0),
      ],
      betGroups: [
        BetGroup(
          id: 'g',
          name: 'G',
          format: PartidaFormat.oneVsOne,
          playerIds: _cinco,
          modules: [
            for (final t in const [
              BetModuleType.nassau,
              BetModuleType.skins,
              BetModuleType.snake,
              BetModuleType.medal,
              BetModuleType.rabbit,
              BetModuleType.oyeses,
            ])
              BetModuleInstance(
                  id: t.name,
                  type: t,
                  name: t.label,
                  participantIds: t == BetModuleType.nassau
                      ? const ['cam', 'rich', 'kawa']
                      : _cinco),
            // Un SEGUNDO Nassau con OTROS participantes, a propósito.
            //
            // Con los mismos cinco no serviría de nada: unir los nombres de los
            // dos módulos y quedarse con los del último dan lo mismo. Partidos
            // —tres contra dos— solo la unión nombra a los dos que faltan.
            BetModuleInstance(
                id: 'nassau2',
                type: BetModuleType.nassau,
                name: 'Nassau de los otros dos',
                participantIds: const ['aam', 'dylan']),
          ],
        )
      ],
      scores: {
        for (final p in _cinco)
          p: {
            for (int h = 1; h <= hasta; h++)
              if (!sinScore.contains(p))
                h: HoleScore(playerId: p, hole: h, grossScore: 4, putts: 2)
          }
      },
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2026, 7, 28),
      totalHoles: totalHoles,
    );

/// Un score SUELTO en el segundo segmento, que es la otra rama que el propio
/// código nombraba: «o hay un score suelto en el segundo segmento, que es lo
/// que hace que `singleNine` deje de ser cierto».
Round _conScoreSuelto(List<String> quienes, int hoyo) {
  final base = _r(totalHoles: 9);
  return base.copyWith(scores: {
    for (final p in _cinco)
      p: {
        ...base.scores[p]!,
        if (quienes.contains(p))
          hoyo: HoleScore(playerId: p, hole: hoyo, grossScore: 4, putts: 2),
      }
  });
}

List<String> _avisos(Round r) =>
    avisosDeScoreIncompleto(r, nombreCorto: (p) => p.toUpperCase());

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  group('una ronda de nueve completa no se queja de nada', () {
    test('declarada de nueve — el caso que ya estaba cubierto', () {
      expect(_avisos(_r(totalHoles: 9)), isEmpty);
    });

    test('declarada de nueve y ABIERTA: tampoco, y esto es lo que prueba que se '
        'miran los hoyos EN JUEGO y no los del campo', () {
      // Cerrada, la regla de arriba —una ronda terminada no tiene hoyos
      // pendientes— tapa este fallo: contar los dieciocho del campo daría nueve
      // hoyos vacíos, y al estar cerrada se callarían igual. Abierta no hay
      // dónde esconderse: si se cuentan los del campo, salen los del 10 al 18.
      expect(_avisos(_r(totalHoles: 9, isFinished: false)), isEmpty);
    });

    test('cerrada, con un jugador que NO anotó: una línea, no seis', () {
      // Lo que se pierde al dar una sola línea en una ronda cerrada sería el
      // nombre. No se pierde: va en la misma línea, detrás del hoyo.
      expect(_avisos(_r(totalHoles: 9, sinScore: ['dylan'])),
          ['Se cerró con 9 hoyos a medias (1–9) · sin score: DYLAN']);
    });

    test('declarada de DIECIOCHO y cerrada en el nueve — el caso de Carlos', () {
      // `singleNine` pide `totalHoles <= 9`, así que una ronda creada de
      // dieciocho y cerrada al terminar el F9 tiene "en juego" los dieciocho.
      // Los nueve de atrás salían como hoyos sin anotar, y como NADIE los
      // anotó, todos los jugadores faltaban en todos: de ahí «falta CAM, RICH,
      // Dylan» en vez de «faltan los hoyos 10 al 18».
      //
      // Una ronda CERRADA no tiene hoyos pendientes. Terminó con nueve.
      expect(_avisos(_r(totalHoles: 18)), isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('un score suelto en el segundo nueve', () {
    test('no convierte una ronda cerrada de nueve en una queja de tres', () {
      // ESTA es la forma del mensaje de Carlos: «falta CAM, RICH, Dylan», no
      // «faltan los hoyos 10 al 18». Un solo score en el 10 basta.
      //
      // `singleNine` deja de ser cierto → dieciocho hoyos en juego. El 10 ya no
      // está vacío, así que no es la causa común: son los tres que no lo
      // anotaron los que «faltan». Y como el 11 al 18 sí están vacíos, la
      // apuesta tampoco se descarta por completa.
      final av = _avisos(_conScoreSuelto(['kawa', 'aam'], 10));
      expect(av, ['Se cerró con 1 hoyo a medias (10) · sin score: CAM, RICH, DYLAN'],
          reason: 'UNA línea, con el hoyo delante: «(10)» señala el score suelto');
    });

    test('abierta sí se dice, y nombra a los tres', () {
      final r = _conScoreSuelto(['kawa', 'aam'], 10).copyWith(isFinished: false);
      final av = _avisos(r);
      expect(av.join(' | '), contains('CAM'));
      expect(av.join(' | '), contains('RICH'));
      expect(av.join(' | '), contains('DYLAN'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('y sigue avisando cuando de verdad falta algo', () {
    test('abierta y a medias: lo dice UNA vez, y nombra hoyos', () {
      final av = _avisos(_r(totalHoles: 18, isFinished: false));
      expect(av.length, 1, reason: 'una causa común, no una línea por apuesta');
      expect(av.single, contains('10–18'));
      expect(av.single, isNot(contains('CAM')),
          reason: 'faltan hoyos, no personas');
    });

    test('un jugador sin anotar sí se nombra, y una sola vez por tipo', () {
      // Abierta a propósito: es la ronda que se está capturando, donde saber a
      // QUIÉN le falta es lo accionable. Cerrada se dice en una sola línea.
      // Uno de cada Nassau: RICH juega el de tres, DYLAN el de dos.
      final av = _avisos(
          _r(totalHoles: 9, isFinished: false, sinScore: ['rich', 'dylan']));
      expect(av.every((l) => l.contains('DYLAN')), isTrue);
      // SIETE apuestas, seis tipos: los dos Nassau dan una sola línea.
      expect(av.length, 6, reason: 'seis tipos distintos, no siete apuestas');
      expect(av.toSet().length, av.length, reason: 'ninguna línea repetida');
      expect(av.where((l) => l.startsWith(BetModuleType.nassau.label)).length, 1);
      // Los dos Nassau se juntan en una línea que SIGUE nombrando a quien
      // falta. La forma alternativa —«sin score en 2 duelos»— lo escondía.
      expect(av.first, '${BetModuleType.nassau.label} · falta RICH, DYLAN',
          reason: 'los dos Nassau se UNEN; quedarse con el último perdería uno');
    });
  });
}
