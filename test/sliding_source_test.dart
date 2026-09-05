// ─────────────────────────────────────────────────────────────────────────────
// sliding_source_test.dart — qué apuesta representa el duelo
//
// El ajuste de ventaja elige UNA apuesta por pareja. El criterio anterior
// comparaba matchResult.absMargin contra nassauResult.absMargin, pero esos
// números no medían lo mismo: uno contaba asientos del ledger y el otro
// segmentos ganados. Cualquier orden que saliera de ahí era casualidad.
//
// No mueve dinero pasado, pero ajusta ventajas futuras sobre la apuesta
// equivocada — un error que se paga en la ronda siguiente.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/sliding_adjustment_engine.dart';

const p1 = 'p1', p2 = 'p2';

CourseInfo _course() => CourseInfo(name: 'T',
    holes: List.generate(18, (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)));

/// Ronda donde p1 gana los primeros 6 hoyos.
Round _round(List<BetModuleInstance> mods) {
  final gross = {
    p1: {for (var h = 1; h <= 18; h++) h: h <= 6 ? 3 : 4},
    p2: {for (var h = 1; h <= 18; h++) h: 4},
  };
  return Round(
    id: 'r', name: 'R', course: _course(),
    players: [Player(id: p1, name: 'P1'), Player(id: p2, name: 'P2')],
    roundPlayers: [
      RoundPlayer(playerId: p1, handicapEnRonda: 0),
      RoundPlayer(playerId: p2, handicapEnRonda: 0),
    ],
    betGroups: [BetGroup(id: 'g', name: 'G',
        format: PartidaFormat.allInOnePot,
        playerIds: const [p1, p2], modules: mods)],
    scores: {
      for (final e in gross.entries)
        e.key: {for (final h in e.value.entries)
          h.key: HoleScore(playerId: e.key, hole: h.key, grossScore: h.value)},
    },
    events: const {}, oyeseRankings: const {}, sliding: const [],
    createdAt: DateTime(2026, 1, 1), totalHoles: 18,
  );
}

/// Un MATCH sobre los 18: Nassau con los dos nueves a cero.
///
/// Era `BetModuleType.matchAutoPress`, que se retiró por ser exactamente esto.
BetModuleInstance _match(double valor) => BetModuleInstance(
      id: 'm', type: BetModuleType.nassau, name: 'Match',
      participantIds: const [p1, p2],
      nassauConfig: NassauConfig(
          frontValue: 0, backValue: 0, totalValue: valor),
    );

BetModuleInstance _nassau(double valor) => BetModuleInstance(
      id: 'n', type: BetModuleType.nassau, name: 'Nassau',
      participantIds: const [p1, p2],
      nassauConfig: NassauConfig(
          frontValue: valor, backValue: valor, totalValue: valor),
    );

BetModuleInstance _skins(double valor) => BetModuleInstance(
      id: 's', type: BetModuleType.skins, name: 'Skins',
      participantIds: const [p1, p2],
      skinsConfig: SkinsConfig(valuePerSkin: valor),
    );

DuelResult? _fuente(List<BetModuleInstance> mods) {
  final sug = SlidingAdjustmentEngine.computeSuggestions(
      round: _round(mods), currentUid: null, playerLinks: const {});
  return sug.isEmpty ? null : sug.first.duelResult;
}

void main() {
  group('manda el dinero, no el margen', () {
    test('un Nassau caro gana a unos Skins baratos', () {
      // El caso reportado comparaba Match contra Nassau. Match + Press se
      // retiró —era un Nassau sin partición en vueltas— así que la comparación
      // entre tipos que queda es esta, y la regla es la misma: manda el dinero,
      // no el margen.
      final f = _fuente([_nassau(200), _skins(5)])!;
      expect(f.betType, BetModuleType.nassau);
    });

    test('y al revés: unos Skins caros ganan a un Nassau barato', () {
      final f = _fuente([_nassau(5), _skins(200)])!;
      expect(f.betType, BetModuleType.skins);
    });

    test('SKINS entra en la comparación', () {
      // Antes quedaba fuera del if y solo aparecía si no había ningún otro,
      // así que unos Skins caros perdían contra un Nassau barato por estar
      // después en la cadena de ??.
      final f = _fuente([_nassau(5), _skins(200)])!;
      expect(f.betType, BetModuleType.skins);
    });

    test('con los tres, gana el de más dinero', () {
      final f = _fuente([_match(10), _skins(300)])!;
      expect(f.betType, BetModuleType.skins);
    });
  });

  group('desempate', () {
    test('a igualdad de dinero manda el orden declarado, no el del código', () {
      // Nassau y Skins con el mismo importe: gana match play, por regla escrita
      // y no porque su rama estuviera antes en el if.
      // Los dos mueven $60: el match por su importe, los skins por seis hoyos
      // a $10. Empatados en dinero, gana match play.
      final f = _fuente([_match(60), _skins(10)])!;
      expect(f.netAmount, 60);
      expect(f.betType, BetModuleType.nassau);
    });

    test('es determinista: mismo caso, misma fuente', () {
      final a = _fuente([_match(60), _skins(10)])!;
      final b = _fuente([_skins(10), _match(60)])!;
      expect(a.betType, b.betType,
          reason: 'el orden de los módulos no puede cambiar el resultado');
    });
  });

  group('el importe del Match incluye las presiones', () {
    test('un match con presses vale más que solo el match principal', () {
      // El ganador se decide con el match principal, pero el DINERO en juego
      // no puede ignorar las presses: son dinero real entre estos dos, y
      // dejarlas fuera subestimaría el Match en la comparación que decide qué
      // apuesta representa el duelo.
      final conPress = BetModuleInstance(
        id: 'm', type: BetModuleType.nassau, name: 'Match',
        participantIds: const [p1, p2],
        nassauConfig: const NassauConfig(
            frontValue: 0,
            backValue: 0,
            totalValue: 100,
            pressEnabled: true,
            frontPressValue: 50,
            backPressValue: 50,
            autoPressTrigger: 2,
            maxPresses: 5),
      );
      final sinPress = _match(100);

      final con = _fuente([conPress])!;
      final sin = _fuente([sinPress])!;
      expect(con.netAmount, greaterThan(sin.netAmount));
      expect(sin.netAmount, 100);
    });
  });

  group('el importe es la unidad común', () {
    test('netAmount refleja lo que movió el ledger en ese duelo', () {
      final f = _fuente([_nassau(20)])!;
      // p1 gana Front y Total; el Back queda empatado —todos hacen 4— así que
      // son DOS segmentos a 20, no tres.
      expect(f.netAmount, 40);
    });

    test('un match sobre 18 mueve su importe entero', () {
      // Los dos nueves a cero: solo paga el total.
      final f = _fuente([_match(100)])!;
      expect(f.netAmount, 100);
    });
  });
}
