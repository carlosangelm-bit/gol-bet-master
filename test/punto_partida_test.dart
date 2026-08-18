// ─────────────────────────────────────────────────────────────────────────────
// punto_partida_test.dart — el campo opcional del punto de partida guardado
//
// La unificación es de PRESENTACIÓN, no de modelo, y el motivo está medido:
// ninguno de los dos modelos es superconjunto del otro.
//
//   RoundTemplate   guarda BetGroups completos → puede llevar apuestas por
//                   EQUIPOS. Guarda los jugadores como NOMBRES.
//   BettingGroup    guarda pairRules → solo por duelo, nunca equipos. Guarda
//                   los jugadores como REFERENCIAS al directorio.
//
// Fundirlos sin pérdida pediría un tercer modelo con las dos mitades buenas, y
// migrar los dos formatos con los grupos de Carlos dentro. Se unifica lo que el
// usuario ve: una lista y una acción de guardar.
//
// Lo único que sí se añade al modelo es el campo, que NINGUNO de los dos
// guardaba: sin él, "incluir el campo" no tenía nada que incluir.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/services/firestore_service.dart';

RoundTemplate _plantilla({String? campo}) => RoundTemplate(
      id: 't1', name: 'Sábados', emoji: '⛳', description: '',
      playerNames: const ['CAM', 'RAFA'],
      betGroupsJson: const [],
      updatedAt: DateTime(2026, 1, 1),
      courseName: campo,
    );

void main() {
  group('el campo es opcional y no cambia lo guardado', () {
    test('sin pedirlo queda null, no vacío', () {
      // null significa "no se pidió". Una cadena vacía sería un campo que se
      // llama "" y la plantilla intentaría preseleccionarlo.
      expect(_plantilla().courseName, isNull);
    });

    test('solo se escribe en Firestore si se pidió', () {
      // El default no puede ensuciar lo guardado: una plantilla vieja releída
      // tiene que seguir comportándose igual.
      expect(_plantilla().toFirestore().containsKey('courseName'), isFalse);
      expect(_plantilla(campo: 'Malanquín').toFirestore()['courseName'],
          'Malanquín');
    });

    test('copyWith lo conserva', () {
      final t = _plantilla(campo: 'México').copyWith(name: 'Otro');
      expect(t.courseName, 'México');
      expect(t.name, 'Otro');
    });

    test('una plantilla vieja sin el campo sigue siendo válida', () {
      // Es la restricción de siempre: nada guardado cambia de comportamiento.
      final vieja = _plantilla();
      expect(vieja.playerNames, const ['CAM', 'RAFA']);
      expect(vieja.toBetGroups(), isEmpty);
      expect(vieja.courseName, isNull);
    });
  });

  group('por qué no se fusionan los modelos', () {
    test('la plantilla PUEDE guardar apuestas por equipos', () {
      // betGroupsJson son BetGroups completos, y un BetGroup lleva módulos con
      // sides. Un BettingGroup no puede: pairRules son por duelo.
      final conEquipos = BetGroup(
        id: 'g', name: 'G', format: PartidaFormat.teams2v2,
        playerIds: const ['a1', 'a2', 'b1', 'b2'],
        modules: [
          BetModuleInstance(
            id: 'm', type: BetModuleType.nassau, name: 'Nassau',
            participantIds: const ['a1', 'a2', 'b1', 'b2'],
            nassauConfig: NassauConfig.def,
            sides: const [
              BetSide(id: 'A', name: 'Equipo A', playerIds: ['a1', 'a2']),
              BetSide(id: 'B', name: 'Equipo B', playerIds: ['b1', 'b2']),
            ],
          ),
        ],
      );
      final t = RoundTemplate(
        id: 't', name: 'Equipos', emoji: '⛳', description: '',
        playerNames: const ['A1', 'A2', 'B1', 'B2'],
        betGroupsJson: [conEquipos.toJson()],
        updatedAt: DateTime(2026, 1, 1),
      );
      // Sobrevive el roundtrip CON los lados: eso es lo que el grupo perdería.
      final vuelta = t.toBetGroups().single.modules.single;
      expect(vuelta.hasTeamSides, isTrue);
      expect(vuelta.sideA.playerIds, const ['a1', 'a2']);
    });

    test('el grupo guarda REFERENCIAS y la plantilla solo nombres', () {
      // Por eso el grupo puede actualizar handicaps y la plantilla no. Ninguno
      // de los dos es superconjunto: migrar en cualquier dirección pierde algo.
      final bg = BettingGroup(
        id: 'bg', name: 'Viernes', emoji: '🏌',
        playerIds: const ['id_cam', 'id_rafa'],
        pairRules: const [], updatedAt: DateTime(2026, 1, 1),
      );
      expect(bg.playerIds.first, startsWith('id_'));
      expect(_plantilla().playerNames.first, 'CAM');
    });
  });
}
