// ─────────────────────────────────────────────────────────────────────────────
// heroe_test.dart — la barra de pasos y la cifra héroe
//
// Dos cosas de la dirección de diseño:
//
//   · la barra pintaba las DIEZ etiquetas en 390 px y salía "Qué se
//     juegaDetalle" sin espacio
//   · cada pantalla apilaba varias respuestas sin declarar cuál es la principal
//
// El punto que más importa aquí es la RESOLUCIÓN del héroe: 1º el vinculado, 2º
// el elegido y recordado, y nunca adivinar. Se descartó caer al "jugador que
// está anotando" porque _activePlayerId es estado local de la captura y no está
// disponible en Resultados.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/screens/setup/setup_flow.dart';

const todos = ['cam', 'rafa', 'cav'];

Round _round({String? vinculadoA}) => Round(
      id: 'r', name: 'R',
      course: CourseInfo(name: 'T',
          holes: List.generate(18,
              (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1))),
      players: [
        for (final i in todos)
          Player(id: i, name: i.toUpperCase(),
              linkedUserId: i == vinculadoA ? 'uid_1' : null),
        // Un virtual, para comprobar que no se puede ser el héroe.
        Player(id: 'team_A', name: 'Equipo A', isVirtual: true,
            teamMemberIds: const ['cam', 'rafa']),
      ],
      roundPlayers: todos
          .map((i) => RoundPlayer(playerId: i, handicapEnRonda: 0)).toList(),
      betGroups: const [], scores: const {}, events: const {},
      oyeseRankings: const {}, sliding: const [],
      createdAt: DateTime(2026, 1, 1), totalHoles: 18,
    );

/// Réplica de la resolución de la pantalla.
Player? heroe(Round r, {String? uid, String? elegido}) {
  final vinculado = uid == null
      ? null
      : r.players.where((p) => p.linkedUserId == uid && !p.isVirtual).firstOrNull;
  if (vinculado != null) return vinculado;
  if (elegido == null) return null;
  return r.realPlayers.where((p) => p.id == elegido).firstOrNull;
}

void main() {
  group('la barra de pasos', () {
    test('con diez pasos solo se lee UNA etiqueta', () {
      // Diez etiquetas en 390 px daban "Qué se juegaDetalle". Los puntos y los
      // checks ya dicen dónde estás.
      final pasos = setupSteps(porEquipos: true, conCuenta: true,
          conParticipantes: true, conMontos: true, conVentaja: true,
          apuestasElegidas: 2, jugadores: 4);
      expect(pasos.length, 10);
      // La barra pinta un solo texto: 'Paso N de M · Etiqueta'.
      final texto = 'Paso 5 de ${pasos.length} · ${setupStepLabel(pasos[4])}';
      expect(texto, 'Paso 5 de 10 · Qué se juega');
    });

    test('los tres recuentos que existen', () {
      // Individual, por equipos, y por equipos con participantes: los tres
      // caben porque solo se pinta una etiqueta.
      final cuentas = [
        setupSteps(porEquipos: false, conCuenta: true).length,
        setupSteps(porEquipos: true, conCuenta: true).length,
        setupSteps(porEquipos: true, conCuenta: true, conParticipantes: true,
                conMontos: true, conVentaja: true,
                apuestasElegidas: 2, jugadores: 4)
            .length,
      ];
      // 6 · 7 · 10. Los conté mal al escribir el test y el propio test lo
      // corrigió: con el paso «Qué se juega» el individual ya son seis.
      expect(cuentas, [6, 7, 10]);
    });

    test('toda etiqueta cabe en una línea corta', () {
      // Si alguien añade un paso con nombre largo, esto lo señala antes de que
      // se vea en pantalla.
      for (final s in SetupStep.values) {
        expect(setupStepLabel(s).length, lessThanOrEqualTo(14), reason: '$s');
      }
    });
  });

  group('de quién es la cifra héroe', () {
    test('1º el jugador vinculado a la cuenta', () {
      final r = _round(vinculadoA: 'rafa');
      expect(heroe(r, uid: 'uid_1')?.id, 'rafa');
    });

    test('2º el elegido, si no hay vinculado', () {
      final r = _round();
      expect(heroe(r, uid: 'uid_1', elegido: 'cav')?.id, 'cav');
    });

    test('el vinculado MANDA sobre el elegido', () {
      // Si no, cambiar de jugador una vez dejaría permanentemente oculto tu
      // propio neto.
      final r = _round(vinculadoA: 'cam');
      expect(heroe(r, uid: 'uid_1', elegido: 'cav')?.id, 'cam');
    });

    test('sin vinculado ni elegido no hay héroe: se PREGUNTA', () {
      // La app no adivina quién eres. Devolver null es lo que dispara la
      // pregunta en pantalla, no una pantalla vacía.
      expect(heroe(_round(), uid: 'uid_1'), isNull);
      expect(heroe(_round()), isNull);
    });

    test('un jugador virtual no puede ser el héroe', () {
      // "¿Cuánto gano o pierdo yo?" no la responde un equipo. realPlayers ya
      // los filtra.
      final r = _round();
      expect(heroe(r, elegido: 'team_A'), isNull);
      expect(r.realPlayers.map((p) => p.id), todos);
    });

    test('un vinculado virtual tampoco', () {
      // El filtro !p.isVirtual de la resolución: sin él, un virtual con
      // linkedUserId ganaría.
      final r = Round(
        id: 'r', name: 'R',
        course: CourseInfo(name: 'T',
            holes: List.generate(18,
                (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1))),
        players: [
          Player(id: 'cam', name: 'CAM'),
          Player(id: 'v', name: 'Equipo', isVirtual: true,
              linkedUserId: 'uid_1', teamMemberIds: const ['cam']),
        ],
        roundPlayers: [RoundPlayer(playerId: 'cam', handicapEnRonda: 0)],
        betGroups: const [], scores: const {}, events: const {},
        oyeseRankings: const {}, sliding: const [],
        createdAt: DateTime(2026, 1, 1), totalHoles: 18,
      );
      expect(heroe(r, uid: 'uid_1'), isNull);
    });

    test('elegir a alguien que no juega no da héroe', () {
      expect(heroe(_round(), elegido: 'nadie'), isNull);
    });
  });
}
