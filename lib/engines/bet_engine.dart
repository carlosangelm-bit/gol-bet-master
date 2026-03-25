// ─────────────────────────────────────────────────────────────────────────────
// BET ENGINE v4
// Responsabilidad: aplicar reglas de cada BetModuleInstance
// Genera LedgerEntries. NO calcula scores ni muestra UI.
// ─────────────────────────────────────────────────────────────────────────────
import '../models/models.dart';
import 'game_engine.dart';

class BetEngine {

  // ── Helper: handicaps efectivos para un par 1v1, respetando manualHandicaps ──
  // Si hay un manualHandicap entre p1 y p2, los HCPs se ajustan para que
  // strokesReceivedVs y strokesReceived produzcan el resultado correcto.
  //
  // Devuelve (hcp1efectivo, hcp2efectivo) donde la diferencia refleja el sliding.
  //
  // Convención manualHandicaps[pA][pB]:
  //   > 0 → pA recibe esos strokes de pB (ventaja para pA)
  //   < 0 → pA da esos strokes a pB  (desventaja para pA)
  //
  // IMPORTANTE: el manual ya ES la diferencia de strokes entre el par.
  // No se suma al HCP — se usa como diferencia directa.
  // Si manual[p1][p2] = +8 → p1 recibe 8 de p2 → hcp1Eff = hcp2 + 8 (para que diff = 8)
  // Si manual[p1][p2] = -8 → p1 da 8 a p2    → hcp2Eff = hcp1 + 8 (para que diff = 8)
  static (double, double) _effectiveHcps(Round round, String p1Id, String p2Id, bool useHandicap) {
    if (!useHandicap) return (0.0, 0.0);
    final hcp1 = round.getHandicap(p1Id);
    final hcp2 = round.getHandicap(p2Id);
    final rp1 = round.roundPlayers.firstWhere(
        (r) => r.playerId == p1Id,
        orElse: () => RoundPlayer(playerId: p1Id, handicapEnRonda: hcp1));
    final manual = rp1.manualHandicaps[p2Id];
    if (manual == null || manual == 0) return (hcp1, hcp2);
    // manual > 0: p1 recibe → p1 es receptor, diff = manual
    //   hcp1Eff = hcp2 + manual  (garantiza hcp1Eff - hcp2 = manual)
    // manual < 0: p1 da → p2 es receptor, diff = |manual|
    //   hcp2Eff = hcp1 + |manual|  (garantiza hcp2Eff - hcp1 = |manual|)
    if (manual > 0) {
      return (hcp2 + manual, hcp2); // p1 recibe: hcp1Eff > hcp2
    } else {
      return (hcp1, hcp1 + (-manual)); // p2 recibe: hcp2Eff > hcp1
    }
  }

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

    final (hcp1, hcp2) = _effectiveHcps(round, p1Id, p2Id, mod.useHandicap);
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

    // Calcular HCPs efectivos (con sliding) UNA vez fuera del loop
    final (hcp1, hcp2) = _effectiveHcps(round, p1Id, p2Id, mod.useHandicap);
    final allHoles = round.course.holes;
    // Patrón bilateral igual que skins1v1 y matchAutoPress
    final p1IsBase    = hcp1 <= hcp2;
    final hcpBase     = p1IsBase ? hcp1 : hcp2;
    final hcpReceiver = p1IsBase ? hcp2 : hcp1;
    final baseId      = p1IsBase ? p1Id : p2Id;
    final receiverId  = p1IsBase ? p2Id : p1Id;

    // Iterar respetando startingNine para consistencia con skins/match
    final holeOrder = round.startingNine == StartingNine.back
        ? [...List.generate(9, (i) => i + 10), ...List.generate(9, (i) => i + 1)]
        : List.generate(round.totalHoles, (i) => i + 1);
    final holeMap = { for (final ch in allHoles) ch.hole: ch };

    for (final h in holeOrder) {
      final ch = holeMap[h]!;
      final sBase     = round.getScore(baseId,     h);
      final sReceiver = round.getScore(receiverId, h);
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

      // Convertir al sistema p1/p2 para el marcador
      final int delta;
      if      (grossBase < netReceiver) delta = p1IsBase ? 1 : -1;
      else if (grossBase > netReceiver) delta = p1IsBase ? -1 : 1;
      else                              delta = 0;

      // Front = hoyos 1-9, Back = hoyos 10-18 (por número real, no por orden de juego)
      if (h <= 9) front += delta;
      else        back  += delta;
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
    // Usa _effectiveHcps como única fuente de verdad para el cálculo de strokes,
    // igual que _skins1v1, _nassauPair y _buildHoleDeltas.
    int netFor(String pAId, String pBId) {
      if (!mod.useHandicap) return GameEngine.grossTotal(round, pAId);
      final (hcpA, hcpB) = _effectiveHcps(round, pAId, pBId, true);
      final allHoles = round.course.holes;
      // pA es base si hcpA <= hcpB; si es receptor, recibe strokes
      final pAIsBase    = hcpA <= hcpB;
      final hcpBase     = pAIsBase ? hcpA : hcpB;
      final hcpReceiver = pAIsBase ? hcpB : hcpA;
      int total = 0;
      for (int h = 1; h <= round.totalHoles; h++) {
        final s = round.getScore(pAId, h);
        if (!s.hasScore) continue;
        final ch = allHoles.firstWhere(
            (c) => c.hole == h, orElse: () => allHoles.first);
        // Solo el receptor recibe strokes; la base juega en bruto
        final strokesHere = pAIsBase ? 0 : GameEngine.strokesReceivedVs(
          hcpHigher: hcpReceiver,
          hcpLower:  hcpBase,
          ch: ch,
          allHoles: allHoles,
          startingNine: round.startingNine,
        );
        total += s.grossScore! - strokesHere;
      }
      return total;
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
    // CRÍTICO: usar _effectiveHcps para respetar manualHandicaps entre el par.
    // Antes se usaba round.getHandicap() directo (HCP bruto), ignorando el
    // ajuste manual → diff incorrecta → strokes por hoyo erróneos → score mal.
    final (hcp1, hcp2) = _effectiveHcps(round, p1Id, p2Id, mod.useHandicap);
    final p1IsBase    = hcp1 <= hcp2;
    final hcpBase     = p1IsBase ? hcp1 : hcp2;
    final hcpReceiver = p1IsBase ? hcp2 : hcp1;
    final baseId      = p1IsBase ? p1Id : p2Id;
    final receiverId  = p1IsBase ? p2Id : p1Id;

    final holeOrder = round.startingNine == StartingNine.back
        ? [...List.generate(9, (i) => i + 10), ...List.generate(9, (i) => i + 1)]
        : List.generate(round.totalHoles, (i) => i + 1);
    final holeMap = { for (final ch in allHoles) ch.hole: ch };

    // deltas[0] no se usa; índice 1-based
    final List<int> deltas = List.filled(holeOrder.length + 1, 0);

    for (int pos = 0; pos < holeOrder.length; pos++) {
      final h  = holeOrder[pos];
      final ch = holeMap[h] ?? allHoles.first;
      final s1 = round.getScore(p1Id, h);
      final s2 = round.getScore(p2Id, h);
      if (!s1.hasScore || !s2.hasScore) continue;

      final strokesHere = mod.useHandicap
          ? GameEngine.strokesReceivedVs(
              hcpHigher:    hcpReceiver,
              hcpLower:     hcpBase,
              ch:           ch,
              allHoles:     allHoles,
              startingNine: round.startingNine,
            )
          : 0;

      final grossBase   = round.getScore(baseId,     h).grossScore!;
      final netReceiver = round.getScore(receiverId, h).grossScore! - strokesHere;

      final int delta;
      if      (grossBase < netReceiver) delta = baseId == p1Id ?  1 : -1;
      else if (grossBase > netReceiver) delta = baseId == p1Id ? -1 :  1;
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

    // HCPs para el caso 1v1: usar _effectiveHcps para respetar manualHandicaps
    final (hcp1, hcp2) = _effectiveHcps(round, p1Id, p2Id, mod.useHandicap);
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
    // Usar _effectiveHcps para respetar manualHandicaps igual que _nassauPair
    final (hcp1, hcp2) = _effectiveHcps(round, p1Id, p2Id, mod.useHandicap);
    final p1IsBase    = hcp1 <= hcp2;
    final hcpBase     = p1IsBase ? hcp1 : hcp2;
    final hcpReceiver = p1IsBase ? hcp2 : hcp1;
    final baseId      = p1IsBase ? p1Id : p2Id;
    final receiverId  = p1IsBase ? p2Id : p1Id;
    final allHoles    = round.course.holes;

    int front = 0, back = 0;
    int frontPlayed = 0, backPlayed = 0;
    final List<int> frontHistory = [];
    final List<int> backHistory  = [];

    for (int h = 1; h <= round.totalHoles; h++) {
      final ch = round.course.holes.firstWhere((c) => c.hole == h);
      final sBase     = round.getScore(baseId,     h);
      final sReceiver = round.getScore(receiverId, h);
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
      final grossBase   = sBase.grossScore!;
      final netReceiver = sReceiver.grossScore! - strokesHere;
      final int delta;
      if      (grossBase < netReceiver) delta = p1IsBase ?  1 : -1;
      else if (grossBase > netReceiver) delta = p1IsBase ? -1 :  1;
      else                              delta = 0;

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
