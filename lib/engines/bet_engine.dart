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
      // ── Modo equipo: sides definidos y válidos ────────────────────────────
      if (mod.hasTeamSides) {
        switch (mod.type) {
          case BetModuleType.matchAutoPress:
            entries.addAll(_matchAutoPressTeam(round, mod));
            break;
          case BetModuleType.nassau:
            entries.addAll(_nassauTeam(round, mod));
            break;
          case BetModuleType.skins:
            // Skins en modo equipo: cada hoyo best-ball entre lados
            entries.addAll(_skinsTeam(round, mod));
            break;
          // nassauPress ya no existe como tipo separado; nassau unificado lo maneja
          default:
            // Medal, putts, oyeses, units: no tienen semántica de equipo aún.
            // Fallback: usar todos los jugadores de ambos lados en modo individual.
            entries.addAll(_computeModuleIndividual(round, group, mod));
        }
        continue;
      }

      // ── Modo individual clásico ───────────────────────────────────────────
      entries.addAll(_computeModuleIndividual(round, group, mod));
    }
    return entries;
  }

  /// Resuelve un módulo en modo individual (comportamiento previo, sin cambios).
  static List<LedgerEntry> _computeModuleIndividual(
      Round round, BetGroup group, BetModuleInstance mod) {
    final entries = <LedgerEntry>[];
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
    // Si las presiones están activas, usar el motor completo de press
    if (mod.nassau.pressEnabled) {
      return _nassauPressPair(round, p1Id, p2Id, mod);
    }

    final entries = <LedgerEntry>[];
    final cfg = mod.nassau;
    int front = 0, back = 0;

    final (hcp1, hcp2) = _effectiveHcps(round, p1Id, p2Id, mod.useHandicap);
    final allHoles = round.course.holes;
    final p1IsBase    = hcp1 <= hcp2;
    final hcpBase     = p1IsBase ? hcp1 : hcp2;
    final hcpReceiver = p1IsBase ? hcp2 : hcp1;
    final baseId      = p1IsBase ? p1Id : p2Id;
    final receiverId  = p1IsBase ? p2Id : p1Id;

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

      final grossBase   = sBase.grossScore!;
      final netReceiver = sReceiver.grossScore! - strokesHere;

      final int delta;
      if      (grossBase < netReceiver) delta = p1IsBase ? 1 : -1;
      else if (grossBase > netReceiver) delta = p1IsBase ? -1 : 1;
      else                              delta = 0;

      if (h <= 9) front += delta;
      else        back  += delta;
    }

    final total = front + back;
    if (round.totalHoles <= 9) {
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
  static List<LedgerEntry> _nassauPress(
      Round round, List<String> pids, BetModuleInstance mod) {
    final entries = <LedgerEntry>[];
    for (int i = 0; i < pids.length; i++) {
      for (int j = i + 1; j < pids.length; j++) {
        entries.addAll(_nassauPressPair(round, pids[i], pids[j], mod));
      }
    }
    return entries;
  }

  static List<LedgerEntry> _nassauPressPair(
      Round round, String p1Id, String p2Id, BetModuleInstance mod) {
    final entries = <LedgerEntry>[];
    // Usa la config unificada de NassauConfig (pressEnabled garantizado true aquí)
    final cfg = mod.nassau;

    final (hcp1, hcp2) = _effectiveHcps(round, p1Id, p2Id, mod.useHandicap);
    final p1IsBase    = hcp1 <= hcp2;
    final hcpBase     = p1IsBase ? hcp1 : hcp2;
    final hcpReceiver = p1IsBase ? hcp2 : hcp1;
    final baseId      = p1IsBase ? p1Id : p2Id;
    final receiverId  = p1IsBase ? p2Id : p1Id;
    final allHoles    = round.course.holes;
    final holeMap     = { for (final ch in allHoles) ch.hole: ch };

    // ── Determinar rango de hoyos según startingNine ─────────────────────────
    // Si la ronda empieza en el back (hoyos 10-18), los "9 hoyos del front"
    // son en realidad los hoyos 10-18 físicamente.
    final bool isBackStart = round.startingNine == StartingNine.back;
    // holeFrom1/holeTo1: primer segmento (lógicamente "front 9")
    final int seg1From = isBackStart ? 10 : 1;
    final int seg1To   = isBackStart ? 18 : 9;
    // holeFrom2/holeTo2: segundo segmento (lógicamente "back 9") — solo para 18 hoyos
    final int seg2From = isBackStart ? 1  : 10;
    final int seg2To   = isBackStart ? 9  : 18;

    // ── Calcular deltas hoyo a hoyo ──────────────────────────────────────────
    // delta > 0 → p1 gana el hoyo; delta < 0 → p2 gana; 0 → empate
    final Map<int, int> deltaByHole = {};
    // Iterar sobre todos los hoyos del curso (no solo 1..totalHoles)
    for (final ch in allHoles) {
      final h = ch.hole;
      final sBase     = round.getScore(baseId, h);
      final sReceiver = round.getScore(receiverId, h);
      if (!sBase.hasScore || !sReceiver.hasScore) continue;
      final strokes = mod.useHandicap
          ? GameEngine.strokesReceivedVs(
              hcpHigher: hcpReceiver, hcpLower: hcpBase,
              ch: ch, allHoles: allHoles, startingNine: round.startingNine)
          : 0;
      final grossBase    = sBase.grossScore!;
      final netReceiver  = sReceiver.grossScore! - strokes;
      if      (grossBase < netReceiver) deltaByHole[h] = p1IsBase ?  1 : -1;
      else if (grossBase > netReceiver) deltaByHole[h] = p1IsBase ? -1 :  1;
      else                              deltaByHole[h] = 0;
    }

    // ── Detectar carry (primer segmento empatado) ────────────────────────────
    int front = 0;
    for (int h = seg1From; h <= seg1To; h++) front += (deltaByHole[h] ?? 0);
    // carryEnabled ahora está en NassauConfig
    final carryActive = cfg.carryEnabled && cfg.carryApplied && front == 0;

    // ── Liquidar segmento con presiones ─────────────────────────────────────
    void liquidateSegment({
      required int holeFrom,
      required int holeTo,
      required double segValue,
      required double pressValue,
      required String segLabel,
    }) {
      // Score acumulado hoyo a hoyo dentro del segmento
      final List<int> history = [];
      for (int h = holeFrom; h <= holeTo; h++) {
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
          final startH = holeFrom + i + 1;
          if (startH <= holeTo) {
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
      // CORRECCIÓN: cada press cierra cuando empieza la SIGUIENTE press,
      // no al final del segmento. Así el score refleja solo el tramo de esa press.
      for (int k = 0; k < pressStarts.length; k++) {
        final ps = pressStarts[k];
        // Endpoint: inicio de la siguiente press (exclusive) o fin del segmento.
        final endIdx = (k + 1 < pressStarts.length)
            ? pressStarts[k + 1].startIdx - 1
            : history.length - 1;
        final pressScore = history[endIdx] - history[ps.startIdx - 1];
        addEntry(pressScore, pressValue,
            'Press H${ps.startHole}–H$holeTo ($segLabel)');
      }

      // Presiones manuales del módulo (no son match principal, en rango del segmento)
      for (final press in mod.presses) {
        if (press.isPrimaryMatch) continue; // solo presiones, no el match principal
        if (press.startHole < holeFrom || press.startHole > holeTo) continue;
        int manualScore = 0;
        for (int h = press.startHole; h <= holeTo; h++) {
          manualScore += (deltaByHole[h] ?? 0);
        }
        addEntry(manualScore, press.value,
            'Press Manual H${press.startHole}–H$holeTo ($segLabel)');
      }
    }

    // ── Aplicar segmentos ────────────────────────────────────────────────────
    if (round.totalHoles <= 9) {
      // Solo 9 hoyos: un único segmento usando el rango físico correcto
      liquidateSegment(
        holeFrom: seg1From, holeTo: seg1To,
        segValue:   cfg.frontValue,
        pressValue: cfg.frontPressValue,
        segLabel:   'Nassau 9H',
      );
    } else {
      // Primer segmento (lógicamente "Front 9")
      liquidateSegment(
        holeFrom: seg1From, holeTo: seg1To,
        segValue:   cfg.frontValue,
        pressValue: cfg.frontPressValue,
        segLabel:   'Nassau Front 9',
      );
      // Segundo segmento (lógicamente "Back 9", con carry si aplica)
      final effBack      = carryActive ? cfg.backValue      * cfg.carryFactor : cfg.backValue;
      final effBackPress = carryActive ? cfg.backPressValue * cfg.carryFactor : cfg.backPressValue;
      liquidateSegment(
        holeFrom: seg2From, holeTo: seg2To,
        segValue:   effBack,
        pressValue: effBackPress,
        segLabel:   'Nassau Back 9${carryActive ? ' (x${cfg.carryFactor.toStringAsFixed(0)})' : ''}',
      );
      // Total 18: suma todos los deltas disponibles
      int total = 0;
      for (final delta in deltaByHole.values) total += delta;
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
  // onePot  : un solo ganador cobra a todos.
  // allVsAll: cada par tiene su propio resultado independiente.
  //
  // Net score = suma hoyo a hoyo de (gross_hoyo − strokes_recibidos_en_ese_hoyo)
  // Los strokes por hoyo se distribuyen con strokesReceivedVs según el SI,
  // respetando la vuelta de inicio (startingNine) del round.
  // Así, si se juegan 9 hoyos, solo se contabilizan los strokes de esos 9 hoyos
  // (no los 18 totales), lo que produce el net correcto.
  static List<LedgerEntry> _medal(Round round, List<String> pids, BetModuleInstance mod) {
    final entries = <LedgerEntry>[];
    final cfg = mod.medal;
    final allHoles = round.course.holes;

    // Net de A relativo a B, sumando hoyo a hoyo los strokes distribuidos por SI.
    // Solo cuenta hoyos donde A tiene score registrado.
    // gross_hoyo(A) − strokes_que_A_recibe_en_ese_hoyo_vs_B
    int netInPair(String pA, String pB) {
      if (!mod.useHandicap) return GameEngine.grossTotal(round, pA);
      final (hcpA, hcpB) = _effectiveHcps(round, pA, pB, true);
      int net = 0;
      for (final ch in allHoles) {
        final score = round.getScore(pA, ch.hole);
        if (!score.hasScore) continue;
        final strokes = hcpA > hcpB
            ? GameEngine.strokesReceivedVs(
                hcpHigher: hcpA, hcpLower: hcpB,
                ch: ch, allHoles: allHoles,
                startingNine: round.startingNine)
            : 0;
        net += score.grossScore! - strokes;
      }
      return net;
    }

    if (mod.isAllVsAll && pids.length > 2) {
      // allVsAll: cada par (A, B) es completamente independiente.
      // net_A = sum_hoyos(gross_A - strokes_A_vs_B)
      // net_B = sum_hoyos(gross_B - strokes_B_vs_A)
      for (int i = 0; i < pids.length; i++) {
        for (int j = i + 1; j < pids.length; j++) {
          final netI = netInPair(pids[i], pids[j]);
          final netJ = netInPair(pids[j], pids[i]);
          if (netI < netJ) {
            entries.add(LedgerEntry(fromPlayerId: pids[j], toPlayerId: pids[i], amount: cfg.value, betType: BetModuleType.medal, reason: 'Medal'));
          } else if (netJ < netI) {
            entries.add(LedgerEntry(fromPlayerId: pids[i], toPlayerId: pids[j], amount: cfg.value, betType: BetModuleType.medal, reason: 'Medal'));
          }
        }
      }
      return entries;
    }

    // onePot (1v1 o grupo con un solo ganador):
    // Para 1v1: net_A vs B, net_B vs A (bilateral, hoyo a hoyo)
    // Para 3+: cada jugador calcula su net vs la base (menor HCP),
    //          todos los nets quedan en la misma escala.
    final nets = <String, int>{};
    if (pids.length == 2) {
      nets[pids[0]] = netInPair(pids[0], pids[1]);
      nets[pids[1]] = netInPair(pids[1], pids[0]);
    } else {
      if (!mod.useHandicap) {
        for (final pid in pids) {
          nets[pid] = GameEngine.grossTotal(round, pid);
        }
      } else {
        final base = pids.reduce((a, b) =>
            round.getHandicap(a) <= round.getHandicap(b) ? a : b);
        for (final pid in pids) {
          nets[pid] = netInPair(pid, base);
        }
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
          entries.add(LedgerEntry(
            fromPlayerId: loser, toPlayerId: winner,
            amount: cfg.value, betType: BetModuleType.oyeses,
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


  // ══════════════════════════════════════════════════════════════════════════
  // MODO EQUIPO — lado A vs lado B (best-ball)
  // ══════════════════════════════════════════════════════════════════════════

  // ── Helper: deltas hoyo a hoyo entre dos lados (usa holeDeltaVs) ──────────
  // Devuelve (holeOrder, deltas[1..n]) igual que _buildHoleDeltas.
  // hcpMap: todos los jugadores de ambos lados, HCP de ronda directo.
  // En modo gross puede pasarse un mapa vacío (todos 0.0).
  static (List<int>, List<int>) _buildHoleDeltasTeam(
      Round round, BetSide sideA, BetSide sideB, BetModuleInstance mod) {
    final allPlayerIds = [...sideA.playerIds, ...sideB.playerIds];
    final hcpMap = mod.useHandicap
        ? GameEngine.buildTeamHcpMap(round, allPlayerIds)
        : <String, double>{};

    final holeOrder = round.startingNine == StartingNine.back
        ? [...List.generate(9, (i) => i + 10), ...List.generate(9, (i) => i + 1)]
        : List.generate(round.totalHoles, (i) => i + 1);

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
        if (deltas[pos] != 0) played++;
        else {
          // También contar hoyos empatados (delta=0) que sí se jugaron
          final h = holeOrder[pos - 1];
          final allPlayed = [...sideA.playerIds, ...sideB.playerIds]
              .every((pid) => round.getScore(pid, h).hasScore);
          if (allPlayed) played++;
        }
      }
      if (played == 0) continue;
      final label = '${m.businessLabel} H${holeOrder[m.startPos - 1]}–H${holeOrder[m.endPos.clamp(1, holeOrder.length) - 1]} (${sideA.name} vs ${sideB.name})';
      if (score > 0) {
        // sideA gana: sideB paga a sideA (cada jugador de B paga a cada jugador de A)
        for (final pA in sideA.playerIds) {
          for (final pB in sideB.playerIds) {
            entries.add(LedgerEntry(
              fromPlayerId: pB, toPlayerId: pA,
              amount: m.value, betType: BetModuleType.matchAutoPress, reason: label,
            ));
          }
        }
      } else if (score < 0) {
        // sideB gana
        for (final pA in sideA.playerIds) {
          for (final pB in sideB.playerIds) {
            entries.add(LedgerEntry(
              fromPlayerId: pA, toPlayerId: pB,
              amount: m.value, betType: BetModuleType.matchAutoPress, reason: label,
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
        ? GameEngine.buildTeamHcpMap(round, allPlayerIds)
        : <String, double>{};

    final holeOrder = round.startingNine == StartingNine.back
        ? [...List.generate(9, (i) => i + 10), ...List.generate(9, (i) => i + 1)]
        : List.generate(round.totalHoles, (i) => i + 1);

    int front = 0, back = 0;
    for (final h in holeOrder) {
      final delta = GameEngine.holeDeltaVs(
        round: round, sideA: sideA, sideB: sideB,
        holeNum: h, useHandicap: mod.useHandicap, hcpMap: hcpMap,
      );
      if (delta == null) continue;
      if (h <= 9) front += delta;
      else        back  += delta;
    }
    final total = front + back;

    void addSegment(int margin, double value, String label) {
      if (margin == 0) return;
      // Si A gana (margin > 0): B paga a A — cruzado entre todos
      for (final pA in sideA.playerIds) {
        for (final pB in sideB.playerIds) {
          if (margin > 0) {
            entries.add(LedgerEntry(fromPlayerId: pB, toPlayerId: pA,
                amount: value, betType: BetModuleType.nassau, reason: label));
          } else {
            entries.add(LedgerEntry(fromPlayerId: pA, toPlayerId: pB,
                amount: value, betType: BetModuleType.nassau, reason: label));
          }
        }
      }
    }

    if (round.totalHoles <= 9) {
      addSegment(front, cfg.frontValue, 'Nassau 9 hoyos (${sideA.name} vs ${sideB.name})');
    } else {
      addSegment(front, cfg.frontValue,          'Nassau Front 9 (${sideA.name} vs ${sideB.name})');
      addSegment(back,  cfg.effectiveBackValue,  'Nassau Back 9 (${sideA.name} vs ${sideB.name})');
      addSegment(total, cfg.effectiveTotalValue, 'Nassau Total 18 (${sideA.name} vs ${sideB.name})');
    }
    return entries;
  }

  // ── SKINS (equipo best-ball por hoyo) ─────────────────────────────────────
  static List<LedgerEntry> _skinsTeam(Round round, BetModuleInstance mod) {
    final entries = <LedgerEntry>[];
    final sideA = mod.sideA;
    final sideB = mod.sideB;
    final cfg   = mod.skins;
    double pot  = cfg.valuePerSkin;

    final allPlayerIds = [...sideA.playerIds, ...sideB.playerIds];
    final hcpMap = mod.useHandicap
        ? GameEngine.buildTeamHcpMap(round, allPlayerIds)
        : <String, double>{};

    final holeOrder = round.startingNine == StartingNine.back
        ? [...List.generate(9, (i) => i + 10), ...List.generate(9, (i) => i + 1)]
        : List.generate(round.totalHoles, (i) => i + 1);

    for (final h in holeOrder) {
      final delta = GameEngine.holeDeltaVs(
        round: round, sideA: sideA, sideB: sideB,
        holeNum: h, useHandicap: mod.useHandicap, hcpMap: hcpMap,
      );
      if (delta == null) continue; // hoyo no completado

      if (delta != 0) {
        final winners = delta > 0 ? sideA.playerIds : sideB.playerIds;
        final losers  = delta > 0 ? sideB.playerIds : sideA.playerIds;
        final share   = pot / losers.length;
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
        ? GameEngine.buildTeamHcpMap(round, allPlayerIds)
        : <String, double>{};

    // Respetar startingNine igual que nassauLiveStatus individual
    final bool isBack  = round.startingNine == StartingNine.back;
    final int seg1From = isBack ? 10 : 1;
    final int seg1To   = isBack ? 18 : 9;
    final int seg2From = isBack ? 1  : 10;
    final int seg2To   = isBack ? 9  : 18;

    int front = 0, back = 0;
    int frontPlayed = 0, backPlayed = 0;
    final List<int> frontHistory = [];
    final List<int> backHistory  = [];

    for (int h = 1; h <= round.totalHoles; h++) {
      final delta = GameEngine.holeDeltaVs(
        round: round, sideA: sideA, sideB: sideB,
        holeNum: h, useHandicap: mod.useHandicap, hcpMap: hcpMap,
      );
      if (delta == null) continue;

      if (h >= seg1From && h <= seg1To) {
        front += delta; frontPlayed++; frontHistory.add(front);
      } else if (h >= seg2From && h <= seg2To) {
        back  += delta; backPlayed++;  backHistory.add(back);
      }
    }

    final idA = sideA.playerIds.first;
    final idB = sideB.playerIds.first;

    final List<NassauPress> presses = [];
    if (cfg.pressEnabled) {
      _detectPresses(presses, frontHistory, seg1From, seg1To, frontPlayed,
          idA, idB, cfg.autoPressTrigger);
      _detectPresses(presses, backHistory, seg2From, seg2To, backPlayed,
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
        final pids = mod.participantIds.isNotEmpty ? mod.participantIds : group.playerIds;
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

        // Mismo cálculo que _medal: net hoyo a hoyo usando strokesReceivedVs.
        // Así los strokes se distribuyen por SI en los hoyos JUGADOS,
        // sin importar si es 9 o 18 hoyos.
        int netInPairDiag(String pA, String pB) {
          if (!mod.useHandicap) return grosses[pA] ?? 0;
          final (hcpA, hcpB) = _effectiveHcps(round, pA, pB, true);
          int net = 0;
          for (final ch in allHoles) {
            final score = round.getScore(pA, ch.hole);
            if (!score.hasScore) continue;
            final strokes = hcpA > hcpB
                ? GameEngine.strokesReceivedVs(
                    hcpHigher: hcpA, hcpLower: hcpB,
                    ch: ch, allHoles: allHoles,
                    startingNine: round.startingNine)
                : 0;
            net += score.grossScore! - strokes;
          }
          return net;
        }

        // Strokes totales recibidos en los hoyos jugados (para mostrar en UI)
        int strokesInPlayedHoles(String pA, String pB) {
          if (!mod.useHandicap) return 0;
          final (hcpA, hcpB) = _effectiveHcps(round, pA, pB, true);
          if (hcpA <= hcpB) return 0;
          int total = 0;
          for (final ch in allHoles) {
            final score = round.getScore(pA, ch.hole);
            if (!score.hasScore) continue;
            total += GameEngine.strokesReceivedVs(
                hcpHigher: hcpA, hcpLower: hcpB,
                ch: ch, allHoles: allHoles,
                startingNine: round.startingNine);
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
          // onePot 3+: base = jugador con menor HCP
          if (!mod.useHandicap) {
            for (final pid in pids) {
              nets[pid] = grosses[pid]!;
              strokesMap[pid] = 0;
            }
          } else {
            final base = pids.reduce((a, b) =>
                round.getHandicap(a) <= round.getHandicap(b) ? a : b);
            for (final pid in pids) {
              nets[pid] = netInPairDiag(pid, base);
              strokesMap[pid] = strokesInPlayedHoles(pid, base);
            }
          }
          final sorted = pids.toList()..sort((a, b) => (nets[a] ?? 999).compareTo(nets[b] ?? 999));
          if ((nets[sorted[0]] ?? 999) == (nets[sorted[1]] ?? 999)) {
            reason = 'EMPATE entre ${sorted[0]} y ${sorted[1]} (net=${nets[sorted[0]]}) → sin entry';
          } else {
            final base = mod.useHandicap
                ? pids.reduce((a, b) => round.getHandicap(a) <= round.getHandicap(b) ? a : b)
                : pids.first;
            final winNetStr = pids.map((pid) =>
                '$pid gross${grosses[pid]}-${strokesMap[pid]}=net${nets[pid]}').join(', ');
            reason = 'Base: $base | ${sorted[0]} gana (net=${nets[sorted[0]]}) | $winNetStr';
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
    final (hcp1, hcp2) = _effectiveHcps(round, p1Id, p2Id, mod.useHandicap);
    final p1IsBase    = hcp1 <= hcp2;
    final hcpBase     = p1IsBase ? hcp1 : hcp2;
    final hcpReceiver = p1IsBase ? hcp2 : hcp1;
    final baseId      = p1IsBase ? p1Id : p2Id;
    final receiverId  = p1IsBase ? p2Id : p1Id;
    final allHoles    = round.course.holes;

    // Respetar startingNine: primer segmento = hoyos que se juegan primero
    final bool isBack   = round.startingNine == StartingNine.back;
    final int seg1From  = isBack ? 10 : 1;
    final int seg1To    = isBack ? 18 : 9;
    final int seg2From  = isBack ? 1  : 10;
    final int seg2To    = isBack ? 9  : 18;

    int front = 0, back = 0;
    int frontPlayed = 0, backPlayed = 0;
    int holesWonP1 = 0, holesWonP2 = 0;
    final List<int> frontHistory = [];
    final List<int> backHistory  = [];

    for (final ch in allHoles) {
      final h         = ch.hole;
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

      // Conteo individual de hoyos ganados (para el badge visual)
      if (delta > 0) holesWonP1++;
      else if (delta < 0) holesWonP2++;

      if (h >= seg1From && h <= seg1To) {
        front += delta; frontPlayed++; frontHistory.add(front);
      } else if (h >= seg2From && h <= seg2To) {
        back  += delta; backPlayed++;  backHistory.add(back);
      }
    }

    // Normalizar history a perspectiva de p1: positivo = p1 arriba.
    // Si p1 no es el base, el delta fue calculado con signo invertido,
    // por lo que hay que multiplicar por -1 antes de detectar presiones.
    final List<int> normFrontHistory = p1IsBase ? frontHistory : frontHistory.map((v) => -v).toList();
    final List<int> normBackHistory  = p1IsBase ? backHistory  : backHistory.map((v) => -v).toList();

    final List<NassauPress> presses = [];
    if (cfg.pressEnabled) {
      _detectPresses(presses, normFrontHistory, seg1From, seg1To, frontPlayed,
          p1Id, p2Id, cfg.autoPressTrigger);
      _detectPresses(presses, normBackHistory, seg2From, seg2To, backPlayed,
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
    final (hcp1, hcp2) = _effectiveHcps(round, p1Id, p2Id, mod.useHandicap);
    final p1IsBase    = hcp1 <= hcp2;
    final hcpBase     = p1IsBase ? hcp1 : hcp2;
    final hcpReceiver = p1IsBase ? hcp2 : hcp1;
    final baseId      = p1IsBase ? p1Id : p2Id;
    final receiverId  = p1IsBase ? p2Id : p1Id;
    final allHoles    = round.course.holes;

    // Respetar startingNine: si la ronda es back, el "primer segmento" es hoyos 10-18
    final bool liveIsBack  = round.startingNine == StartingNine.back;
    final int liveSeg1From = liveIsBack ? 10 : 1;
    final int liveSeg1To   = liveIsBack ? 18 : 9;
    final int liveSeg2From = liveIsBack ? 1  : 10;
    final int liveSeg2To   = liveIsBack ? 9  : 18;

    int front = 0, back = 0;
    int frontPlayed = 0, backPlayed = 0;
    final List<int> frontHistory = [];
    final List<int> backHistory  = [];

    // Iterar sobre todos los hoyos del curso
    for (final ch in allHoles) {
      final h = ch.hole;
      final sBase     = round.getScore(baseId,     h);
      final sReceiver = round.getScore(receiverId, h);
      if (!sBase.hasScore || !sReceiver.hasScore) continue;
      final strokes = mod.useHandicap
          ? GameEngine.strokesReceivedVs(
              hcpHigher: hcpReceiver, hcpLower: hcpBase,
              ch: ch, allHoles: allHoles, startingNine: round.startingNine)
          : 0;
      final grossBase   = sBase.grossScore!;
      final netReceiver = sReceiver.grossScore! - strokes;
      final int delta;
      if      (grossBase < netReceiver) delta = p1IsBase ?  1 : -1;
      else if (grossBase > netReceiver) delta = p1IsBase ? -1 :  1;
      else                              delta = 0;

      // Asignar al segmento correcto según el rango físico de hoyos
      if (h >= liveSeg1From && h <= liveSeg1To) {
        front += delta; frontPlayed++; frontHistory.add(front);
      } else if (h >= liveSeg2From && h <= liveSeg2To) {
        back  += delta; backPlayed++;  backHistory.add(back);
      }
    }

    // Carry: primer segmento completo y empatado
    final f9Complete  = frontPlayed == 9;
    final carryActive = cfg.carryEnabled && cfg.carryApplied && f9Complete && front == 0;

    // Valores efectivos
    final effBackVal       = carryActive ? cfg.backValue      * cfg.carryFactor : cfg.backValue;
    final effBackPressVal  = carryActive ? cfg.backPressValue * cfg.carryFactor : cfg.backPressValue;
    final effTotalVal      = carryActive ? cfg.totalValue     * cfg.carryFactor : cfg.totalValue;

    // Normalizar history a perspectiva de p1: positivo = p1 arriba.
    // Si p1 no es el base, el delta fue calculado con signo invertido.
    final List<int> normFrontHistoryP = p1IsBase ? frontHistory : frontHistory.map((v) => -v).toList();
    final List<int> normBackHistoryP  = p1IsBase ? backHistory  : backHistory.map((v) => -v).toList();

    // Presiones primer segmento (físicamente liveSeg1From..liveSeg1To)
    final List<NassauPress> frontPresses = [];
    _detectPresses(frontPresses, normFrontHistoryP, liveSeg1From, liveSeg1To, frontPlayed,
        p1Id, p2Id, cfg.autoPressTrigger);
    // Presiones segundo segmento (físicamente liveSeg2From..liveSeg2To)
    final List<NassauPress> backPresses  = [];
    _detectPresses(backPresses, normBackHistoryP, liveSeg2From, liveSeg2To, backPlayed,
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

  static void _detectPresses(
    List<NassauPress> out,
    List<int> history,
    int holeStart, int holeEnd,
    int played,
    String p1Id, String p2Id,
    int trigger,
  ) {
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
        final startHole = holeStart + i + 1;
        if (startHole <= holeEnd) {
          final loser = relDiff < 0 ? p1Id : p2Id;
          triggers.add((trigIdx: i, loser: loser, startHole: startHole));
          refIdx = i + 1;
        }
      }
    }

    final segmentHoles = holeEnd - holeStart + 1;
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
