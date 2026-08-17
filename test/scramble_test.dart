// ─────────────────────────────────────────────────────────────────────────────
// scramble_test.dart — el equipo entrega una tarjeta, y esa tarjeta liquida
//
// Scramble llegaba a la mitad: la captura pedía dos scores y el handicap
// combinado se calculaba, pero la ronda acababa en $0 con un aviso de "no
// tiene score de todos sus jugadores".
//
// La causa NO era la validación, aunque fuera lo que se veía:
// GameEngine.holeDeltaVs resolvía el score del lado recorriendo
// side.playerIds —los reales—, que en scramble ni siquiera están en la ronda.
// Ningún score → hoyo no jugado → deltas a cero en los 18 → sin asientos.
//
// El criterio que fija esto: un scramble liquida lo MISMO que un best ball con
// los mismos scores de equipo. Si difiere, el arreglo cambió el cálculo en vez
// de conectarlo.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';

const a1 = 'a1', a2 = 'a2', b1 = 'b1', b2 = 'b2';
const va = 'team_A', vb = 'team_B';

CourseInfo _course() => CourseInfo(name: 'T',
    holes: List.generate(18,
        (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)));

/// Scores por hoyo del equipo A y del B. Iguales en los dos montajes.
const scoresA = 4, scoresB = 5;

BetModuleInstance _mod(TeamPlayMode modo, List<String> pa, List<String> pb) =>
    BetModuleInstance(
      id: 'm', type: BetModuleType.nassau, name: 'Nassau',
      participantIds: [...pa, ...pb],
      nassauConfig: NassauConfig.def,
      sides: [
        BetSide(id: 'A', name: 'Equipo A', playerIds: pa, playMode: modo),
        BetSide(id: 'B', name: 'Equipo B', playerIds: pb, playMode: modo),
      ],
    );

Round _round({
  required List<Player> jugadores,
  required BetModuleInstance mod,
  required Map<String, int> porHoyo,
  int hasta = 18,
}) =>
    Round(
      id: 'r', name: 'R', course: _course(),
      players: jugadores,
      roundPlayers: [
        for (final p in jugadores)
          RoundPlayer(playerId: p.id, handicapEnRonda: 0),
      ],
      betGroups: [BetGroup(id: 'g', name: 'G',
          format: PartidaFormat.teams2v2,
          playerIds: jugadores.map((p) => p.id).toList(), modules: [mod])],
      scores: {
        for (final e in porHoyo.entries)
          e.key: {
            for (var h = 1; h <= hasta; h++)
              h: HoleScore(playerId: e.key, hole: h, grossScore: e.value),
          },
      },
      events: const {}, oyeseRankings: const {}, sliding: const [],
      createdAt: DateTime(2026, 1, 1), totalHoles: 18,
    );

/// Montaje TAL COMO LO PRODUCE SETUP.
///
/// Es la forma que hay que probar, y la que este archivo NO probaba: Setup
/// reescribe los lados en scramble —PASO 3, setup_screen.dart— para que
/// playerIds contenga el VIRTUAL y no los reales. El comentario de ahí ya
/// avisaba: "si el side conservara los IDs reales, el motor buscaría scores
/// que no existen".
///
/// Mi montaje original dejaba los ids reales en el lado. Pasaba, pero probaba
/// un escenario que la app no genera — dando por bueno el arreglo sobre datos
/// que nunca ocurren.
Round _setupShape({int hasta = 18}) => _round(
      jugadores: [
        for (final i in [a1, a2, b1, b2]) Player(id: i, name: i),
        Player(id: va, name: 'Equipo A', isVirtual: true,
            teamMemberIds: const [a1, a2]),
        Player(id: vb, name: 'Equipo B', isVirtual: true,
            teamMemberIds: const [b1, b2]),
      ],
      mod: _mod(TeamPlayMode.scramble, const [va], const [vb]),
      porHoyo: const {va: scoresA, vb: scoresB},
      hasta: hasta,
    );

/// Montaje con los ids REALES en el lado. No es lo que Setup produce hoy, pero
/// una ronda guardada antes de PASO 3 puede tener esta forma, y
/// scoreCarriersOf tiene que resolverla igual.
Round _scramble({int hasta = 18}) => _round(
      jugadores: [
        Player(id: va, name: 'Equipo A', isVirtual: true,
            teamMemberIds: [a1, a2]),
        Player(id: vb, name: 'Equipo B', isVirtual: true,
            teamMemberIds: [b1, b2]),
      ],
      mod: _mod(TeamPlayMode.scramble, const [a1, a2], const [b1, b2]),
      porHoyo: const {va: scoresA, vb: scoresB},
      hasta: hasta,
    );

/// Montaje best ball con el MISMO score de equipo: el mejor de cada lado
/// coincide con lo que entregó el scramble.
Round _bestBall() => _round(
      jugadores: [a1, a2, b1, b2].map((i) => Player(id: i, name: i)).toList(),
      mod: _mod(TeamPlayMode.bestBall, const [a1, a2], const [b1, b2]),
      porHoyo: const {
        a1: scoresA, a2: scoresA + 2, // el mejor de A es scoresA
        b1: scoresB, b2: scoresB + 2, // el mejor de B es scoresB
      },
    );

double _total(List<LedgerEntry> e) =>
    e.fold(0.0, (acc, x) => acc + x.amount);

void main() {
  group('scramble liquida', () {
    test('una ronda completa produce asientos, no \$0', () {
      final entries = BetEngine.computeAll(_scramble());
      expect(entries, isNotEmpty,
          reason: 'el equipo entregó tarjeta y la apuesta no pagó');
    });

    test('cobran las PERSONAS del equipo ganador, no el virtual', () {
      // A hace 4 por hoyo y B hace 5: gana A. El importe del equipo se reparte
      // entre los cruces —teamCrossAmount— así que los asientos van a nombre
      // de gente real. El virtual anota la tarjeta; no cobra: la deuda es
      // entre personas.
      final entries = BetEngine.computeAll(_scramble());
      expect(entries.every((e) => [a1, a2].contains(e.toPlayerId)), isTrue,
          reason: 'cobró el lado equivocado');
      expect(entries.every((e) => [b1, b2].contains(e.fromPlayerId)), isTrue);
      expect(entries.any((e) => e.toPlayerId == va || e.fromPlayerId == va),
          isFalse, reason: 'el jugador virtual aparece en el libro');
    });

    test('cubre los tres segmentos del Nassau', () {
      final motivos =
          BetEngine.computeAll(_scramble()).map((e) => e.reason).toSet();
      expect(motivos.length, 3, reason: 'faltan segmentos: $motivos');
    });
  });

  group('la forma que produce Setup', () {
    // Es la que ejecuta la app. Probar solo la otra era darse el visto bueno
    // sobre datos que nunca ocurren.
    test('el lado lleva el virtual, no los reales', () {
      final mod = _setupShape().betGroups.first.modules.first;
      expect(mod.sideA.playerIds, [va]);
      expect(mod.hasTeamSides, isTrue,
          reason: 'con un jugador por lado el motor debe seguir enrutando a equipos');
    });

    test('liquida, y sin errores de integridad', () {
      final c = BetEngine.safeComputeAll(_setupShape());
      expect(c.errors, isEmpty);
      expect(c.entries, isNotEmpty);
    });

    test('un lado de un solo virtual no confunde a scoreCarriersOf', () {
      // El virtual no tiene un virtual dentro, así que no hay emparejamiento
      // posible y se devuelve el propio lado. Que sea el resultado correcto
      // por el camino del fallback merece test propio: si alguien endurece
      // ese fallback, esto se rompe.
      final r = _setupShape();
      final mod = r.betGroups.first.modules.first;
      expect(r.scoreCarriersOf(mod.sideA), [va]);
      expect(r.scoreCarriersOfModule(mod, const []), [va, vb]);
    });

    test('los 18 hoyos cuentan como completos', () {
      final r = _setupShape();
      final g = r.betGroups.first;
      final pids = r.scoreCarriersOfModule(g.modules.first, g.playerIds);
      final completos = r.course.holes
          .where((ch) => pids.every((p) => r.getScore(p, ch.hole).hasScore))
          .length;
      expect(completos, 18, reason: 'el aviso de incompleta seguiría encendido');
    });

    test('paga lo mismo que la forma con ids reales', () {
      expect(_total(BetEngine.computeAll(_setupShape())),
          _total(BetEngine.computeAll(_scramble())));
    });
  });

  group('el importe coincide con best ball', () {
    test('mismo score de equipo, mismo dinero', () {
      // Es EL criterio: si difiere, el arreglo cambió el cálculo en vez de
      // conectarlo. La forma de jugar no debería mover el importe cuando el
      // resultado del equipo es idéntico.
      final scr = BetEngine.computeAll(_scramble());
      final bb = BetEngine.computeAll(_bestBall());
      expect(_total(scr), _total(bb));
      expect(scr.length, bb.length);
    });

    test('y los mismos motivos, segmento a segmento', () {
      final scr = BetEngine.computeAll(_scramble()).map((e) => e.reason).toList();
      final bb = BetEngine.computeAll(_bestBall()).map((e) => e.reason).toList();
      expect(scr, bb);
    });
  });

  group('quién anota por un lado', () {
    test('en scramble, el virtual del equipo', () {
      final r = _scramble();
      final mod = r.betGroups.first.modules.first;
      expect(r.scoreCarriersOf(mod.sideA), [va]);
      expect(r.scoreCarriersOf(mod.sideB), [vb]);
    });

    test('en best ball, los reales', () {
      final r = _bestBall();
      final mod = r.betGroups.first.modules.first;
      expect(r.scoreCarriersOf(mod.sideA), [a1, a2]);
    });

    test('se empareja por composición, no por el patrón del id', () {
      // El nombre 'team_X' es una convención de Setup; el motor no debe
      // depender de cómo la escriba.
      final r = _round(
        jugadores: [
          Player(id: 'cualquier_cosa', name: 'A', isVirtual: true,
              teamMemberIds: [a1, a2]),
          Player(id: 'otra', name: 'B', isVirtual: true,
              teamMemberIds: [b1, b2]),
        ],
        mod: _mod(TeamPlayMode.scramble, const [a1, a2], const [b1, b2]),
        porHoyo: const {'cualquier_cosa': 4, 'otra': 5},
      );
      final mod = r.betGroups.first.modules.first;
      expect(r.scoreCarriersOf(mod.sideA), ['cualquier_cosa']);
      expect(BetEngine.computeAll(r), isNotEmpty);
    });

    test('sin virtual se cae a los reales en vez de reventar', () {
      final r = _round(
        jugadores: [a1, a2, b1, b2].map((i) => Player(id: i, name: i)).toList(),
        mod: _mod(TeamPlayMode.scramble, const [a1, a2], const [b1, b2]),
        porHoyo: const {a1: 4, a2: 4, b1: 5, b2: 5},
      );
      final mod = r.betGroups.first.modules.first;
      expect(r.scoreCarriersOf(mod.sideA), [a1, a2]);
    });
  });

  group('la validación de completitud usa la misma fuente', () {
    test('un scramble completo no tiene jugadores sin score', () {
      // Es lo que encendía el aviso "Nassau no tiene score de todos sus
      // jugadores" de forma permanente.
      final r = _scramble();
      final g = r.betGroups.first;
      final pids = r.scoreCarriersOfModule(g.modules.first, g.playerIds);
      final completos = r.course.holes
          .where((ch) => pids.every((p) => r.getScore(p, ch.hole).hasScore))
          .length;
      expect(completos, r.course.holes.length);
    });

    test('media ronda sí se marca incompleta', () {
      // La validación tiene que seguir sirviendo para lo que sirve.
      final r = _scramble(hasta: 9);
      final g = r.betGroups.first;
      final pids = r.scoreCarriersOfModule(g.modules.first, g.playerIds);
      final completos = r.course.holes
          .where((ch) => pids.every((p) => r.getScore(p, ch.hole).hasScore))
          .length;
      expect(completos, lessThan(r.course.holes.length));
    });
  });

  _oyes();
}

// ── Oyes: cosas que solo hace una persona ────────────────────────────────────
//
// En los par 3 el ranking ofrecía como participantes a los cuatro jugadores Y
// a Equipo A y Equipo B. round.players lleva ambos porque las apuestas por
// equipos los necesitan, pero un equipo no pega un tiro de aproximación.
void _oyes() {
  group('el ranking de Oyes es de personas', () {
    test('realPlayers excluye los virtuales', () {
      final r = _scramble();
      expect(r.players.length, 2, reason: 'el montaje tiene dos virtuales');
      expect(r.realPlayers, isEmpty,
          reason: 'ambos jugadores del montaje son virtuales');
    });

    test('con reales y virtuales mezclados, solo salen los reales', () {
      // Es el caso de la app: players lleva los 4 reales y los 2 virtuales.
      final r = _round(
        jugadores: [
          for (final i in [a1, a2, b1, b2]) Player(id: i, name: i),
          Player(id: va, name: 'Equipo A', isVirtual: true,
              teamMemberIds: const [a1, a2]),
          Player(id: vb, name: 'Equipo B', isVirtual: true,
              teamMemberIds: const [b1, b2]),
        ],
        mod: _mod(TeamPlayMode.scramble, const [a1, a2], const [b1, b2]),
        porHoyo: const {va: 4, vb: 5},
      );
      expect(r.players.length, 6);
      expect(r.realPlayers.map((p) => p.id), [a1, a2, b1, b2]);
    });
  });
}
