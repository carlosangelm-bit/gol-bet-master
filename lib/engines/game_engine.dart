// ─────────────────────────────────────────────────────────────────────────────
// GAME ENGINE
// Responsabilidad: calcular score neto, strokes por hoyo, ganador del hoyo
// NO calcula dinero. Solo contexto deportivo.
// ─────────────────────────────────────────────────────────────────────────────
import '../models/models.dart';

class HoleContext {
  final int hole;
  final String playerId;
  final int grossScore;
  final int netScore;
  final int strokesReceived;
  final int relativeToPar;    // neto vs par del hoyo
  final int stablefordPts;
  final int putts;

  const HoleContext({
    required this.hole, required this.playerId,
    required this.grossScore, required this.netScore,
    required this.strokesReceived, required this.relativeToPar,
    required this.stablefordPts, required this.putts,
  });

  bool get isEagleOrBetter => relativeToPar <= -2;
  bool get isBirdie  => relativeToPar == -1;
  bool get isPar     => relativeToPar == 0;
  bool get isBogey   => relativeToPar == 1;
  bool get isDouble  => relativeToPar == 2;

  String get scoreName {
    if (relativeToPar <= -3) return 'Albatross';
    if (relativeToPar == -2) return 'Eagle';
    if (relativeToPar == -1) return 'Birdie';
    if (relativeToPar ==  0) return 'Par';
    if (relativeToPar ==  1) return 'Bogey';
    if (relativeToPar ==  2) return 'Doble';
    return '+${relativeToPar}';
  }
}

class GameEngine {
  // ── strokes recibidos en un hoyo (handicap individual vs par) ───────────
  static int strokesReceived(double handicap, CourseHole ch) {
    if (handicap <= 0) return 0;
    final hcp = handicap.round();
    int s = hcp >= ch.strokeIndex ? 1 : 0;
    if (hcp > 18 && (hcp - 18) >= ch.strokeIndex) s++;
    return s;
  }

  // ── strokes que recibe el jugador de mayor HCP respecto al de menor HCP ──
  // Implementa la regla USGA/R&A de distribución:
  //   - diff = round(hcpAlto - hcpBajo)
  //   - La vuelta de inicio (startingNine) lleva el stroke extra cuando diff es impar.
  //   - Dentro de cada vuelta, los strokes se asignan a los hoyos con SI relativo más bajo.
  //
  // Retorna cuántos strokes recibe `higherHcpPlayer` en el hoyo `ch`.
  static int strokesReceivedVs({
    required double hcpHigher,
    required double hcpLower,
    required CourseHole ch,
    required List<CourseHole> allHoles,
    StartingNine startingNine = StartingNine.front,
  }) {
    final diff = (hcpHigher - hcpLower).round();
    if (diff <= 0) return 0;

    // Separar hoyos por vuelta y ordenar por SI relativo (1 = más difícil en esa vuelta)
    final front9 = allHoles.where((h) => h.hole <= 9).toList()
      ..sort((a, b) => a.strokeIndex.compareTo(b.strokeIndex));
    final back9  = allHoles.where((h) => h.hole > 9).toList()
      ..sort((a, b) => a.strokeIndex.compareTo(b.strokeIndex));

    // La vuelta de inicio lleva el stroke extra (ceil), la otra lleva floor
    final startIsfront = startingNine == StartingNine.front;
    final firstStrokes  = (diff / 2).ceil();   // vuelta de inicio: más strokes
    final secondStrokes = (diff / 2).floor();  // vuelta secundaria: menos strokes

    if (ch.hole <= 9) {
      final rank = front9.indexWhere((h) => h.hole == ch.hole) + 1;
      final limit = startIsfront ? firstStrokes : secondStrokes;
      return rank <= limit ? 1 : 0;
    } else {
      final rank = back9.indexWhere((h) => h.hole == ch.hole) + 1;
      final limit = startIsfront ? secondStrokes : firstStrokes;
      return rank <= limit ? 1 : 0;
    }
  }

  // ── contexto de un hoyo para un jugador ──────────────────────────────────
  static HoleContext? contextForHole(
    Round round, String playerId, int holeNum, bool useHandicap,
  ) {
    final score = round.getScore(playerId, holeNum);
    if (!score.hasScore) return null;
    final ch = round.course.holes.firstWhere((h) => h.hole == holeNum);
    final hcp = useHandicap ? round.getHandicap(playerId) : 0.0;
    final strokes = strokesReceived(hcp, ch);
    final net = score.grossScore! - strokes;
    final rel = net - ch.par;
    return HoleContext(
      hole: holeNum, playerId: playerId,
      grossScore: score.grossScore!, netScore: net,
      strokesReceived: strokes, relativeToPar: rel,
      stablefordPts: _stableford(rel), putts: score.putts,
    );
  }

  static int _stableford(int rel) {
    if (rel >= 2)  return 0;
    if (rel ==  1) return 1;
    if (rel ==  0) return 2;
    if (rel == -1) return 3;
    if (rel == -2) return 4;
    return 5;
  }

  // ── ganador único de un hoyo (neto) ──────────────────────────────────────
  static String? holeWinner(Round round, List<String> playerIds, int holeNum, bool useHandicap) {
    final ctxs = <HoleContext>[];
    for (final pid in playerIds) {
      final c = contextForHole(round, pid, holeNum, useHandicap);
      if (c != null) ctxs.add(c);
    }
    if (ctxs.length < playerIds.length) return null; // no todos tienen score
    ctxs.sort((a, b) => a.netScore.compareTo(b.netScore));
    if (ctxs[0].netScore == ctxs[1].netScore) return null; // empate
    return ctxs[0].playerId;
  }

  // ── ganador único de un hoyo (BRUTO) — para Skins gross ─────────────────
  static String? holeWinnerGross(Round round, List<String> playerIds, int holeNum) {
    final scores = <String, int>{};
    for (final pid in playerIds) {
      final s = round.getScore(pid, holeNum);
      if (s.hasScore) scores[pid] = s.grossScore!;
    }
    if (scores.length < playerIds.length) return null;
    final sorted = scores.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    if (sorted[0].value == sorted[1].value) return null;
    return sorted[0].key;
  }

  // ── score neto total de un jugador (18 hoyos) ────────────────────────────
  static int netTotal(Round round, String playerId, bool useHandicap, {int from = 1, int to = 18}) {
    int total = 0;
    for (int h = from; h <= to; h++) {
      final ctx = contextForHole(round, playerId, h, useHandicap);
      if (ctx != null) total += ctx.netScore;
    }
    return total;
  }

  // ── score bruto total ─────────────────────────────────────────────────────
  static int grossTotal(Round round, String playerId, {int from = 1, int to = 18}) {
    int total = 0;
    for (int h = from; h <= to; h++) {
      final s = round.getScore(playerId, h);
      if (s.hasScore) total += s.grossScore!;
    }
    return total;
  }

  // ── total de putts ────────────────────────────────────────────────────────
  static int totalPutts(Round round, String playerId, {int from = 1, int to = 18}) =>
      List.generate(to - from + 1, (i) => from + i)
        .map((h) => round.getScore(playerId, h).putts)
        .fold(0, (s, p) => s + p);

  // ── puntos stableford totales ─────────────────────────────────────────────
  static int stablefordTotal(Round round, String playerId, bool useHandicap, {int from = 1, int to = 18}) {
    int total = 0;
    for (int h = from; h <= to; h++) {
      final ctx = contextForHole(round, playerId, h, useHandicap);
      if (ctx != null) total += ctx.stablefordPts;
    }
    return total;
  }

  // ── match play status entre dos jugadores (p1 perspectiva) ───────────────
  // retorna: positivo = p1 up, 0 = all square, negativo = p1 down
  //
  // NOTA SOBRE manualHandicaps:
  // manual[p1][p2] ya ES la diferencia de strokes (no un ajuste al HCP).
  //   > 0 → p1 recibe esos strokes de p2  → p2=base, p1=receptor, diff=manual
  //   < 0 → p1 da esos strokes a p2       → p1=base, p2=receptor, diff=|manual|
  //   null → diferencia de HCPs normales
  static int matchPlayStatus(Round round, String p1Id, String p2Id, bool useHandicap, {int throughHole = 18}) {
    int status = 0;

    // Calcular base/receptor y diff UNA sola vez (no cambia por hoyo)
    final hcp1 = useHandicap ? round.getHandicap(p1Id) : 0.0;
    final hcp2 = useHandicap ? round.getHandicap(p2Id) : 0.0;
    final rp1 = round.roundPlayers.firstWhere(
      (r) => r.playerId == p1Id,
      orElse: () => RoundPlayer(playerId: p1Id, handicapEnRonda: hcp1),
    );
    final manual = useHandicap ? rp1.manualHandicaps[p2Id] : null;

    final bool p1IsBase;
    final double hcpBase;
    final double hcpReceiver;

    if (manual != null && manual != 0) {
      // El manual ya ES la diferencia de strokes:
      // manual > 0: p1 recibe → p2=base, p1=receptor, diff=manual
      // manual < 0: p1 da     → p1=base, p2=receptor, diff=|manual|
      if (manual > 0) {
        p1IsBase    = false;          // p2 es base
        hcpBase     = hcp2;
        hcpReceiver = hcp2 + manual;  // diff = manual
      } else {
        p1IsBase    = true;           // p1 es base
        hcpBase     = hcp1;
        hcpReceiver = hcp1 + (-manual); // diff = |manual|
      }
    } else {
      // Sin manual: diferencia de HCPs normales
      p1IsBase    = hcp1 <= hcp2;
      hcpBase     = p1IsBase ? hcp1 : hcp2;
      hcpReceiver = p1IsBase ? hcp2 : hcp1;
    }

    final allHoles = round.course.holes;

    for (int h = 1; h <= throughHole; h++) {
      final ch = round.course.holes.firstWhere((c) => c.hole == h);
      final s1 = round.getScore(p1Id, h);
      final s2 = round.getScore(p2Id, h);
      if (!s1.hasScore || !s2.hasScore) continue;

      final strokesHere = useHandicap
          ? strokesReceivedVs(
              hcpHigher: hcpReceiver,
              hcpLower:  hcpBase,
              ch: ch,
              allHoles: allHoles,
              startingNine: round.startingNine,
            )
          : 0;

      final grossBase     = round.getScore(p1IsBase ? p1Id : p2Id, h).grossScore!;
      final grossReceiver = round.getScore(p1IsBase ? p2Id : p1Id, h).grossScore!;
      final netReceiver   = grossReceiver - strokesHere;

      // Resultado en perspectiva p1
      if (p1IsBase) {
        if (grossBase < netReceiver)      status++;
        else if (grossBase > netReceiver) status--;
      } else {
        if (netReceiver < grossBase)      status++;
        else if (netReceiver > grossBase) status--;
      }
    }
    return status;
  }

  // ── todos los hoyos completados por todos los jugadores ───────────────────
  // Retorna el último hoyo jugado según el orden de la ronda (startingNine).
  // Si startingNine == back: el orden es 10‑18, 1‑9.
  static int lastCompletedHole(Round round, List<String> playerIds) {
    // Construir el orden de la ronda
    final order = round.startingNine == StartingNine.back
        ? [...List.generate(9, (i) => i + 10), ...List.generate(9, (i) => i + 1)]
        : List.generate(18, (i) => i + 1);
    // Recorrer en reversa para encontrar el último con score
    for (int i = order.length - 1; i >= 0; i--) {
      final h = order[i];
      if (playerIds.every((pid) => round.getScore(pid, h).hasScore)) return h;
    }
    return 0;
  }
}
