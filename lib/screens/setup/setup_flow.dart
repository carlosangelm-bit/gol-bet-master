// ─────────────────────────────────────────────────────────────────────────────
// SETUP FLOW — qué pasos existen en esta ronda, y en qué orden
//
// Lógica pura, sin Flutter. La pantalla la consume; los tests también.
//
// La regla: el flujo se acorta cuando puede. Un paso que no aplica NO aparece
// —ni deshabilitado, ni vacío al atravesarlo—. Un paso con una única respuesta
// posible enseña a pulsar Continuar sin leer, y entonces tampoco se lee el que
// sí importaba.
// ─────────────────────────────────────────────────────────────────────────────

/// Los pasos posibles del asistente de nueva ronda.
///
/// Estar aquí no implica aparecer: eso lo decide [setupSteps].
enum SetupStep {
  campo,
  jugadores,
  compiten,
  /// Solo con equipos: sin dos lados no hay "bola del equipo" que elegir.
  bola,
  apuestas,
  /// Solo con más de una apuesta o más de dos jugadores.
  participantes,
  montos,
  ventaja,
  revisar,
}

/// Los pasos de esta ronda, en orden.
///
/// [apuestasElegidas] y [jugadores] deciden si el paso de participantes tiene
/// algo que preguntar: con una sola apuesta entre dos jugadores no hay nada
/// que repartir, juegan todos a todo.
List<SetupStep> setupSteps({
  required bool porEquipos,
  int apuestasElegidas = 0,
  int jugadores = 0,
  bool conMontos = false,
  bool conVentaja = false,
  bool conParticipantes = false,
}) =>
    [
      SetupStep.campo,
      SetupStep.jugadores,
      SetupStep.compiten,
      if (porEquipos) SetupStep.bola,
      SetupStep.apuestas,
      if (conParticipantes && (apuestasElegidas > 1 || jugadores > 2))
        SetupStep.participantes,
      if (conMontos) SetupStep.montos,
      if (conVentaja) SetupStep.ventaja,
      SetupStep.revisar,
    ];

/// El paso al que hay que ir cuando [actual] deja de existir.
///
/// Pasa de verdad: el usuario está en "qué bola", vuelve atrás y cambia a
/// individual. Sin esto, el índice apuntaría a otra pantalla o se saldría de
/// rango. Se elige el paso anterior más cercano que siga vivo, para no
/// empujar al usuario hacia adelante saltándose decisiones.
SetupStep resolveStep(SetupStep actual, List<SetupStep> pasos) {
  if (pasos.contains(actual)) return actual;
  final orden = SetupStep.values.indexOf(actual);
  for (var i = orden - 1; i >= 0; i--) {
    final candidato = SetupStep.values[i];
    if (pasos.contains(candidato)) return candidato;
  }
  return pasos.first;
}

/// Etiqueta corta para la barra de progreso.
String setupStepLabel(SetupStep s) => switch (s) {
      SetupStep.campo => 'Campo',
      SetupStep.jugadores => 'Jugadores',
      SetupStep.compiten => 'Compiten',
      SetupStep.bola => 'Bola',
      SetupStep.apuestas => 'Apuestas',
      SetupStep.participantes => 'Quién juega',
      SetupStep.montos => 'Montos',
      SetupStep.ventaja => 'Ventaja',
      SetupStep.revisar => 'Revisar',
    };
