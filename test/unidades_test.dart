// ─────────────────────────────────────────────────────────────────────────────
// unidades_test.dart — el valor se configura, el evento se registra
//
// "Puedo establecer el monto por unidad en el grupo de apuesta, pero también
// puedo cargar la unidad y el monto en la tarjeta."
//
// Dos fuentes de verdad para el mismo número: la hoja de captura mantenía un
// _localValues mutable que ganaba sobre lo pactado. La distinción que faltaba es
// la misma de scoreCarriersOf: una cosa es QUÉ pasó y otra CUÁNTO VALE lo que
// pasó.
//
// Y el criterio 5 —dos cruces con montos distintos liquidan distinto— resulta
// que el modelo ya lo soportaba: _units consulta effectiveValueForDuel, así que
// pairConfigOverrides con la clave 'allEvents' fija el monto de un duelo sin
// expandir el módulo. Se comprueba sobre el LIBRO, no sobre la config.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';

const a = 'a', b = 'b', c = 'c';
const todos = [a, b, c];

CourseInfo _course() => CourseInfo(name: 'T',
    holes: List.generate(18,
        (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)));

/// Ronda donde SOLO 'a' hace un birdie, en el hoyo 1.
Round _round(BetModuleInstance mod) => Round(
      id: 'r', name: 'R', course: _course(),
      players: todos.map((i) => Player(id: i, name: i)).toList(),
      roundPlayers:
          todos.map((i) => RoundPlayer(playerId: i, handicapEnRonda: 0)).toList(),
      betGroups: [BetGroup(id: 'g', name: 'G',
          format: PartidaFormat.oneVsOne, playerIds: todos, modules: [mod])],
      scores: {
        for (final p in todos)
          p: {for (var h = 1; h <= 18; h++)
            h: HoleScore(playerId: p, hole: h, grossScore: 4)},
      },
      events: {
        a: {1: [HoleEvent(playerId: a, hole: 1, type: UnitEventType.birdie)]},
      },
      oyeseRankings: const {}, sliding: const [],
      createdAt: DateTime(2026, 1, 1), totalHoles: 18,
    );

BetModuleInstance _units({
  Map<UnitEventType, double>? valores,
  Map<String, Map<String, dynamic>>? porPareja,
}) =>
    BetModuleInstance(
      id: 'u', type: BetModuleType.units, name: 'Unidades',
      participantIds: todos,
      unitsConfig: UnitsConfig(
          eventValues: valores ??
              {for (final e in UnitEventType.values) e: 50}),
      pairConfigOverrides: porPareja,
    );

/// Lo que cobra 'a' de un rival concreto.
double _cobra(Round r, String rival) => BetEngine.computeAll(r)
    .where((e) => e.toPlayerId == a && e.fromPlayerId == rival)
    .fold<double>(0, (x, e) => x + e.amount);

void main() {
  group('el monto sale de la configuración de la apuesta', () {
    test('el birdie se cobra al valor configurado', () {
      final r = _round(_units());
      expect(_cobra(r, b), 50);
      expect(_cobra(r, c), 50);
    });

    test('cambiar el valor cambia el importe', () {
      // Si esto no cambiara, el monto no vendría de la config.
      final r = _round(_units(
          valores: {for (final e in UnitEventType.values) e: 120}));
      expect(_cobra(r, b), 120);
    });

    test('solo se cobra el evento que OCURRIÓ', () {
      // La tarjeta registra qué pasó: sin evento no hay cobro, por mucho que el
      // tipo tenga valor configurado.
      final entries = BetEngine.computeAll(_round(_units()));
      expect(entries.every((e) => e.reason.contains('Birdie')), isTrue,
          reason: 'aparecen eventos que nadie registró');
      expect(entries.length, 2, reason: 'un birdie de a contra b y contra c');
    });
  });

  group('todas a un monto, con desviación', () {
    test('withAllEventsValue fija los seis', () {
      final cfg = UnitsConfig.def.withAllEventsValue(80);
      for (final e in UnitEventType.values) {
        expect(cfg.valueFor(e), 80, reason: e.name);
      }
    });

    test('y después se puede desviar uno solo', () {
      // El caso común en un campo, el detallado disponible: un eagle suele valer
      // más que un birdie.
      final base = UnitsConfig.def.withAllEventsValue(50);
      final cfg = UnitsConfig(eventValues: {
        ...base.eventValues,
        UnitEventType.eagle: 200,
      });
      expect(cfg.valueFor(UnitEventType.birdie), 50);
      expect(cfg.valueFor(UnitEventType.eagle), 200);
    });

    test('y la desviación llega al libro', () {
      final r = _round(_units(valores: {
        for (final e in UnitEventType.values) e: 50,
        UnitEventType.birdie: 200,
      }));
      expect(_cobra(r, b), 200, reason: 'el birdie desviado no se aplicó');
    });
  });

  group('montos distintos por cruce — criterio 5, sobre el libro', () {
    test('un duelo con override cobra distinto que el resto', () {
      // El modelo ya lo soportaba: _units consulta effectiveValueForDuel. La
      // clave del override en units es 'allEvents', que fija UN valor para todos
      // los eventos de ese par.
      final clave = BetModuleInstance.pairKey(a, b);
      final r = _round(_units(porPareja: {
        clave: {'allEvents': 300.0},
      }));
      expect(_cobra(r, b), 300, reason: 'el override del duelo a–b no se aplicó');
      expect(_cobra(r, c), 50, reason: 'el resto debe seguir en el base');
    });

    test('sin override todos cobran igual', () {
      // Lo que da valor al test anterior: si sin override ya difirieran, no
      // estaría probando el override.
      final r = _round(_units());
      expect(_cobra(r, b), _cobra(r, c));
    });

    test('el override NO exige expandir el módulo', () {
      // Un solo módulo con dos importes distintos. Si hubiera hecho falta
      // expandir por cruces, el alcance habría sido mayor.
      final clave = BetModuleInstance.pairKey(a, b);
      final r = _round(_units(porPareja: {clave: {'allEvents': 300.0}}));
      expect(r.betGroups.single.modules.length, 1);
    });
  });
}
