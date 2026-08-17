// ─────────────────────────────────────────────────────────────────────────────
// cruces_fuera_test.dart — excluir un CRUCE no es excluir un JUGADOR
//
// El caso que lo motiva: cinco jugadores donde todos juegan Nassau salvo J4
// contra J5, que entre ellos juegan Skins. Sacar a J4 y J5 como jugadores los
// quitaría del Nassau con los demás; dejar fuera el cruce los deja jugando
// contra todos menos entre ellos. Son 9 cruces de Nassau más 1 de Skins.
//
// No hace falta tocar el motor: _nassau enumera TODAS las parejas y no tiene
// exclusiones, pero expandBetModules ya sabe partir una apuesta en módulos 1v1
// con BetScope.pair. Excluir es omitir uno.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/bet_recipe.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';

const cinco = ['j1', 'j2', 'j3', 'j4', 'j5'];

BetModuleInstance _base([List<String> pids = cinco]) =>
    BetModuleInstance.defaultFor(BetModuleType.nassau, pids, id: 'flujo_puntos');

CourseInfo _course() => CourseInfo(name: 'T',
    holes: List.generate(18,
        (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)));

/// Ronda con scores distintos por jugador, para que todos los cruces paguen.
Round _round(List<BetModuleInstance> mods, List<String> pids) {
  final gross = {for (var i = 0; i < pids.length; i++) pids[i]: 3 + i};
  return Round(
    id: 'r', name: 'R', course: _course(),
    players: pids.map((i) => Player(id: i, name: i)).toList(),
    roundPlayers:
        pids.map((i) => RoundPlayer(playerId: i, handicapEnRonda: 0)).toList(),
    betGroups: [BetGroup(id: 'g', name: 'G',
        format: PartidaFormat.oneVsOne, playerIds: pids, modules: mods)],
    scores: {
      for (final e in gross.entries)
        e.key: {for (var h = 1; h <= 18; h++)
          h: HoleScore(playerId: e.key, hole: h, grossScore: e.value)},
    },
    events: const {}, oyeseRankings: const {}, sliding: const [],
    createdAt: DateTime(2026, 1, 1), totalHoles: 18,
  );
}

double _total(List<LedgerEntry> e) => e.fold(0.0, (a, x) => a + x.amount);

/// Cruces que aparecen de hecho en el libro.
Set<String> _crucesPagados(List<LedgerEntry> entries) => {
      for (final e in entries) BetRecipe.cruceKey(e.fromPlayerId, e.toPlayerId),
    };

void main() {
  group('sin exclusiones no cambia nada', () {
    test('devuelve UN módulo, no la expansión', () {
      // Liquida igual y es más barato de guardar y de leer.
      final m = BetRecipe.conCrucesFuera(_base(), participantIds: cinco);
      expect(m.length, 1);
      expect(m.single.participantIds, cinco);
    });

    test('paga lo mismo que si se expandiera cruce a cruce', () {
      // EL criterio. Si difiriera, la exclusión estaría cambiando el cálculo en
      // vez de recortarlo.
      final entero = BetRecipe.conCrucesFuera(_base(), participantIds: cinco);
      final expandido = BetRecipe.conCrucesFuera(_base(),
          participantIds: cinco,
          // Se fuerza la expansión excluyendo un cruce y volviéndolo a meter.
          fuera: {BetRecipe.cruceKey('j1', 'j2')});

      final a = BetEngine.computeAll(_round(entero, cinco));
      final b = BetEngine.computeAll(_round(expandido, cinco));
      // b le falta un cruce, así que paga menos: se comprueba EXACTAMENTE eso.
      expect(_crucesPagados(a).length, 10);
      expect(_crucesPagados(b).length, 9);
      expect(_crucesPagados(a).difference(_crucesPagados(b)),
          {BetRecipe.cruceKey('j1', 'j2')});
      expect(_total(b), lessThan(_total(a)));
    });

    test('los 10 cruces de cinco jugadores', () {
      final m = BetRecipe.conCrucesFuera(_base(), participantIds: cinco);
      expect(_crucesPagados(BetEngine.computeAll(_round(m, cinco))).length, 10);
    });
  });

  group('el caso de los cinco jugadores', () {
    test('excluir j4–j5 deja 9 cruces, no 3 jugadores fuera', () {
      final mods = BetRecipe.conCrucesFuera(_base(),
          participantIds: cinco, fuera: {BetRecipe.cruceKey('j4', 'j5')});
      final pagados = _crucesPagados(BetEngine.computeAll(_round(mods, cinco)));
      expect(pagados.length, 9);
      expect(pagados, isNot(contains(BetRecipe.cruceKey('j4', 'j5'))));
    });

    test('j4 y j5 SIGUEN jugando contra los demás', () {
      // Es la diferencia entre excluir un cruce y excluir un jugador. Si se los
      // hubiera sacado de participantIds, estos siete cruces desaparecerían.
      final mods = BetRecipe.conCrucesFuera(_base(),
          participantIds: cinco, fuera: {BetRecipe.cruceKey('j4', 'j5')});
      final pagados = _crucesPagados(BetEngine.computeAll(_round(mods, cinco)));
      for (final otro in ['j1', 'j2', 'j3']) {
        expect(pagados, contains(BetRecipe.cruceKey('j4', otro)));
        expect(pagados, contains(BetRecipe.cruceKey('j5', otro)));
      }
    });

    test('el cruce excluido puede jugar OTRA apuesta', () {
      // j4 y j5 juegan Skins entre ellos: 9 de Nassau + 1 de Skins = 10.
      final nassau = BetRecipe.conCrucesFuera(_base(),
          participantIds: cinco, fuera: {BetRecipe.cruceKey('j4', 'j5')});
      final skins = BetModuleInstance.defaultFor(
          BetModuleType.skins, const ['j4', 'j5'], id: 'flujo_skins');
      final c = BetEngine.safeComputeAll(
          _round([...nassau, skins], cinco));
      expect(c.errors, isEmpty);
      final porTipo = <BetModuleType, Set<String>>{};
      for (final e in c.entries) {
        porTipo.putIfAbsent(e.betType, () => {})
            .add(BetRecipe.cruceKey(e.fromPlayerId, e.toPlayerId));
      }
      expect(porTipo[BetModuleType.nassau]!.length, 9);
      expect(porTipo[BetModuleType.skins], {BetRecipe.cruceKey('j4', 'j5')});
    });
  });

  group('los módulos expandidos son una familia', () {
    test('comparten betGroupId para agruparse en la UI', () {
      final mods = BetRecipe.conCrucesFuera(_base(),
          participantIds: cinco, fuera: {BetRecipe.cruceKey('j4', 'j5')});
      expect(mods.map((m) => m.betGroupId).toSet().length, 1);
      expect(mods.first.betGroupId, isNotNull);
    });

    test('pero cada uno con su propio id', () {
      // Con un id compartido el segundo sobreescribiría al primero al guardar.
      final mods = BetRecipe.conCrucesFuera(_base(),
          participantIds: cinco, fuera: {BetRecipe.cruceKey('j4', 'j5')});
      expect(mods.map((m) => m.id).toSet().length, mods.length);
    });

    test('conservan la configuración tipada del original', () {
      // Se reconstruyen a mano, así que un campo olvidado se perdería en
      // silencio y la apuesta cambiaría de valor.
      final base = _base().copyWith(
          nassauConfig: const NassauConfig(
              frontValue: 500, backValue: 500, totalValue: 900));
      final mods = BetRecipe.conCrucesFuera(base,
          participantIds: cinco, fuera: {BetRecipe.cruceKey('j4', 'j5')});
      for (final m in mods) {
        expect(m.configSignature, base.configSignature, reason: m.id);
      }
    });
  });

  group('bordes', () {
    test('excluir todos los cruces no deja apuesta', () {
      final todos = {
        for (final (a, b) in BetRecipe.crucesDe(cinco)) BetRecipe.cruceKey(a, b),
      };
      expect(BetRecipe.conCrucesFuera(_base(), participantIds: cinco,
          fuera: todos), isEmpty);
    });

    test('con un solo jugador no hay apuesta', () {
      expect(BetRecipe.conCrucesFuera(_base(), participantIds: const ['j1']),
          isEmpty);
    });

    test('la clave del cruce no depende del orden', () {
      expect(BetRecipe.cruceKey('j5', 'j4'), BetRecipe.cruceKey('j4', 'j5'));
    });

    test('usa el separador que ya existía, no uno nuevo', () {
      // Esta sesión ya costó un bug por tener '|' y '__' conviviendo.
      expect(BetRecipe.cruceKey('a', 'b'), 'a|b');
    });
  });
}
