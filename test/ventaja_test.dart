// ─────────────────────────────────────────────────────────────────────────────
// ventaja_test.dart — handicap y sliding son excluyentes, y el flag no se ve
//
// Handicap iguala por nivel declarado y sliding por historial del grupo:
// sumarlos aplicaría la ventaja dos veces. El motor ya prioriza pairSliding
// sobre el handicap, así que dejar el mapa puesto con handicap elegido
// aplicaría una ventaja que nadie pidió.
//
// Y el interruptor "recalcular al cerrar" decide si la ronda ALIMENTA el
// historial, no si los números se ven.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/providers/round_provider.dart';

CourseInfo _course() => CourseInfo(name: 'T',
    holes: List.generate(18,
        (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)));

Round _round({
  Map<String, double> pairSliding = const {},
  bool recalcula = true,
  double hcpA = 0,
  double hcpB = 0,
}) =>
    Round(
      id: 'r', name: 'R', course: _course(),
      players: [Player(id: 'a', name: 'A'), Player(id: 'b', name: 'B')],
      roundPlayers: [
        RoundPlayer(playerId: 'a', handicapEnRonda: hcpA),
        RoundPlayer(playerId: 'b', handicapEnRonda: hcpB),
      ],
      betGroups: [BetGroup(id: 'g', name: 'G',
          format: PartidaFormat.oneVsOne, playerIds: const ['a', 'b'],
          modules: [BetModuleInstance.defaultFor(
              BetModuleType.nassau, const ['a', 'b'], id: 'm')])],
      scores: {
        for (final p in ['a', 'b'])
          p: {for (var h = 1; h <= 18; h++)
            h: HoleScore(playerId: p, hole: h, grossScore: p == 'a' ? 4 : 5)},
      },
      events: const {}, oyeseRankings: const {}, sliding: const [],
      pairSliding: pairSliding,
      slidingRecalcula: recalcula,
      createdAt: DateTime(2026, 1, 1), totalHoles: 18,
    );

void main() {
  group('el flag de recalculo', () {
    test('por defecto está encendido', () {
      // Las rondas guardadas antes de que existiera el campo se comportan igual.
      expect(_round().slidingRecalcula, isTrue);
    });

    test('sobrevive el roundtrip cuando está apagado', () {
      // Si no se serializara, apagarlo no serviría de nada al releer la ronda.
      final r = roundFromJson(
          jsonDecode(jsonEncode(roundToJson(_round(recalcula: false))))
              as Map<String, dynamic>);
      expect(r.slidingRecalcula, isFalse);
    });

    test('encendido no ocupa espacio en el documento', () {
      // Solo se escribe cuando está apagado: el default no ensucia lo guardado.
      expect(roundToJson(_round()).containsKey('slidingRecalcula'), isFalse);
      expect(roundToJson(_round(recalcula: false))['slidingRecalcula'], false);
    });

    test('no toca el cálculo: mismo dinero encendido y apagado', () {
      // Decide si la ronda ALIMENTA el historial, no cuánto se paga hoy.
      final on = BetEngine.computeAll(_round(recalcula: true));
      final off = BetEngine.computeAll(_round(recalcula: false));
      expect(off.fold<double>(0, (a, e) => a + e.amount),
          on.fold<double>(0, (a, e) => a + e.amount));
    });
  });

  group('handicap y sliding no se suman', () {
    test('con pairSliding puesto, el motor lo prioriza sobre el handicap', () {
      // Es la razón por la que el paso solo escribe el mapa si se ELIGIÓ
      // sliding: dejarlo con handicap elegido aplicaría las dos ventajas.
      final soloHcp = BetEngine.computeAll(_round(hcpA: 0, hcpB: 18));
      final conSliding = BetEngine.computeAll(
          _round(hcpA: 0, hcpB: 18, pairSliding: const {'a|b': 0}));
      expect(conSliding.fold<double>(0, (x, e) => x + e.amount),
          isNot(soloHcp.fold<double>(0, (x, e) => x + e.amount)),
          reason: 'si dieran igual, pairSliding no estaría mandando');
    });

    test('sin ventaja: handicap a cero deja el resultado bruto', () {
      final bruto = BetEngine.computeAll(_round(hcpA: 0, hcpB: 0));
      expect(bruto, isNotEmpty);
      // A hace 4 y B hace 5 en los 18: gana A sin necesidad de golpes.
      expect(bruto.every((e) => e.toPlayerId == 'a'), isTrue);
    });
  });

  group('la clave del sliding usa una sola convención', () {
    test('pairKey ordena, así que (a,b) y (b,a) son la misma', () {
      expect(BetEngine.pairKey('b', 'a'), BetEngine.pairKey('a', 'b'));
      expect(BetEngine.pairKey('a', 'b'), 'a|b');
    });

    test('y el signo se lee del id menor al mayor', () {
      // El mapa guarda recv(idMenor, idMayor). Pintar la pareja en otro orden
      // invertiría el número en pantalla sin que nada falle.
      final r = _round(pairSliding: const {'a|b': 3});
      expect(r.pairSliding[BetEngine.pairKey('b', 'a')], 3);
    });
  });
}
