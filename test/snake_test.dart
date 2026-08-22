// ─────────────────────────────────────────────────────────────────────────────
// SNAKE — el último 3-putt de la ronda paga a todos
//
// Los tres casos borde del encargo son los tests que importan, porque son los
// tres sitios donde el formato puede mentir sin fallar:
//
//   · Nadie hace 3-putt → no se paga NADA, y hay que decirlo. Un cero
//     silencioso se lee como un fallo del cálculo.
//   · Empate en el último hoyo → el resultado no puede depender del orden de la
//     lista de jugadores.
//   · Ronda incompleta → "el último" todavía puede cambiar, así que la respuesta
//     va marcada como provisional en vez de darse por cerrada.
//
// Y uno más que no estaba en el encargo y sale del dato: `putts` es un int que
// arranca en 0, así que "no capturé los putts" y "hizo 0 putts" son
// indistinguibles. Se comprueba que el sesgo cae del lado seguro.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/snake_engine.dart';
import 'package:golf_bet_master/engines/settlement_notes.dart';

const a = 'a', b = 'b', c = 'c', d = 'd';
const todos = [a, b, c, d];

CourseInfo _course([int hoyos = 18]) => CourseInfo(
    name: 'T',
    holes: List.generate(
        hoyos, (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)));

/// Ronda con putts a medida.
///
/// [putts] es hoyo → {jugador: putts}. Los hoyos ausentes van con 2 putts, que
/// no dispara nada. [sinScore] son hoyos que nadie ha capturado todavía.
Round _round({
  Map<int, Map<String, int>> putts = const {},
  Set<int> sinScore = const {},
  SnakeConfig cfg = SnakeConfig.def,
  int hoyos = 18,
  List<String> participantes = todos,
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
          playerIds: participantes,
          modules: [
            BetModuleInstance.defaultFor(BetModuleType.snake, participantes,
                    id: 'sn')
                .copyWith(snakeConfig: cfg),
          ]),
    ],
    scores: {
      for (final pid in todos)
        pid: {
          for (var h = 1; h <= hoyos; h++)
            if (!sinScore.contains(h))
              h: HoleScore(
                  playerId: pid, hole: h, grossScore: 4,
                  putts: putts[h]?[pid] ?? 2),
        },
    },
    events: const {}, oyeseRankings: const {}, sliding: const [],
    createdAt: DateTime(2026, 1, 1), totalHoles: hoyos,
  );
}

List<LedgerEntry> _asientos(Round r) => BetEngine.computeAll(r);
List<NotaDeLiquidacion> _notas(Round r) => notasDeLiquidacion(r);

void main() {
  group('1 · la serpiente es la ÚLTIMA, no la peor', () {
    test('un 3-putt tardío se lleva la serpiente de un 4-putt anterior', () {
      // Es la regla que distingue Snake de "quien peor putteó". Si el motor
      // buscara el máximo, aquí ganaría A con sus cuatro putts.
      final r = _round(putts: {
        4: {a: 4},
        15: {b: 3},
      });
      final e = _asientos(r);
      expect(e, isNotEmpty);
      expect(e.every((x) => x.fromPlayerId == b), isTrue,
          reason: 'paga B, que la agarró en el 15');
      expect(e.length, 3, reason: 'paga a los otros tres');
    });

    test('el umbral se respeta: con 4 configurado, un 3-putt no la agarra', () {
      final r = _round(
          putts: {
            4: {a: 4},
            15: {b: 3},
          },
          cfg: const SnakeConfig(umbral: 4));
      final e = _asientos(r);
      expect(e.every((x) => x.fromPlayerId == a), isTrue,
          reason: 'con umbral 4 el 3-putt del 15 no cuenta');
    });

    test('el importe es por rival, no un bote a repartir', () {
      final r = _round(
          putts: {9: {a: 3}}, cfg: const SnakeConfig(value: 100));
      final e = _asientos(r);
      expect(e.length, 3);
      expect(e.every((x) => x.amount == 100), isTrue);
    });
  });

  group('2 · nadie hace 3-putt: no se paga, y se DICE', () {
    test('cero asientos', () {
      final r = _round();
      expect(_asientos(r), isEmpty);
    });

    test('y una nota que lo explica, no un silencio', () {
      // El caso del encargo. Sin esto, la pantalla enseña $0 y el usuario no
      // puede distinguir "no pasó nada" de "el cálculo falló".
      final notas = _notas(_round());
      expect(notas, hasLength(1));
      expect(notas.single.texto, contains('Nadie hizo 3 putts'));
      expect(notas.single.tono, TonoNota.informativa,
          reason: 'no es un error: la apuesta funcionó');
    });

    test('la nota cita el umbral configurado, no un 3 fijo', () {
      final notas = _notas(_round(cfg: const SnakeConfig(umbral: 4)));
      expect(notas.single.texto, contains('4 putts'));
    });

    test('y cuando SÍ hay dueño la nota lo nombra', () {
      // El contrapeso: sin este, la nota podría estar diciendo siempre "nadie".
      final notas = _notas(_round(putts: {7: {a: 3}}));
      expect(notas.single.texto, contains('A'));
      expect(notas.single.texto, contains('hoyo 7'));
    });
  });

  group('3 · empate en el último hoyo', () {
    test('pagan los dos completo, por defecto', () {
      final r = _round(putts: {18: {a: 3, b: 3}});
      final e = _asientos(r);
      // Cada uno paga a los DOS que no la agarraron. Entre ellos no se pagan:
      // los dos perdieron.
      expect(e.length, 4);
      expect(e.where((x) => x.fromPlayerId == a).length, 2);
      expect(e.where((x) => x.fromPlayerId == b).length, 2);
      expect(e.any((x) => x.toPlayerId == a || x.toPlayerId == b), isFalse,
          reason: 'cobrar uno al otro sería decir que uno perdió menos');
    });

    test('con "dividen" el bolsillo del rival recibe lo mismo que con uno solo',
        () {
      // Es la comprobación que da sentido a la variante: el que no la agarró
      // cobra 100 tanto si la agarró uno como si la agarraron dos.
      final r = _round(
          putts: {18: {a: 3, b: 3}},
          cfg: const SnakeConfig(value: 100, empate: SnakeEmpate.dividen));
      final e = _asientos(r);
      final cobraC = e.where((x) => x.toPlayerId == c)
          .fold(0.0, (s, x) => s + x.amount);
      expect(cobraC, 100);
    });

    test('el resultado NO depende del orden de la lista de jugadores', () {
      // El riesgo que el encargo señala. Se compara la misma ronda con los
      // participantes al revés: los dueños tienen que ser los mismos.
      final normal = SnakeEngine.buscar(
          _round(putts: {18: {b: 3, d: 3}}), todos, SnakeConfig.def);
      final revuelto = SnakeEngine.buscar(
          _round(putts: {18: {b: 3, d: 3}}),
          todos.reversed.toList(),
          SnakeConfig.def);
      expect(normal.duenos, revuelto.duenos);
      expect(normal.duenos, [b, d], reason: 'ordenados, no en orden de llegada');
    });

    test('tres empatados también funciona', () {
      final r = _round(putts: {18: {a: 3, b: 3, c: 3}});
      final e = _asientos(r);
      // Los tres pagan al único que no la agarró.
      expect(e.length, 3);
      expect(e.every((x) => x.toPlayerId == d), isTrue);
    });
  });

  group('4 · ronda incompleta: provisional, no cerrada', () {
    test('con hoyos sin capturar el resultado se marca provisional', () {
      // La decisión: se calcula en vivo y se enseña con aviso. Snake es una
      // apuesta que se comenta durante la vuelta; esconderla hasta el 18 le
      // quita la gracia. Lo que no se puede es darla por definitiva.
      final r = _round(putts: {7: {a: 3}}, sinScore: {16, 17, 18});
      final res = SnakeEngine.buscar(r, todos, SnakeConfig.def);
      expect(res.provisional, isTrue);
      expect(res.hoyosSinCapturar, 3);

      final notas = _notas(r);
      expect(notas.single.tono, TonoNota.provisional);
      expect(notas.single.texto, contains('3 hoyos'));
    });

    test('completa, la nota deja de ser provisional', () {
      final notas = _notas(_round(putts: {7: {a: 3}}));
      expect(notas.single.tono, TonoNota.informativa);
    });

    test('y el dinero se mueve igual: provisional no es "sin liquidar"', () {
      // Decisión explícita: el ledger cobra la serpiente provisional. Si no
      // cobrara, el balance de la ronda en curso mentiría por defecto.
      final r = _round(putts: {7: {a: 3}}, sinScore: {16, 17, 18});
      expect(_asientos(r), hasLength(3));
    });

    test('un 3-putt en un hoyo sin capturar no cuenta todavía', () {
      // Es lo que hace que "el último" pueda cambiar: el hoyo 18 existe en el
      // campo pero nadie lo anotó.
      final r = _round(putts: {7: {a: 3}, 18: {b: 3}}, sinScore: {18});
      final e = _asientos(r);
      expect(e.every((x) => x.fromPlayerId == a), isTrue);
    });
  });

  group('5 · el dato: putts arranca en 0', () {
    test('un hoyo sin capturar no dispara la serpiente con putts 0', () {
      // 0 no es >= 3, así que el sesgo cae solo. Se comprueba para que quede
      // fijado: si algún día el umbral pudiera ser 0, esto avisa.
      final r = _round(sinScore: {5, 6});
      expect(SnakeEngine.buscar(r, todos, SnakeConfig.def).hayDueno, isFalse);
    });

    test('quien tiene score pero no putts capturados no la agarra', () {
      // El falso negativo conocido: putts=2 por defecto en el fixture, pero en
      // la app un score guardado sin putts llega como 0. En ninguno de los dos
      // casos alguien agarra la serpiente por error.
      final r = _round(putts: {9: {a: 0}});
      expect(_asientos(r), isEmpty);
    });
  });

  group('6 · la configuración sobrevive al viaje', () {
    test('serializar y deserializar la ronda conserva umbral y empate', () {
      // La config vive en snakeConfig, y hay CINCO sitios que reconstruyen un
      // BetModuleInstance campo a campo. Uno que se olvide la borra en silencio.
      final cfg = const SnakeConfig(
          value: 250, umbral: 4, empate: SnakeEmpate.dividen);
      final json = BetModuleInstance.defaultFor(BetModuleType.snake, todos,
              id: 'sn')
          .copyWith(snakeConfig: cfg)
          .toJson();
      final vuelta = BetModuleInstance.fromJson(Map<String, dynamic>.from(json));
      expect(vuelta.snake.value, 250);
      expect(vuelta.snake.umbral, 4);
      expect(vuelta.snake.empate, SnakeEmpate.dividen);
    });

    test('copyWith no la pierde al tocar otra cosa', () {
      final m = BetModuleInstance.defaultFor(BetModuleType.snake, todos, id: 's')
          .copyWith(snakeConfig: const SnakeConfig(umbral: 4))
          .copyWith(name: 'Otra cosa');
      expect(m.snake.umbral, 4);
    });
  });
}
