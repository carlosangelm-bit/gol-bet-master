// ─────────────────────────────────────────────────────────────────────────────
// sliding_deportivo_test.dart — el sliding se ajusta por RESULTADO, no por dinero
//
// Reporte de uso real: "la app detectaba que un jugador había ganado o perdido
// dinero y lo ponía como victoria, modificando el sliding. El sliding solo se
// modifica cuando un jugador gana el match o los skins."
//
// Dos reglas, y la segunda era el bug vivo:
//
//   1. Ganar en medal, putts, oyes o unidades NO es ganar el duelo.
//   2. El juego por EQUIPOS no ajusta la ventaja personal. Los motores de equipo
//      emiten con el MISMO betType que los individuales y teamCrossAmount
//      reparte el importe del lado entre los cruces, así que en una 2v2
//      aparecían asientos `nassau` entre A1 y B2 y el sliding los leía como un
//      duelo que esos dos nunca jugaron.
//
// Se resuelve desde el MÓDULO —hasTeamSides + containsPair— sin campo nuevo en
// LedgerEntry y sin deducirlo del texto del reason.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/sliding_adjustment_engine.dart';

const a1 = 'a1', a2 = 'a2', b1 = 'b1', b2 = 'b2';
const todos = [a1, a2, b1, b2];

CourseInfo _course() => CourseInfo(name: 'T',
    holes: List.generate(18,
        (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)));

/// Ronda con los módulos dados. a1 juega mejor que b1 en bruto.
Round _round(List<BetModuleInstance> mods, {Map<String, int>? gross}) {
  final g = gross ?? {a1: 4, a2: 5, b1: 5, b2: 6};
  return Round(
    id: 'r', name: 'R', course: _course(),
    players: todos.map((i) => Player(id: i, name: i)).toList(),
    roundPlayers:
        todos.map((i) => RoundPlayer(playerId: i, handicapEnRonda: 0)).toList(),
    betGroups: [BetGroup(id: 'grp', name: 'G',
        format: PartidaFormat.oneVsOne, playerIds: todos, modules: mods)],
    scores: {
      for (final e in g.entries)
        e.key: {for (var h = 1; h <= 18; h++)
          h: HoleScore(playerId: e.key, hole: h, grossScore: e.value)},
    },
    events: {
      // Unidades para a1: mueven MUCHO dinero sin ser una victoria deportiva.
      a1: {for (var h = 1; h <= 18; h++)
        h: [HoleEvent(playerId: a1, hole: h, type: UnitEventType.birdie)]},
    },
    oyeseRankings: const {}, sliding: const [],
    createdAt: DateTime(2026, 1, 1), totalHoles: 18,
  );
}

DuelResult? _duelo(Round r, String p1, String p2) =>
    SlidingAdjustmentEngine.computeDuelForTest(
        p1Id: p1, p2Id: p2, round: r, allEntries: BetEngine.computeAll(r));

BetModuleInstance _individual(BetModuleType t, List<String> pids,
        {String? id, double? valor}) {
  var m = BetModuleInstance.defaultFor(t, pids, id: id ?? t.name);
  if (valor != null) m = m.withBaseValue(valor) ?? m;
  return m;
}

BetModuleInstance _equipos(BetModuleType t, {double? valor}) {
  var m = BetModuleInstance.defaultFor(t, todos, id: '${t.name}_eq', sides: const [
    BetSide(id: 'A', name: 'Equipo A', playerIds: [a1, a2]),
    BetSide(id: 'B', name: 'Equipo B', playerIds: [b1, b2]),
  ]);
  if (valor != null) m = m.withBaseValue(valor) ?? m;
  return m;
}

void main() {
  group('1 · solo match y skins mueven la ventaja', () {
    test('una ronda solo con unidades y oyes no ajusta nada', () {
      final r = _round([
        _individual(BetModuleType.units, todos),
        _individual(BetModuleType.oyeses, todos),
      ]);
      // Hay dinero moviéndose: los birdies de a1 se cobran a todos.
      expect(BetEngine.computeAll(r), isNotEmpty);
      // Y aun así no hay duelo que ajustar.
      expect(_duelo(r, a1, b1), isNull);
    });

    test('y el diálogo explica por qué', () {
      final r = _round([_individual(BetModuleType.units, todos)]);
      expect(SlidingAdjustmentEngine.motivoSinAjuste(r),
          SinAjusteMotivo.sinMatchNiSkins);
      expect(SlidingAdjustmentEngine.motivoSinAjuste(r)!.detalle,
          contains('no tenía apuesta de match'));
    });

    test('sin ninguna apuesta el motivo es otro', () {
      expect(SlidingAdjustmentEngine.motivoSinAjuste(_round(const [])),
          SinAjusteMotivo.sinApuestas);
    });
  });

  group('2 · el juego por equipos no ajusta la ventaja personal', () {
    test('un Nassau de equipos no produce duelo entre personas', () {
      // teamCrossAmount reparte el importe del lado entre los cruces, así que
      // SÍ hay transferencias entre a1 y b1. No son un duelo que jugaran.
      final r = _round([_equipos(BetModuleType.nassau)]);
      final entries = BetEngine.computeAll(r);
      expect(
          entries.any((e) =>
              {e.fromPlayerId, e.toPlayerId}.containsAll({a1, b1})),
          isTrue,
          reason: 'sin transferencias el test no probaría nada');
      expect(_duelo(r, a1, b1), isNull);
    });

    test('tampoco entre compañeros del mismo lado', () {
      final r = _round([_equipos(BetModuleType.nassau)]);
      expect(_duelo(r, a1, a2), isNull);
    });

    test('Skins de equipos tampoco', () {
      final r = _round([_equipos(BetModuleType.skins)]);
      expect(_duelo(r, a1, b1), isNull);
    });

    test('el motivo que se muestra es el de equipos', () {
      expect(
          SlidingAdjustmentEngine.motivoSinAjuste(
              _round([_equipos(BetModuleType.nassau)])),
          SinAjusteMotivo.soloEquipos);
    });
  });

  group('3 · ajusta por el MATCH aunque las unidades muevan más dinero', () {
    // EL test del reporte. Los importes son deliberadamente desiguales: si se
    // montara con importes iguales pasaría por casualidad.
    test('unidades a \$500 y nassau a \$10: manda el nassau', () {
      final r = _round([
        _individual(BetModuleType.nassau, todos, valor: 10),
        _individual(BetModuleType.units, todos, valor: 500),
      ]);

      final unidades = BetEngine.computeAll(r)
          .where((e) => e.betType == BetModuleType.units)
          .fold<double>(0, (x, e) => x + e.amount);
      final nassau = BetEngine.computeAll(r)
          .where((e) => e.betType == BetModuleType.nassau)
          .fold<double>(0, (x, e) => x + e.amount);
      expect(unidades, greaterThan(nassau),
          reason: 'el montaje debe tener las unidades moviendo MÁS dinero');

      final d = _duelo(r, a1, b1);
      expect(d, isNotNull);
      expect(d!.betType, BetModuleType.nassau,
          reason: 'las unidades no representan el duelo por mover más dinero');
    });

    test('y el ganador es quien ganó el match, no quien cobró más', () {
      final r = _round([
        _individual(BetModuleType.nassau, todos, valor: 10),
        _individual(BetModuleType.units, todos, valor: 500),
      ]);
      // a1 hace 4 y b1 hace 5 en los 18: a1 gana el nassau.
      expect(_duelo(r, a1, b1)!.winnerId, a1);
    });

    test('si el match lo gana el otro, gana el otro aunque cobre menos', () {
      // b1 mejor que a1 en el campo, pero a1 se lleva las unidades.
      final r = _round([
        _individual(BetModuleType.nassau, todos, valor: 10),
        _individual(BetModuleType.units, todos, valor: 500),
      ], gross: {a1: 5, a2: 5, b1: 4, b2: 6});
      expect(_duelo(r, a1, b1)!.winnerId, b1);
    });
  });

  group('4 · equipos MÁS un duelo pactado aparte', () {
    test('solo el duelo ajusta', () {
      final duelo = BetModuleInstance.defaultFor(
              BetModuleType.skins, const [a1, b1], id: 'duelo_0_skins')
          .copyWith(scope: BetScope.pair(a1, b1));
      final r = _round([_equipos(BetModuleType.nassau), duelo]);

      final d = _duelo(r, a1, b1);
      expect(d, isNotNull, reason: 'el duelo individual sí cuenta');
      expect(d!.betType, BetModuleType.skins,
          reason: 'el nassau de equipos no puede representar el duelo');
    });

    test('y los cruces sin duelo siguen sin ajustar', () {
      final duelo = BetModuleInstance.defaultFor(
              BetModuleType.skins, const [a1, b1], id: 'duelo_0_skins')
          .copyWith(scope: BetScope.pair(a1, b1));
      final r = _round([_equipos(BetModuleType.nassau), duelo]);
      expect(_duelo(r, a2, b2), isNull);
    });
  });

  group('5 · el filtro es explícito', () {
    test('los tipos que no equilibran un enfrentamiento quedan fuera', () {
      for (final t in [BetModuleType.medal, BetModuleType.putts,
                       BetModuleType.oyeses, BetModuleType.units]) {
        final r = _round([_individual(t, todos)]);
        expect(_duelo(r, a1, b1), isNull, reason: t.label);
      }
    });

    test('los que sí, dan duelo', () {
      for (final t in [BetModuleType.nassau, BetModuleType.skins]) {
        final r = _round([_individual(t, todos)]);
        expect(_duelo(r, a1, b1), isNotNull, reason: t.label);
      }
    });

    test('Bola Baja / Bola Alta queda fuera por ser siempre de equipos', () {
      final r = _round([_equipos(BetModuleType.nassauLowHigh)]);
      expect(_duelo(r, a1, b1), isNull);
    });
  });
}
