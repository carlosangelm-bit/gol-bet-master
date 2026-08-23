// ─────────────────────────────────────────────────────────────────────────────
// TORNEO PROVIDER — la definición se guarda, la tabla se deriva
//
// Hermano de PerfilProvider y montado igual. Lo único que transmite son las
// DEFINICIONES de torneo; la tabla la calcula tablaDe() con los resultados que
// PerfilProvider ya tiene en memoria.
//
// Ninguna tabla se guarda, y es a propósito: si se guardara, corregir una ronda
// dejaría la clasificación vieja sin avisar. Es exactamente lo que pasó con los
// balances del tablero de Inicio.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/torneo.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

class TorneoProvider extends ChangeNotifier {
  StreamSubscription<List<Torneo>>? _sub;
  List<Torneo> _torneos = [];
  bool _loading = false;
  String? _error;

  List<Torneo> get torneos => _torneos;
  bool get loading => _loading;
  String? get error => _error;

  /// Siembra sin Firestore, para los tests de widget.
  @visibleForTesting
  void sembrar(List<Torneo> t) {
    _torneos = t;
    _loading = false;
    notifyListeners();
  }

  void startListening() {
    if (_sub != null) return;
    if (AuthService.uid == null) return;
    _loading = true;
    notifyListeners();
    _sub = FirestoreService.torneosStream().listen((lista) {
      _torneos = lista;
      _loading = false;
      _error = null;
      notifyListeners();
    }, onError: (e) {
      _error = e.toString();
      _loading = false;
      notifyListeners();
    });
  }

  void stopListening() {
    _sub?.cancel();
    _sub = null;
    _torneos = [];
    _loading = false;
    notifyListeners();
  }

  Future<void> guardar(Torneo t) async {
    final guardado = await FirestoreService.saveTorneo(t);
    // Optimista: el stream lo confirmará. Sin esto, crear un torneo y volver a
    // la lista lo enseña vacío hasta que Firestore contesta.
    final i = _torneos.indexWhere((x) => x.id == guardado.id);
    if (i >= 0) {
      _torneos[i] = guardado;
    } else {
      _torneos = [..._torneos, guardado];
    }
    notifyListeners();
  }

  Future<void> borrar(String id) async {
    await FirestoreService.deleteTorneo(id);
    _torneos = _torneos.where((x) => x.id != id).toList();
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
