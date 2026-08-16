// ─────────────────────────────────────────────────────────────────────────────
// SLIDING ADJUSTMENT ENGINE
// Determina las sugerencias de ajuste de sliding al finalizar una ronda.
//
// Estrategia: usa las LedgerEntries ya calculadas por BetEngine para deducir
// quién ganó en cada apuesta, evitando duplicar la lógica de cálculo.
//
// Prioridad de apuesta principal:
//   1. Match + Press (solo el match principal, primer nodo del árbol)
//      → Usa los entries de BetModuleType.matchAutoPress para el par.
//      → Ganador = quién acumula más amount recibido en el match.
//   2. Nassau (si no hay Match)
//      → Ganador = quién gana más segmentos (front/back/total) por cantidad.
//   3. Skins (si no hay Match ni Nassau)
//      → Ganador = quién acumula más skins en los entries.
//
// Si se juegan Nassau Y Match para el mismo par, gana quien tenga el margen
// mayor (medido en segmentos/hoyos). En empate perfecto no hay ajuste.
//
// El ajuste es bilateral ±1:
//   ganador → delta = -1 (recibe menos strokes en la próxima ronda)
//   perdedor → delta = +1 (recibe más strokes)
// ─────────────────────────────────────────────────────────────────────────────

import '../models/models.dart';
import '../engines/bet_engine.dart';

/// Resultado de un duelo para una pareja de jugadores.
class DuelResult {
  final String playerAId;
  final String playerBId;
  /// SIGNO del resultado: > 0 gana A, < 0 gana B, 0 empate.
  ///
  /// Su MAGNITUD no es comparable entre tipos de apuesta: en Nassau son
  /// segmentos ganados (máx. 3) y en Match era un conteo de asientos del
  /// ledger. Por eso no existe un `absMargin`: compararlos era comparar
  /// segmentos contra filas, y cualquier orden que saliera de ahí era
  /// casualidad. Para decidir entre apuestas está [netAmount].
  final int margin;

  /// Dinero en juego de este duelo, en valor absoluto.
  ///
  /// Es la ÚNICA unidad común entre tipos: un peso es un peso en Nassau, en
  /// Match y en Skins. El ledger ya lo tiene, así que no hay que estimarlo.
  final double netAmount;

  /// De qué apuesta salió, para poder decirlo en pantalla.
  final BetModuleType betType;

  final String sourceBet;

  const DuelResult({
    required this.playerAId,
    required this.playerBId,
    required this.margin,
    required this.netAmount,
    required this.betType,
    required this.sourceBet,
  });

  bool get isTie     => margin == 0;
  bool get isWinForA => margin > 0;
  bool get isWinForB => margin < 0;

  String get winnerId  => margin > 0 ? playerAId : playerBId;
  String get loserId   => margin > 0 ? playerBId : playerAId;
}

/// Sugerencia de ajuste de sliding para un par de jugadores.
class SlidingAdjustmentSuggestion {
  final String playerId;
  final String opponentId;
  final String opponentName;
  final int    opponentColorIndex;
  /// Handicap base del oponente (para mostrar info en UI).
  final double opponentHandicap;
  final double currentAdjustment;
  final int    delta;               // +1 o -1 o 0 (empate)
  final DuelResult duelResult;
  /// true si el oponente tiene linkedUserId → ajuste bilateral posible.
  final bool opponentIsLinked;
  /// true si el jugador existe en el directorio del usuario (tiene PlayerLink).
  final bool opponentInDirectory;
  bool accepted;
  /// Valor ajustado manualmente por el usuario (override del suggestedAdjustment).
  double? manualOverride;

  /// Sliding que el oponente tiene hacia mí (desde la perspectiva del oponente),
  /// leído del manualHandicap de la ronda (o del PlayerLink del oponente como fallback).
  /// Se usa para el ajuste BILATERAL, garantizando que el baseline sea el de la ronda
  /// independientemente de lo que cada usuario tenga guardado en su PlayerLink.
  final double? opponentCurrentAdjustment;

  SlidingAdjustmentSuggestion({
    required this.playerId,
    required this.opponentId,
    required this.opponentName,
    required this.currentAdjustment,
    required this.delta,
    required this.duelResult,
    this.opponentIsLinked    = false,
    this.opponentInDirectory = false,
    this.opponentColorIndex  = 0,
    this.opponentHandicap    = 0,
    this.accepted            = true,
    this.opponentCurrentAdjustment,
    this.manualOverride,
  });

  /// Valor efectivo de sliding: override manual si fue tocado, sino la sugerencia automática.
  double get effectiveAdjustment => manualOverride ?? suggestedAdjustment;

  double get suggestedAdjustment => currentAdjustment + delta;

  /// Nuevo valor que se debe guardar en el link del oponente hacia mí.
  /// Usa el baseline de la ronda (opponentCurrentAdjustment) si está disponible.
  double get opponentSuggestedAdjustment {
    // Si hubo override manual, ajustar bilateralmente desde el override.
    // El valor del oponente siempre es el simétrico del mío:
    // si yo recibo X strokes del oponente → oponente da X → oponente[yo] = -X
    final myFinalAdj = manualOverride ?? suggestedAdjustment;
    return -myFinalAdj;
  }
}

class SlidingAdjustmentEngine {

  /// Calcula las sugerencias de ajuste de sliding.
  ///
  /// [round]       : ronda finalizada.
  /// [currentUid]  : UID del usuario actual (puede ser null si no está autenticado).
  /// [playerLinks] : mapa playerId → PlayerLink del usuario actual.
  static List<SlidingAdjustmentSuggestion> computeSuggestions({
    required Round round,
    String? currentUid,
    required Map<String, PlayerLink> playerLinks,
  }) {
    final myPlayer = _findMyPlayer(round, currentUid);
    if (myPlayer == null) return [];

    // Computar todos los entries de la ronda una sola vez
    final allEntries = BetEngine.computeAll(round);

    // RoundPlayer de mi jugador para leer manualHandicaps reales de la ronda
    final myRoundPlayer = round.roundPlayers
        .where((rp) => rp.playerId == myPlayer.id)
        .firstOrNull;

    final suggestions = <SlidingAdjustmentSuggestion>[];

    for (final player in round.players) {
      if (player.id == myPlayer.id) continue;
      // Se calcula sliding para TODOS los jugadores, tengan cuenta o no.
      // Si no tiene cuenta, el ajuste se guarda solo del lado del usuario actual
      // en su PlayerLink hacia ese jugador (por linkedPlayerId).

      final duel = _computeDuel(
        p1Id:       myPlayer.id,
        p2Id:       player.id,
        round:      round,
        allEntries: allEntries,
      );
      if (duel == null) continue;

      // ── Baseline de sliding: el manualHandicap REAL que se usó en la ronda ──
      //
      // FUENTE DE VERDAD: pairSliding canónico de la ronda (nuevo formato).
      // Si no existe, fallback a manualHandicaps legacy (rondas antiguas).
      // Nunca usar playerLinks como baseline (depende de quién abre la ronda).
      //
      // Prioridad:
      //   1. round.pairSliding canónico → BetEngine.canonicalSlidingBetween
      //   2. manualHandicaps legacy     → myRoundPlayer.manualHandicaps[opponent]
      //   3. playerLinks fallback       → solo si ninguno de los dos existe
      final link         = playerLinks[player.id];
      final canonicalAdj = BetEngine.canonicalSlidingBetween(round, myPlayer.id, player.id);
      final legacyAdj    = myRoundPlayer?.manualHandicaps[player.id];
      final currentAdj   = canonicalAdj ?? legacyAdj ?? link?.defaultSlidingAdjustment ?? 0.0;

      final int delta;
      if (duel.isTie) {
        delta = 0;
      } else if (duel.winnerId == myPlayer.id) {
        delta = -1;
      } else {
        delta = 1;
      }

      // Sliding del oponente hacia mí (perspectiva inversa de la ronda).
      // manualHandicaps[myPlayer][opponent] = +X → yo recibo X de oponente
      // → oponente da X a mí → oponente.manualHandicap[mí] = -X
      // Si no está en la ronda, intentamos inferirlo del manualHandicap inverso.
      final opponentRoundPlayer = round.roundPlayers
          .where((rp) => rp.playerId == player.id)
          .firstOrNull;
      // La perspectiva del oponente es el simétrico del mío (convención bilateral).
      // Prioridad: pairSliding canónico (invertido) → legacy manualHandicaps → inferido.
      final opponentCanonicalAdj = canonicalAdj != null ? -canonicalAdj : null;
      final opponentLegacyAdj    = opponentRoundPlayer?.manualHandicaps[myPlayer.id];
      final opponentCurrentAdj   = opponentCanonicalAdj ?? opponentLegacyAdj
          ?? (legacyAdj != null ? -legacyAdj : null);

      suggestions.add(SlidingAdjustmentSuggestion(
        playerId:                   myPlayer.id,
        opponentId:                 player.id,
        opponentName:               player.name,
        opponentColorIndex:         player.colorIndex,
        opponentHandicap:           player.handicapBase,
        currentAdjustment:          currentAdj,
        delta:                      delta,
        duelResult:                 duel,
        opponentIsLinked:           player.hasLinkedAccount,
        opponentInDirectory:        link != null,
        accepted:                   true,
        opponentCurrentAdjustment:  opponentCurrentAdj,
      ));
    }

    return suggestions;
  }

  // ── Encontrar el jugador del usuario actual ─────────────────────────────────
  // Prioridad:
  //   1. linkedUserId == uid autenticado
  //   2. linkedUserId == round.ownerUid
  //   3. Primer jugador de la ronda (fallback: el creador es típicamente el primero)
  static Player? _findMyPlayer(Round round, String? uid) {
    if (uid != null && uid.isNotEmpty) {
      for (final p in round.players) {
        if (p.linkedUserId == uid) return p;
      }
      // ownerUid como fallback
      if (round.ownerUid != null) {
        for (final p in round.players) {
          if (p.linkedUserId == round.ownerUid) return p;
        }
      }
    }
    // Fallback: primer jugador de la ronda
    return round.players.isNotEmpty ? round.players.first : null;
  }

  // ── Calcular el duelo entre p1 y p2 usando prioridad de apuesta ────────────
  static DuelResult? _computeDuel({
    required String p1Id,
    required String p2Id,
    required Round  round,
    required List<LedgerEntry> allEntries,
  }) {
    // Filtrar entries que involucran solo a este par
    final pairEntries = allEntries.where((e) =>
      (e.fromPlayerId == p1Id && e.toPlayerId == p2Id) ||
      (e.fromPlayerId == p2Id && e.toPlayerId == p1Id)
    ).toList();

    if (pairEntries.isEmpty) return null;

    // Agrupar por tipo
    final matchEntries  = pairEntries.where((e) => e.betType == BetModuleType.matchAutoPress).toList();
    final nassauEntries = pairEntries.where((e) => e.betType == BetModuleType.nassau).toList();
    final skinsEntries  = pairEntries.where((e) => e.betType == BetModuleType.skins).toList();

    DuelResult? matchResult;
    DuelResult? nassauResult;
    DuelResult? skinsResult;

    if (matchEntries.isNotEmpty) {
      matchResult = _duelFromMatchEntries(p1Id, p2Id, matchEntries);
    }
    if (nassauEntries.isNotEmpty) {
      nassauResult = _duelFromNassauEntries(p1Id, p2Id, nassauEntries);
    }
    if (skinsEntries.isNotEmpty) {
      skinsResult = _duelFromSkinsEntries(p1Id, p2Id, skinsEntries);
    }

    // ── Qué apuesta representa el duelo ───────────────────────────────────
    //
    // Manda el DINERO en juego, que es la única unidad común entre tipos. El
    // criterio anterior comparaba matchResult.absMargin contra
    // nassauResult.absMargin, y esos números no medían lo mismo: uno contaba
    // asientos del ledger y el otro segmentos ganados, máximo 3. Cualquier
    // orden que saliera de esa comparación era casualidad.
    //
    // Skins entra aquí también. Antes quedaba fuera del if y solo aparecía si
    // no había ninguno de los otros dos, así que unos Skins de $500 perdían
    // contra un Nassau de $60 por estar después en la cadena de ??.
    final candidatos = [matchResult, nassauResult, skinsResult]
        .whereType<DuelResult>()
        .toList();
    if (candidatos.isEmpty) return null;

    candidatos.sort((a, b) {
      final porDinero = b.netAmount.compareTo(a.netAmount);
      if (porDinero != 0) return porDinero;
      // Empate de importe: se decide por un orden FIJO y declarado, no por el
      // orden en que estén escritas las ramas. Antes el >= hacía que ganara
      // la rama de la izquierda, que es un efecto de la escritura y no una
      // regla que nadie eligiera.
      return _ordenDesempate(a.betType).compareTo(_ordenDesempate(b.betType));
    });
    return candidatos.first;
  }

  /// Precedencia cuando dos apuestas ponen el mismo dinero en juego.
  ///
  /// Los formatos de match play van antes que los de hoyo suelto: el ajuste de
  /// ventaja trata de equilibrar el enfrentamiento directo, y ahí un match
  /// describe mejor la relación entre dos jugadores que un recuento de skins.
  static int _ordenDesempate(BetModuleType t) => switch (t) {
        BetModuleType.matchAutoPress => 0,
        BetModuleType.nassau => 1,
        BetModuleType.skins => 2,
        _ => 3,
      };

  // ── Match: balancear amount recibido vs pagado ──────────────────────────────
  // El label del match principal contiene 'Match H' o 'Match' sin número de press.
  // Las presiones contienen 'Press'.
  static DuelResult _duelFromMatchEntries(
      String p1Id, String p2Id, List<LedgerEntry> entries) {
    // Separar match principal (reason empieza con 'Match' y no contiene 'Press')
    // vs presiones. Usamos solo el match principal para determinar el ganador.
    final primaryEntries = entries.where((e) {
      final r = e.reason.toLowerCase();
      return r.contains('match') && !r.contains('press');
    }).toList();

    // Si no hay entries de match principal (ronda sin hoyos suficientes para match),
    // usar todos los entries de matchAutoPress
    final relevant = primaryEntries.isNotEmpty ? primaryEntries : entries;

    double p1net = 0; // cuánto recibió p1 (- cuánto pagó)
    for (final e in relevant) {
      if (e.toPlayerId   == p1Id) p1net += e.amount;
      if (e.fromPlayerId == p1Id) p1net -= e.amount;
    }

    // Solo el SIGNO. Antes se contaban asientos del ledger y se llamaban
    // "matches ganados": un match con dos presses daba margen 3, que además se
    // comparaba contra los segmentos de Nassau. Filas contra segmentos.
    //
    // Quién ganó sale del neto, que sí es un hecho. Cuánto ganó, en unidades
    // de match, no se puede saber desde el ledger, así que no se inventa.
    final margin = p1net > 0.001 ? 1 : p1net < -0.001 ? -1 : 0;

    // Dinero total movido por esta apuesta en este duelo — incluidas las
    // presses, porque también es dinero en juego entre estos dos.
    var bruto = 0.0;
    for (final e in entries) {
      bruto += e.amount;
    }

    final label = margin > 0
        ? 'Match (gana ${entries.length > 1 ? "con presiones" : "el match"})'
        : margin < 0
            ? 'Match (pierde ${entries.length > 1 ? "con presiones" : "el match"})'
            : 'Match (AS)';

    return DuelResult(
      playerAId: p1Id,
      playerBId: p2Id,
      margin:    margin,
      netAmount: p1net.abs(),
      betType:   BetModuleType.matchAutoPress,
      sourceBet: label,
    );
  }

  // ── Nassau: contar segmentos ganados ─────────────────────────────────────────
  // Cada entry de Nassau corresponde a un segmento (Front 9, Back 9, Total 18).
  // Margen = segmentos ganados por p1 - segmentos ganados por p2.
  static DuelResult _duelFromNassauEntries(
      String p1Id, String p2Id, List<LedgerEntry> entries) {
    int segsGanadosP1 = 0;
    int segsGanadosP2 = 0;

    for (final e in entries) {
      if (e.toPlayerId == p1Id) segsGanadosP1++;
      if (e.toPlayerId == p2Id) segsGanadosP2++;
    }

    final margin = segsGanadosP1 - segsGanadosP2;
    final label = margin > 0
        ? 'Nassau ($segsGanadosP1-$segsGanadosP2 segmentos)'
        : margin < 0
            ? 'Nassau ($segsGanadosP1-$segsGanadosP2 segmentos)'
            : 'Nassau (empate $segsGanadosP1-$segsGanadosP2)';


    // Neto de esta apuesta en este duelo: la unidad que sí compara con las
    // demás. El margen de arriba solo vale dentro de este tipo.
    var neto = 0.0;
    for (final e in entries) {
      if (e.toPlayerId   == p1Id) neto += e.amount;
      if (e.fromPlayerId == p1Id) neto -= e.amount;
    }
    return DuelResult(
      playerAId: p1Id,
      playerBId: p2Id,
      margin:    margin,
      netAmount: neto.abs(),
      betType:   BetModuleType.nassau,
      sourceBet: label,
    );
  }

  // ── Skins: contar skins ganadas ───────────────────────────────────────────
  static DuelResult _duelFromSkinsEntries(
      String p1Id, String p2Id, List<LedgerEntry> entries) {
    int skinsP1 = 0;
    int skinsP2 = 0;

    for (final e in entries) {
      if (e.toPlayerId == p1Id) skinsP1++;
      if (e.toPlayerId == p2Id) skinsP2++;
    }

    final margin = skinsP1 - skinsP2;
    final label = 'Skins ($skinsP1 vs $skinsP2)';


    // Neto de esta apuesta en este duelo: la unidad que sí compara con las
    // demás. El margen de arriba solo vale dentro de este tipo.
    var neto = 0.0;
    for (final e in entries) {
      if (e.toPlayerId   == p1Id) neto += e.amount;
      if (e.fromPlayerId == p1Id) neto -= e.amount;
    }
    return DuelResult(
      playerAId: p1Id,
      playerBId: p2Id,
      margin:    margin,
      netAmount: neto.abs(),
      betType:   BetModuleType.skins,
      sourceBet: label,
    );
  }
}
