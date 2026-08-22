// ─────────────────────────────────────────────────────────────────────────────
// ROUND PROVIDER — State management central
// Recalcula el ledger automáticamente ante cualquier cambio.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_theme.dart';
import '../engines/ledger_engine.dart';
import '../models/models.dart';
import '../services/firestore_service.dart';
import '../services/live_round_service.dart';
import '../services/auth_service.dart';

// ── Funciones top-level para serialización (usadas también por FirestoreService)
Map<String, dynamic> roundToJson(Round r) {
  // Construir participantUids: ownerUid + linkedUserId de todos los jugadores
  // Este campo es necesario para las reglas de Firestore en liveRounds.
  final participantUids = <String>{
    if (r.ownerUid != null) r.ownerUid!,
    ...r.players
        .where((p) => p.linkedUserId != null && p.linkedUserId!.isNotEmpty)
        .map((p) => p.linkedUserId!),
  }.toList();

  return {
  'id': r.id, 'name': r.name, 'createdAt': r.createdAt.toIso8601String(),
  'currentHole': r.currentHole, 'isFinished': r.isFinished,
  'startingNine': r.startingNine.name,
  'totalHoles': r.totalHoles,
  'isLive': r.isLive,
  if (r.ownerUid != null) 'ownerUid': r.ownerUid,
  if (r.liveCode != null) 'liveCode': r.liveCode,
  'scoringMode': r.scoringMode,
  if (participantUids.isNotEmpty) 'participantUids': participantUids,
  'course': r.course.toJson(),
  'players': r.players.map((p) => p.toJson()).toList(),
  'roundPlayers': r.roundPlayers.map((rp) => rp.toJson()).toList(),
  'betGroups': r.betGroups.map((g) => g.toJson()).toList(),
  'scores': r.scores.map((pid, hmap) => MapEntry(pid, hmap.map((h, s) => MapEntry(h.toString(), s.toJson())))),
  'events': r.events.map((pid, hmap) => MapEntry(pid, hmap.map((h, list) => MapEntry(h.toString(), list.map((e) => e.toJson()).toList())))),
  'oyeseRankings': r.oyeseRankings.map((h, or_) => MapEntry(h.toString(), or_.toJson())),
  'sliding': r.sliding.map((s) => s.toJson()).toList(),
  // pairSliding: fuente canónica de acuerdos bilaterales (solo si hay valores)
  if (r.pairSliding.isNotEmpty) 'pairSliding': r.pairSliding,
  // Solo se escribe cuando está APAGADO: el default es true, así que las
  // rondas guardadas antes de que existiera el campo se comportan igual.
  if (!r.slidingRecalcula) 'slidingRecalcula': false,
  // pendingProposals: propuestas colaborativas de cambio de apuestas
  if (r.pendingProposals.isNotEmpty)
    'pendingProposals': r.pendingProposals.map((p) => p.toJson()).toList(),
  };
}

Round roundFromJson(Map<String, dynamic> j) {
  // ── Helpers defensivos para evitar ClassCastException con datos de Firestore ──
  List asList(dynamic v) => v is List ? v : [];
  Map<String, dynamic> asMap(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  final players = asList(j['players'])
      .map((p) => Player.fromJson(asMap(p))).toList();
  final roundPlayers = asList(j['roundPlayers'])
      .map((rp) => RoundPlayer.fromJson(asMap(rp))).toList();
  final betGroups = asList(j['betGroups'])
      .map((g) => BetGroup.fromJson(asMap(g))).toList();

  final scoresJson = asMap(j['scores']);
  final scores = <String, Map<int, HoleScore>>{};
  scoresJson.forEach((pid, hmap) {
    final inner = <int, HoleScore>{};
    asMap(hmap).forEach((hStr, sJson) {
      final h = int.tryParse(hStr);
      if (h != null && sJson != null) {
        try { inner[h] = HoleScore.fromJson(asMap(sJson)); } catch (_) {}
      }
    });
    scores[pid] = inner;
  });

  final eventsJson = asMap(j['events']);
  final events = <String, Map<int, List<HoleEvent>>>{};
  eventsJson.forEach((pid, hmap) {
    final inner = <int, List<HoleEvent>>{};
    asMap(hmap).forEach((hStr, list) {
      final h = int.tryParse(hStr);
      if (h != null) {
        try {
          inner[h] = asList(list)
              .map((e) => HoleEvent.fromJson(asMap(e)))
              .toList();
        } catch (_) { inner[h] = []; }
      }
    });
    events[pid] = inner;
  });

  final oyesesJson = asMap(j['oyeseRankings']);
  final oyeses = <int, OyeseRanking>{};
  oyesesJson.forEach((hStr, or_) {
    final h = int.tryParse(hStr);
    if (h != null && or_ != null) {
      try { oyeses[h] = OyeseRanking.fromJson(asMap(or_)); } catch (_) {}
    }
  });

  final sliding = asList(j["sliding"])
      .map((s) {
        try { return SlidingRelation.fromJson(asMap(s)); }
        catch (_) { return null; }
      })
      .whereType<SlidingRelation>()
      .toList();

  // Parsear createdAt de forma defensiva: puede ser String ISO o Timestamp de Firestore
  final rawCreatedAt = j['createdAt'];
  final DateTime parsedCreatedAt;
  if (rawCreatedAt is Timestamp) {
    parsedCreatedAt = rawCreatedAt.toDate();
  } else if (rawCreatedAt is String) {
    parsedCreatedAt = DateTime.tryParse(rawCreatedAt) ?? DateTime.now();
  } else {
    parsedCreatedAt = DateTime.now();
  }

  return Round(
    // Casts defensivos: Firestore Web devuelve Map<Object?,Object?> y tipos numéricos
    // variables, por eso usamos helpers en lugar de casts directos con 'as'.
    id:          (j['id']   as Object?)?.toString() ?? '',
    name:        (j['name'] as Object?)?.toString() ?? 'Ronda',
    createdAt:   parsedCreatedAt,
    currentHole: (j['currentHole'] as num?)?.toInt()  ?? 1,
    isFinished:  j['isFinished']  == true,
    startingNine: j['startingNine'] == 'back' ? StartingNine.back : StartingNine.front,
    totalHoles:  (j['totalHoles']  as num?)?.toInt()  ?? 18,
    isLive:      j['isLive']      == true,
    ownerUid:    (j['ownerUid']   as Object?)?.toString(),
    liveCode:    (j['liveCode']   as Object?)?.toString(),
    scoringMode: (j['scoringMode'] as Object?)?.toString() ?? 'open',
    players: players, roundPlayers: roundPlayers,
    betGroups: betGroups,
    course: j['course'] != null
        ? CourseInfo.fromJson(asMap(j['course']))   // asMap() normaliza Map<Object?,Object?>
        : CourseInfo.standard,
    scores: scores, events: events, oyeseRankings: oyeses, sliding: sliding,
    // ── pairSliding: leer campo canónico y aplicar migración legacy ──────────
    pairSliding: _buildPairSliding(j, roundPlayers),
    slidingRecalcula: j['slidingRecalcula'] as bool? ?? true,
    // ── pendingProposals: propuestas colaborativas ───────────────────────────
    pendingProposals: asList(j['pendingProposals'])
        .map((p) {
          try { return BetChangeProposal.fromJson(asMap(p)); }
          catch (_) { return null; }
        })
        .whereType<BetChangeProposal>()
        .toList(),
  );
}

/// Construye el mapa pairSliding canónico a partir del JSON deserializado.
///
/// Prioridad:
///   1. Campo 'pairSliding' en el JSON (rondas nuevas)
///   2. Migración automática desde manualHandicaps legacy (rondas viejas)
///
/// Convención de clave: '\$lowId|\$highId' (IDs ordenados lexicográficamente).
/// Valor: cuántos strokes recibe lowId de highId.
///   +5 → lowId recibe 5  |  -5 → lowId da 5 (highId recibe 5)
Map<String, double> _buildPairSliding(
    Map<String, dynamic> j, List<RoundPlayer> roundPlayers) {
  // ── Paso 1: leer campo canónico si existe ─────────────────────────────────
  // Se descartan las claves mal formadas. Una versión anterior escribía la
  // clave literal '$lowId|$highId' (interpolación escapada por error), y ese
  // valor quedó persistido en Firestore/prefs de rondas ya creadas. Si tras
  // sanear no queda ninguna entrada válida, se cae a la migración legacy.
  final rawPs = j['pairSliding'];
  if (rawPs is Map && rawPs.isNotEmpty) {
    final sanitized = <String, double>{};
    for (final e in rawPs.entries) {
      final k = e.key.toString();
      if (!_isValidPairKey(k)) {
        debugPrint('[pairSliding] Clave inválida descartada: "$k"');
        continue;
      }
      sanitized[k] = (e.value as num?)?.toDouble() ?? 0.0;
    }
    if (sanitized.isNotEmpty) return sanitized;
  }

  // ── Paso 2: migración desde manualHandicaps legacy ────────────────────────
  // Recopilar todos los pares únicos presentes en manualHandicaps
  final result = <String, double>{};
  final seen = <String>{}; // claves canónicas ya procesadas

  for (final rp in roundPlayers) {
    final p1 = rp.playerId;
    for (final entry in rp.manualHandicaps.entries) {
      final p2 = entry.key;
      final m1 = entry.value; // cuánto recibe p1 de p2 (según legacy)

      // Clave canónica: ids ordenados lexicográficamente
      final lowId = p1.compareTo(p2) <= 0 ? p1 : p2;
      final key   = _pairKeyOf(p1, p2);

      if (seen.contains(key)) continue; // ya procesado desde el otro sentido
      seen.add(key);

      // Buscar el valor del sentido inverso para validar consistencia
      final rp2 = roundPlayers.firstWhere(
        (r) => r.playerId == p2,
        orElse: () => RoundPlayer(playerId: p2, handicapEnRonda: 0),
      );
      final m2 = rp2.manualHandicaps[p1]; // cuánto recibe p2 de p1 (legacy)

      // Ambos lados existen: deben ser opuestos (m1 == -m2).
      if (m2 != null && (m1 + m2).abs() > 0.01) {
        // Inconsistencia legacy: no se migra este par. El engine la detecta y
        // BetEngine.computeAll la reporta sin lanzar (ver safeComputeAll).
        debugPrint(
          '[pairSliding] Inconsistencia legacy en par ($p1, $p2): '
          'manual[$p1][$p2]=$m1 pero manual[$p2][$p1]=$m2 '
          '(se esperaba $m1 == ${-m2}). Par omitido en la migración.',
        );
        continue;
      }

      // Valor canónico desde la perspectiva del lowId
      result[key] = (p1 == lowId) ? m1 : -m1;
    }
  }

  return result;
}

/// Clave canónica de un par: ids en orden lexicográfico separados por '|'.
String _pairKeyOf(String a, String b) =>
    a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';

/// true si [key] tiene la forma canónica 'idBajo|idAlto' con ids no vacíos,
/// distintos y en orden lexicográfico.
bool _isValidPairKey(String key) {
  final parts = key.split('|');
  if (parts.length != 2) return false;
  if (parts[0].isEmpty || parts[1].isEmpty) return false;
  if (parts[0] == parts[1]) return false;
  return parts[0].compareTo(parts[1]) < 0;
}

// ─────────────────────────────────────────────────────────────────────────────
class RoundProvider extends ChangeNotifier {
  Round? _round;
  AppThemeMode _themeMode = AppThemeMode.light;
  int _tabIndex = 0;

  // ── Cifra héroe: de quién ──────────────────────────────────────────────────
  //
  // Cada pantalla debe responder UNA pregunta con una cifra grande arriba, y en
  // Resultados esa pregunta es "¿cuánto gano o pierdo YO?". Para eso hay que
  // saber quién es "yo".
  //
  // Orden de resolución:
  //   1. el jugador vinculado a la cuenta, si existe
  //   2. si no, se PREGUNTA una vez y se recuerda
  //   3. nunca una pantalla sin héroe
  //
  // Vive en el provider y no en Round a propósito: es estado de SESIÓN, como
  // _tabIndex. Meterlo en el modelo lo escribiría en Firestore y lo compartiría
  // con los demás participantes, cuando es una preferencia de este teléfono.
  //
  // Y es lo que resuelve el caso real de pasarse el móvil entre el grupo para
  // que cada uno vea lo suyo: se toca el héroe y se cambia.
  String? _heroPlayerId;

  /// De quién es la cifra héroe, si ya se sabe.
  String? get heroPlayerId => _heroPlayerId;

  void setHeroPlayer(String pid) {
    _heroPlayerId = pid;
    notifyListeners();
  }

  // Stream de ronda en vivo
  StreamSubscription<Round?>? _liveRoundSub;
  // Flag para ignorar el próximo evento del stream (evitar eco)
  bool _ignoringLiveUpdate = false;
  // Contador de escrituras locales de pairSliding pendientes de confirmación
  // remota. Cada _persist() que incluye cambios de pairSliding lo incrementa;
  // el listener lo decrementa al procesar el eco. Mientras sea > 0, el listener
  // preserva el pairSliding local en vez de sobreescribirlo con el remoto.
  int _pendingPairSlidingWrites = 0;
  // Flag: el admin finalizó la ronda pero este usuario aún no presionó "Cerrar"
  bool _roundFinishedByAdmin = false;

  Round? get round => _round;
  AppThemeMode get themeMode => _themeMode;
  int get tabIndex => _tabIndex;
  bool get hasRound => _round != null;
  bool get isLiveRound => _round?.isLive ?? false;
  bool get isLiveOwner => _round?.isLive == true && _round?.ownerUid == AuthService.uid;
  /// true cuando el admin de la ronda live la finalizó pero el usuario local aún no cerró
  bool get roundFinishedByAdmin => _roundFinishedByAdmin;

  GolfTheme get theme {
    switch (_themeMode) {
      case AppThemeMode.light:   return GolfTheme.light;
      case AppThemeMode.dark:    return GolfTheme.dark;
      case AppThemeMode.classic: return GolfTheme.classic;
    }
  }

  // ── Theme ──────────────────────────────────────────────────────────────────
  void setTheme(AppThemeMode m) {
    _themeMode = m;
    GolfThemeExt.setCurrent(theme);
    _prefs().then((p) => p.setString('theme', m.name));
    notifyListeners();
  }

  void setTab(int i) { _tabIndex = i; notifyListeners(); }

  // ── Round lifecycle ────────────────────────────────────────────────────────
  void startRound(Round r) {
    _round = r;
    // Otra ronda, otros jugadores: arrastrar la elección mostraría el neto de
    // alguien que no juega hoy.
    _heroPlayerId = null;
    _tabIndex = 1;
    notifyListeners();
    _persist();
    // Si es ronda en vivo, iniciar listener
    if (r.isLive) _startLiveListener(r.id);
  }

  /// Activa una ronda en vivo (invitado que acepta) sin escribir en Firestore
  void joinLiveRound(Round r) {
    _cancelLiveListener();
    _round = r;
    _tabIndex = 0; // Ir a Inicio para mostrar la ronda activa
    notifyListeners();
    _startLiveListener(r.id);
    // Guardar ref local
    _prefs().then((p) => p.setString('round', jsonEncode(roundToJson(r))));
  }

  /// Convierte la ronda actual en vivo y la publica
  Future<Round> publishAsLive() async {
    if (_round == null) throw Exception('Sin ronda activa');
    final liveRound = await LiveRoundService.publishRound(_round!);
    _round = liveRound;
    notifyListeners();
    _persist();
    // También marcar la ronda personal como isLive=true para que loadPrefs
    // active el listener correctamente al reabrir la app
    FirestoreService.saveRound(liveRound).catchError((e) {
      if (kDebugMode) debugPrint('[publishAsLive] Error actualizando ronda personal: $e');
    });
    _startLiveListener(liveRound.id);
    return liveRound;
  }

  // ── Listener en tiempo real para rondas en vivo ────────────────────────────
  void _startLiveListener(String roundId) {
    _cancelLiveListener();
    _liveRoundSub = LiveRoundService.liveRoundStream(roundId).listen((remote) {
      if (remote == null) return;
      if (_ignoringLiveUpdate) {
        _ignoringLiveUpdate = false;
        return;
      }
      if (_round == null) return;

      // ── Detección: el ADMIN finalizó la ronda remotamente ──────────────────
      // Si la ronda remota tiene isFinished=true y el usuario local NO es el owner,
      // mantenemos la ronda visible pero activamos el banner de aviso.
      if (remote.isFinished && !isLiveOwner) {
        // La ronda está cerrando — los datos finales del admin son canónicos.
        // Resetear el contador: ya no tiene sentido proteger el pairSliding local.
        _pendingPairSlidingWrites = 0;
        _round = remote;          // Actualizar datos (scores, resultados finales)
        _roundFinishedByAdmin = true;
        notifyListeners();
        // Navegar automáticamente a Resultados para que el usuario vea el banner
        if (_tabIndex != 2) _tabIndex = 2;
        notifyListeners();
        if (kDebugMode) debugPrint('[LiveRound] Ronda finalizada por el admin — mostrando aviso al invitado');
        return;
      }

      // Caso normal: actualización de datos en tiempo real.
      // Si hay escrituras locales de pairSliding pendientes de confirmación
      // (otro jugador guardó concurrentemente y llegó un segundo evento antes
      // de que nuestro eco fuera procesado), preservamos el pairSliding local
      // en lugar de sobreescribirlo con la versión remota que aún no incluye
      // nuestra ventaja recién configurada.
      final Round merged;
      if (_pendingPairSlidingWrites > 0) {
        _pendingPairSlidingWrites--;
        // Fusión: entradas locales ganan sobre el remoto para pairSliding.
        // El resto de datos (scores, etc.) viene del remoto como siempre.
        merged = remote.copyWith(
          pairSliding: {
            ...remote.pairSliding,
            ..._round!.pairSliding, // local sobreescribe — son más recientes
          },
        );
        if (kDebugMode) {
          debugPrint(
            '[LiveRound] Merge pairSliding: remote=${remote.pairSliding} '
            'local=${_round!.pairSliding} → merged=${merged.pairSliding}',
          );
        }
      } else {
        merged = remote;
      }
      _round = merged;
      notifyListeners();
      // Actualizar caché local también
      _prefs().then((p) => p.setString('round', jsonEncode(roundToJson(merged))));
    });
    if (kDebugMode) debugPrint('[LiveRound] Listener iniciado: $roundId');
  }

  void _cancelLiveListener() {
    _liveRoundSub?.cancel();
    _liveRoundSub = null;
  }

  /// El invitado reconoce que el admin ya finalizó y decide cerrar la ronda en su dispositivo.
  /// Ejecuta finishRound() para él (guarda en historial personal y limpia la UI).
  Future<void> acknowledgeAdminFinish() async {
    _roundFinishedByAdmin = false;
    await finishRound();
  }

  @override
  void dispose() {
    _cancelLiveListener();
    super.dispose();
  }

  // ── Clave para rondas finalizadas pendientes de sync ───────────────────────
  static const _kPendingFinished = 'pending_finished_rounds';

  /// Finaliza la ronda de forma segura:
  /// 1. Intenta guardar en Firestore (await).
  /// 2. Si falla (sin conexión / bloqueador de anuncios / sin sesión),
  ///    encola la ronda en SharedPreferences para sincronizarla después.
  /// 3. SIEMPRE limpia la ronda activa de la UI — nunca bloquea al usuario.
  /// Retorna true si se guardó en Firestore, false si quedó pendiente local.
  Future<bool> finishRound() async {
    if (_round == null) return false;
    _cancelLiveListener();

    final finishedRound = _round!.copyWith(isFinished: true);
    bool savedToFirestore = false;

    // 1. Intentar guardar en Firestore
    if (AuthService.uid != null) {
      try {
        // Si era ronda en vivo, finalizar en liveRounds también
        if (finishedRound.isLive) {
          await LiveRoundService.finishLiveRound(finishedRound.id);
        }
        await FirestoreService.saveRound(finishedRound);
        savedToFirestore = true;
      } catch (e) {
        debugPrint('[finishRound] Firestore error (encolando local): $e');
        await _enqueuePendingFinished(finishedRound);
      }
    } else {
      debugPrint('[finishRound] Sin sesión: encolando local');
      await _enqueuePendingFinished(finishedRound);
    }

    // 2. Limpiar caché de ronda activa
    try {
      final p = await _prefs();
      await p.remove('round');
    } catch (_) {}

    // 3. Limpiar estado de UI — siempre, independiente del resultado de Firestore
    _round = null;
    _tabIndex = 0;
    notifyListeners();

    return savedToFirestore;
  }

  /// Encola una ronda finalizada en SharedPreferences para sync posterior.
  Future<void> _enqueuePendingFinished(Round r) async {
    try {
      final p = await _prefs();
      final existing = p.getStringList(_kPendingFinished) ?? [];
      // Evitar duplicados por el mismo ID
      existing.removeWhere((s) {
        try { return (jsonDecode(s) as Map)['id'] == r.id; } catch (_) { return false; }
      });
      existing.add(jsonEncode(roundToJson(r)));
      await p.setStringList(_kPendingFinished, existing);
      debugPrint('[pendingSync] Ronda encolada: ${r.id} (total: ${existing.length})');
    } catch (e) {
      debugPrint('[pendingSync] Error al encolar: $e');
    }
  }

  /// Sincroniza rondas finalizadas pendientes con Firestore.
  /// Llamar después de login exitoso y al iniciar la app con sesión.
  /// Retorna el número de rondas sincronizadas exitosamente.
  Future<int> syncPendingFinished() async {
    if (AuthService.uid == null) return 0;
    try {
      final p = await _prefs();
      final pending = p.getStringList(_kPendingFinished) ?? [];
      if (pending.isEmpty) return 0;

      debugPrint('[pendingSync] Sincronizando ${pending.length} ronda(s) pendiente(s)...');
      int synced = 0;
      final remaining = <String>[];

      for (final jsonStr in pending) {
        try {
          final round = roundFromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
          await FirestoreService.saveRound(round);
          synced++;
          debugPrint('[pendingSync] OK: ${round.id}');
        } catch (e) {
          debugPrint('[pendingSync] FAIL: $e');
          remaining.add(jsonStr); // Reintentar la próxima vez
        }
      }

      if (remaining.isEmpty) {
        await p.remove(_kPendingFinished);
      } else {
        await p.setStringList(_kPendingFinished, remaining);
      }
      debugPrint('[pendingSync] Sincronizadas: $synced/${pending.length}');
      return synced;
    } catch (e) {
      debugPrint('[pendingSync] Error general: $e');
      return 0;
    }
  }

  /// Cuenta las rondas finalizadas pendientes de sincronización.
  Future<int> pendingFinishedCount() async {
    try {
      final p = await _prefs();
      return (p.getStringList(_kPendingFinished) ?? []).length;
    } catch (_) { return 0; }
  }

  void resetRound() {
    _cancelLiveListener();
    _round = null;
    _tabIndex = 0;
    notifyListeners();
    _prefs().then((p) => p.remove('round'));
  }

  // ── Score capture ──────────────────────────────────────────────────────────
  void updateScore(String playerId, int hole, int? gross, int putts) {
    if (_round == null) return;
    final newScores = _cloneScores();
    newScores[playerId] ??= {};
    newScores[playerId]![hole] = HoleScore(playerId: playerId, hole: hole, grossScore: gross, putts: putts);
    _round = _round!.copyWith(scores: newScores);
    notifyListeners();
    _persist();
  }

  // ── Unit events ────────────────────────────────────────────────────────────
  void toggleEvent(String playerId, int hole, UnitEventType type) {
    if (_round == null) return;
    final newEvents = _cloneEvents();
    newEvents[playerId] ??= {};
    newEvents[playerId]![hole] ??= [];
    final list = newEvents[playerId]![hole]!;
    final existing = list.indexWhere((e) => e.type == type);
    if (existing >= 0) { list.removeAt(existing); }
    else { list.add(HoleEvent(playerId: playerId, hole: hole, type: type)); }
    _round = _round!.copyWith(events: newEvents);
    notifyListeners();
    _persist();
  }

  bool hasEvent(String playerId, int hole, UnitEventType type) =>
      _round?.getEvents(playerId, hole).any((e) => e.type == type) ?? false;

  // ── Oyese ranking ──────────────────────────────────────────────────────────
  void setOyeseRanking(int hole, List<String> ranking) {
    if (_round == null) return;
    final newRankings = Map<int, OyeseRanking>.from(_round!.oyeseRankings);
    newRankings[hole] = OyeseRanking(hole: hole, ranking: ranking);
    _round = _round!.copyWith(oyeseRankings: newRankings);
    notifyListeners();
    _persist();
  }

  // ── Bet groups ─────────────────────────────────────────────────────────────
  void updateBetGroups(List<BetGroup> groups) {
    if (_round == null) return;
    _round = _round!.copyWith(betGroups: groups);
    notifyListeners();
    _persist();
  }

  /// Reemplaza un módulo individual dentro del betGroup correspondiente.
  /// Busca el grupo por [groupId] y el módulo por [mod.id]. Si el módulo no
  /// existe lo añade al final del grupo.
  void updateBetModule(String groupId, BetModuleInstance mod) {
    if (_round == null) return;
    final newGroups = _round!.betGroups.map((g) {
      if (g.id != groupId) return g;
      final idx = g.modules.indexWhere((m) => m.id == mod.id);
      List<BetModuleInstance> updated;
      if (idx >= 0) {
        updated = List<BetModuleInstance>.from(g.modules);
        updated[idx] = mod;
      } else {
        updated = [...g.modules, mod];
      }
      return g.copyWith(modules: updated);
    }).toList();
    _round = _round!.copyWith(betGroups: newGroups);
    notifyListeners();
    _persist();
  }

  /// Elimina un módulo individual del betGroup. Si el grupo queda vacío
  /// se elimina también el grupo.
  void removeBetModule(String groupId, String moduleId) {
    if (_round == null) return;
    final newGroups = _round!.betGroups
        .map((g) {
          if (g.id != groupId) return g;
          final remaining = g.modules.where((m) => m.id != moduleId).toList();
          if (remaining.isEmpty) return null;
          return g.copyWith(modules: remaining);
        })
        .whereType<BetGroup>()
        .toList();
    _round = _round!.copyWith(betGroups: newGroups);
    notifyListeners();
    _persist();
  }

  /// Fija la ventaja acordada del par (p1, p2) de forma ATÓMICA y BILATERAL.
  ///
  /// [strokes] positivo = p1 recibe de p2; negativo = p1 da; null = eliminar
  /// el acuerdo y volver a la diferencia de HCP.
  ///
  /// Escribe la fuente canónica ([Round.pairSliding]) y espeja el legacy
  /// [RoundPlayer.manualHandicaps] en AMBOS jugadores en una sola operación.
  ///
  /// IMPORTANTE — no llamar dos veces para "limpiar el otro lado". La clave de
  /// pairSliding es simétrica: una segunda llamada invertida con strokes=null
  /// borraría el valor que acaba de escribir la primera.
  void setPairSliding(String p1Id, String p2Id, double? strokes) {
    if (_round == null || p1Id == p2Id) return;

    // ── Fuente canónica ────────────────────────────────────────────────────
    final key   = _pairKey(p1Id, p2Id);
    final newPs = Map<String, double>.from(_round!.pairSliding);
    if (strokes == null) {
      newPs.remove(key);
    } else {
      final lowId = p1Id.compareTo(p2Id) <= 0 ? p1Id : p2Id;
      newPs[key] = (p1Id == lowId) ? strokes : -strokes;
    }

    // ── Espejo legacy en los DOS RoundPlayers ──────────────────────────────
    // Si solo se escribiera un lado, quedaría un manualHandicaps unilateral
    // desactualizado que el engine podría leer como fuente alternativa.
    final newRPs = _round!.roundPlayers.map((rp) {
      if (rp.playerId != p1Id && rp.playerId != p2Id) return rp;
      final otherId = rp.playerId == p1Id ? p2Id : p1Id;
      final updated = Map<String, double>.from(rp.manualHandicaps);
      if (strokes == null) {
        updated.remove(otherId);
      } else {
        updated[otherId] = rp.playerId == p1Id ? strokes : -strokes;
      }
      return RoundPlayer(
        playerId:        rp.playerId,
        handicapEnRonda: rp.handicapEnRonda,
        tee:             rp.tee,
        manualHandicaps: updated,
      );
    }).toList();

    _round = _round!.copyWith(roundPlayers: newRPs, pairSliding: newPs);
    notifyListeners();
    _persist();
  }

  /// Actualiza la ventaja manual de p1 hacia p2.
  /// [strokes] positivo = p1 recibe de p2; null = eliminar override manual.
  ///
  /// Alias de [setPairSliding], que ya mantiene ambos lados sincronizados.
  void updateManualHandicap(String p1Id, String p2Id, double? strokes) =>
      setPairSliding(p1Id, p2Id, strokes);

  // ── Alta de jugador en las apuestas de una partida ─────────────────────────

  /// Suma [playerId] a la partida [groupId] de la ronda en curso.
  ///
  /// El jugador queda dentro de todas las apuestas de esa partida con alcance
  /// [BetScopeKind.everyone] sin tocar su configuración: esos módulos resuelven
  /// participantes contra `group.playerIds` en cada cálculo.
  ///
  /// Las apuestas de alcance fijo (duelo, subconjunto, equipos) NO se tocan —
  /// meter a alguien en un duelo acordado entre otros dos no sería correcto.
  ///
  /// Devuelve cuántos módulos pasan a incluirlo (0 si no había ninguno con
  /// alcance abierto, lo que indica que hay que añadirlo a mano).
  int addPlayerToGroupBets(String playerId, String groupId) {
    if (_round == null) return 0;

    final groups = _round!.betGroups;
    final gi = groups.indexWhere((g) => g.id == groupId);
    if (gi < 0) return 0;

    final group = groups[gi];
    if (group.playerIds.contains(playerId)) {
      // Ya estaba: informar cuántas apuestas abiertas le aplican.
      return group.modules.where((m) => m.effectiveScope.isEveryone).length;
    }

    final newGroups = List<BetGroup>.from(groups);
    newGroups[gi] = group.copyWith(
      playerIds: [...group.playerIds, playerId],
    );

    // Asegurar que el jugador tenga contenedores de score/eventos, si no la
    // captura y los motores lo tratan como ausente.
    final newScores = Map<String, Map<int, HoleScore>>.from(_round!.scores);
    newScores.putIfAbsent(playerId, () => {});
    final newEvents = Map<String, Map<int, List<HoleEvent>>>.from(_round!.events);
    newEvents.putIfAbsent(playerId, () => {});

    // RoundPlayer con su handicap, si aún no existe
    final newRPs = List<RoundPlayer>.from(_round!.roundPlayers);
    if (!newRPs.any((rp) => rp.playerId == playerId)) {
      final player = _round!.players
          .where((p) => p.id == playerId)
          .firstOrNull;
      newRPs.add(RoundPlayer(
        playerId: playerId,
        handicapEnRonda: player?.handicapBase ?? 0,
      ));
    }

    _round = _round!.copyWith(
      betGroups:    newGroups,
      scores:       newScores,
      events:       newEvents,
      roundPlayers: newRPs,
    );
    notifyListeners();
    _persist();

    return newGroups[gi].modules.where((m) => m.effectiveScope.isEveryone).length;
  }

  // ── Apertura de alcance en rondas ya creadas ───────────────────────────────

  /// true si [mod] cubre exactamente a toda su partida pero tiene el alcance
  /// fijado a esa lista concreta de jugadores.
  ///
  /// Abrirlo NO cambia quién juega hoy — los participantes son los mismos —,
  /// solo hace que quien se sume más tarde entre automáticamente.
  static bool _isOpenable(BetModuleInstance mod, BetGroup group) {
    if (mod.effectiveScope.isEveryone) return false; // ya está abierto
    if (mod.hasTeamSides) return false;              // los equipos son fijos
    final pids = mod.participantIds.toSet();
    if (pids.length < 2) return false;
    final groupIds = group.playerIds.toSet();
    return pids.length == groupIds.length && pids.containsAll(groupIds);
  }

  /// Cuántas apuestas de la ronda podrían abrirse a toda su partida.
  int get openableBetsCount {
    if (_round == null) return 0;
    return _round!.betGroups.fold(
      0,
      (acc, g) => acc + g.modules.where((m) => _isOpenable(m, g)).length,
    );
  }

  /// Convierte a alcance abierto todas las apuestas de [openableBetsCount].
  /// Devuelve cuántas se convirtieron.
  int openAllWholeGroupBets() {
    if (_round == null) return 0;
    int changed = 0;

    final newGroups = _round!.betGroups.map((g) {
      final mods = g.modules.map((m) {
        if (!_isOpenable(m, g)) return m;
        changed++;
        return m.copyWith(scope: const BetScope.everyone());
      }).toList();
      return g.copyWith(modules: mods);
    }).toList();

    if (changed == 0) return 0;
    _round = _round!.copyWith(betGroups: newGroups);
    notifyListeners();
    _persist();
    return changed;
  }

  // ── Permisos colaborativos ─────────────────────────────────────────────────

  /// Jugador de la ronda cuyo [Player.linkedUserId] coincide con el UID actual.
  /// null si el usuario no tiene un jugador asociado en esta ronda.
  Player? get myPlayerInRound {
    final uid = AuthService.uid;
    if (uid == null || _round == null) return null;
    try {
      return _round!.players.firstWhere(
        (p) => p.linkedUserId != null && p.linkedUserId == uid,
      );
    } catch (_) {
      return null;
    }
  }

  /// true si el usuario actual participa en el duelo (es p1 o p2).
  bool isParticipantInDuel(String p1Id, String p2Id) {
    final me = myPlayerInRound;
    if (me == null) return false;
    return me.id == p1Id || me.id == p2Id;
  }

  /// true si el usuario puede editar apuestas directamente:
  /// - es el owner de la ronda en vivo, O
  /// - la ronda no es en vivo.
  bool get canEditBets {
    if (_round == null) return true;
    if (!_round!.isLive) return true;
    return isLiveOwner;
  }

  /// true si el usuario puede proponer un cambio de apuesta en este duelo:
  /// - ronda en vivo, scoringMode == 'open' o 'collaborative'
  /// - usuario es participante del duelo
  /// - usuario NO es el owner (el owner edita directamente)
  bool canProposeBetChange(String p1Id, String p2Id) {
    if (_round == null) return false;
    if (!_round!.isLive) return false;
    if (isLiveOwner) return false; // owner edita directo, no propone
    if (_round!.isAdminScoring) return false; // en admin mode, invitados = read-only
    return isParticipantInDuel(p1Id, p2Id);
  }

  /// true si el usuario NO es participante del duelo de la propuesta ni owner.
  bool isOutsiderForProposal(BetChangeProposal proposal) {
    if (isLiveOwner) return false;
    return !isParticipantInDuel(proposal.p1Id, proposal.p2Id);
  }

  /// Propuestas activas (pendientes) para un duelo concreto.
  List<BetChangeProposal> pendingProposalsForDuel(String p1Id, String p2Id) {
    if (_round == null) return [];
    return _round!.pendingProposals.where((pr) =>
      pr.isPending &&
      ((pr.p1Id == p1Id && pr.p2Id == p2Id) ||
       (pr.p1Id == p2Id && pr.p2Id == p1Id)),
    ).toList();
  }

  // ── CRUD propuestas colaborativas ──────────────────────────────────────────

  /// Añade una nueva propuesta de cambio. Requiere que el usuario sea
  /// participante del duelo y que el scoringMode permita propuestas.
  void proposeBetChange(BetChangeProposal proposal) {
    if (_round == null) return;
    if (!canProposeBetChange(proposal.p1Id, proposal.p2Id)) return;

    // Descartar propuestas anteriores del mismo tipo y duelo (reemplazar)
    final filtered = _round!.pendingProposals.where((pr) =>
      !(pr.isPending &&
        pr.changeType == proposal.changeType &&
        ((pr.p1Id == proposal.p1Id && pr.p2Id == proposal.p2Id) ||
         (pr.p1Id == proposal.p2Id && pr.p2Id == proposal.p1Id)) &&
        pr.moduleId == proposal.moduleId),
    ).toList();

    _round = _round!.copyWith(
      pendingProposals: [...filtered, proposal],
    );
    notifyListeners();
    _persist();
  }

  /// El usuario actual aprueba una propuesta. Si el quórum es suficiente
  /// (ambos jugadores del duelo la aprobaron o el owner la aprueba),
  /// la propuesta se aplica y su estado cambia a [approved].
  void approveBetChange(String proposalId) {
    if (_round == null) return;
    final uid = AuthService.uid;
    if (uid == null) return;

    final idx = _round!.pendingProposals.indexWhere(
      (pr) => pr.id == proposalId && pr.isPending,
    );
    if (idx < 0) return;

    final proposal = _round!.pendingProposals[idx];

    // Calcular nuevo estado de aprobación
    final newApprovedBy = [...proposal.approvedByUids];
    if (!newApprovedBy.contains(uid)) newApprovedBy.add(uid);

    // Quórum: el owner puede aprobar solo; participantes necesitan ambos
    final quorumReached = isLiveOwner ||
        (_quorumUidsForDuel(proposal.p1Id, proposal.p2Id)
            .every((u) => newApprovedBy.contains(u)));

    final updated = proposal.copyWith(
      approvedByUids: newApprovedBy,
      status: quorumReached ? BetProposalStatus.approved : BetProposalStatus.pending,
      resolvedByUid: quorumReached ? uid : null,
    );

    final newProposals = List<BetChangeProposal>.from(_round!.pendingProposals);
    newProposals[idx] = updated;
    _round = _round!.copyWith(pendingProposals: newProposals);

    if (quorumReached) _applyProposalPayload(updated);

    notifyListeners();
    _persist();
  }

  /// Rechaza una propuesta (cualquier participante o el owner puede rechazar).
  void rejectBetChange(String proposalId) {
    if (_round == null) return;
    final uid = AuthService.uid;
    if (uid == null) return;

    final idx = _round!.pendingProposals.indexWhere(
      (pr) => pr.id == proposalId && pr.isPending,
    );
    if (idx < 0) return;

    final updated = _round!.pendingProposals[idx].copyWith(
      status: BetProposalStatus.rejected,
      resolvedByUid: uid,
    );
    final newProposals = List<BetChangeProposal>.from(_round!.pendingProposals);
    newProposals[idx] = updated;
    _round = _round!.copyWith(pendingProposals: newProposals);
    notifyListeners();
    _persist();
  }

  /// Elimina propuestas ya resueltas (approved / rejected) de la lista.
  void clearResolvedProposals() {
    if (_round == null) return;
    final active = _round!.pendingProposals
        .where((pr) => pr.isPending)
        .toList();
    if (active.length == _round!.pendingProposals.length) return;
    _round = _round!.copyWith(pendingProposals: active);
    notifyListeners();
    _persist();
  }

  /// UIDs de los dos jugadores del duelo (para calcular quórum).
  List<String> _quorumUidsForDuel(String p1Id, String p2Id) {
    if (_round == null) return [];
    final uids = <String>[];
    for (final p in _round!.players) {
      if ((p.id == p1Id || p.id == p2Id) &&
          p.linkedUserId != null &&
          p.linkedUserId!.isNotEmpty) {
        uids.add(p.linkedUserId!);
      }
    }
    return uids;
  }

  /// Aplica el payload de una propuesta aprobada al modelo de la ronda.
  void _applyProposalPayload(BetChangeProposal p) {
    if (_round == null) return;
    final payload = p.payload;

    switch (p.changeType) {
      case 'handicap':
        // payload: {'manualStrokes': 2.0, 'p1ReceivesFrom': 'pB_id'}
        final strokes = (payload['manualStrokes'] as num?)?.toDouble();
        final receiver = payload['p1ReceivesFrom'] as String?;
        final giver = receiver == p.p1Id ? p.p2Id : p.p1Id;
        if (receiver != null && strokes != null) {
          // Actualizar pairSliding: cuánto recibe el lowId
          final lowId  = receiver.compareTo(giver) <= 0 ? receiver : giver;
          final highId = receiver.compareTo(giver) <= 0 ? giver : receiver;
          final canonicalVal = receiver == lowId ? strokes : -strokes;
          final newPs = Map<String, double>.from(_round!.pairSliding);
          newPs['$lowId|$highId'] = canonicalVal;
          _round = _round!.copyWith(pairSliding: newPs);
        }

      case 'amount':
      case 'mode':
      case 'rules':
        // Aplicar cambios al BetModuleInstance si moduleId está presente
        if (p.moduleId != null) {
          final groupIdx = _round!.betGroups.indexWhere((g) => g.id == p.groupId);
          if (groupIdx < 0) break;
          final group = _round!.betGroups[groupIdx];
          final modIdx = group.modules.indexWhere((m) => m.id == p.moduleId);
          if (modIdx < 0) break;

          final mod = group.modules[modIdx];
          final updatedMod = _applyPayloadToModule(mod, payload);
          final newMods = List<BetModuleInstance>.from(group.modules);
          newMods[modIdx] = updatedMod;
          final newGroups = List<BetGroup>.from(_round!.betGroups);
          newGroups[groupIdx] = group.copyWith(modules: newMods);
          _round = _round!.copyWith(betGroups: newGroups);
        }
    }
  }

  /// Aplica el mapa [payload] a los campos de un [BetModuleInstance].
  /// Solo modifica los campos que el payload contiene; devuelve una copia.
  BetModuleInstance _applyPayloadToModule(
      BetModuleInstance mod, Map<String, dynamic> payload) {
    // Configuración de Nassau
    NassauConfig? nassauCfg = mod.nassauConfig;
    if (nassauCfg != null) {
      nassauCfg = nassauCfg.copyWith(
        frontValue:   (payload['nassauFront']  as num?)?.toDouble(),
        backValue:    (payload['nassauBack']   as num?)?.toDouble(),
        totalValue:   (payload['nassauTotal']  as num?)?.toDouble(),
        pressEnabled: payload.containsKey('pressEnabled')
            ? payload['pressEnabled'] == true : null,
      );
    }

    // Configuración de Skins
    SkinsConfig? skinsCfg = mod.skinsConfig;
    if (skinsCfg != null) {
      skinsCfg = skinsCfg.copyWith(
        valuePerSkin: (payload['valuePerSkin'] as num?)?.toDouble(),
        carryOver:    payload.containsKey('carryOver')
            ? payload['carryOver'] == true : null,
      );
    }

    // Configuración de Putts
    PuttsConfig? puttsCfg = mod.puttsConfig;
    if (puttsCfg != null) {
      puttsCfg = puttsCfg.copyWith(
        value: (payload['valuePerPutt'] as num?)?.toDouble(),
      );
    }

    // Configuración de Snake
    SnakeConfig? snakeCfg = mod.snakeConfig;
    if (snakeCfg != null) {
      snakeCfg = snakeCfg.copyWith(
        value: (payload['snakeValue'] as num?)?.toDouble(),
      );
    }

    // Configuración de Rabbit
    RabbitConfig? rabbitCfg = mod.rabbitConfig;
    if (rabbitCfg != null) {
      rabbitCfg = rabbitCfg.copyWith(
        value: (payload['rabbitValue'] as num?)?.toDouble(),
      );
    }

    // Configuración de Medal
    MedalConfig? medalCfg = mod.medalConfig;
    if (medalCfg != null) {
      medalCfg = medalCfg.copyWith(
        value: (payload['valuePerStroke'] as num?)?.toDouble(),
      );
    }

    return BetModuleInstance(
      id:                    mod.id,
      type:                  mod.type,
      name:                  mod.name,
      participantIds:        mod.participantIds,
      sides:                 mod.sides,
      status:                mod.status,
      formatMode:            mod.formatMode,
      nassauConfig:          nassauCfg,
      skinsConfig:           skinsCfg,
      matchAutoPressConfig:  mod.matchAutoPressConfig,
      medalConfig:           medalCfg,
      puttsConfig:           puttsCfg,
      oyesesConfig:          mod.oyesesConfig,
      unitsConfig:           mod.unitsConfig,
      // Se reconstruye campo a campo, no con copyWith, así que una config que
      // falte aquí se BORRA en silencio al editar cualquier otra cosa del
      // módulo. El compilador no lo caza: son parámetros con nombre opcionales.
      snakeConfig:           snakeCfg,
      rabbitConfig:          rabbitCfg,
      presses:               mod.presses,
      structure:             mod.structure,
      betGroupId:            mod.betGroupId,
      betGroupName:          mod.betGroupName,
      anchorPlayerId:        mod.anchorPlayerId,
      playerConfigOverrides: mod.playerConfigOverrides,
      pairConfigOverrides:   mod.pairConfigOverrides,
    );
  }

  // ── Round players (ventajas manuales) ──────────────────────────────────────
  void updateRoundPlayers(List<RoundPlayer> roundPlayers) {
    if (_round == null) return;
    // ── Re-sincronizar pairSliding desde los nuevos manualHandicaps ──────────
    // Home screen escribe en roundPlayers.manualHandicaps. Para que la tarjeta
    // 1v1 y el ledger lo reflejen de inmediato, reconstruimos pairSliding.
    final mergedPs = _mergePairSlidingFromRoundPlayers(
        _round!.pairSliding, roundPlayers, _round!.isLive);
    _round = _round!.copyWith(roundPlayers: roundPlayers, pairSliding: mergedPs);
    notifyListeners();
    _persist();
  }

  // ── Helpers de sincronización pairSliding ──────────────────────────────────

  /// Clave canónica: ids en orden lexicográfico separados por '|'.
  static String _pairKey(String a, String b) => _pairKeyOf(a, b);

  /// Reconstruye pairSliding a partir de los manualHandicaps de [roundPlayers].
  ///
  /// **Modo no-live** (rondas locales, setup):
  ///   pairSliding = espejo EXACTO de manualHandicaps entre jugadores de la ronda.
  ///   Los pares donde AMBOS jugadores están en la ronda se reconstruyen desde
  ///   cero; los pares con al menos un jugador externo se conservan de [existingPs].
  ///   Esto evita que un valor viejo quede pegado cuando el usuario baja/quita
  ///   una ventaja desde Home.
  ///
  /// **Modo live** (comportamiento previo, sin cambios):
  ///   Solo se sobreescriben/añaden los pares que aparecen en manualHandicaps;
  ///   el resto de [existingPs] se conserva para no pisar propuestas colaborativas
  ///   aprobadas por otros jugadores vía el sistema de proposals.
  static Map<String, double> _mergePairSlidingFromRoundPlayers(
      Map<String, double> existingPs,
      List<RoundPlayer> roundPlayers,
      bool isLive,
  ) {
    final ids = roundPlayers.map((rp) => rp.playerId).toSet();

    if (isLive) {
      // ── Live: añadir/sobreescribir, nunca borrar (preserva propuestas) ───
      final result = Map<String, double>.from(existingPs);
      final seen   = <String>{};
      for (final rp in roundPlayers) {
        final p1 = rp.playerId;
        for (final entry in rp.manualHandicaps.entries) {
          final p2  = entry.key;
          final m1  = entry.value;
          final key = _pairKey(p1, p2);
          if (seen.contains(key)) continue;
          seen.add(key);
          final lowId = p1.compareTo(p2) <= 0 ? p1 : p2;
          result[key] = (p1 == lowId) ? m1 : -m1;
        }
      }
      return result;
    }

    // ── No-live: espejo exacto de manualHandicaps entre jugadores de la ronda ─
    // Conservar solo pares con algún jugador FUERA de la ronda (datos externos).
    final result = <String, double>{};
    for (final entry in existingPs.entries) {
      final parts = entry.key.split('|');
      // Conservar si al menos uno de los dos no pertenece a roundPlayers
      if (parts.length == 2 &&
          !(ids.contains(parts[0]) && ids.contains(parts[1]))) {
        result[entry.key] = entry.value;
      }
    }
    // Escribir desde manualHandicaps (la ausencia de entrada = ventaja = 0 = eliminada)
    final seen = <String>{};
    for (final rp in roundPlayers) {
      final p1 = rp.playerId;
      for (final entry in rp.manualHandicaps.entries) {
        final p2  = entry.key;
        final m1  = entry.value;
        final key = _pairKey(p1, p2);
        if (seen.contains(key)) continue;
        seen.add(key);
        final lowId = p1.compareTo(p2) <= 0 ? p1 : p2;
        result[key] = (p1 == lowId) ? m1 : -m1;
      }
    }
    return result;
  }

  void setCurrentHole(int h) {
    if (_round == null) return;
    _round = _round!.copyWith(currentHole: h);
    notifyListeners();
  }

  // ── Computed ───────────────────────────────────────────────────────────────
  Map<String, double> get balances {
    if (_round == null) return {};
    try {
      return LedgerEngine.playerBalances(_round!);
    } catch (e, st) {
      if (kDebugMode) debugPrint('[balances] Error: $e\n$st');
      return {};
    }
  }

  List<NetDebt> get netDebts {
    if (_round == null) return [];
    try {
      return LedgerEngine.compute(_round!);
    } catch (e, st) {
      if (kDebugMode) debugPrint('[netDebts] Error: $e\n$st');
      return [];
    }
  }

  // ── Persistence: local + Firestore ─────────────────────────────────────────
  Future<void> loadPrefs() async {
    final p = await _prefs();
    _themeMode = AppThemeMode.values.firstWhere(
      (t) => t.name == (p.getString('theme') ?? 'light'),
      orElse: () => AppThemeMode.light,
    );
    GolfThemeExt.setCurrent(theme);
    final json = p.getString('round');
    if (json != null) {
      try {
        _round = roundFromJson(jsonDecode(json) as Map<String, dynamic>);
        // Si había una ronda en vivo activa, reactivar listener al reabrir app
        if (_round!.isLive && !_round!.isFinished) {
          _startLiveListener(_round!.id);
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Llamar tras login: carga ronda activa desde Firestore y sincroniza pendientes.
  Future<void> syncFromFirestore() async {
    if (AuthService.uid == null) return;

    // 1. Sincronizar rondas finalizadas que quedaron pendientes localmente
    final synced = await syncPendingFinished();
    if (synced > 0 && kDebugMode) {
      debugPrint('syncFromFirestore: \$synced ronda(s) pendiente(s) sincronizadas');
    }

    // 2. Cargar ronda activa remota
    // Si ya hay una ronda en vivo activa (invitado unido), NO sobreescribir con ronda personal
    if (_round != null && _round!.isLive && !_round!.isFinished) {
      if (kDebugMode) debugPrint('[syncFromFirestore] Ronda en vivo activa, omitiendo.');
      return;
    }
    try {
      // 2a. Primero buscar si el usuario es organizador de una ronda live activa
      Round? remote;
      final ownerLive = await LiveRoundService.loadOwnerActiveLiveRound();
      if (ownerLive != null) {
        remote = ownerLive;
        if (kDebugMode) debugPrint('[syncFromFirestore] Cargando ronda live del organizador: ${ownerLive.id}');
      } else {
        // 2b. Buscar si el usuario es invitado aceptado en una ronda live activa
        final acceptedLive = await LiveRoundService.loadAcceptedLiveRound();
        if (acceptedLive != null) {
          remote = acceptedLive;
          if (kDebugMode) debugPrint('[syncFromFirestore] Cargando ronda live como invitado: ${acceptedLive.id}');
        } else {
          // 2c. Si no, cargar ronda normal desde colección personal
          remote = await FirestoreService.loadActiveRound();
        }
      }

      if (remote != null) {
        // Verificación post-fetch: si mientras esperaba el usuario se unió a una ronda live, no sobreescribir
        if (_round != null && _round!.isLive && !_round!.isFinished) {
          if (kDebugMode) debugPrint('[syncFromFirestore] Ronda en vivo activa (post-fetch), omitiendo.');
          return;
        }
        _round = remote;
        // Si la ronda cargada ya está finalizada (admin la cerró antes de que
        // el invitado abriera la app), mostrar el banner de aviso en Resultados.
        if (_round!.isFinished && _round!.isLive && !isLiveOwner) {
          _roundFinishedByAdmin = true;
          _tabIndex = 2; // Ir directo a Resultados
        } else {
          _tabIndex = _round!.isFinished ? 0 : 1;
        }
        notifyListeners();
        // Actualizar caché local
        final p = await _prefs();
        await p.setString('round', jsonEncode(roundToJson(_round!)));
        // Si es ronda en vivo activa, activar listener
        if (_round!.isLive && !_round!.isFinished) {
          _startLiveListener(_round!.id);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[syncFromFirestore] Error: $e');
    }
  }

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  /// Persiste localmente Y en Firestore si hay sesión
  Future<void> _persist() async {
    if (_round == null) return;
    // Local — siempre
    try {
      final p = await _prefs();
      await p.setString('round', jsonEncode(roundToJson(_round!)));
    } catch (e) {
      debugPrint('[_persist] Error local: $e');
    }
    // Firestore — fire-and-forget con log de error
    if (AuthService.uid != null) {
      if (_round!.isLive) {
        // Ronda en vivo: escribir en liveRounds (compartida)
        // Marcar que el próximo evento del stream es nuestro (eco)
        _ignoringLiveUpdate = true;
        // Incrementar contador de escrituras locales de pairSliding pendientes.
        // El listener lo decrementará al recibir el eco y, mientras sea > 0,
        // preservará el pairSliding local ante cualquier evento remoto
        // (incluso si llegan varios eventos concurrentes de otros jugadores).
        _pendingPairSlidingWrites++;
        LiveRoundService.saveRound(_round!).catchError((e) {
          _ignoringLiveUpdate = false;
          // Si el save falla, revertir el contador para no bloquear el listener
          // indefinidamente en caso de error de red.
          if (_pendingPairSlidingWrites > 0) _pendingPairSlidingWrites--;
          debugPrint('[_persist] LiveRound error: $e');
        });
      } else {
        // Ronda normal: escribir en users/{uid}/rounds
        FirestoreService.saveRound(_round!).catchError((e) {
          debugPrint('[_persist] Firestore error (ignorado): $e');
        });
      }
    }
  }

  // ── Clone helpers ──────────────────────────────────────────────────────────
  Map<String, Map<int, HoleScore>> _cloneScores() {
    final result = <String, Map<int, HoleScore>>{};
    for (final entry in _round!.scores.entries) {
      result[entry.key] = Map<int, HoleScore>.from(entry.value);
    }
    return result;
  }

  Map<String, Map<int, List<HoleEvent>>> _cloneEvents() {
    final result = <String, Map<int, List<HoleEvent>>>{};
    for (final entry in _round!.events.entries) {
      final inner = <int, List<HoleEvent>>{};
      for (final he in entry.value.entries) {
        inner[he.key] = List<HoleEvent>.from(he.value);
      }
      result[entry.key] = inner;
    }
    return result;
  }
}
