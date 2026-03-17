// ─────────────────────────────────────────────────────────────────────────────
// ROUND PROVIDER — State management central
// Recalcula el ledger automáticamente ante cualquier cambio.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_theme.dart';
import '../engines/ledger_engine.dart';
import '../models/models.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';

// ── Funciones top-level para serialización (usadas también por FirestoreService)
Map<String, dynamic> roundToJson(Round r) => {
  'id': r.id, 'name': r.name, 'createdAt': r.createdAt.toIso8601String(),
  'currentHole': r.currentHole, 'isFinished': r.isFinished,
  'startingNine': r.startingNine.name,
  'totalHoles': r.totalHoles,
  'course': r.course.toJson(),
  'players': r.players.map((p) => p.toJson()).toList(),
  'roundPlayers': r.roundPlayers.map((rp) => rp.toJson()).toList(),
  'betGroups': r.betGroups.map((g) => g.toJson()).toList(),
  'scores': r.scores.map((pid, hmap) => MapEntry(pid, hmap.map((h, s) => MapEntry(h.toString(), s.toJson())))),
  'events': r.events.map((pid, hmap) => MapEntry(pid, hmap.map((h, list) => MapEntry(h.toString(), list.map((e) => e.toJson()).toList())))),
  'oyeseRankings': r.oyeseRankings.map((h, or_) => MapEntry(h.toString(), or_.toJson())),
  'sliding': r.sliding.map((s) => s.toJson()).toList(),
};

Round roundFromJson(Map<String, dynamic> j) {
  final players     = (j['players'] as List).map((p) => Player.fromJson(p as Map<String, dynamic>)).toList();
  final roundPlayers = (j['roundPlayers'] as List).map((rp) => RoundPlayer.fromJson(rp as Map<String, dynamic>)).toList();
  final betGroups   = (j['betGroups'] as List).map((g) => BetGroup.fromJson(g as Map<String, dynamic>)).toList();

  final scoresJson = j['scores'] as Map<String, dynamic>;
  final scores = <String, Map<int, HoleScore>>{};
  scoresJson.forEach((pid, hmap) {
    final inner = <int, HoleScore>{};
    (hmap as Map<String, dynamic>).forEach((hStr, sJson) {
      inner[int.parse(hStr)] = HoleScore.fromJson(sJson as Map<String, dynamic>);
    });
    scores[pid] = inner;
  });

  final eventsJson = j['events'] as Map<String, dynamic>;
  final events = <String, Map<int, List<HoleEvent>>>{};
  eventsJson.forEach((pid, hmap) {
    final inner = <int, List<HoleEvent>>{};
    (hmap as Map<String, dynamic>).forEach((hStr, list) {
      inner[int.parse(hStr)] = (list as List)
          .map((e) => HoleEvent.fromJson(e as Map<String, dynamic>))
          .toList();
    });
    events[pid] = inner;
  });

  final oyesesJson = j['oyeseRankings'] as Map<String, dynamic>;
  final oyeses = <int, OyeseRanking>{};
  oyesesJson.forEach((hStr, or_) {
    oyeses[int.parse(hStr)] = OyeseRanking.fromJson(or_ as Map<String, dynamic>);
  });

  final sliding = (j['sliding'] as List).map((s) => SlidingRelation.fromJson(s as Map<String, dynamic>)).toList();

  return Round(
    id: j['id'] as String, name: j['name'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    currentHole: j['currentHole'] as int? ?? 1,
    isFinished: j['isFinished'] as bool? ?? false,
    startingNine: j['startingNine'] == 'back' ? StartingNine.back : StartingNine.front,
    totalHoles: j['totalHoles'] as int? ?? 18,
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

  Round? get round => _round;
  AppThemeMode get themeMode => _themeMode;
  int get tabIndex => _tabIndex;
  bool get hasRound => _round != null;

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
  }

  void finishRound() {
    if (_round == null) return;
    final roundId = _round!.id;
    // Sincronizar con Firestore primero (antes de limpiar la referencia)
    if (AuthService.uid != null) {
      FirestoreService.finishRound(roundId);
    }
    // Limpiar la ronda activa → va al historial automáticamente
    _round = null;
    _tabIndex = 0;
    notifyListeners();
    _prefs().then((p) => p.remove('round'));
  }

  void resetRound() {
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
      try { _round = roundFromJson(jsonDecode(json) as Map<String, dynamic>); } catch (_) {}
    }
    notifyListeners();
  }

  /// Llamar tras login: intenta cargar ronda activa desde Firestore
  Future<void> syncFromFirestore() async {
    if (AuthService.uid == null) return;
    try {
      final remote = await FirestoreService.loadActiveRound();
      if (remote != null) {
        _round = remote;
        _tabIndex = _round!.isFinished ? 0 : 1;
        notifyListeners();
        // Actualizar caché local
        final p = await _prefs();
        await p.setString('round', jsonEncode(roundToJson(_round!)));
      }
    } catch (_) {}
  }

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  /// Persiste localmente Y en Firestore si hay sesión
  Future<void> _persist() async {
    if (_round == null) return;
    // Local
    final p = await _prefs();
    await p.setString('round', jsonEncode(roundToJson(_round!)));
    // Firestore (si autenticado)
    if (AuthService.uid != null) {
      FirestoreService.saveRound(_round!);
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
