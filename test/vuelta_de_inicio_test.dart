// ─────────────────────────────────────────────────────────────────────────────
// "LA RONDA EMPIEZA EN EL HOYO 1" — un supuesto que la app misma desmiente
//
// La app ofrece salir por el 10 desde el diálogo de inicio, y la ronda del 28 de
// agosto que auditamos salió así. Este test recorre los formatos que dependen de
// la vuelta y fija cuál es el orden que manda.
//
// Lo que había, medido:
//
//   · SNAKE ordenaba los hoyos por NÚMERO y buscaba "el último" hacia atrás. Con
//     salida por el 10 eso hace que el último sea el 18, que se juega noveno.
//     Con A haciendo 3 putts en el 16 y B en el 5 —el 5 es el último jugado— la
//     serpiente se le quedaba a A y A le pagaba a B. El dinero al revés.
//   · PUTTS partía en 1-9 y 10-18 fijos, así que en la misma partida repartía
//     al revés que Nassau, que sí usa segmentsOf.
//   · RABBIT ya usaba segmentsOf. Comprobado, no supuesto.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';
import 'package:golf_bet_master/engines/settlement_notes.dart';

final _curso = CourseInfo(name: 'P72', holes: [
  for (int i = 1; i <= 18; i++) CourseHole(hole: i, par: 4, strokeIndex: i),
]);

Round _r(StartingNine inicio, Map<String, List<int>> tresPutts) => Round(
      id: 'r',
      name: 'R',
      course: _curso,
      isFinished: true,
      players: [for (final p in tresPutts.keys) Player(id: p, name: p)],
      roundPlayers: [
        for (final p in tresPutts.keys)
          RoundPlayer(playerId: p, handicapEnRonda: 0)
      ],
      betGroups: [
        BetGroup(
            id: 'g',
            name: 'G',
            format: PartidaFormat.allInOnePot,
            playerIds: tresPutts.keys.toList(),
            modules: [
              BetModuleInstance(
                  id: 's',
                  type: BetModuleType.snake,
                  name: 'Snake',
                  participantIds: const [],
                  snakeConfig: const SnakeConfig(value: 100)),
              BetModuleInstance(
                  id: 'p',
                  type: BetModuleType.putts,
                  name: 'Putts',
                  participantIds: const [],
                  puttsConfig: const PuttsConfig(
                      value: 50, puttsMode: PuttsMode.perHole)),
            ])
      ],
      scores: {
        for (final e in tresPutts.entries)
          e.key: {
            for (int h = 1; h <= 18; h++)
              h: HoleScore(
                  playerId: e.key,
                  hole: h,
                  grossScore: 4,
                  putts: e.value.contains(h) ? 3 : 2)
          }
      },
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2026, 8, 28),
      totalHoles: 18,
      startingNine: inicio,
    );

List<LedgerEntry> _de(Round r, BetModuleType t) {
  LedgerEngine.invalidateCache();
  return LedgerEngine.entriesOf(r).where((e) => e.betType == t).toList();
}

void main() {
  group('1 · el orden de juego manda', () {
    test('con salida por el 10, el orden es 10..18 y luego 1..9', () {
      final segs = BetEngine.segmentsOf(_r(StartingNine.back, {'A': []}));
      expect(segs.playOrder.first, 10);
      expect(segs.playOrder.last, 9);
      expect(segs.firstNine.first, 10);
    });
  });

  group('2 · SNAKE se la queda el último que JUGÓ', () {
    test('salida por el 10: el 3-putt del hoyo 5 es posterior al del 16', () {
      // El 5 se juega decimocuarto; el 16, noveno.
      final r = _r(StartingNine.back, {
        'A': [16],
        'B': [5]
      });
      final e = _de(r, BetModuleType.snake).single;
      expect(e.fromPlayerId, 'B', reason: 'B tiene la serpiente y paga');
      expect(e.toPlayerId, 'A');
      expect(e.reason, contains('H5'));
    });

    test('y el contrapeso: por el 1, el último es el 16', () {
      final r = _r(StartingNine.front, {
        'A': [16],
        'B': [5]
      });
      final e = _de(r, BetModuleType.snake).single;
      expect(e.fromPlayerId, 'A');
      expect(e.reason, contains('H16'));
    });

    test('la nota y el ledger dicen el MISMO hoyo', () {
      // Es la razón por la que el motor expone la búsqueda: dos recorridos
      // podrían discrepar y la pantalla diría un dueño y el libro cobraría a
      // otro.
      final r = _r(StartingNine.back, {
        'A': [16],
        'B': [5]
      });
      final notas = notasDeLiquidacion(r).join(' ');
      if (notas.isNotEmpty) {
        expect(notas.contains('16'), isFalse,
            reason: 'la nota no puede citar el hoyo que ya no es');
      }
      expect(_de(r, BetModuleType.snake).single.reason, contains('H5'));
    });
  });

  group('3 · PUTTS parte la ronda como Nassau', () {
    test('el primer segmento son los nueve que se jugaron primero', () {
      final r = _r(StartingNine.back, {
        'A': [16],
        'B': [5]
      });
      final ps = _de(r, BetModuleType.putts);
      final primero = ps.firstWhere((e) => e.reason.contains('F9'));
      // A hizo el 3-putt en el 16, que está en la PRIMERA vuelta jugada, así que
      // A pierde ese segmento.
      expect(primero.fromPlayerId, 'A');
      expect(primero.reason, contains('H10–H18'));
    });

    test('y por el 1 la etiqueta se queda como siempre', () {
      final r = _r(StartingNine.front, {
        'A': [16],
        'B': [5]
      });
      final ps = _de(r, BetModuleType.putts);
      expect(ps.map((e) => e.reason).toSet(), {'Putts F9', 'Putts B9'});
    });
  });

  group('3b · y la pantalla dice qué vuelta es cada segmento', () {
    test('con salida por el 10 hay aclaración, con los hoyos', () {
      // La etiqueta del asiento lleva el rango pegado, pero eso solo se ve en
      // el desglose. Los chips del duelo y la tarjeta de Apuestas solo tienen
      // sitio para "F9", así que la aclaración va debajo, una vez.
      final segs = BetEngine.segmentsOf(_r(StartingNine.back, {'A': []}));
      final a = segs.aclaracionDeVueltas(StartingNine.back);
      expect(a, isNotNull);
      expect(a, contains('hoyos 10-18'));
      expect(a, contains('se jugó primero'));
      expect(a, contains('hoyos 1-9'));
    });

    test('y por el 1 no hay ninguna: ahí no hay nada que aclarar', () {
      // Un aviso que sale siempre deja de leerse.
      final segs = BetEngine.segmentsOf(_r(StartingNine.front, {'A': []}));
      expect(segs.aclaracionDeVueltas(StartingNine.front), isNull);
    });
  });

  group('4 · las etiquetas no engañan, y no pierden la palabra de siempre', () {
    test('por el 10 se añade la vuelta y el rango', () {
      final segs = BetEngine.segmentsOf(_r(StartingNine.back, {'A': []}));
      expect(segs.etiqueta(true, StartingNine.back),
          'Front 9 · 1ª vuelta (H10–H18)');
      expect(segs.etiqueta(false, StartingNine.back),
          'Back 9 · 2ª vuelta (H1–H9)');
    });

    test('por el 1 no se añade nada: ahí no engaña', () {
      final segs = BetEngine.segmentsOf(_r(StartingNine.front, {'A': []}));
      expect(segs.etiqueta(true, StartingNine.front), 'Front 9');
      expect(segs.etiqueta(false, StartingNine.front), 'Back 9');
    });

    test('la palabra canónica sobrevive: quien busca "Front 9" la encuentra',
        () {
      final segs = BetEngine.segmentsOf(_r(StartingNine.back, {'A': []}));
      expect(segs.etiqueta(true, StartingNine.back), contains('Front 9'));
    });
  });
}
