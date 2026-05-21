// ─────────────────────────────────────────────────────────────────────────────
// BETTING GROUP PROVIDER — Estado reactivo de grupos habituales de apuestas
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';

class BettingGroupProvider extends ChangeNotifier {
  List<BettingGroup> _groups = [];
  bool               _loading = false;
  String?            _error;
  StreamSubscription<List<BettingGroup>>? _sub;

  List<BettingGroup> get groups  => _groups;
  bool               get loading => _loading;
  String?            get error   => _error;

  // ── Inicialización ──────────────────────────────────────────────────────────
  /// Inicia el stream reactivo de Firestore cuando el usuario está autenticado.
  void init() {
    _sub?.cancel();
    if (AuthService.uid == null) {
      _groups = [];
      notifyListeners();
      return;
    }
    _loading = true;
    notifyListeners();
    _sub = FirestoreService.bettingGroupsStream().listen(
      (list) {
        _groups  = list;
        _loading = false;
        _error   = null;
        notifyListeners();
      },
      onError: (e) {
        _error   = e.toString();
        _loading = false;
        notifyListeners();
      },
    );
  }

  /// Para el stream (p.ej. al cerrar sesión).
  void stop() {
    _sub?.cancel();
    _sub     = null;
    _groups  = [];
    _loading = false;
    _error   = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ── CRUD ────────────────────────────────────────────────────────────────────

  Future<BettingGroup?> save(BettingGroup group) async {
    try {
      final saved = await FirestoreService.saveBettingGroup(group);
      return saved;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> delete(String groupId) async {
    try {
      await FirestoreService.deleteBettingGroup(groupId);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  // ── Detección de compatibilidad ─────────────────────────────────────────────

  /// Devuelve los grupos que tienen al menos un duelo activo
  /// dado el conjunto de jugadores presentes.
  List<BettingGroup> compatibleGroups(Set<String> presentIds) => _groups
      .where((g) => g.activeDuelsFor(presentIds) > 0)
      .toList();

  /// Calcula el resumen de aplicación para un grupo dado los jugadores presentes.
  BettingGroupSummary summaryFor(BettingGroup g, Set<String> presentIds) {
    final activeRules = g.activeRulesFor(presentIds);
    return BettingGroupSummary(
      group:        g,
      activeRules:  activeRules,
      totalModules: activeRules.fold(0, (s, r) => s + r.modules.length),
    );
  }
}

// ── Resumen de aplicación de un grupo ─────────────────────────────────────────
class BettingGroupSummary {
  final BettingGroup       group;
  final List<PairBetRule>  activeRules;
  final int                totalModules;

  const BettingGroupSummary({
    required this.group,
    required this.activeRules,
    required this.totalModules,
  });
}
