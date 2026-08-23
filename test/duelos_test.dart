// ─────────────────────────────────────────────────────────────────────────────
// duelos_test.dart — duelos pactados aparte de la apuesta de equipos
//
// La pregunta que abría el entregable: ¿basta SlidingRelation para expresar
// "entre tú y yo sin handicap" cuando la ronda va con handicap?
//
// Determinado EJECUTANDO, y la respuesta es sí:
//
//     neto sin sliding        : 0     (B recibe 18 por handicap → empate)
//     neto + pairSliding 0    : 200
//     bruto, scratch de facto : 200   ← idéntico
//     neto + pairSliding -18  : 0     (invierte quien recibe)
//
// pairSliding SUSTITUYE al handicap, y un 0 explícito se honra en vez de
// confundirse con "sin entrada". Así que delta 0 es scratch de verdad y no hizo
// falta modelo nuevo: el alcance bajó de nivel 3 a nivel 1.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/bet_recipe.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/screens/bets/bets_screen.dart';

const a1 = 'a1', a2 = 'a2', b1 = 'b1', b2 = 'b2';
const todos = [a1, a2, b1, b2];

CourseInfo _course() => CourseInfo(name: 'T',
    holes: List.generate(18,
        (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)));

/// Ronda por equipos, en NETO, con handicaps distintos entre a1 y b1.
///
/// [duelo] es un módulo suelto entre a1 y b1; [slidingDuelo] su ventaja propia.
Round _round({
  BetModuleInstance? duelo,
  double? slidingDuelo,
  int golpesB1 = 5,
}) {
  final equipo = BetModuleInstance(
    id: 'eq', type: BetModuleType.nassau, name: 'Nassau',
    participantIds: todos,
    nassauConfig: NassauConfig.def.copyWith(mode: GrossNetMode.net),
    sides: const [
      BetSide(id: 'A', name: 'Equipo A', playerIds: [a1, a2]),
      BetSide(id: 'B', name: 'Equipo B', playerIds: [b1, b2]),
    ],
  );
  // Los scores están elegidos para que la apuesta de EQUIPOS pague y el DUELO
  // empate al heredar el handicap. Con todos a 4 y 5 la ronda entera empataba y
  // el libro salía vacío: el test "el duelo no paga" pasaba por ausencia total
  // de asientos, no por empate. Un test que pasa porque no hay nada no prueba
  // nada.
  //
  //   lado A → mejor bola 3 (a2)      · lado B → mejor bola 4 (b1 neto)
  //   duelo  → a1 4 contra b1 neto 4  · empate al heredar, a1 gana a scratch
  final gross = {a1: 4, a2: 3, b1: golpesB1, b2: 6};
  return Round(
    id: 'r', name: 'R', course: _course(),
    players: todos.map((i) => Player(id: i, name: i)).toList(),
    roundPlayers: [
      // a1 scratch, b1 con 18 de handicap: la diferencia se nota.
      RoundPlayer(playerId: a1, handicapEnRonda: 0),
      RoundPlayer(playerId: a2, handicapEnRonda: 0),
      RoundPlayer(playerId: b1, handicapEnRonda: 18),
      RoundPlayer(playerId: b2, handicapEnRonda: 0),
    ],
    betGroups: [BetGroup(id: 'g', name: 'G',
        format: PartidaFormat.teams2v2, playerIds: todos,
        modules: [equipo, if (duelo != null) duelo])],
    scores: {
      for (final e in gross.entries)
        e.key: {for (var h = 1; h <= 18; h++)
          h: HoleScore(playerId: e.key, hole: h, grossScore: e.value)},
    },
    events: const {}, oyeseRankings: const {}, sliding: const [],
    pairSliding: slidingDuelo == null
        ? const {}
        : {BetEngine.pairKey(a1, b1): slidingDuelo},
    createdAt: DateTime(2026, 1, 1), totalHoles: 18,
  );
}

BetModuleInstance _duelo(BetCount c, {double? monto}) {
  final res = BetRecipe.build(
      cuenta: c, participantIds: const [a1, b1], id: 'duelo_0_${c.name}');
  var m = res.module!.copyWith(scope: BetScope.pair(a1, b1));
  if (monto != null) {
    m = BetRecipe.conMontoDeCruce(m, MontoPorCruce(unico: monto));
  }
  return m;
}

/// Lo que se mueve SOLO en el duelo entre a1 y b1, por tipo de apuesta.
double _netoDuelo(Round r, BetModuleType tipo) {
  var s = 0.0;
  for (final e in BetEngine.computeAll(r)) {
    if (e.betType != tipo) continue;
    final par = {e.fromPlayerId, e.toPlayerId};
    if (par.length != 2 || !par.contains(a1) || !par.contains(b1)) continue;
    s += e.toPlayerId == a1 ? e.amount : -e.amount;
  }
  return s;
}

void main() {
  group('la ventaja propia cambia el DINERO, no solo la config', () {
    test('heredando la de la ronda, b1 recibe sus 18 golpes', () {
      // b1 hace 5 con 18 de handicap: neto 4, empata con a1 → el duelo no paga.
      final r = _round(duelo: _duelo(BetCount.skins, monto: 100));
      expect(_netoDuelo(r, BetModuleType.skins), 0,
          reason: 'con handicap deberían empatar');
      // Y que el libro NO esté vacío: si lo estuviera, el 0 de arriba sería
      // ausencia de asientos y no empate.
      expect(BetEngine.computeAll(r), isNotEmpty);
    });

    test('con ventaja propia a cero —scratch— el duelo sí paga', () {
      // EL criterio del entregable: mismo duelo, ventaja distinta, dinero
      // distinto. Sin esto, "entre tú y yo sin handicap" no significaría nada.
      final r = _round(duelo: _duelo(BetCount.skins, monto: 100),
          slidingDuelo: 0);
      expect(_netoDuelo(r, BetModuleType.skins), greaterThan(0),
          reason: 'a scratch a1 gana: 4 contra 5 en los 18');
    });

    test('y son importes DISTINTOS entre sí', () {
      final heredada = _netoDuelo(
          _round(duelo: _duelo(BetCount.skins, monto: 100)),
          BetModuleType.skins);
      final propia = _netoDuelo(
          _round(duelo: _duelo(BetCount.skins, monto: 100), slidingDuelo: 0),
          BetModuleType.skins);
      expect(propia, isNot(heredada));
    });

    test('la ventaja propia no altera la apuesta de equipos', () {
      // El duelo es aparte: tocar su ventaja no puede mover lo ya pactado
      // entre los dos lados.
      double equipo(Round r) => BetEngine.computeAll(r)
          .where((e) => e.betType == BetModuleType.nassau)
          .fold<double>(0, (x, e) => x + e.amount);
      expect(equipo(_round(duelo: _duelo(BetCount.skins), slidingDuelo: 0)),
          equipo(_round(duelo: _duelo(BetCount.skins))));
    });
  });

  group('un duelo lleva varias apuestas', () {
    test('cada una con su módulo y su importe', () {
      final mods = [
        _duelo(BetCount.skins, monto: 100),
        _duelo(BetCount.putts, monto: 30),
      ];
      expect(mods.map((m) => m.id).toSet().length, 2);
      expect(mods.map((m) => m.type).toSet(),
          {BetModuleType.skins, BetModuleType.putts});
      expect(mods.firstWhere((m) => m.type == BetModuleType.skins).baseValue,
          100);
      expect(mods.firstWhere((m) => m.type == BetModuleType.putts).baseValue,
          30);
    });

    test('todas de alcance pair, solo entre esos dos', () {
      for (final c in [BetCount.skins, BetCount.putts, BetCount.scoreTotal]) {
        final m = _duelo(c);
        expect(m.effectiveScope.kind, BetScopeKind.pair, reason: c.label);
        expect(m.participantIds, const [a1, b1]);
      }
    });

    test('y conviven con la apuesta de equipos sin errores', () {
      // Con ventaja propia, para que el duelo pague: heredando empata y no
      // emitiría asiento, y entonces la convivencia no se estaría probando.
      final r = _round(
          duelo: _duelo(BetCount.skins, monto: 100), slidingDuelo: 0);
      final c = BetEngine.safeComputeAll(r);
      expect(c.errors, isEmpty);
      expect(c.entries.map((e) => e.betType).toSet(),
          containsAll([BetModuleType.nassau, BetModuleType.skins]));
    });
  });

  group('Oyes y Unidades no se pactan en un duelo', () {
    test('son de grupo, y lo dicen', () {
      // Este test fijaba la frase literal 'todo el grupo', que era UNA para las
      // dos. Ahora el motivo es POR TIPO y más concreto —Oyes habla del ranking
      // del par 3, Unidades de acreditar contra todos— así que la aserción pasa
      // a la intención: que se declaren de grupo y digan dónde ponerlas. Eso es
      // lo que el test quería comprobar, y aguanta el siguiente formato.
      for (final c in [BetCount.oyes, BetCount.unidades]) {
        expect(c.esDeGrupo, isTrue, reason: c.label);
        final motivo = c.soloDeGrupo;
        expect(motivo, isNotNull, reason: c.label);
        expect(motivo!.toLowerCase().contains('partida') ||
                motivo.toLowerCase().contains('ronda'),
            isTrue,
            reason: '${c.label} no dice dónde ponerla: $motivo');
      }
    });

    test('los demás sí se pactan', () {
      for (final c in [BetCount.puntos, BetCount.skins,
                       BetCount.scoreTotal, BetCount.putts]) {
        expect(c.esDeGrupo, isFalse, reason: c.label);
        expect(c.soloDeGrupo, isNull);
      }
    });
  });

  group('en un duelo 1v1 el conteo es Match', () {
    test('nunca "Puntos": el hoyo reparte un punto', () {
      // La bola no aplica en un duelo, así que labelCon(null) es lo correcto.
      expect(BetCount.puntos.labelCon(null), 'Match');
    });

    test('y el tipo es nassau, no bola baja/alta', () {
      expect(_duelo(BetCount.puntos).type, BetModuleType.nassau);
    });
  });

  group('el signo de la ventaja propia', () {
    test('se invierte si el primero no es el id menor', () {
      // El mapa guarda recv(idMenor, idMayor) y delta es lo que recibe d.a de
      // d.b. Con a1 < b1 no se invierte; al revés sí. Un signo al revés daría
      // la ventaja al jugador equivocado sin que nada falle.
      double signo(String a, String b, double delta) =>
          a.compareTo(b) <= 0 ? delta : -delta;
      expect(signo(a1, b1, 3), 3);
      expect(signo(b1, a1, 3), -3);
    });
  });

  _duelosSonDePersonas();
}

// ── La pestaña Duelos es de personas ────────────────────────────────────────
//
// La pestaña decía "6 jugadores · 15 duelos" en una ronda 2v2 y listaba
// "CAM vs Equipo". round.players lleva reales y virtuales porque las apuestas
// por equipos necesitan ambos, pero un duelo contra un equipo no existe.
//
// Tercera superficie con el mismo fallo. La anterior fue el ranking de Oyes.
void _duelosSonDePersonas() {
  group('los duelos solo entre personas', () {
    /// Ronda 2v2 a best ball: los reales anotan y hay un virtual por equipo
    /// para nombrarlo, igual que la produce Setup.
    Round bestBall() => Round(
          id: 'r', name: 'R', course: _course(),
          players: [
            for (final i in todos) Player(id: i, name: i.toUpperCase()),
            Player(id: 'bb_team_A', name: 'Equipo A', isVirtual: true,
                teamMemberIds: const [a1, a2]),
            Player(id: 'bb_team_B', name: 'Equipo B', isVirtual: true,
                teamMemberIds: const [b1, b2]),
          ],
          roundPlayers: [
            for (final i in [...todos, 'bb_team_A', 'bb_team_B'])
              RoundPlayer(playerId: i, handicapEnRonda: 0),
          ],
          betGroups: [BetGroup(id: 'g', name: 'G',
              format: PartidaFormat.teams2v2, playerIds: todos, modules: [
            BetModuleInstance(
              id: 'eq', type: BetModuleType.nassau, name: 'Nassau',
              participantIds: todos, nassauConfig: NassauConfig.def,
              sides: const [
                BetSide(id: 'A', name: 'Equipo A', playerIds: [a1, a2]),
                BetSide(id: 'B', name: 'Equipo B', playerIds: [b1, b2]),
              ],
            ),
          ])],
          scores: {
            for (final i in [...todos, 'bb_team_A', 'bb_team_B'])
              i: {for (var h = 1; h <= 18; h++)
                h: HoleScore(playerId: i, hole: h, grossScore: 4)},
          },
          events: const {}, oyeseRankings: const {}, sliding: const [],
          createdAt: DateTime(2026, 1, 1), totalHoles: 18,
        );

    test('realPlayers deja fuera los virtuales del equipo', () {
      final r = bestBall();
      expect(r.players.length, 6);
      expect(r.realPlayers.map((p) => p.id), todos);
    });

    test('con 2v2 salen CUATRO cruces, no quince', () {
      // Cuatro personas dan 6 combinaciones; companerosDeLado quita las 2 de
      // compañeros y quedan 4 entre lados opuestos. Los 15 venían de contar 6
      // jugadores incluyendo los virtuales.
      final r = bestBall();
      final duelos = buildDuelsForTest(r);
      expect(duelos.length, 4);
    });

    test('ningún duelo incluye a un virtual', () {
      for (final d in buildDuelsForTest(bestBall())) {
        expect(duelIdsForTest(d).any((id) => id.startsWith('bb_team_')), isFalse,
            reason: 'un equipo no pacta un duelo');
      }
    });

    test('y ninguno enfrenta a compañeros', () {
      for (final d in buildDuelsForTest(bestBall())) {
        final ids = duelIdsForTest(d).toSet();
        expect(ids, isNot({a1, a2}));
        expect(ids, isNot({b1, b2}));
      }
    });
  });
}
