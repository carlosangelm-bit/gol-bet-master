// ─────────────────────────────────────────────────────────────────────────────
// PAREJA BASE CONTRA EL CAMPO — la asimetría es el formato
//
// Con cinco jugadores, una pareja base juega contra CADA pareja posible del
// resto: tres enfrentamientos a la vez. La pareja base juega los tres y cada
// rival dos, así que gana más y pierde más. Eso no es un desequilibrio a
// corregir: es de lo que va el formato, y está escrito en la descripción para
// que nadie lo "arregle" después bajando importes.
//
// El test que define el formato es el del LIBRO: si la pareja base gana los
// tres, cobra el triple que lo que paga un rival. Tres módulos bien creados no
// garantizan eso —es exactamente el caso donde un reparto pensado para un
// enfrentamiento da tres cifras plausibles cuyo total no cierra— así que se
// comprueba sobre balances reales y se exige que el ledger cierre en cero.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';
import 'package:golf_bet_master/models/bet_recipe.dart';
import 'package:golf_bet_master/models/formaciones.dart';
import 'package:golf_bet_master/models/models.dart';

// A y B son la pareja base; C, D y E el resto.
const pa = 'pid_aa01', pb = 'pid_bb02';
const pc = 'pid_cc03', pd = 'pid_dd04', pe = 'pid_ee05';
const cinco = [pa, pb, pc, pd, pe];

List<Player> _js(List<(String, double)> g) =>
    [for (final x in g) Player(id: x.$1, name: x.$1.toUpperCase(), handicapBase: x.$2)];

/// Los cinco con handicap creciente: la pareja base propuesta es A+B.
List<Player> _cinco() => _js(const [
      (pa, 4),
      (pb, 9),
      (pc, 15),
      (pd, 18),
      (pe, 22),
    ]);

CourseInfo _course() => CourseInfo(
    name: 'Los Encinos',
    holes: List.generate(
        18, (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)));

/// Una ronda con los TRES enfrentamientos montados como los monta el atajo.
///
/// Se construyen con BetRecipe.porEnfrentamiento —el mismo camino que usa el
/// asistente— para que el test pruebe lo que la app produce y no una forma que
/// yo escriba a mano. Es la lección del scramble.
Round _round({
  required Map<String, int> golpes,
  double value = 100,
  List<String> parejaBase = const [pa, pb],
}) {
  final jugadores = _cinco();
  final base = BetModuleInstance(
    id: 'mod',
    type: BetModuleType.nassau,
    name: 'Nassau',
    participantIds: cinco,
    nassauConfig: NassauConfig(
      frontValue: value,
      backValue: 0,
      totalValue: 0,
      pressEnabled: false,
      mode: GrossNetMode.gross,
    ),
  );
  final mods = BetRecipe.porEnfrentamiento(
    base,
    lados: enfrentamientosDe(Formacion.parejaBaseVsCampo, jugadores,
        parejaBase: parejaBase),
    bola: TeamBall.mejor,
  );

  return Round(
    id: 'r1',
    name: 'Sábado',
    course: _course(),
    players: jugadores,
    roundPlayers: jugadores
        .map((p) => RoundPlayer(playerId: p.id, handicapEnRonda: 0))
        .toList(),
    betGroups: [
      BetGroup(
          id: 'grp',
          name: 'G',
          format: PartidaFormat.allInOnePot,
          playerIds: cinco,
          modules: mods)
    ],
    scores: {
      for (final e in golpes.entries)
        e.key: {
          for (var h = 1; h <= 18; h++)
            h: HoleScore(playerId: e.key, hole: h, grossScore: e.value),
        },
    },
    events: const {},
    oyeseRankings: const {},
    sliding: const [],
    createdAt: DateTime(2026, 8, 1),
    totalHoles: 18,
    isFinished: true,
  );
}

void main() {
  group('1 · tres enfrentamientos, y son las tres parejas del resto', () {
    test('con cinco salen exactamente tres', () {
      final e = enfrentamientosDe(Formacion.parejaBaseVsCampo, _cinco());
      expect(e, hasLength(3));
      // La pareja base está en los tres, y es la de handicap combinado más bajo.
      for (final x in e) {
        expect(x.$1, [pa, pb]);
      }
      // Y los rivales son las tres parejas posibles de C, D, E.
      expect(e.map((x) => x.$2), [
        [pc, pd],
        [pc, pe],
        [pd, pe],
      ]);
    });

    test('cada rival juega DOS de los tres', () {
      // Es la otra cara de la asimetría, y define el formato igual que el
      // triple de la pareja base.
      final e = enfrentamientosDe(Formacion.parejaBaseVsCampo, _cinco());
      for (final r in [pc, pd, pe]) {
        expect(e.where((x) => x.$2.contains(r)), hasLength(2), reason: r);
      }
    });

    test('la pareja base se fija a mano y manda', () {
      final e = enfrentamientosDe(Formacion.parejaBaseVsCampo, _cinco(),
          parejaBase: const [pd, pe]);
      for (final x in e) {
        expect(x.$1, [pd, pe]);
      }
      expect(e.map((x) => x.$2), [
        [pa, pb],
        [pa, pc],
        [pb, pc],
      ]);
    });

    test('armar dos veces da lo mismo: no hay sorteo', () {
      // Un sorteo daría un reparto distinto cada vez que se toca el botón, y
      // rearmar dejaría de ser seguro. Si lo quieren a suertes, lo sortean ellos.
      final una = enfrentamientosDe(Formacion.parejaBaseVsCampo, _cinco());
      final otra = enfrentamientosDe(Formacion.parejaBaseVsCampo, _cinco());
      expect(una.map((x) => x.$2), otra.map((x) => x.$2));
    });
  });

  group('2 · el catálogo: cinco y solo cinco', () {
    test('fuera de cinco no se ofrece', () {
      expect(Formacion.parejaBaseVsCampo.motivoNoDisponible(5), isNull);
      for (final n in [3, 4, 6, 7]) {
        expect(Formacion.parejaBaseVsCampo.motivoNoDisponible(n), isNotNull,
            reason: '$n');
      }
    });

    test('el motivo distingue pocos de muchos, y explica por qué', () {
      final pocos = Formacion.parejaBaseVsCampo.motivoNoDisponible(4)!;
      final muchos = Formacion.parejaBaseVsCampo.motivoNoDisponible(6)!;
      expect(pocos, contains('se juega con 5 jugadores'));
      expect(pocos, contains('2 contra 2'));
      expect(muchos, contains('seis'));
      expect(pocos, isNot(muchos));
    });

    test('fuera de rango no arma nada', () {
      expect(
          enfrentamientosDe(Formacion.parejaBaseVsCampo,
              _js(const [(pa, 4), (pb, 9), (pc, 15), (pd, 18)])),
          isEmpty);
    });

    test('el reparto se anuncia con el número real', () {
      expect(Formacion.parejaBaseVsCampo.reparto(5),
          '3 enfrentamientos a la vez.');
    });

    test('la descripción dice que la asimetría es el formato', () {
      // Que quede escrito donde se decide, para que nadie lo "arregle" después.
      final d = Formacion.parejaBaseVsCampo.reglas.descripcion;
      expect(d, contains('A PROPÓSITO'));
      expect(d, contains('gana más y pierde más'));
      expect(d, contains('no es un desequilibrio'));
    });

    test('y que la pareja base no rota', () {
      expect(Formacion.parejaBaseVsCampo.reglas.comoSeDecide, contains('no rota'));
    });
  });

  group('3 · el atajo monta tres módulos de verdad', () {
    test('tres módulos, con sus lados y con ids distintos', () {
      final r = _round(golpes: const {pa: 4, pb: 4, pc: 5, pd: 5, pe: 5});
      final mods = r.betGroups.first.modules;
      expect(mods, hasLength(3));
      expect(mods.map((m) => m.id).toSet(), hasLength(3),
          reason: 'ids repetidos serían el mismo módulo en el ledger');
      for (final m in mods) {
        expect(m.sides, hasLength(2));
        expect(m.sides![0].playerIds, [pa, pb]);
        expect(m.sides![1], isNotNull);
        expect(m.hasTeamSides, isTrue);
      }
    });

    test('el nombre dice contra quién: hay que poder editar el tercero', () {
      final r = _round(golpes: const {pa: 4, pb: 4, pc: 5, pd: 5, pe: 5});
      final nombres = r.betGroups.first.modules.map((m) => m.name).toSet();
      expect(nombres, hasLength(3));
    });

    test('un conteo sin motor de equipo NO se multiplica', () {
      // Tres copias sin lados serían tres apuestas idénticas cobrando el triple.
      final mods = BetRecipe.porEnfrentamiento(
        BetModuleInstance.defaultFor(BetModuleType.putts, cinco, id: 'm'),
        lados: enfrentamientosDe(Formacion.parejaBaseVsCampo, _cinco()),
      );
      expect(mods, hasLength(1));
      expect(mods.first.sides, isNull);
    });

    test('con un solo enfrentamiento se comporta como antes', () {
      // El contrapeso: la rama nueva no puede haberse comido la vieja.
      final mods = BetRecipe.porEnfrentamiento(
        BetModuleInstance.defaultFor(BetModuleType.nassau, cinco, id: 'm'),
        lados: [
          ([pa, pb], [pc, pd])
        ],
      );
      expect(mods, hasLength(1));
      expect(mods.first.id, 'm', reason: 'sin sufijo: no se clonó');
      expect(mods.first.sides![0].playerIds, [pa, pb]);
    });
  });

  group('4 · EL LIBRO: la pareja base cobra el triple', () {
    // La propiedad que define el formato. Front a $100 y nada más, así que cada
    // enfrentamiento mueve $100.
    test('gana los tres: cada uno de la base +\$150, cada rival −\$100', () {
      // La base saca 4 en todos los hoyos; los tres rivales, 5. La mejor bola de
      // la base gana los 18 hoyos de los tres enfrentamientos.
      final r = _round(golpes: const {pa: 4, pb: 4, pc: 5, pd: 5, pe: 5});
      final bal = LedgerEngine.playerBalances(r);

      // Tres enfrentamientos a $100 = $300 a repartir entre los dos de la base.
      expect(bal[pa], closeTo(150, 0.001));
      expect(bal[pb], closeTo(150, 0.001));
      // Cada rival jugó DOS enfrentamientos y perdió los dos: $50 en cada uno.
      for (final rival in [pc, pd, pe]) {
        expect(bal[rival], closeTo(-100, 0.001), reason: rival);
      }
    });

    test('el triple, dicho como proporción', () {
      // Es la forma en la que el formato se describe, y la que se rompería si
      // alguien "arreglara" la asimetría.
      final r = _round(golpes: const {pa: 4, pb: 4, pc: 5, pd: 5, pe: 5});
      final bal = LedgerEngine.playerBalances(r);
      final ganaLaBase = bal[pa]! + bal[pb]!;
      final pagaUnRival = bal[pc]!.abs();
      expect(ganaLaBase, closeTo(pagaUnRival * 3, 0.001));
    });

    test('el ledger cierra en CERO', () {
      // Es lo que caza un reparto roto: tres cifras pueden parecer plausibles y
      // no sumar cero. Sin este test, el formato podría estar creando dinero.
      final r = _round(golpes: const {pa: 4, pb: 4, pc: 5, pd: 5, pe: 5});
      final bal = LedgerEngine.playerBalances(r);
      expect(bal.values.fold(0.0, (s, v) => s + v), closeTo(0, 0.001));
    });

    test('pierde los tres: la base paga el triple, misma aritmética', () {
      final r = _round(golpes: const {pa: 6, pb: 6, pc: 4, pd: 4, pe: 4});
      final bal = LedgerEngine.playerBalances(r);
      expect(bal[pa], closeTo(-150, 0.001));
      expect(bal[pb], closeTo(-150, 0.001));
      for (final rival in [pc, pd, pe]) {
        expect(bal[rival], closeTo(100, 0.001), reason: rival);
      }
      expect(bal.values.fold(0.0, (s, v) => s + v), closeTo(0, 0.001));
    });

    test('gana uno y pierde dos: los enfrentamientos son independientes', () {
      // C juega bien y D y E mal. La base pierde contra C+D y C+E, y gana contra
      // D+E. Si los tres se liquidaran juntos, esto saldría mal.
      final r = _round(golpes: const {pa: 5, pb: 5, pc: 4, pd: 6, pe: 6});
      final bal = LedgerEngine.playerBalances(r);
      // La base: pierde dos ($-100 cada uno) y gana uno ($+100) → −100 entre dos.
      expect(bal[pa]! + bal[pb]!, closeTo(-100, 0.001));
      // C jugó dos y ganó los dos: +50 en cada uno.
      expect(bal[pc], closeTo(100, 0.001));
      // D y E: cada uno ganó uno (con C) y perdió uno (D+E) → 0.
      expect(bal[pd], closeTo(0, 0.001));
      expect(bal[pe], closeTo(0, 0.001));
      expect(bal.values.fold(0.0, (s, v) => s + v), closeTo(0, 0.001));
    });

    test('el importe se puede separar por enfrentamiento', () {
      // Son tres módulos de verdad, así que bajar el tercero no necesita ninguna
      // opción nueva. Se comprueba editando uno y viendo cambiar solo su dinero.
      final r = _round(golpes: const {pa: 4, pb: 4, pc: 5, pd: 5, pe: 5});
      final mods = [...r.betGroups.first.modules];
      mods[2] = mods[2].copyWith(
          nassauConfig: mods[2].nassau.copyWith(frontValue: 20));
      final r2 = r.copyWith(
          betGroups: [r.betGroups.first.copyWith(modules: mods)]);
      final bal = LedgerEngine.playerBalances(r2);
      // Dos a $100 y uno a $20 = $220 para la base.
      expect(bal[pa]! + bal[pb]!, closeTo(220, 0.001));
      expect(bal.values.fold(0.0, (s, v) => s + v), closeTo(0, 0.001));
    });
  });

  group('5 · la pareja base se DEDUCE de las apuestas', () {
    test('de los tres módulos del atajo', () {
      final r = _round(golpes: const {pa: 4, pb: 4, pc: 5, pd: 5, pe: 5});
      final p = parejaBaseDe(r.betGroups.first.modules);
      expect(p, isNotNull);
      expect(p!.base.toSet(), {pa, pb});
      expect(p.rivales, hasLength(3));
    });

    test('y de tres apuestas montadas A MANO, que es como ya se podía jugar', () {
      // Por eso se deriva en vez de guardarse: la pantalla sirve igual a quien
      // se lo montó a mano antes de que el atajo existiera.
      BetModuleInstance m(String id, List<String> a, List<String> b) =>
          BetModuleInstance(
            id: id,
            type: BetModuleType.nassau,
            name: id,
            participantIds: [...a, ...b],
            sides: [
              BetSide(id: '${id}_a', name: 'A', playerIds: a),
              BetSide(id: '${id}_b', name: 'B', playerIds: b),
            ],
          );
      final p = parejaBaseDe([
        m('1', [pa, pb], [pc, pd]),
        m('2', [pc, pe], [pa, pb]), // a mano y con los lados al revés
        m('3', [pa, pb], [pd, pe]),
      ]);
      expect(p, isNotNull);
      expect(p!.base.toSet(), {pa, pb});
      expect(p.rivales, hasLength(3));
    });

    test('sin patrón no dice nada, en vez de inventarlo', () {
      // Una ronda por equipos normal tiene UN módulo con dos lados: ahí no hay
      // pareja base que enseñar.
      expect(
          parejaBaseDe([
            BetModuleInstance(
              id: '1',
              type: BetModuleType.nassau,
              name: 'n',
              participantIds: const [pa, pb, pc, pd],
              sides: [
                BetSide(id: 'a', name: 'A', playerIds: const [pa, pb]),
                BetSide(id: 'b', name: 'B', playerIds: const [pc, pd]),
              ],
            )
          ]),
          isNull);
      // Y sin lados tampoco.
      expect(
          parejaBaseDe(
              [BetModuleInstance.defaultFor(BetModuleType.skins, cinco, id: 'm')]),
          isNull);
    });

    test('con dos candidatos empatados no elige uno al azar', () {
      // Dos apuestas cruzadas donde ambos lados se repiten igual. Decir algo
      // falso es peor que no decir nada.
      BetModuleInstance m(String id, List<String> a, List<String> b) =>
          BetModuleInstance(
            id: id,
            type: BetModuleType.nassau,
            name: id,
            participantIds: [...a, ...b],
            sides: [
              BetSide(id: '${id}_a', name: 'A', playerIds: a),
              BetSide(id: '${id}_b', name: 'B', playerIds: b),
            ],
          );
      expect(
          parejaBaseDe([
            m('1', [pa, pb], [pc, pd]),
            m('2', [pa, pb], [pc, pd]),
          ]),
          isNull);
    });
  });
}
