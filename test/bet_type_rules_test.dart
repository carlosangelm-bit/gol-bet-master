// ─────────────────────────────────────────────────────────────────────────────
// bet_type_rules_test.dart — la tabla declarativa no puede desviarse del motor
//
// Una tabla de compatibilidad que se mantiene a mano miente en cuanto alguien
// cambia el motor y se olvida de ella. Estos tests la contrastan contra el
// comportamiento real, no contra sí misma: si el motor gana o pierde una
// capacidad y la tabla no lo refleja, fallan.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';

const a1 = 'a1', a2 = 'a2', b1 = 'b1', b2 = 'b2';

CourseInfo _course() => CourseInfo(name: 'T',
    holes: List.generate(18, (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)));

/// Ronda 2v2 donde el lado A gana con claridad.
Round _round(BetModuleInstance mod) {
  final gross = {
    a1: {for (var h = 1; h <= 18; h++) h: 3},
    a2: {for (var h = 1; h <= 18; h++) h: 4},
    b1: {for (var h = 1; h <= 18; h++) h: 5},
    b2: {for (var h = 1; h <= 18; h++) h: 6},
  };
  return Round(
    id: 'r', name: 'R', course: _course(),
    players: [a1, a2, b1, b2].map((i) => Player(id: i, name: i)).toList(),
    roundPlayers: [a1, a2, b1, b2]
        .map((i) => RoundPlayer(playerId: i, handicapEnRonda: 0))
        .toList(),
    betGroups: [BetGroup(id: 'g', name: 'G',
        format: PartidaFormat.allInOnePot,
        playerIds: const [a1, a2, b1, b2], modules: [mod])],
    scores: {
      for (final e in gross.entries)
        e.key: {for (final h in e.value.entries)
          h.key: HoleScore(playerId: e.key, hole: h.key, grossScore: h.value)},
    },
    events: const {}, oyeseRankings: const {}, sliding: const [],
    createdAt: DateTime(2026, 1, 1), totalHoles: 18,
  );
}

BetModuleInstance _conLados(BetModuleType t) => BetModuleInstance(
      id: 'm', type: t, name: t.label,
      participantIds: const [a1, a2, b1, b2],
      sides: const [
        BetSide(id: 'A', name: 'Equipo A', playerIds: [a1, a2]),
        BetSide(id: 'B', name: 'Equipo B', playerIds: [b1, b2]),
      ],
      skinsConfig: t == BetModuleType.skins ? const SkinsConfig() : null,
      nassauConfig: t == BetModuleType.nassau ? NassauConfig.def : null,
      medalConfig: t == BetModuleType.medal ? MedalConfig.def : null,
      puttsConfig: t == BetModuleType.putts ? PuttsConfig.def : null,
      oyesesConfig: t == BetModuleType.oyeses ? OyesesConfig.def : null,
      unitsConfig: t == BetModuleType.units ? UnitsConfig.def : null,
      matchAutoPressConfig:
          t == BetModuleType.matchAutoPress ? MatchAutoPressConfig() : null,
      nassauLowHighConfig:
          t == BetModuleType.nassauLowHigh ? const NassauLowHighConfig() : null,
    );

void main() {
  group('la tabla no se desvía del motor', () {
    test('perPairAmount coincide con supportsPlayerOverride', () {
      for (final t in BetModuleType.values) {
        final mod = BetModuleInstance(
            id: 'x', type: t, name: t.label, participantIds: const []);
        expect(t.rules.perPairAmount, mod.supportsPlayerOverride,
            reason: '$t: la tabla dice ${t.rules.perPairAmount} y el modelo '
                '${mod.supportsPlayerOverride}');
      }
    });

    test('requiresTeams coincide con el getter del enum', () {
      for (final t in BetModuleType.values) {
        expect(t.rules.requiresTeams, t.requiresTeams, reason: '$t');
      }
    });

    test('un tipo que requiere equipos también los admite', () {
      for (final t in BetModuleType.values) {
        if (!t.rules.requiresTeams) continue;
        expect(t.rules.teams, isTrue,
            reason: '$t exige equipos pero la tabla dice que no los admite');
      }
    });

    test('teams=true significa que el motor liquida por lados', () {
      // Prueba de comportamiento, no de declaración: con lados configurados,
      // un tipo con motor de equipo produce asientos entre lados opuestos y
      // NUNCA entre compañeros. Los que caen al fallback individual sí
      // enfrentan a compañeros entre sí, que es exactamente la diferencia.
      for (final t in BetModuleType.values) {
        if (!t.rules.teams) continue;
        final entries = BetEngine.computeAll(_round(_conLados(t)));
        if (entries.isEmpty) continue; // el tipo no pagó en este escenario
        final entreCompaneros = entries.any((e) =>
            (e.fromPlayerId == a1 && e.toPlayerId == a2) ||
            (e.fromPlayerId == a2 && e.toPlayerId == a1) ||
            (e.fromPlayerId == b1 && e.toPlayerId == b2) ||
            (e.fromPlayerId == b2 && e.toPlayerId == b1));
        expect(entreCompaneros, isFalse,
            reason: '$t dice tener motor de equipo, pero cobró entre '
                'compañeros del mismo lado');
      }
    });
  });

  group('la tabla explica lo que niega', () {
    test('todo lo que no admite lleva motivo', () {
      for (final t in BetModuleType.values) {
        final r = t.rules;
        if (!r.teams) {
          expect(r.sinEquipos, isNotNull, reason: '$t niega equipos sin motivo');
          expect(r.sinEquipos, isNotEmpty);
        }
        if (!r.segments) {
          expect(r.sinSegmentos, isNotNull, reason: '$t niega segmentos sin motivo');
        }
        if (!r.perPairAmount) {
          expect(r.sinMontoPorPareja, isNotNull,
              reason: '$t niega monto por pareja sin motivo');
        }
      }
    });

    test('lo que sí admite no lleva motivo de negación', () {
      // Un motivo colgado de una capacidad activa es residuo de un cambio a
      // medias, y acabaría mostrándose junto a una opción habilitada.
      for (final t in BetModuleType.values) {
        final r = t.rules;
        if (r.teams) expect(r.sinEquipos, isNull, reason: '$t');
        if (r.segments) expect(r.sinSegmentos, isNull, reason: '$t');
        if (r.perPairAmount) expect(r.sinMontoPorPareja, isNull, reason: '$t');
      }
    });

    test('cada tipo del enum tiene fila', () {
      // Si alguien añade un formato y no lo mete en la tabla, el switch de
      // rules deja de compilar. Este test lo deja explícito.
      for (final t in BetModuleType.values) {
        expect(() => t.rules, returnsNormally, reason: '$t sin fila');
      }
    });
  });
}
