// =============================================================================
// Excepciones por duelo (pairConfigOverrides).
//
// El modelo ya tenía effectiveValueForDuel(), pero NINGÚN motor lo llamaba: se
// podía pactar un valor distinto para un duelo, la UI lo guardaba y lo mostraba,
// y el ledger cobraba el valor base. Estos tests fijan el comportamiento
// correcto para Skins, Oyeses y Units.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';

final _course = CourseInfo(
  name: '18',
  holes: List.generate(18, (i) =>
      CourseHole(hole: i + 1, par: i == 2 ? 3 : 4, strokeIndex: i + 1)),
);

const _ids = ['A', 'B', 'C'];

Round _round({
  required BetModuleInstance mod,
  required Map<String, int> perHole,
  Map<String, Map<int, List<HoleEvent>>> events = const {},
  Map<int, OyeseRanking> oyeses = const {},
}) {
  LedgerEngine.invalidateCache();
  return Round(
    id: 't', name: 't', course: _course,
    players: _ids.map((i) => Player(id: i, name: i, handicapBase: 0)).toList(),
    roundPlayers:
        _ids.map((i) => RoundPlayer(playerId: i, handicapEnRonda: 0)).toList(),
    betGroups: [
      BetGroup(
        id: 'g', name: 'Partida', format: PartidaFormat.allInOnePot,
        playerIds: _ids, modules: [mod],
      )
    ],
    scores: {
      for (final id in _ids)
        id: {
          for (int h = 1; h <= 18; h++)
            h: HoleScore(
                playerId: id, hole: h, grossScore: perHole[id] ?? 4, putts: 2)
        }
    },
    events: events, oyeseRankings: oyeses,
    sliding: const [], createdAt: DateTime(2025),
  );
}

void main() {
  final pkAB = BetModuleInstance.pairKey('A', 'B');

  // ═══════════════════════════════════════════════════════════════════════════
  group('Skins — valor distinto pactado para un duelo', () {
    BetModuleInstance skinsMod({Map<String, Map<String, dynamic>>? ov}) =>
        BetModuleInstance.defaultFor(BetModuleType.skins, _ids).copyWith(
          formatMode: BetFormatMode.allVsAll,
          skinsConfig: const SkinsConfig(
              valuePerSkin: 10, carryOver: false, mode: GrossNetMode.gross),
          pairConfigOverrides: ov,
        );

    test('K1 – el duelo con override cobra su valor; los demás el base', () {
      // A gana los 18 hoyos a todos. A-B pactado a 100/skin, A-C al base 10.
      final r = _round(
        mod: skinsMod(ov: {pkAB: {'value': 100.0}}),
        perHole: {'A': 3, 'B': 5, 'C': 5},
      );
      expect(LedgerEngine.breakdownBetween(r, 'A', 'B')[BetModuleType.skins],
          1800.0, reason: '18 hoyos × 100');
      expect(LedgerEngine.breakdownBetween(r, 'A', 'C')[BetModuleType.skins],
          180.0, reason: '18 hoyos × 10 (sin excepción)');
    });

    test('K2 – sin overrides todos los duelos cobran el valor base', () {
      final r = _round(
        mod: skinsMod(),
        perHole: {'A': 3, 'B': 5, 'C': 5},
      );
      expect(LedgerEngine.breakdownBetween(r, 'A', 'B')[BetModuleType.skins],
          180.0);
      expect(LedgerEngine.breakdownBetween(r, 'A', 'C')[BetModuleType.skins],
          180.0);
    });

    test('K3 – el carry-over acumula sobre el valor del duelo', () {
      // A y B empatan los hoyos 1-17 y A gana el 18 → 18 skins acumuladas.
      final scores = <String, Map<int, HoleScore>>{
        'A': {
          for (int h = 1; h <= 18; h++)
            h: HoleScore(playerId: 'A', hole: h, grossScore: h == 18 ? 3 : 4, putts: 2)
        },
        'B': {
          for (int h = 1; h <= 18; h++)
            h: HoleScore(playerId: 'B', hole: h, grossScore: 4, putts: 2)
        },
      };
      final mod = BetModuleInstance.defaultFor(BetModuleType.skins, ['A', 'B'])
          .copyWith(
        formatMode: BetFormatMode.allVsAll,
        skinsConfig: const SkinsConfig(
            valuePerSkin: 10, carryOver: true, mode: GrossNetMode.gross),
        pairConfigOverrides: {pkAB: {'value': 100.0}},
      );
      LedgerEngine.invalidateCache();
      final r = Round(
        id: 't', name: 't', course: _course,
        players: ['A', 'B']
            .map((i) => Player(id: i, name: i, handicapBase: 0)).toList(),
        roundPlayers: ['A', 'B']
            .map((i) => RoundPlayer(playerId: i, handicapEnRonda: 0)).toList(),
        betGroups: [
          BetGroup(
            id: 'g', name: 'g', format: PartidaFormat.allInOnePot,
            playerIds: ['A', 'B'], modules: [mod],
          )
        ],
        scores: scores, events: const {}, oyeseRankings: const {},
        sliding: const [], createdAt: DateTime(2025),
      );
      expect(LedgerEngine.breakdownBetween(r, 'A', 'B')[BetModuleType.skins],
          1800.0,
          reason: '17 empates acumulan + el hoyo 18 → 18 skins × 100');
    });

    test('K4 – la tarjeta y el ledger usan el mismo valor', () {
      final mod = skinsMod(ov: {pkAB: {'value': 100.0}});
      final r = _round(mod: mod, perHole: {'A': 3, 'B': 5, 'C': 5});
      final card = BetEngine.skinsScorecard(r, 'A', 'B', mod);
      // pot de cada hoyo = el valor pactado del duelo
      expect(card.every((h) => h.pot == 100.0), isTrue,
          reason: 'la tarjeta debe mostrar el valor pactado, no el base');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('Oyeses — valor distinto pactado para un duelo', () {
    test('Y1 – cada par cobra su propio valor', () {
      final mod = BetModuleInstance.defaultFor(BetModuleType.oyeses, _ids)
          .copyWith(
        oyesesConfig: const OyesesConfig(value: 20, zapatoEnabled: false),
        pairConfigOverrides: {pkAB: {'value': 75.0}},
      );
      final r = _round(
        mod: mod,
        perHole: {'A': 3, 'B': 3, 'C': 3},
        oyeses: {3: OyeseRanking(hole: 3, ranking: const ['A', 'B', 'C'])},
      );
      // A 1°, B 2°, C 3° en el único par-3 (hoyo 3)
      expect(LedgerEngine.breakdownBetween(r, 'A', 'B')[BetModuleType.oyeses],
          75.0, reason: 'duelo A-B pactado a 75');
      expect(LedgerEngine.breakdownBetween(r, 'A', 'C')[BetModuleType.oyeses],
          20.0, reason: 'duelo A-C al valor base');
      expect(LedgerEngine.breakdownBetween(r, 'B', 'C')[BetModuleType.oyeses],
          20.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('Units — override allEvents por duelo', () {
    test('U1 – el duelo pactado usa allEvents para cualquier evento', () {
      final mod = BetModuleInstance.defaultFor(BetModuleType.units, _ids)
          .copyWith(
        unitsConfig: UnitsConfig(eventValues: {
          for (final e in UnitEventType.values) e: 10.0,
        }),
        pairConfigOverrides: {pkAB: {'allEvents': 55.0}},
      );
      final r = _round(
        mod: mod,
        perHole: {'A': 3, 'B': 4, 'C': 4},
        events: {
          'A': {
            1: [HoleEvent(playerId: 'A', hole: 1, type: UnitEventType.birdie)]
          },
        },
      );
      expect(LedgerEngine.breakdownBetween(r, 'A', 'B')[BetModuleType.units],
          55.0, reason: 'B paga el valor pactado del duelo');
      expect(LedgerEngine.breakdownBetween(r, 'A', 'C')[BetModuleType.units],
          10.0, reason: 'C paga el valor base del evento');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('No regresión — el pozo común no usa overrides por par', () {
    test('N1 – Skins 1 Pot ignora el override (no hay "valor del duelo")', () {
      final mod = BetModuleInstance.defaultFor(BetModuleType.skins, _ids)
          .copyWith(
        formatMode: BetFormatMode.onePot,
        skinsConfig: const SkinsConfig(
            valuePerSkin: 10, carryOver: false, mode: GrossNetMode.gross),
        pairConfigOverrides: {pkAB: {'value': 100.0}},
      );
      final r = _round(mod: mod, perHole: {'A': 3, 'B': 5, 'C': 5});
      // A gana los 18 hoyos y cobra 10 a cada rival
      expect(LedgerEngine.playerBalances(r)['A'], 360.0,
          reason: '18 × 10 × 2 rivales — el pozo es único, sin excepciones');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('effectiveValueForDuel — resolución', () {
    test('V1 – el override del par gana sobre el valor base', () {
      final mod = BetModuleInstance.defaultFor(BetModuleType.skins, _ids)
          .copyWith(
        skinsConfig: const SkinsConfig(valuePerSkin: 10),
        pairConfigOverrides: {pkAB: {'value': 100.0}},
      );
      expect(mod.effectiveValueForDuel('A', 'B').$1, 100.0);
      expect(mod.effectiveValueForDuel('B', 'A').$1, 100.0,
          reason: 'la clave del par es simétrica');
      expect(mod.effectiveValueForDuel('A', 'C').$1, 10.0);
    });
  });
}
