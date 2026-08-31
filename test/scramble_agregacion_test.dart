// ─────────────────────────────────────────────────────────────────────────────
// EL AGUJERO DEL SCRAMBLE, Y LA UNIDAD DE CLASIFICACIÓN
//
// «Una ronda de scramble produce un RoundResult sin score para nadie. Es un bug
// vivo, y afecta al formato principal del producto.»
//
// Llevaba ahí desde el principio y no se veía porque nunca se cerró una ronda
// de scramble marcada para un torneo. Misma familia que los diferenciales
// imposibles: aparece cuando alguien mira.
//
// ── EL BARRIDO, por estructura ──────────────────────────────────────────────
//
// `models.dart` ya documenta tres listas y una tabla de qué superficie usa cuál:
//
//   players         todos, para buscar por id
//   realPlayers     personas: el dinero, los duelos, el ranking de oyes
//   scoringPlayers  quien lleva TARJETA: reales en best ball, el virtual en
//                   scramble
//
// `RoundResult` era la ÚNICA superficie que faltaba en esa tabla, y usaba
// `realPlayers` para todo. De ahí el agujero, y de ahí que sea exactamente uno:
//
//   · scramble        → la tarjeta la lleva el virtual  ROTO
//   · best ball       → la llevan los cuatro reales     bien
//   · bola alterna    → no existe como modo aparte; una bola es scramble
//   · High and Low, Pair vs Field → lados de personas, cada una con su tarjeta
//
// Solo hay DOS creadores de jugador virtual en todo el código —el de scramble,
// que anota, y el `bb_team_` de best ball, que solo nombra al equipo— así que
// la enumeración está cerrada.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/round_result.dart';
import 'package:golf_bet_master/models/shotgun.dart';
import 'package:golf_bet_master/models/torneo.dart';
import 'package:golf_bet_master/providers/round_provider.dart';

const _a = 'ana', _b = 'beto', _c = 'caro', _d = 'dani';

CourseInfo _campo() => CourseInfo(
      name: 'Los Encinos',
      holes: List.generate(
          18,
          (i) => CourseHole(
              hole: i + 1,
              par: const {3, 7, 12, 16}.contains(i + 1) ? 3 : 4,
              strokeIndex: i + 1)),
    );

/// Una ronda de SCRAMBLE de verdad: el equipo entrega una tarjeta.
///
/// Se monta como la monta Setup —un lado con `playMode: scramble` y un jugador
/// virtual que lleva el score— porque probarlo de otra forma probaría otra cosa.
Round _scramble({int golpesPorHoyo = 4}) {
  final personas = [
    Player(id: _a, name: 'Ana'),
    Player(id: _b, name: 'Beto'),
  ];
  const virtualId = 'team_lado1';
  final virtual = Player(
      id: virtualId,
      name: 'Los del sábado',
      isVirtual: true,
      teamMemberIds: [_a, _b]);
  final rivales = [
    Player(id: _c, name: 'Caro'),
    Player(id: _d, name: 'Dani'),
  ];
  const virtualId2 = 'team_lado2';
  final virtual2 = Player(
      id: virtualId2,
      name: 'Los otros',
      isVirtual: true,
      teamMemberIds: [_c, _d]);

  final todos = [...personas, ...rivales, virtual, virtual2];
  return Round(
    id: 'r_scr',
    name: 'Scramble del sábado',
    course: _campo(),
    players: todos,
    // En scramble los reales NO están en el lado: Setup los sustituye por el
    // virtual, y los roundPlayers llevan a los dos virtuales.
    roundPlayers: [
      for (final p in [...personas, ...rivales])
        RoundPlayer(playerId: p.id, handicapEnRonda: 0),
      RoundPlayer(playerId: virtualId, handicapEnRonda: 0),
      RoundPlayer(playerId: virtualId2, handicapEnRonda: 0),
    ],
    betGroups: [
      BetGroup(
        id: 'g',
        name: 'G',
        format: PartidaFormat.teams2v2,
        playerIds: [virtualId, virtualId2],
        modules: [
          BetModuleInstance.defaultFor(
                  BetModuleType.medal, [virtualId, virtualId2], id: 'md')
              .copyWith(sides: [
            BetSide(
                id: 'lado1',
                name: 'Los del sábado',
                playerIds: [virtualId],
                playMode: TeamPlayMode.scramble),
            BetSide(
                id: 'lado2',
                name: 'Los otros',
                playerIds: [virtualId2],
                playMode: TeamPlayMode.scramble),
          ]),
        ],
      ),
    ],
    // El score lo lleva el VIRTUAL. Los reales no tienen ninguno, que es
    // exactamente el estado que producía un resultado vacío.
    scores: {
      virtualId: {
        for (var h = 1; h <= 18; h++)
          h: HoleScore(
              playerId: virtualId, hole: h, grossScore: golpesPorHoyo),
      },
      virtualId2: {
        for (var h = 1; h <= 18; h++)
          h: HoleScore(playerId: virtualId2, hole: h, grossScore: 5),
      },
    },
    events: const {},
    oyeseRankings: const {},
    sliding: const [],
    createdAt: DateTime(2026, 8, 31),
    totalHoles: 18,
    torneoIds: const ['t1'],
    isFinished: true,
  );
}

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('1 · una ronda de scramble cerrada produce score', () {
    test('CLAVE: el equipo tiene gross, neto y Stableford', () {
      // El criterio 1. Antes de esto los tres mapas salían VACÍOS.
      final r = RoundResult.fromRound(_scramble());
      expect(r.grossByPlayer['team_lado1'], 72, reason: '18 × 4');
      expect(r.grossByPlayer['team_lado2'], 90, reason: '18 × 5');
      expect(r.netByPlayer.containsKey('team_lado1'), isTrue);
      expect(r.stablefordByPlayer.containsKey('team_lado1'), isTrue);
      expect(r.holesPlayed, 18, reason: 'y los hoyos, que también salían a 0');
    });

    test('CLAVE: y NO se le atribuye a los cuatro — el histórico de handicap',
        () {
      // Es la parte que importa más. Un scramble sale seis u ocho golpes por
      // debajo de lo que cualquiera firmaría solo. Meter ese 72 como score
      // personal de los cuatro produce diferenciales que no existen, en el
      // sitio donde nadie los comprueba.
      final r = RoundResult.fromRound(_scramble());
      for (final pid in [_a, _b, _c, _d]) {
        expect(r.grossByPlayer.containsKey(pid), isFalse, reason: pid);
        expect(r.netByPlayer.containsKey(pid), isFalse, reason: pid);
      }
    });

    test('CLAVE: el equipo tiene NOMBRE — sin él la tabla diría «—»', () {
      final r = RoundResult.fromRound(_scramble());
      expect(r.playerNames['team_lado1'], 'Los del sábado');
      // Y las personas siguen ahí: el dinero es de ellas.
      expect(r.playerNames[_a], 'Ana');
      expect(r.playerIds, containsAll([_a, _b, _c, _d]));
      expect(r.playerIds, isNot(contains('team_lado1')),
          reason: 'quien juega es una persona; quien anota puede no serlo');
    });

    test('el resultado sobrevive al viaje por Firestore', () {
      final ida = RoundResult.fromRound(_scramble());
      final vuelta = RoundResult.fromJson(ida.toJson());
      expect(vuelta.grossByPlayer['team_lado1'], 72);
      expect(vuelta.playerNames['team_lado1'], 'Los del sábado');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('2 · lo que NO era el agujero, comprobado', () {
    test('CLAVE: en best ball siguen anotando los cuatro reales', () {
      // El barrido decía que best ball estaba bien. Esto lo fija: si algún día
      // alguien "arregla" best ball moviéndolo al virtual, los cuatro perderían
      // su score individual y su handicap dejaría de alimentarse.
      final personas = [
        Player(id: _a, name: 'Ana'),
        Player(id: _b, name: 'Beto'),
      ];
      final bb = Player(
          id: 'bb_team_l1',
          name: 'Equipo',
          isVirtual: true,
          teamMemberIds: [_a, _b]);
      final r = Round(
        id: 'r_bb',
        name: 'Best ball',
        course: _campo(),
        players: [...personas, bb],
        roundPlayers: [
          for (final p in personas)
            RoundPlayer(playerId: p.id, handicapEnRonda: 0),
          RoundPlayer(playerId: bb.id, handicapEnRonda: 0),
        ],
        betGroups: [
          BetGroup(
            id: 'g',
            name: 'G',
            format: PartidaFormat.teams2v2,
            playerIds: [_a, _b],
            modules: [
              BetModuleInstance.defaultFor(BetModuleType.medal, [_a, _b],
                      id: 'md')
                  .copyWith(sides: [
                BetSide(id: 'l1', name: 'Equipo', playerIds: [_a, _b]),
              ]),
            ],
          ),
        ],
        scores: {
          for (final p in personas)
            p.id: {
              for (var h = 1; h <= 18; h++)
                h: HoleScore(playerId: p.id, hole: h, grossScore: 5),
            },
        },
        events: const {},
        oyeseRankings: const {},
        sliding: const [],
        createdAt: DateTime(2026, 8, 31),
        totalHoles: 18,
        isFinished: true,
      );
      final res = RoundResult.fromRound(r);
      expect(res.grossByPlayer[_a], 90);
      expect(res.grossByPlayer[_b], 90);
      expect(res.grossByPlayer.containsKey('bb_team_l1'), isFalse,
          reason: 'el bb_team_ solo nombra al equipo; no anota');
    });

    test('CLAVE: una ronda normal no cambia en nada', () {
      // El criterio 4. `scoringPlayers` sin lados devuelve los reales, así que
      // esto tiene que dar exactamente lo de siempre.
      final ps = [Player(id: _a, name: 'Ana'), Player(id: _b, name: 'Beto')];
      final r = Round(
        id: 'r',
        name: 'Sábado',
        course: _campo(),
        players: ps,
        roundPlayers:
            ps.map((p) => RoundPlayer(playerId: p.id, handicapEnRonda: 0)).toList(),
        betGroups: [
          BetGroup(
              id: 'g',
              name: 'G',
              format: PartidaFormat.oneVsOne,
              playerIds: [_a, _b],
              modules: [
                BetModuleInstance.defaultFor(BetModuleType.skins, [_a, _b],
                    id: 'sk')
              ]),
        ],
        scores: {
          for (final p in ps)
            p.id: {
              for (var h = 1; h <= 18; h++)
                h: HoleScore(playerId: p.id, hole: h, grossScore: 4),
            },
        },
        events: const {},
        oyeseRankings: const {},
        sliding: const [],
        createdAt: DateTime(2026, 8, 31),
        totalHoles: 18,
        isFinished: true,
      );
      final res = RoundResult.fromRound(r);
      expect(res.grossByPlayer[_a], 72);
      expect(res.grossByPlayer[_b], 72);
      expect(res.grossByPlayer.keys.length, 2);
      expect(res.holesPlayed, 18);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 3 · LA UNIDAD DE CLASIFICACIÓN
  //
  // El único cambio en la agregación: contra qué se filtra la tabla. Todo lo
  // demás —orden, puestos, empates, mejores N, par acumulado— no sabía qué era
  // un "jugador": suma medidas por clave.
  // ───────────────────────────────────────────────────────────────────────────
  group('3 · un torneo por equipos tiene tabla, con una fila por equipo', () {
    Torneo porEquipos() => Torneo(
          id: 't1',
          nombre: 'Copa por equipos',
          metodo: MetodoDePuntuacion.scoreNeto,
          participantes: const [_a, _b, _c, _d],
        ).copyWith(porEquipos: true, equipos: const [
          EquipoDeTorneo(
              numero: 1,
              nombre: 'Los del sábado',
              miembros: [_a, _b],
              hoyoDeSalida: 1),
          EquipoDeTorneo(numero: 2, miembros: [_c, _d], hoyoDeSalida: 2),
        ]);

    /// El resultado de una ronda cuyo equipo 01 anotó [neto].
    RoundResult _res(String id, {required int neto1, required int neto2}) =>
        RoundResult(
          roundId: id,
          roundName: id,
          courseName: 'Los Encinos',
          playedAt: DateTime(2026, 8, 31),
          holesPlayed: 18,
          parDeLaRonda: 68,
          playerIds: const [_a, _b, _c, _d],
          playerNames: const {
            _a: 'Ana',
            _b: 'Beto',
            _c: 'Caro',
            _d: 'Dani',
            'e01': 'Equipo 01 · Los del sábado',
            'e02': 'Equipo 02',
          },
          balances: const {},
          pairBalances: const {},
          grossByPlayer: {'e01': neto1, 'e02': neto2},
          netByPlayer: {'e01': neto1, 'e02': neto2},
          torneoIds: const ['t1'],
        );

    test('CLAVE: una fila por EQUIPO, no por persona', () {
      final tabla = tablaDe(porEquipos(), [_res('r1', neto1: 65, neto2: 71)]);
      expect(tabla.filas.map((f) => f.playerId), ['e01', 'e02']);
      expect(tabla.filas.first.nombre, 'Equipo 01 · Los del sábado');
      expect(tabla.filas.first.total, 65);
    });

    test('CLAVE: un equipo sin nombre se llama por su número', () {
      final tabla = tablaDe(porEquipos(), [_res('r1', neto1: 65, neto2: 71)]);
      expect(tabla.filas.last.nombre, 'Equipo 02');
    });

    test('CLAVE: y las personas NO salen en la tabla', () {
      // Ochenta y ocho filas vacías es lo que habría sin esto: los miembros no
      // tienen score propio porque jugaron una bola.
      final tabla = tablaDe(porEquipos(), [_res('r1', neto1: 65, neto2: 71)]);
      final ids = [...tabla.filas, ...tabla.bajoMinimo].map((f) => f.playerId);
      for (final pid in [_a, _b, _c, _d]) {
        expect(ids, isNot(contains(pid)), reason: pid);
      }
    });

    test('CLAVE: un equipo formado que aún no ha salido SÍ se ve', () {
      // Estar formado es un hecho aunque no hayas salido, igual que estar
      // inscrito. Y con su nombre, no con un guion.
      final tabla = tablaDe(porEquipos(), const []);
      final todas = [...tabla.filas, ...tabla.bajoMinimo];
      expect(todas.map((f) => f.playerId), containsAll(['e01', 'e02']));
      expect(todas.firstWhere((f) => f.playerId == 'e02').nombre, 'Equipo 02');
    });

    test('CLAVE: el par acumulado y las mejores N siguen funcionando', () {
      // La agregación no sabía qué era un jugador. Esto lo comprueba: dos
      // rondas, y el bajo par sale de la suma de las dos.
      final tabla = tablaDe(porEquipos(), [
        _res('r1', neto1: 65, neto2: 71),
        _res('r2', neto1: 66, neto2: 70),
      ]);
      final primera = tabla.filas.first;
      expect(primera.total, 131, reason: '65 + 66');
      expect(primera.parDeLasQueCuentan, 136, reason: '68 × 2');
    });

    test('CONTRAPESO: el MISMO torneo sin la bandera clasifica personas', () {
      // Es el criterio 4 mirado desde el otro lado: lo único que cambia es la
      // bandera, y con ella apagada la tabla es la de siempre.
      final individual = Torneo(
        id: 't1',
        nombre: 'Copa',
        metodo: MetodoDePuntuacion.scoreNeto,
        participantes: const [_a, _b, _c, _d],
      );
      final tabla = tablaDe(individual, [
        RoundResult(
          roundId: 'r1',
          roundName: 'r1',
          courseName: 'C',
          playedAt: DateTime(2026, 8, 31),
          holesPlayed: 18,
          playerIds: const [_a, _b],
          playerNames: const {_a: 'Ana', _b: 'Beto'},
          balances: const {},
          pairBalances: const {},
          grossByPlayer: const {_a: 74, _b: 78},
          netByPlayer: const {_a: 70, _b: 74},
          torneoIds: const ['t1'],
        )
      ]);
      final ids = [...tabla.filas, ...tabla.bajoMinimo].map((f) => f.playerId);
      expect(ids, containsAll([_a, _b]));
      expect(ids.where((x) => x.startsWith('e0')), isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('4 · la ronda del shotgun por equipos lleva una tarjeta', () {
    test('CLAVE: el equipo entra como jugador y la ronda lo declara', () {
      // Una ronda de shotgun NO tiene apuestas, así que `scoringPlayers` no
      // puede deducir nada de los lados. La ronda lo dice.
      final plan = planDeShotgun(
          padron: const [_a, _b, _c, _d], campo: _campo(), tamano: 4);
      final equipos = equiposDelPlan(plan, nombresPuestos: {1: 'Sierra'});
      final rondas = rondasDelPlan(
        plan: plan,
        torneoId: 't1',
        campo: _campo(),
        porId: {
          _a: Player(id: _a, name: 'Ana'),
          _b: Player(id: _b, name: 'Beto'),
          _c: Player(id: _c, name: 'Caro'),
          _d: Player(id: _d, name: 'Dani'),
        },
        cuando: DateTime(2026, 8, 31),
        equipos: equipos,
      );
      final r = rondas.single;
      expect(r.equipoId, 'e01');
      // Los cuatro siguen en la ronda: son quienes juegan y quienes editan.
      expect(r.realPlayers.length, 4);
      // Y la tarjeta es UNA, la del equipo.
      expect(r.scoringPlayers.map((p) => p.id), ['e01']);
      expect(r.scoringPlayers.single.name, 'Equipo 01 · Sierra');
    });

    test('CLAVE: sin equipos, los cuatro llevan su tarjeta — como siempre', () {
      final plan = planDeShotgun(
          padron: const [_a, _b, _c, _d], campo: _campo(), tamano: 4);
      final r = rondasDelPlan(
        plan: plan,
        torneoId: 't1',
        campo: _campo(),
        porId: {
          _a: Player(id: _a, name: 'Ana'),
          _b: Player(id: _b, name: 'Beto'),
          _c: Player(id: _c, name: 'Caro'),
          _d: Player(id: _d, name: 'Dani'),
        },
        cuando: DateTime(2026, 8, 31),
      ).single;
      expect(r.equipoId, isNull);
      expect(r.scoringPlayers.length, 4);
    });

    test('CLAVE: y el declarado sobrevive al guardado', () {
      // `saveRound` escribe con merge:false: sin serializar `equipoId`, la
      // ronda se recarga y los cuatro vuelven a tener tarjeta propia.
      final plan = planDeShotgun(
          padron: const [_a, _b, _c, _d], campo: _campo(), tamano: 4);
      final r = rondasDelPlan(
        plan: plan,
        torneoId: 't1',
        campo: _campo(),
        porId: {
          _a: Player(id: _a, name: 'Ana'),
          _b: Player(id: _b, name: 'Beto'),
          _c: Player(id: _c, name: 'Caro'),
          _d: Player(id: _d, name: 'Dani'),
        },
        cuando: DateTime(2026, 8, 31),
        equipos: equiposDelPlan(plan),
      ).single;
      expect(roundFromJson(roundToJson(r)).equipoId, 'e01');
      expect(roundFromJson(roundToJson(r)).scoringPlayers.single.id, 'e01');
    });
  });
}
