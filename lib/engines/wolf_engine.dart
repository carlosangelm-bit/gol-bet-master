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

  /// True si el hoyo se jugó en solitario contra los otros tres.
  final bool loneWolf;

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
  /// Rotación simple: hoyo N → índice (N-1) mod 4 del orden de salida. No se
  /// pregunta nunca.
  ///
  /// **Los hoyos 17 y 18 siguen la misma rotación.** Algunos grupos hacen que
  /// sea Wolf el que va perdiendo, y sin dato sobre cuál usa este grupo no se
  /// supone. El día que se quiera, es una rama AQUÍ y nada más: el diseño de
  /// captura no depende de la regla de rotación, así que añadirla es una opción
  /// más y no rehacer el formato.
  ///
  /// **Blind Wolf queda fuera de esta versión**: es variante sobre variante y no
  /// hay a quién preguntarle el detalle. Entraría como un campo del WolfCall
  /// —"declaró antes de ver los tiros"— sin tocar nada de esto.
  static String wolfDelHoyo(List<String> ordenDeSalida, int hoyo) =>
      ordenDeSalida[(hoyo - 1) % ordenDeSalida.length];

  /// Recorre los hoyos y resuelve cada enfrentamiento.
  ///
  /// [ordenDeSalida] es el orden fijado al crear la ronda: los participantIds
  /// del módulo, en su orden.
  static List<WolfHoyo> recorrido(
      Round round, List<String> ordenDeSalida, WolfConfig cfg) {
    final salida = <WolfHoyo>[];
    if (ordenDeSalida.length != 4) return salida;

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

      // El multiplicador SOLO premia al Lone Wolf que gana. El que pierde paga
      // sencillo a cada rival, que es lo estándar y por eso no es configurable.
      final importe =
          (lone && ganaWolf) ? cfg.value * cfg.loneMultiplier : cfg.value;

      salida.add(WolfHoyo(
        hoyo: h,
        wolf: wolf,
        companero: comp,
        loneWolf: lone,
        ganadores: ganaWolf ? ladoWolf : rivales,
        perdedores: ganaWolf ? rivales : ladoWolf,
        sinLiquidar: null,
        importe: importe,
      ));
    }

    return salida;
  }

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
