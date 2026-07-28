// =============================================================================
// Tests de regresión de la auditoría previa al lanzamiento.
//
// Cada grupo cubre un fallo confirmado que la suite anterior NO detectaba.
// Todos fallan contra el código anterior a los arreglos.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';
import 'package:golf_bet_master/providers/round_provider.dart';

// ── Curso 18 hoyos: SI impares en F9, pares en B9 ────────────────────────────
final _course18 = CourseInfo(
  name: '18-Hole',
  holes: List.generate(18, (i) {
    final si = (i % 9) * 2 + (i < 9 ? 1 : 2);
    return CourseHole(hole: i + 1, par: 4, strokeIndex: si);
  }),
);

/// Curso de 9 hoyos numerados 1-9 (para el caso de numeración "invertida").
final _course1a9 = CourseInfo(
  name: 'F9-Numbered',
  holes: List.generate(9, (i) =>
      CourseHole(hole: i + 1, par: 4, strokeIndex: i * 2 + 1)),
);

Round _round({
  required Map<String, double> hcps,
  required List<BetGroup> groups,
  required Map<String, Map<int, int>> scores,
  int totalHoles = 18,
  StartingNine sn = StartingNine.front,
  CourseInfo? course,
  Map<String, double>? pairSliding,
  List<RoundPlayer>? roundPlayers,
}) {
  final rp = roundPlayers ??
      hcps.entries
          .map((e) => RoundPlayer(playerId: e.key, handicapEnRonda: e.value))
          .toList();
  final ps = hcps.keys
      .map((id) => Player(id: id, name: id, handicapBase: hcps[id]!))
      .toList();
  final sc = <String, Map<int, HoleScore>>{
    for (final e in scores.entries)
      e.key: {
        for (final h in e.value.entries)
          h.key: HoleScore(
              playerId: e.key, hole: h.key, grossScore: h.value, putts: 2)
      }
  };
  // La caché del ledger usa identidad de objeto; cada Round nueva la invalida
  // sola, pero lo hacemos explícito para no depender del orden de los tests.
  LedgerEngine.invalidateCache();
  return Round(
    id: 't', name: 't', course: course ?? _course18,
    players: ps, roundPlayers: rp, betGroups: groups,
    scores: sc, events: const {}, oyeseRankings: const {},
    sliding: const [], createdAt: DateTime(2025),
    totalHoles: totalHoles, startingNine: sn,
    pairSliding: pairSliding ?? const {},
  );
}

BetGroup _group(List<String> pids, List<BetModuleInstance> mods) => BetGroup(
      id: 'g', name: 'Partida', format: PartidaFormat.allInOnePot,
      playerIds: pids, modules: mods,
    );

/// A gana todos los hoyos de 1 a [upTo].
Map<String, Map<int, int>> _aWinsAll(int upTo) => {
      'A': {for (int h = 1; h <= upTo; h++) h: 4},
      'B': {for (int h = 1; h <= upTo; h++) h: 5},
    };

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // B1 — Ronda de 9 hoyos extendida a 18 ("⛳ Continuar Back 9")
  //
  // totalHoles se queda en 9 al extender. Antes, Nassau liquidaba SOLO el
  // primer segmento y descartaba el segundo en silencio.
  // ═══════════════════════════════════════════════════════════════════════════
  group('B1 – Segmentación independiente de totalHoles', () {
    final nassauMod = BetModuleInstance
        .defaultFor(BetModuleType.nassau, ['A', 'B'])
        .copyWith(
          nassauConfig: const NassauConfig(
            frontValue: 100, backValue: 100, totalValue: 200,
            mode: GrossNetMode.gross,
          ),
        );

    test('B1.1 – 9 hoyos declarados pero 18 capturados → liquida los 3 segmentos', () {
      final r = _round(
        hcps: {'A': 0, 'B': 0},
        groups: [_group(['A', 'B'], [nassauMod])],
        scores: _aWinsAll(18),
        totalHoles: 9, // NO se actualizó al extender
      );
      final reasons = BetEngine.computeAll(r).map((e) => e.reason).toList();
      expect(reasons, containsAll(['Nassau Front 9', 'Nassau Back 9', 'Nassau Total 18']),
          reason: 'Con 18 hoyos capturados deben liquidarse los tres segmentos '
                  'aunque totalHoles siga siendo 9');
      expect(LedgerEngine.playerBalances(r)['A'], 400.0,
          reason: '100 (Front) + 100 (Back) + 200 (Total)');
    });

    test('B1.2 – 9 hoyos reales siguen liquidando UN solo segmento', () {
      final r = _round(
        hcps: {'A': 0, 'B': 0},
        groups: [_group(['A', 'B'], [nassauMod])],
        scores: _aWinsAll(9), // solo F9 capturado
        totalHoles: 9,
      );
      final reasons = BetEngine.computeAll(r).map((e) => e.reason).toList();
      expect(reasons, ['Nassau 9 hoyos'],
          reason: 'Sin scores en el segundo nine sigue siendo una ronda de 9');
      expect(LedgerEngine.playerBalances(r)['A'], 100.0);
    });

    test('B1.3 – ronda de 18 parcial (solo F9 jugado) no cambia de comportamiento', () {
      final r = _round(
        hcps: {'A': 0, 'B': 0},
        groups: [_group(['A', 'B'], [nassauMod])],
        scores: _aWinsAll(9),
        totalHoles: 18,
      );
      final reasons = BetEngine.computeAll(r).map((e) => e.reason).toSet();
      expect(reasons, {'Nassau Front 9', 'Nassau Total 18'},
          reason: 'Back sin jugar → sin entry de Back; Total = Front');
    });

    test('B1.4 – equipo: 9 declarados con 18 capturados liquida los 3 segmentos', () {
      final ids = ['A1', 'A2', 'B1', 'B2'];
      final teamMod = BetModuleInstance
          .defaultFor(BetModuleType.nassau, ids)
          .copyWith(
            nassauConfig: const NassauConfig(
              frontValue: 100, backValue: 100, totalValue: 200,
              mode: GrossNetMode.gross,
            ),
            sides: [
              BetSide(id: 's1', name: 'A', playerIds: ['A1', 'A2'],
                  playMode: TeamPlayMode.bestBall),
              BetSide(id: 's2', name: 'B', playerIds: ['B1', 'B2'],
                  playMode: TeamPlayMode.bestBall),
            ],
          );
      final r = _round(
        hcps: {for (final i in ids) i: 0},
        groups: [_group(ids, [teamMod])],
        scores: {
          'A1': {for (int h = 1; h <= 18; h++) h: 4},
          'A2': {for (int h = 1; h <= 18; h++) h: 4},
          'B1': {for (int h = 1; h <= 18; h++) h: 5},
          'B2': {for (int h = 1; h <= 18; h++) h: 5},
        },
        totalHoles: 9,
      );
      // El duelo por equipos vale lo configurado EN TOTAL (ver teamCrossAmount):
      // Front 100 + Back 100 + Total 200 = 400 para el lado A,
      // repartidos entre sus 2 miembros → 200 cada uno.
      expect(LedgerEngine.playerBalances(r)['A1'], 200.0,
          reason: '(100 + 100 + 200) / 2 miembros del equipo');
    });

    test('B1.5 – Nassau+Press con 18 capturados liquida ambos segmentos', () {
      final pressMod = BetModuleInstance
          .defaultFor(BetModuleType.nassau, ['A', 'B'])
          .copyWith(
            nassauConfig: const NassauConfig(
              frontValue: 100, backValue: 100, totalValue: 200,
              mode: GrossNetMode.gross, pressEnabled: true,
              autoPressTrigger: 2, frontPressValue: 50, backPressValue: 50,
              allowMultiplePresses: false,
            ),
          );
      final r = _round(
        hcps: {'A': 0, 'B': 0},
        groups: [_group(['A', 'B'], [pressMod])],
        scores: _aWinsAll(18),
        totalHoles: 9,
      );
      final reasons = BetEngine.computeAll(r).map((e) => e.reason).toList();
      expect(reasons.where((r) => r.contains('Front 9')), isNotEmpty);
      expect(reasons.where((r) => r.contains('Back 9')), isNotEmpty);
      expect(reasons.where((r) => r == 'Nassau Total 18'), isNotEmpty);
    });

    test('B1.6 – campo 1-9 jugado como vuelta de inicio con back-start', () {
      // Caso que _courseHolesF9B9 ya contemplaba para los strokes pero que la
      // segmentación descartaba: todos los hoyos caían en "back" y el Nassau
      // de 9 hoyos liquidaba front=0 → ni una sola entry.
      final r = _round(
        hcps: {'A': 0, 'B': 0},
        groups: [_group(['A', 'B'], [nassauMod])],
        scores: _aWinsAll(9),
        totalHoles: 9,
        sn: StartingNine.back,
        course: _course1a9,
      );
      final entries = BetEngine.computeAll(r);
      expect(entries, isNotEmpty,
          reason: 'Un campo 1-9 jugado como back-start debe liquidar su Nassau');
      expect(LedgerEngine.playerBalances(r)['A'], 100.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // B2 — Skins "1 Pot" con 3+ jugadores debe respetar pairSliding
  //
  // Antes usaba GameEngine.holeWinner (handicap individual vs par), que ignora
  // por completo los acuerdos bilaterales.
  // ═══════════════════════════════════════════════════════════════════════════
  group('B2 – Skins 1 Pot respeta pairSliding', () {
    // Todos con HCP 0 → sin strokes por handicap individual.
    // pairSliding: C recibe 18 de A y de B (1 stroke por hoyo).
    // Gross: A=4, B=5, C=5  →  netos con ventaja: A=4, B=5, C=4 → empate A/C.
    const sliding = {'A|C': -18.0, 'B|C': -18.0};
    final scores = {
      'A': {for (int h = 1; h <= 18; h++) h: 4},
      'B': {for (int h = 1; h <= 18; h++) h: 5},
      'C': {for (int h = 1; h <= 18; h++) h: 5},
    };

    test('B2.1 – la ventaja de C neutraliza a A → sin ganador de hoyo', () {
      final mod = BetModuleInstance
          .defaultFor(BetModuleType.skins, ['A', 'B', 'C'])
          .copyWith(
            formatMode: BetFormatMode.onePot,
            skinsConfig: const SkinsConfig(
                valuePerSkin: 10, carryOver: false, mode: GrossNetMode.net),
          );
      final r = _round(
        hcps: {'A': 0, 'B': 0, 'C': 0},
        groups: [_group(['A', 'B', 'C'], [mod])],
        scores: scores,
        pairSliding: sliding,
      );
      expect(BetEngine.strokesP1ReceivesFromP2(r, 'C', 'A'), 18.0);
      expect(LedgerEngine.playerBalances(r),
          {'A': 0.0, 'B': 0.0, 'C': 0.0},
          reason: 'A y C empatan netos en cada hoyo → nadie cobra. '
                  'Antes A cobraba 360 ignorando el pairSliding.');
    });

    test('B2.2 – coincide con Medal 1 Pot en el mismo escenario', () {
      final medalMod = BetModuleInstance
          .defaultFor(BetModuleType.medal, ['A', 'B', 'C'])
          .copyWith(
            formatMode: BetFormatMode.onePot,
            medalConfig: const MedalConfig(value: 100, mode: GrossNetMode.net),
          );
      final r = _round(
        hcps: {'A': 0, 'B': 0, 'C': 0},
        groups: [_group(['A', 'B', 'C'], [medalMod])],
        scores: scores,
        pairSliding: sliding,
      );
      expect(LedgerEngine.playerBalances(r), {'A': 0.0, 'B': 0.0, 'C': 0.0},
          reason: 'Skins y Medal deben leer las mismas ventajas');
    });

    test('B2.3 – sin ventajas, el mejor gross sigue ganando los skins', () {
      final mod = BetModuleInstance
          .defaultFor(BetModuleType.skins, ['A', 'B', 'C'])
          .copyWith(
            formatMode: BetFormatMode.onePot,
            skinsConfig: const SkinsConfig(
                valuePerSkin: 10, carryOver: false, mode: GrossNetMode.net),
          );
      final r = _round(
        hcps: {'A': 0, 'B': 0, 'C': 0},
        groups: [_group(['A', 'B', 'C'], [mod])],
        scores: scores, // sin pairSliding
      );
      expect(LedgerEngine.playerBalances(r)['A'], 18 * 10 * 2,
          reason: 'A gana los 18 hoyos y cobra 10 a cada uno de los 2 rivales');
    });

    test('B2.4 – la tarjeta (skinsScorecard) coincide con el ledger', () {
      final mod = BetModuleInstance
          .defaultFor(BetModuleType.skins, ['A', 'B', 'C'])
          .copyWith(
            formatMode: BetFormatMode.onePot,
            skinsConfig: const SkinsConfig(
                valuePerSkin: 10, carryOver: false, mode: GrossNetMode.net),
          );
      final r = _round(
        hcps: {'A': 0, 'B': 0, 'C': 0},
        groups: [_group(['A', 'B', 'C'], [mod])],
        scores: scores,
        pairSliding: sliding,
      );
      final card = BetEngine.skinsScorecard(r, 'A', 'C', mod,
          groupPids: ['A', 'B', 'C']);
      expect(card.where((h) => h.winner != null), isEmpty,
          reason: 'Si el ledger no reparte skins, la tarjeta tampoco debe '
                  'mostrar ganadores de hoyo');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // B3 — Migración legacy manualHandicaps → pairSliding
  //
  // La clave se construía con '\$lowId|\$highId' (interpolación escapada),
  // produciendo una única entrada literal en vez de una por par.
  // ═══════════════════════════════════════════════════════════════════════════
  group('B3 – Migración legacy produce claves canónicas', () {
    Map<String, dynamic> legacyJson() => {
          'id': 'r1', 'name': 'Vieja',
          'createdAt': '2025-01-01T00:00:00.000',
          'currentHole': 1, 'isFinished': false,
          'startingNine': 'front', 'totalHoles': 18,
          'course': _course18.toJson(),
          'players': [
            Player(id: 'aaa', name: 'A', handicapBase: 0).toJson(),
            Player(id: 'bbb', name: 'B', handicapBase: 10).toJson(),
            Player(id: 'ccc', name: 'C', handicapBase: 20).toJson(),
          ],
          'roundPlayers': [
            RoundPlayer(playerId: 'aaa', handicapEnRonda: 0,
                manualHandicaps: {'bbb': -8.0, 'ccc': -15.0}).toJson(),
            RoundPlayer(playerId: 'bbb', handicapEnRonda: 10,
                manualHandicaps: {'aaa': 8.0}).toJson(),
            RoundPlayer(playerId: 'ccc', handicapEnRonda: 20,
                manualHandicaps: {'aaa': 15.0}).toJson(),
          ],
          'betGroups': [], 'scores': {}, 'events': {},
          'oyeseRankings': {}, 'sliding': [],
        };

    test('B3.1 – migra un par por cada acuerdo, con clave canónica', () {
      final r = roundFromJson(legacyJson());
      expect(r.pairSliding.keys.toSet(), {'aaa|bbb', 'aaa|ccc'});
      expect(r.pairSliding['aaa|bbb'], -8.0, reason: 'aaa da 8 a bbb');
      expect(r.pairSliding['aaa|ccc'], -15.0, reason: 'aaa da 15 a ccc');
    });

    test('B3.2 – el valor migrado es legible por canonicalSlidingBetween', () {
      final r = roundFromJson(legacyJson());
      expect(BetEngine.canonicalSlidingBetween(r, 'aaa', 'bbb'), -8.0);
      expect(BetEngine.canonicalSlidingBetween(r, 'bbb', 'aaa'), 8.0);
    });

    test('B3.3 – la ronda migrada no produce errores de validación', () {
      final r = roundFromJson(legacyJson());
      expect(BetEngine.validatePairSliding(r), isEmpty);
    });

    test('B3.4 – una clave basura persistida se descarta y se remigra', () {
      // Rondas guardadas por la versión con el bug traen esta clave literal.
      final json = legacyJson()..['pairSliding'] = {r'$lowId|$highId': -8.0};
      final r = roundFromJson(json);
      expect(r.pairSliding.containsKey(r'$lowId|$highId'), isFalse,
          reason: 'La clave mal formada debe descartarse');
      expect(r.pairSliding.keys.toSet(), {'aaa|bbb', 'aaa|ccc'},
          reason: 'Al no quedar claves válidas, debe reintentarse la migración');
    });

    test('B3.5 – un pairSliding válido tiene prioridad sobre el legacy', () {
      final json = legacyJson()..['pairSliding'] = {'aaa|bbb': -3.0};
      final r = roundFromJson(json);
      expect(r.pairSliding, {'aaa|bbb': -3.0},
          reason: 'El campo canónico gana; no se remigra');
    });

    test('B3.6 – un par legacy inconsistente se omite en la migración', () {
      final json = legacyJson();
      json['roundPlayers'] = [
        RoundPlayer(playerId: 'aaa', handicapEnRonda: 0,
            manualHandicaps: {'bbb': -8.0}).toJson(),
        RoundPlayer(playerId: 'bbb', handicapEnRonda: 10,
            manualHandicaps: {'aaa': 4.0}).toJson(), // ≠ +8 → contradictorio
      ];
      final r = roundFromJson(json);
      expect(r.pairSliding, isEmpty,
          reason: 'No se inventa un valor para un par contradictorio');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // B5 — safeComputeAll aísla los fallos de integridad por módulo
  // ═══════════════════════════════════════════════════════════════════════════
  group('B5 – Aislamiento de errores de integridad', () {
    // manual[A][B] = 5 pero manual[B][A] = 7 (deberían ser opuestos)
    final inconsistentRPs = [
      RoundPlayer(playerId: 'A', handicapEnRonda: 0, manualHandicaps: {'B': 5}),
      RoundPlayer(playerId: 'B', handicapEnRonda: 0, manualHandicaps: {'A': 7}),
      RoundPlayer(playerId: 'C', handicapEnRonda: 0),
      RoundPlayer(playerId: 'D', handicapEnRonda: 0),
    ];

    Round buildRound() => _round(
          hcps: {'A': 0, 'B': 0, 'C': 0, 'D': 0},
          groups: [
            BetGroup(
              id: 'g1', name: 'Duelo AB', format: PartidaFormat.allInOnePot,
              playerIds: ['A', 'B'],
              modules: [BetModuleInstance.defaultFor(BetModuleType.nassau, ['A', 'B'])],
            ),
            BetGroup(
              id: 'g2', name: 'Duelo CD', format: PartidaFormat.allInOnePot,
              playerIds: ['C', 'D'],
              modules: [BetModuleInstance.defaultFor(BetModuleType.nassau, ['C', 'D'])],
            ),
          ],
          scores: {
            for (final p in ['A', 'B', 'C', 'D'])
              p: {for (int h = 1; h <= 18; h++) h: p == 'A' || p == 'C' ? 4 : 5},
          },
          roundPlayers: inconsistentRPs,
        );

    test('B5.1 – computeAll sigue lanzando (contrato deliberado)', () {
      expect(() => BetEngine.computeAll(buildRound()),
          throwsA(isA<StateError>()));
    });

    test('B5.2 – safeComputeAll no lanza y reporta el módulo afectado', () {
      final result = BetEngine.safeComputeAll(buildRound());
      expect(result.hasErrors, isTrue);
      expect(result.errors.single, contains('Duelo AB'));
    });

    test('B5.3 – el módulo sano SÍ se liquida', () {
      final result = BetEngine.safeComputeAll(buildRound());
      expect(result.entries, isNotEmpty,
          reason: 'El duelo C-D no está afectado y debe cobrarse');
      expect(result.entries.every((e) => e.toPlayerId == 'C'), isTrue);
    });

    test('B5.4 – LedgerEngine no propaga la excepción a la UI', () {
      final r = buildRound();
      expect(() => LedgerEngine.playerBalances(r), returnsNormally);
      expect(LedgerEngine.integrityErrors(r), hasLength(1));
      expect(LedgerEngine.playerBalances(r)['C'], greaterThan(0));
    });

    test('B5.5 – una ronda sana no reporta errores', () {
      final r = _round(
        hcps: {'A': 0, 'B': 0},
        groups: [_group(['A', 'B'],
            [BetModuleInstance.defaultFor(BetModuleType.nassau, ['A', 'B'])])],
        scores: _aWinsAll(18),
      );
      expect(LedgerEngine.integrityErrors(r), isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Caché del ledger: no debe cambiar ningún resultado
  // ═══════════════════════════════════════════════════════════════════════════
  group('Caché del LedgerEngine', () {
    test('C.1 – dos llamadas seguidas devuelven lo mismo', () {
      final r = _round(
        hcps: {'A': 0, 'B': 0},
        groups: [_group(['A', 'B'],
            [BetModuleInstance.defaultFor(BetModuleType.nassau, ['A', 'B'])])],
        scores: _aWinsAll(18),
      );
      expect(LedgerEngine.playerBalances(r), LedgerEngine.playerBalances(r));
    });

    test('C.2 – una Round nueva invalida la caché', () {
      final groups = [_group(['A', 'B'],
          [BetModuleInstance.defaultFor(BetModuleType.nassau, ['A', 'B'])])];
      final r1 = _round(
        hcps: {'A': 0, 'B': 0}, groups: groups, scores: _aWinsAll(18));
      final before = LedgerEngine.playerBalances(r1)['A'];

      // Misma ronda pero con B ganando todos los hoyos
      final r2 = _round(
        hcps: {'A': 0, 'B': 0},
        groups: groups,
        scores: {
          'A': {for (int h = 1; h <= 18; h++) h: 5},
          'B': {for (int h = 1; h <= 18; h++) h: 4},
        },
      );
      final after = LedgerEngine.playerBalances(r2)['A'];
      expect(after, isNot(before));
      expect(after, lessThan(0));
    });

    test('C.3 – copyWith sobre la misma ronda refleja el cambio', () {
      final groups = [_group(['A', 'B'],
          [BetModuleInstance.defaultFor(BetModuleType.nassau, ['A', 'B'])])];
      final r1 = _round(
        hcps: {'A': 0, 'B': 0}, groups: groups, scores: _aWinsAll(18));
      expect(LedgerEngine.playerBalances(r1)['A'], greaterThan(0));

      // Quitar los scores de A → nadie gana nada
      final r2 = r1.copyWith(scores: {...r1.scores, 'A': {}});
      expect(LedgerEngine.playerBalances(r2)['A'], 0.0,
          reason: 'copyWith crea una instancia nueva → la caché se invalida');
    });
  });
}
