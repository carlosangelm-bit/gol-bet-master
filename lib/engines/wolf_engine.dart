// ─────────────────────────────────────────────────────────────────────────────
// WOLF — cada hoyo un jugador elige compañero, o va solo por el doble
//
// LO QUE NO SE CONSTRUYE, y es la decisión que hace este formato baratísimo:
// nadie necesita ver en la app quién es el Wolf durante el hoyo. Eso se sabe en
// el tee. Lo que hace falta es registrar el resultado.
//
// Así que fuera la máquina de decisión secuencial, fuera el bloqueo de opciones
// tras cada tiro, fuera la captura en tiempo real. Todo eso es lo que hace que
// Wolf PAREZCA caro, y no es necesario.
//
// Queda: el Wolf se DERIVA del orden de salida —hoyo N → (N-1) mod 4— y una sola
// pregunta al anotar el score: con quién jugó.
//
// LO ÚNICO QUE ES CÁLCULO NUEVO: los lados cambian cada hoyo. BetSide es de la
// ronda, así que Wolf no puede usar los ejes de composición existentes. De ahí
// este motor, que arma el enfrentamiento hoyo a hoyo desde el WolfCall.
//
// Sobre la configuración: Carlos no juega Wolf, conoce grupos que sí. Así que lo
// que no se sabe va configurable con el estándar por defecto, en vez de
// decidirse a ciegas. Y el diseño de captura NO depende de ninguna de esas
// opciones —una pregunta por hoyo funciona igual con cualquier regla de rotación
// o multiplicador—, así que añadir una variante después es una opción más, no
// rehacer nada. Ver [wolfDelHoyo], donde se decide la rotación.
// ─────────────────────────────────────────────────────────────────────────────
import '../models/models.dart';
import 'game_engine.dart';

/// Por qué un hoyo de Wolf no liquidó.
enum WolfSinLiquidar {
  /// Nadie eligió compañero. NO se inventa uno: el hoyo queda como uno sin
  /// score y se dice.
  sinEleccion,

  /// Falta el score de alguien.
  sinScore,

  /// El enfrentamiento quedó empatado en el hoyo.
  empatado,
}

/// El resultado de un hoyo de Wolf.
class WolfHoyo {
  final int hoyo;

  /// Quién era el Wolf. Se deriva, nunca se pregunta.
  final String wolf;

  /// El compañero elegido, o null si fue solo.
  final String? companero;

  /// True si el hoyo se jugó en solitario contra todos los demás.
  final bool loneWolf;

  /// True si ganó el lado en MINORÍA y por eso el importe va doblado.
  ///
  /// Se guarda para poder decirlo: un importe al doble sin motivo visible en el
  /// asiento se lee como un error de cálculo.
  final bool bonusMinoria;

  /// Quién ganó el hoyo: los ids del lado ganador. Vacío si no liquidó.
  final List<String> ganadores;

  /// Los del lado perdedor. Vacío si no liquidó.
  final List<String> perdedores;

  /// Null si el hoyo liquidó.
  final WolfSinLiquidar? sinLiquidar;

  /// Lo que cada perdedor paga a cada ganador en este hoyo.
  final double importe;

  const WolfHoyo({
    required this.hoyo,
    required this.wolf,
    required this.companero,
    required this.loneWolf,
    this.bonusMinoria = false,
    required this.ganadores,
    required this.perdedores,
    required this.sinLiquidar,
    required this.importe,
  });

  bool get liquido => sinLiquidar == null;
}

class WolfEngine {
  /// Quién es el Wolf en [hoyo].
  ///
  /// Rotación simple sobre el orden de salida, y GENÉRICA en el número de
  /// jugadores: con cuatro el ciclo cierra cada cuatro hoyos y con cinco cada
  /// cinco, sin tocar nada. El `mod 4` que decía el comentario original estaba
  /// solo en el comentario. Eso es lo que valida haber DERIVADO el Wolf en vez
  /// de preguntarlo: el diseño de captura aguantó un cambio de reglas sin
  /// enterarse.
  ///
  /// **El ajuste de los últimos hoyos sigue fuera.** Algunos grupos hacen que
  /// sea Wolf el que va perdiendo, y ese ajuste arranca en el **hoyo 17 con
  /// cuatro jugadores y en el 16 con cinco** —el último ciclo completo—. Sin
  /// dato sobre cuál usa cada grupo no se supone; el día que se quiera, los dos
  /// números están aquí y es una rama en esta función y nada más.
  ///
  /// ── Variantes documentadas y NO construidas ──────────────────────────────
  ///
  /// Todas por el mismo motivo: Carlos no juega Wolf y no tiene a quién
  /// preguntarle el detalle. Un interruptor con el nombre de una variante real y
  /// una regla inventada detrás es peor que no ofrecerla.
  ///
  ///   · **Blind Wolf** — declararse antes de ver los tiros. Entraría como un
  ///     campo del WolfCall sin tocar el reparto.
  ///   · **Howling Wolf** — declararse ciego antes de CUALQUIER tiro,
  ///     triplicando. Variante sobre variante.
  ///   · **Carryover** — qué pasa con el hoyo que nadie gana. Hoy no paga nadie;
  ///     acumularlo exige decidir a qué hoyo y con qué tope.
  ///   · **Dump** — el compañero elegido rechaza y deja al Wolf solo. Ver la
  ///     nota en [WolfCall]: el ESTADO es trivial, el reparto no.
  static String wolfDelHoyo(List<String> ordenDeSalida, int hoyo) =>
      ordenDeSalida[(hoyo - 1) % ordenDeSalida.length];

  /// Recorre los hoyos y resuelve cada enfrentamiento.
  ///
  /// [ordenDeSalida] es el orden fijado al crear la ronda: los participantIds
  /// del módulo, en su orden.
  static List<WolfHoyo> recorrido(
      Round round, List<String> ordenDeSalida, WolfConfig cfg) {
    final salida = <WolfHoyo>[];
    // El tamaño admitido se pregunta a la tabla, no se fija aquí: con 4 y con 5
    // el formato es el mismo y lo único que cambia es el reparto cuando los
    // lados quedan desiguales.
    if (BetModuleType.wolf.motivoNoDisponible(ordenDeSalida.length) != null) {
      return salida;
    }

    for (final ch in round.course.holes) {
      final h = ch.hole;
      final wolf = wolfDelHoyo(ordenDeSalida, h);
      final call = round.getWolfCall(h);

      WolfHoyo sin(WolfSinLiquidar motivo, {String? comp, bool lone = false}) =>
          WolfHoyo(
              hoyo: h, wolf: wolf, companero: comp, loneWolf: lone,
              ganadores: const [], perdedores: const [],
              sinLiquidar: motivo, importe: 0);

      if (call == null) {
        salida.add(sin(WolfSinLiquidar.sinEleccion));
        continue;
      }

      // Un compañero que no está en la partida, o el Wolf eligiéndose a sí
      // mismo, no describe un enfrentamiento. Se trata como sin elegir en vez
      // de armar un lado inválido.
      final comp = call.partnerId;
      final compValido =
          comp != null && comp != wolf && ordenDeSalida.contains(comp);
      if (comp != null && !compValido) {
        salida.add(sin(WolfSinLiquidar.sinEleccion));
        continue;
      }

      final lone = comp == null;
      final ladoWolf = lone ? [wolf] : [wolf, comp];
      final rivales = ordenDeSalida.where((p) => !ladoWolf.contains(p)).toList();

      if (ordenDeSalida.any((p) => !round.getScore(p, h).hasScore)) {
        salida.add(sin(WolfSinLiquidar.sinScore, comp: comp, lone: lone));
        continue;
      }

      // Mejor bola NETA de cada lado. Se usa contextForHole, que es la misma
      // primitiva de la que sale el neto en todos los demás motores: una
      // segunda fórmula aquí podría discrepar de la que cobra Skins.
      final netoWolf = _mejorNeto(round, ladoWolf, h);
      final netoRival = _mejorNeto(round, rivales, h);
      if (netoWolf == null || netoRival == null) {
        salida.add(sin(WolfSinLiquidar.sinScore, comp: comp, lone: lone));
        continue;
      }

      if (netoWolf == netoRival) {
        salida.add(sin(WolfSinLiquidar.empatado, comp: comp, lone: lone));
        continue;
      }

      final ganaWolf = netoWolf < netoRival;

      final importe = _importeDelHoyo(
        cfg: cfg,
        gano: ganaWolf,
        lone: lone,
        tamanoWolf: ladoWolf.length,
        tamanoRival: rivales.length,
      );

      salida.add(WolfHoyo(
        hoyo: h,
        wolf: wolf,
        companero: comp,
        loneWolf: lone,
        bonusMinoria:
            ganaWolf && !lone && ladoWolf.length < rivales.length,
        ganadores: ganaWolf ? ladoWolf : rivales,
        perdedores: ganaWolf ? rivales : ladoWolf,
        sinLiquidar: null,
        importe: importe,
      ));
    }

    return salida;
  }

  /// Cuánto paga cada perdedor a cada ganador en un hoyo.
  ///
  /// ── La regla, formulada por ASIMETRÍA y no por número de jugadores ────────
  ///
  /// Con cuatro, el Wolf y su compañero son 2 contra 2: equilibrado, sin bonus.
  /// Con cinco son 2 contra 3, y el lado del Wolf está en minoría; si gana, los
  /// puntos se duplican para compensar la dificultad.
  ///
  /// Se podría haber escrito `if (jugadores == 5)`. No se hizo, y el motivo es
  /// que la regla REAL no habla del número de jugadores sino de la desigualdad
  /// de los lados: **el lado más pequeño que gana, cobra doble**. Formulado así
  /// vale para cualquier tamaño —si algún día entra un caso de seis, no hay que
  /// volver aquí— y además hace evidente por qué con cuatro no se aplica: no hay
  /// lado pequeño.
  ///
  /// El Lone Wolf NO acumula las dos cosas. Ir solo ya es el caso extremo de
  /// minoría, y tiene su propio multiplicador configurable porque es una
  /// DECISIÓN del jugador, no una consecuencia del reparto de la partida.
  /// Sumarle el doble de la minoría sería cobrar dos veces por lo mismo.
  ///
  /// Y perder no lleva bonus en ningún caso: el lado pequeño que pierde paga
  /// sencillo. Es lo estándar y es lo que ya hacía el Lone Wolf.
  static double _importeDelHoyo({
    required WolfConfig cfg,
    required bool gano,
    required bool lone,
    required int tamanoWolf,
    required int tamanoRival,
  }) {
    if (!gano) return cfg.value;
    if (lone) return cfg.value * cfg.loneMultiplier;
    return tamanoWolf < tamanoRival
        ? cfg.value * factorMinoria
        : cfg.value;
  }

  /// Lo que cobra de más el lado pequeño que gana.
  ///
  /// Constante y no configurable a propósito: "si el equipo de 2 gana, los
  /// puntos se duplican" es LA regla del formato con cinco, no una variante de
  /// casa. Un control por cada regla convierte la hoja de configuración en un
  /// formulario y deja de leerse — y nadie ha pedido otro valor.
  static const factorMinoria = 2.0;

  static int? _mejorNeto(Round round, List<String> pids, int hoyo) {
    int? mejor;
    for (final pid in pids) {
      final ctx = GameEngine.contextForHole(round, pid, hoyo, true);
      if (ctx == null) continue;
      if (mejor == null || ctx.netScore < mejor) mejor = ctx.netScore;
    }
    return mejor;
  }

  /// Los asientos de Wolf.
  ///
  /// Cada perdedor paga a cada ganador. Es la convención que ya usa el reparto
  /// de importes de equipo: el enfrentamiento se resuelve entre lados y el
  /// dinero se mueve por CRUCES, así que los asientos nombran personas reales y
  /// el ajuste de ventajas los sabe leer.
  static List<LedgerEntry> liquidar(
      Round round, List<String> pids, BetModuleInstance mod) {
    final cfg = mod.wolf;
    final entries = <LedgerEntry>[];

    for (final hoyo in recorrido(round, pids, cfg)) {
      if (!hoyo.liquido || hoyo.importe <= 0) continue;
      final motivo = hoyo.loneWolf
          ? 'Wolf H${hoyo.hoyo} · solo'
          : hoyo.bonusMinoria
              ? 'Wolf H${hoyo.hoyo} · en minoría ×'
                  '${factorMinoria.toStringAsFixed(0)}'
              : 'Wolf H${hoyo.hoyo}';
      for (final perdedor in hoyo.perdedores) {
        for (final ganador in hoyo.ganadores) {
          entries.add(LedgerEntry(
            fromPlayerId: perdedor,
            toPlayerId: ganador,
            amount: hoyo.importe,
            betType: BetModuleType.wolf,
            reason: motivo,
          ));
        }
      }
    }

    return entries;
  }
}
