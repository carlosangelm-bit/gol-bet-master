// ─────────────────────────────────────────────────────────────────────────────
// HANDICAP SERVICE — World Handicap System (WHS) 2024
// Calcula Score Differential, Handicap Index y Course Handicap
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:math';
import '../models/models.dart';

// ── Modelo de diferencial de score por ronda ──────────────────────────────────
class ScoreDifferential {
  final String roundId;
  final String roundName;
  final DateTime playedAt;
  final double differential;
  final int grossScore;
  final int adjustedGrossScore; // RBA
  final double courseRating;
  final int slopeRating;
  final int parTotal;
  final int holesPlayed; // 9 o 18
  final String courseName;

  const ScoreDifferential({
    required this.roundId,
    required this.roundName,
    required this.playedAt,
    required this.differential,
    required this.grossScore,
    required this.adjustedGrossScore,
    required this.courseRating,
    required this.slopeRating,
    required this.parTotal,
    required this.holesPlayed,
    required this.courseName,
  });

  Map<String, dynamic> toJson() => {
    'roundId': roundId,
    'roundName': roundName,
    'playedAt': playedAt.toIso8601String(),
    'differential': differential,
    'grossScore': grossScore,
    'adjustedGrossScore': adjustedGrossScore,
    'courseRating': courseRating,
    'slopeRating': slopeRating,
    'parTotal': parTotal,
    'holesPlayed': holesPlayed,
    'courseName': courseName,
  };

  factory ScoreDifferential.fromJson(Map<String, dynamic> j) => ScoreDifferential(
    roundId:             (j['roundId']    as String?) ?? '',
    roundName:           (j['roundName']  as String?) ?? 'Ronda',
    playedAt:            DateTime.tryParse(j['playedAt'] as String? ?? '') ?? DateTime.now(),
    differential:        (j['differential'] as num?)?.toDouble() ?? 0.0,
    grossScore:          (j['grossScore'] as num?)?.toInt() ?? 0,
    adjustedGrossScore:  (j['adjustedGrossScore'] as num?)?.toInt() ?? 0,
    courseRating:        (j['courseRating'] as num?)?.toDouble() ?? 72.0,
    slopeRating:         (j['slopeRating'] as num?)?.toInt() ?? 113,
    parTotal:            (j['parTotal']   as num?)?.toInt() ?? 72,
    holesPlayed:         (j['holesPlayed'] as num?)?.toInt() ?? 18,
    courseName:          (j['courseName'] as String?) ?? '',
  );
}

// ── Resultado del cálculo del Handicap Index ──────────────────────────────────
class HandicapIndexResult {
  /// Handicap Index calculado (null si hay < 3 rondas)
  final double? index;
  /// Número de rondas disponibles
  final int totalRounds;
  /// Diferenciales usados para el cálculo (los N mejores)
  final List<ScoreDifferential> usedDifferentials;
  /// Todos los diferenciales (últimas 20)
  final List<ScoreDifferential> allDifferentials;
  /// Ajuste de reducción aplicado por ESR (0 si no aplica)
  final double esrAdjustment;
  /// Ajuste por pocas rondas (tabla WHS)
  final double tableAdjustment;

  const HandicapIndexResult({
    this.index,
    required this.totalRounds,
    required this.usedDifferentials,
    required this.allDifferentials,
    this.esrAdjustment = 0.0,
    this.tableAdjustment = 0.0,
  });

  bool get hasIndex => index != null;
  String get displayIndex => index == null ? '—' : index!.toStringAsFixed(1);
}

// ── Servicio principal de handicap WHS ────────────────────────────────────────
class HandicapService {
  // Constante de referencia WHS
  static const double _refSlope = 113.0;
  static const double _maxHI = 54.0;

  /// Calcula el Adjusted Gross Score (RBA) aplicando Net Double Bogey por hoyo.
  /// Para cada hoyo: max = par + 2 + strokes_de_handicap_en_ese_hoyo
  /// [grossScores]: mapa hole# → gross score (sólo hoyos jugados)
  /// [courseHoles]: información de cada hoyo (par, strokeIndex)
  /// [playingHandicap]: handicap de juego del jugador (entero)
  /// [playedHoles]: lista de hoyos jugados (para rondas de 9)
  static int calculateRBA({
    required Map<int, int?> grossScores,
    required List<CourseHole> courseHoles,
    required int playingHandicap,
    List<int>? playedHoles,
  }) {
    final holesInPlay = playedHoles ?? courseHoles.map((h) => h.hole).toList();
    int rba = 0;
    for (final holeNum in holesInPlay) {
      final gross = grossScores[holeNum];
      if (gross == null || gross == 0) continue;
      final holeInfo = courseHoles.firstWhere(
        (h) => h.hole == holeNum,
        orElse: () => CourseHole(hole: holeNum, par: 4, strokeIndex: 18),
      );
      // Strokes de handicap en este hoyo
      final strokesOnHole = _strokesOnHole(holeInfo.strokeIndex, playingHandicap);
      // Net Double Bogey = par + 2 + strokes
      final maxScore = holeInfo.par + 2 + strokesOnHole;
      rba += min(gross, maxScore);
    }
    return rba;
  }

  /// Calcula cuántos strokes de ventaja aplican en un hoyo dado el strokeIndex
  static int _strokesOnHole(int strokeIndex, int playingHandicap) {
    if (playingHandicap <= 0) return 0;
    // Rondas de 18 hoyos: si el handicap es mayor que 18, se da 2 en algunos hoyos
    if (strokeIndex <= (playingHandicap % 18 == 0 ? 18 : playingHandicap % 18)) {
      return (playingHandicap ~/ 18) + 1;
    }
    return playingHandicap ~/ 18;
  }

  /// Calcula el Score Differential para una ronda.
  /// Fórmula WHS: (113 / Slope) × (RBA − CR − PCC)
  /// Para rondas de 9 hoyos se aplica un ajuste especial.
  ///
  /// [pcc]: Playing Conditions Calculation (generalmente 0 si no se mide)
  static double calculateScoreDifferential({
    required int rba,
    required double courseRating,
    required int slopeRating,
    required int holesPlayed,
    double pcc = 0.0,
  }) {
    double cr = courseRating;
    double slope = slopeRating.toDouble();
    if (slope <= 0) slope = _refSlope;

    // Para rondas de 9 hoyos: se dobla el diferencial (estándar WHS)
    // En la práctica se usan dos rondas de 9 para calcular 1 diferencial de 18
    // Aquí calculamos el diferencial proporcional
    double diff = (_refSlope / slope) * (rba - cr - pcc);

    // Redondear a 1 decimal
    return double.parse(diff.toStringAsFixed(1));
  }

  /// Calcula el Score Differential directamente desde la ronda.
  /// Retorna null si el jugador no tiene scores válidos.
  static ScoreDifferential? calculateFromRound({
    required Round round,
    required String playerId,
  }) {
    final rp = round.roundPlayers.firstWhere(
      (r) => r.playerId == playerId,
      orElse: () => RoundPlayer(playerId: playerId, handicapEnRonda: 0),
    );
    final tee = rp.tee;
    final playerScores = round.scores[playerId] ?? {};

    // Hoyos jugados según startingNine y totalHoles
    final playedHoles = _getPlayedHoles(round);

    // Verificar que haya al menos la mitad de los hoyos con score
    final scoredHoles = playedHoles.where((h) => (playerScores[h]?.grossScore ?? 0) > 0).length;
    if (scoredHoles < (playedHoles.length / 2).ceil()) return null;

    // Gross score total
    final grossScore = playedHoles.fold<int>(0, (sum, h) {
      final s = playerScores[h]?.grossScore ?? 0;
      return sum + s;
    });
    if (grossScore == 0) return null;

    // Playing Handicap para este tee
    final playingHandicap = tee.playingHandicap(rp.handicapEnRonda).round();

    // RBA (Adjusted Gross Score — Net Double Bogey)
    final grossMap = playerScores.map((h, s) => MapEntry(h, s.grossScore));
    final rba = calculateRBA(
      grossScores: grossMap,
      courseHoles: round.course.holes,
      playingHandicap: playingHandicap,
      playedHoles: playedHoles,
    );

    // Course Rating y Slope para los hoyos jugados
    // Para 9 hoyos usamos la mitad del CR/par proporcional
    double cr = tee.courseRating;
    int slope = tee.slopeRating;
    int par = tee.parTotal;

    if (round.totalHoles == 9) {
      // Ajuste proporcional para 9 hoyos (WHS recomienda usar datos separados de 9 hoyos)
      // Aproximación: mitad del CR y par
      cr = cr / 2.0;
      par = par ~/ 2;
    }

    final diff = calculateScoreDifferential(
      rba: rba,
      courseRating: cr,
      slopeRating: slope,
      holesPlayed: playedHoles.length,
    );

    return ScoreDifferential(
      roundId: round.id,
      roundName: round.name,
      playedAt: round.createdAt,
      differential: diff,
      grossScore: grossScore,
      adjustedGrossScore: rba,
      courseRating: cr,
      slopeRating: slope,
      parTotal: par,
      holesPlayed: playedHoles.length,
      courseName: round.course.name,
    );
  }

  /// Obtiene la lista de hoyos efectivamente jugados según la configuración de la ronda
  static List<int> _getPlayedHoles(Round round) {
    final allHoles = round.course.holes.map((h) => h.hole).toSet();
    if (round.totalHoles == 18) return round.course.holes.map((h) => h.hole).toList();

    // Ronda de 9 hoyos según startingNine
    if (round.startingNine == StartingNine.front) {
      return allHoles.where((h) => h <= 9).toList()..sort();
    } else {
      final back = allHoles.where((h) => h > 9).toList()..sort();
      if (back.isEmpty) return allHoles.take(9).toList()..sort();
      return back;
    }
  }

  // ── Tabla WHS: número de diferenciales a usar y ajuste ───────────────────────
  static _WHS _whsTableEntry(int rounds) {
    if (rounds < 3)  return _WHS(count: 0, adj: 0);
    if (rounds == 3) return _WHS(count: 1, adj: -2.0);
    if (rounds == 4) return _WHS(count: 1, adj: -1.0);
    if (rounds == 5) return _WHS(count: 1, adj: 0.0);
    if (rounds == 6) return _WHS(count: 2, adj: -1.0);
    if (rounds <= 8) return _WHS(count: 2, adj: 0.0);
    if (rounds <= 11) return _WHS(count: 3, adj: 0.0);
    if (rounds <= 14) return _WHS(count: 4, adj: 0.0);
    if (rounds <= 16) return _WHS(count: 5, adj: 0.0);
    if (rounds <= 18) return _WHS(count: 6, adj: 0.0);
    if (rounds == 19) return _WHS(count: 7, adj: 0.0);
    return _WHS(count: 8, adj: 0.0); // 20+
  }

  /// Calcula el Handicap Index a partir de una lista de ScoreDifferentials.
  /// Usa las últimas 20 rondas (o menos si no hay suficientes).
  static HandicapIndexResult calculateIndex(List<ScoreDifferential> allDiffs) {
    if (allDiffs.isEmpty) {
      return HandicapIndexResult(
        totalRounds: 0,
        usedDifferentials: [],
        allDifferentials: [],
      );
    }

    // Ordenar por fecha descendente y tomar las últimas 20
    final sorted = [...allDiffs]
      ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    final last20 = sorted.take(20).toList();

    final n = last20.length;
    final entry = _whsTableEntry(n);

    if (entry.count == 0) {
      return HandicapIndexResult(
        totalRounds: n,
        usedDifferentials: [],
        allDifferentials: last20,
        tableAdjustment: entry.adj,
      );
    }

    // Ordenar por diferencial ascendente para tomar los mejores (más bajos)
    final byDiff = [...last20]..sort((a, b) => a.differential.compareTo(b.differential));
    final used = byDiff.take(entry.count).toList();

    // Promedio de los mejores N
    final avg = used.fold<double>(0, (s, d) => s + d.differential) / entry.count;

    // Aplicar ajuste de tabla y truncar a 1 decimal (WHS trunca, no redondea)
    double hi = avg + entry.adj;

    // ESR: Exceptional Score Reduction
    double esrAdj = 0.0;
    if (hi > 0) {
      for (final d in used) {
        final diff = hi - d.differential;
        if (diff >= 10.0) {
          esrAdj = max(esrAdj, -2.0);
        } else if (diff >= 7.0) {
          esrAdj = max(esrAdj, -1.0);
        }
      }
    }
    hi += esrAdj;

    // Límite máximo
    hi = min(hi, _maxHI);
    // No puede ser negativo
    if (hi < 0) hi = 0;

    // Truncar a 1 decimal (WHS trunca, no redondea)
    hi = (hi * 10).truncateToDouble() / 10;

    return HandicapIndexResult(
      index: hi,
      totalRounds: n,
      usedDifferentials: used,
      allDifferentials: last20,
      esrAdjustment: esrAdj,
      tableAdjustment: entry.adj,
    );
  }

  /// Calcula el Course Handicap a partir del Handicap Index.
  /// Fórmula 2024: CH = (HI × Slope / 113) + (CR − Par)
  static int courseHandicap({
    required double handicapIndex,
    required int slopeRating,
    required double courseRating,
    required int parTotal,
  }) {
    final ch = (handicapIndex * slopeRating / _refSlope) + (courseRating - parTotal);
    return ch.round();
  }

  /// Calcula el Playing Handicap (Course Handicap × Allowance)
  /// Allowance por defecto: 100% (stroke play individual)
  static int playingHandicap({
    required double handicapIndex,
    required int slopeRating,
    required double courseRating,
    required int parTotal,
    double allowancePct = 1.0,
  }) {
    final ch = courseHandicap(
      handicapIndex: handicapIndex,
      slopeRating: slopeRating,
      courseRating: courseRating,
      parTotal: parTotal,
    );
    return (ch * allowancePct).round();
  }

  /// Texto de descripción del nivel de handicap
  static String handicapLevelLabel(double hi) {
    if (hi <= 5)  return 'Scratch / Low';
    if (hi <= 12) return 'Medio-Bajo';
    if (hi <= 20) return 'Intermedio';
    if (hi <= 28) return 'Medio-Alto';
    return 'Alto';
  }
}

// ── Clase auxiliar para la tabla WHS ─────────────────────────────────────────
class _WHS {
  final int count;
  final double adj;
  const _WHS({required this.count, required this.adj});
}
