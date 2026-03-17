// ─────────────────────────────────────────────────────────────────────────────
// LEDGER ENGINE
// Responsabilidad: netear deudas y convertir a pagos entre pares de jugadores
// Es la ÚNICA fuente de verdad financiera del sistema.
// ─────────────────────────────────────────────────────────────────────────────
import '../models/models.dart';
import 'bet_engine.dart';

class LedgerEngine {
  /// Balance neto por jugador (positivo = gana, negativo = debe)
  static Map<String, double> playerBalances(Round round) {
    final entries = BetEngine.computeAll(round);
    final balances = <String, double>{for (final p in round.players) p.id: 0.0};
    for (final e in entries) {
      if (e.amount <= 0) continue;
      balances[e.fromPlayerId] = (balances[e.fromPlayerId] ?? 0) - e.amount;
      balances[e.toPlayerId]   = (balances[e.toPlayerId]   ?? 0) + e.amount;
    }
    return balances.map((k, v) => MapEntry(k, _r(v)));
  }

  /// Neteo simplificado: deudas mínimas entre pares
  static List<NetDebt> compute(Round round) {
    return _netEntries(BetEngine.computeAll(round), round.players);
  }

  static List<NetDebt> _netEntries(List<LedgerEntry> entries, List<Player> players) {
    final bal = <String, double>{for (final p in players) p.id: 0.0};
    for (final e in entries) {
      if (e.amount <= 0) continue;
      bal[e.fromPlayerId] = (bal[e.fromPlayerId] ?? 0) - e.amount;
      bal[e.toPlayerId]   = (bal[e.toPlayerId]   ?? 0) + e.amount;
    }

    // Greedy neteo
    final debtors   = bal.entries.where((e) => e.value < -0.005).map((e) => [e.key, -e.value]).toList()
      ..sort((a, b) => (b[1] as double).compareTo(a[1] as double));
    final creditors = bal.entries.where((e) => e.value > 0.005).map((e) => [e.key, e.value]).toList()
      ..sort((a, b) => (b[1] as double).compareTo(a[1] as double));

    final debts = <NetDebt>[];
    int di = 0, ci = 0;
    while (di < debtors.length && ci < creditors.length) {
      final pay = (debtors[di][1] as double) < (creditors[ci][1] as double)
          ? debtors[di][1] as double : creditors[ci][1] as double;
      if (pay > 0.005) {
        debts.add(NetDebt(fromPlayerId: debtors[di][0] as String, toPlayerId: creditors[ci][0] as String, amount: _r(pay)));
      }
      debtors[di][1]   = (debtors[di][1]   as double) - pay;
      creditors[ci][1] = (creditors[ci][1] as double) - pay;
      if ((debtors[di][1]   as double) < 0.005) di++;
      if ((creditors[ci][1] as double) < 0.005) ci++;
    }
    return debts;
  }

  /// Balance entre dos jugadores específicos (desde perspectiva de p1Id)
  static double balanceBetween(Round round, String p1Id, String p2Id) {
    final entries = BetEngine.computeAll(round);
    double balance = 0;
    for (final e in entries) {
      if (e.fromPlayerId == p1Id && e.toPlayerId == p2Id) balance -= e.amount;
      if (e.fromPlayerId == p2Id && e.toPlayerId == p1Id) balance += e.amount;
    }
    return _r(balance);
  }

  /// Entries de un jugador contra otro, agrupados por tipo
  static Map<BetModuleType, double> breakdownBetween(Round round, String p1Id, String p2Id) {
    final entries = BetEngine.computeAll(round);
    final result = <BetModuleType, double>{};
    for (final e in entries) {
      double delta = 0;
      if (e.fromPlayerId == p1Id && e.toPlayerId == p2Id) delta = -e.amount;
      if (e.fromPlayerId == p2Id && e.toPlayerId == p1Id) delta = e.amount;
      if (delta != 0) result[e.betType] = (result[e.betType] ?? 0) + delta;
    }
    return result.map((k, v) => MapEntry(k, _r(v)));
  }

  /// Todos los entries agrupados por tipo de apuesta (para la vista detalle)
  static Map<BetModuleType, List<LedgerEntry>> byBetType(Round round) {
    final entries = BetEngine.computeAll(round);
    final result = <BetModuleType, List<LedgerEntry>>{};
    for (final e in entries) {
      result[e.betType] = [...(result[e.betType] ?? []), e];
    }
    return result;
  }

  /// Balance acumulado hoyo a hoyo de un jugador (para curva de progreso)
  static Map<int, double> runningBalance(Round round, String playerId) {
    final entries = BetEngine.computeAll(round);
    final result = <int, double>{};
    double running = 0;
    for (int h = 1; h <= 18; h++) {
      for (final e in entries.where((e) => e.hole == h)) {
        if (e.fromPlayerId == playerId) running -= e.amount;
        if (e.toPlayerId   == playerId) running += e.amount;
      }
      result[h] = _r(running);
    }
    return result;
  }

  static double _r(double v) => (v * 100).round() / 100.0;
}
