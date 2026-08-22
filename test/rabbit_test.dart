// ─────────────────────────────────────────────────────────────────────────────
// RABBIT — el conejo empieza suelto y lo captura quien gana un hoyo solo
//
// Dos cosas de la especificación no se podían deducir del resumen y se
// preguntaron, así que quedan FIJADAS aquí —si mañana el documento dice otra
// cosa, estos son los tests que hay que cambiar—:
//
//   1. "En solitario" = neto más bajo ESTRICTAMENTE único.
//   2. Un empate NO suelta el conejo: solo impide capturarlo.
//
// Y los que de verdad protegen algo:
//
//   · El conejo suelto al cerrar → nadie cobra, y se DICE. Mismo problema que
//     el cero de Snake: un tramo sin asientos es indistinguible de uno que no
//     se calculó.
//   · Reinicio en el segundo nueve. Sin él, el dueño del primero cobraría dos
//     veces sin haber cazado nada en el segundo.
//   · Las cuatro variantes apagadas por defecto. Una encendida sin querer
//     cambia el juego y no se nota hasta el cierre.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/rabbit_engine.dart';
import 'package:golf_bet_master/engines/settlement_notes.dart';

const a = 'a', b = 'b', c = 'c', d = 'd';
const todos = [a, b, c, d];

CourseInfo _course([int hoyos = 18]) => CourseInfo(
    name: 'T',
    holes: List.generate(
        hoyos, (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)));

/// Ronda donde [ganadores] dice quién gana cada hoyo en solitario.
///
/// Sin handicap, así que neto = bruto y el ganador es quien tiene menos golpes.
/// El ganador hace 3 y el resto 4; un hoyo sin entrada queda EMPATADO a 4, que
/// es el caso "bloqueado". [sinScore] son hoyos que nadie capturó.
Round _round({
  Map<int, String> ganadores = const {},
  Set<int> sinScore = const {},
  RabbitConfig cfg = RabbitConfig.def,
  int hoyos = 18,
  Map<int, Map<String, int>> brutoExacto = const {},
}) {
  final course = _course(hoyos);
  return Round(
    id: 'r', name: 'R', course: course,
    players: todos.map((i) => Player(id: i, name: i.toUpperCase())).toList(),
    roundPlayers:
        todos.map((i) => RoundPlayer(playerId: i, handicapEnRonda: 0)).toList(),
    betGroups: [
      BetGroup(
          id: 'g', name: 'G',
          format: PartidaFormat.allInOnePot,
          playerIds: todos,
          modules: [
            BetModuleInstance.defaultFor(BetModuleType.rabbit, todos, id: 'rb')
                .copyWith(rabbitConfig: cfg),
          ]),
    ],
    scores: {
      for (final pid in todos)
        pid: {
          for (var h = 1; h <= hoyos; h++)
            if (!sinScore.contains(h))
              h: HoleScore(
                  playerId: pid, hole: h,
                  grossScore: brutoExacto[h]?[pid] ??
                      (ganadores[h] == pid ? 3 : 4)),
        },
    },
    events: const {}, oyeseRankings: const {}, sliding: const [],
    createdAt: DateTime(2026, 1, 1), totalHoles: hoyos,
  );
}

List<RabbitPaso> _pasosDe(Round r, {bool primero = true}) =>
    RabbitEngine.recorrido(r, todos, r.betGroups.first.modules.first.rabbit)
        .segmentos
        .firstWhere((s) => s.primero == primero)
        .pasos;

RabbitSegmento _seg(Round r, {bool primero = true}) =>
    RabbitEngine.recorrido(r, todos, r.betGroups.first.modules.first.rabbit)
        .segmentos
        .firstWhere((s) => s.primero == primero);

RabbitEvento _en(Round r, int hoyo) =>
    _pasosDe(r, primero: hoyo <= 9).firstWhere((p) => p.hoyo == hoyo).evento;

void main() {
  group('1 · "en solitario" es el neto más bajo, único', () {
    test('ganar el hoyo solo captura el conejo suelto', () {
      final r = _round(ganadores: {4: a});
      expect(_en(r, 4), RabbitEvento.capturado);
      expect(_seg(r).dueno, a);
    });

    test('un empate en el MEJOR score no captura', () {
      // Dos a 3 y dos a 4: hay un mejor score compartido. Nadie lo agarra.
      final r = _round(brutoExacto: {
        4: {a: 3, b: 3, c: 4, d: 4}
      });
      expect(_en(r, 4), RabbitEvento.bloqueado);
      expect(_seg(r).dueno, isNull);
    });

    test('empatar el SEGUNDO puesto no impide capturar', () {
      // El que da valor al anterior: lo que importa es que el mejor sea único,
      // no que no haya empates en el hoyo.
      final r = _round(brutoExacto: {
        4: {a: 3, b: 4, c: 4, d: 4}
      });
      expect(_en(r, 4), RabbitEvento.capturado);
      expect(_seg(r).dueno, a);
    });
  });

  group('2 · el empate no suelta el conejo', () {
    test('el dueño lo conserva a través de hoyos empatados', () {
      // La decisión que se preguntó. Con la otra respuesta —el empate lo
      // suelta— aquí el dueño al cerrar sería null.
      final r = _round(ganadores: {4: a}); // 5..9 empatados
      expect(_en(r, 5), RabbitEvento.bloqueado);
      expect(_en(r, 9), RabbitEvento.bloqueado);
      expect(_seg(r).dueno, a, reason: 'A lo conserva hasta el cierre');
    });

    test('y suelto sigue suelto: un empate no lo entrega a nadie', () {
      final r = _round(); // todos empatados
      expect(_seg(r).dueno, isNull);
    });
  });

  group('3 · ganarle al dueño SUELTA el conejo, no lo transfiere', () {
    test('sin robable hacen falta DOS hoyos para arrebatarlo', () {
      final r = _round(ganadores: {4: a, 7: b});
      expect(_en(r, 7), RabbitEvento.soltado);
      expect(_seg(r).dueno, isNull, reason: 'B lo soltó pero no lo tiene');
    });

    test('el segundo hoyo ganado sí lo captura', () {
      final r = _round(ganadores: {4: a, 7: b, 8: b});
      expect(_en(r, 8), RabbitEvento.capturado);
      expect(_seg(r).dueno, b);
    });

    test('el dueño que gana otra vez lo retiene', () {
      final r = _round(ganadores: {4: a, 6: a});
      expect(_en(r, 6), RabbitEvento.retenido);
      expect(_seg(r).dueno, a);
    });

    test('con robable cambia de manos en el acto', () {
      final r = _round(
          ganadores: {4: a, 7: b}, cfg: const RabbitConfig(robable: true));
      expect(_en(r, 7), RabbitEvento.robado);
      expect(_seg(r).dueno, b);
    });
  });

  group('4 · se cobra por segmento, y el segundo nueve empieza de cero', () {
    test('el dueño del cierre cobra a cada uno de los demás', () {
      final r = _round(ganadores: {4: a}, hoyos: 9);
      final e = BetEngine.computeAll(r);
      expect(e, hasLength(3));
      expect(e.every((x) => x.toPlayerId == a), isTrue);
      expect(e.every((x) => x.amount == 100), isTrue);
    });

    test('el conejo se REINICIA: el dueño del primer nueve no cobra el segundo',
        () {
      // Sin reinicio, A cobraría los dos tramos sin haber cazado nada en el
      // segundo. Es el bug más fácil de escribir en este motor.
      final r = _round(ganadores: {4: a});
      expect(_seg(r, primero: true).dueno, a);
      expect(_seg(r, primero: false).dueno, isNull,
          reason: 'el segundo nueve arranca suelto');
      final e = BetEngine.computeAll(r);
      expect(e, hasLength(3), reason: 'solo se cobra un tramo');
    });

    test('dos dueños distintos cobran un tramo cada uno', () {
      final r = _round(ganadores: {4: a, 14: b});
      final e = BetEngine.computeAll(r);
      expect(e.where((x) => x.toPlayerId == a), hasLength(3));
      expect(e.where((x) => x.toPlayerId == b), hasLength(3));
    });

    test('a nueve hoyos no hay un segundo tramo que cobrar', () {
      final r = _round(ganadores: {4: a}, hoyos: 9);
      expect(RabbitEngine.recorrido(r, todos, RabbitConfig.def).segmentos,
          hasLength(1));
    });
  });

  group('5 · el conejo suelto al cerrar: nadie cobra, y se DICE', () {
    test('cero asientos', () {
      final r = _round(); // nadie gana nada
      expect(BetEngine.computeAll(r), isEmpty);
    });

    test('y una nota por tramo que lo explica', () {
      // El caso que el encargo pide explicar. Sin la frase, un tramo sin
      // asientos es indistinguible de uno que no se calculó.
      final notas = notasDeLiquidacion(_round());
      expect(notas, hasLength(2), reason: 'una por cada nueve');
      expect(notas.first.texto, contains('quedó suelto'));
      expect(notas.first.texto, contains('nadie cobra'));
      expect(notas.first.tono, TonoNota.informativa);
    });

    test('con acumular encendido la nota dice a dónde va el importe', () {
      final notas = notasDeLiquidacion(
          _round(cfg: const RabbitConfig(acumula: true)));
      expect(notas.first.texto, contains('pasa al siguiente tramo'));
    });

    test('y el importe acumulado se cobra de verdad en el tramo siguiente', () {
      // Que la nota lo diga no basta: hay que comprobar el dinero.
      final r = _round(
          ganadores: {14: b}, cfg: const RabbitConfig(acumula: true));
      final e = BetEngine.computeAll(r);
      expect(e, hasLength(3));
      expect(e.every((x) => x.amount == 200), isTrue,
          reason: 'los 100 del primer tramo se suman a los 100 del segundo');
    });

    test('sin acumular, ese importe se pierde', () {
      final r = _round(ganadores: {14: b});
      final e = BetEngine.computeAll(r);
      expect(e.every((x) => x.amount == 100), isTrue);
    });

    test('un tramo aún sin jugar no genera nota', () {
      // Decir "quedó suelto en los segundos nueve" antes de jugarlos sería
      // afirmar el resultado de algo que no ha pasado.
      final r = _round(
          ganadores: {4: a},
          sinScore: {for (var h = 10; h <= 18; h++) h});
      final notas = notasDeLiquidacion(r);
      expect(notas, hasLength(1));
      expect(notas.single.texto, contains('primeros 9'));
    });
  });

  group('6 · squirrel exige birdie neto', () {
    test('apagado, ganar el hoyo basta', () {
      // Par 4 y el ganador hace 3: es birdie, así que este fixture no
      // distingue. Se usa un ganador con 4 contra 5 para que NO sea birdie.
      final r = _round(brutoExacto: {
        4: {a: 4, b: 5, c: 5, d: 5}
      });
      expect(_en(r, 4), RabbitEvento.capturado);
    });

    test('encendido, ganar sin birdie no captura', () {
      final r = _round(
          brutoExacto: {
            4: {a: 4, b: 5, c: 5, d: 5}
          },
          cfg: const RabbitConfig(squirrel: true));
      expect(_en(r, 4), RabbitEvento.sinBirdie);
      expect(_seg(r).dueno, isNull);
    });

    test('encendido, ganar CON birdie sí captura', () {
      final r = _round(
          ganadores: {4: a}, cfg: const RabbitConfig(squirrel: true));
      expect(_en(r, 4), RabbitEvento.capturado);
    });

    test('y se explica por qué nadie capturó', () {
      final r = _round(
          brutoExacto: {
            4: {a: 4, b: 5, c: 5, d: 5}
          },
          cfg: const RabbitConfig(squirrel: true));
      expect(notasDeLiquidacion(r).map((n) => n.texto).join(),
          contains('birdie neto'));
    });
  });

  group('7 · las variantes vienen apagadas', () {
    test('el valor por defecto es el estándar en las tres', () {
      const c = RabbitConfig.def;
      expect((c.robable, c.acumula, c.squirrel), (false, false, false));
    });

    test('y el módulo por defecto también', () {
      final m = BetModuleInstance.defaultFor(BetModuleType.rabbit, todos);
      expect(m.rabbit.robable, isFalse);
      expect(m.rabbit.acumula, isFalse);
      expect(m.rabbit.squirrel, isFalse);
    });

    test('solo se serializa lo que se apartó del estándar', () {
      // Así una ronda guardada antes de que existieran las variantes se lee
      // igual, y el JSON dice qué se tocó de verdad.
      expect(RabbitConfig.def.toJson().keys, ['value']);
      expect(const RabbitConfig(squirrel: true).toJson().keys,
          containsAll(['value', 'squirrel']));
    });

    test('el viaje a JSON conserva las tres', () {
      final cfg = const RabbitConfig(
          value: 300, robable: true, acumula: true, squirrel: true);
      final v = RabbitConfig.fromJson(Map<String, dynamic>.from(cfg.toJson()));
      expect((v.value, v.robable, v.acumula, v.squirrel),
          (300.0, true, true, true));
    });
  });

  group('8 · hoyos sin capturar', () {
    test('no deciden nada y el tramo queda provisional', () {
      final r = _round(ganadores: {4: a}, sinScore: {8, 9});
      final seg = _seg(r);
      expect(seg.hoyosSinCapturar, 2);
      expect(seg.completo, isFalse);
      expect(notasDeLiquidacion(r).first.tono, TonoNota.provisional);
    });

    test('un ganador en un hoyo sin capturar no mueve el conejo', () {
      final r = _round(ganadores: {4: a, 8: b}, sinScore: {8});
      expect(_en(r, 8), RabbitEvento.sinScore);
      expect(_seg(r).dueno, a);
    });
  });
}
