// ─────────────────────────────────────────────────────────────────────────────
// PERFIL PROVIDER — tu histórico de dinero, en tiempo real
//
// Hermano de HandicapProvider y montado igual: escucha una colección ligera que
// se escribe al cerrar cada ronda. El tablero de Inicio no descarga rondas.
//
// Lo único que hace es transmitir y delegar: el cálculo vive en resumenDe(),
// que es pura y tiene sus tests. Un provider con lógica dentro es lógica que
// solo se puede probar arrancando Flutter.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/perfil_resumen.dart';
import '../models/round_result.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/user_profile_service.dart';

class PerfilProvider extends ChangeNotifier {
  StreamSubscription<List<RoundResult>>? _sub;
  List<RoundResult> _resultados = [];
  bool _loading = false;
  String? _error;

  bool get loading => _loading;
  String? get error => _error;
  List<RoundResult> get resultados => _resultados;

  /// Cuántas rondas cerradas tienen su resultado ya guardado.
  ///
  /// Se enseña junto al backfill: las rondas cerradas ANTES de que esta
  /// colección existiera no tienen documento, así que el histórico arranca
  /// incompleto y hay que poder decirlo en vez de dar un total corto por
  /// bueno.
  int get rondasConDatos => _resultados.length;

  /// Tu histórico.
  ///
  /// [miId] se puede pasar explícito; si no, se usa el del perfil. Sin ninguno
  /// de los dos devuelve [PerfilResumen.sinIdentidad], que la pantalla
  /// distingue de ir en cero.
  PerfilResumen resumen({String? miId, int cuantasUltimas = 4}) => resumenDe(
        _resultados,
        miId: miId ?? UserProfileService.miJugadorId,
        cuantasUltimas: cuantasUltimas,
      );

  /// Siembra resultados sin Firestore, para los tests de widget.
  ///
  /// El tablero tiene estados que solo se distinguen con datos —el aviso de
  /// "falta decir quién eres" contra la cifra— y sin esto habría que arrancar
  /// una base de datos para comprobar cuál sale.
  @visibleForTesting
  void sembrar(List<RoundResult> resultados) {
    _resultados = resultados;
    _loading = false;
    notifyListeners();
  }

  void startListening() {
    if (_sub != null) return;
    if (AuthService.uid == null) return;

    _loading = true;
    _error = null;
    notifyListeners();

    _sub = FirestoreService.roundResultsStream().listen(
      (lista) {
        _resultados = lista;
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
    _resultados = [];
    _loading = false;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
