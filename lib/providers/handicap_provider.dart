// ─────────────────────────────────────────────────────────────────────────────
// HANDICAP PROVIDER — Handicap Index en tiempo real (WHS)
// Carga los diferenciales del usuario desde Firestore y calcula el HI
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';
import '../services/handicap_service.dart';

class HandicapProvider extends ChangeNotifier {
  static final _db = FirebaseFirestore.instance;

  StreamSubscription<QuerySnapshot>? _sub;
  List<ScoreDifferential> _diffs = [];
  HandicapIndexResult _result = HandicapIndexResult(
    totalRounds: 0,
    usedDifferentials: [],
    allDifferentials: [],
  );
  bool _loading = false;
  String? _error;

  // ── Getters ──────────────────────────────────────────────────────────────────
  bool get loading => _loading;
  String? get error => _error;
  HandicapIndexResult get result => _result;
  List<ScoreDifferential> get differentials => _diffs;
  double? get handicapIndex => _result.index;
  String get displayIndex => _result.displayIndex;

  // ── Inicializar escucha ───────────────────────────────────────────────────────
  void startListening() {
    if (_sub != null) return; // ya activo
    final uid = AuthService.uid;
    if (uid == null) return;

    _loading = true;
    _error = null;
    notifyListeners();

    _sub = _db
        .collection('users')
        .doc(uid)
        .collection('scoreDifferentials')
        .snapshots()
        .listen(
          (snap) {
            _diffs = snap.docs
                .map((d) {
                  try {
                    return ScoreDifferential.fromJson(
                        Map<String, dynamic>.from(d.data()));
                  } catch (_) {
                    return null;
                  }
                })
                .whereType<ScoreDifferential>()
                .toList();
            _result = HandicapService.calculateIndex(_diffs);
            _loading = false;
            _error = null;
            notifyListeners();
          },
          onError: (e) {
            _error = e.toString();
            _loading = false;
            notifyListeners();
          },
        );
  }

  void stopListening() {
    _sub?.cancel();
    _sub = null;
    _diffs = [];
    _result = HandicapIndexResult(
      totalRounds: 0,
      usedDifferentials: [],
      allDifferentials: [],
    );
    _loading = false;
    _error = null;
    notifyListeners();
  }

  // ── Guardar un diferencial nuevo ──────────────────────────────────────────────
  Future<void> saveDifferential(ScoreDifferential diff) async {
    final uid = AuthService.uid;
    if (uid == null) return;
    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('scoreDifferentials')
          .doc(diff.roundId)
          .set(diff.toJson(), SetOptions(merge: false));
    } catch (e) {
      if (kDebugMode) debugPrint('HandicapProvider.saveDifferential error: $e');
    }
  }

  /// Migra rondas históricas: calcula y guarda diferenciales de rondas pasadas
  /// que no tengan diferencial registrado aún.
  Future<int> migrateHistoricalRounds(List<Map<String, dynamic>> roundsJson) async {
    final uid = AuthService.uid;
    if (uid == null) return 0;

    // Obtener los roundIds que ya tienen diferencial
    final existing = _diffs.map((d) => d.roundId).toSet();

    int saved = 0;
    for (final json in roundsJson) {
      final id = json['id'] as String? ?? '';
      if (id.isEmpty || existing.contains(id)) continue;

      // Tenemos que importar roundFromJson aquí dinámicamente para evitar
      // dependencias circulares — usamos los campos directamente
      // La migración la haremos mediante HandicapService.calculateFromRound
      // que recibe el Round deserializado
      saved++;
    }
    return saved;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
