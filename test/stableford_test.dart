// ─────────────────────────────────────────────────────────────────────────────
// STABLEFORD COMO APUESTA
//
// La aritmética ya existía: GameEngine produce los puntos de cada hoyo desde
// siempre para pintar la tarjeta. Esto la EXPONE como formato.
//
// Los dos tests que el encargo pedía explícitamente, y son los que importan:
//
//   · LOS PUNTOS USAN EL NETO, no el bruto. Se comprueba con dos jugadores que
//     hacen el MISMO bruto y distinto handicap: si usara el bruto empatarían.
//   · Y el interruptor bruto/neto tenía que declararse. El switch de
//     useHandicap tiene `_ => false`, así que sin su rama Stableford habría
//     calculado bruto EN SILENCIO mientras la tarjeta decía "Net". Se comprueba
//     que la rama existe y que cambia el resultado.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/game_engine.dart';
import 'package:golf_bet_master/engines/stableford_engine.dart';

const a = 'a', b = 'b', c = 'c', d = 'd';
const todos = [a, b, c, d];

/// Campo de 18 par 4, con stroke index 1..18 en orden.
CourseInfo _course() => CourseInfo(
    name: 'T',
    holes: List.generate(
        18, (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)));

Round _round({
  Map<String, int> bruto = const {},
  Map<String, double> handicaps = const {},
  StablefordConfig cfg = StablefordConfig.def,
  BetFormatMode reparto = BetFormatMode.onePot,
  Set<int> sinScore = const {},
}) {
  var mod = BetModuleInstance.defaultFor(BetModuleType.stableford, todos,
          id: 'sf')
      .copyWith(stablefordConfig: cfg);
  mod = mod.copyWith(formatMode: reparto);
  return Round(
    id: 'r', name: 'R', course: _course(),
    players: todos.map((i) => Player(id: i, name: i.toUpperCase())).toList(),
    roundPlayers: todos
        .map((i) => RoundPlayer(
            playerId: i, handicapEnRonda: handicaps[i] ?? 0))
        .toList(),
    betGroups: [
      BetGroup(
          id: 'g', name: 'G',
          format: PartidaFormat.allInOnePot,
          playerIds: todos, modules: [mod]),
    ],
    scores: {
      for (final pid in todos)
        pid: {
          for (var h = 1; h <= 18; h++)
            if (!sinScore.contains(h))
              h: HoleScore(
                  playerId: pid, hole: h, grossScore: bruto[pid] ?? 4),
        },
    },
    events: const {}, oyeseRankings: const {}, sliding: const [],
    createdAt: DateTime(2026, 1, 1), totalHoles: 18,
  );
}

BetModuleInstance _mod(Round r) => r.betGroups.first.modules.first;

void main() {
  group('1 · los puntos salen del NETO, no del bruto', () {
    test('mismo bruto y distinto handicap dan distintos puntos', () {
      // El test que el encargo pedía. Con el bruto empatarían a 36 los dos.
      final r = _round(handicaps: {a: 18});
      final pts = StablefordEngine.tabla(r, todos, _mod(r));
      expect(pts[b], 36, reason: '18 pares = 18 × 2');
      expect(pts[a], 54,
          reason: 'con 18 de handicap cada hoyo es birdie neto: 18 × 3');
      expect(pts[a], isNot(pts[b]),
          reason: 'si usara el bruto, esto sería un empate');
    });

    test('el handicap se distribuye por stroke index, no a todos los hoyos', () {
      // Con 9 de handicap solo los nueve hoyos de SI más bajo reciben golpe.
      final r = _round(handicaps: {a: 9});
      final pts = StablefordEngine.tabla(r, todos, _mod(r));
      expect(pts[a], 45, reason: '9 birdies netos (3) + 9 pares (2)');
    });

    test('y en modo BRUTO no se descuenta nada', () {
      final r = _round(
          handicaps: {a: 18},
          cfg: const StablefordConfig(mode: GrossNetMode.gross));
      final pts = StablefordEngine.tabla(r, todos, _mod(r));
      expect(pts[a], 36, reason: 'el handicap se ignora');
      expect(pts[a], pts[b]);
    });
  });

  group('2 · el interruptor bruto/neto está declarado', () {
    test('useHandicap responde al modo, no al default del switch', () {
      // Sin la rama en el switch, `_ => false` habría hecho que Stableford
      // calculara bruto siempre, con la tarjeta diciendo "Net".
      final neto = BetModuleInstance
          .defaultFor(BetModuleType.stableford, todos, id: 'x');
      expect(neto.useHandicap, isTrue, reason: 'el default es neto');

      final bruto = neto.copyWith(
          stablefordConfig: const StablefordConfig(mode: GrossNetMode.gross));
      expect(bruto.useHandicap, isFalse);
    });
  });

  group('3 · la liquidación', () {
    test('un bote: el de más puntos cobra a todos', () {
      final r = _round(bruto: {a: 3}); // a hace birdie en todos
      final e = BetEngine.computeAll(r);
      expect(e, hasLength(3));
      expect(e.every((x) => x.toPlayerId == a), isTrue);
      expect(e.every((x) => x.amount == 100), isTrue);
    });

    test('más puntos gana: al revés que Medal', () {
      // Es el error fácil de escribir: copiar el orden de Medal, donde menos es
      // mejor. Aquí a hace MÁS golpes, así que menos puntos, así que paga.
      final r = _round(bruto: {a: 6});
      final e = BetEngine.computeAll(r);
      expect(e.every((x) => x.fromPlayerId == a), isTrue);
    });

    test('empate arriba: nadie paga', () {
      final r = _round(); // todos igual
      expect(BetEngine.computeAll(r), isEmpty);
    });

    test('todos contra todos: un duelo por pareja', () {
      final r = _round(
          bruto: {a: 3, b: 4, c: 5, d: 6},
          reparto: BetFormatMode.allVsAll);
      final e = BetEngine.computeAll(r);
      expect(e, hasLength(6), reason: 'C(4,2)');
      // a gana a todos, d pierde con todos.
      expect(e.where((x) => x.toPlayerId == a), hasLength(3));
      expect(e.where((x) => x.fromPlayerId == d), hasLength(3));
    });

    test('el motivo dice los puntos: un importe sin cifra no se comprueba', () {
      final r = _round(bruto: {a: 3});
      expect(BetEngine.computeAll(r).first.reason, contains('54'));
    });

    test('una ronda sin capturar nada no mueve dinero', () {
      final r = _round(sinScore: {for (var h = 1; h <= 18; h++) h});
      expect(BetEngine.computeAll(r), isEmpty);
    });
  });

  group('4 · la tabla configurable llega al resultado', () {
    test('con suelo negativo un desastre resta', () {
      // a hace 8 en todos: relativo +4. Con suelo 0 son 0 puntos; con −1, −18.
      final conSuelo0 = _round(bruto: {a: 8});
      expect(StablefordEngine.tabla(conSuelo0, todos, _mod(conSuelo0))[a], 0);

      final conSueloNeg = _round(
          bruto: {a: 8}, cfg: const StablefordConfig(piso: -1));
      expect(StablefordEngine.tabla(conSueloNeg, todos, _mod(conSueloNeg))[a],
          -18);
    });

    test('subir los puntos del par sube a todos por igual', () {
      final r = _round(cfg: const StablefordConfig(puntosDelPar: 3, techo: 9));
      final pts = StablefordEngine.tabla(r, todos, _mod(r));
      expect(pts.values.every((v) => v == 54), isTrue, reason: '18 × 3');
    });

    test('la config sobrevive el viaje a JSON', () {
      final cfg = const StablefordConfig(
          value: 250, mode: GrossNetMode.gross, puntosDelPar: 1, piso: -2);
      final v = StablefordConfig.fromJson(
          Map<String, dynamic>.from(cfg.toJson()));
      expect((v.value, v.mode, v.puntosDelPar, v.piso),
          (250.0, GrossNetMode.gross, 1, -2));
    });

    test('y solo se serializa lo que se aparta de la clásica', () {
      // Así una ronda guardada antes de que la tabla fuera configurable se lee
      // igual.
      expect(StablefordConfig.def.toJson().keys, ['value', 'mode']);
      expect(StablefordConfig.def.tablaClasica, isTrue);
    });
  });

  group('5 · coincide con lo que ya pintaba la tarjeta', () {
    test('con la tabla clásica da lo mismo que GameEngine.stablefordTotal', () {
      // El motor nuevo recorre los hoyos por su cuenta —la tabla es
      // configurable y el atajo usa la clásica— así que conviene comprobar que
      // con los valores por defecto no se separa de lo que la app ya enseñaba.
      final r = _round(bruto: {a: 3, b: 4, c: 5, d: 6}, handicaps: {a: 9, c: 4});
      for (final pid in todos) {
        expect(
            StablefordEngine.puntosDe(r, pid, StablefordConfig.def, neto: true),
            GameEngine.stablefordTotal(r, pid, true),
            reason: pid);
      }
    });
  });
}
