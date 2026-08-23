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
    return '+$relativeToPar';
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

  // ── Strokes recibidos en un hoyo cuando la ventaja se aplica SOLO sobre
  //    los hoyos jugados (no dividida entre F9 y B9). ───────────────────────
  //
  // Usar para manualHandicaps (sliding): si se acordaron 9 strokes y se juega
  // solo B9, los 9 strokes se reparten entre los 9 hoyos jugados, no entre 18.
  // Los primeros [diff] hoyos por SI reciben 1 stroke; el resto, 0.
  // Si diff ≥ nHoles, todos los hoyos reciben 1 stroke (puede recibir 2 si
  // diff ≥ 2*nHoles, pero eso sería un caso extremo).
  //
  // [playedHoles]: lista de hoyos CON score del jugador receptor, ordenada por SI.
  static int strokesReceivedInPlayedHoles({
    required int diff,
    required CourseHole ch,
    required List<CourseHole> playedHoles,
  }) {
    if (diff <= 0) return 0;
    // Ordenar los hoyos jugados por SI (menor SI = más difícil = primer stroke)
    final sorted = [...playedHoles]..sort((a, b) => a.strokeIndex.compareTo(b.strokeIndex));
    final n = sorted.length;
    if (n == 0) return 0;
    // Strokes completos: 1 por cada "vuelta completa" de los hoyos jugados
    final fullRounds = diff ~/ n;   // cuántas veces se recorre completa la lista
    final remainder  = diff % n;    // hoyos que reciben un stroke extra
    final rank = sorted.indexWhere((h) => h.hole == ch.hole) + 1; // 1-based
    if (rank <= 0) return 0; // hoyo no encontrado
    return fullRounds + (rank <= remainder ? 1 : 0);
  }

  // ── Share de strokes para una de las dos vueltas (F9/B9) ─────────────────
  //
  // El pairSliding es SIEMPRE un valor oficial de 18 hoyos.
  // Al repartir entre las dos vueltas, la vuelta de inicio (startingNine)
  // recibe ceil(diff18/2) y la vuelta secundaria recibe floor(diff18/2).
  //
  // [diff18]            : valor oficial de 18 hoyos (positivo).
  // [startingNine]      : la vuelta que se juega primero en la ronda.
  // [targetIsStartingNine]: true si la vuelta objetivo ES la de inicio.
  //
  // Retorna el share correcto para la vuelta objetivo.
  static int slidingShareForNine({
    required int diff18,
    required StartingNine startingNine,
    required bool targetIsStartingNine,
  }) {
    if (diff18 <= 0) return 0;
    // La vuelta de inicio lleva ceil (el stroke "extra" del impar).
    // La vuelta secundaria lleva floor.
    return targetIsStartingNine ? (diff18 / 2).ceil() : (diff18 / 2).floor();
  }

  // ── Strokes que recibe el receptor en un hoyo usando el pairSliding oficial
  //    de 18 hoyos, respetando la segmentación F9/B9. ─────────────────────────
  //
  // REGLA CENTRAL:
  //   1. Identifica a qué vuelta pertenece [ch] (F9: hoyo≤9, B9: hoyo>9).
  //   2. Calcula el share de esa vuelta usando [slidingShareForNine].
  //   3. Distribuye ese share entre TODOS los hoyos del curso en esa vuelta (por SI).
  //      La distribución se basa en el orden de SI de los 9 hoyos completos,
  //      independientemente de cuántos se hayan jugado ya.
  //
  // IMPORTANTE: courseHolesInSameNine son los hoyos DEL CURSO (no solo jugados).
  // Usar todos los hoyos de la vuelta garantiza que los strokes se distribuyen
  // correctamente aunque la ronda esté en progreso (ej: solo H1-H3 de F9 jugados).
  //
  // Esto es correcto para:
  //   • Ronda completa de 18 hoyos: F9 recibe ceil, B9 recibe floor (o viceversa).
  //   • Ronda de solo 9 hoyos: solo se usa el share de la vuelta jugada.
  //   • Ronda en progreso: los strokes se distribuyen sobre los 9 hoyos del curso,
  //     no concentrados en los pocos hoyos ya jugados.
  //
  // [diff18]               : valor oficial de 18 hoyos (positivo).
  // [ch]                   : hoyo objetivo (donde se consulta el stroke).
  // [courseHolesInSameNine]: TODOS los hoyos del CURSO en la MISMA vuelta que [ch].
  // [startingNine]         : la vuelta que se juega primero en la ronda.
  static int strokesReceivedFromOfficial18Sliding({
    required int diff18,
    required CourseHole ch,
    // Hoyos del CURSO en la misma vuelta (F9 o B9) que [ch].
    // Usar siempre todos los hoyos del curso, no solo los jugados,
    // para garantizar distribución correcta en rondas parciales.
    List<CourseHole> courseHolesInSameNine = const [],
    required StartingNine startingNine,
    // Parámetro explícito que indica si [courseHolesInSameNine] corresponde a la vuelta
    // de inicio (startingNine). Necesario para campos de 9 hoyos con numeración invertida:
    //   • Campo 1-9 jugado como B9 (startingNine=back): todos los hoyos son ≤9 pero son
    //     la vuelta de inicio → isNineHolesStartingNine=true.
    //   • Campo 10-18 jugado como F9 (startingNine=front): todos son >9 pero son la vuelta
    //     de inicio → isNineHolesStartingNine=true.
    // Si null (default), se determina automáticamente a partir de ch.hole y startingNine
    // (comportamiento estándar para campos de 18 hoyos).
    bool? isNineHolesStartingNine,
    // Alias de compatibilidad — DEPRECATED: usar courseHolesInSameNine
    List<CourseHole>? playedHolesInSameNine,
  }) {
    if (diff18 <= 0) return 0;
    // Usar courseHolesInSameNine; si no se pasa, usar playedHolesInSameNine (legacy)
    final nineHoles = courseHolesInSameNine.isNotEmpty
        ? courseHolesInSameNine
        : (playedHolesInSameNine ?? []);
    if (nineHoles.isEmpty) return 0;

    // Determinar si [ch] pertenece a la vuelta de inicio (startingNine).
    //
    // Caso estándar 18 hoyos:
    //   startingNine=front → la vuelta de inicio es F9 (hoyos 1-9), targetIsStartingNine = chIsF9.
    //   startingNine=back  → la vuelta de inicio es B9 (hoyos 10-18), targetIsStartingNine = !chIsF9.
    //
    // Caso especial campo 9 hoyos numerados 1-9 jugado como B9 (o 10-18 jugado como F9):
    //   El caller pasa isNineHolesStartingNine=true para indicar que los nineHoles
    //   son la vuelta de inicio, independientemente del número del hoyo.
    final bool targetIsStartingNine;
    if (isNineHolesStartingNine != null) {
      // El caller ya calculó esto correctamente.
      targetIsStartingNine = isNineHolesStartingNine;
    } else {
      // Fallback estándar: basarse en el número del hoyo.
      final chIsF9 = ch.hole <= 9;
      targetIsStartingNine = startingNine == StartingNine.front
          ? chIsF9   // front start → F9 es la vuelta de inicio
          : !chIsF9; // back start  → B9 (hoyo>9) es la vuelta de inicio
    }

    final share = slidingShareForNine(
      diff18: diff18,
      startingNine: startingNine,
      targetIsStartingNine: targetIsStartingNine,
    );
    if (share <= 0) return 0;

    // Distribuir el share entre TODOS los hoyos del curso en esta vuelta (por SI)
    return strokesReceivedInPlayedHoles(
      diff:        share,
      ch:          ch,
      playedHoles: nineHoles,
    );
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

  /// Puntos Stableford de un hoyo, dado el neto RELATIVO AL PAR.
  ///
  /// La tabla clásica es exactamente `clamp(puntosDelPar - rel, piso, techo)`
  /// con 2 / 0 / 5, y eso se comprobó contra la implementación anterior valor
  /// por valor antes de sustituirla:
  ///
  ///   albatros −3 → 5 · eagle −2 → 4 · birdie −1 → 3
  ///   par 0 → 2 · bogey +1 → 1 · doble o peor → 0
  ///
  /// Parametrizada porque algunos grupos cambian cuánto vale un par o dónde
  /// está el suelo, y sale gratis: es una sola línea. Lo que NO cabe aquí es el
  /// Stableford Modificado —8/5/2/0/−1/−3— que no es lineal y necesitaría una
  /// tabla explícita; queda reportado en vez de inventado.
  static int stablefordPuntos(int rel,
      {int puntosDelPar = 2, int piso = 0, int techo = 5}) {
    final bruto = puntosDelPar - rel;
    if (bruto < piso) return piso;
    if (bruto > techo) return techo;
    return bruto;
  }

  /// La tabla estándar, que es la que usa [contextForHole].
  static int _stableford(int rel) => stablefordPuntos(rel);

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
  // Solo suma hoyos con hasScore==true para evitar contar defaults silenciosos.
  static int totalPutts(Round round, String playerId, {int from = 1, int to = 18}) {
    int total = 0;
    for (int h = from; h <= to; h++) {
      final s = round.getScore(playerId, h);
      if (s.hasScore) total += s.putts;
    }
    return total;
  }

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
  // Usa la misma lógica bilateral de acuerdos manuales que BetEngine:
  //   1. manual[p1][p2]  → valor directo (incluyendo 0 como acuerdo explícito)
  //   2. manual[p2][p1]  → invertido    (incluyendo 0)
  //   3. Ambos null      → diferencia de HCPs como fallback
  //
  // La distribución de strokes usa strokesReceivedInPlayedHoles (no strokesReceivedVs)
  // para ser correcta en medias rondas, solo B9, solo F9 o rondas parciales.
  static int matchPlayStatus(Round round, String p1Id, String p2Id, bool useHandicap, {int throughHole = 18}) {
    int status = 0;

    // ── Calcular recv bilateral una sola vez ──────────────────────────────────
    // Misma prioridad que BetEngine._strokesP1ReceivesFromP2:
    //   1. pairSliding (fuente canónica)
    //   2. manualHandicaps (legacy)
    //   3. HCP diff (fallback)
    double recv = 0;
    if (useHandicap) {
      // 1. pairSliding — fuente canónica, idéntica lógica que BetEngine
      final psKey = p1Id.compareTo(p2Id) <= 0 ? '$p1Id|$p2Id' : '$p2Id|$p1Id';
      final psStored = round.pairSliding[psKey];
      if (psStored != null) {
        // El valor almacenado corresponde al lowId; invertir si p1 es el highId
        final lowId = p1Id.compareTo(p2Id) <= 0 ? p1Id : p2Id;
        recv = (p1Id == lowId) ? psStored : -psStored;
      } else {
        // 2. Legacy manualHandicaps
        final rp1 = round.roundPlayers.firstWhere(
          (r) => r.playerId == p1Id,
          orElse: () => RoundPlayer(playerId: p1Id, handicapEnRonda: round.getHandicap(p1Id)),
        );
        final m1 = rp1.manualHandicaps[p2Id];
        if (m1 != null) {
          recv = m1; // directo, 0 es acuerdo explícito
        } else {
          final rp2 = round.roundPlayers.firstWhere(
            (r) => r.playerId == p2Id,
            orElse: () => RoundPlayer(playerId: p2Id, handicapEnRonda: round.getHandicap(p2Id)),
          );
          final m2 = rp2.manualHandicaps[p1Id];
          if (m2 != null) {
            recv = -m2; // inverso
          } else {
            // 3. Fallback HCP diff
            recv = round.getHandicap(p1Id) - round.getHandicap(p2Id);
          }
        }
      }
    }

    // recv > 0 → p1 recibe (p2=base, p1=receptor)
    // recv < 0 → p1 da     (p1=base, p2=receptor)
    // recv = 0 → sin ventaja
    final bool p1IsBase  = recv <= 0;
    final String baseId     = p1IsBase ? p1Id : p2Id;
    final String receiverId = p1IsBase ? p2Id : p1Id;
    final int    recvAbs    = recv.abs().round();

    final allCh = round.course.holes;

    // Hoyos del CURSO en F9/B9 (no filtrados por jugados) — distribución SI correcta.
    // CORRECCIÓN para campos de 9 hoyos con numeración "invertida":
    //   Campo 1-9 con back-start → todos los hoyos son la vuelta de inicio (B9).
    //   Campo 10-18 con front-start → todos son la vuelta de inicio (F9).
    final List<CourseHole> courseF9mp;
    final List<CourseHole> courseB9mp;
    final courseHasOnlyF9nums = allCh.isNotEmpty && allCh.every((h) => h.hole <= 9);
    final courseHasOnlyB9nums = allCh.isNotEmpty && allCh.every((h) => h.hole >  9);
    if (courseHasOnlyF9nums && round.startingNine == StartingNine.back) {
      courseF9mp = [];
      courseB9mp = [...allCh];
    } else if (courseHasOnlyB9nums && round.startingNine == StartingNine.front) {
      courseF9mp = [...allCh];
      courseB9mp = [];
    } else {
      courseF9mp = allCh.where((ch) => ch.hole <= 9).toList();
      courseB9mp = allCh.where((ch) => ch.hole >  9).toList();
    }

    // Orden lógico de hoyos del curso (igual que en _nassauPair):
    // - Si startingNine=back: primero 10-18, luego 1-9 (solo los que existan en el curso).
    // - Si startingNine=front: orden numérico ascendente.
    // Esto evita "Hole X not found" en cursos de 9 hoyos y corrige el orden en B9.
    final List<CourseHole> orderedHoles;
    {
      if (round.startingNine == StartingNine.back) {
        final b9 = allCh.where((c) => c.hole >= 10).toList()..sort((a, b) => a.hole.compareTo(b.hole));
        final f9 = allCh.where((c) => c.hole < 10).toList()..sort((a, b) => a.hole.compareTo(b.hole));
        orderedHoles = [...b9, ...f9];
      } else {
        orderedHoles = [...allCh]..sort((a, b) => a.hole.compareTo(b.hole));
      }
    }

    for (final ch in orderedHoles) {
      final h = ch.hole;
      // Respetar el parámetro throughHole (límite numérico del hoyo, no posición)
      if (h > throughHole && throughHole <= 18) {
        // Solo aplicar filtro si throughHole es un límite de hoyo F9 (≤9 o 18)
        // Para B9 el caller pasa throughHole=18, así que no se filtra nada
        if (round.startingNine != StartingNine.back || throughHole < 18) continue;
      }
      final s1 = round.getScore(p1Id, h);
      final s2 = round.getScore(p2Id, h);
      if (!s1.hasScore || !s2.hasScore) continue;

      // Strokes distribuidos usando el sliding oficial de 18 hoyos (F9/B9 separados).
      // Usar hoyos del CURSO (no solo jugados) para distribución correcta en rondas parciales.
      final courseHolesForMP = courseF9mp.any((hh) => hh.hole == ch.hole) ? courseF9mp : courseB9mp;
      final strokesHere = useHandicap && recvAbs > 0
          ? strokesReceivedFromOfficial18Sliding(
              diff18:              recvAbs,
              ch:                  ch,
              courseHolesInSameNine: courseHolesForMP,
              startingNine:        round.startingNine,
              isNineHolesStartingNine: courseF9mp.any((h) => h.hole == ch.hole)
                  ? (round.startingNine == StartingNine.front)
                  : (round.startingNine == StartingNine.back),
            )
          : 0;

      final grossBase     = round.getScore(baseId,     h).grossScore!;
      final grossReceiver = round.getScore(receiverId, h).grossScore!;
      final netReceiver   = grossReceiver - strokesHere;

      // Resultado en perspectiva p1
      if (p1IsBase) {
        if      (grossBase < netReceiver) {
          status++;
        } else if (grossBase > netReceiver) status--;
      } else {
        if      (netReceiver < grossBase) {
          status++;
        } else if (netReceiver > grossBase) status--;
      }
    }
    return status;
  }

  // ── Delta de un hoyo entre dos lados (best ball por defecto) ─────────────
  //
  // Reglas:
  //   • Para cada lado se toma el mejor score válido de todos sus jugadores.
  //     "Best ball" = el menor score neto (o bruto si !useHandicap).
  //   • Si al menos un jugador del lado no tiene score en ese hoyo,
  //     el lado se considera sin score y el resultado es null (hoyo no jugado).
  //   • Para lados de 1 jugador el comportamiento es idéntico al actual.
  //
  // Retorna:
  //   +1 si sideA gana el hoyo
  //   -1 si sideB gana el hoyo
  //    0 si empatan
  //   null si el hoyo no está completo (algún jugador sin score)
  //
  // hcpMap: mapa playerId → HCP efectivo calculado con _effectiveHcps.
  //   Se precalcula fuera del loop de hoyos para no repetirlo.
  //   Para modo gross puede ser un mapa vacío (todos 0.0).
  //
  // Nota sobre handicap en equipo:
  //   En modo net cada jugador recibe sus strokes individuales vs el hoyo.
  //   La diferencia entre los jugadores del equipo NO genera strokes adicionales;
  //   simplemente se toma el mejor score neto del equipo.
  //   En un futuro versión podría añadirse un HCP de equipo ajustado.
  static int? holeDeltaVs({
    required Round round,
    required BetSide sideA,
    required BetSide sideB,
    required int holeNum,
    required bool useHandicap,
    required Map<String, double> hcpMap, // playerId → HCP efectivo
  }) {
    final ch = round.course.holes.firstWhere(
      (h) => h.hole == holeNum,
      orElse: () => round.course.holes.first,
    );

    // ── Score válido de un jugador en el hoyo ─────────────────────────────
    int? playerScore(String pid) {
      final s = round.getScore(pid, holeNum);
      if (!s.hasScore) return null;
      if (!useHandicap) return s.grossScore;
      final hcp = hcpMap[pid] ?? round.getHandicap(pid);
      final strokes = strokesReceived(hcp, ch);
      return s.grossScore! - strokes;
    }

    // ── Best ball de un lado: menor score neto/bruto de los que SÍ anotaron ──
    //
    // Basta con que UN jugador del lado tenga score. Es la regla real de Best
    // Ball: se juega la mejor bola y quien queda fuera del hoyo no necesita
    // terminarlo. Antes se exigía score de todos, así que un compañero que
    // levantaba la bola anulaba el hoyo para ambos lados.
    //
    // null solo si NINGÚN jugador del lado anotó → el hoyo no se ha jugado.
    int? bestBall(BetSide side) {
      int? best;
      // Quién ANOTA, no quién juega: en scramble es el virtual del equipo.
      // Con side.playerIds este bucle no encontraba ningún score y el hoyo se
      // daba por no jugado en los 18.
      for (final pid in round.scoreCarriersOf(side)) {
        final sc = playerScore(pid);
        if (sc == null) continue; // ese jugador levantó la bola
        if (best == null || sc < best) best = sc;
      }
      return best;
    }

    final scoreA = bestBall(sideA);
    final scoreB = bestBall(sideB);

    // Si algún lado no tiene score completo, el hoyo no está listo
    if (scoreA == null || scoreB == null) return null;

    if (scoreA < scoreB) return  1;  // A gana
    if (scoreA > scoreB) return -1;  // B gana
    return 0;                         // empate
  }

  // ── HCP efectivo para modo equipo BEST BALL ───────────────────────────────
  // En Best Ball, cada jugador recibe strokes RELATIVOS al jugador con menor HCP.
  // El jugador con menor HCP = 0 strokes.
  // Los demás reciben la diferencia vs el jugador de menor HCP.
  //
  // Ejemplo:
  //   Jugador A: HCP 5  → 0 strokes (es el mejor)
  //   Jugador B: HCP 10 → 5 strokes
  //   Jugador C: HCP 12 → 7 strokes
  //   Jugador D: HCP 18 → 13 strokes
  //
  // Este mapa se usa en holeDeltaVs() para calcular scores netos.
  //
  // [cfg] aplica el allowance del WHS (paso 2): cada handicap se reduce al
  // porcentaje acordado ANTES de calcular la diferencia. Con el default
  // ([TeamHandicapConfig.legacy], 100%) el resultado es idéntico al previo.
  //
  // Ejemplo Four-Ball al 90% con HCP 5 / 10 / 12 / 18:
  //   ajustados → 4.5 / 9 / 10.8 / 16.2   (el más bajo pasa a ser scratch)
  //   strokes   →   0 / 4.5 / 6.3 / 11.7
  //
  // En Scramble los "jugadores" son los virtuales de equipo, cuyo handicap ya
  // viene combinado desde Setup con lowWeight; aquí solo se les aplica el
  // allowance, de modo que 50% × (70/30) reproduce el clásico 35%/15%.
  static Map<String, double> buildTeamHcpMap(
    Round round,
    List<String> playerIds, {
    TeamHandicapConfig cfg = TeamHandicapConfig.legacy,
  }) {
    if (playerIds.isEmpty) return {};

    // Handicap con allowance aplicado
    final adjusted = {
      for (final pid in playerIds) pid: round.getHandicap(pid) * cfg.allowance,
    };

    // Encontrar el HCP más bajo (jugador mejor) — pasa a ser el "scratch"
    double lowestHcp = double.infinity;
    for (final v in adjusted.values) {
      if (v < lowestHcp) lowestHcp = v;
    }

    // Calcular strokes relativos: cada jugador recibe (su HCP - menor HCP)
    return adjusted.map((pid, v) => MapEntry(pid, v - lowestHcp));
  }

  // ── Calcular handicap de equipo para modo SCRAMBLE ────────────────────────
  // En Scramble, el equipo tiene UN solo handicap calculado según USGA:
  //
  // Para 2 jugadores:
  //   HCP equipo = (35% del HCP más bajo) + (15% del HCP más alto)
  //
  // Ejemplo:
  //   Jugador A: HCP 10
  //   Jugador B: HCP 20
  //   → HCP equipo = (0.35 × 10) + (0.15 × 20) = 3.5 + 3 = 6.5 ≈ 7
  //
  // Para 4 jugadores:
  //   HCP equipo = (25% bajo) + (20% 2do) + (15% 3ro) + (10% alto)
  static double calculateScrambleTeamHandicap(Round round, List<String> playerIds) {
    if (playerIds.isEmpty) return 0.0;
    if (playerIds.length == 1) return round.getHandicap(playerIds.first);

    // Obtener handicaps de todos los jugadores y ordenar de menor a mayor
    final hcps = playerIds.map((pid) => round.getHandicap(pid)).toList()
      ..sort();

    if (playerIds.length == 2) {
      // 2 jugadores: 35% bajo + 15% alto
      return (hcps[0] * 0.35) + (hcps[1] * 0.15);
    } else if (playerIds.length == 3) {
      // 3 jugadores: 30% bajo + 20% medio + 10% alto
      return (hcps[0] * 0.30) + (hcps[1] * 0.20) + (hcps[2] * 0.10);
    } else {
      // 4 jugadores: 25% bajo + 20% 2do + 15% 3ro + 10% alto
      return (hcps[0] * 0.25) + (hcps[1] * 0.20) + (hcps[2] * 0.15) + (hcps[3] * 0.10);
    }
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
