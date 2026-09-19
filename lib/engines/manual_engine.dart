// ─────────────────────────────────────────────────────────────────────────────
// APUESTAS MANUALES — lo que la app no entiende, contado a mano
//
//     «Crear una apuesta con el mecanismo que ya tienes —bote o todos vs todos,
//      monto, quiénes juegan—. Estoy pensando en grupos que apuestan cosas
//      raras que no vamos a meter a la app, como fairways, green en regulation,
//      y ese tipo de cosas.»
//
// Este motor es pequeño A PROPÓSITO. Todo lo que hace falta ya existía: la
// estructura, el importe por duelo, quién juega, el desglose, el balance. Lo
// único nuevo es de dónde sale el número — de lo que alguien marcó en vez de
// del score— y eso son las dos funciones de aquí abajo.
//
// Las dos formas de contar son las de Putts y las de Oyes:
//
//   · sí/no  → se cuentan los hoyos marcados y se paga por diferencia, igual
//              que los putts totales de un segmento.
//   · ranking→ se paga por diferencia de posición en cada hoyo, igual que un
//              oyés. La diferencia con Oyes es quién ordena: allí lo deduce el
//              score, aquí lo marca una persona.
//
// Por eso no hay un tercer modo para «gana quien menos tenga»: es el primero
// con el signo cambiado.
// ─────────────────────────────────────────────────────────────────────────────
import '../models/models.dart';
import 'ledger_engine.dart';

class ManualEngine {
  /// Los hoyos en los que [pid] está marcado en esta apuesta.
  static int marcas(Round round, BetModuleInstance mod, String pid) {
    final porHoyo = round.manuales[mod.id] ?? const {};
    var n = 0;
    for (final pids in porHoyo.values) {
      if (pids.contains(pid)) n++;
    }
    return n;
  }

  /// Los asientos de una apuesta manual entre [pids].
  static List<LedgerEntry> liquidar(
      Round round, List<String> pids, BetModuleInstance mod) {
    final cfg = mod.manual;
    return switch (cfg.modo) {
      ModoManual.siNo => _porConteo(round, pids, mod, invertido: false),
      ModoManual.siNoInvertido => _porConteo(round, pids, mod, invertido: true),
      ModoManual.ranking => _porPosicion(round, pids, mod),
    };
  }

  // ── Sí/no: se cuenta y se paga por diferencia ─────────────────────────────
  //
  // Un solo asiento por duelo, como Putts. Empate no paga: no es un cero mal
  // calculado, es que quedaron igual.
  static List<LedgerEntry> _porConteo(
      Round round, List<String> pids, BetModuleInstance mod,
      {required bool invertido}) {
    final entries = <LedgerEntry>[];
    final nombre = mod.manual.nombre;
    for (int i = 0; i < pids.length; i++) {
      for (int j = i + 1; j < pids.length; j++) {
        final a = pids[i], b = pids[j];
        final ma = marcas(round, mod, a), mb = marcas(round, mod, b);
        if (ma == mb) continue;
        // Con el signo cambiado gana quien menos tenga. Es lo que convierte
        // «fairways» en «penalizaciones» sin escribir otro motor.
        final ganaA = invertido ? ma < mb : ma > mb;
        entries.add(LedgerEntry(
          fromPlayerId: ganaA ? b : a,
          toPlayerId: ganaA ? a : b,
          amount: mod.effectiveValueForDuel(a, b).$1,
          betType: BetModuleType.manual,
          // El nombre del usuario en el motivo: es lo único que distingue dos
          // manuales en el desglose, que agrupa por TIPO.
          reason: '$nombre ($ma–$mb)',
        ));
      }
    }
    return entries;
  }

  // ── Ranking: se paga por diferencia de posición, hoyo a hoyo ──────────────
  //
  // Mismo reparto que un oyés: en un hoyo con tres marcados, el 1º cobra del 2º
  // y del 3º, y el 2º del 3º. Quien no esté marcado en ese hoyo no entra —no
  // jugó ese punto— en vez de contar como último, que sería inventarle una
  // posición que nadie puso.
  static List<LedgerEntry> _porPosicion(
      Round round, List<String> pids, BetModuleInstance mod) {
    final entries = <LedgerEntry>[];
    final nombre = mod.manual.nombre;
    final porHoyo = round.manuales[mod.id] ?? const {};
    final hoyos = porHoyo.keys.toList()..sort();

    for (final h in hoyos) {
      final orden = porHoyo[h]!.where(pids.contains).toList();
      if (orden.length < 2) continue;
      for (int i = 0; i < orden.length - 1; i++) {
        for (int j = i + 1; j < orden.length; j++) {
          entries.add(LedgerEntry(
            fromPlayerId: orden[j],
            toPlayerId: orden[i],
            amount: mod.effectiveValueForDuel(orden[i], orden[j]).$1,
            betType: BetModuleType.manual,
            reason: '$nombre H$h (${i + 1}° vs ${j + 1}°)',
          ));
        }
      }
    }
    return entries;
  }
}
