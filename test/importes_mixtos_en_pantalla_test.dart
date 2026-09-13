// ─────────────────────────────────────────────────────────────────────────────
// IMPORTES MIXTOS: LO QUE SE ENSEÑA ES LO QUE SE COBRA
//
// Una ronda donde ana↔beto pactaron $25 y ana↔caro se quedó con los $100 de la
// apuesta. Lo que se comprueba es el criterio que da la certeza:
//
//   «Ninguna superficie enseña una cifra que el motor no cobraría.»
//
// No basta con que el motor cobre bien: si una pantalla dice otra cosa, el
// jugador no sabe cuál creer — y ya le ha pasado dos veces.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';
import 'package:golf_bet_master/models/models.dart';

final _curso = CourseInfo(
    name: 'P72',
    holes: List.generate(
        18, (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)));

const _tres = ['ana', 'beto', 'caro'];

/// Un módulo de [tipo] con \$100 de base y \$25 pactados para ana↔beto.
BetModuleInstance _mod(BetModuleType tipo) {
  final base = BetModuleInstance.defaultFor(tipo, _tres, id: 'm');
  final clave = base.pairOverrideKey;
  return (base.withBaseValue(100) ?? base).copyWith(
      formatMode: BetFormatMode.allVsAll,
      pairConfigOverrides: clave == null
          ? null
          : {
              BetModuleInstance.pairKey('ana', 'beto'): {clave: 25.0}
            });
}

Round _r(BetModuleType tipo) => Round(
      id: 'r',
      name: 'Mixta',
      course: _curso,
      isFinished: true,
      players: [for (final p in _tres) Player(id: p, name: p)],
      roundPlayers: [
        for (final p in _tres) RoundPlayer(playerId: p, handicapEnRonda: 0)
      ],
      betGroups: [
        BetGroup(
            id: 'g',
            name: 'G',
            format: PartidaFormat.oneVsOne,
            playerIds: _tres,
            modules: [_mod(tipo)])
      ],
      scores: {
        for (final (i, p) in _tres.indexed)
          p: {
            for (final ch in _curso.holes)
              ch.hole: HoleScore(
                  playerId: p, hole: ch.hole, grossScore: ch.par + i - 1,
                  putts: 1 + i)
          }
      },
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2026, 9, 13),
      totalHoles: 18,
    );

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIO 2 · ninguna cifra que el motor no cobraría', () {
    test('CLAVE: el resumen del chip coincide con el importe base', () {
      // Stableford pintaba `m.value` en Inicio y `stableford.value` en
      // Apuestas: dos cifras del mismo dato, y ninguna atada a lo que se cobra.
      for (final t in BetModuleType.values) {
        final mod = _mod(t);
        final inicio = File('lib/screens/home/home_screen.dart')
            .readAsStringSync();
        final apuestas = File('lib/screens/bets/bets_screen.dart')
            .readAsStringSync();
        // Las dos leen del MISMO sitio.
        expect(inicio.contains('m.baseValue.toStringAsFixed'), isTrue);
        expect(apuestas.contains('mod.baseValue.toStringAsFixed'), isTrue);
        // Y ese sitio es el que el motor usa de base — donde «el importe»
        // existe. Nassau lleva varios y no se deja fijar de uno en uno.
        if (mod.withBaseValue(100) != null) {
          expect(mod.baseValue, 100.0, reason: t.name);
        }
      }
    });

    test('CLAVE: y con importes mixtos, el base NO describe los dos duelos', () {
      // La cifra del chip es el BASE. Con una excepción viva deja de ser cierta
      // para todos, y por eso la superficie que la enseña tiene que poder
      // decirlo — como hace la hoja de unidades con su rango.
      for (final t in BetModuleType.values) {
        final mod = _mod(t);
        if (mod.pairOverrideKey == null) continue;
        expect(mod.effectiveValueForDuel('ana', 'beto').$1, 25.0);
        expect(mod.effectiveValueForDuel('ana', 'caro').$1, 100.0);
        expect(mod.baseValue, 100.0,
            reason: '${t.name}: el base es uno de los dos, no los dos');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIO 3 · cada duelo liquida con el suyo, tipo por tipo', () {
    test('CLAVE: el ledger cobra 25 a una pareja y 100 a la otra', () {
      var comprobados = 0;
      for (final t in BetModuleType.values) {
        if (_mod(t).pairOverrideKey == null) continue;
        final r = _r(t);
        LedgerEngine.invalidateCache();
        final todos = LedgerEngine.entriesOf(r);
        double? entre(String a, String b) {
          final e = todos.where((x) =>
              (x.fromPlayerId == a && x.toPlayerId == b) ||
              (x.fromPlayerId == b && x.toPlayerId == a));
          return e.isEmpty ? null : e.map((x) => x.amount).toSet().single;
        }

        final ab = entre('ana', 'beto');
        final ac = entre('ana', 'caro');
        if (ab == null || ac == null) continue;
        comprobados++;
        expect(ab, 25.0, reason: '${t.name}: la pareja pactó 25');
        expect(ac, 100.0, reason: '${t.name}: la otra se contaminó');
      }
      // Que de verdad haya recorrido tipos: si el filtro los descartara todos,
      // la prueba pasaría sin comprobar nada. Es la misma lección del barrido.
      expect(comprobados, greaterThanOrEqualTo(3),
          reason: 'el recorrido no llegó a ningún tipo');
    });
  });
}
