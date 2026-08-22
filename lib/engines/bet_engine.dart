// ─────────────────────────────────────────────────────────────────────────────
// BET ENGINE v4
// Responsabilidad: aplicar reglas de cada BetModuleInstance
// Genera LedgerEntries. NO calcula scores ni muestra UI.
// ─────────────────────────────────────────────────────────────────────────────
import '../models/models.dart';
import 'snake_engine.dart';
import 'rabbit_engine.dart';
import 'game_engine.dart';

class BetEngine {

  // ══════════════════════════════════════════════════════════════════════════
  // CANONICAL PAIR SLIDING — fuente de verdad única
  // ══════════════════════════════════════════════════════════════════════════

  /// Construye la clave canónica para el par (a, b):
  /// ids ordenados lexicográficamente, separados por '|'.
  static String pairKey(String a, String b) =>
      a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';

  /// Devuelve cuántos strokes recibe [p1Id] de [p2Id] usando [round.pairSliding].
  /// Retorna null si no hay entrada para este par en pairSliding.
  ///
  /// Convención del valor almacenado: el valor representa los strokes que recibe
  /// el jugador cuyo id es menor lexicográficamente.
  ///   - Si clave = 'A|B' y valor = -5 → A da 5 a B (A recibe -5).
  ///   - Consulta recv(A,B) = -5, recv(B,A) = +5.
  static double? canonicalSlidingBetween(Round round, String p1Id, String p2Id) {
    if (p1Id == p2Id) return 0.0;
    final key = pairKey(p1Id, p2Id);
    final stored = round.pairSliding[key];
    if (stored == null) return null;
    // Si p1Id es el "low" id de la clave, el valor se usa directo.
    // Si p1Id es el "high" id de la clave, se invierte el signo.
    final lowId = p1Id.compareTo(p2Id) <= 0 ? p1Id : p2Id;
    return (p1Id == lowId) ? stored : -stored;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // VALIDACIÓN DE pairSliding
  // ══════════════════════════════════════════════════════════════════════════

  /// Valida la coherencia del campo [round.pairSliding] y detecta conflictos con
  /// los legacy [manualHandicaps] de [RoundPlayer].
  ///
  /// Retorna una lista de mensajes de error descriptivos (vacía si todo está ok).
  static List<String> validatePairSliding(Round round) {
    final errors = <String>[];

    for (final entry in round.pairSliding.entries) {
      final key = entry.key;
      final val = entry.value;

      // 1. Formato de clave válido
      final parts = key.split('|');
      if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
        errors.add('pairSliding: clave "$key" mal formada (se esperaba "id1|id2").');
        continue;
      }

      // 2. Los dos ids del par no pueden ser el mismo jugador
      if (parts[0] == parts[1]) {
        errors.add('pairSliding: clave "$key" tiene el mismo jugador en ambos lados.');
        continue;
      }

      // 3. Ids deben estar en orden lexicográfico (la clave siempre debe ser canónica)
      if (parts[0].compareTo(parts[1]) > 0) {
        errors.add('pairSliding: clave "$key" no está en orden canónico '
            '(se esperaba "${parts[1]}|${parts[0]}").');
      }

      // 4. El valor no puede ser NaN o infinito
      if (val.isNaN || val.isInfinite) {
        errors.add('pairSliding: clave "$key" tiene valor inválido ($val).');
      }

      // 5. Verificar conflicto con legacy manualHandicaps si ambos existen
      final lowId  = parts[0];
      final highId = parts[1];

      final rpLow  = round.roundPlayers.where((r) => r.playerId == lowId).firstOrNull;
      final rpHigh = round.roundPlayers.where((r) => r.playerId == highId).firstOrNull;

      final mLowHigh  = rpLow?.manualHandicaps[highId];   // lo que lowId dice que recibe de highId
      final mHighLow  = rpHigh?.manualHandicaps[lowId];   // lo que highId dice que recibe de lowId

      // El pairSliding dice que lowId recibe `val` de highId.
      // El legacy manual[lowId][highId] también debería ser `val`.
      if (mLowHigh != null && (mLowHigh - val).abs() > 0.01) {
        errors.add('pairSliding: conflicto entre pairSliding["$key"]=$val y '
            'manualHandicaps[$lowId][$highId]=$mLowHigh. '
            'Si ambos existen deben coincidir.');
      }

      // El legacy manual[highId][lowId] debería ser -val (highId da `val` a lowId).
      if (mHighLow != null && (mHighLow + val).abs() > 0.01) {
        errors.add('pairSliding: conflicto entre pairSliding["$key"]=$val y '
            'manualHandicaps[$highId][$lowId]=$mHighLow '
            '(se esperaba ${-val}). '
            'Si ambos existen deben ser opuestos.');
      }
    }

    return errors;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MIGRACIÓN LEGACY: manualHandicaps → pairSliding
  // ══════════════════════════════════════════════════════════════════════════

  /// Construye un mapa pairSliding a partir de los manualHandicaps legacy
  /// de los RoundPlayers. Útil para rondas antiguas que aún no tienen pairSliding.
  ///
  /// Reglas:
  ///   - Si existen ambos lados y son consistentes (a+b≈0) → migra.
  ///   - Si existe solo uno → migra ese valor como fuente de verdad.
  ///   - Si existen ambos y son inconsistentes → añade error a [errors] y omite ese par.
  static Map<String, double> buildPairSlidingFromLegacy(
    Round round, {
    List<String>? errors,
  }) {
    final result = <String, double>{};
    final processed = <String>{};

    for (final rp in round.roundPlayers) {
      for (final entry in rp.manualHandicaps.entries) {
        final otherId = entry.key;
        final key = pairKey(rp.playerId, otherId);
        if (processed.contains(key)) continue;
        processed.add(key);

        // Valor directo: rp recibe `entry.value` de otherId
        final mDirect = entry.value; // recv(rp.playerId, otherId)

        // Buscar el inverso en el otro RoundPlayer
        final rpOther = round.roundPlayers
            .where((r) => r.playerId == otherId)
            .firstOrNull;
        final mInverse = rpOther?.manualHandicaps[rp.playerId]; // recv(otherId, rp.playerId)

        // El valor canónico en pairSliding es: recv(lowId, highId)
        final lowId = rp.playerId.compareTo(otherId) <= 0 ? rp.playerId : otherId;
        final isRpLow = rp.playerId == lowId;

        if (mInverse != null) {
          // Ambos lados existen: verificar consistencia (deben sumar 0)
          if ((mDirect + mInverse).abs() > 0.01) {
            errors?.add(
              'Legacy inconsistente para el par "$key": '
              'manual[${rp.playerId}][$otherId]=$mDirect y '
              'manual[$otherId][${rp.playerId}]=$mInverse '
              'no son opuestos. Par ignorado en la migración.',
            );
            continue; // No migrar un par inconsistente
          }
          // Consistentes: usar el valor desde la perspectiva del lowId
          result[key] = isRpLow ? mDirect : -mDirect;
        } else {
          // Solo un lado definido: ese es la fuente de verdad
          result[key] = isRpLow ? mDirect : -mDirect;
        }
      }
    }

    return result;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPER CENTRAL: strokes que recibe p1 de p2
  // ══════════════════════════════════════════════════════════════════════════
  //
  // REGLAS DE PRIORIDAD (nueva):
  //   1. pairSliding (fuente canónica)  → si existe para el par, usarlo.
  //   2. manualHandicaps legacy         → compatibilidad con rondas antiguas.
  //      a. Manual[p1][p2]  → p1 recibe ese valor.
  //      b. Manual[p2][p1]  → invertido.
  //      c. Si ambos existen y son inconsistentes → StateError.
  //   3. Fallback HCP                   → p1.hcp - p2.hcp.
  //
  // ══════════════════════════════════════════════════════════════════════════
  // HELPER: clasificación correcta de hoyos para campos de 9 hoyos
  // ══════════════════════════════════════════════════════════════════════════

  /// Clasifica los hoyos jugados de [playerId] en F9 y B9 teniendo en cuenta
  /// el caso especial de campos de 9 hoyos con numeración "incorrecta":
  ///
  /// • Campo 1-9 con startingNine=back → todos los hoyos son la vuelta de inicio
  ///   (B9), pero tienen números ≤9. Se reclasifican como B9 para que
  ///   strokesReceivedFromOfficial18Sliding aplique ceil (no floor).
  ///
  /// • Campo 10-18 con startingNine=front → análogamente se reclasifican como F9.
  ///
  /// Retorna (playedF9, playedB9) correctamente clasificados.
  /// Devuelve los hoyos del CURSO (no filtrados por si fueron jugados) divididos
  /// en (F9, B9), respetando campos de 9 hoyos con numeración invertida.
  /// Usar para strokesReceivedFromOfficial18Sliding: la distribución de SI
  /// debe hacerse sobre los 9 hoyos completos del curso.
  static (List<CourseHole>, List<CourseHole>) _courseHolesF9B9(
    List<CourseHole> allHoles,
    StartingNine startingNine,
  ) {
    final courseHasOnlyF9nums = allHoles.isNotEmpty && allHoles.every((h) => h.hole <= 9);
    final courseHasOnlyB9nums = allHoles.isNotEmpty && allHoles.every((h) => h.hole >  9);

    if (courseHasOnlyF9nums && startingNine == StartingNine.back) {
      // Campo 1-9 jugado como back-nine: todos son "B9" (vuelta de inicio)
      return (<CourseHole>[], [...allHoles]);
    } else if (courseHasOnlyB9nums && startingNine == StartingNine.front) {
      // Campo 10-18 jugado como front-nine: todos son "F9" (vuelta de inicio)
      return ([...allHoles], <CourseHole>[]);
    } else {
      return (
        allHoles.where((ch) => ch.hole <= 9).toList(),
        allHoles.where((ch) => ch.hole >  9).toList(),
      );
    }
  }

  /// Dado un hoyo [ch] y las listas [courseF9]/[courseB9] producidas por
  /// [_courseHolesF9B9] (o [courseHolesF9B9Public]), calcula si los
  /// [courseHolesInSameNine] correspondientes al hoyo son la vuelta de inicio.
  ///
  /// Esto es necesario para campos de 9 hoyos con numeración "invertida":
  ///   • Campo 1-9 jugado como B9 (startingNine=back): courseB9 tiene todos los
  ///     hoyos ≤9, que SON la vuelta de inicio → devuelve true.
  ///   • Campo 10-18 jugado como F9 (startingNine=front): courseF9 tiene todos
  ///     los hoyos >9, que SON la vuelta de inicio → devuelve true.
  ///   • Campo 18H estándar: comportamiento normal (F9=starting si front, B9=starting si back).
  ///
  /// Usar el resultado como [isNineHolesStartingNine] en
  /// [GameEngine.strokesReceivedFromOfficial18Sliding].
  static bool isNineStartingNine({
    required CourseHole ch,
    required List<CourseHole> courseF9,
    required List<CourseHole> courseB9,
    required StartingNine startingNine,
  }) {
    final isF9 = courseF9.any((h) => h.hole == ch.hole);
    return isF9
        ? startingNine == StartingNine.front
        : startingNine == StartingNine.back;
  }

  /// Versión pública para uso en la UI.
  /// Devuelve los hoyos del CURSO divididos en (F9, B9).
  static (List<CourseHole>, List<CourseHole>) splitHolesForPlayerPublic(
    Round round,
    String playerId,
    List<CourseHole> allHoles,
  ) => _courseHolesF9B9(allHoles, round.startingNine);

  /// Versión pública directa: devuelve los hoyos del CURSO divididos en (F9, B9)
  /// sin necesitar round ni playerId. Usar para la UI cuando solo se tienen
  /// los hoyos del curso y el startingNine.
  static (List<CourseHole>, List<CourseHole>) courseHolesF9B9Public(
    List<CourseHole> allHoles,
    StartingNine startingNine,
  ) => _courseHolesF9B9(allHoles, startingNine);

  // Devuelve cuántos strokes recibe p1 de p2:
  //   > 0 → p1 recibe esa cantidad
  //   = 0 → acuerdo par a par: sin ventaja
  //   < 0 → p2 recibe |valor| (p1 da strokes)
  static double _strokesP1ReceivesFromP2(Round round, String p1Id, String p2Id) {
    // ── 1. pairSliding (fuente canónica) ─────────────────────────────────────
    final canonical = canonicalSlidingBetween(round, p1Id, p2Id);
    if (canonical != null) return canonical;

    // ── 2. Legacy manualHandicaps ─────────────────────────────────────────────
    final rp1 = round.roundPlayers.firstWhere(
        (r) => r.playerId == p1Id,
        orElse: () => RoundPlayer(playerId: p1Id, handicapEnRonda: round.getHandicap(p1Id)));
    final m1 = rp1.manualHandicaps[p2Id];

    final rp2 = round.roundPlayers.firstWhere(
        (r) => r.playerId == p2Id,
        orElse: () => RoundPlayer(playerId: p2Id, handicapEnRonda: round.getHandicap(p2Id)));
    final m2 = rp2.manualHandicaps[p1Id];

    // ── Validación de consistencia bilateral ─────────────────────────────────
    // Si AMBOS lados tienen manual guardado, deben ser espejos exactos (m1 == -m2).
    // Si no lo son, significa inconsistencia de datos: lanzar error controlado.
    if (m1 != null && m2 != null) {
      // Tolerancia de 0.01 para evitar falsos positivos por precisión de punto flotante
      if ((m1 + m2).abs() > 0.01) {
        throw StateError(
          'Inconsistencia bilateral de acuerdo manual entre $p1Id y $p2Id: '
          'manual[$p1Id][$p2Id]=$m1 pero manual[$p2Id][$p1Id]=$m2 '
          '(se esperaba $m1 == ${-m2}). '
          'Corrige los acuerdos antes de calcular la apuesta.',
        );
      }
      // Son consistentes: usar m1 (fuente canónica desde perspectiva p1)
      return m1;
    }

    if (m1 != null) return m1; // manual directo — 0 es acuerdo válido, se respeta
    if (m2 != null) return -m2; // inverso: 0 también se respeta

    // Fallback HCP: SOLO si no existe ningún manual entre este par en ninguna dirección.
    return round.getHandicap(p1Id) - round.getHandicap(p2Id);
  }

  /// Método público: cuántos strokes recibe p1 de p2.
  /// Prioridad: manual[p1][p2] → manual[p2][p1] invertido → HCP diff.
  /// Positivo = p1 recibe, negativo = p1 da (p2 recibe).
  static double strokesP1ReceivesFromP2(Round round, String p1Id, String p2Id) =>
      _strokesP1ReceivesFromP2(round, p1Id, p2Id);

  /// Retorna true si existe un acuerdo explícito de strokes entre p1 y p2
  /// (ya sea en pairSliding o en manualHandicaps), aunque el valor sea 0.
  ///
  /// Útil para distinguir "acordaron jugar parejo" (0 explícito)
  /// de "sin acuerdo → usar diferencia de HCP" (fallback).
  static bool hasExplicitAgreement(Round round, String p1Id, String p2Id) {
    // 1. pairSliding canónico
    if (canonicalSlidingBetween(round, p1Id, p2Id) != null) return true;
    // 2. legacy manualHandicaps
    final rp1 = round.roundPlayers.cast<RoundPlayer?>().firstWhere(
        (r) => r?.playerId == p1Id, orElse: () => null);
    final rp2 = round.roundPlayers.cast<RoundPlayer?>().firstWhere(
        (r) => r?.playerId == p2Id, orElse: () => null);
    if (rp1?.manualHandicaps.containsKey(p2Id) == true) return true;
    if (rp2?.manualHandicaps.containsKey(p1Id) == true) return true;
    return false;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SEGMENTACIÓN LÓGICA DE LA RONDA
  // ══════════════════════════════════════════════════════════════════════════
  //
  // El "primer segmento" es SIEMPRE la vuelta de inicio (startingNine), aunque
  // sus hoyos se numeren 10-18. El "segundo segmento" es la otra vuelta.
  //
  // IMPORTANTE — por qué no basta con round.totalHoles:
  //   La captura permite extender una ronda declarada de 9 hoyos a 18
  //   ("⛳ Continuar Back 9"), y totalHoles NO se actualiza al hacerlo.
  //   Si se segmentara por totalHoles, el segundo nine se descartaría en
  //   silencio y Nassau pagaría solo la mitad. Por eso [singleNine] mira
  //   también si hay scores capturados en el segundo segmento.

  /// Segmentación lógica de una ronda para las apuestas por vuelta.
  static RoundSegments segmentsOf(Round round) {
    final (f9, b9) = _courseHolesF9B9(round.course.holes, round.startingNine);
    final isBack   = round.startingNine == StartingNine.back;

    final firstHoles  = (isBack ? b9 : f9).map((c) => c.hole).toList()..sort();
    final secondHoles = (isBack ? f9 : b9).map((c) => c.hole).toList()..sort();

    // ¿Se capturó algún score en el segundo segmento?
    bool secondPlayed = false;
    outer:
    for (final h in secondHoles) {
      for (final pid in round.scores.keys) {
        if (round.getScore(pid, h).hasScore) {
          secondPlayed = true;
          break outer;
        }
      }
    }

    return RoundSegments(
      firstNine:  firstHoles,
      secondNine: secondHoles,
      singleNine: round.totalHoles <= 9 && !secondPlayed,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ESCALA COMÚN DE UN GRUPO (modos "1 Pot" con 3+ jugadores)
  // ══════════════════════════════════════════════════════════════════════════
  //
  // Los acuerdos de pairSliding son BILATERALES. Para resolver un pot único con
  // 3+ jugadores hace falta una escala común: se elige un "ancla" y cada jugador
  // calcula su neto respecto a ella. Sin esto habría que comparar netos medidos
  // contra rivales distintos, que no son comparables entre sí.

  /// Ancla del grupo: el jugador que MÁS da y MENOS recibe según los acuerdos
  /// bilaterales. Si hay empate de ventaja, gana el de HCP más bajo.
  static String groupAnchor(Round round, List<String> pids) {
    if (pids.isEmpty) return '';
    String anchor  = pids.first;
    double bestScore = double.negativeInfinity;
    for (final pid in pids) {
      double net = 0;
      for (final other in pids) {
        if (other == pid) continue;
        net += _strokesP1ReceivesFromP2(round, pid, other); // + recibe, − da
      }
      // Queremos el net MÁS NEGATIVO (da más, recibe menos) → maximizar −net
      final score = -net;
      if (score > bestScore ||
          (score == bestScore && round.getHandicap(pid) < round.getHandicap(anchor))) {
        bestScore = score;
        anchor    = pid;
      }
    }
    return anchor;
  }

  /// Strokes que recibe [pid] en el hoyo [ch] respecto de [anchorId], usando el
  /// pairSliding oficial de 18 hoyos con reparto F9/B9.
  /// Devuelve 0 si [pid] es el ancla o si no recibe ventaja de ella.
  static int strokesVsAnchorAtHole({
    required Round round,
    required String pid,
    required String anchorId,
    required CourseHole ch,
    required List<CourseHole> courseF9,
    required List<CourseHole> courseB9,
  }) {
    if (pid == anchorId) return 0;
    final recv = _strokesP1ReceivesFromP2(round, pid, anchorId);
    if (recv <= 0) return 0;
    final inF9 = courseF9.any((hh) => hh.hole == ch.hole);
    return GameEngine.strokesReceivedFromOfficial18Sliding(
      diff18:                recv.round(),
      ch:                    ch,
      courseHolesInSameNine: inF9 ? courseF9 : courseB9,
      startingNine:          round.startingNine,
      isNineHolesStartingNine: isNineStartingNine(
        ch: ch, courseF9: courseF9, courseB9: courseB9,
        startingNine: round.startingNine,
      ),
    );
  }

  /// Ganador neto de un hoyo dentro de un grupo, respetando pairSliding a
  /// través del ancla. Devuelve null si hay empate o si falta algún score.
  ///
  /// Sustituye a [GameEngine.holeWinner] en los modos de grupo: aquél usa el
  /// handicap individual contra el par e ignora los acuerdos bilaterales.
  static String? groupHoleWinner({
    required Round round,
    required List<String> pids,
    required CourseHole ch,
    required bool useHandicap,
    required String anchorId,
    required List<CourseHole> courseF9,
    required List<CourseHole> courseB9,
  }) {
    int?    best;
    String? winner;
    bool    tie = false;

    for (final pid in pids) {
      final s = round.getScore(pid, ch.hole);
      if (!s.hasScore) return null; // hoyo incompleto
      final strokes = useHandicap
          ? strokesVsAnchorAtHole(
              round: round, pid: pid, anchorId: anchorId,
              ch: ch, courseF9: courseF9, courseB9: courseB9)
          : 0;
      final net = s.grossScore! - strokes;
      if (best == null || net < best) {
        best   = net;
        winner = pid;
        tie    = false;
      } else if (net == best) {
        tie = true;
      }
    }
    return tie ? null : winner;
  }

  /// Genera todos los LedgerEntries para una BetGroup completa
  static List<LedgerEntry> computeGroup(Round round, BetGroup group) {
    final entries = <LedgerEntry>[];
    for (final mod in group.modules) {
      entries.addAll(computeModule(round, group, mod));
    }
    return entries;
  }

  /// Genera los LedgerEntries de UN módulo (equipo o individual).
  /// Aislar el cálculo por módulo permite que [safeComputeAll] descarte solo
  /// el módulo con datos corruptos en vez de toda la ronda.
  static List<LedgerEntry> computeModule(
      Round round, BetGroup group, BetModuleInstance mod) {
    // ── Modo equipo: sides definidos y válidos ──────────────────────────────
    if (mod.hasTeamSides) {
      switch (mod.type) {
        case BetModuleType.matchAutoPress:
          return _matchAutoPressTeam(round, mod);
        case BetModuleType.nassau:
          return _nassauTeam(round, mod);
        case BetModuleType.skins:
          // Skins en modo equipo: cada hoyo best-ball entre lados
          return _skinsTeam(round, mod);
        case BetModuleType.nassauLowHigh:
          return _nassauLowHighTeam(round, mod);
        // nassauPress ya no existe como tipo separado; nassau unificado lo maneja
        default:
          // Medal, putts, oyeses, units: no tienen semántica de equipo aún.
          // Fallback: usar todos los jugadores de ambos lados en modo individual.
          return _computeModuleIndividual(round, group, mod);
      }
    }

    // ── Modo individual clásico ─────────────────────────────────────────────
    return _computeModuleIndividual(round, group, mod);
  }

  /// Resuelve un módulo en modo individual (comportamiento previo, sin cambios).
  static List<LedgerEntry> _computeModuleIndividual(
      Round round, BetGroup group, BetModuleInstance mod) {
    final entries = <LedgerEntry>[];
    final pids = mod.effectivePids(group.playerIds);
    switch (mod.type) {
      case BetModuleType.skins:
        entries.addAll(_skins(round, pids, mod));
        break;
      case BetModuleType.nassau:
        entries.addAll(_nassau(round, pids, mod));
        break;
      case BetModuleType.matchAutoPress:
        entries.addAll(_matchAutoPress(round, pids, mod));
        break;
      case BetModuleType.medal:
        entries.addAll(_medal(round, pids, mod));
        break;
      case BetModuleType.putts:
        entries.addAll(_putts(round, pids, mod));
        break;
      case BetModuleType.oyeses:
        entries.addAll(_oyeses(round, pids, mod));
        break;
      case BetModuleType.nassauLowHigh:
        // Sin lados no hay bola baja ni alta que comparar. Antes esto devolvía
        // vacío y el módulo se quedaba mudo: la apuesta aparecía configurada y
        // nadie cobraba nada. Lanzar lo convierte en un aviso visible, que
        // safeComputeAll reporta sin tumbar el resto de la ronda.
        throw StateError(
            'Bola Baja / Bola Alta necesita dos equipos de 2 jugadores. '
            'Abre la apuesta y define el Lado A y el Lado B.');
      case BetModuleType.units:
        entries.addAll(_units(round, pids, mod));
        break;
      case BetModuleType.snake:
        // Rama nueva, motor aparte. No toca nada de lo de arriba.
        //
        // Devolver vacío cuando nadie hizo 3-putt es CORRECTO —no hay dinero
        // que mover— y a la vez insuficiente: un cero sin explicación se lee
        // como un fallo del cálculo. Lo que falta no es un asiento, es una
        // frase, y esa la pone notasDeLiquidacion() desde la misma búsqueda que
        // usa esto. Ver settlement_notes.dart.
        entries.addAll(SnakeEngine.liquidar(round, pids, mod));
        break;
      case BetModuleType.rabbit:
        // Otra rama nueva, otro motor aparte. Reutiliza GameEngine.holeWinner
        // en vez de redefinir "ganar un hoyo": una segunda definición podría
        // discrepar de la que usa Skins.
        entries.addAll(RabbitEngine.liquidar(round, pids, mod));
        break;
    }
    return entries;
  }

  // ── SKINS ─────────────────────────────────────────────────────────────────
  // onePot   (default): todos vs todos, un solo ganador por hoyo toma de todos.
  // allVsAll           : cada par tiene su propia skin independiente.
  static List<LedgerEntry> _skins(Round round, List<String> pids, BetModuleInstance mod) {
    final entries = <LedgerEntry>[];
    final n = pids.length;
    if (n < 2) return entries;

    // allVsAll: iterar todos los pares → cada par tiene su propio duelo
    if (mod.isAllVsAll || n == 2) {
      for (int i = 0; i < n; i++) {
        for (int j = i + 1; j < n; j++) {
          entries.addAll(_skins1v1(round, pids[i], pids[j], mod));
        }
      }
      return entries;
    }

    // ── onePot GRUPAL (3+ jugadores): un ganador por hoyo cobra de CADA rival ─
    // Cada jugador aporta valuePerSkin por hoyo. Con carry, el pot acumulado
    // se cobra completo a cada perdedor (no dividido entre ellos).
    // Ej: n=3, valuePerSkin=10, sin carry → cada perdedor paga 10 al ganador.
    // Con carry de 3 hoyos → cada perdedor paga 30 al ganador.
    final cfg = mod.skins;
    // pot = lo que cada perdedor debe pagar por skin acumulado
    double potPerLoser = cfg.valuePerSkin;

    // Iterar en el orden correcto de la ronda (respeta startingNine)
    final allHoles  = round.course.holes;
    final holeMap   = { for (final ch in allHoles) ch.hole: ch };
    final holeOrder = segmentsOf(round).playOrder;

    // Escala común del grupo: ancla + hoyos F9/B9 del curso.
    // Antes se usaba GameEngine.holeWinner (handicap individual vs par), que
    // ignoraba por completo pairSliding y las ventajas acordadas.
    final anchorId = groupAnchor(round, pids);
    final (courseF9skins, courseB9skins) =
        _courseHolesF9B9(allHoles, round.startingNine);

    for (final h in holeOrder) {
      // Hoyo no jugado aún: se salta sin acumular carry
      if (!pids.every((pid) => round.getScore(pid, h).hasScore)) continue;

      final winner = groupHoleWinner(
        round:       round,
        pids:        pids,
        ch:          holeMap[h]!,
        useHandicap: mod.useHandicap,
        anchorId:    anchorId,
        courseF9:    courseF9skins,
        courseB9:    courseB9skins,
      );
      if (winner != null) {
        // Cada perdedor paga potPerLoser al ganador
        for (final pid in pids) {
          if (pid != winner) {
            entries.add(LedgerEntry(
              fromPlayerId: pid, toPlayerId: winner,
              amount: potPerLoser, betType: BetModuleType.skins,
              reason: 'Skins H$h', hole: h,
            ));
          }
        }
        potPerLoser = cfg.valuePerSkin;
      } else {
        // Empate en hoyo jugado → acumular carry (cada perdedor acumula 1 skin más)
        if (cfg.carryOver) potPerLoser += cfg.valuePerSkin;
      }
    }
    return entries;
  }

  // Skins 1v1: usa strokesReceivedFromOfficial18Sliding (igual que skinsScorecard).
  // Itera en el orden real de la ronda (startingNine) para que el carry-over
  // no se acumule en hoyos pending del segmento no iniciado.
  static List<LedgerEntry> _skins1v1(Round round, String p1Id, String p2Id, BetModuleInstance mod) {
    final entries = <LedgerEntry>[];
    final cfg = mod.skins;
    // Valor pactado para ESTE duelo: respeta la excepción por par si la hay
    // (pairConfigOverrides), si no usa el valor base del módulo.
    final skinValue = mod.effectiveValueForDuel(p1Id, p2Id).$1;
    double pot = skinValue;

    final recv = _strokesP1ReceivesFromP2(round, p1Id, p2Id);
    // El receptor es quien recibe strokes positivos
    final p1Receives = recv > 0;
    final baseId      = p1Receives ? p2Id : p1Id;
    final receiverId  = p1Receives ? p1Id : p2Id;
    final recvAbs     = recv.abs().round();
    final allHoles    = round.course.holes;

    // Hoyos del CURSO (no jugados) en F9 y B9 — para distribución de SI correcta
    // independientemente de cuántos hoyos se hayan jugado ya.
    final (courseF9skins, courseB9skins) =
        _courseHolesF9B9(allHoles, round.startingNine);

    // Iterar en orden real de la ronda para un carry correcto.
    // Usar hoyos reales del curso (igual que _nassauPair) para evitar null en
    // cursos de 9 hoyos.
    final holeMap = { for (final ch in allHoles) ch.hole: ch };
    final List<int> holeOrder;
    if (round.startingNine == StartingNine.back) {
      final b9 = allHoles.where((c) => c.hole >= 10).map((c) => c.hole).toList()..sort();
      final f9 = allHoles.where((c) => c.hole <= 9).map((c) => c.hole).toList()..sort();
      holeOrder = [...b9, ...f9];
    } else {
      holeOrder = allHoles.map((c) => c.hole).toList()..sort();
    }

    for (final h in holeOrder) {
      final ch = holeMap[h]!;
      final sBase     = round.getScore(baseId,     h);
      final sReceiver = round.getScore(receiverId, h);

      // Hoyo no jugado aún: se salta sin acumular carry
      // (el carry solo se acumula cuando el hoyo es JUGADO y resulta en empate)
      if (!sBase.hasScore || !sReceiver.hasScore) continue;

      // Distribuir strokes por vuelta usando el sliding oficial de 18 hoyos.
      // Usar hoyos del CURSO (no solo jugados) para que el share se distribuya
      // correctamente sobre los 9 hoyos de la vuelta, incluso en rondas parciales.
      final courseHolesForHole = courseF9skins.any((hh) => hh.hole == ch.hole)
          ? courseF9skins
          : courseB9skins;
      final strokesHere = mod.useHandicap && recvAbs > 0
          ? GameEngine.strokesReceivedFromOfficial18Sliding(
              diff18:              recvAbs,
              ch:                  ch,
              courseHolesInSameNine: courseHolesForHole,
              startingNine:        round.startingNine,
              isNineHolesStartingNine: BetEngine.isNineStartingNine(ch: ch, courseF9: courseF9skins, courseB9: courseB9skins, startingNine: round.startingNine),
            )
          : 0;

      final grossBase     = sBase.grossScore!;
      final netReceiver   = sReceiver.grossScore! - strokesHere;

      String? winner;
      if      (grossBase < netReceiver) {
        winner = baseId;
      } else if (grossBase > netReceiver) winner = receiverId;
      // else tie → pot lleva el carry

      if (winner != null) {
        final loser = winner == p1Id ? p2Id : p1Id;
        entries.add(LedgerEntry(
          fromPlayerId: loser, toPlayerId: winner,
          amount: pot, betType: BetModuleType.skins,
          reason: 'Skins H$h', hole: h,
        ));
        pot = skinValue;
      } else {
        // Empate en hoyo jugado → acumular carry
        if (cfg.carryOver) pot += skinValue;
      }
    }
    return entries;
  }

  // ── NASSAU ────────────────────────────────────────────────────────────────
  // Nassau ya es siempre por pares (allVsAll por naturaleza).
  // onePot: también pares, pero se suma al mismo ledger como grupo.
  static List<LedgerEntry> _nassau(Round round, List<String> pids, BetModuleInstance mod) {
    final entries = <LedgerEntry>[];
    for (int i = 0; i < pids.length; i++) {
      for (int j = i + 1; j < pids.length; j++) {
        entries.addAll(_nassauPair(round, pids[i], pids[j], mod));
      }
    }
    return entries;
  }

  static List<LedgerEntry> _nassauPair(Round round, String p1Id, String p2Id, BetModuleInstance mod) {
    // Si las presiones están activas, usar el motor completo de press
    if (mod.nassau.pressEnabled) {
      return _nassauPressPair(round, p1Id, p2Id, mod);
    }

    final entries = <LedgerEntry>[];
    final cfg = mod.nassau;
    int front = 0, back = 0;

    final recv = _strokesP1ReceivesFromP2(round, p1Id, p2Id);
    // p1IsBase = p1 da strokes (recv<=0 desde perspectiva p1)
    final p1IsBase    = recv <= 0;
    final baseId      = p1IsBase ? p1Id : p2Id;
    final receiverId  = p1IsBase ? p2Id : p1Id;
    final recvAbs     = recv.abs().round();
    final allHoles = round.course.holes;

    final holeMap = { for (final ch in allHoles) ch.hole: ch };

    // Hoyos del CURSO (no jugados) en F9 y B9 — distribución de SI correcta
    final (courseF9nassau, courseB9nassau) =
        _courseHolesF9B9(allHoles, round.startingNine);

    // Segmentación lógica: el primer segmento jugado es siempre "Front",
    // aunque sus hoyos se numeren 10-18. Ver BetEngine.segmentsOf.
    final seg       = segmentsOf(round);
    final holeOrder = seg.playOrder;

    for (final h in holeOrder) {
      final ch = holeMap[h]!;
      final sBase     = round.getScore(baseId,     h);
      final sReceiver = round.getScore(receiverId, h);
      if (!sBase.hasScore || !sReceiver.hasScore) continue;

      final courseHolesForHoleN = courseF9nassau.any((hh) => hh.hole == ch.hole)
          ? courseF9nassau : courseB9nassau;
      final strokesHere = mod.useHandicap && recvAbs > 0
          ? GameEngine.strokesReceivedFromOfficial18Sliding(
              diff18:              recvAbs,
              ch:                  ch,
              courseHolesInSameNine: courseHolesForHoleN,
              startingNine:        round.startingNine,
              isNineHolesStartingNine: BetEngine.isNineStartingNine(ch: ch, courseF9: courseF9nassau, courseB9: courseB9nassau, startingNine: round.startingNine),
            )
          : 0;

      final grossBase   = sBase.grossScore!;
      final netReceiver = sReceiver.grossScore! - strokesHere;

      final int delta;
      if      (grossBase < netReceiver) {
        delta = p1IsBase ? 1 : -1;
      } else if (grossBase > netReceiver) delta = p1IsBase ? -1 : 1;
      else                              delta = 0;

      // Segmentación LÓGICA: el primer segmento jugado es siempre "front",
      // independientemente de si los números de hoyo son 1-9 ó 10-18.
      if (seg.isFirst(h)) {
        front += delta;
      } else {
        back  += delta;
      }
    }

    final total = front + back;
    if (seg.singleNine) {
      _addNassauSegment(entries, p1Id, p2Id, front, cfg.frontValue, 'Nassau 9 hoyos');
    } else {
      _addNassauSegment(entries, p1Id, p2Id, front, cfg.frontValue,          'Nassau Front 9');
      _addNassauSegment(entries, p1Id, p2Id, back,  cfg.effectiveBackValue,  'Nassau Back 9');
      _addNassauSegment(entries, p1Id, p2Id, total, cfg.effectiveTotalValue, 'Nassau Total 18');
    }
    return entries;
  }

  static void _addNassauSegment(
    List<LedgerEntry> entries, String p1Id, String p2Id,
    int margin, double value, String label,
  ) {
    if (margin > 0) {
      entries.add(LedgerEntry(fromPlayerId: p2Id, toPlayerId: p1Id, amount: value, betType: BetModuleType.nassau, reason: label));
    } else if (margin < 0) {
      entries.add(LedgerEntry(fromPlayerId: p1Id, toPlayerId: p2Id, amount: value, betType: BetModuleType.nassau, reason: label));
    }
  }

  // ── NASSAU + PRESS ────────────────────────────────────────────────────────
  // Nassau F9/B9/Total18 con presiones automáticas por segmento.
  // Las presiones de un segmento terminan al finalizar ese segmento.
  // Carry: si el F9 termina en empate (push) y carryEnabled, el B9 vale x2.
  static List<LedgerEntry> _nassauPressPair(
      Round round, String p1Id, String p2Id, BetModuleInstance mod) {
    final entries = <LedgerEntry>[];
    // Usa la config unificada de NassauConfig (pressEnabled garantizado true aquí)
    final cfg = mod.nassau;

    final recv = _strokesP1ReceivesFromP2(round, p1Id, p2Id);
    final p1IsBase    = recv <= 0;
    final baseId      = p1IsBase ? p1Id : p2Id;
    final receiverId  = p1IsBase ? p2Id : p1Id;
    final recvAbs     = recv.abs().round();
    final allHoles    = round.course.holes;

    // Hoyos del CURSO (no jugados) en F9 y B9 — distribución de SI correcta
    final (courseF9press, courseB9press) =
        _courseHolesF9B9(allHoles, round.startingNine);

    // ── Segmentos lógicos de la ronda (ver BetEngine.segmentsOf) ─────────────
    final seg = segmentsOf(round);

    // ── Calcular deltas hoyo a hoyo ──────────────────────────────────────────
    final Map<int, int> deltaByHole = {};
    for (final ch in allHoles) {
      final h = ch.hole;
      final sBase     = round.getScore(baseId, h);
      final sReceiver = round.getScore(receiverId, h);
      if (!sBase.hasScore || !sReceiver.hasScore) continue;
      final courseHolesForPress = courseF9press.any((hh) => hh.hole == ch.hole)
          ? courseF9press : courseB9press;
      final strokes = mod.useHandicap && recvAbs > 0
          ? GameEngine.strokesReceivedFromOfficial18Sliding(
              diff18:              recvAbs,
              ch:                  ch,
              courseHolesInSameNine: courseHolesForPress,
              startingNine:        round.startingNine,
              isNineHolesStartingNine: BetEngine.isNineStartingNine(ch: ch, courseF9: courseF9press, courseB9: courseB9press, startingNine: round.startingNine),
            )
          : 0;
      final grossBase    = sBase.grossScore!;
      final netReceiver  = sReceiver.grossScore! - strokes;
      if      (grossBase < netReceiver) {
        deltaByHole[h] = p1IsBase ?  1 : -1;
      } else if (grossBase > netReceiver) deltaByHole[h] = p1IsBase ? -1 :  1;
      else                              deltaByHole[h] = 0;
    }

    // ── Detectar carry (primer segmento empatado) ────────────────────────────
    int front = 0;
    for (final h in seg.firstNine) {
      front += (deltaByHole[h] ?? 0);
    }
    // carryEnabled ahora está en NassauConfig
    final carryActive = cfg.carryEnabled && cfg.carryApplied && front == 0;

    // ── Liquidar segmento con presiones ─────────────────────────────────────
    // [holes] son los hoyos REALES del segmento en orden de juego (no un rango
    // numérico), para que funcione con campos de 9 hoyos y numeración invertida.
    void liquidateSegment({
      required List<int> holes,
      required double segValue,
      required double pressValue,
      required String segLabel,
    }) {
      if (holes.isEmpty) return;
      final holeTo = holes.last;

      // Score acumulado hoyo a hoyo dentro del segmento
      final List<int> history = [];
      for (final h in holes) {
        final prev = history.isEmpty ? 0 : history.last;
        history.add(prev + (deltaByHole[h] ?? 0));
      }
      if (history.isEmpty) return;

      // Score final del segmento
      final segScore = history.last;

      // Detectar presiones automáticas.
      // Regla: una presión se dispara cuando el marcador RELATIVO al último punto
      // de referencia (inicio del segmento o inicio de la última presión) alcanza
      // el trigger. Así evitamos disparar múltiples presiones en el mismo "bache".
      final int maxP = cfg.maxPresses ?? 99;
      final List<({int startIdx, int startHole})> pressStarts = [];

      // refIdx: índice en history desde donde medimos el marcador relativo.
      // Al inicio es 0 (el segmento entero); después de cada press se actualiza
      // al idx del hoyo que disparó esa press.
      int refIdx = 0;
      for (int i = 0; i < history.length; i++) {
        if (pressStarts.length >= maxP) break;
        // Marcador relativo desde el último punto de referencia
        final relDiff = history[i] - (refIdx == 0 ? 0 : history[refIdx - 1]);
        if (relDiff.abs() >= cfg.autoPressTrigger) {
          // La press empieza en el hoyo SIGUIENTE dentro del mismo segmento
          if (i + 1 < holes.length) {
            final startH = holes[i + 1];
            if (cfg.allowMultiplePresses || pressStarts.isEmpty) {
              pressStarts.add((startIdx: i + 1, startHole: startH));
              refIdx = i + 1; // mover referencia al hoyo que disparó la press
            }
          }
        }
      }

      // Liquidar segmento base
      void addEntry(int score, double val, String label) {
        if (score > 0) {
          entries.add(LedgerEntry(fromPlayerId: p2Id, toPlayerId: p1Id,
              amount: val, betType: BetModuleType.nassau, reason: label));
        } else if (score < 0) {
          entries.add(LedgerEntry(fromPlayerId: p1Id, toPlayerId: p2Id,
              amount: val, betType: BetModuleType.nassau, reason: label));
        }
      }

      addEntry(segScore, segValue, segLabel);

      // Liquidar cada presión.
      // Cada press cierra cuando empieza la SIGUIENTE press,
      // no al final del segmento. El label refleja el tramo real liquidado.
      for (int k = 0; k < pressStarts.length; k++) {
        final ps = pressStarts[k];
        // Endpoint: inicio de la siguiente press (exclusive) o fin del segmento.
        final endIdx = (k + 1 < pressStarts.length)
            ? pressStarts[k + 1].startIdx - 1
            : history.length - 1;
        final pressScore = history[endIdx] - history[ps.startIdx - 1];
        // endHole real: history[i] corresponde a holes[i]
        final endHole = holes[endIdx];
        addEntry(pressScore, pressValue,
            'Press H${ps.startHole}–H$endHole ($segLabel)');
      }

      // Presiones manuales del módulo (no son match principal, en rango del segmento)
      for (final press in mod.presses) {
        if (press.isPrimaryMatch) continue; // solo presiones, no el match principal
        final startIdx = holes.indexOf(press.startHole);
        if (startIdx < 0) continue; // la press no pertenece a este segmento
        int manualScore = 0;
        for (int i = startIdx; i < holes.length; i++) {
          manualScore += (deltaByHole[holes[i]] ?? 0);
        }
        addEntry(manualScore, press.value,
            'Press Manual H${press.startHole}–H$holeTo ($segLabel)');
      }
    }

    // ── Aplicar segmentos ────────────────────────────────────────────────────
    if (seg.singleNine) {
      // Solo 9 hoyos: un único segmento con los hoyos reales de la vuelta
      liquidateSegment(
        holes:      seg.firstNine,
        segValue:   cfg.frontValue,
        pressValue: cfg.frontPressValue,
        segLabel:   'Nassau 9H',
      );
    } else {
      // Primer segmento (lógicamente "Front 9")
      liquidateSegment(
        holes:      seg.firstNine,
        segValue:   cfg.frontValue,
        pressValue: cfg.frontPressValue,
        segLabel:   'Nassau Front 9',
      );
      // Segundo segmento (lógicamente "Back 9", con carry si aplica)
      final effBack      = carryActive ? cfg.backValue      * cfg.carryFactor : cfg.backValue;
      final effBackPress = carryActive ? cfg.backPressValue * cfg.carryFactor : cfg.backPressValue;
      liquidateSegment(
        holes:      seg.secondNine,
        segValue:   effBack,
        pressValue: effBackPress,
        segLabel:   'Nassau Back 9${carryActive ? ' (x${cfg.carryFactor.toStringAsFixed(0)})' : ''}',
      );
      // Total 18: suma todos los deltas disponibles
      int total = 0;
      for (final delta in deltaByHole.values) {
        total += delta;
      }
      final effTotal = carryActive ? cfg.totalValue * cfg.carryFactor : cfg.totalValue;
      void addTotal(int score, double val) {
        if (score > 0) {
          entries.add(LedgerEntry(fromPlayerId: p2Id, toPlayerId: p1Id,
              amount: val, betType: BetModuleType.nassau, reason: 'Nassau Total 18'));
        } else if (score < 0) {
          entries.add(LedgerEntry(fromPlayerId: p1Id, toPlayerId: p2Id,
              amount: val, betType: BetModuleType.nassau, reason: 'Nassau Total 18'));
        }
      }
      addTotal(total, effTotal);
    }

    return entries;
  }

  // ── MEDAL ─────────────────────────────────────────────────────────────────
  // Regla: menor net total gana.
  // Net = suma hoyo a hoyo de (gross − strokes_recibidos_en_ese_hoyo).
  // Strokes recibidos: PRIORIDAD MANUAL > HCP diff.
  //   Si hay manual entre A y B → esos son los strokes del par (ignora HCP).
  //   Si no hay manual → diferencia de HCP como fallback.
  //
  // allVsAll : cada par es independiente; ambos computan net vs el otro.
  // onePot   : se necesita una escala común → se elige el "ancla" del grupo
  //            (el que más da / menos recibe según los manuales del grupo),
  //            y cada jugador calcula su net respecto al ancla.
  static List<LedgerEntry> _medal(Round round, List<String> pids, BetModuleInstance mod) {
    final entries = <LedgerEntry>[];  
    final cfg     = mod.medal;
    final allHoles = round.course.holes;

    // Net de pA respecto a pB: gross(pA) - strokes_que_pA_recibe_de_pB por hoyo.
    // useHandicap=false → net = gross bruto.
    //
    // REGLA DE DISTRIBUCIÓN (pairSliding oficial de 18 hoyos):
    // El pairSliding es el valor oficial de 18 hoyos; se divide entre F9 y B9
    // con ceil/floor según startingNine, y dentro de cada vuelta se distribuye
    // solo entre los hoyos efectivamente jugados.
    int netVs(String pA, String pB) {
      // Caso explícito: auto-comparación — el net es el gross bruto (sin ventajas).
      // Ocurre cuando el ancla se compara contra sí misma en onePot N>2.
      if (pA == pB) return GameEngine.grossTotal(round, pA);
      if (!mod.useHandicap) return GameEngine.grossTotal(round, pA);
      final recv = _strokesP1ReceivesFromP2(round, pA, pB); // cuánto recibe pA de pB
      int net = 0;
      if (recv <= 0) {
        // pA da strokes (o sin ventaja): su net es su bruto
        final playedHoles = allHoles.where((ch) => round.getScore(pA, ch.hole).hasScore).toList();
        for (final ch in playedHoles) {
          net += round.getScore(pA, ch.hole).grossScore!;
        }
        return net;
      }
      final diff18 = recv.round();
      // Hoyos del CURSO en F9/B9 (no filtrados por jugados) — distribución SI correcta
      final (courseF9medal, courseB9medal) = _courseHolesF9B9(allHoles, round.startingNine);
      // Iterar solo hoyos efectivamente jugados, pero con SI del curso completo
      final playedHoles = allHoles.where((ch) => round.getScore(pA, ch.hole).hasScore).toList();
      for (final ch in playedHoles) {
        final score = round.getScore(pA, ch.hole);
        final courseHolesForMedal = courseF9medal.any((hh) => hh.hole == ch.hole)
            ? courseF9medal : courseB9medal;
        final strokes = GameEngine.strokesReceivedFromOfficial18Sliding(
          diff18: diff18,
          ch: ch,
          courseHolesInSameNine: courseHolesForMedal,
          startingNine:        round.startingNine,
          isNineHolesStartingNine: BetEngine.isNineStartingNine(ch: ch, courseF9: courseF9medal, courseB9: courseB9medal, startingNine: round.startingNine),
        );
        net += score.grossScore! - strokes;
      }
      return net;
    }

    // ── allVsAll ──────────────────────────────────────────────────────────────
    // Cada par se resuelve de forma bilateral e independiente.
    if (mod.isAllVsAll) {
      for (int i = 0; i < pids.length; i++) {
        for (int j = i + 1; j < pids.length; j++) {
          final netI = netVs(pids[i], pids[j]);
          final netJ = netVs(pids[j], pids[i]);
          if (netI < netJ) {
            entries.add(LedgerEntry(fromPlayerId: pids[j], toPlayerId: pids[i], amount: cfg.value, betType: BetModuleType.medal, reason: 'Medal'));
          } else if (netJ < netI) {
            entries.add(LedgerEntry(fromPlayerId: pids[i], toPlayerId: pids[j], amount: cfg.value, betType: BetModuleType.medal, reason: 'Medal'));
          }
        }
      }
      return entries;
    }

    // ── onePot (1v1 o N jugadores, un solo ganador) ───────────────────────────
    // Sin handicap: net = gross.
    if (!mod.useHandicap) {
      final nets = { for (final p in pids) p: GameEngine.grossTotal(round, p) };
      final sorted = pids.toList()..sort((a, b) => nets[a]!.compareTo(nets[b]!));
      if (nets[sorted[0]] == nets[sorted[1]]) return entries; // empate
      final winner = sorted.first;
      for (final pid in sorted.skip(1)) {
        entries.add(LedgerEntry(fromPlayerId: pid, toPlayerId: winner, amount: cfg.value, betType: BetModuleType.medal, reason: 'Medal'));
      }
      return entries;
    }

    // Con handicap / manuals:
    // 1v1: bilateral (A vs B, B vs A) → nets comparables.
    // N>2: elegir ancla = el jugador que más da al grupo (menor ventaja recibida).
    //      Net de cada jugador = netVs(jugador, ancla).
    final nets = <String, int>{};
    if (pids.length == 2) {
      nets[pids[0]] = netVs(pids[0], pids[1]);
      nets[pids[1]] = netVs(pids[1], pids[0]);
    } else {
      // Ancla = jugador que, en la suma de acuerdos bilaterales del grupo,
      // da más y recibe menos. Si hay empate de ventaja, usar HCP más bajo.
      final ancla = groupAnchor(round, pids);
      for (final pid in pids) {
        nets[pid] = netVs(pid, ancla);
      }
    }

    final sorted = pids.toList()..sort((a, b) => (nets[a] ?? 999).compareTo(nets[b] ?? 999));
    if ((nets[sorted[0]] ?? 999) == (nets[sorted[1]] ?? 999)) return entries; // empate
    final winner = sorted.first;
    for (final pid in sorted.skip(1)) {
      entries.add(LedgerEntry(fromPlayerId: pid, toPlayerId: winner, amount: cfg.value, betType: BetModuleType.medal, reason: 'Medal'));
    }
    return entries;
  }

  // ── PUTTS ─────────────────────────────────────────────────────────────────
  // onePot  : winner del segmento cobra a todos.
  // allVsAll: cada par tiene su propio resultado en cada segmento.
  static List<LedgerEntry> _putts(Round round, List<String> pids, BetModuleInstance mod) {
    final entries = <LedgerEntry>[];
    final cfg = mod.putts;

    final segs = cfg.puttsMode == PuttsMode.total
        ? [(1, 18, 'Putts Total')]
        : [(1, 9, 'Putts F9'), (10, 18, 'Putts B9')];

    if (mod.isAllVsAll) {
      // allVsAll: cada par (A, B) es completamente independiente.
      // El que menos putts totales tenga en el segmento, gana el duelo directo.
      // No se filtra por 0 putts: 0 puede ser un dato válido (ej. chip-in).
      for (final seg in segs) {
        final (from, to, label) = seg;
        for (int i = 0; i < pids.length; i++) {
          for (int j = i + 1; j < pids.length; j++) {
            final t1 = GameEngine.totalPutts(round, pids[i], from: from, to: to);
            final t2 = GameEngine.totalPutts(round, pids[j], from: from, to: to);
            if (t1 < t2) {
              entries.add(LedgerEntry(fromPlayerId: pids[j], toPlayerId: pids[i], amount: cfg.value, betType: BetModuleType.putts, reason: label));
            } else if (t2 < t1) {
              entries.add(LedgerEntry(fromPlayerId: pids[i], toPlayerId: pids[j], amount: cfg.value, betType: BetModuleType.putts, reason: label));
            }
            // empate → no se añade entrada
          }
        }
      }
      return entries;
    }

    // onePot: el jugador con menos putts totales en el segmento cobra a todos.
    // El que menos haga gana; empate → sin resultado.
    for (final seg in segs) {
      final (from, to, label) = seg;
      if (pids.length < 2) continue;
      final totals = { for (final pid in pids) pid: GameEngine.totalPutts(round, pid, from: from, to: to) };
      final sorted = pids.toList()..sort((a, b) => totals[a]!.compareTo(totals[b]!));
      if (totals[sorted[0]] == totals[sorted[1]]) continue; // empate
      final winner = sorted.first;
      for (final pid in sorted.skip(1)) {
        entries.add(LedgerEntry(fromPlayerId: pid, toPlayerId: winner, amount: cfg.value, betType: BetModuleType.putts, reason: label));
      }
    }
    return entries;
  }

  // ── OYESES ────────────────────────────────────────────────────────────────
  static List<LedgerEntry> _oyeses(Round round, List<String> pids, BetModuleInstance mod) {
    final entries = <LedgerEntry>[];
    final cfg        = mod.oyeses;
    final isAllVsAll = mod.isAllVsAll; // onePot vs allVsAll

    final par3Holes = round.course.holes.where((h) => h.isPar3).toList();

    // Filtrar por hoyos elegibles
    final eligible = cfg.eligibleHoles.isNotEmpty
        ? par3Holes.where((h) => cfg.eligibleHoles.contains(h.hole)).toList()
        : par3Holes;

    final totalEligible = eligible.length;

    // ── Estructuras para zapato ────────────────────────────────────────────
    // onePot  → firstPlaceCount[pid]: cuántos oyeses fue PRIMERO absoluto
    // allVsAll → winsVs[A][B]: cuántos oyeses A quedó por delante de B
    final Map<String, int> firstPlaceCount = { for (final p in pids) p: 0 };
    final Map<String, Map<String, int>> winsVs = {
      for (final p in pids) p: { for (final q in pids) q: 0 },
    };
    int holesWithRanking = 0;

    // ── Cobros hoyo a hoyo ─────────────────────────────────────────────────
    for (final ch in eligible) {
      final ranking = round.getOyese(ch.hole);
      if (ranking == null || ranking.ranking.isEmpty) continue;
      final orderedPids = ranking.ranking.where((pid) => pids.contains(pid)).toList();
      if (orderedPids.length < 2) continue;

      holesWithRanking++;

      // 1° absoluto (para onePot zapato)
      firstPlaceCount[orderedPids[0]] = (firstPlaceCount[orderedPids[0]] ?? 0) + 1;

      // Cobros par a par y conteo para allVsAll zapato
      for (int i = 0; i < orderedPids.length - 1; i++) {
        for (int j = i + 1; j < orderedPids.length; j++) {
          final winner = orderedPids[i];
          final loser  = orderedPids[j];
          // Valor pactado para este duelo (excepción por par si la hay)
          final oyesValue = mod.effectiveValueForDuel(winner, loser).$1;
          entries.add(LedgerEntry(
            fromPlayerId: loser, toPlayerId: winner,
            amount: oyesValue, betType: BetModuleType.oyeses,
            reason: 'Oyés H${ch.hole} (${i + 1}° vs ${j + 1}°)', hole: ch.hole,
          ));
          // allVsAll: acumular victorias de winner sobre loser
          winsVs[winner]![loser] = (winsVs[winner]![loser] ?? 0) + 1;
        }
      }
    }

    // ── Zapato ─────────────────────────────────────────────────────────────
    // REGLA:
    //   El zapato SIEMPRE requiere que se hayan completado TODOS los par-3
    //   elegibles del campo (holesWithRanking == totalEligible).
    //
    //   onePot   → Un solo zapato grupal: el jugador que fue 1° ABSOLUTO en
    //              todos los oyeses cobra a todos los demás.
    //              Monto = totalEligible × value (cobra a cada rival).
    //
    //   allVsAll → Zapato por par: para cada par (A, B), si A quedó por
    //              delante de B en TODOS los oyeses → A hace zapato vs B.
    //              Monto = totalEligible × value (por cada par afectado).
    //              Pueden ocurrir varios zapatos simultáneos.
    //
    //   zapatoRequires18 = true → además exige campo con 3+ par-3s.
    if (cfg.zapatoEnabled && holesWithRanking >= 1) {
      final allPlayed   = holesWithRanking == totalEligible;
      final enoughHoles = cfg.zapatoRequires18 ? (totalEligible >= 3) : true;

      if (allPlayed && enoughHoles) {
        final zapatoAmt = cfg.zapatoAmount(totalEligible);

        if (!isAllVsAll) {
          // ── 1 Pot: un solo zapato grupal ────────────────────────────────
          for (final pid in pids) {
            if ((firstPlaceCount[pid] ?? 0) == holesWithRanking) {
              for (final other in pids.where((p) => p != pid)) {
                entries.add(LedgerEntry(
                  fromPlayerId: other, toPlayerId: pid,
                  amount: zapatoAmt, betType: BetModuleType.oyeses,
                  reason: '👟 Zapato 1Pot ($holesWithRanking oyeses)',
                ));
              }
              break; // un solo zapato posible en onePot
            }
          }
        } else {
          // ── Todos vs Todos: zapato por cada par (A, B) ──────────────────
          // A hace zapato vs B si quedó por delante de B en TODOS los oyeses.
          for (int i = 0; i < pids.length; i++) {
            for (int j = i + 1; j < pids.length; j++) {
              final a = pids[i];
              final b = pids[j];
              final aWinsVsB = winsVs[a]![b] ?? 0;
              final bWinsVsA = winsVs[b]![a] ?? 0;

              if (aWinsVsB == holesWithRanking) {
                // A le ganó todos los oyeses a B → zapato de A vs B
                entries.add(LedgerEntry(
                  fromPlayerId: b, toPlayerId: a,
                  amount: zapatoAmt, betType: BetModuleType.oyeses,
                  reason: '👟 Zapato AvA ($holesWithRanking oyeses)',
                ));
              } else if (bWinsVsA == holesWithRanking) {
                // B le ganó todos los oyeses a A → zapato de B vs A
                entries.add(LedgerEntry(
                  fromPlayerId: a, toPlayerId: b,
                  amount: zapatoAmt, betType: BetModuleType.oyeses,
                  reason: '👟 Zapato AvA ($holesWithRanking oyeses)',
                ));
              }
            }
          }
        }
      }
    }

    return entries;
  }

  // ── UNITS ─────────────────────────────────────────────────────────────────
  static List<LedgerEntry> _units(Round round, List<String> pids, BetModuleInstance mod) {
    final entries = <LedgerEntry>[];
    final cfg = mod.units;

    // Iterar sobre los hoyos reales del curso respetando startingNine.
    // Antes se usaba h=1..totalHoles, que fallaba cuando startingNine=back
    // porque los eventos estaban guardados en los hoyos físicos 10-18.
    final holeNums = round.course.holes.map((ch) => ch.hole).toList();

    for (final pid in pids) {
      for (final h in holeNums) {
        final evts = round.getEvents(pid, h);
        for (final evt in evts.where((e) => pids.contains(e.playerId))) {
          // Valor individual por evento — configurado en UnitsConfig
          final amount = cfg.valueFor(evt.type);
          for (final other in pids.where((p) => p != pid)) {
            // Excepción por duelo: en Units el override ('allEvents') fija un
            // valor único para todos los eventos de ese par.
            final pairAmount = mod.effectiveValueForDuel(pid, other).$1;
            final hasOverride = mod.overrideForPair(pid, other) != null;
            entries.add(LedgerEntry(
              fromPlayerId: other, toPlayerId: pid,
              amount: hasOverride ? pairAmount : amount,
              betType: BetModuleType.units,
              reason: '${evt.type.label} H$h', hole: h,
            ));
          }
        }
      }
    }
    return entries;
  }


  // ══════════════════════════════════════════════════════════════════════════
  // MODO EQUIPO — lado A vs lado B (best-ball)
  // ══════════════════════════════════════════════════════════════════════════

  /// Importe de CADA entrada cruzada jugador↔jugador en un duelo por equipos.
  ///
  /// Un duelo por equipos vale lo configurado EN TOTAL: se comporta igual que
  /// un jugador contra otro. Un Nassau F$50 entre dos parejas mueve $50 en el
  /// Front, no $200.
  ///
  /// Como el ledger solo sabe mover dinero entre jugadores, el importe se
  /// reparte en las |A|×|B| entradas cruzadas. Así:
  ///   • cada miembro del lado ganador recibe  value / |ganadores|
  ///   • cada miembro del lado perdedor paga   value / |perdedores|
  ///   • el total movido es exactamente        value
  /// y funciona también con lados de distinto tamaño (2 vs 3).
  static double teamCrossAmount(double value, int sizeA, int sizeB) {
    final pairs = sizeA * sizeB;
    if (pairs <= 0) return 0;
    return value / pairs;
  }

  // ── Helper: deltas hoyo a hoyo entre dos lados (usa holeDeltaVs) ──────────
  // Devuelve (holeOrder, deltas[1..n]) igual que _buildHoleDeltas.
  // hcpMap: todos los jugadores de ambos lados, HCP de ronda directo.
  // En modo gross puede pasarse un mapa vacío (todos 0.0).
  static (List<int>, List<int>) _buildHoleDeltasTeam(
      Round round, BetSide sideA, BetSide sideB, BetModuleInstance mod) {
    final allPlayerIds = [...sideA.playerIds, ...sideB.playerIds];
    final hcpMap = mod.useHandicap
        ? GameEngine.buildTeamHcpMap(round, allPlayerIds, cfg: mod.teamHandicap)
        : <String, double>{};

    // Hoyos reales del curso en orden de juego (no un rango derivado de
    // totalHoles, que se queda en 9 si la ronda se extiende a 18).
    final holeOrder = segmentsOf(round).playOrder;

    // deltas[0] no se usa; índice 1-based
    final List<int> deltas = List.filled(holeOrder.length + 1, 0);

    for (int pos = 0; pos < holeOrder.length; pos++) {
      final h = holeOrder[pos];
      final delta = GameEngine.holeDeltaVs(
        round:        round,
        sideA:        sideA,
        sideB:        sideB,
        holeNum:      h,
        useHandicap:  mod.useHandicap,
        hcpMap:       hcpMap,
      );
      // null → hoyo no completado → delta queda 0 (no jugado)
      if (delta != null) deltas[pos + 1] = delta;
    }
    return (holeOrder, deltas);
  }

  // ── MATCH + AUTO PRESS (equipo) ───────────────────────────────────────────
  static List<LedgerEntry> _matchAutoPressTeam(Round round, BetModuleInstance mod) {
    final entries = <LedgerEntry>[];
    final sideA = mod.sideA;
    final sideB = mod.sideB;
    final cfg   = mod.matchAutoPress;

    // Carry factor: en equipo usamos valor de configuración directo (sin sliding bilateral)
    final matchValue = cfg.matchValue;
    final pressValue = cfg.pressValue;

    final hd        = _buildHoleDeltasTeam(round, sideA, sideB, mod);
    final holeOrder = hd.$1;
    final deltas    = hd.$2;

    final matches = _buildMatchTreeRoot(
      holeOrder:  holeOrder,
      deltas:     deltas,
      trigger:    cfg.pressTriggerValue,
      maxPresses: cfg.maxPresses ?? 99,
      matchValue: matchValue,
      pressValue: pressValue,
    );

    for (final m in matches) {
      int score  = 0;
      int played = 0;
      for (int pos = m.startPos; pos <= m.endPos && pos <= holeOrder.length; pos++) {
        score += deltas[pos];
        // Contar como jugado si el delta fue calculado (hoyo completo en ambos lados)
        if (deltas[pos] != 0) {
          played++;
        } else {
          // También contar hoyos empatados (delta=0) que sí se jugaron.
          // Basta con que CADA lado tenga al menos una bola anotada (best ball).
          final h = holeOrder[pos - 1];
          final aPlayed = sideA.playerIds.any((pid) => round.getScore(pid, h).hasScore);
          final bPlayed = sideB.playerIds.any((pid) => round.getScore(pid, h).hasScore);
          if (aPlayed && bPlayed) played++;
        }
      }
      if (played == 0) continue;
      // El match por equipos vale lo configurado en total (ver teamCrossAmount)
      final amount = teamCrossAmount(
          m.value, sideA.playerIds.length, sideB.playerIds.length);
      final label = '${m.businessLabel} H${holeOrder[m.startPos - 1]}–H${holeOrder[m.endPos.clamp(1, holeOrder.length) - 1]} (${sideA.name} vs ${sideB.name})';
      if (score > 0) {
        // sideA gana: sideB paga a sideA (cada jugador de B paga a cada jugador de A)
        for (final pA in sideA.playerIds) {
          for (final pB in sideB.playerIds) {
            entries.add(LedgerEntry(
              fromPlayerId: pB, toPlayerId: pA,
              amount: amount, betType: BetModuleType.matchAutoPress, reason: label,
            ));
          }
        }
      } else if (score < 0) {
        // sideB gana
        for (final pA in sideA.playerIds) {
          for (final pB in sideB.playerIds) {
            entries.add(LedgerEntry(
              fromPlayerId: pA, toPlayerId: pB,
              amount: amount, betType: BetModuleType.matchAutoPress, reason: label,
            ));
          }
        }
      }
    }
    return entries;
  }

  // ── NASSAU (equipo) ───────────────────────────────────────────────────────
  static List<LedgerEntry> _nassauTeam(Round round, BetModuleInstance mod) {
    final entries = <LedgerEntry>[];
    final sideA = mod.sideA;
    final sideB = mod.sideB;
    final cfg   = mod.nassau;

    final allPlayerIds = [...sideA.playerIds, ...sideB.playerIds];
    final hcpMap = mod.useHandicap
        ? GameEngine.buildTeamHcpMap(round, allPlayerIds, cfg: mod.teamHandicap)
        : <String, double>{};

    // Segmentación lógica: primer segmento jugado = "Front" (ver segmentsOf).
    final seg       = segmentsOf(round);
    final holeOrder = seg.playOrder;

    int front = 0, back = 0;

    for (final h in holeOrder) {
      final delta = GameEngine.holeDeltaVs(
        round: round, sideA: sideA, sideB: sideB,
        holeNum: h, useHandicap: mod.useHandicap, hcpMap: hcpMap,
      );
      if (delta == null) continue;
      if (seg.isFirst(h)) {
        front += delta;
      } else {
        back += delta;
      }
    }
    final total = front + back;

    void addSegment(int margin, double value, String label) {
      if (margin == 0) return;
      // El duelo por equipos vale lo configurado EN TOTAL: el lado que gana se
      // lleva `value` repartido entre sus miembros, igual que si fuera un
      // jugador contra otro. Ver [teamCrossAmount].
      final amount = teamCrossAmount(value, sideA.playerIds.length,
          sideB.playerIds.length);
      for (final pA in sideA.playerIds) {
        for (final pB in sideB.playerIds) {
          if (margin > 0) {
            entries.add(LedgerEntry(fromPlayerId: pB, toPlayerId: pA,
                amount: amount, betType: BetModuleType.nassau, reason: label));
          } else {
            entries.add(LedgerEntry(fromPlayerId: pA, toPlayerId: pB,
                amount: amount, betType: BetModuleType.nassau, reason: label));
          }
        }
      }
    }

    if (seg.singleNine) {
      addSegment(front, cfg.frontValue, 'Nassau 9 hoyos (${sideA.name} vs ${sideB.name})');
    } else {
      addSegment(front, cfg.frontValue,          'Nassau Front 9 (${sideA.name} vs ${sideB.name})');
      addSegment(back,  cfg.effectiveBackValue,  'Nassau Back 9 (${sideA.name} vs ${sideB.name})');
      addSegment(total, cfg.effectiveTotalValue, 'Nassau Total 18 (${sideA.name} vs ${sideB.name})');
    }
    return entries;
  }

  // ── BOLA BAJA / BOLA ALTA (2 vs 2) ────────────────────────────────────────
  //
  // Cada hoyo reparte hasta dos puntos, uno por categoría:
  //   • bola baja  → el MENOR score de cada equipo, comparados entre sí
  //   • bola alta  → el MAYOR score de cada equipo, comparados entre sí
  // Son independientes: un equipo puede llevarse las dos, repartirlas 1-1 o
  // empatar cualquiera.
  //
  // Los tres segmentos se recorren POR SEPARADO, cada uno con su propio estado
  // de acumulado. El Overall no es la suma de Front y Back: con carryover
  // activo, un punto acumulado expira al cerrar el Front pero sigue vivo en el
  // recorrido completo del Overall, así que los números pueden diferir.
  //
  // Se apoya en [segmentsOf] y no en los números de hoyo 1-9 / 10-18: una ronda
  // que arranca por el tee 10 tiene su primer segmento en los hoyos 10-18, y
  // partir por número invertiría Front y Back.
  /// Contexto compartido por la liquidación y el desglose de lectura.
  ///
  /// Devuelve la config, la segmentación de la ronda y el recorrido de hoyos.
  /// Existe para que ambos caminos partan del MISMO cálculo: si cada uno
  /// construyera el suyo, el marcador mostrado podría dejar de explicar el
  /// dinero cobrado sin que nada lo detectara.
  static (NassauLowHighConfig, RoundSegments, _LowHighTally Function(List<int>))
      _lowHighContext(Round round, BetModuleInstance mod) {
    final cfg   = mod.lowHigh;
    final sideA = mod.sideA;
    final sideB = mod.sideB;

    // El formato solo está definido para 2 vs 2: con tres jugadores por lado,
    // "la bola alta" es ambigua (¿el peor, o el segundo peor?). Se rechaza en
    // vez de elegir por el usuario; safeComputeAll lo reporta sin tumbar la ronda.
    if (sideA.playerIds.length != 2 || sideB.playerIds.length != 2) {
      throw StateError(
          'Bola Baja / Bola Alta requiere exactamente 2 jugadores por lado '
          '(${sideA.name}: ${sideA.playerIds.length}, '
          '${sideB.name}: ${sideB.playerIds.length})');
    }

    final allPlayerIds = [...sideA.playerIds, ...sideB.playerIds];
    final hcpMap = mod.useHandicap
        ? GameEngine.buildTeamHcpMap(round, allPlayerIds, cfg: mod.teamHandicap)
        : <String, double>{};

    // Score de un jugador en un hoyo, ya neto si aplica. null si no anotó.
    int? scoreOf(String pid, int holeNum) {
      final s = round.getScore(pid, holeNum);
      if (!s.hasScore) return null;
      if (!mod.useHandicap) return s.grossScore;
      final ch = round.course.holes.firstWhere((h) => h.hole == holeNum,
          orElse: () => round.course.holes.first);
      final hcp = hcpMap[pid] ?? round.getHandicap(pid);
      return s.grossScore! - GameEngine.strokesReceived(hcp, ch);
    }

    final segs = segmentsOf(round);

    // Recorre [holes] con estado de acumulado propio y devuelve los puntos.
    _LowHighTally walk(List<int> holes) {
      final tally = _LowHighTally();
      // Cuánto vale el punto de cada categoría en el próximo hoyo disputado.
      var lowCarry = 1.0;
      var highCarry = 1.0;

      for (final h in holes) {
        final a = sideA.playerIds.map((p) => scoreOf(p, h)).toList();
        final b = sideB.playerIds.map((p) => scoreOf(p, h)).toList();

        // Hoyo incompleto: no se disputa ninguna categoría y el acumulado se
        // mantiene intacto. Sin los cuatro scores no hay bola alta que comparar,
        // y dejar correr solo la baja repartiría el hoyo a medias.
        if (a.any((s) => s == null) || b.any((s) => s == null)) {
          // Se deja constancia igualmente: la pantalla de captura necesita
          // decir "este hoyo no cuenta todavía" y cuánto vale el punto que
          // sigue pendiente. No altera los puntos.
          tally.holes.add(LowHighHoleResult(
            hole: h, played: false,
            aScores: a.whereType<int>().toList()..sort(),
            bScores: b.whereType<int>().toList()..sort(),
            lowCarry: lowCarry, highCarry: highCarry,
          ));
          continue;
        }

        final aS = a.cast<int>()..sort();
        final bS = b.cast<int>()..sort();

        // Devuelve el nuevo valor del acumulado tras resolver la categoría.
        double resolve({
          required int aScore,
          required int bScore,
          required double carry,
          required bool carriesHere,
          required void Function(double) toA,
          required void Function(double) toB,
        }) {
          if (aScore < bScore) {
            toA(carry);
            return 1.0;
          }
          if (bScore < aScore) {
            toB(carry);
            return 1.0;
          }
          // Empate.
          switch (cfg.tieRule) {
            case LowHighTieRule.split:
              toA(carry / 2);
              toB(carry / 2);
              return 1.0;
            case LowHighTieRule.carryover:
              // Si el carryover no aplica a ESTA categoría se comporta como
              // "sin punto": nadie suma y el valor no crece.
              return carriesHere ? carry + 1 : 1.0;
            case LowHighTieRule.noPoint:
              return 1.0;
          }
        }

        // Valor del punto AL ENTRAR al hoyo: es lo que la UI anuncia como
        // "esta bola vale 2 puntos", y hay que capturarlo antes de resolver.
        final lowCarryAntes  = lowCarry;
        final highCarryAntes = highCarry;
        var lowA = 0.0, lowB = 0.0, highA = 0.0, highB = 0.0;

        lowCarry = resolve(
          aScore: aS.first, bScore: bS.first,
          carry: lowCarry, carriesHere: cfg.carriesLow,
          toA: (v) { tally.aLow += v; lowA = v; },
          toB: (v) { tally.bLow += v; lowB = v; },
        );
        highCarry = resolve(
          aScore: aS.last, bScore: bS.last,
          carry: highCarry, carriesHere: cfg.carriesHigh,
          toA: (v) { tally.aHigh += v; highA = v; },
          toB: (v) { tally.bHigh += v; highB = v; },
        );

        tally.holes.add(LowHighHoleResult(
          hole: h, played: true,
          aScores: aS, bScores: bS,
          lowCarry: lowCarryAntes, highCarry: highCarryAntes,
          lowPointsA: lowA, lowPointsB: lowB,
          highPointsA: highA, highPointsB: highB,
        ));
      }
      return tally;
    }

    return (cfg, segs, walk);
  }

  static List<LedgerEntry> _nassauLowHighTeam(Round round, BetModuleInstance mod) {
    final cfg = mod.lowHigh;
    // Sin ninguna modalidad activa no hay nada que cobrar. Se comprueba aquí y
    // no en el contexto porque el desglose SÍ tiene sentido mostrarlo: el
    // marcador existe aunque no se liquide dinero.
    if (!cfg.hasSettlement) return const [];

    final sideA = mod.sideA;
    final sideB = mod.sideB;
    final (_, segs, walk) = _lowHighContext(round, mod);
    final entries = <LedgerEntry>[];

    // Reparte [total] entre los cruces de ambos lados, igual que el Nassau por
    // equipos: lo configurado es el valor del duelo completo, no por jugador.
    void pay(double total, bool aWins, String reason) {
      if (total <= 0) return;
      final amount = teamCrossAmount(
          total, sideA.playerIds.length, sideB.playerIds.length);
      for (final pA in sideA.playerIds) {
        for (final pB in sideB.playerIds) {
          entries.add(LedgerEntry(
            fromPlayerId: aWins ? pB : pA,
            toPlayerId:   aWins ? pA : pB,
            amount: amount,
            betType: BetModuleType.nassauLowHigh,
            reason: reason,
          ));
        }
      }
    }

    // El reparto por segmentos vive en _lowHighSegments, que es exactamente la
    // misma fuente que consume la UI. Así el desglose que se muestra y el
    // dinero que se cobra no pueden desincronizarse: si divergieran, el
    // jugador vería un marcador que no explica lo que pagó.
    final vs = '${sideA.name} vs ${sideB.name}';
    for (final seg in _lowHighSegments(cfg, segs, walk)) {
      if (seg.isTie) continue; // segmento empatado: no se cobra nada
      final aWins = seg.diff > 0;
      if (seg.segmentAmount > 0) {
        pay(seg.segmentAmount, aWins, '${seg.label} ($vs)');
      }
      if (seg.pointAmount > 0) {
        final pts = seg.diff.abs();
        pay(seg.pointAmount, aWins,
            '${seg.label} · ${formatPoints(pts)} punto${pts == 1 ? "" : "s"} ($vs)');
      }
    }
    return entries;
  }

  /// Desglose por segmento de un módulo de Bola Baja / Bola Alta.
  ///
  /// Solo lectura: no genera asientos ni toca nada. Existe para que la UI pueda
  /// mostrar puntos y montos por segmento SIN recalcularlos por su cuenta —
  /// [_nassauLowHighTeam] consume este mismo resultado para liquidar.
  ///
  /// Lanza el mismo [StateError] que la liquidación si los lados no son 2 vs 2,
  /// así que conviene comprobar [BetModuleInstance.hasTeamSides] antes.
  static List<LowHighSegmentBreakdown> lowHighBreakdown(
      Round round, BetModuleInstance mod) {
    final (cfg, segs, walk) = _lowHighContext(round, mod);
    return _lowHighSegments(cfg, segs, walk);
  }

  /// Reparto de la ronda en segmentos liquidables, con sus puntos y montos.
  ///
  /// [walk] recorre una lista de hoyos y devuelve los puntos acumulados; se
  /// recibe como parámetro para que liquidación y desglose usen el MISMO
  /// recorrido, con su mismo estado de acumulado.
  static List<LowHighSegmentBreakdown> _lowHighSegments(
    NassauLowHighConfig cfg,
    RoundSegments segs,
    _LowHighTally Function(List<int>) walk,
  ) {
    LowHighSegmentBreakdown build({
      required String id,
      required String label,
      required List<int> holes,
      required double fixedAmount,
      required bool payPoints,
    }) {
      final tally = walk(holes);
      final tie = tally.diff == 0;
      return LowHighSegmentBreakdown(
        segment: id,
        label: label,
        holes: holes,
        aLow: tally.aLow, aHigh: tally.aHigh,
        bLow: tally.bLow, bHigh: tally.bHigh,
        // Los montos son los LIQUIDADOS: cero si el segmento quedó empatado o
        // si esa modalidad no aplica. Así la tabla suma lo mismo que el ledger.
        segmentAmount:
            (!tie && cfg.segmentBetEnabled && fixedAmount > 0) ? fixedAmount : 0,
        pointAmount: (!tie && payPoints && cfg.pointBetEnabled &&
                cfg.amountPerPoint > 0)
            ? tally.diff.abs() * cfg.amountPerPoint
            : 0,
        holeResults: tally.holes,
      );
    }

    // Ronda de 9 hoyos: Front y Overall cubrirían exactamente los mismos hoyos,
    // así que liquidar los dos sería cobrar dos veces lo mismo. Va uno solo.
    if (segs.singleNine) {
      if (!cfg.front9Enabled && !cfg.overallEnabled) return const [];
      return [
        build(
          id: 'nine',
          label: 'Bola Baja/Alta 9 hoyos',
          holes: segs.firstNine,
          fixedAmount: cfg.amountForFront(),
          payPoints: cfg.pointsOnHalves || cfg.pointsOnOverall,
        )
      ];
    }

    return [
      if (cfg.front9Enabled)
        build(
          id: 'front9', label: 'Bola Baja/Alta Front 9',
          holes: segs.firstNine,
          fixedAmount: cfg.amountForFront(), payPoints: cfg.pointsOnHalves,
        ),
      if (cfg.back9Enabled)
        build(
          id: 'back9', label: 'Bola Baja/Alta Back 9',
          holes: segs.secondNine,
          fixedAmount: cfg.amountForBack(), payPoints: cfg.pointsOnHalves,
        ),
      if (cfg.overallEnabled)
        build(
          id: 'overall', label: 'Bola Baja/Alta Overall',
          holes: segs.playOrder,
          fixedAmount: cfg.amountForOverall(), payPoints: cfg.pointsOnOverall,
        ),
    ];
  }

  /// Formatea puntos evitando el ".0" cuando son enteros — con la regla de
  /// empate "dividir" pueden salir medios puntos.
  ///
  /// Pública para que la UI use la MISMA convención que las descripciones de
  /// los asientos: 1.5 se muestra como 1.5, y 2 como 2.
  static String formatPoints(double p) =>
      p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(1);

  // ── SKINS (equipo best-ball por hoyo) ─────────────────────────────────────
  static List<LedgerEntry> _skinsTeam(Round round, BetModuleInstance mod) {
    final entries = <LedgerEntry>[];
    final sideA = mod.sideA;
    final sideB = mod.sideB;
    final cfg   = mod.skins;
    double pot  = cfg.valuePerSkin;

    final allPlayerIds = [...sideA.playerIds, ...sideB.playerIds];
    final hcpMap = mod.useHandicap
        ? GameEngine.buildTeamHcpMap(round, allPlayerIds, cfg: mod.teamHandicap)
        : <String, double>{};

    final holeOrder = segmentsOf(round).playOrder;

    for (final h in holeOrder) {
      final delta = GameEngine.holeDeltaVs(
        round: round, sideA: sideA, sideB: sideB,
        holeNum: h, useHandicap: mod.useHandicap, hcpMap: hcpMap,
      );
      if (delta == null) continue; // hoyo no completado

      if (delta != 0) {
        final winners = delta > 0 ? sideA.playerIds : sideB.playerIds;
        final losers  = delta > 0 ? sideB.playerIds : sideA.playerIds;
        // La skin del hoyo vale `pot` EN TOTAL para el lado ganador
        // (ver teamCrossAmount). Antes solo se dividía entre perdedores, así
        // que en 2v2 se movía el doble de lo configurado.
        final share   = teamCrossAmount(pot, winners.length, losers.length);
        for (final w in winners) {
          for (final l in losers) {
            entries.add(LedgerEntry(
              fromPlayerId: l, toPlayerId: w,
              amount: share, betType: BetModuleType.skins,
              reason: 'Skins H$h (${sideA.name} vs ${sideB.name})', hole: h,
            ));
          }
        }
        pot = cfg.valuePerSkin;
      } else {
        // Empate — carry-over si está configurado
        if (cfg.carryOver) pot += cfg.valuePerSkin;
      }
    }
    return entries;
  }

  // ── MATCH AUTO PRESS LIVE (equipo) ────────────────────────────────────────
  static List<MatchPressLiveStatus> matchAutoPressLiveTeam(
      Round round, BetModuleInstance mod) {
    final sideA = mod.sideA;
    final sideB = mod.sideB;
    final cfg   = mod.matchAutoPress;

    final hd        = _buildHoleDeltasTeam(round, sideA, sideB, mod);
    final holeOrder = hd.$1;
    final deltas    = hd.$2;

    // Último hoyo jugado
    int lastPlayedPos = 0;
    for (int pos = 1; pos <= holeOrder.length; pos++) {
      final h = holeOrder[pos - 1];
      final allPlayed = [...sideA.playerIds, ...sideB.playerIds]
          .every((pid) => round.getScore(pid, h).hasScore);
      if (allPlayed && pos > lastPlayedPos) lastPlayedPos = pos;
    }
    final lastPlayedHole = lastPlayedPos > 0 ? holeOrder[lastPlayedPos - 1] : 0;

    final matches = _buildMatchTreeRoot(
      holeOrder:  holeOrder,
      deltas:     deltas,
      trigger:    cfg.pressTriggerValue,
      maxPresses: cfg.maxPresses ?? 99,
      matchValue: cfg.matchValue,
      pressValue: cfg.pressValue,
    );

    final idA = sideA.playerIds.first;
    final idB = sideB.playerIds.first;

    final results = <MatchPressLiveStatus>[];
    for (final m in matches) {
      int score = 0, played = 0;
      for (int pos = m.startPos; pos <= m.endPos && pos <= holeOrder.length; pos++) {
        score += deltas[pos];
        if (deltas[pos] != 0) {
          played++;
        } else {
          final h = holeOrder[pos - 1];
          final allPlayed = [...sideA.playerIds, ...sideB.playerIds]
              .every((pid) => round.getScore(pid, h).hasScore);
          if (allPlayed) played++;
        }
      }
      final startHole = holeOrder[m.startPos - 1];
      final endIdx    = (m.endPos - 1).clamp(0, holeOrder.length - 1);
      final endHole   = holeOrder[endIdx];
      results.add(MatchPressLiveStatus(
        sequenceNumber: m.seq,
        isPrimaryMatch: m.isPrimary,
        startHole:      startHole,
        endHole:        endHole,
        score:          score,
        played:         played,
        value:          m.value,
        leadingPlayerId: score > 0 ? idA : score < 0 ? idB : null,
        lastHole:       lastPlayedHole,
      ));
    }
    return results;
  }

  // ── NASSAU LIVE STATUS (equipo) ───────────────────────────────────────────
  static NassauLiveStatus nassauLiveStatusTeam(Round round, BetModuleInstance mod) {
    final sideA = mod.sideA;
    final sideB = mod.sideB;
    final cfg   = mod.nassau;

    final allPlayerIds = [...sideA.playerIds, ...sideB.playerIds];
    final hcpMap = mod.useHandicap
        ? GameEngine.buildTeamHcpMap(round, allPlayerIds, cfg: mod.teamHandicap)
        : <String, double>{};

    // Segmentación lógica (ver segmentsOf): respeta startingNine y campos de 9.
    final seg = segmentsOf(round);

    int front = 0, back = 0;
    int frontPlayed = 0, backPlayed = 0;
    final List<int> frontHistory = [];
    final List<int> backHistory  = [];

    for (final h in seg.playOrder) {
      final delta = GameEngine.holeDeltaVs(
        round: round, sideA: sideA, sideB: sideB,
        holeNum: h, useHandicap: mod.useHandicap, hcpMap: hcpMap,
      );
      if (delta == null) continue;

      if (seg.isFirst(h)) {
        front += delta; frontPlayed++; frontHistory.add(front);
      } else {
        back  += delta; backPlayed++;  backHistory.add(back);
      }
    }

    final idA = sideA.playerIds.first;
    final idB = sideB.playerIds.first;

    final List<NassauPress> presses = [];
    if (cfg.pressEnabled) {
      _detectPressesInSegment(presses, frontHistory, seg.firstNine, frontPlayed,
          idA, idB, cfg.autoPressTrigger);
      _detectPressesInSegment(presses, backHistory, seg.secondNine, backPlayed,
          idA, idB, cfg.autoPressTrigger);
    }

    return NassauLiveStatus(
      front: front, back: back, total: front + back,
      frontPlayed: frontPlayed, backPlayed: backPlayed,
      presses: presses,
      frontVal: cfg.frontValue,
      backVal:  cfg.effectiveBackValue,
      totalVal: cfg.effectiveTotalValue,
    );
  }

  // ── MATCH + AUTO PRESS ────────────────────────────────────────────────────
  // Spec: cada match activo (principal o presión) se sigue por separado.
  // Cuando su marcador llega al trigger, abre UN press hijo que empieza
  // en el SIGUIENTE hoyo. Las presiones son recursivas (press-sobre-press).
  // Reglas:
  //   R1  El match principal siempre existe.
  //   R2  Un press solo nace cuando un match activo alcanza el trigger.
  //   R3  El press empieza en el hoyo siguiente al trigger.
  //   R4  Cada match activo abre solo un press hijo.
  //   R5  Un press también es un match activo y puede abrir otro press.
  //   R6  Las presiones dependen del marcador, no de bloques fijos.
  //   R7  Si no hay hoyo siguiente, no se abre press.
  //   R8  En Todos vs Todos cada duelo se calcula por separado.

  static List<LedgerEntry> _matchAutoPress(
      Round round, List<String> pids, BetModuleInstance mod) {
    final entries = <LedgerEntry>[];
    if (pids.length != 2) return entries;
    final p1Id = pids[0];
    final p2Id = pids[1];
    final cfg  = mod.matchAutoPress;
    final cf   = cfg.carryFactorForPair(p1Id, p2Id);

    // Deltas hoyo a hoyo en orden real de juego
    final hd = _buildHoleDeltas(round, p1Id, p2Id, mod);
    final holeOrder = hd.$1;
    final deltas    = hd.$2;   // deltas[pos] (1-based), 0 = no jugado

    // Construir el árbol de matches activos con la lógica recursiva
    final matches = _buildMatchTreeRoot(
      holeOrder:  holeOrder,
      deltas:     deltas,
      trigger:    cfg.pressTriggerValue,
      maxPresses: cfg.maxPresses ?? 99,
      matchValue: cfg.matchValue * cf,
      pressValue: cfg.pressValue * cf,
    );

    // Liquidar cada match
    for (final m in matches) {
      int score = 0;
      int played = 0;
      for (int pos = m.startPos; pos <= m.endPos && pos <= holeOrder.length; pos++) {
        score += deltas[pos];
        // Contar como jugado si ambos tienen score (incluye hoyos empatados con delta=0)
        final h  = holeOrder[pos - 1];
        final s1 = round.getScore(p1Id, h);
        final s2 = round.getScore(p2Id, h);
        if (s1.hasScore && s2.hasScore) played++;
      }
      if (played == 0) continue;
      final label = '${m.businessLabel} H${holeOrder[m.startPos - 1]}–H${holeOrder[m.endPos.clamp(1, holeOrder.length) - 1]}';
      if (score > 0) {
        entries.add(LedgerEntry(fromPlayerId: p2Id, toPlayerId: p1Id,
            amount: m.value, betType: BetModuleType.matchAutoPress, reason: label));
      } else if (score < 0) {
        entries.add(LedgerEntry(fromPlayerId: p1Id, toPlayerId: p2Id,
            amount: m.value, betType: BetModuleType.matchAutoPress, reason: label));
      }
    }
    return entries;
  }

  // ── MATCH AUTO PRESS — ESTADO EN VIVO ────────────────────────────────────
  static List<MatchPressLiveStatus> matchAutoPressLive(
    Round round, String p1Id, String p2Id, BetModuleInstance mod,
  ) {
    final cfg = mod.matchAutoPress;
    final cf  = cfg.carryFactorForPair(p1Id, p2Id);

    final hd = _buildHoleDeltas(round, p1Id, p2Id, mod);
    final holeOrder = hd.$1;
    final deltas    = hd.$2;

    int lastPlayedPos = 0;
    for (int pos = holeOrder.length; pos >= 1; pos--) {
      if (deltas[pos] != 0) { lastPlayedPos = pos; break; }
    }
    // También detectar hoyos con score = 0 (par) que sí se jugaron
    for (int pos = 1; pos <= holeOrder.length; pos++) {
      final h = holeOrder[pos - 1];
      final s1 = round.getScore(p1Id, h);
      final s2 = round.getScore(p2Id, h);
      if (s1.hasScore && s2.hasScore && pos > lastPlayedPos) lastPlayedPos = pos;
    }
    final lastPlayedHole = lastPlayedPos > 0 ? holeOrder[lastPlayedPos - 1] : 0;

    final matches = _buildMatchTreeRoot(
      holeOrder:  holeOrder,
      deltas:     deltas,
      trigger:    cfg.pressTriggerValue,
      maxPresses: cfg.maxPresses ?? 99,
      matchValue: cfg.matchValue * cf,
      pressValue: cfg.pressValue * cf,
    );

    final results = <MatchPressLiveStatus>[];
    for (final m in matches) {
      int score = 0;
      int played = 0;
      for (int pos = m.startPos; pos <= m.endPos && pos <= holeOrder.length; pos++) {
        score += deltas[pos];
        // Contar como jugado si ambos tienen score
        final h = holeOrder[pos - 1];
        final s1 = round.getScore(p1Id, h);
        final s2 = round.getScore(p2Id, h);
        if (s1.hasScore && s2.hasScore) played++;
      }
      final startHole = holeOrder[m.startPos - 1];
      final endIdx    = (m.endPos - 1).clamp(0, holeOrder.length - 1);
      final endHole   = holeOrder[endIdx];
      results.add(MatchPressLiveStatus(
        sequenceNumber: m.seq,
        isPrimaryMatch: m.isPrimary,
        startHole: startHole,
        endHole:   endHole,
        score:     score,
        played:    played,
        value:     m.value,
        leadingPlayerId: score > 0 ? p1Id : score < 0 ? p2Id : null,
        lastHole:  lastPlayedHole,
      ));
    }
    return results;
  }

  // ── Helper: calcular deltas hoyo a hoyo ──────────────────────────────────
  // Devuelve (holeOrder, deltas) donde deltas[pos 1-based] = +1/-1/0.
  // Para hoyos no jugados devuelve 0 pero NO los marca como jugados.
  static (List<int>, List<int>) _buildHoleDeltas(
      Round round, String p1Id, String p2Id, BetModuleInstance mod) {
    final allHoles = round.course.holes;
    // Usar _strokesP1ReceivesFromP2 que prioriza manualHandicaps sobre HCP.
    final recv     = _strokesP1ReceivesFromP2(round, p1Id, p2Id);
    final p1IsBase = recv <= 0;
    final baseId   = p1IsBase ? p1Id : p2Id;
    final receiverId = p1IsBase ? p2Id : p1Id;
    final recvAbs  = recv.abs().round();

    // Hoyos del CURSO en F9/B9 — distribución de SI correcta
    final (courseF9match, courseB9match) =
        _courseHolesF9B9(allHoles, round.startingNine);

    final holeOrder = round.startingNine == StartingNine.back
        ? [...allHoles.where((c) => c.hole >= 10).map((c) => c.hole).toList()..sort(),
           ...allHoles.where((c) => c.hole <= 9).map((c) => c.hole).toList()..sort()]
        : allHoles.map((c) => c.hole).toList()..sort();
    final holeMap = { for (final ch in allHoles) ch.hole: ch };

    // deltas[0] no se usa; índice 1-based
    final List<int> deltas = List.filled(holeOrder.length + 1, 0);

    for (int pos = 0; pos < holeOrder.length; pos++) {
      final h  = holeOrder[pos];
      final ch = holeMap[h] ?? allHoles.first;
      final s1 = round.getScore(p1Id, h);
      final s2 = round.getScore(p2Id, h);
      if (!s1.hasScore || !s2.hasScore) continue;

      final courseHolesForMatch = courseF9match.any((hh) => hh.hole == ch.hole)
          ? courseF9match : courseB9match;
      final strokesHere = mod.useHandicap && recvAbs > 0
          ? GameEngine.strokesReceivedFromOfficial18Sliding(
              diff18:              recvAbs,
              ch:                  ch,
              courseHolesInSameNine: courseHolesForMatch,
              startingNine:        round.startingNine,
              isNineHolesStartingNine: BetEngine.isNineStartingNine(ch: ch, courseF9: courseF9match, courseB9: courseB9match, startingNine: round.startingNine),
            )
          : 0;

      final grossBase   = round.getScore(baseId,     h).grossScore!;
      final netReceiver = round.getScore(receiverId, h).grossScore! - strokesHere;

      final int delta;
      if      (grossBase < netReceiver) {
        delta = baseId == p1Id ?  1 : -1;
      } else if (grossBase > netReceiver) delta = baseId == p1Id ? -1 :  1;
      else                              delta = 0;

      deltas[pos + 1] = delta;
    }
    return (holeOrder, deltas);
  }

  // ── Helper: construir árbol de matches activos recursivamente ────────────
  // Spec:
  //   R1  El match principal siempre existe (seq=1).
  //   R2  Un press nace cuando un match activo alcanza el trigger.
  //   R3  El press empieza en el hoyo SIGUIENTE al trigger.
  //   R4  Cada match activo abre solo UN press hijo.
  //   R5  Un press también es un match activo y puede abrir su propio press.
  //   R6  Las presiones dependen del marcador, no de bloques fijos.
  //   R7  Si no hay hoyo siguiente al trigger, no se crea press.
  //   R8  En Todos vs Todos cada duelo se calcula por separado.
  //
  // Implementación: cada llamada representa UN match activo.
  // Devuelve la lista plana de todos los matches abiertos (este + descendientes).
  // El seq counter se pasa por referencia (List<int> de un elemento) para que
  // cada nodo reciba un número único en el árbol completo.
  static List<_MatchNode> _buildMatchTree({
    required List<int> holeOrder,
    required List<int> deltas,
    required int trigger,
    required int maxPresses,
    required double matchValue,
    required double pressValue,
    required int startPos,
    int seq = 1,
    required List<int> seqCounter, // contador compartido [siguiente seq disponible]
  }) {
    final nodes = <_MatchNode>[];
    if (startPos > holeOrder.length) return nodes;

    // Registrar este match
    final node = _MatchNode(
      seq:       seq,
      isPrimary: seq == 1,
      startPos:  startPos,
      endPos:    holeOrder.length,
      value:     seq == 1 ? matchValue : pressValue,
    );
    nodes.add(node);

    // Recorrer los hoyos de este match evaluando su propio marcador acumulado
    int matchScore = 0;
    bool pressOpened = false; // R4: solo un press hijo por match

    for (int pos = startPos; pos <= holeOrder.length; pos++) {
      matchScore += deltas[pos];

      // R2 + R4: trigger alcanzado y aún no abrimos press hijo
      if (!pressOpened && matchScore.abs() >= trigger) {
        // R7: solo si hay hoyo siguiente
        final nextPos = pos + 1;
        if (nextPos <= holeOrder.length) {
          // Verificar límite global de presses (maxPresses)
          final totalPressesInTree = seqCounter[0] - 2; // -2 porque seq=1 es el match principal
          if (totalPressesInTree < maxPresses) {
            pressOpened = true;
            final childSeq = seqCounter[0]++;
            // R5: el press hijo también puede abrir su propio press
            final children = _buildMatchTree(
              holeOrder:  holeOrder,
              deltas:     deltas,
              trigger:    trigger,
              maxPresses: maxPresses,
              matchValue: matchValue,
              pressValue: pressValue,
              startPos:   nextPos,
              seq:        childSeq,
              seqCounter: seqCounter,
            );
            nodes.addAll(children);
          }
        }
      }
    }
    return nodes;
  }

  // Wrapper público para _buildMatchTree (maneja el seqCounter compartido)
  static List<_MatchNode> _buildMatchTreeRoot({
    required List<int> holeOrder,
    required List<int> deltas,
    required int trigger,
    required int maxPresses,
    required double matchValue,
    required double pressValue,
  }) {
    // seqCounter[0] empieza en 2 (seq=1 es el match principal)
    final seqCounter = [2];
    return _buildMatchTree(
      holeOrder:  holeOrder,
      deltas:     deltas,
      trigger:    trigger,
      maxPresses: maxPresses,
      matchValue: matchValue,
      pressValue: pressValue,
      startPos:   1,
      seq:        1,
      seqCounter: seqCounter,
    );
  }


  /// Genera TODOS los entries de todos los grupos de la ronda.
  ///
  /// Lanza [StateError] si algún par tiene acuerdos legacy contradictorios.
  /// Es deliberado: mejor fallar que liquidar dinero mal. Para llamarlo desde
  /// la UI usa [safeComputeAll], que aísla el fallo por módulo.
  static List<LedgerEntry> computeAll(Round round) {
    final all = <LedgerEntry>[];
    for (final group in round.betGroups) {
      all.addAll(computeGroup(round, group));
    }
    return all;
  }

  /// Versión tolerante a fallos de [computeAll], pensada para la UI.
  ///
  /// La UI llama al ledger desde `build()`, donde una excepción tumba la
  /// pantalla entera. Este wrapper captura los errores de integridad,
  /// deja fuera SOLO el módulo afectado y devuelve los mensajes para que la
  /// pantalla pueda avisar al usuario de qué ventaja debe corregir.
  static LedgerComputation safeComputeAll(Round round) {
    final entries = <LedgerEntry>[];
    final errors  = <String>[];

    for (final group in round.betGroups) {
      for (final mod in group.modules) {
        try {
          entries.addAll(computeModule(round, group, mod));
        } on StateError catch (e) {
          errors.add('${group.name} · ${mod.type.label}: ${e.message}');
        } catch (e) {
          errors.add('${group.name} · ${mod.type.label}: error inesperado ($e)');
        }
      }
    }
    return LedgerComputation(entries: entries, errors: errors);
  }

  // ── DIAGNÓSTICO DE MEDAL ──────────────────────────────────────────────────
  /// Retorna un mapa con toda la información necesaria para depurar por qué el
  /// Medal no produce entries en un grupo/módulo dado.
  ///
  /// Estructura del resultado:
  /// ```
  /// {
  ///   'groupId':    String,
  ///   'moduleId':   String,
  ///   'pids':       List<String>,
  ///   'pidsCount':  int,
  ///   'isAllVsAll': bool,
  ///   'useHandicap': bool,
  ///   'mode':       String,            // 'net' | 'gross'
  ///   'value':      double,
  ///   'nets':       Map<String, int>,  // net calculado por jugador
  ///   'grosses':    Map<String, int>,  // gross de cada jugador
  ///   'hcps':       Map<String, double>,
  ///   'entries':    int,               // número de entries generados
  ///   'reason':     String,            // explicación textual
  /// }
  /// ```
  static List<Map<String, dynamic>> diagnoseMedal(Round round) {
    final result = <Map<String, dynamic>>[];
    for (final group in round.betGroups) {
      for (final mod in group.modules) {
        if (mod.type != BetModuleType.medal) continue;
        final pids = mod.effectivePids(group.playerIds);
        final cfg  = mod.medal;

        final grosses    = <String, int>{};
        final hcps       = <String, double>{};
        final nets       = <String, int>{};
        final strokesMap = <String, int>{};  // strokes en los hoyos jugados (vs rival o base)
        final allHoles   = round.course.holes;

        for (final pid in pids) {
          grosses[pid] = GameEngine.grossTotal(round, pid);
          hcps[pid]    = round.getHandicap(pid);
        }

        // Mismo cálculo que _medal: usar sliding oficial 18 hoyos con split F9/B9.
        // Hoyos del CURSO (no jugados) para distribución correcta de SI.
        final (courseF9diag, courseB9diag) = _courseHolesF9B9(allHoles, round.startingNine);

        int netInPairDiag(String pA, String pB) {
          if (!mod.useHandicap) return grosses[pA] ?? 0;
          final recv = _strokesP1ReceivesFromP2(round, pA, pB);
          if (recv <= 0) return grosses[pA] ?? 0;
          final diff18 = recv.round();
          final playedHolesA = allHoles.where((ch) => round.getScore(pA, ch.hole).hasScore).toList();
          int net = 0;
          for (final ch in playedHolesA) {
            final score = round.getScore(pA, ch.hole);
            final courseHolesForDiag = courseF9diag.any((hh) => hh.hole == ch.hole)
                ? courseF9diag : courseB9diag;
            final strokes = GameEngine.strokesReceivedFromOfficial18Sliding(
              diff18: diff18, ch: ch,
              courseHolesInSameNine: courseHolesForDiag,
              startingNine:        round.startingNine,
              isNineHolesStartingNine: BetEngine.isNineStartingNine(ch: ch, courseF9: courseF9diag, courseB9: courseB9diag, startingNine: round.startingNine),
            );
            net += score.grossScore! - strokes;
          }
          return net;
        }

        // Strokes totales recibidos en los hoyos jugados (para mostrar en UI)
        int strokesInPlayedHoles(String pA, String pB) {
          if (!mod.useHandicap) return 0;
          final recv = _strokesP1ReceivesFromP2(round, pA, pB);
          if (recv <= 0) return 0;
          final diff18 = recv.round();
          final playedHolesA = allHoles.where((ch) => round.getScore(pA, ch.hole).hasScore).toList();
          int total = 0;
          for (final ch in playedHolesA) {
            final courseHolesForDiag = courseF9diag.any((hh) => hh.hole == ch.hole)
                ? courseF9diag : courseB9diag;
            total += GameEngine.strokesReceivedFromOfficial18Sliding(
              diff18: diff18, ch: ch,
              courseHolesInSameNine: courseHolesForDiag,
              startingNine:        round.startingNine,
              isNineHolesStartingNine: BetEngine.isNineStartingNine(ch: ch, courseF9: courseF9diag, courseB9: courseB9diag, startingNine: round.startingNine),
            );
          }
          return total;
        }

        String reason;
        // Para allVsAll: detalle de cada par {p1,p2,gross1,strokes1,net1,gross2,strokes2,net2,winner}
        final pairDetails = <Map<String, dynamic>>[];

        if (pids.length < 2) {
          reason = 'ERROR: Solo ${pids.length} jugador(es) — se necesitan ≥2';
        } else if (pids.length == 2) {
          final s0 = strokesInPlayedHoles(pids[0], pids[1]);
          final s1 = strokesInPlayedHoles(pids[1], pids[0]);
          final n0 = netInPairDiag(pids[0], pids[1]);
          final n1 = netInPairDiag(pids[1], pids[0]);
          nets[pids[0]] = n0;
          nets[pids[1]] = n1;
          strokesMap[pids[0]] = s0;
          strokesMap[pids[1]] = s1;
          if (n0 < n1) {
            reason = '${pids[0]} gana: gross ${grosses[pids[0]]} - $s0 strokes = net $n0 '
                '< ${pids[1]}: gross ${grosses[pids[1]]} - $s1 strokes = net $n1';
          } else if (n1 < n0) {
            reason = '${pids[1]} gana: gross ${grosses[pids[1]]} - $s1 strokes = net $n1 '
                '< ${pids[0]}: gross ${grosses[pids[0]]} - $s0 strokes = net $n0';
          } else {
            reason = 'EMPATE NET (ambos net=$n0). '
                '${pids[0]}: gross ${grosses[pids[0]]} - $s0 = $n0. '
                '${pids[1]}: gross ${grosses[pids[1]]} - $s1 = $n1';
          }
        } else if (mod.isAllVsAll) {
          // allVsAll: cada par hoyo a hoyo con strokes distribuidos por SI
          for (int i = 0; i < pids.length; i++) {
            for (int j = i + 1; j < pids.length; j++) {
              final si = strokesInPlayedHoles(pids[i], pids[j]);
              final sj = strokesInPlayedHoles(pids[j], pids[i]);
              final ni = netInPairDiag(pids[i], pids[j]);
              final nj = netInPairDiag(pids[j], pids[i]);
              String pairWinner;
              if (ni < nj) {
                pairWinner = pids[i];
              } else if (nj < ni) {
                pairWinner = pids[j];
              } else {
                pairWinner = 'EMPATE';
              }
              pairDetails.add({
                'p1': pids[i], 'gross1': grosses[pids[i]] ?? 0, 'strokes1': si, 'net1': ni,
                'p2': pids[j], 'gross2': grosses[pids[j]] ?? 0, 'strokes2': sj, 'net2': nj,
                'winner': pairWinner,
              });
            }
          }
          final wins    = pairDetails.where((p) => p['winner'] != 'EMPATE').length;
          final empates = pairDetails.where((p) => p['winner'] == 'EMPATE').length;
          reason = '${pids.length} jugadores · ${pairDetails.length} pares · $wins con ganador · $empates empates';
        } else {
          // onePot 3+: MISMA ancla que usa _medal (el que más da / menos recibe).
          // Antes se usaba "menor HCP" aquí, así que el diagnóstico mostraba
          // netos distintos de los que el motor liquidaba realmente.
          final base = mod.useHandicap ? groupAnchor(round, pids) : pids.first;
          if (!mod.useHandicap) {
            for (final pid in pids) {
              nets[pid] = grosses[pid]!;
              strokesMap[pid] = 0;
            }
          } else {
            for (final pid in pids) {
              nets[pid] = netInPairDiag(pid, base);
              strokesMap[pid] = strokesInPlayedHoles(pid, base);
            }
          }
          final sorted = pids.toList()..sort((a, b) => (nets[a] ?? 999).compareTo(nets[b] ?? 999));
          if ((nets[sorted[0]] ?? 999) == (nets[sorted[1]] ?? 999)) {
            reason = 'EMPATE entre ${sorted[0]} y ${sorted[1]} (net=${nets[sorted[0]]}) → sin entry';
          } else {
            final winNetStr = pids.map((pid) =>
                '$pid gross${grosses[pid]}-${strokesMap[pid]}=net${nets[pid]}').join(', ');
            reason = 'Ancla: $base | ${sorted[0]} gana (net=${nets[sorted[0]]}) | $winNetStr';
          }
        }

        final entries = _medal(round, pids, mod);
        result.add({
          'groupId':     group.id,
          'groupName':   group.name,
          'moduleId':    mod.id,
          'pids':        pids,
          'pidsCount':   pids.length,
          'isAllVsAll':  mod.isAllVsAll,
          'useHandicap': mod.useHandicap,
          'mode':        cfg.mode.name,
          'value':       cfg.value,
          'nets':        nets,
          'grosses':     grosses,
          'hcps':        hcps,
          'strokes':     strokesMap,
          'pairDetails': pairDetails,  // solo para allVsAll
          'entries':     entries.length,
          'reason':      reason,
        });
      }
    }
    return result;
  }

  // ── SKINS LIVE SCORECARD ──────────────────────────────────────────────────
  // Para partidas 1v1 puras: usa strokesReceivedInPlayedHoles (distribuye
  //   las ventajas solo entre los hoyos realmente jugados, sin dividir F9/B9).
  // Para grupos de 3+ jugadores: usa holeWinner con strokesReceived individual
  // (coincide exactamente con la lógica del motor _skins en computeAll).
  // En ambos casos el carry-over acumula correctamente.
  static List<SkinHoleResult> skinsScorecard(
    Round round, String p1Id, String p2Id, BetModuleInstance mod, {
    List<String>? groupPids,  // todos los participantes del módulo (opcional)
  }) {
    final cfg = mod.skins;

    // Determinar si el módulo es de grupo (3+) o 1v1 puro
    final pids = groupPids ?? [p1Id, p2Id];
    final isGroup = pids.length > 2;

    // En 1v1 se respeta la excepción por duelo, igual que en _skins1v1.
    // En grupo (pozo común) no hay "valor del duelo": se usa el base.
    final skinValue =
        isGroup ? cfg.valuePerSkin : mod.effectiveValueForDuel(p1Id, p2Id).$1;

    double pot = skinValue;
    int cumP1 = 0, cumP2 = 0;

    final allHoles = round.course.holes;

    // Iterar en el ORDEN de la ronda (respetando startingNine).
    // Usar hoyos reales del curso para evitar null en cursos de 9 hoyos.
    final holeMap = { for (final ch in allHoles) ch.hole: ch };
    final List<int> holeOrder;
    if (round.startingNine == StartingNine.back) {
      final b9 = allHoles.where((c) => c.hole >= 10).map((c) => c.hole).toList()..sort();
      final f9 = allHoles.where((c) => c.hole <= 9).map((c) => c.hole).toList()..sort();
      holeOrder = [...b9, ...f9];
    } else {
      holeOrder = allHoles.map((c) => c.hole).toList()..sort();
    }

    // 1v1: determinar base/receptor usando _strokesP1ReceivesFromP2
    // (respeta manuales; si no hay manual, usa diff HCP como fallback)
    final recv1v1   = _strokesP1ReceivesFromP2(round, p1Id, p2Id);
    final p1Receives = recv1v1 > 0;
    final baseId      = p1Receives ? p2Id : p1Id;
    final receiverId  = p1Receives ? p1Id : p2Id;
    final recvAbs1v1  = recv1v1.abs().round();

    // Hoyos del CURSO en F9/B9 — distribución de SI correcta para skinsScorecard
    final (courseF9scorecard, courseB9scorecard) =
        _courseHolesF9B9(allHoles, round.startingNine);

    // Grupo (3+): misma escala común que usa _skins en el ledger.
    final anchorId = isGroup ? groupAnchor(round, pids) : '';

    // Construir resultados en orden de la ronda
    final orderedResults = <SkinHoleResult>[];

    for (final h in holeOrder) {
      final ch = holeMap[h]!;

      if (isGroup) {
        // ── CAMINO GRUPAL: todos deben tener score ─────────────────────────
        if (!pids.every((pid) => round.getScore(pid, h).hasScore)) {
          // Hoyo no jugado aún: pendiente, sin acumular carry
          orderedResults.add(SkinHoleResult(
            hole: h, winner: null, isPending: true,
            pot: pot, cumP1: cumP1, cumP2: cumP2,
          ));
          continue;
        }

        // Ganador del hoyo en el grupo — misma escala (ancla + pairSliding)
        // que usa _skins al generar los LedgerEntries.
        final winner = groupHoleWinner(
          round:       round,
          pids:        pids,
          ch:          ch,
          useHandicap: mod.useHandicap,
          anchorId:    anchorId,
          courseF9:    courseF9scorecard,
          courseB9:    courseB9scorecard,
        );
        final skinsInPot = (pot / skinValue).round();

        if (winner == null) {
          // Empate en el grupo
          orderedResults.add(SkinHoleResult(
            hole: h, winner: null, isPending: false, isTie: true,
            pot: pot, cumP1: cumP1, cumP2: cumP2,
          ));
          if (cfg.carryOver) pot += skinValue;
        } else {
          // Solo registrar como ganador de p1/p2 si el ganador es uno de los dos
          if (winner == p1Id) {
            cumP1 += skinsInPot;
          } else if (winner == p2Id) cumP2 += skinsInPot;
          orderedResults.add(SkinHoleResult(
            hole: h, winner: winner, isPending: false,
            pot: pot, cumP1: cumP1, cumP2: cumP2,
          ));
          pot = skinValue;
        }
      } else {
        // ── CAMINO 1v1: usa strokesReceivedInPlayedHoles ─────────────────
        // Distribuye las ventajas SOLO entre los hoyos jugados por el receptor.
        // Correcto para medias rondas (solo B9 o solo F9) y rondas completas.
        final s1 = round.getScore(p1Id, h);
        final s2 = round.getScore(p2Id, h);

        // Hoyo no jugado aún: pendiente, sin acumular carry
        if (!s1.hasScore || !s2.hasScore) {
          orderedResults.add(SkinHoleResult(
            hole: h, winner: null, isPending: true,
            pot: pot, cumP1: cumP1, cumP2: cumP2,
          ));
          continue;
        }

        final grossBase     = round.getScore(baseId,     h).grossScore!;
        final grossReceiver = round.getScore(receiverId, h).grossScore!;

        final courseHolesForScorecard = courseF9scorecard.any((hh) => hh.hole == ch.hole)
            ? courseF9scorecard : courseB9scorecard;
        final strokesHere = mod.useHandicap && recvAbs1v1 > 0
            ? GameEngine.strokesReceivedFromOfficial18Sliding(
                diff18:              recvAbs1v1,
                ch:                  ch,
                courseHolesInSameNine: courseHolesForScorecard,
                startingNine:        round.startingNine,
                isNineHolesStartingNine: BetEngine.isNineStartingNine(ch: ch, courseF9: courseF9scorecard, courseB9: courseB9scorecard, startingNine: round.startingNine),
              )
            : 0;
        final netReceiver = grossReceiver - strokesHere;

        String? winner;
        bool isTie = false;
        if      (grossBase < netReceiver) { winner = baseId;     }
        else if (grossBase > netReceiver) { winner = receiverId; }
        else                              { isTie  = true;       }

        final skinsInPot = (pot / skinValue).round();
        if (!isTie) {
          if (winner == p1Id) {
            cumP1 += skinsInPot;
          } else {
            cumP2 += skinsInPot;
          }
          orderedResults.add(SkinHoleResult(
            hole: h, winner: winner, isPending: false,
            pot: pot, cumP1: cumP1, cumP2: cumP2,
          ));
          pot = skinValue;
        } else {
          orderedResults.add(SkinHoleResult(
            hole: h, winner: null, isPending: false, isTie: true,
            pot: pot, cumP1: cumP1, cumP2: cumP2,
          ));
          if (cfg.carryOver) pot += skinValue;
        }
      }
    }

    return orderedResults;
  }

  // ── NASSAU LIVE STATUS ────────────────────────────────────────────────────
  static NassauLiveStatus nassauLiveStatus(
    Round round, String p1Id, String p2Id, BetModuleInstance mod,
  ) {
    final cfg = mod.nassau;
    final recv        = _strokesP1ReceivesFromP2(round, p1Id, p2Id);
    final p1IsBase    = recv <= 0;
    final baseId      = p1IsBase ? p1Id : p2Id;
    final receiverId  = p1IsBase ? p2Id : p1Id;
    final recvAbs     = recv.abs().round();
    final allHoles    = round.course.holes;

    // Hoyos del CURSO en F9/B9 — distribución de SI correcta para nassauLiveStatus
    final (courseF9live, courseB9live) =
        _courseHolesF9B9(allHoles, round.startingNine);

    // Segmentación lógica (ver segmentsOf): primer segmento = vuelta de inicio
    final seg = segmentsOf(round);

    int front = 0, back = 0;
    int frontPlayed = 0, backPlayed = 0;
    int holesWonP1 = 0, holesWonP2 = 0;
    final List<int> frontHistory = [];
    final List<int> backHistory  = [];

    // Iterar en orden de juego para que los históricos de press sean correctos
    final holeMapLive = { for (final ch in allHoles) ch.hole: ch };
    for (final h in seg.playOrder) {
      final ch = holeMapLive[h]!;
      final sBase     = round.getScore(baseId,     h);
      final sReceiver = round.getScore(receiverId, h);
      if (!sBase.hasScore || !sReceiver.hasScore) continue;

      final courseHolesForLive = courseF9live.any((hh) => hh.hole == ch.hole)
          ? courseF9live : courseB9live;
      final strokesHere = mod.useHandicap && recvAbs > 0
          ? GameEngine.strokesReceivedFromOfficial18Sliding(
              diff18:              recvAbs,
              ch:                  ch,
              courseHolesInSameNine: courseHolesForLive,
              startingNine:        round.startingNine,
              isNineHolesStartingNine: BetEngine.isNineStartingNine(ch: ch, courseF9: courseF9live, courseB9: courseB9live, startingNine: round.startingNine),
            )
          : 0;
      final grossBase   = sBase.grossScore!;
      final netReceiver = sReceiver.grossScore! - strokesHere;
      final int delta;
      if      (grossBase < netReceiver) {
        delta = p1IsBase ?  1 : -1;
      } else if (grossBase > netReceiver) delta = p1IsBase ? -1 :  1;
      else                              delta = 0;

      // Conteo individual de hoyos ganados (para el badge visual)
      if (delta > 0) {
        holesWonP1++;
      } else if (delta < 0) holesWonP2++;

      if (seg.isFirst(h)) {
        front += delta; frontPlayed++; frontHistory.add(front);
      } else {
        back  += delta; backPlayed++;  backHistory.add(back);
      }
    }

    // El delta ya está calculado en perspectiva de p1 (positivo = p1 arriba):
    //   p1IsBase=true : delta= 1 si base(p1) gana, -1 si pierde
    //   p1IsBase=false: delta=-1 si base(p2) gana, +1 si pierde  →  +1 = p1 arriba
    // Por tanto NO se normaliza: pasar frontHistory/backHistory directamente.
    final List<NassauPress> presses = [];
    if (cfg.pressEnabled) {
      _detectPressesInSegment(presses, frontHistory, seg.firstNine, frontPlayed,
          p1Id, p2Id, cfg.autoPressTrigger);
      _detectPressesInSegment(presses, backHistory, seg.secondNine, backPlayed,
          p1Id, p2Id, cfg.autoPressTrigger);
    }

    return NassauLiveStatus(
      front: front, back: back, total: front + back,
      frontPlayed: frontPlayed, backPlayed: backPlayed,
      presses: presses,
      frontVal: cfg.frontValue,
      backVal:  cfg.effectiveBackValue,
      totalVal: cfg.effectiveTotalValue,
      holesWonP1: holesWonP1,
      holesWonP2: holesWonP2,
    );
  }

  // ── NASSAU con presiones: estado en vivo ─────────────────────────────────
  // Antes nassauPressLiveStatus; ahora unificado bajo NassauConfig.pressEnabled
  static NassauPressLiveStatus nassauPressLiveStatus(
    Round round, String p1Id, String p2Id, BetModuleInstance mod,
  ) {
    // Usa la config unificada NassauConfig (que contiene los campos de press)
    final cfg = mod.nassau;
    final recv        = _strokesP1ReceivesFromP2(round, p1Id, p2Id);
    final p1IsBase    = recv <= 0;
    final baseId      = p1IsBase ? p1Id : p2Id;
    final receiverId  = p1IsBase ? p2Id : p1Id;
    final recvAbs     = recv.abs().round();
    final allHoles    = round.course.holes;

    // Hoyos del CURSO en F9/B9 — distribución de SI correcta para nassauPressLiveStatus
    final (courseF9press2, courseB9press2) =
        _courseHolesF9B9(allHoles, round.startingNine);

    // Segmentación lógica (ver segmentsOf): primer segmento = vuelta de inicio
    final seg = segmentsOf(round);

    int front = 0, back = 0;
    int frontPlayed = 0, backPlayed = 0;
    final List<int> frontHistory = [];
    final List<int> backHistory  = [];

    // Iterar en orden de juego para que los históricos de press sean correctos
    final holeMapPress = { for (final ch in allHoles) ch.hole: ch };
    for (final h in seg.playOrder) {
      final ch = holeMapPress[h]!;
      final sBase     = round.getScore(baseId,     h);
      final sReceiver = round.getScore(receiverId, h);
      if (!sBase.hasScore || !sReceiver.hasScore) continue;
      final courseHolesForPress2 = courseF9press2.any((hh) => hh.hole == ch.hole)
          ? courseF9press2 : courseB9press2;
      final strokes = mod.useHandicap && recvAbs > 0
          ? GameEngine.strokesReceivedFromOfficial18Sliding(
              diff18:              recvAbs,
              ch:                  ch,
              courseHolesInSameNine: courseHolesForPress2,
              startingNine:        round.startingNine,
              isNineHolesStartingNine: BetEngine.isNineStartingNine(ch: ch, courseF9: courseF9press2, courseB9: courseB9press2, startingNine: round.startingNine),
            )
          : 0;
      final grossBase   = sBase.grossScore!;
      final netReceiver = sReceiver.grossScore! - strokes;
      final int delta;
      if      (grossBase < netReceiver) {
        delta = p1IsBase ?  1 : -1;
      } else if (grossBase > netReceiver) delta = p1IsBase ? -1 :  1;
      else                              delta = 0;

      // Asignar al segmento lógico correcto
      if (seg.isFirst(h)) {
        front += delta; frontPlayed++; frontHistory.add(front);
      } else {
        back  += delta; backPlayed++;  backHistory.add(back);
      }
    }

    // Carry: primer segmento completo y empatado
    final f9Complete  = seg.firstNine.isNotEmpty && frontPlayed == seg.firstNine.length;
    final carryActive = cfg.carryEnabled && cfg.carryApplied && f9Complete && front == 0;

    // Valores efectivos
    final effBackVal       = carryActive ? cfg.backValue      * cfg.carryFactor : cfg.backValue;
    final effBackPressVal  = carryActive ? cfg.backPressValue * cfg.carryFactor : cfg.backPressValue;
    final effTotalVal      = carryActive ? cfg.totalValue     * cfg.carryFactor : cfg.totalValue;

    // El delta ya está calculado en perspectiva de p1 (positivo = p1 arriba):
    //   p1IsBase=true : delta= 1 si base(p1) gana, -1 si pierde
    //   p1IsBase=false: delta=-1 si base(p2) gana, +1 si pierde  →  +1 = p1 arriba
    // Por tanto NO se normaliza: pasar frontHistory/backHistory directamente.

    // Presiones del primer segmento (vuelta de inicio)
    final List<NassauPress> frontPresses = [];
    _detectPressesInSegment(frontPresses, frontHistory, seg.firstNine, frontPlayed,
        p1Id, p2Id, cfg.autoPressTrigger);
    // Presiones del segundo segmento
    final List<NassauPress> backPresses  = [];
    _detectPressesInSegment(backPresses, backHistory, seg.secondNine, backPlayed,
        p1Id, p2Id, cfg.autoPressTrigger);

    return NassauPressLiveStatus(
      front: front, back: back, total: front + back,
      frontPlayed: frontPlayed, backPlayed: backPlayed,
      frontVal:      cfg.frontValue,
      backVal:       effBackVal,
      totalVal:      effTotalVal,
      frontPressVal: cfg.frontPressValue,
      backPressVal:  effBackPressVal,
      carryActive:   carryActive,
      carryEnabled:  cfg.carryEnabled,
      frontPresses:  frontPresses,
      backPresses:   backPresses,
    );
  }

  /// Detecta presiones dentro de un segmento.
  ///
  /// [holes] son los hoyos REALES del segmento en orden de juego. Se usa en
  /// lugar de un rango numérico para soportar campos de 9 hoyos y numeración
  /// invertida (ej: campo 1-9 jugado como vuelta de inicio con back-start).
  static void _detectPressesInSegment(
    List<NassauPress> out,
    List<int> history,
    List<int> holes,
    int played,
    String p1Id, String p2Id,
    int trigger,
  ) {
    if (holes.isEmpty) return;
    final holeEnd = holes.last;
    // Misma lógica de marcador relativo que liquidateSegment:
    // el trigger se mide desde el inicio del segmento o desde el último press,
    // no desde el acumulado absoluto. Así se evitan presiones duplicadas
    // cuando el marcador se mantiene en el umbral varios hoyos seguidos.
    //
    // IMPORTANTE: cada presión termina cuando empieza la SIGUIENTE presión
    // (no al final del segmento completo). Usamos dos pasadas:
    // 1ª pasada: detectar todos los índices de trigger y el loser de cada press.
    // 2ª pasada: calcular el pressScore de cada press usando como endpoint
    //            el índice donde empieza la siguiente press (o history.last si es la última).
    final List<({int trigIdx, String loser, int startHole})> triggers = [];

    int refIdx = 0;
    for (int i = 0; i < history.length; i++) {
      final relDiff = history[i] - (refIdx == 0 ? 0 : history[refIdx - 1]);
      if (relDiff.abs() >= trigger) {
        // La press empieza en el hoyo siguiente, si existe dentro del segmento
        if (i + 1 < holes.length) {
          final startHole = holes[i + 1];
          final loser = relDiff < 0 ? p1Id : p2Id;
          triggers.add((trigIdx: i, loser: loser, startHole: startHole));
          refIdx = i + 1;
        }
      }
    }

    final segmentHoles = holes.length;
    for (int k = 0; k < triggers.length; k++) {
      final t = triggers[k];
      // La press cierra justo antes de que empiece la siguiente; si es la última,
      // cierra al final del segmento (history.last).
      final endIdx = (k + 1 < triggers.length)
          ? triggers[k + 1].trigIdx - 1
          : history.length - 1;
      // pressScore: cambio desde el punto de disparo hasta el cierre de la press.
      // Positivo → p1 arriba → p1 ganó la press.
      // Para presses ABIERTAS: se muestra el marcador en tiempo real (último hoyo jugado).
      // Para presses CERRADAS: se usa el índice donde empieza la siguiente press (o el final).
      final isOpen = played < segmentHoles;
      final scoreEndIdx = isOpen ? history.length - 1 : endIdx;
      final pressScore = scoreEndIdx < history.length
          ? history[scoreEndIdx] - history[t.trigIdx]
          : 0;
      out.add(NassauPress(
        loser: t.loser, startHole: t.startHole, endHole: holeEnd,
        score: pressScore,
        isOpen: played < segmentHoles,
      ));
    }
  }
}

// ── LedgerComputation: resultado tolerante a fallos de computeAll ────────────
class LedgerComputation {
  final List<LedgerEntry> entries;

  /// Mensajes de integridad de los módulos que no se pudieron calcular.
  /// Vacío si todo está correcto.
  final List<String> errors;

  const LedgerComputation({required this.entries, required this.errors});

  bool get hasErrors => errors.isNotEmpty;
}

// ── RoundSegments: segmentación lógica de la ronda ───────────────────────────
//
// [firstNine]  hoyos de la vuelta de inicio, en orden numérico.
// [secondNine] hoyos de la otra vuelta, en orden numérico (vacío en campos de 9).
// [singleNine] true → la ronda se liquida con UN solo segmento (9 hoyos).
//
// Ojo: "first"/"second" son lógicos, no numéricos. Con startingNine=back,
// firstNine son los hoyos 10-18 y secondNine los 1-9.
/// Qué pasó en UN hoyo de Bola Baja / Bola Alta.
///
/// Lo produce el mismo recorrido que reparte los puntos, así que lo que muestra
/// la pantalla de captura es literalmente lo que el motor contó.
class LowHighHoleResult {
  final int hole;

  /// true si los cuatro jugadores anotaron. Con false no se disputa NINGUNA
  /// categoría —sin los cuatro scores no hay bola alta que comparar— y el
  /// marcador no se mueve; la UI debe explicarlo.
  final bool played;

  /// Scores ya netos si la apuesta se juega en neto, ordenados de menor a
  /// mayor: el primero es la bola baja del lado y el último la alta.
  /// Con [played] false pueden venir incompletos.
  final List<int> aScores;
  final List<int> bScores;

  /// Cuánto valía el punto de cada categoría AL ENTRAR a este hoyo. Mayor que 1
  /// significa que viene acumulado de empates anteriores — es el dato que la UI
  /// anuncia como "la bola baja vale 2 puntos aquí".
  final double lowCarry;
  final double highCarry;

  /// Puntos otorgados en este hoyo. Con la regla "dividir" ambos pueden ser 0.5.
  final double lowPointsA, lowPointsB, highPointsA, highPointsB;

  const LowHighHoleResult({
    required this.hole,
    required this.played,
    required this.aScores,
    required this.bScores,
    required this.lowCarry,
    required this.highCarry,
    this.lowPointsA = 0,
    this.lowPointsB = 0,
    this.highPointsA = 0,
    this.highPointsB = 0,
  });

  int? get aLow  => aScores.isEmpty ? null : aScores.first;
  int? get aHigh => aScores.isEmpty ? null : aScores.last;
  int? get bLow  => bScores.isEmpty ? null : bScores.first;
  int? get bHigh => bScores.isEmpty ? null : bScores.last;

  /// 'a' | 'b' | null (empate o no disputado).
  String? get lowWinner => !played
      ? null
      : lowPointsA > lowPointsB
          ? 'a'
          : lowPointsB > lowPointsA
              ? 'b'
              : null;

  String? get highWinner => !played
      ? null
      : highPointsA > highPointsB
          ? 'a'
          : highPointsB > highPointsA
              ? 'b'
              : null;
}

/// Resultado de un segmento en Bola Baja / Bola Alta, listo para mostrarse.
///
/// Lo produce [BetEngine.lowHighBreakdown] a partir del MISMO recorrido que usa
/// la liquidación, así que los montos de aquí son exactamente los que se
/// cobraron: la suma de [total] de todos los segmentos coincide con lo que el
/// ledger movió por este módulo.
class LowHighSegmentBreakdown {
  /// 'front9' | 'back9' | 'overall' | 'nine' (ronda de 9 hoyos).
  final String segment;

  /// Etiqueta mostrable, la misma que aparece en los asientos del ledger.
  final String label;

  final List<int> holes;

  /// Puntos de cada lado, separados por categoría. Pueden ser medios puntos
  /// con la regla de empate "dividir".
  final double aLow, aHigh, bLow, bHigh;

  /// Monto LIQUIDADO por la apuesta fija de este segmento. Cero si quedó
  /// empatado o si esa modalidad está desactivada.
  final double segmentAmount;

  /// Monto LIQUIDADO por diferencia de puntos. Cero si no aplica al segmento.
  final double pointAmount;

  /// Detalle hoyo a hoyo del segmento, en orden de juego.
  final List<LowHighHoleResult> holeResults;

  const LowHighSegmentBreakdown({
    required this.segment,
    required this.label,
    required this.holes,
    required this.aLow,
    required this.aHigh,
    required this.bLow,
    required this.bHigh,
    required this.segmentAmount,
    required this.pointAmount,
    this.holeResults = const [],
  });

  /// El resultado de [hole] dentro de este segmento, o null si no pertenece.
  LowHighHoleResult? resultForHole(int hole) {
    for (final h in holeResults) {
      if (h.hole == hole) return h;
    }
    return null;
  }

  double get aTotal => aLow + aHigh;
  double get bTotal => bLow + bHigh;

  /// Positiva = gana el lado A.
  double get diff => aTotal - bTotal;

  bool get isTie => diff == 0;

  /// Lo que el lado perdedor paga al ganador en este segmento.
  double get total => segmentAmount + pointAmount;
}

/// Puntos acumulados de un segmento en Bola Baja / Bola Alta.
///
/// Se guardan las cuatro cifras y no solo la diferencia porque la UI muestra el
/// desglose por categoría, y porque con la regla "dividir" los totales cambian
/// aunque la diferencia no: A y B suman medio punto cada uno y el marcador se
/// mueve sin que nadie cobre.
class _LowHighTally {
  /// Detalle hoyo a hoyo del recorrido, en orden de juego. Se llena como
  /// SUBPRODUCTO del mismo walk que reparte los puntos, para que la pantalla
  /// de captura no tenga que rehacer el cálculo.
  final List<LowHighHoleResult> holes = [];

  double aLow = 0;
  double aHigh = 0;
  double bLow = 0;
  double bHigh = 0;

  double get aTotal => aLow + aHigh;
  double get bTotal => bLow + bHigh;

  /// Positiva = gana el lado A.
  double get diff => aTotal - bTotal;
}

class RoundSegments {
  final List<int> firstNine;
  final List<int> secondNine;
  final bool      singleNine;

  const RoundSegments({
    required this.firstNine,
    required this.secondNine,
    required this.singleNine,
  });

  /// Todos los hoyos del curso en orden real de juego.
  List<int> get playOrder => [...firstNine, ...secondNine];

  /// true si [hole] pertenece al primer segmento jugado.
  bool isFirst(int hole) => firstNine.contains(hole);
}

// ── _MatchNode: nodo interno para el árbol de matches activos ────────────────
class _MatchNode {
  final int    seq;
  final bool   isPrimary;
  final int    startPos;
  final int    endPos;
  final double value;
  const _MatchNode({
    required this.seq,
    required this.isPrimary,
    required this.startPos,
    required this.endPos,
    required this.value,
  });

  int?   get pressNumber   => isPrimary ? null : seq - 1;
  String get businessLabel => isPrimary ? 'Match' : 'Press $pressNumber';
}

// ── Modelos de resultado en vivo ──────────────────────────────────────────────
class SkinHoleResult {
  final int hole;
  final String? winner;
  final bool isPending;
  final bool isTie;
  final double pot;
  final int cumP1;
  final int cumP2;

  const SkinHoleResult({
    required this.hole, required this.winner, required this.isPending,
    this.isTie = false, required this.pot, required this.cumP1, required this.cumP2,
  });

  int get p1Lead => cumP1 - cumP2;
}

class NassauLiveStatus {
  final int front;
  final int back;
  final int total;
  final int frontPlayed;
  final int backPlayed;
  final List<NassauPress> presses;
  final double frontVal;
  final double backVal;
  final double totalVal;
  // Hoyos ganados individualmente (independiente del sentido del segmento)
  final int holesWonP1;
  final int holesWonP2;

  const NassauLiveStatus({
    required this.front, required this.back, required this.total,
    required this.frontPlayed, required this.backPlayed,
    required this.presses,
    required this.frontVal, required this.backVal, required this.totalVal,
    this.holesWonP1 = 0,
    this.holesWonP2 = 0,
  });
}

class NassauPress {
  final String loser;
  final int startHole;
  final int endHole;
  final int score;
  final bool isOpen;

  const NassauPress({
    required this.loser, required this.startHole, required this.endHole,
    required this.score, required this.isOpen,
  });
}

// ── MatchPressLiveStatus ──────────────────────────────────────────────────────
// Estado en vivo de una presión individual dentro de un juego Match + Auto Press.
class MatchPressLiveStatus {
  final int    sequenceNumber;   // 1 = match principal
  final bool   isPrimaryMatch;
  final int    startHole;
  final int    endHole;
  final int    score;            // positivo = p1 va arriba, negativo = p2 va arriba
  final int    played;           // hoyos jugados en esta presión
  final double value;
  final String? leadingPlayerId; // null si empatado
  final int    lastHole;         // último hoyo jugado en la ronda

  const MatchPressLiveStatus({
    required this.sequenceNumber, required this.isPrimaryMatch,
    required this.startHole, required this.endHole,
    required this.score, required this.played, required this.value,
    required this.lastHole,
    this.leadingPlayerId,
  });

  /// Número de press para mostrar en UI (1, 2, 3…). Null si es el match principal.
  int? get pressNumber => isPrimaryMatch ? null : sequenceNumber - 1;

  /// Etiqueta de negocio: 'Match' o 'Press 1', 'Press 2', etc.
  String get businessLabel => isPrimaryMatch ? 'Match' : 'Press $pressNumber';

  bool get isAllSquare  => score == 0;
  bool get isOpen       => lastHole < endHole;
  int  get holesLeft    => endHole - lastHole;
  String get scoreLabel {
    if (score == 0) return 'AS';
    return '${score.abs()}UP';
  }
}

// ── NassauPressLiveStatus ─────────────────────────────────────────────────────
// Estado en vivo de un duelo Nassau + Press para la scorecard.
class NassauPressLiveStatus {
  final int front;         // score acumulado F9 (positivo = p1 va arriba)
  final int back;          // score acumulado B9
  final int total;         // front + back
  final int frontPlayed;   // hoyos F9 jugados
  final int backPlayed;    // hoyos B9 jugados
  final double frontVal;
  final double backVal;
  final double totalVal;
  final double frontPressVal;
  final double backPressVal;
  final bool   carryActive;   // carry ya está activado y F9 terminó en empate
  final bool   carryEnabled;  // carry está configurado
  final List<NassauPress> frontPresses;
  final List<NassauPress> backPresses;

  const NassauPressLiveStatus({
    required this.front, required this.back, required this.total,
    required this.frontPlayed, required this.backPlayed,
    required this.frontVal, required this.backVal, required this.totalVal,
    required this.frontPressVal, required this.backPressVal,
    required this.carryActive, required this.carryEnabled,
    required this.frontPresses, required this.backPresses,
  });

  String scoreLabel(int s) => s == 0 ? 'AS' : '${s.abs()}UP';
  String get frontLabel => scoreLabel(front);
  String get backLabel  => scoreLabel(back);
  String get totalLabel => scoreLabel(total);
  bool get frontComplete => frontPlayed == 9;
  bool get backComplete  => backPlayed  == 9;
}
