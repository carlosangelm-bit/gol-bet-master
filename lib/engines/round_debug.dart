// ignore_for_file: avoid_print
// =============================================================================
// round_debug.dart — Helpers de diagnóstico runtime para el motor de apuestas
//
// USO:
//   import 'package:golf_bet_master/engines/round_debug.dart';
//
//   // Desde test, log manual o UI debug:
//   print(RoundDebug.explainSlidingPair(round, 'A', 'B'));
//   print(RoundDebug.explainRoundState(round, group));
//   print(RoundDebug.explainModuleComputation(round, group, mod));
//
// RESTRICCIÓN: NO produce logs automáticos en producción.
// Todos los métodos son funciones puras que retornan String.
// Para activarlos en producción, pasar debugMode: true al llamador.
// =============================================================================

import '../models/models.dart';
import 'bet_engine.dart';
import 'game_engine.dart';

/// Fuente detectada para el sliding de un par.
enum SlidingSource {
  pairSliding,   // fuente canónica (nueva)
  legacyBilateral, // legacy manualHandicaps — ambas direcciones presentes y consistentes
  legacyUnilateral, // legacy manualHandicaps — solo una dirección presente
  hcpFallback,   // diferencia de handicap (sin ningún manual)
  inconsistency, // legacy inconsistente (lanzaría StateError)
}

// ─────────────────────────────────────────────────────────────────────────────
// Clase principal de diagnóstico
// ─────────────────────────────────────────────────────────────────────────────

class RoundDebug {

  // ──────────────────────────────────────────────────────────────────────────
  // 1. explainSlidingPair
  // ──────────────────────────────────────────────────────────────────────────

  /// Diagnostica la fuente y los valores de sliding para el par (a, b).
  ///
  /// Imprime:
  ///  - IDs de ambos jugadores y sus handicaps
  ///  - Clave canónica del par
  ///  - Valor almacenado en pairSliding (si existe)
  ///  - recv(a,b) y recv(b,a) calculados
  ///  - Fuente usada: pairSliding / legacyBilateral / legacyUnilateral / hcpFallback / inconsistency
  ///  - Si existe override explícito a 0
  ///  - Si hay inconsistencia detectada en legacy
  static String explainSlidingPair(Round round, String aId, String bId) {
    final buf = StringBuffer();
    buf.writeln('── Sliding Pair $aId vs $bId ──────────────────────');

    // Handicaps
    final hcpA = round.getHandicap(aId);
    final hcpB = round.getHandicap(bId);
    buf.writeln('  hcp($aId)=${hcpA.toStringAsFixed(1)}  hcp($bId)=${hcpB.toStringAsFixed(1)}');

    // Clave canónica
    final key = BetEngine.pairKey(aId, bId);
    buf.writeln('  pairKey=$key');

    // pairSliding
    final stored = round.pairSliding[key];
    if (stored != null) {
      buf.writeln('  pairSliding[$key]=${stored > 0 ? '+' : ''}${stored.toStringAsFixed(2)}');
    } else {
      buf.writeln('  pairSliding[$key]=<no existe>');
    }

    // recv calculados
    double? recvAB, recvBA;
    String? errorMsg;
    try {
      recvAB = BetEngine.strokesP1ReceivesFromP2(round, aId, bId);
      recvBA = BetEngine.strokesP1ReceivesFromP2(round, bId, aId);
    } catch (e) {
      errorMsg = e.toString();
    }

    if (errorMsg != null) {
      buf.writeln('  ⚠️  ERROR al calcular recv: $errorMsg');
    } else {
      // Normalizar -0.0 → 0.0 para evitar el string "+-0.00"
      final normAB = recvAB! == 0.0 ? 0.0 : recvAB;
      final normBA = recvBA! == 0.0 ? 0.0 : recvBA;
      final fmtAB = normAB >= 0 ? '+${normAB.toStringAsFixed(2)}' : normAB.toStringAsFixed(2);
      final fmtBA = normBA >= 0 ? '+${normBA.toStringAsFixed(2)}' : normBA.toStringAsFixed(2);
      buf.writeln('  recv($aId,$bId)=$fmtAB');
      buf.writeln('  recv($bId,$aId)=$fmtBA');

      // Override explícito 0
      if (stored != null && stored == 0.0) {
        buf.writeln('  ℹ️  Override explícito: pairSliding=0 (sin ventaja ni intercambio)');
      }
    }

    // Detectar fuente
    final source = _detectSlidingSource(round, aId, bId);
    buf.writeln('  source=${_sourceLabel(source)}');

    // Detalles legacy si aplica
    if (source == SlidingSource.legacyBilateral ||
        source == SlidingSource.legacyUnilateral ||
        source == SlidingSource.inconsistency) {
      final rpA = round.roundPlayers.where((r) => r.playerId == aId).firstOrNull;
      final rpB = round.roundPlayers.where((r) => r.playerId == bId).firstOrNull;
      final mAB = rpA?.manualHandicaps[bId];
      final mBA = rpB?.manualHandicaps[aId];
      if (mAB != null) {
        buf.writeln('  legacy manual[$aId][$bId]=${mAB >= 0 ? '+' : ''}${mAB.toStringAsFixed(2)}');
      }
      if (mBA != null) {
        buf.writeln('  legacy manual[$bId][$aId]=${mBA >= 0 ? '+' : ''}${mBA.toStringAsFixed(2)}');
      }
      if (source == SlidingSource.inconsistency) {
        buf.writeln('  ❌ INCONSISTENCIA: manual[$aId][$bId]=$mAB ≠ -manual[$bId][$aId]=$mBA');
        buf.writeln('     Esto lanzaría StateError en el engine.');
      }
    }

    if (source == SlidingSource.hcpFallback) {
      buf.writeln('  ℹ️  Fallback HCP: hcp($aId)-hcp($bId)=${(hcpA-hcpB).toStringAsFixed(1)}');
    }

    buf.write('────────────────────────────────────────────────────');
    return buf.toString();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 2. explainModuleComputation
  // ──────────────────────────────────────────────────────────────────────────

  /// Diagnostica el cálculo completo de un módulo de apuesta.
  ///
  /// Para todos los tipos de módulo imprime:
  ///  - tipo de apuesta, participantes, modo (allVsAll/onePot), team/individual, useHandicap
  /// Para módulos con pares (Nassau, Medal, Skins):
  ///  - por par: gross total, recv, net aproximado, resultado
  /// Para Nassau sin press:
  ///  - holeOrder, segmentación Front/Back, deltas por hoyo (agrupados), carry
  /// Siempre al final:
  ///  - ledger entries generadas por este módulo
  static String explainModuleComputation(
    Round round,
    BetGroup group,
    BetModuleInstance mod,
  ) {
    final buf = StringBuffer();
    buf.writeln('── Module: ${mod.type.label} (${mod.id}) ──────────────────');
    buf.writeln('  tipo=${mod.type.name}');

    final pids = mod.effectivePids(group.playerIds);
    buf.writeln('  participantes=${pids.join(', ')}');

    // Modo
    if (mod.hasTeamSides) {
      buf.writeln('  modo=EQUIPO  sideA=${mod.sideA.playerIds}  sideB=${mod.sideB.playerIds}');
    } else {
      buf.writeln('  modo=${mod.isAllVsAll ? 'allVsAll' : 'onePot'} individual');
    }
    buf.writeln('  useHandicap=${mod.useHandicap}');

    // Detalle por tipo
    switch (mod.type) {
      case BetModuleType.nassau:
        _explainNassauPairs(buf, round, pids, mod);
        break;
      case BetModuleType.medal:
        _explainMedalPairs(buf, round, pids, mod);
        break;
      case BetModuleType.skins:
        _explainSkinsByHole(buf, round, pids, mod);
        break;
      case BetModuleType.oyeses:
        _explainOyesesByHole(buf, round, pids, mod);
        break;
      default:
        buf.writeln('  (detalle por hoyo no implementado para ${mod.type.name})');
    }

    // Ledger entries
    List<LedgerEntry> entries;
    try {
      entries = BetEngine.computeGroup(round, group)
          .where((e) => e.betType == mod.type)
          .toList();
    } catch (e) {
      buf.writeln('  ❌ ERROR al computar: $e');
      buf.write('────────────────────────────────────────────────────');
      return buf.toString();
    }

    buf.writeln('  ── LedgerEntries (${entries.length}) ────────────');
    if (entries.isEmpty) {
      buf.writeln('  (sin entradas — empate o datos insuficientes)');
    } else {
      for (final e in entries) {
        final holeStr = e.hole != null ? ' H${e.hole}' : '';
        buf.writeln('    ${e.fromPlayerId} → ${e.toPlayerId}  \$${e.amount.toStringAsFixed(2)}$holeStr  ${e.reason}');
      }
    }

    buf.write('────────────────────────────────────────────────────');
    return buf.toString();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 3. explainRoundState
  // ──────────────────────────────────────────────────────────────────────────

  /// Resumen completo del estado de una ronda y sus grupos de apuesta.
  ///
  /// Imprime:
  ///  - round id, isLive, liveCode, startingNine, totalHoles
  ///  - course holes disponibles con par y SI
  ///  - roundPlayers con handicap y manualHandicaps
  ///  - pairSliding canónico completo
  ///  - manualHandicaps legacy (si existen)
  ///  - betGroups y módulos activos
  ///  - validación de pairSliding (errores si los hay)
  static String explainRoundState(Round round, [BetGroup? group]) {
    final buf = StringBuffer();
    buf.writeln('══════════════════════════════════════════════════════');
    buf.writeln('  ROUND STATE DIAGNOSTIC');
    buf.writeln('══════════════════════════════════════════════════════');

    // Identificadores
    buf.writeln('  id=${round.id}');
    buf.writeln('  name="${round.name}"');
    buf.writeln('  isLive=${round.isLive}');
    if (round.liveCode != null) buf.writeln('  liveCode=${round.liveCode}');
    buf.writeln('  startingNine=${round.startingNine.name}');
    buf.writeln('  totalHoles=${round.totalHoles}');

    // Course holes
    buf.writeln('  ── Course: "${round.course.name}" ──────────────');
    buf.writeln('  hoyos disponibles: ${round.course.holes.length}');
    for (final ch in round.course.holes) {
      final p3 = ch.isPar3 ? ' [par3]' : '';
      buf.writeln('    H${ch.hole.toString().padLeft(2)}  par=${ch.par}  SI=${ch.strokeIndex.toString().padLeft(2)}$p3');
    }

    // RoundPlayers
    buf.writeln('  ── RoundPlayers ────────────────────────────────');
    for (final rp in round.roundPlayers) {
      buf.writeln('  ${rp.playerId}  hcp=${rp.handicapEnRonda.toStringAsFixed(1)}');
      if (rp.manualHandicaps.isNotEmpty) {
        for (final me in rp.manualHandicaps.entries) {
          final sign = me.value >= 0 ? '+' : '';
          buf.writeln('    legacy manual[${rp.playerId}][${me.key}]=$sign${me.value.toStringAsFixed(2)}');
        }
      }
    }

    // pairSliding canónico
    buf.writeln('  ── pairSliding (canónico) ──────────────────────');
    if (round.pairSliding.isEmpty) {
      buf.writeln('  (vacío — sin acuerdos canónicos)');
    } else {
      for (final e in round.pairSliding.entries) {
        final sign = e.value >= 0 ? '+' : '';
        buf.writeln('  ${e.key}  =  $sign${e.value.toStringAsFixed(2)}');
      }
    }

    // Validación pairSliding
    final errors = BetEngine.validatePairSliding(round);
    if (errors.isNotEmpty) {
      buf.writeln('  ── ❌ Errores detectados en pairSliding ────────');
      for (final err in errors) {
        buf.writeln('  • $err');
      }
    } else {
      buf.writeln('  ✅ pairSliding: sin errores de validación');
    }

    // oyeseRankings
    if (round.oyeseRankings.isNotEmpty) {
      buf.writeln('  ── oyeseRankings ───────────────────────────────');
      for (final e in round.oyeseRankings.entries) {
        buf.writeln('  H${e.key}: ${e.value.ranking.asMap().entries.map((r) => '${r.key + 1}°=${r.value}').join('  ')}');
      }
    }

    // Scores summary
    final allPids = round.roundPlayers.map((r) => r.playerId).toList();
    if (allPids.isNotEmpty) {
      buf.writeln('  ── Scores (hoyos jugados) ──────────────────────');
      for (final pid in allPids) {
        final holesPlayed = round.course.holes
            .where((ch) => round.getScore(pid, ch.hole).hasScore)
            .length;
        buf.writeln('  $pid: $holesPlayed/${round.course.holes.length} hoyos');
      }
    }

    // BetGroups
    final groups = group != null ? [group] : round.betGroups;
    buf.writeln('  ── BetGroups (${groups.length}) ─────────────────────');
    for (final g in groups) {
      buf.writeln('  Group "${g.name}" [${g.id}]  players=${g.playerIds.join(', ')}');
      for (final m in g.modules) {
        final cfgSummary = _moduleCfgSummary(m);
        buf.writeln('    • ${m.type.name.padRight(14)} ${m.id.substring(0, m.id.length.clamp(0, 8))}...  $cfgSummary');
      }
    }

    buf.writeln('══════════════════════════════════════════════════════');
    return buf.toString();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Helpers privados
  // ──────────────────────────────────────────────────────────────────────────

  static SlidingSource _detectSlidingSource(Round round, String aId, String bId) {
    final key = BetEngine.pairKey(aId, bId);
    if (round.pairSliding.containsKey(key)) return SlidingSource.pairSliding;

    final rpA = round.roundPlayers.where((r) => r.playerId == aId).firstOrNull;
    final rpB = round.roundPlayers.where((r) => r.playerId == bId).firstOrNull;
    final mAB = rpA?.manualHandicaps[bId];
    final mBA = rpB?.manualHandicaps[aId];

    if (mAB != null && mBA != null) {
      if ((mAB + mBA).abs() > 0.01) return SlidingSource.inconsistency;
      return SlidingSource.legacyBilateral;
    }
    if (mAB != null || mBA != null) return SlidingSource.legacyUnilateral;
    return SlidingSource.hcpFallback;
  }

  static String _sourceLabel(SlidingSource s) => switch (s) {
    SlidingSource.pairSliding      => 'pairSliding (canónico)',
    SlidingSource.legacyBilateral  => 'legacy manualHandicaps (bilateral consistente)',
    SlidingSource.legacyUnilateral => 'legacy manualHandicaps (unilateral)',
    SlidingSource.hcpFallback      => 'hcp fallback',
    SlidingSource.inconsistency    => '❌ INCONSISTENCIA (legacy bilateral incoherente)',
  };

  static void _explainNassauPairs(
      StringBuffer buf, Round round, List<String> pids, BetModuleInstance mod) {
    final cfg = mod.nassau;
    final isBack = round.startingNine == StartingNine.back;
    buf.writeln('  nassauMode=${cfg.pressEnabled ? 'con press (trigger=${cfg.autoPressTrigger})' : 'sin press'}');
    buf.writeln('  carry=${cfg.carryEnabled}  carryApplied=${cfg.carryApplied}');
    buf.writeln('  startingNine=${round.startingNine.name}  → seg1=${isBack ? '10-18' : '1-9'}  seg2=${isBack ? '1-9' : '10-18'}');

    for (int i = 0; i < pids.length; i++) {
      for (int j = i + 1; j < pids.length; j++) {
        final a = pids[i];
        final b = pids[j];
        buf.writeln('  ·· Par $a vs $b ··');
        _explainPairSlidingLine(buf, round, a, b);

        // Deltas por segmento
        final allHoles = round.course.holes;
        final seg1From = isBack ? 10 : 1;
        final seg1To   = isBack ? 18 : 9;
        int front = 0, back = 0;
        final deltaLines = <String>[];

        double recv;
        try {
          recv = BetEngine.strokesP1ReceivesFromP2(round, a, b);
        } catch (_) {
          buf.writeln('    ❌ Error calculando recv — no se puede mostrar deltas');
          continue;
        }

        final p1IsBase   = recv <= 0;
        final baseId     = p1IsBase ? a : b;
        final receiverId = p1IsBase ? b : a;
        final recvAbs    = recv.abs().round();
        final receiverPlayedHoles = allHoles
            .where((ch) => round.getScore(receiverId, ch.hole).hasScore)
            .toList();

        for (final ch in allHoles) {
          final sBase     = round.getScore(baseId,     ch.hole);
          final sReceiver = round.getScore(receiverId, ch.hole);
          if (!sBase.hasScore || !sReceiver.hasScore) continue;
          final strokes = mod.useHandicap && recvAbs > 0
              ? GameEngine.strokesReceivedInPlayedHoles(
                  diff: recvAbs, ch: ch, playedHoles: receiverPlayedHoles)
              : 0;
          final gB = sBase.grossScore!;
          final nR = sReceiver.grossScore! - strokes;
          final int delta;
          if (gB < nR) {
            delta = p1IsBase ?  1 : -1;
          } else if (gB > nR) {
            delta = p1IsBase ? -1 :  1;
          } else {
            delta = 0;
          }
          final seg = (ch.hole >= seg1From && ch.hole <= seg1To) ? 'F' : 'B';
          if (ch.hole >= seg1From && ch.hole <= seg1To) {
            front += delta;
          } else {
            back += delta;
          }
          deltaLines.add('H${ch.hole}[$seg]=${delta >= 0 ? '+' : ''}$delta');
        }

        buf.writeln('    deltas: ${deltaLines.join('  ')}');
        buf.writeln('    Front=${front >= 0 ? '+' : ''}$front  Back=${back >= 0 ? '+' : ''}$back  Total=${front+back >= 0 ? '+' : ''}${front+back}');
      }
    }
  }

  static void _explainMedalPairs(
      StringBuffer buf, Round round, List<String> pids, BetModuleInstance mod) {
    buf.writeln('  medalMode=${mod.isAllVsAll ? 'allVsAll' : 'onePot'}  useHcp=${mod.useHandicap}');
    if (mod.isAllVsAll) {
      for (int i = 0; i < pids.length; i++) {
        for (int j = i + 1; j < pids.length; j++) {
          final a = pids[i];
          final b = pids[j];
          buf.writeln('  ·· Par $a vs $b ··');
          _explainPairSlidingLine(buf, round, a, b);
          final grossA = _grossTotal(round, a);
          final grossB = _grossTotal(round, b);
          buf.writeln('    gross($a)=$grossA  gross($b)=$grossB');
        }
      }
    } else {
      for (final pid in pids) {
        buf.writeln('    gross($pid)=${_grossTotal(round, pid)}');
      }
    }
  }

  static void _explainSkinsByHole(
      StringBuffer buf, Round round, List<String> pids, BetModuleInstance mod) {
    final allHoles = round.course.holes;
    buf.writeln('  skinsMode=${mod.skins.carryOver ? 'carryOver' : 'sin carry'}');
    for (final ch in allHoles) {
      final hasAll = pids.every((pid) => round.getScore(pid, ch.hole).hasScore);
      if (!hasAll) continue;
      final scores = {for (final pid in pids) pid: round.getScore(pid, ch.hole).grossScore!};
      final minScore = scores.values.reduce((a, b) => a < b ? a : b);
      final winners = scores.entries.where((e) => e.value == minScore).map((e) => e.key).toList();
      buf.writeln('    H${ch.hole}: ${scores.entries.map((e) => '${e.key}=${e.value}').join(' ')}  → ${winners.length == 1 ? 'gana ${winners.first}' : 'empate'}');
    }
  }

  static void _explainOyesesByHole(
      StringBuffer buf, Round round, List<String> pids, BetModuleInstance mod) {
    final cfg = mod.oyeses;
    final par3Holes = round.course.holes.where((h) => h.isPar3).toList();
    final eligible = cfg.eligibleHoles.isNotEmpty
        ? par3Holes.where((h) => cfg.eligibleHoles.contains(h.hole)).toList()
        : par3Holes;

    buf.writeln('  par3Holes=${par3Holes.map((h) => 'H${h.hole}').join(', ')}');
    buf.writeln('  eligibleHoles=${eligible.map((h) => 'H${h.hole}').join(', ')}');
    buf.writeln('  zapatoEnabled=${cfg.zapatoEnabled}  zapatoValue=${cfg.zapatoValue}');

    for (final ch in eligible) {
      final ranking = round.getOyese(ch.hole);
      if (ranking == null || ranking.ranking.isEmpty) {
        buf.writeln('    H${ch.hole}: <sin ranking>');
      } else {
        final relevant = ranking.ranking.where((pid) => pids.contains(pid)).toList();
        buf.writeln('    H${ch.hole}: ${relevant.asMap().entries.map((e) => '${e.key + 1}°=${e.value}').join('  ')}');
      }
    }
  }

  static void _explainPairSlidingLine(
      StringBuffer buf, Round round, String a, String b) {
    try {
      final recvAB = BetEngine.strokesP1ReceivesFromP2(round, a, b);
      final src    = _detectSlidingSource(round, a, b);
      final sign   = recvAB >= 0 ? '+' : '';
      buf.writeln('    recv($a,$b)=$sign${recvAB.toStringAsFixed(2)}  src=${_sourceLabel(src)}');
    } catch (e) {
      buf.writeln('    recv($a,$b)=❌ ERROR: $e');
    }
  }

  static int _grossTotal(Round round, String pid) {
    int total = 0;
    for (final ch in round.course.holes) {
      final s = round.getScore(pid, ch.hole);
      if (s.hasScore) total += s.grossScore!;
    }
    return total;
  }

  static String _moduleCfgSummary(BetModuleInstance m) {
    return switch (m.type) {
      BetModuleType.nassau  => '\$${m.nassau.frontValue.toStringAsFixed(0)}F/\$${m.nassau.backValue.toStringAsFixed(0)}B/\$${m.nassau.totalValue.toStringAsFixed(0)}T press=${m.nassau.pressEnabled}',
      BetModuleType.medal   => '\$${m.medal.value.toStringAsFixed(0)} ${m.medal.mode.name} ${m.isAllVsAll ? 'allVsAll' : 'onePot'}',
      BetModuleType.skins   => '\$${m.skins.valuePerSkin.toStringAsFixed(0)}/skin carry=${m.skins.carryOver}',
      BetModuleType.oyeses  => '\$${m.oyeses.value.toStringAsFixed(0)}/oyés zapato=${m.oyeses.zapatoEnabled}',
      BetModuleType.putts   => '\$${m.putts.value.toStringAsFixed(0)}/putt ${m.putts.puttsMode.name}',
      BetModuleType.units   => 'birdie=\$${m.units.valueFor(UnitEventType.birdie).toStringAsFixed(0)}',
      BetModuleType.matchAutoPress => '\$${m.matchAutoPress.matchValue.toStringAsFixed(0)} trigger=${m.matchAutoPress.pressTriggerValue}',
      BetModuleType.nassauLowHigh => 'seg=\$${m.lowHigh.segmentAmount.toStringAsFixed(0)} '
          'pto=\$${m.lowHigh.amountPerPoint.toStringAsFixed(0)} '
          'tie=${m.lowHigh.tieRule.name} ${m.lowHigh.mode.name}',
    };
  }
}
