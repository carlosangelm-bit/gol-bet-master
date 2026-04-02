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
  if (participantUids.isNotEmpty) 'participantUids': participantUids,
  'course': r.course.toJson(),
  'players': r.players.map((p) => p.toJson()).toList(),
  'roundPlayers': r.roundPlayers.map((rp) => rp.toJson()).toList(),
  'betGroups': r.betGroups.map((g) => g.toJson()).toList(),
  'scores': r.scores.map((pid, hmap) => MapEntry(pid, hmap.map((h, s) => MapEntry(h.toString(), s.toJson())))),
  'events': r.events.map((pid, hmap) => MapEntry(pid, hmap.map((h, list) => MapEntry(h.toString(), list.map((e) => e.toJson()).toList())))),
  'oyeseRankings': r.oyeseRankings.map((h, or_) => MapEntry(h.toString(), or_.toJson())),
  'sliding': r.sliding.map((s) => s.toJson()).toList(),
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
    id: j['id'] as String, name: j['name'] as String,
    createdAt: parsedCreatedAt,
    currentHole: j['currentHole'] as int? ?? 1,
    isFinished: j['isFinished'] as bool? ?? false,
    startingNine: j['startingNine'] == 'back' ? StartingNine.back : StartingNine.front,
    totalHoles: j['totalHoles'] as int? ?? 18,
    isLive: j['isLive'] as bool? ?? false,
    ownerUid: j['ownerUid'] as String?,
    liveCode: j['liveCode'] as String?,
    players: players, roundPlayers: roundPlayers,
    betGroups: betGroups,
    course: j['course'] != null
        ? CourseInfo.fromJson(j['course'] as Map<String, dynamic>)
        : CourseInfo.standard,
    scores: scores, events: events, oyeseRankings: oyeses, sliding: sliding,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
class RoundProvider extends ChangeNotifier {
  Round? _round;
  AppThemeMode _themeMode = AppThemeMode.light;
  int _tabIndex = 0;

  // Stream de ronda en vivo
  StreamSubscription<Round?>? _liveRoundSub;
  // Flag para ignorar el próximo evento del stream (evitar eco)
  bool _ignoringLiveUpdate = false;

  Round? get round => _round;
  AppThemeMode get themeMode => _themeMode;
  int get tabIndex => _tabIndex;
  bool get hasRound => _round != null;
  bool get isLiveRound => _round?.isLive ?? false;
  bool get isLiveOwner => _round?.isLive == true && _round?.ownerUid == AuthService.uid;

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
    _tabIndex = 1;
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
      // Solo actualizar si hay cambio real (evitar rebuilds innecesarios)
      if (_round == null) return;
      _round = remote;
      notifyListeners();
      // Actualizar caché local también
      _prefs().then((p) => p.setString('round', jsonEncode(roundToJson(remote))));
    });
    if (kDebugMode) debugPrint('[LiveRound] Listener iniciado: $roundId');
  }

  void _cancelLiveListener() {
    _liveRoundSub?.cancel();
    _liveRoundSub = null;
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

  // ── Round players (ventajas manuales) ──────────────────────────────────────
  void updateRoundPlayers(List<RoundPlayer> roundPlayers) {
    if (_round == null) return;
    _round = _round!.copyWith(roundPlayers: roundPlayers);
    notifyListeners();
    _persist();
  }

  void setCurrentHole(int h) {
    if (_round == null) return;
    _round = _round!.copyWith(currentHole: h);
    notifyListeners();
  }

  // ── Computed ───────────────────────────────────────────────────────────────
  Map<String, double> get balances => _round != null ? LedgerEngine.playerBalances(_round!) : {};
  List<NetDebt> get netDebts => _round != null ? LedgerEngine.compute(_round!) : [];

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
    try {
      final remote = await FirestoreService.loadActiveRound();
      if (remote != null) {
        _round = remote;
        _tabIndex = _round!.isFinished ? 0 : 1;
        notifyListeners();
        // Actualizar caché local
        final p = await _prefs();
        await p.setString('round', jsonEncode(roundToJson(_round!)));
        // Si era ronda en vivo, reactivar listener
        if (_round!.isLive && !_round!.isFinished) {
          _startLiveListener(_round!.id);
        }
      }
    } catch (_) {}
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
        LiveRoundService.saveRound(_round!).catchError((e) {
          _ignoringLiveUpdate = false;
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
