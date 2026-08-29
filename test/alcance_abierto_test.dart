// ─────────────────────────────────────────────────────────────────────────────
// UN NASSAU, TRES PANELES — Y ERA DINERO
//
// Auditado contra la ronda real 31921707 del 28 de agosto, leída de producción.
// Tiene SEIS módulos de Nassau para cuatro jugadores, y dos de ellos guardan
// `scope: everyone` con dos participantIds:
//
//   pair      CAM+KAWA   → liquida entre 2
//   everyone  CAM+AAM    → liquida entre los CUATRO   ← 6 parejas
//   everyone  CAM+Dylan  → liquida entre los CUATRO   ← 6 parejas
//   ...
//
// Los paneles no mentían: hay tres módulos que mueven dinero entre ese par, así
// que salen tres. Lo que faltaba era decir cuál es cuál, y avisar al crearlos.
//
// Y NO es ruido visual, que era la pregunta que decidía la gravedad: la ronda
// mueve $3550 solo en Nassau porque dos apuestas de dos personas se liquidan
// entre cuatro.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';

const _cuatro = ['CAM', 'AAM', 'KAWA', 'Dylan'];

BetModuleInstance _nassau({required String id, BetScope? scope,
        List<String> pids = const ['CAM', 'AAM']}) =>
    BetModuleInstance(
      id: id,
      type: BetModuleType.nassau,
      name: 'Nassau',
      participantIds: pids,
      scope: scope,
      nassauConfig: const NassauConfig(
          frontValue: 50, backValue: 50, totalValue: 100),
    );

void main() {
  group('1 · un módulo, una fila — y por qué salían tres', () {
    test('el alcance abierto dice SÍ a los seis duelos, no solo al suyo', () {
      // containsPair corta en cuanto el alcance es everyone: los participantIds
      // no se miran. Por eso un Nassau creado entre CAM y AAM aparece en el
      // duelo de KAWA con Dylan.
      final abierto =
          _nassau(id: 'm', scope: const BetScope.everyone());
      var cuantos = 0;
      for (var i = 0; i < _cuatro.length; i++) {
        for (var k = i + 1; k < _cuatro.length; k++) {
          if (abierto.containsPair(_cuatro[i], _cuatro[k])) cuantos++;
        }
      }
      expect(cuantos, 6);
    });

    test('y el de par solo al suyo', () {
      final propio = _nassau(id: 'm', scope: BetScope.pair('CAM', 'AAM'));
      expect(propio.containsPair('CAM', 'AAM'), isTrue);
      expect(propio.containsPair('KAWA', 'Dylan'), isFalse);
    });

    test('con los seis módulos reales, un duelo ve tres Nassau', () {
      // La cuenta exacta del síntoma: los dos abiertos más el suyo.
      final mods = [
        _nassau(id: '1', scope: BetScope.pair('AAM', 'KAWA'), pids: const ['AAM', 'KAWA']),
        _nassau(id: '2', scope: BetScope.pair('KAWA', 'CAM'), pids: const ['KAWA', 'CAM']),
        _nassau(id: '3', scope: const BetScope.everyone(), pids: const ['CAM', 'AAM']),
        _nassau(id: '4', scope: const BetScope.everyone(), pids: const ['CAM', 'Dylan']),
        _nassau(id: '5', scope: BetScope.pair('AAM', 'Dylan'), pids: const ['AAM', 'Dylan']),
        _nassau(id: '6', scope: BetScope.pair('KAWA', 'Dylan'), pids: const ['KAWA', 'Dylan']),
      ];
      int vistos(String a, String b) =>
          mods.where((m) => m.containsPair(a, b)).length;
      expect(vistos('AAM', 'KAWA'), 3);
      expect(vistos('KAWA', 'Dylan'), 3);
      expect(vistos('CAM', 'AAM'), 2);
    });
  });

  group('2 · y era dinero: el alcance abierto liquida entre todos', () {
    test('resolveParticipants ignora los participantIds con everyone', () {
      // Esta es la mitad que convierte el defecto visual en dinero: el módulo
      // no solo SE MUESTRA en los seis duelos, se CALCULA sobre los cuatro.
      final abierto = _nassau(id: 'm', scope: const BetScope.everyone());
      expect(abierto.resolveParticipants(_cuatro), _cuatro);
    });

    test('mientras que el de par se queda en dos', () {
      final propio = _nassau(id: 'm', scope: BetScope.pair('CAM', 'AAM'));
      expect(propio.resolveParticipants(_cuatro), ['CAM', 'AAM']);
    });

    test('sin scope explícito, dos participantes infieren PAR', () {
      // Así nace un módulo creado desde un duelo: defaultFor no pone scope y
      // effectiveScope infiere par. Los dos abiertos de la ronda real llevan el
      // scope escrito, así que se eligió — no se heredó.
      final sinScope = _nassau(id: 'm');
      expect(sinScope.effectiveScope.isPair, isTrue);
      expect(sinScope.resolveParticipants(_cuatro), ['CAM', 'AAM']);
    });
  });
}
