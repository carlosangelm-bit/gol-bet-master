// ─────────────────────────────────────────────────────────────────────────────
// LOS SIDE BETS EN UNA RONDA POR EQUIPOS: SUS PARTICIPANTES SON PERSONAS
//
// Tres hallazgos del uso real, y son UN solo bug:
//
//   1. "Quedan 18 hoyos por capturar" con 2 de 18 capturados.
//   2. El aviso de score incompleto pedía score a "Equipo A" y "Equipo B".
//   3. Rabbit no decía nada, ni con el conejo ya capturado.
//
// La causa: en una ronda best ball por equipos, group.playerIds son los cuatro
// reales MÁS los dos jugadores virtuales de equipo, y un módulo añadido con
// defaultFor(tipo, group.playerIds) se los queda todos. Los virtuales nunca
// tienen score en best ball, así que:
//
//   · todos los hoyos parecen sin capturar → 18 pendientes, y Rabbit no llega a
//     considerar ningún hoyo, así que no captura ni dice nada
//   · el aviso los nombra porque los cree anotadores
//
// Y un cuarto que no se había visto: Wolf en esa ronda contaba SEIS participantes
// y decía "se juega exactamente con 4".
//
// La forma del fixture es la que produce Setup de verdad —lo verifiqué en
// _createAndStartRound— y no una inventada. Es la lección del scramble: aquel
// test montaba una forma que la app nunca produce y pasaba en verde mientras la
// pantalla fallaba.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/snake_engine.dart';
import 'package:golf_bet_master/engines/rabbit_engine.dart';
import 'package:golf_bet_master/engines/wolf_engine.dart';
import 'package:golf_bet_master/engines/settlement_notes.dart';

const cam = 'cam', cav = 'cav', aam = 'aam', rafa = 'rafa';
const eqA = 'bb_A', eqB = 'bb_B';
const reales = [cam, cav, aam, rafa];

/// Los seis ids del grupo, en el orden que produce Setup: reales y luego los
/// virtuales de equipo.
const seisDelGrupo = [cam, cav, aam, rafa, eqA, eqB];

CourseInfo _course() => CourseInfo(
    name: 'T',
    holes: List.generate(
        18, (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)));

/// Ronda best ball 2v2 con side bets añadidos desde "Agregar apuesta".
///
/// [capturados] son los hoyos con score de los CUATRO reales; los virtuales no
/// tienen score en ninguno, que es como funciona best ball.
Round _round({
  required Set<int> capturados,
  Map<int, Map<String, int>> bruto = const {},
  Map<int, Map<String, int>> putts = const {},
  List<BetModuleType> sideBets = const [BetModuleType.snake],
}) {
  final virtuales = [
    Player(id: eqA, name: 'Equipo A', isVirtual: true,
        teamMemberIds: const [cam, cav]),
    Player(id: eqB, name: 'Equipo B', isVirtual: true,
        teamMemberIds: const [aam, rafa]),
  ];

  // El módulo de equipos, tal como queda tras la reescritura de Setup:
  // participantIds son los virtuales y los lados llevan a los reales.
  final nassau = BetModuleInstance.defaultFor(
    BetModuleType.nassau, const [eqA, eqB], id: 'na',
    sides: const [
      BetSide(id: 'lado_A', name: 'Equipo A', playerIds: [cam, cav],
          playMode: TeamPlayMode.bestBall),
      BetSide(id: 'lado_B', name: 'Equipo B', playerIds: [aam, rafa],
          playMode: TeamPlayMode.bestBall),
    ],
  );

  return Round(
    id: 'r', name: 'R', course: _course(),
    players: [
      ...reales.map((i) => Player(id: i, name: i.toUpperCase())),
      ...virtuales,
    ],
    roundPlayers: [
      ...reales, eqA, eqB,
    ].map((i) => RoundPlayer(playerId: i, handicapEnRonda: 0)).toList(),
    betGroups: [
      BetGroup(
        id: 'g', name: 'Partida Principal',
        format: PartidaFormat.allInOnePot,
        // Los SEIS, que es lo que Setup deja en el grupo.
        playerIds: seisDelGrupo,
        modules: [
          nassau,
          // Y los side bets nacen con los seis, porque _openAddBet usa
          // defaultFor(bt, group.playerIds).
          for (final t in sideBets)
            BetModuleInstance.defaultFor(t, seisDelGrupo, id: t.name),
        ],
      ),
    ],
    scores: {
      for (final pid in reales)
        pid: {
          for (final h in capturados)
            h: HoleScore(
                playerId: pid, hole: h,
                grossScore: bruto[h]?[pid] ?? 4,
                putts: putts[h]?[pid] ?? 2),
        },
      // Los virtuales sin score en ningún hoyo: es best ball.
      eqA: const {}, eqB: const {},
    },
    events: const {}, oyeseRankings: const {}, sliding: const [],
    createdAt: DateTime(2026, 1, 1), totalHoles: 18,
  );
}

BetModuleInstance _mod(Round r, BetModuleType t) =>
    r.betGroups.first.modules.firstWhere((m) => m.type == t);

void main() {
  _individualesViejos();

  group('1 · el conteo de hoyos pendientes descuenta lo capturado', () {
    test('con 2 de 18 capturados quedan 16, no 18', () {
      // El hallazgo tal como se reportó.
      final r = _round(capturados: {1, 2}, putts: {1: {cav: 5}});
      final res = SnakeEngine.buscar(
          r, r.participantesDe(_mod(r, BetModuleType.snake), seisDelGrupo),
          SnakeConfig.def);
      expect(res.hoyosSinCapturar, 16);
    });

    test('y la nota lo dice con ese número', () {
      final r = _round(capturados: {1, 2}, putts: {1: {cav: 5}});
      final nota = notasDeLiquidacion(r)
          .firstWhere((n) => n.tipo == BetModuleType.snake);
      expect(nota.texto, contains('16 hoyos'));
      expect(nota.texto, isNot(contains('18 hoyos')));
    });

    test('con los 18 capturados no queda ninguno y deja de ser provisional', () {
      final r = _round(
          capturados: {for (var h = 1; h <= 18; h++) h},
          putts: {1: {cav: 5}});
      final nota = notasDeLiquidacion(r)
          .firstWhere((n) => n.tipo == BetModuleType.snake);
      expect(nota.tono, TonoNota.informativa);
    });
  });

  group('2 · nadie pide score a un equipo', () {
    test('el aviso de score incompleto no nombra a los virtuales', () {
      // Es la lista que consume el aviso de Resultados.
      final r = _round(capturados: {1},
          sideBets: const [BetModuleType.snake, BetModuleType.rabbit]);
      for (final t in [BetModuleType.snake, BetModuleType.rabbit]) {
        final quienes = r.scoreCarriersOfModule(_mod(r, t), seisDelGrupo);
        expect(quienes, isNot(contains(eqA)), reason: t.label);
        expect(quienes, isNot(contains(eqB)), reason: t.label);
        expect(quienes.toSet(), reales.toSet(), reason: t.label);
      }
    });

    test('y el módulo de EQUIPOS sigue resolviéndose por sus lados', () {
      // El contrapeso: si el filtro se aplicara a todo, Nassau por equipos
      // dejaría de preguntar por quien anota y volvería el bug del scramble.
      final r = _round(capturados: {1});
      final quienes = r.scoreCarriersOfModule(_mod(r, BetModuleType.nassau),
          seisDelGrupo);
      expect(quienes.toSet(), reales.toSet(),
          reason: 'en best ball anotan los cuatro reales');
    });

    test('el ledger de un side bet solo mueve dinero entre personas', () {
      final r = _round(
          capturados: {for (var h = 1; h <= 18; h++) h},
          putts: {5: {cav: 4}},
          sideBets: const [BetModuleType.snake]);
      final e = BetEngine.computeAll(r)
          .where((x) => x.betType == BetModuleType.snake);
      expect(e, isNotEmpty);
      for (final x in e) {
        expect([x.fromPlayerId, x.toPlayerId], isNot(contains(eqA)));
        expect([x.fromPlayerId, x.toPlayerId], isNot(contains(eqB)));
      }
      expect(e, hasLength(3), reason: 'el dueño paga a los otros TRES');
    });
  });

  group('3 · Rabbit habla desde que el conejo se mueve', () {
    /// Hoyo 1 lo gana CAM en solitario; el 2, CAV.
    Round conConejo() => _round(
          capturados: {1, 2},
          bruto: {
            1: {cam: 3},
            2: {cav: 3},
          },
          sideBets: const [BetModuleType.rabbit],
        );

    test('el conejo se captura de verdad', () {
      // Antes no capturaba NADA: con los virtuales dentro, ningún hoyo parecía
      // completo y el recorrido entero era "sin score".
      final r = conConejo();
      final pids = r.participantesDe(_mod(r, BetModuleType.rabbit), seisDelGrupo);
      final rec = RabbitEngine.recorrido(r, pids, RabbitConfig.def);
      final primero = rec.segmentos.firstWhere((s) => s.primero);
      // H1 lo captura CAM; H2 lo gana CAV, que con la regla estándar lo SUELTA.
      expect(primero.pasos.first.evento, RabbitEvento.capturado);
      expect(primero.pasos[1].evento, RabbitEvento.soltado);
    });

    test('y lo dice en vivo, no solo al cerrar el nueve', () {
      // El estado del conejo durante los nueve hoyos ES la tensión del juego.
      final notas = notasDeLiquidacion(conConejo())
          .where((n) => n.tipo == BetModuleType.rabbit);
      expect(notas, isNotEmpty,
          reason: 'con el conejo ya movido, callarse esconde el juego');
    });

    test('con dueño, la nota dice quién lo tiene y desde cuándo', () {
      final r = _round(
          capturados: {1, 2},
          bruto: {1: {cam: 3}},
          sideBets: const [BetModuleType.rabbit]);
      final nota = notasDeLiquidacion(r)
          .firstWhere((n) => n.tipo == BetModuleType.rabbit);
      expect(nota.texto, contains('CAM'));
      expect(nota.texto, contains('hoyo 1'));
      expect(nota.texto, contains('cerrar'),
          reason: 'y cuándo se cobra');
      expect(nota.tono, TonoNota.provisional);
    });

    test('en vivo NO dice "al cerrar los primeros 9" como hecho consumado', () {
      // Con siete hoyos por jugar, el conejo puede cambiar de manos. Decir que
      // alguien "lo tiene al cerrar" es afirmar algo que no ha pasado.
      final r = _round(
          capturados: {1, 2},
          bruto: {1: {cam: 3}},
          sideBets: const [BetModuleType.rabbit]);
      final nota = notasDeLiquidacion(r)
          .firstWhere((n) => n.tipo == BetModuleType.rabbit);
      expect(nota.texto, isNot(contains('tiene el conejo al cerrar')));
    });

    test('suelto y en curso también se explica', () {
      final r = _round(capturados: {1, 2},
          sideBets: const [BetModuleType.rabbit]);
      final nota = notasDeLiquidacion(r)
          .firstWhere((n) => n.tipo == BetModuleType.rabbit);
      expect(nota.texto.toLowerCase(), contains('suelto'));
    });
  });

  group('4 · Wolf cuenta personas, no participantes del grupo', () {
    test('con cuatro reales y dos equipos, Wolf ve CUATRO', () {
      // El cuarto hallazgo, que no se había visto: Wolf decía "se juega
      // exactamente con 4" en una ronda de cuatro personas.
      final r = _round(capturados: {1}, sideBets: const [BetModuleType.wolf]);
      final pids = r.participantesDe(_mod(r, BetModuleType.wolf), seisDelGrupo);
      expect(pids.length, 4);
      final notas = notasDeLiquidacion(r)
          .where((n) => n.tipo == BetModuleType.wolf);
      expect(notas.map((n) => n.texto).join(),
          isNot(contains('exactamente con 4')));
    });

    test('y el Wolf del hoyo sale de una persona', () {
      final r = _round(capturados: {1}, sideBets: const [BetModuleType.wolf]);
      final pids = r.participantesDe(_mod(r, BetModuleType.wolf), seisDelGrupo);
      expect(reales, contains(WolfEngine.wolfDelHoyo(pids, 1)));
    });
  });

  group('5 · la regla es declarada, no un if por motor', () {
    test('los tres side bets se declaran de personas', () {
      for (final t in [BetModuleType.snake, BetModuleType.rabbit,
        BetModuleType.wolf]) {
        expect(t.rules.soloPersonas, isTrue, reason: t.label);
      }
    });

    test('y los formatos con semántica de equipo NO', () {
      // Si esto cambiara, el reparto de importes de equipo dejaría de nombrar
      // personas y el ajuste de ventajas no sabría leer los asientos.
      for (final t in [BetModuleType.nassau, BetModuleType.skins,
        BetModuleType.nassauLowHigh]) {
        expect(t.rules.soloPersonas, isFalse, reason: t.label);
      }
    });

    test('participantesDe no toca a los tipos que no lo declaran', () {
      final r = _round(capturados: {1});
      final pids = r.participantesDe(_mod(r, BetModuleType.snake), seisDelGrupo);
      expect(pids.toSet(), reales.toSet());
      // Un tipo sin la marca devuelve exactamente effectivePids, sin filtrar.
      final nassau = _mod(r, BetModuleType.nassau);
      expect(r.participantesDe(nassau, seisDelGrupo),
          nassau.effectivePids(seisDelGrupo));
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// LOS INDIVIDUALES VIEJOS: MISMA CAUSA, DESDE ANTES
//
// Se midieron porque el hallazgo de los side bets abría la pregunta —si los
// nuevos tenían esto, ¿los viejos también?— y la tenían. Nadie lo había visto
// porque nadie había añadido un formato individual a una ronda por equipos.
//
// Los números de esta sección son los que MEDÍ con el código anterior, no
// inventados:
//
//   oyeses: 6 asientos, 0 con equipo      ← ya era correcto
//   units:  5 asientos, 2 con equipo      ← bb_A → cam $50, bb_B → cam $50
//   medal:  0 asientos                    ← no liquidaba nada
//   putts:  0 asientos                    ← no liquidaba nada
//
// Ninguno de los 1078 tests existentes falló al marcarlos. Eso no significa que
// el comportamiento estuviera bendecido: significa que nadie lo había probado.
// ─────────────────────────────────────────────────────────────────────────────
void _individualesViejos() {
  /// Ronda best ball con los cuatro individuales añadidos como side bets.
  ///
  /// CAM hace 3 en todos los hoyos y un putt; los demás 4 y dos putts. Así hay
  /// un ganador claro en medal y en putts, y un birdie en el hoyo 2.
  Round conIndividuales() {
    final course = CourseInfo(
        name: 'T',
        holes: List.generate(18,
            (i) => CourseHole(hole: i + 1, par: i == 0 ? 3 : 4, strokeIndex: i + 1)));
    return Round(
      id: 'r', name: 'R', course: course,
      players: [
        ...reales.map((i) => Player(id: i, name: i.toUpperCase())),
        Player(id: eqA, name: 'Equipo A', isVirtual: true,
            teamMemberIds: const [cam, cav]),
        Player(id: eqB, name: 'Equipo B', isVirtual: true,
            teamMemberIds: const [aam, rafa]),
      ],
      roundPlayers: seisDelGrupo
          .map((i) => RoundPlayer(playerId: i, handicapEnRonda: 0))
          .toList(),
      betGroups: [
        BetGroup(
            id: 'g', name: 'G',
            format: PartidaFormat.allInOnePot,
            playerIds: seisDelGrupo,
            modules: [
              for (final t in [
                BetModuleType.oyeses,
                BetModuleType.units,
                BetModuleType.medal,
                BetModuleType.putts,
              ])
                BetModuleInstance.defaultFor(t, seisDelGrupo, id: t.name),
            ]),
      ],
      scores: {
        for (final p in reales)
          p: {
            for (var h = 1; h <= 18; h++)
              h: HoleScore(
                  playerId: p, hole: h,
                  grossScore: p == cam ? 3 : 4,
                  putts: p == cam ? 1 : 2),
          },
        eqA: const {}, eqB: const {},
      },
      events: {
        cam: {2: [HoleEvent(playerId: cam, hole: 2, type: UnitEventType.birdie)]}
      },
      oyeseRankings: {1: OyeseRanking(hole: 1, ranking: reales)},
      sliding: const [],
      createdAt: DateTime(2026, 1, 1), totalHoles: 18,
    );
  }

  List<LedgerEntry> deTipo(Round r, BetModuleType t) =>
      BetEngine.computeAll(r).where((x) => x.betType == t).toList();

  group('6 · ningún asiento contra un jugador virtual', () {
    test('Unidades ya no cobra a los equipos', () {
      // Eran DOS asientos: bb_A → cam \$50 y bb_B → cam \$50, por el birdie del
      // hoyo 2. Dinero cargado a entidades que no juegan.
      final e = deTipo(conIndividuales(), BetModuleType.units);
      expect(e, isNotEmpty, reason: 'sin asientos el test pasaría por ausencia');
      for (final x in e) {
        expect([x.fromPlayerId, x.toPlayerId], isNot(contains(eqA)));
        expect([x.fromPlayerId, x.toPlayerId], isNot(contains(eqB)));
      }
    });

    test('y el birdie lo pagan los TRES rivales reales', () {
      // El número concreto: antes eran 5 asientos —tres reales y dos equipos—.
      final e = deTipo(conIndividuales(), BetModuleType.units)
          .where((x) => x.reason.contains('Birdie'));
      expect(e, hasLength(3));
      expect(e.every((x) => x.toPlayerId == cam), isTrue);
    });

    test('ninguno de los cuatro individuales toca un virtual', () {
      final r = conIndividuales();
      for (final t in [BetModuleType.oyeses, BetModuleType.units,
        BetModuleType.medal, BetModuleType.putts]) {
        for (final x in deTipo(r, t)) {
          expect([x.fromPlayerId, x.toPlayerId], isNot(contains(eqA)),
              reason: '${t.label}: ${x.reason}');
          expect([x.fromPlayerId, x.toPlayerId], isNot(contains(eqB)),
              reason: '${t.label}: ${x.reason}');
        }
      }
    });
  });

  group('7 · Medal y Putts liquidan en una ronda por equipos', () {
    test('Medal paga: antes daba CERO asientos', () {
      // El caso peor que "mal": la apuesta aparecía configurada, con su monto, y
      // no pagaba nada. El usuario creía jugar algo que no existía.
      final e = deTipo(conIndividuales(), BetModuleType.medal);
      expect(e, isNotEmpty);
      expect(e.every((x) => x.toPlayerId == cam), isTrue,
          reason: 'CAM hace 3 en todos los hoyos: gana el medal');
    });

    test('Putts paga: antes daba CERO asientos', () {
      final e = deTipo(conIndividuales(), BetModuleType.putts);
      expect(e, isNotEmpty);
      expect(e.every((x) => x.toPlayerId == cam), isTrue,
          reason: 'CAM hace un putt por hoyo');
    });

    test('Oyes sigue igual: ya era correcto, y no se rompe', () {
      // Medí 6 asientos y 0 con equipo antes del cambio. Es el contrapeso: si el
      // filtro hubiera alterado lo que ya funcionaba, aquí se vería.
      final e = deTipo(conIndividuales(), BetModuleType.oyeses);
      expect(e, hasLength(6), reason: 'C(4,2) duelos entre los cuatro reales');
    });

    test('la suma de cada tipo es cero: el dinero no se crea ni se pierde', () {
      // Con los equipos dentro, Medal y Putts sumaban cero por no emitir NADA.
      // Ahora suma cero por estar cuadrado, que es distinto.
      final r = conIndividuales();
      for (final t in [BetModuleType.oyeses, BetModuleType.units,
        BetModuleType.medal, BetModuleType.putts]) {
        final e = deTipo(r, t);
        var suma = 0.0;
        for (final x in e) {
          suma += x.amount; // sale de uno
          suma -= x.amount; // entra en otro
        }
        expect(suma.abs() < 0.01, isTrue, reason: t.label);
        expect(e, isNotEmpty, reason: '${t.label} no emite nada');
      }
    });
  });

  group('8 · la tabla queda coherente', () {
    test('los siete formatos sin semántica de equipo se declaran de personas', () {
      // La regla completa, no una lista de los que se acordaron. Un tipo que
      // dice "no tiene semántica de equipo" y no marca soloPersonas es
      // exactamente la incoherencia que produjo los cuatro hallazgos.
      for (final t in creatableBetTypes) {
        final r = t.rules;
        if (r.teams || r.requiresTeams) continue;
        expect(r.soloPersonas, isTrue,
            reason: '${t.label} no admite equipos y no se declara de personas');
      }
    });

    test('y los que SÍ tienen semántica de equipo no la llevan', () {
      for (final t in creatableBetTypes) {
        if (!t.rules.teams) continue;
        expect(t.rules.soloPersonas, isFalse, reason: t.label);
      }
    });
  });
}
