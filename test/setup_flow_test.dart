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

  _cuenta();
  _desdeGrupo();
  _atajo();

  test('todo paso tiene etiqueta', () {
    for (final s in SetupStep.values) {
      expect(setupStepLabel(s), isNotEmpty, reason: '$s sin etiqueta');
    }
  });
}

// ── El paso de qué se cuenta ─────────────────────────────────────────────────
void _cuenta() {
  group('el paso de qué se cuenta', () {
    test('va después de la bola y antes del detalle', () {
      final p = setupSteps(porEquipos: true, conCuenta: true);
      expect(p.indexOf(SetupStep.cuenta), p.indexOf(SetupStep.bola) + 1);
      expect(p.indexOf(SetupStep.cuenta),
          lessThan(p.indexOf(SetupStep.apuestas)));
    });

    test('en individual va justo después de "quiénes compiten"', () {
      final p = setupSteps(porEquipos: false, conCuenta: true);
      expect(p.indexOf(SetupStep.cuenta), p.indexOf(SetupStep.compiten) + 1);
    });

    test('resolveStep no deja al usuario en cuenta si desaparece', () {
      final sin = setupSteps(porEquipos: false);
      expect(sin, isNot(contains(SetupStep.cuenta)));
      expect(sin, contains(resolveStep(SetupStep.cuenta, sin)));
    });
  });
}

// ── Arrancar desde un grupo de apuesta guardado ──────────────────────────────
//
// Un grupo responde media configuración por adelantado. Pedirla igual y ofrecer
// el grupo al final —como hacía el paso 5— es preguntarla dos veces.
//
// Mismo principio que la señalización y la partición derivada: no preguntar lo
// que ya está respondido.
void _desdeGrupo() {
  group('el wizard aterriza donde el grupo no llega', () {
    test('en Campo, porque el grupo no guarda campo', () {
      // Hoy es el primer paso, así que el ahorro está en que los de en medio
      // vienen rellenos, no en saltárselos. Conviene que quede dicho.
      final pasos = setupSteps(porEquipos: false, conCuenta: true,
          conParticipantes: true, conMontos: true, conVentaja: true,
          apuestasElegidas: 2, jugadores: 4);
      expect(primerPasoSinResolver(pasos, resueltosPorGrupo()),
          SetupStep.campo);
    });

    test('si el campo estuviera resuelto, aterrizaría en Ventaja', () {
      // Se calcula en vez de fijarse: el día que el grupo guarde un campo, esto
      // funciona sin tocar nada más.
      final pasos = setupSteps(porEquipos: false, conCuenta: true,
          conParticipantes: true, conMontos: true, conVentaja: true,
          apuestasElegidas: 2, jugadores: 4);
      expect(
          primerPasoSinResolver(
              pasos, {...resueltosPorGrupo(), SetupStep.campo}),
          SetupStep.ventaja);
    });

    test('un grupo no responde la ventaja', () {
      // No está en el modelo, y aplicarla por defecto sería inventarse un
      // acuerdo que nadie pactó.
      expect(resueltosPorGrupo(), isNot(contains(SetupStep.ventaja)));
    });

    test('ni el campo', () {
      expect(resueltosPorGrupo(), isNot(contains(SetupStep.campo)));
    });

    test('sí responde jugadores, qué se juega y montos', () {
      for (final p in [SetupStep.jugadores, SetupStep.cuenta,
                       SetupStep.montos, SetupStep.participantes,
                       SetupStep.apuestas]) {
        expect(resueltosPorGrupo(), contains(p), reason: '$p');
      }
    });

    test('el paso resuelto sigue EXISTIENDO en la lista', () {
      // Resolverlo no es quitarlo: hay que poder retroceder a cambiarlo.
      // Precargar no es bloquear.
      final pasos = setupSteps(porEquipos: false, conCuenta: true,
          conParticipantes: true, conMontos: true, conVentaja: true,
          apuestasElegidas: 2, jugadores: 4);
      for (final p in resueltosPorGrupo()) {
        if (p == SetupStep.bola) continue; // solo con equipos
        expect(pasos, contains(p), reason: '$p desapareció');
      }
    });

    test('con todo resuelto se aterriza en revisar, no fuera de rango', () {
      final pasos = setupSteps(porEquipos: false);
      expect(primerPasoSinResolver(pasos, SetupStep.values.toSet()),
          pasos.last);
    });

    test('el aterrizaje siempre es un paso de la lista', () {
      // Si devolviera algo fuera, el IndexedStack reventaría.
      for (final eq in [true, false]) {
        final pasos = setupSteps(porEquipos: eq, conCuenta: true);
        expect(pasos,
            contains(primerPasoSinResolver(pasos, resueltosPorGrupo())));
      }
    });
  });
}

// ── Un punto de partida es un ATAJO, no un formulario prellenado ─────────────
//
// La precarga funcionaba pero se sentía igual que empezar de cero: la barra
// mostraba "paso 1 de 8" sin un check y había que pulsar Siguiente seis veces
// confirmando lo que el grupo ya respondía.
//
// Prellenar ahorra escribir pero se recorre igual. Un atajo lleva al final y
// solo para donde falta algo.
void _atajo() {
  group('qué queda por decidir', () {
    test('hoy: campo y ventaja, porque ningún modelo los guarda', () {
      expect(preguntasPendientes(traeCampo: false, traeVentaja: false),
          [SetupStep.campo, SetupStep.ventaja]);
    });

    test('con el campo guardado, solo la ventaja', () {
      // Se CALCULA: el día que un punto de partida guarde el campo, la pantalla
      // de arranque se acorta sola sin tocar nada.
      expect(preguntasPendientes(traeCampo: true, traeVentaja: false),
          [SetupStep.ventaja]);
    });

    test('con todo guardado, ninguna pregunta', () {
      // Criterio 5. No es alcanzable en pantalla hoy —nada guarda campo Y
      // ventaja— así que solo se puede fijar por test.
      expect(preguntasPendientes(traeCampo: true, traeVentaja: true), isEmpty);
    });

    test('el orden respeta el del wizard', () {
      // Campo antes que ventaja, como en el flujo completo: cambiar el orden
      // entre las dos superficies desorientaría.
      final p = preguntasPendientes(traeCampo: false, traeVentaja: false);
      expect(p.map(SetupStep.values.indexOf).toList(),
          [...p.map(SetupStep.values.indexOf)]..sort());
    });
  });

  group('la frase de la tarjeta', () {
    test('dice qué falta, no de qué tipo es', () {
      // "Grupo de apuesta" contra "plantilla de ronda" describe implementación.
      // Lo que permite decidir si tocarla es qué queda por decidir.
      expect(
          faltaPorDecidir(
              preguntasPendientes(traeCampo: false, traeVentaja: false)),
          'Falta elegir campo y ventaja');
    });

    test('en singular cuando falta una sola', () {
      expect(faltaPorDecidir(preguntasPendientes(traeCampo: true, traeVentaja: false)),
          'Solo falta la ventaja');
    });

    test('y lo dice cuando no falta nada', () {
      expect(faltaPorDecidir(const []), 'Todo listo');
    });

    test('nunca queda vacía', () {
      // Una tarjeta sin frase no dice si se puede tocar.
      for (final c in [true, false]) {
        for (final v in [true, false]) {
          expect(
              faltaPorDecidir(
                  preguntasPendientes(traeCampo: c, traeVentaja: v)),
              isNotEmpty);
        }
      }
    });
  });
}
