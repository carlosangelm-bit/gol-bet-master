// ─────────────────────────────────────────────────────────────────────────────
// PLAYER PROVIDER — Estado del directorio de compañeros
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/player_service.dart';

class PlayerProvider extends ChangeNotifier {
  List<PlayerWithLink> _directory = [];
  bool    _loading = false;
  String? _error;
  StreamSubscription<List<PlayerWithLink>>? _sub;

  // ── Getters ────────────────────────────────────────────────────────────────
  List<PlayerWithLink> get directory => _directory;
  List<PlayerWithLink> get favorites => _directory.where((p) => p.isFavorite).toList();
  bool    get loading => _loading;
  String? get error   => _error;
  bool    get isEmpty => _directory.isEmpty;

  /// Siembra el directorio sin Firestore, para los tests de widget.
  ///
  /// La misma costura que PerfilProvider y TorneoProvider. Sin ella, una pantalla
  /// que resuelve nombres contra el directorio se prueba con el directorio vacío
  /// —o sea, se prueba el camino de respaldo y no el real—.
  @visibleForTesting
  void sembrar(List<PlayerWithLink> dir) {
    _directory = dir;
    _loading = false;
    notifyListeners();
  }

  // ── Suscripción en tiempo real ──────────────────────────────────────────────
  void startListening() {
    _sub?.cancel();
    _loading = true;
    _error   = null;
    notifyListeners();

    _sub = PlayerService.directoryStream().listen(
      (list) {
        _directory = list;
        _loading   = false;
        _error     = null;
        notifyListeners();
      },
      onError: (e) {
        if (kDebugMode) debugPrint('PlayerProvider stream error: $e');
        // Guardar el error real completo para diagnóstico en pantalla
        _error = e.toString();
        _loading = false;
        notifyListeners();
      },
    );
  }

  /// Reinicia la escucha (útil tras error de permisos o conexión)
  void retry() => startListening();

  void stopListening() {
    _sub?.cancel();
    _sub = null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ── Operaciones CRUD — relanzamos errores para que la UI los muestre ────────

  Future<PlayerWithLink> createPlayer({
    required String name,
    double handicap = 0,
    int colorIndex = 0,
    bool isFavorite = false,
    String? customDisplayName,
    double defaultSlidingAdjustment = 0,
    String? notes,
  }) async {
    // Sin try-catch aquí: el error sube a la UI (_PlayerFormSheet._save)
    final result = await PlayerService.createPlayer(
      name: name,
      handicap: handicap,
      colorIndex: colorIndex,
      isFavorite: isFavorite,
      customDisplayName: customDisplayName,
      defaultSlidingAdjustment: defaultSlidingAdjustment,
      notes: notes,
    );
    return result;
  }

  Future<void> updatePlayer(Player player) =>
      PlayerService.updatePlayerData(player);

  Future<void> updateLink(PlayerLink link) =>
      PlayerService.updateLink(link);

  Future<void> toggleFavorite(String playerId) {
    final current = _directory
        .where((p) => p.player.id == playerId)
        .map((p) => p.isFavorite)
        .firstOrNull ?? false;
    return PlayerService.toggleFavorite(playerId, current);
  }

  Future<void> removeFromDirectory(String playerId) =>
      PlayerService.removeFromDirectory(playerId);

  // ── Búsqueda local en el directorio cargado ────────────────────────────────
  List<PlayerWithLink> search(String query) {
    if (query.isEmpty) return _directory;
    final q = query.toLowerCase();
    return _directory.where((p) =>
      p.displayName.toLowerCase().contains(q) ||
      p.player.name.toLowerCase().contains(q)
    ).toList();
  }

  /// Convierte el directorio en una lista de Player para el setup de ronda.
  /// Usa el displayName del link si existe.
  List<Player> toPlayers(List<String> selectedIds) {
    return _directory
        .where((pw) => selectedIds.contains(pw.player.id))
        .map((pw) => pw.player.copyWith(name: pw.displayName))
        .toList();
  }
}
