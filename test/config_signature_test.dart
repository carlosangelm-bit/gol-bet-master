// =============================================================================
// configSignature — identidad de una apuesta.
//
// Setup agrupaba las tarjetas por betGroupId, que BettingGroup construye con
// el id de la PairBetRule. Resultado: 4 jugadores × 5 tipos = 30 tarjetas.
// Ahora se agrupa por CONFIGURACIÓN: las iguales colapsan, las distintas se
// separan solas.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';

BetModuleInstance _nassau(List<String> pids,
        {double front = 50, double back = 50, double total = 100,
        GrossNetMode mode = GrossNetMode.gross}) =>
    BetModuleInstance.defaultFor(BetModuleType.nassau, pids).copyWith(
      nassauConfig: NassauConfig(
          frontValue: front, backValue: back, totalValue: total, mode: mode),
    );

/// Cuenta las tarjetas que pintaría Setup: una por firma distinta.
int _tarjetas(List<BetModuleInstance> mods) =>
    mods.map((m) => m.configSignature).toSet().length;

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  group('Apuestas iguales colapsan', () {
    test('S1 – mismos importes en pares distintos → una sola firma', () {
      final a = _nassau(['ana', 'beto']);
      final b = _nassau(['ana', 'caro']);
      final c = _nassau(['beto', 'caro']);
      expect({a, b, c}.map((m) => m.configSignature).toSet(), hasLength(1));
    });

    test('S2 – el id, el nombre y el betGroupId no cuentan', () {
      final a = _nassau(['ana', 'beto'])
          .copyWith(name: 'Nassau de la mañana', betGroupId: 'X');
      final b = _nassau(['caro', 'dani'])
          .copyWith(name: 'Otro nombre', betGroupId: 'Y');
      expect(a.configSignature, b.configSignature);
    });

    test('S3 – las excepciones por duelo no rompen la familia', () {
      final base = _nassau(['ana', 'beto']);
      final conOverride = _nassau(['ana', 'caro']).copyWith(
        pairConfigOverrides: {
          BetModuleInstance.pairKey('ana', 'caro'): {'value': 999.0}
        },
      );
      expect(base.configSignature, conOverride.configSignature,
          reason: 'un override es una excepción, no otra apuesta');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('Apuestas distintas se separan', () {
    test('D1 – importe distinto → firma distinta', () {
      expect(_nassau(['ana', 'beto']).configSignature,
          isNot(_nassau(['ana', 'caro'], front: 100).configSignature));
    });

    test('D2 – gross vs net → firma distinta', () {
      expect(_nassau(['ana', 'beto']).configSignature,
          isNot(_nassau(['ana', 'beto'], mode: GrossNetMode.net).configSignature));
    });

    test('D3 – tipo distinto → firma distinta', () {
      final n = _nassau(['ana', 'beto']);
      final s = BetModuleInstance.defaultFor(BetModuleType.skins, ['ana', 'beto']);
      expect(n.configSignature, isNot(s.configSignature));
    });

    test('D4 – formatMode distinto → firma distinta', () {
      final a = BetModuleInstance.defaultFor(BetModuleType.skins, ['a', 'b', 'c'])
          .copyWith(formatMode: BetFormatMode.onePot);
      final b = a.copyWith(formatMode: BetFormatMode.allVsAll);
      expect(a.configSignature, isNot(b.configSignature));
    });

    test('D5 – dos duelos por equipos nunca se fusionan', () {
      BetModuleInstance team(List<String> x, List<String> y) =>
          _nassau([...x, ...y]).copyWith(sides: [
            BetSide(id: 'sA', name: 'A', playerIds: x),
            BetSide(id: 'sB', name: 'B', playerIds: y),
          ]);
      expect(team(['a', 'b'], ['c', 'd']).configSignature,
          isNot(team(['a', 'c'], ['b', 'd']).configSignature),
          reason: '"A vs B" y "C vs D" son apuestas distintas');
    });

    test('D6 – allowance de equipo distinto → firma distinta', () {
      BetModuleInstance team(TeamHandicapConfig cfg) =>
          _nassau(['a', 'b', 'c', 'd']).copyWith(
            sides: [
              BetSide(id: 'sA', name: 'A', playerIds: ['a', 'b']),
              BetSide(id: 'sB', name: 'B', playerIds: ['c', 'd']),
            ],
            teamHandicapConfig: cfg,
          );
      expect(team(TeamHandicapConfig.fourBall).configSignature,
          isNot(team(TeamHandicapConfig.local85).configSignature));
    });

    test('D7 – la firma es estable entre llamadas', () {
      final m = _nassau(['ana', 'beto']);
      expect(m.configSignature, m.configSignature);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('El caso real: aplicar un grupo de apuesta', () {
    /// Grupo habitual: cada par con los mismos 5 tipos de apuesta.
    List<BetModuleInstance> aplicarGrupo(
        List<String> jugadores, List<BetModuleType> tipos,
        {Map<String, BetModuleTemplate>? excepciones}) {
      final reglas = <PairBetRule>[];
      for (int i = 0; i < jugadores.length; i++) {
        for (int j = i + 1; j < jugadores.length; j++) {
          final key = '${jugadores[i]}_${jugadores[j]}';
          reglas.add(PairBetRule(
            id: 'r_$key',
            playerAId: jugadores[i],
            playerBId: jugadores[j],
            modules: tipos.map((tp) {
              final ex = excepciones?[key];
              return (ex != null && ex.type == tp)
                  ? ex
                  : BetModuleTemplate(type: tp);
            }).toList(),
          ));
        }
      }
      return BettingGroup(
        id: 'bg', name: 'Los de siempre',
        playerIds: jugadores, pairRules: reglas, updatedAt: DateTime(2025),
      ).toBetModuleInstances(
        presentIds: jugadores.toSet(),
        betGroupId: 'GRUPO', betGroupName: 'Los de siempre',
      );
    }

    const tipos = [
      BetModuleType.nassau, BetModuleType.skins, BetModuleType.medal,
      BetModuleType.putts,  BetModuleType.oyeses,
    ];

    test('G1 – 4 jugadores × 5 tipos: 30 módulos, 5 tarjetas', () {
      final mods = aplicarGrupo(['ana', 'beto', 'caro', 'dani'], tipos);
      expect(mods, hasLength(30), reason: '6 duelos × 5 tipos');
      expect(_tarjetas(mods), 5,
          reason: 'una tarjeta por tipo — antes salían 30');
    });

    test('G2 – 6 jugadores no empeora: siguen siendo 5 tarjetas', () {
      final mods = aplicarGrupo(
          ['a', 'b', 'c', 'd', 'e', 'f'], tipos);
      expect(mods, hasLength(75), reason: '15 duelos × 5 tipos');
      expect(_tarjetas(mods), 5);
    });

    test('G3 – un duelo con importe distinto se separa en su propia tarjeta', () {
      final mods = aplicarGrupo(
        ['ana', 'beto', 'caro', 'dani'],
        tipos,
        excepciones: {
          'ana_beto': const BetModuleTemplate(
            type: BetModuleType.nassau,
            nassauConfig: NassauConfig(
                frontValue: 500, backValue: 500, totalValue: 1000),
          ),
        },
      );
      expect(_tarjetas(mods), 6,
          reason: '5 tipos + el Nassau caro de ana-beto aparte');

      // La tarjeta especial cubre exactamente ese duelo
      final firmas = <String, List<BetModuleInstance>>{};
      for (final m in mods) {
        firmas.putIfAbsent(m.configSignature, () => []).add(m);
      }
      final sueltas = firmas.values.where((l) => l.length == 1).toList();
      expect(sueltas, hasLength(1));
      expect(sueltas.first.first.participantIds, containsAll(['ana', 'beto']));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('copyForPair — meter a un jugador en una apuesta', () {
    test('C1 – conserva la configuración exacta', () {
      final base  = _nassau(['ana', 'beto'], front: 75, mode: GrossNetMode.net);
      final clone = base.copyForPair('nuevo-id', 'ana', 'zoe');
      expect(clone.configSignature, base.configSignature,
          reason: 'debe caer en la MISMA tarjeta');
    });

    test('C2 – cambia participantes, alcance e id', () {
      final base  = _nassau(['ana', 'beto']);
      final clone = base.copyForPair('nuevo-id', 'ana', 'zoe');
      expect(clone.id, 'nuevo-id');
      expect(clone.participantIds, ['ana', 'zoe']);
      expect(clone.effectiveScope.kind, BetScopeKind.pair);
      expect(base.participantIds, ['ana', 'beto'], reason: 'no muta el original');
    });

    test('C3 – no arrastra las excepciones de otros duelos', () {
      final base = _nassau(['ana', 'beto']).copyWith(
        pairConfigOverrides: {
          BetModuleInstance.pairKey('ana', 'beto'): {'value': 999.0}
        },
      );
      final clone = base.copyForPair('n', 'ana', 'zoe');
      expect(clone.pairConfigOverrides, isNull);
    });

    test('C4 – nunca hereda lados de equipo', () {
      final base = _nassau(['a', 'b', 'c', 'd']).copyWith(sides: [
        BetSide(id: 'sA', name: 'A', playerIds: ['a', 'b']),
        BetSide(id: 'sB', name: 'B', playerIds: ['c', 'd']),
      ]);
      final clone = base.copyForPair('n', 'a', 'zoe');
      expect(clone.hasTeamSides, isFalse);
    });

    test('C5 – meter a un jugador nuevo no crea tarjetas extra', () {
      // 3 jugadores con Nassau todos-contra-todos = 3 duelos, 1 tarjeta
      final mods = [
        _nassau(['ana', 'beto']),
        _nassau(['ana', 'caro']),
        _nassau(['beto', 'caro']),
      ];
      expect(_tarjetas(mods), 1);

      // Entra Zoe: un duelo contra cada uno
      final conZoe = [
        ...mods,
        for (final rival in ['ana', 'beto', 'caro'])
          mods.first.copyForPair('id_$rival', rival, 'zoe'),
      ];
      expect(conZoe, hasLength(6));
      expect(_tarjetas(conZoe), 1,
          reason: 'sigue siendo la misma apuesta, ahora con 6 duelos');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // El paso "Revisar" usa la MISMA agrupación
  //
  // Se me escapó: arreglé la lista del paso de Apuestas pero el resumen de
  // Revisar pintaba un chip por módulo, así que seguían saliendo 30.
  // ═══════════════════════════════════════════════════════════════════════════
  group('Consistencia entre pantallas', () {
    test('X1 – chips de Revisar = tarjetas de Apuestas', () {
      const jugadores = ['ana', 'beto', 'caro', 'dani'];
      const tipos = [
        BetModuleType.nassau, BetModuleType.skins, BetModuleType.medal,
        BetModuleType.putts,  BetModuleType.oyeses,
      ];
      final reglas = <PairBetRule>[];
      for (int i = 0; i < jugadores.length; i++) {
        for (int j = i + 1; j < jugadores.length; j++) {
          reglas.add(PairBetRule(
            id: 'r_${jugadores[i]}_${jugadores[j]}',
            playerAId: jugadores[i], playerBId: jugadores[j],
            modules: tipos.map((tp) => BetModuleTemplate(type: tp)).toList(),
          ));
        }
      }
      final mods = BettingGroup(
        id: 'bg', name: 'G', playerIds: jugadores,
        pairRules: reglas, updatedAt: DateTime(2025),
      ).toBetModuleInstances(
        presentIds: jugadores.toSet(),
        betGroupId: 'GRUPO', betGroupName: 'G',
      );

      // Ambas pantallas deduplican por configSignature: mismo recuento.
      final familias = mods.map((m) => m.configSignature).toSet();
      expect(mods.length, 30);
      expect(familias.length, 5,
          reason: 'tanto las tarjetas como los chips deben salir 5');
    });
  });
}
