// ─────────────────────────────────────────────────────────────────────────────
// setup_flow_test.dart — qué pasos existen, y qué pasa cuando dejan de existir
//
// La regla del flujo es que se acorta cuando puede. Eso convierte la lista de
// pasos en algo dinámico, y un índice sobre una lista dinámica es una bomba:
// al pasar de equipos a individual la lista se acorta y el mismo número apunta
// a otra pantalla. Por eso el paso se guarda por identidad y estos tests fijan
// el comportamiento en los bordes.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/screens/setup/setup_flow.dart';

void main() {
  group('el flujo se acorta cuando puede', () {
    test('sin equipos, el paso de la bola no existe', () {
      // No aparece deshabilitado ni se atraviesa vacío: no está.
      expect(setupSteps(porEquipos: false), isNot(contains(SetupStep.bola)));
    });

    test('con equipos sí, y va justo después de "quiénes compiten"', () {
      final p = setupSteps(porEquipos: true);
      expect(p, contains(SetupStep.bola));
      expect(p.indexOf(SetupStep.bola), p.indexOf(SetupStep.compiten) + 1);
    });

    test('campo y jugadores siempre van primero, revisar siempre al final', () {
      for (final eq in [true, false]) {
        final p = setupSteps(porEquipos: eq);
        expect(p.first, SetupStep.campo);
        expect(p[1], SetupStep.jugadores);
        expect(p.last, SetupStep.revisar);
      }
    });

    test('nunca se repite un paso', () {
      for (final eq in [true, false]) {
        final p = setupSteps(porEquipos: eq, conParticipantes: true,
            apuestasElegidas: 3, jugadores: 5, conMontos: true, conVentaja: true);
        expect(p.toSet().length, p.length, reason: 'hay un paso duplicado');
      }
    });

    test('el orden respeta el del enum', () {
      // Si alguien inserta un paso en el sitio equivocado de setupSteps, el
      // usuario vería "montos" antes que "qué se cuenta".
      final p = setupSteps(porEquipos: true, conParticipantes: true,
          apuestasElegidas: 2, jugadores: 4, conMontos: true, conVentaja: true);
      final orden = p.map(SetupStep.values.indexOf).toList();
      final ordenado = [...orden]..sort();
      expect(orden, ordenado);
    });
  });

  group('participantes solo cuando hay algo que repartir', () {
    test('una apuesta entre dos jugadores no lo necesita', () {
      final p = setupSteps(porEquipos: false, conParticipantes: true,
          apuestasElegidas: 1, jugadores: 2);
      expect(p, isNot(contains(SetupStep.participantes)));
    });

    test('más de una apuesta sí', () {
      final p = setupSteps(porEquipos: false, conParticipantes: true,
          apuestasElegidas: 2, jugadores: 2);
      expect(p, contains(SetupStep.participantes));
    });

    test('más de dos jugadores también, aunque haya una sola apuesta', () {
      // Con tres o más hay cruces que pueden quedar fuera.
      final p = setupSteps(porEquipos: false, conParticipantes: true,
          apuestasElegidas: 1, jugadores: 3);
      expect(p, contains(SetupStep.participantes));
    });
  });

  group('cuando el paso actual deja de existir', () {
    test('estar en "bola" y cambiar a individual retrocede, no avanza', () {
      // Empujar hacia adelante se saltaría decisiones que el usuario no ha
      // tomado. Se retrocede al paso vivo más cercano.
      final sinEquipos = setupSteps(porEquipos: false);
      expect(resolveStep(SetupStep.bola, sinEquipos), SetupStep.compiten);
    });

    test('un paso que sigue existiendo no se mueve', () {
      final p = setupSteps(porEquipos: true);
      for (final s in p) {
        expect(resolveStep(s, p), s, reason: '$s se movió sin motivo');
      }
    });

    test('siempre devuelve un paso de la lista', () {
      // Si devolviera algo fuera de la lista, indexOf daría -1 y el
      // IndexedStack reventaría.
      for (final eq in [true, false]) {
        final p = setupSteps(porEquipos: eq);
        for (final s in SetupStep.values) {
          expect(p, contains(resolveStep(s, p)), reason: '$s con equipos=$eq');
        }
      }
    });
  });

  test('todo paso tiene etiqueta', () {
    for (final s in SetupStep.values) {
      expect(setupStepLabel(s), isNotEmpty, reason: '$s sin etiqueta');
    }
  });
}
