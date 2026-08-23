// ─────────────────────────────────────────────────────────────────────────────
// STABLEFORD — gana quien más puntos acumule
//
// Motor aislado, y el más pequeño de todos: la aritmética YA EXISTÍA. GameEngine
// produce los puntos de cada hoyo desde siempre para pintar la tarjeta, así que
// esto no calcula nada nuevo, EXPONE lo que había como apuesta.
//
// Dos cosas que se comprobaron antes de escribirlo, porque el encargo las pedía:
//
//   · Los puntos usan el NETO, no el bruto. contextForHole resta los golpes
//     recibidos por stroke index antes de comparar con el par. Verificado con
//     test: un jugador con handicap saca más puntos que otro con el mismo bruto
//     y handicap cero.
//   · Y el interruptor bruto/neto del módulo hacía falta declararlo. El switch
//     de BetModuleInstance.useHandicap tiene `_ => false` por defecto, así que
//     sin su rama Stableford habría calculado bruto EN SILENCIO — con la
//     configuración diciendo "Net" en la tarjeta.
//
// El neto de Stableford es ABSOLUTO: sale del handicap propio del jugador, no
// del acuerdo bilateral de pairSliding que usan Medal, Skins y Nassau. Es lo
// correcto para este formato —es una competición individual de puntos, no un
// duelo— y por eso no hay ancla de grupo ni netVs: un número por jugador.
// ─────────────────────────────────────────────────────────────────────────────
import '../models/models.dart';
import 'game_engine.dart';

class StablefordEngine {
  /// Los puntos de [pid] en la ronda, con la tabla de [cfg].
  ///
  /// Se recorre hoyo a hoyo en vez de llamar a GameEngine.stablefordTotal
  /// porque la tabla es configurable y ese atajo usa la clásica. La resta de
  /// golpes sigue siendo la misma primitiva.
  static int puntosDe(Round round, String pid, StablefordConfig cfg,
      {required bool neto, int desde = 1, int hasta = 18}) {
    var total = 0;
    for (var h = desde; h <= hasta; h++) {
      final ctx = GameEngine.contextForHole(round, pid, h, neto);
      if (ctx == null) continue;
      total += GameEngine.stablefordPuntos(
        ctx.relativeToPar,
        puntosDelPar: cfg.puntosDelPar,
        piso: cfg.piso,
        techo: cfg.techo,
      );
    }
    return total;
  }

  /// Los puntos de cada jugador, para la tabla y para las notas.
  static Map<String, int> tabla(
      Round round, List<String> pids, BetModuleInstance mod) {
    final cfg = mod.stableford;
    return {
      for (final pid in pids)
        pid: puntosDe(round, pid, cfg, neto: mod.useHandicap),
    };
  }

  /// Los asientos.
  ///
  /// Misma estructura que Medal —el formato hermano— con dos diferencias: los
  /// puntos van al revés (más es mejor) y no hay ancla, porque los puntos son
  /// absolutos.
  ///
  ///   · onePot   → el de más puntos cobra [value] a cada uno de los demás.
  ///   · allVsAll → cada par es un duelo independiente por [value].
  ///
  /// Empate: nadie paga. Ni en el pot ni en un duelo suelto.
  static List<LedgerEntry> liquidar(
      Round round, List<String> pids, BetModuleInstance mod) {
    final entries = <LedgerEntry>[];
    if (pids.length < 2) return entries;
    final cfg = mod.stableford;
    final pts = tabla(round, pids, mod);

    // Sin ningún hoyo capturado no hay nada que liquidar. Si no se comprobara,
    // una ronda vacía daría un empate a cero... que ya no paga, pero dejarlo
    // dicho evita que un cambio futuro lo convierta en un pago.
    if (pts.values.every((v) => v == 0) &&
        pids.every((p) => round.course.holes
            .every((ch) => !round.getScore(p, ch.hole).hasScore))) {
      return entries;
    }

    if (mod.isAllVsAll) {
      for (var i = 0; i < pids.length; i++) {
        for (var j = i + 1; j < pids.length; j++) {
          final a = pids[i], b = pids[j];
          final pa = pts[a]!, pb = pts[b]!;
          if (pa == pb) continue;
          final gana = pa > pb ? a : b;
          final pierde = pa > pb ? b : a;
          entries.add(LedgerEntry(
            fromPlayerId: pierde,
            toPlayerId: gana,
            amount: cfg.value,
            betType: BetModuleType.stableford,
            reason: 'Stableford ${pts[gana]}-${pts[pierde]}',
          ));
        }
      }
      return entries;
    }

    // onePot: un solo ganador. Más puntos es mejor, así que se ordena al revés
    // que Medal.
    final orden = pids.toList()..sort((a, b) => pts[b]!.compareTo(pts[a]!));
    if (pts[orden[0]] == pts[orden[1]]) return entries; // empate arriba
    final ganador = orden.first;
    for (final pid in orden.skip(1)) {
      entries.add(LedgerEntry(
        fromPlayerId: pid,
        toPlayerId: ganador,
        amount: cfg.value,
        betType: BetModuleType.stableford,
        reason: 'Stableford ${pts[ganador]} pts',
      ));
    }
    return entries;
  }
}
