// ─────────────────────────────────────────────────────────────────────────────
// BET ENGINE v4
// Responsabilidad: aplicar reglas de cada BetModuleInstance
// Genera LedgerEntries. NO calcula scores ni muestra UI.
// ─────────────────────────────────────────────────────────────────────────────
import '../models/models.dart';
import 'game_engine.dart';

class BetEngine {
  /// Genera todos los LedgerEntries para una BetGroup completa
  static List<LedgerEntry> computeGroup(Round round, BetGroup group) {
    final entries = <LedgerEntry>[];
    for (final mod in group.modules) {
      final pids = mod.participantIds.isNotEmpty
          ? mod.participantIds
          : group.playerIds;
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
        case BetModuleType.units:
          entries.addAll(_units(round, pids, mod));
          break;
      }
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

    // ── onePot GRUPAL (3+ jugadores): un ganador por hoyo toma de todos ──────
    final cfg = mod.skins;
    double pot = cfg.valuePerSkin;
    for (final ch in round.course.holes) {
      final h = ch.hole;
      // Hoyo no jugado aún: se salta sin acumular carry
      if (!pids.every((pid) => round.getScore(pid, h).hasScore)) continue;

      final winner = GameEngine.holeWinner(round, pids, h, mod.useHandicap);
      if (winner != null) {
        final share = pot / (n - 1);
        for (final pid in pids) {
          if (pid != winner) {
            entries.add(LedgerEntry(
              fromPlayerId: pid, toPlayerId: winner,
              amount: share, betType: BetModuleType.skins,
              reason: 'Skins H$h', hole: h,
            ));
          }
        }
        pot = cfg.valuePerSkin;
      } else {
        // Empate en hoyo jugado → acumular carry
        if (cfg.carryOver) pot += cfg.valuePerSkin;
      }
    }
    return entries;
  }

  // Skins 1v1: usa strokesReceivedVs (igual que skinsScorecard y la vista UI).
  // Itera en el orden real de la ronda (startingNine) para que el carry-over
  // no se acumule en hoyos pending del segmento no iniciado.
  static List<LedgerEntry> _skins1v1(Round round, String p1Id, String p2Id, BetModuleInstance mod) {
    final entries = <LedgerEntry>[];
    final cfg = mod.skins;
    double pot = cfg.valuePerSkin;

    final hcp1 = round.getHandicap(p1Id);
    final hcp2 = round.getHandicap(p2Id);
    final p1IsBase  = hcp1 <= hcp2;
    final hcpBase     = p1IsBase ? hcp1 : hcp2;
    final hcpReceiver = p1IsBase ? hcp2 : hcp1;
    final baseId      = p1IsBase ? p1Id : p2Id;
    final receiverId  = p1IsBase ? p2Id : p1Id;
    final allHoles    = round.course.holes;

    // Iterar en orden real de la ronda para un carry correcto
    final holeOrder = round.startingNine == StartingNine.back
        ? [...List.generate(9, (i) => i + 10), ...List.generate(9, (i) => i + 1)]
        : List.generate(18, (i) => i + 1);
    final holeMap = { for (final ch in allHoles) ch.hole: ch };

    for (final h in holeOrder) {
      final ch = holeMap[h]!;
      final sBase     = round.getScore(baseId,     h);
      final sReceiver = round.getScore(receiverId, h);

      // Hoyo no jugado aún: se salta sin acumular carry
      // (el carry solo se acumula cuando el hoyo es JUGADO y resulta en empate)
      if (!sBase.hasScore || !sReceiver.hasScore) continue;

      final strokesHere = mod.useHandicap
          ? GameEngine.strokesReceivedVs(
              hcpHigher:    hcpReceiver,
              hcpLower:     hcpBase,
              ch:           ch,
              allHoles:     allHoles,
              startingNine: round.startingNine,
            )
          : 0;

      final grossBase     = sBase.grossScore!;
      final netReceiver   = sReceiver.grossScore! - strokesHere;

      String? winner;
      if      (grossBase < netReceiver) winner = baseId;
      else if (grossBase > netReceiver) winner = receiverId;
      // else tie → pot lleva el carry

      if (winner != null) {
        final loser = winner == p1Id ? p2Id : p1Id;
        entries.add(LedgerEntry(
          fromPlayerId: loser, toPlayerId: winner,
          amount: pot, betType: BetModuleType.skins,
          reason: 'Skins H$h', hole: h,
        ));
        pot = cfg.valuePerSkin;
      } else {
        // Empate en hoyo jugado → acumular carry
        if (cfg.carryOver) pot += cfg.valuePerSkin;
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
    final entries = <LedgerEntry>[];
    final cfg = mod.nassau;
    int front = 0, back = 0;

    for (int h = 1; h <= round.totalHoles; h++) {
      final ch = round.course.holes.firstWhere((c) => c.hole == h);
      final s1 = round.getScore(p1Id, h);
      final s2 = round.getScore(p2Id, h);
      if (!s1.hasScore || !s2.hasScore) continue;

      final hcp1 = mod.useHandicap ? round.getHandicap(p1Id) : 0.0;
      final hcp2 = mod.useHandicap ? round.getHandicap(p2Id) : 0.0;
      final net1 = s1.grossScore! - GameEngine.strokesReceived(hcp1, ch);
      final net2 = s2.grossScore! - GameEngine.strokesReceived(hcp2, ch);

      if (h <= 9) {
        if (net1 < net2) front++;
        else if (net1 > net2) front--;
      } else {
        if (net1 < net2) back++;
        else if (net1 > net2) back--;
      }
    }

    final total = front + back;
    if (round.totalHoles <= 9) {
      // Ronda de 9: solo existe el segmento front con el valor frontValue
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

  // ── MEDAL ─────────────────────────────────────────────────────────────────
  // onePot  : winner toma de todos (comportamiento actual).
  // allVsAll: cada par tiene su propio resultado individual.
  static List<LedgerEntry> _medal(Round round, List<String> pids, BetModuleInstance mod) {
    final entries = <LedgerEntry>[];
    final cfg = mod.medal;

    // Helper: score neto de pA respecto a pB, respetando el manualHandicap bilateral (sliding).
    // manualHandicaps[pA][pB] = strokes que pA recibe de pB (positivo = ventaja para pA).
    // Aplica strokesReceivedVs hoyo a hoyo para distribuir correctamente los strokes.
    int netFor(String pAId, String pBId) {
      if (!mod.useHandicap) return GameEngine.grossTotal(round, pAId);
      final rpA = round.roundPlayers.firstWhere(
          (r) => r.playerId == pAId,
          orElse: () => RoundPlayer(playerId: pAId, handicapEnRonda: 0));
      final rpB = round.roundPlayers.firstWhere(
          (r) => r.playerId == pBId,
          orElse: () => RoundPlayer(playerId: pBId, handicapEnRonda: 0));

      // ¿Hay manualHandicap entre este par?
      final manualDiff = rpA.manualHandicaps[pBId];
      if (manualDiff != null && manualDiff != 0) {
        // manualDiff > 0: pA recibe strokes → pA tiene ventaja (su neto = gross - strokes recibidos)
        // manualDiff < 0: pA da strokes   → pA en desventaja (su neto = gross, sin reducción)
        int total = 0;
        for (int h = 1; h <= round.totalHoles; h++) {
          final s = round.getScore(pAId, h);
          if (!s.hasScore) continue;
          final ch = round.course.holes.firstWhere(
              (c) => c.hole == h, orElse: () => round.course.holes.first);
          int strokes = 0;
          if (manualDiff > 0) {
            // pA recibe: usar strokesReceivedVs con hcpHigher = hcpA + diff, hcpLower = hcpB
            strokes = GameEngine.strokesReceivedVs(
              hcpHigher: rpA.handicapEnRonda + manualDiff,
              hcpLower:  rpB.handicapEnRonda,
              ch: ch,
              allHoles: round.course.holes,
              startingNine: round.startingNine,
            );
          }
          // manualDiff < 0: pA da strokes → strokes = 0 (pA juega en bruto respecto a pB)
          total += s.grossScore! - strokes;
        }
        return total;
      }
      // Sin manualHandicap → usar handicap individual normal
      return GameEngine.netTotal(round, pAId, mod.useHandicap);
    }

    if (mod.isAllVsAll && pids.length > 2) {
      for (int i = 0; i < pids.length; i++) {
        for (int j = i + 1; j < pids.length; j++) {
          final net1 = netFor(pids[i], pids[j]);
          final net2 = netFor(pids[j], pids[i]);
          if (net1 < net2) {
            entries.add(LedgerEntry(fromPlayerId: pids[j], toPlayerId: pids[i], amount: cfg.value, betType: BetModuleType.medal, reason: 'Medal'));
          } else if (net2 < net1) {
            entries.add(LedgerEntry(fromPlayerId: pids[i], toPlayerId: pids[j], amount: cfg.value, betType: BetModuleType.medal, reason: 'Medal'));
          }
        }
      }
      return entries;
    }

    // onePot: winner toma de todos
    final nets = <String, int>{};
    if (pids.length == 2) {
      // Par exacto: respetar manualHandicap bilateral
      nets[pids[0]] = netFor(pids[0], pids[1]);
      nets[pids[1]] = netFor(pids[1], pids[0]);
    } else {
      // 3+ jugadores sin sliding bilateral: handicap individual normal
      for (final pid in pids) {
        nets[pid] = GameEngine.netTotal(round, pid, mod.useHandicap);
      }
    }
    final sorted = pids.toList()..sort((a, b) => (nets[a] ?? 999).compareTo(nets[b] ?? 999));
    final winner = sorted.first;
    if ((nets[sorted[0]] ?? 999) == (nets[sorted[1]] ?? 999)) return entries;
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

    if (mod.isAllVsAll && pids.length > 2) {
      for (final seg in segs) {
        final (from, to, label) = seg;
        for (int i = 0; i < pids.length; i++) {
          for (int j = i + 1; j < pids.length; j++) {
            final t1 = GameEngine.totalPutts(round, pids[i], from: from, to: to);
            final t2 = GameEngine.totalPutts(round, pids[j], from: from, to: to);
            if (t1 == 0 || t2 == 0) continue;
            if (t1 < t2) {
              entries.add(LedgerEntry(fromPlayerId: pids[j], toPlayerId: pids[i], amount: cfg.value, betType: BetModuleType.putts, reason: label));
            } else if (t2 < t1) {
              entries.add(LedgerEntry(fromPlayerId: pids[i], toPlayerId: pids[j], amount: cfg.value, betType: BetModuleType.putts, reason: label));
            }
          }
        }
      }
      return entries;
    }

    // onePot: winner cobra a todos
    for (final seg in segs) {
      final (from, to, label) = seg;
      final totals = <String, int>{};
      for (final pid in pids) {
        totals[pid] = GameEngine.totalPutts(round, pid, from: from, to: to);
      }
      if (totals.values.any((v) => v == 0)) continue;
      final sorted = pids.toList()..sort((a, b) => (totals[a] ?? 99).compareTo(totals[b] ?? 99));
      if ((totals[sorted[0]] ?? 99) == (totals[sorted[1]] ?? 99)) continue;
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
    final cfg = mod.oyeses;
    final par3Holes = round.course.holes.where((h) => h.isPar3).toList();

    // Filtrar por hoyos elegibles
    final eligible = cfg.eligibleHoles.isNotEmpty
        ? par3Holes.where((h) => cfg.eligibleHoles.contains(h.hole)).toList()
        : par3Holes;

    // ── Cobros hoyo a hoyo ─────────────────────────────────────────────────
    // Para el zapato: rastrear quién gana cada oyés
    // winner[playerId] = número de oyeses ganados como PRIMERO (1°)
    final Map<String, int> firstPlaceCount = { for (final p in pids) p: 0 };
    int holesWithRanking = 0; // oyeses donde hay ranking registrado

    for (final ch in eligible) {
      final ranking = round.getOyese(ch.hole);
      if (ranking == null || ranking.ranking.isEmpty) continue;
      final orderedPids = ranking.ranking.where((pid) => pids.contains(pid)).toList();
      if (orderedPids.length < 2) continue;

      holesWithRanking++;
      // El primero gana el oyés de este hoyo
      firstPlaceCount[orderedPids[0]] = (firstPlaceCount[orderedPids[0]] ?? 0) + 1;

      for (int i = 0; i < orderedPids.length - 1; i++) {
        for (int j = i + 1; j < orderedPids.length; j++) {
          entries.add(LedgerEntry(
            fromPlayerId: orderedPids[j], toPlayerId: orderedPids[i],
            amount: cfg.value, betType: BetModuleType.oyeses,
            reason: 'Oyés H${ch.hole} (${i + 1}° vs ${j + 1}°)', hole: ch.hole,
          ));
        }
      }
    }

    // ── Zapato ─────────────────────────────────────────────────────────────
    if (cfg.zapatoEnabled && holesWithRanking >= 2) {
      // Condición de 18 hoyos: verificar si se jugaron todos los par-3 elegibles
      final totalEligible = eligible.length;
      final allPlayed = holesWithRanking == totalEligible;

      // zapatoRequires18 = true → necesita que TODOS los oyeses estén jugados
      // zapatoRequires18 = false → basta con 2+ oyeses registrados
      final conditionMet = cfg.zapatoRequires18 ? allPlayed : holesWithRanking >= 2;

      if (conditionMet) {
        // ¿Algún jugador ganó TODOS los oyeses con ranking?
        for (final pid in pids) {
          if ((firstPlaceCount[pid] ?? 0) == holesWithRanking) {
            // Este jugador hizo zapato — cobra a todos los demás
            final zapatoAmt = cfg.zapatoAmount(holesWithRanking);
            for (final other in pids.where((p) => p != pid)) {
              entries.add(LedgerEntry(
                fromPlayerId: other, toPlayerId: pid,
                amount: zapatoAmt, betType: BetModuleType.oyeses,
                reason: '👟 Zapato ($holesWithRanking oyeses)',
              ));
            }
            break; // solo puede haber un zapato
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

    for (final pid in pids) {
      for (int h = 1; h <= round.totalHoles; h++) {
        final evts = round.getEvents(pid, h);
        for (final evt in evts.where((e) => pids.contains(e.playerId))) {
          // Valor individual por evento — configurado en UnitsConfig
          final amount = cfg.valueFor(evt.type);
          for (final other in pids.where((p) => p != pid)) {
            entries.add(LedgerEntry(
              fromPlayerId: other, toPlayerId: pid,
              amount: amount, betType: BetModuleType.units,
              reason: '${evt.type.label} H$h', hole: h,
            ));
          }
        }
      }
    }
    return entries;
  }

  // ── MATCH + AUTO PRESS ───────────────────────────────────────────────────
  // Regla del juego:
  //   • MATCH PRINCIPAL: H1–totalHoles, vale matchValue.
  //   • Cuando el marcador acumulado llega a ±pressTriggerValue:
  //       1. Se abre un "Dígito": segmento desde el inicio del segmento activo
  //          hasta el hoyo que lo disparó (ambos inclusive). Vale pressValue.
  //       2. Se abre una NUEVA PRESIÓN desde el hoyo siguiente.
  //          El marcador de la nueva presión arranca en 0.
  //   • Empate en cualquier segmento = push (no se cobra).
  //   • Las presiones se detectan sobre el marcador del segmento activo,
  //     no sobre el acumulado global (cada presión tiene su propio contador).
  static List<LedgerEntry> _matchAutoPress(
      Round round, List<String> pids, BetModuleInstance mod) {
    final entries = <LedgerEntry>[];
    if (pids.length != 2) return entries;
    final p1Id = pids[0];
    final p2Id = pids[1];
    final cfg  = mod.matchAutoPress;
    final hcp1 = mod.useHandicap ? round.getHandicap(p1Id) : 0.0;
    final hcp2 = mod.useHandicap ? round.getHandicap(p2Id) : 0.0;

    // Delta hoyo a hoyo (positivo = p1 gana el hoyo)
    // Usa strokesReceivedVs (bilateral) igual que skins 1v1 para consistencia.
    final allHoles = round.course.holes;
    final String baseId     = hcp1 <= hcp2 ? p1Id : p2Id;
    final String receiverId = hcp1 <= hcp2 ? p2Id : p1Id;
    final double hcpBase     = hcp1 <= hcp2 ? hcp1 : hcp2;
    final double hcpReceiver = hcp1 <= hcp2 ? hcp2 : hcp1;

    final List<int> hd = List.filled(round.totalHoles + 1, 0);
    for (int h = 1; h <= round.totalHoles; h++) {
      final ch = round.course.holes.firstWhere(
          (c) => c.hole == h, orElse: () => round.course.holes.first);
      final s1 = round.getScore(p1Id, h);
      final s2 = round.getScore(p2Id, h);
      if (!s1.hasScore || !s2.hasScore) continue;

      // Strokes bilaterales: el jugador de mayor hcp recibe strokes vs el de menor
      final strokesHere = mod.useHandicap
          ? GameEngine.strokesReceivedVs(
              hcpHigher:    hcpReceiver,
              hcpLower:     hcpBase,
              ch:           ch,
              allHoles:     allHoles,
              startingNine: round.startingNine,
            )
          : 0;

      final grossBase     = round.getScore(baseId,     h).grossScore!;
      final grossReceiver = round.getScore(receiverId, h).grossScore!;
      final netReceiver   = grossReceiver - strokesHere;

      // Convertir resultado al orden p1/p2
      final int delta;
      if (grossBase < netReceiver)      delta = baseId == p1Id ? 1 : -1;
      else if (grossBase > netReceiver) delta = baseId == p1Id ? -1 : 1;
      else                              delta = 0;
      hd[h] = delta;
    }

    // ── Construir segmentos ──────────────────────────────────────────────────
    // Segmento = (startHole, endHole, value, label)
    // El match principal siempre va de H1 a totalHoles.
    // Las presiones se construyen dinámicamente.
    // Si hay carry, todos los valores se multiplican por carryFactor.
    final double cf = cfg.carryApplied ? cfg.carryFactor : 1.0;
    final List<(int start, int end, double value, String label)> segments = [];
    segments.add((1, round.totalHoles, cfg.matchValue * cf, 'Match H1–${round.totalHoles}${cfg.carryApplied ? ' ×carry' : ''}'));

    // currentPressStart: desde qué hoyo empieza el segmento de presión activo
    int currentPressStart = 1;
    int pressSegScore = 0;      // marcador del segmento de presión activo
    int pressCount = 0;         // cuántas presiones se han abierto ya
    final int maxP = cfg.maxPresses ?? 99;

    for (int h = 1; h <= round.totalHoles; h++) {
      pressSegScore += hd[h];   // acumular delta del segmento activo

      final absDiff = pressSegScore.abs();
      if (absDiff == cfg.pressTriggerValue && pressCount < maxP) {
        // 1. Cerrar el dígito/segmento que acaba de disparar
        final isFirstDigit = (pressCount == 0);
        final segLabel = isFirstDigit
            ? 'Dígito H$currentPressStart–$h'
            : 'Press H$currentPressStart–$h';
        segments.add((currentPressStart, h, cfg.pressValue * cf, segLabel));
        pressCount++;

        // 2. Abrir nuevo segmento desde el siguiente hoyo
        final nextHole = h + 1;
        if (nextHole <= round.totalHoles && pressCount < maxP) {
          currentPressStart = nextHole;
          pressSegScore = 0; // el nuevo segmento arranca en 0
        }
      }
    }
    // Si aún hay un segmento de presión activo abierto que no se cerró
    // (no llegó al trigger), se agrega como presión abierta/pendiente.
    // Solo se agrega si hubo al menos una presión previa (para no duplicar
    // el dígito cuando no se activó ningún trigger).
    if (pressCount > 0 && currentPressStart <= round.totalHoles) {
      final lastLabel = 'Press H$currentPressStart–${round.totalHoles}';
      // Solo si este segmento no fue ya agregado (el último trigger pudo
      // haberlo cerrado exactamente en totalHoles)
      final alreadyAdded = segments.any((s) => s.$1 == currentPressStart &&
          s.$2 == round.totalHoles && s.$3 == cfg.pressValue * cf);
      if (!alreadyAdded) {
        segments.add((currentPressStart, round.totalHoles, cfg.pressValue * cf, lastLabel));
      }
    }

    // ── Liquidar cada segmento ───────────────────────────────────────────────
    for (final (start, end, value, label) in segments) {
      int score = 0;
      int played = 0;
      for (int h = start; h <= end; h++) {
        score += hd[h];
        if (hd[h] != 0) played++;
      }
      if (played == 0) continue;

      String? from;
      String? to;
      if (score > 0)      { from = p2Id; to = p1Id; }
      else if (score < 0) { from = p1Id; to = p2Id; }
      // score == 0 → empate → push (no cobra)

      if (from != null && to != null) {
        entries.add(LedgerEntry(
          fromPlayerId: from, toPlayerId: to,
          amount: value, betType: BetModuleType.matchAutoPress,
          reason: label,
        ));
      }
    }
    return entries;
  }

  // ── MATCH AUTO PRESS — ESTADO EN VIVO ────────────────────────────────────
  // Mismo algoritmo que _matchAutoPress pero devuelve MatchPressLiveStatus
  // para mostrar en tiempo real en la tarjeta de scoring.
  static List<MatchPressLiveStatus> matchAutoPressLive(
    Round round, String p1Id, String p2Id, BetModuleInstance mod,
  ) {
    final cfg  = mod.matchAutoPress;
    final hcp1 = mod.useHandicap ? round.getHandicap(p1Id) : 0.0;
    final hcp2 = mod.useHandicap ? round.getHandicap(p2Id) : 0.0;

    // Delta por hoyo — usa strokesReceivedVs (bilateral) para consistencia con skins 1v1
    final allHolesLive = round.course.holes;
    final String baseIdLive     = hcp1 <= hcp2 ? p1Id : p2Id;
    final String receiverIdLive = hcp1 <= hcp2 ? p2Id : p1Id;
    final double hcpBaseLive     = hcp1 <= hcp2 ? hcp1 : hcp2;
    final double hcpReceiverLive = hcp1 <= hcp2 ? hcp2 : hcp1;

    final List<int> hd = List.filled(round.totalHoles + 1, 0);
    int lastPlayedHole = 0;
    for (int h = 1; h <= round.totalHoles; h++) {
      final ch = round.course.holes.firstWhere(
          (c) => c.hole == h, orElse: () => round.course.holes.first);
      final s1 = round.getScore(p1Id, h);
      final s2 = round.getScore(p2Id, h);
      if (!s1.hasScore || !s2.hasScore) continue;
      lastPlayedHole = h;

      final strokesHere = mod.useHandicap
          ? GameEngine.strokesReceivedVs(
              hcpHigher:    hcpReceiverLive,
              hcpLower:     hcpBaseLive,
              ch:           ch,
              allHoles:     allHolesLive,
              startingNine: round.startingNine,
            )
          : 0;

      final grossBase     = round.getScore(baseIdLive,     h).grossScore!;
      final grossReceiver = round.getScore(receiverIdLive, h).grossScore!;
      final netReceiver   = grossReceiver - strokesHere;

      final int delta;
      if (grossBase < netReceiver)      delta = baseIdLive == p1Id ? 1 : -1;
      else if (grossBase > netReceiver) delta = baseIdLive == p1Id ? -1 : 1;
      else                              delta = 0;
      hd[h] = delta;
    }

    // ── Mismo algoritmo de construcción de segmentos que _matchAutoPress ──
    // (start, end, value, isPrimary, seq)
    // Si hay carry, todos los valores se multiplican por carryFactor.
    final double cfLive = cfg.carryApplied ? cfg.carryFactor : 1.0;
    final List<(int start, int end, double value, bool isPrimary, int seq)> segs = [];
    segs.add((1, round.totalHoles, cfg.matchValue * cfLive, true, 1));

    int currentPressStart = 1;
    int pressSegScore = 0;
    int pressCount = 0;
    int seqN = 2;
    final int maxP = cfg.maxPresses ?? 99;

    for (int h = 1; h <= round.totalHoles; h++) {
      pressSegScore += hd[h];

      final absDiff = pressSegScore.abs();
      if (absDiff == cfg.pressTriggerValue && pressCount < maxP) {
        segs.add((currentPressStart, h, cfg.pressValue * cfLive, false, seqN++));
        pressCount++;

        final nextHole = h + 1;
        if (nextHole <= round.totalHoles && pressCount < maxP) {
          currentPressStart = nextHole;
          pressSegScore = 0;
        }
      }
    }
    // Segmento de presión activo aún abierto
    if (pressCount > 0 && currentPressStart <= round.totalHoles) {
      final alreadyAdded = segs.any((s) =>
          s.$1 == currentPressStart &&
          s.$2 == round.totalHoles &&
          s.$3 == cfg.pressValue * cfLive);
      if (!alreadyAdded) {
        segs.add((currentPressStart, round.totalHoles, cfg.pressValue * cfLive, false, seqN++));
      }
    }

    // ── Calcular estado de cada segmento ─────────────────────────────────────
    final results = <MatchPressLiveStatus>[];
    for (final (start, end, value, isPrimary, seqNum) in segs) {
      int score = 0;
      int played = 0;
      for (int h = start; h <= end; h++) {
        score += hd[h];
        if (hd[h] != 0) played++;
      }
      results.add(MatchPressLiveStatus(
        sequenceNumber: seqNum,
        isPrimaryMatch: isPrimary,
        startHole: start,
        endHole: end,
        score: score,
        played: played,
        value: value,
        leadingPlayerId: score > 0 ? p1Id : score < 0 ? p2Id : null,
        lastHole: lastPlayedHole,
      ));
    }
    return results;
  }


  /// Genera TODOS los entries de todos los grupos de la ronda
  static List<LedgerEntry> computeAll(Round round) {
    final all = <LedgerEntry>[];
    for (final group in round.betGroups) {
      all.addAll(computeGroup(round, group));
    }
    return all;
  }

  // ── SKINS LIVE SCORECARD ──────────────────────────────────────────────────
  // Para partidas 1v1 puras: usa strokesReceivedVs (diferencia de HCPs).
  // Para grupos de 3+ jugadores: usa holeWinner con strokesReceived individual
  // (coincide exactamente con la lógica del motor _skins en computeAll).
  // En ambos casos el carry-over acumula correctamente.
  static List<SkinHoleResult> skinsScorecard(
    Round round, String p1Id, String p2Id, BetModuleInstance mod, {
    List<String>? groupPids,  // todos los participantes del módulo (opcional)
  }) {
    final cfg = mod.skins;
    double pot = cfg.valuePerSkin;
    int cumP1 = 0, cumP2 = 0;

    final allHoles = round.course.holes;

    // Determinar si el módulo es de grupo (3+) o 1v1 puro
    final pids = groupPids ?? [p1Id, p2Id];
    final isGroup = pids.length > 2;

    // Iterar en el ORDEN de la ronda (respetando startingNine).
    final holeOrder = round.startingNine == StartingNine.back
        ? [...List.generate(9, (i) => i + 10), ...List.generate(9, (i) => i + 1)]
        : List.generate(18, (i) => i + 1);

    // Mapa para acceder rápido a CourseHole por número
    final holeMap = { for (final ch in allHoles) ch.hole: ch };

    // HCPs para el caso 1v1 (lógica de diferencia)
    final hcp1 = round.getHandicap(p1Id);
    final hcp2 = round.getHandicap(p2Id);
    final p1IsBase = hcp1 <= hcp2;
    final hcpBase     = p1IsBase ? hcp1 : hcp2;
    final hcpReceiver = p1IsBase ? hcp2 : hcp1;
    final baseId      = p1IsBase ? p1Id : p2Id;
    final receiverId  = p1IsBase ? p2Id : p1Id;

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

        // Ganador del hoyo en el grupo (neto individual vs par)
        final winner = GameEngine.holeWinner(round, pids, h, mod.useHandicap);
        final skinsInPot = (pot / cfg.valuePerSkin).round();

        if (winner == null) {
          // Empate en el grupo
          orderedResults.add(SkinHoleResult(
            hole: h, winner: null, isPending: false, isTie: true,
            pot: pot, cumP1: cumP1, cumP2: cumP2,
          ));
          if (cfg.carryOver) pot += cfg.valuePerSkin;
        } else {
          // Solo registrar como ganador de p1/p2 si el ganador es uno de los dos
          if (winner == p1Id) cumP1 += skinsInPot;
          else if (winner == p2Id) cumP2 += skinsInPot;
          orderedResults.add(SkinHoleResult(
            hole: h, winner: winner, isPending: false,
            pot: pot, cumP1: cumP1, cumP2: cumP2,
          ));
          pot = cfg.valuePerSkin;
        }
      } else {
        // ── CAMINO 1v1: usa strokesReceivedVs ────────────────────────────
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

        final strokesHere = mod.useHandicap
            ? GameEngine.strokesReceivedVs(
                hcpHigher:    hcpReceiver,
                hcpLower:     hcpBase,
                ch:           ch,
                allHoles:     allHoles,
                startingNine: round.startingNine,
              )
            : 0;
        final netReceiver = grossReceiver - strokesHere;

        String? winner;
        bool isTie = false;
        if      (grossBase < netReceiver) { winner = baseId;     }
        else if (grossBase > netReceiver) { winner = receiverId; }
        else                              { isTie  = true;       }

        final skinsInPot = (pot / cfg.valuePerSkin).round();
        if (!isTie) {
          if (winner == p1Id) cumP1 += skinsInPot;
          else                cumP2 += skinsInPot;
          orderedResults.add(SkinHoleResult(
            hole: h, winner: winner, isPending: false,
            pot: pot, cumP1: cumP1, cumP2: cumP2,
          ));
          pot = cfg.valuePerSkin;
        } else {
          orderedResults.add(SkinHoleResult(
            hole: h, winner: null, isPending: false, isTie: true,
            pot: pot, cumP1: cumP1, cumP2: cumP2,
          ));
          if (cfg.carryOver) pot += cfg.valuePerSkin;
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
    final hcp1 = mod.useHandicap ? round.getHandicap(p1Id) : 0.0;
    final hcp2 = mod.useHandicap ? round.getHandicap(p2Id) : 0.0;

    int front = 0, back = 0;
    int frontPlayed = 0, backPlayed = 0;
    final List<int> frontHistory = [];
    final List<int> backHistory  = [];

    for (int h = 1; h <= round.totalHoles; h++) {
      final ch = round.course.holes.firstWhere((c) => c.hole == h);
      final s1 = round.getScore(p1Id, h);
      final s2 = round.getScore(p2Id, h);
      if (!s1.hasScore || !s2.hasScore) continue;

      final net1 = s1.grossScore! - GameEngine.strokesReceived(hcp1, ch);
      final net2 = s2.grossScore! - GameEngine.strokesReceived(hcp2, ch);
      final delta = net1 < net2 ? 1 : net1 > net2 ? -1 : 0;

      if (h <= 9) {
        front += delta; frontPlayed++; frontHistory.add(front);
      } else {
        back += delta; backPlayed++; backHistory.add(back);
      }
    }

    final List<NassauPress> presses = [];
    if (cfg.pressEnabled) {
      _detectPresses(presses, frontHistory, 1, 9, frontPlayed,
          p1Id, p2Id, cfg.autoPressTrigger);
      _detectPresses(presses, backHistory, 10, 18, backPlayed,
          p1Id, p2Id, cfg.autoPressTrigger);
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

  static void _detectPresses(
    List<NassauPress> out,
    List<int> history,
    int holeStart, int holeEnd,
    int played,
    String p1Id, String p2Id,
    int trigger,
  ) {
    final List<int> pressStartHoles = [];
    for (int i = 0; i < history.length; i++) {
      final diff = history[i];
      if (diff.abs() >= trigger) {
        final startHole = holeStart + i + 1;
        if (startHole <= holeEnd && !pressStartHoles.contains(startHole)) {
          pressStartHoles.add(startHole);
          int pressScore = 0;
          for (int j = i + 1; j < history.length; j++) {
            pressScore = history[j] - history[i];
          }
          final loser = diff < 0 ? p1Id : p2Id;
          out.add(NassauPress(
            loser: loser, startHole: startHole, endHole: holeEnd,
            score: pressScore,
            isOpen: played < (holeEnd - holeStart + 1),
          ));
        }
      }
    }
  }
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

  const NassauLiveStatus({
    required this.front, required this.back, required this.total,
    required this.frontPlayed, required this.backPlayed,
    required this.presses,
    required this.frontVal, required this.backVal, required this.totalVal,
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

  bool get isAllSquare  => score == 0;
  bool get isOpen       => lastHole < endHole;
  int  get holesLeft    => endHole - lastHole;
  String get scoreLabel {
    if (score == 0) return 'AS';
    return '${score.abs()}UP';
  }
}
