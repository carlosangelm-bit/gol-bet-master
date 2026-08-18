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
  /// Multi-select de qué se cuenta, con la configuración de cada apuesta
  /// desplegada debajo en el mismo paso.
  cuenta,
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
  bool conCuenta = false,
}) =>
    [
      SetupStep.campo,
      SetupStep.jugadores,
      SetupStep.compiten,
      if (porEquipos) SetupStep.bola,
      if (conCuenta) SetupStep.cuenta,
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
      SetupStep.cuenta => 'Qué se juega',
      SetupStep.apuestas => 'Detalle',
      SetupStep.participantes => 'Quién juega',
      SetupStep.montos => 'Montos',
      SetupStep.ventaja => 'Ventaja',
      SetupStep.revisar => 'Revisar',
    };

/// Qué pasos deja resueltos un punto de partida guardado.
///
/// Un grupo de apuesta guardado responde media configuración por adelantado.
/// Pedirla igual y ofrecer el grupo al FINAL —como hacía el paso 5— es
/// preguntarla dos veces: hay que recorrer Campo, Jugadores, Compiten, Bola y
/// Qué se juega para luego seleccionar el grupo que evitaría todo eso.
///
/// Qué responde un BettingGroup, y por qué:
///
///   · Jugadores      → playerIds, los habituales
///   · Compiten       → INDIVIDUAL. pairRules son reglas por duelo, así que el
///                      grupo solo puede describir juego uno contra uno
///   · Qué se juega   → los tipos de pairRules[].modules
///   · Participantes  → las reglas dicen qué pareja juega qué
///   · Montos         → cada BetModuleTemplate lleva su config tipada, y con
///                      ella los importes
///
/// Y qué NO responde:
///
///   · Campo   → el modelo no guarda campo. Es el PRIMER paso, así que hoy el
///               aterrizaje es siempre ahí y el ahorro está en que los pasos de
///               en medio vienen rellenos, no en saltárselos.
///   · Ventaja → tampoco está en el modelo. Es el segundo sin responder.
///
/// Si algún día el grupo guardara un campo, esta función haría aterrizar en
/// Ventaja sin tocar nada más. Por eso se calcula en vez de fijarse.
Set<SetupStep> resueltosPorGrupo() => const {
      SetupStep.jugadores,
      SetupStep.compiten,
      SetupStep.bola,
      SetupStep.cuenta,
      // El paso Detalle muestra los módulos, y el grupo es justo lo que los
      // pone. Olvidarlo hacía aterrizar ahí en vez de en Ventaja.
      SetupStep.apuestas,
      SetupStep.participantes,
      SetupStep.montos,
    };

/// El primer paso que [resueltos] no cubre.
///
/// Precargar no es bloquear: se aterriza aquí, pero se puede retroceder a
/// cambiar cualquier cosa.
SetupStep primerPasoSinResolver(
    List<SetupStep> pasos, Set<SetupStep> resueltos) {
  for (final p in pasos) {
    if (!resueltos.contains(p)) return p;
  }
  // Todo resuelto: se va a revisar, que es donde se confirma.
  return pasos.last;
}

/// Lo que un punto de partida guardado deja sin responder.
///
/// Se CALCULA de lo que trae, no se fija. Hoy son Campo y Ventaja porque ningún
/// modelo los guarda; el día que uno guarde el campo, esta función devuelve solo
/// Ventaja y la pantalla de arranque se acorta sola.
///
/// Es la misma función que decidía el aterrizaje del wizard, usada para lo que
/// de verdad hacía falta: en vez de llevar al primer paso sin responder —que por
/// el orden es siempre Campo, o sea el paso 1— dice QUÉ preguntas quedan, para
/// preguntar solo esas.
///
/// Un punto de partida es un ATAJO, no un formulario prellenado. Prellenar
/// ahorra escribir pero se recorre igual; un atajo lleva al final y solo para
/// donde falta algo.
List<SetupStep> preguntasPendientes({
  required bool traeCampo,
  required bool traeVentaja,
}) =>
    [
      if (!traeCampo) SetupStep.campo,
      if (!traeVentaja) SetupStep.ventaja,
    ];

/// Frase corta de lo que falta, para la tarjeta.
///
/// Lo que permite decidir si tocar una tarjeta no es de qué TIPO es —"grupo de
/// apuesta" contra "plantilla de ronda" describe implementación— sino qué queda
/// por decidir. Y eso vuelve la distinción innecesaria en la etiqueta, porque
/// queda expresada en lo concreto.
String faltaPorDecidir(List<SetupStep> pendientes) {
  if (pendientes.isEmpty) return 'Todo listo';
  final nombres = pendientes.map((p) => switch (p) {
        SetupStep.campo => 'campo',
        SetupStep.ventaja => 'ventaja',
        _ => setupStepLabel(p).toLowerCase(),
      });
  if (pendientes.length == 1) return 'Solo falta la ${nombres.first}';
  return 'Falta elegir ${nombres.join(' y ')}';
}
