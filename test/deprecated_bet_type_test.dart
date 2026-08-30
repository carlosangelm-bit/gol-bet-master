// ─────────────────────────────────────────────────────────────────────────────
// deprecated_bet_type_test.dart — retirar un tipo sin romper el pasado
//
// Match + Press se retira del catálogo porque es redundante: NassauConfig ya
// trae todo el aparato de presiones. Pero hay rondas guardadas en Firestore con
// type: matchAutoPress serializado, y una ronda histórica que cambia de
// resultado es peor que un módulo redundante.
//
// La frontera: NO se puede crear uno nuevo, SÍ se sigue deserializando y
// liquidando exactamente igual.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';

const p1 = 'p1', p2 = 'p2';

Round _rondaConMatch() {
  final course = CourseInfo(name: 'T',
      holes: List.generate(18, (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)));
  final gross = {
    p1: {for (var h = 1; h <= 18; h++) h: h <= 6 ? 3 : 4},
    p2: {for (var h = 1; h <= 18; h++) h: 4},
  };
  final mod = BetModuleInstance(
    id: 'm', type: BetModuleType.matchAutoPress, name: 'Match',
    participantIds: const [p1, p2],
    matchAutoPressConfig: const MatchAutoPressConfig(
        matchValue: 100, pressValue: 50, pressTriggerValue: 2, maxPresses: 5),
  );
  return Round(
    id: 'r', name: 'R', course: course,
    players: [Player(id: p1, name: 'P1'), Player(id: p2, name: 'P2')],
    roundPlayers: [
      RoundPlayer(playerId: p1, handicapEnRonda: 0),
      RoundPlayer(playerId: p2, handicapEnRonda: 0),
    ],
    betGroups: [BetGroup(id: 'g', name: 'G',
        format: PartidaFormat.allInOnePot,
        playerIds: const [p1, p2], modules: [mod])],
    scores: {
      for (final e in gross.entries)
        e.key: {for (final h in e.value.entries)
          h.key: HoleScore(playerId: e.key, hole: h.key, grossScore: h.value)},
    },
    events: const {}, oyeseRankings: const {}, sliding: const [],
    createdAt: DateTime(2026, 1, 1), totalHoles: 18,
  );
}

void main() {
  group('no se puede crear', () {
    test('matchAutoPress queda fuera del catálogo', () {
      expect(creatableBetTypes, isNot(contains(BetModuleType.matchAutoPress)));
      expect(BetModuleType.matchAutoPress.isCreatable, isFalse);
    });

    test('los demás tipos siguen disponibles', () {
      for (final t in BetModuleType.values) {
        if (t == BetModuleType.matchAutoPress) continue;
        expect(creatableBetTypes, contains(t), reason: '$t desapareció');
      }
      expect(creatableBetTypes.length, BetModuleType.values.length - 1);
    });
  });

  group('pero el pasado no se toca', () {
    test('el tipo sigue en el enum y se deserializa por nombre', () {
      // Si el valor desapareciera del enum, las rondas guardadas fallarían al
      // cargar o se abrirían SIN la apuesta.
      expect(BetModuleType.values.byName('matchAutoPress'),
          BetModuleType.matchAutoPress);
    });

    test('un módulo guardado sobrevive el roundtrip JSON', () {
      final mod = BetModuleInstance(
        id: 'm', type: BetModuleType.matchAutoPress, name: 'Match',
        participantIds: const [p1, p2],
        matchAutoPressConfig: const MatchAutoPressConfig(
            matchValue: 100, pressValue: 50, pressTriggerValue: 2),
      );
      final back = BetModuleInstance.fromJson(mod.toJson());
      expect(back.type, BetModuleType.matchAutoPress);
      expect(back.matchAutoPress.matchValue, 100);
      expect(back.matchAutoPress.pressValue, 50);
    });

    test('una ronda histórica sigue liquidando lo mismo', () {
      final entries = BetEngine.computeAll(_rondaConMatch());
      expect(entries, isNotEmpty, reason: 'la apuesta dejó de pagar');

      var total = 0.0;
      for (final e in entries) {
        total += e.amount;
      }
      // 1 match de 100 + 2 presses de 50 = 200. El mismo importe que antes de
      // retirar el tipo del catálogo.
      expect(total, 200);
      expect(entries.every((e) => e.betType == BetModuleType.matchAutoPress),
          isTrue);
    });

    test('sigue teniendo etiqueta e icono para pintarse', () {
      // Las pantallas que muestran una ronda histórica los necesitan; sin
      // ellos, abrir la ronda reventaría en vez de mostrar la apuesta.
      expect(BetModuleType.matchAutoPress.label, isNotEmpty);
      expect(() => BetModuleType.matchAutoPress.icono, returnsNormally);
      expect(BetModuleType.matchAutoPress.description, isNotEmpty);
    });
  });
}
