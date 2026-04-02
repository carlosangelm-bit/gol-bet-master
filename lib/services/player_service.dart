// ─────────────────────────────────────────────────────────────────────────────
// PLAYER SERVICE
// Gestiona dos colecciones Firestore:
//   • players/{playerId}               → catálogo global de jugadores
//   • users/{uid}/playerLinks/{playerId} → relación usuario↔jugador
//
// Regla de diseño:
//   - Un Player existe como entidad reutilizable entre rondas.
//   - Un PlayerLink es la relación personal del usuario con ese jugador:
//     favorito, apodo, sliding recurrente.
//   - La app siempre trabaja con ambos juntos (PlayerWithLink).
// ─────────────────────────────────────────────────────────────────────────────
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../models/models.dart';
import 'auth_service.dart';

/// Resultado de intentar vincular un jugador por email.
enum LinkResult {
  success,          // Vinculado correctamente
  userNotFound,     // No existe ningún usuario con ese email
  alreadyLinked,    // El jugador ya tiene ese mismo linkedUserId
  alreadyUsed,      // Ese email ya está vinculado a otro jugador del directorio
  error,            // Error inesperado
}

// ── DTO: jugador + su link (puede ser null si no es compañero aún) ────────────
class PlayerWithLink {
  final Player player;
  final PlayerLink? link;

  const PlayerWithLink({required this.player, this.link});

  bool get isFavorite    => link?.isFavorite ?? false;
  bool get isInDirectory => link != null;
  int  get sortOrder     => link?.sortOrder ?? 999;

  /// Nombre a mostrar priorizando el apodo del link
  String get displayName => link?.displayName(player.name) ?? player.name;
}

class PlayerService {
  static final _db = FirebaseFirestore.instance;

  // ── Paths ──────────────────────────────────────────────────────────────────
  static CollectionReference<Map<String, dynamic>> get _players =>
      _db.collection('players');

  static CollectionReference<Map<String, dynamic>> _links() =>
      _db.collection('users').doc(AuthService.uid).collection('playerLinks');

  // ══════════════════════════════════════════════════════════════════════════════
  // LECTURA — Directorio del usuario (links + players)
  // ══════════════════════════════════════════════════════════════════════════════

  /// Stream en tiempo real del directorio completo del usuario.
  /// Combina playerLinks con sus Player globales.
  ///
  /// IMPORTANTE: linkedUserId se toma del playerLink cuando está disponible,
  /// y como fallback del player global. Esto garantiza que el stream se
  /// reactiva inmediatamente cuando se vincula un compañero por email,
  /// ya que el cambio se escribe en el playerLink (que es lo que escucha
  /// este stream) además del player global.
  static Stream<List<PlayerWithLink>> directoryStream() {
    // Si el uid todavía no está listo, esperar al primer cambio de authState
    // en lugar de devolver un stream vacío que nunca se actualiza.
    final uid = AuthService.uid;
    if (uid == null) {
      if (kDebugMode) debugPrint('directoryStream: uid null, esperando authState...');
      return FirebaseAuth.instance.authStateChanges()
          .where((u) => u != null)
          .take(1)
          .asyncExpand((_) => directoryStream());
    }

    // Capturar el uid una sola vez y usarlo directamente (evita race conditions).
    // No usamos orderBy('sortOrder') para no requerir índice en Firestore web.
    final linksCol = _db
        .collection('users')
        .doc(uid)
        .collection('playerLinks');

    return linksCol
        .snapshots()
        .asyncMap((snap) async {
      if (snap.docs.isEmpty) return <PlayerWithLink>[];

      // Leer todos los Player globales referenciados de una vez (batch)
      final ids = snap.docs.map((d) => d.id).toList();
      List<DocumentSnapshot<Map<String, dynamic>>> playerDocs;
      try {
        playerDocs = await Future.wait(
          ids.map((id) => _players.doc(id).get()),
        );
      } catch (e) {
        if (kDebugMode) debugPrint('directoryStream: error al leer players: $e');
        // Devolver lista vacía en lugar de propagar el error
        return <PlayerWithLink>[];
      }

      final results = <PlayerWithLink>[];
      for (int i = 0; i < snap.docs.length; i++) {
        final linkDoc   = snap.docs[i];
        final playerDoc = playerDocs[i];
        if (!playerDoc.exists) continue;

        // Leer linkedUserId: primero del playerLink (se actualiza junto con
        // la vinculación y dispara el stream), luego del player global.
        final linkData          = linkDoc.data();
        final linkedFromLink    = linkData['linkedUserId'] as String?;
        final linkedFromPlayer  = playerDoc.data()?['linkedUserId'] as String?;
        final resolvedLinkedUid = (linkedFromLink != null && linkedFromLink.isNotEmpty)
            ? linkedFromLink
            : linkedFromPlayer;

        var player = _playerFromDoc(playerDoc);
        // Si el player global aún no tiene linkedUserId pero el link sí,
        // usamos el del link para que la UI lo muestre inmediatamente.
        if (resolvedLinkedUid != null &&
            (player.linkedUserId == null || player.linkedUserId!.isEmpty)) {
          player = player.copyWith(linkedUserId: resolvedLinkedUid);
        }

        final link = PlayerLink.fromFirestore(linkData, linkDoc.id);
        results.add(PlayerWithLink(player: player, link: link));
      }

      // Ordenar por sortOrder en memoria (evita necesitar índice en Firestore)
      results.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return results;
    });
  }

  /// Carga puntual del directorio (sin stream).
  static Future<List<PlayerWithLink>> getDirectory() async {
    if (AuthService.uid == null) return [];
    try {
      // Sin orderBy para no requerir índice; ordenamos en memoria al final.
      final snap = await _links().get();
      if (snap.docs.isEmpty) return [];

      final ids = snap.docs.map((d) => d.id).toList();
      final playerDocs = await Future.wait(ids.map((id) => _players.doc(id).get()));

      final results = <PlayerWithLink>[];
      for (int i = 0; i < snap.docs.length; i++) {
        if (!playerDocs[i].exists) continue;

        // Aplicar la misma lógica de resolución que directoryStream():
        // leer linkedUserId del playerLink primero (ya que es lo que se actualiza
        // al vincular por email), y caer al player global si no está en el link.
        final linkData         = snap.docs[i].data();
        final linkedFromLink   = linkData['linkedUserId'] as String?;
        final linkedFromPlayer = playerDocs[i].data()?['linkedUserId'] as String?;
        final resolvedLinked   = (linkedFromLink != null && linkedFromLink.isNotEmpty)
            ? linkedFromLink
            : linkedFromPlayer;

        var player = _playerFromDoc(playerDocs[i]);
        if (resolvedLinked != null && resolvedLinked.isNotEmpty &&
            (player.linkedUserId == null || player.linkedUserId!.isEmpty)) {
          player = player.copyWith(linkedUserId: resolvedLinked);
        }

        results.add(PlayerWithLink(
          player: player,
          link:   PlayerLink.fromFirestore(linkData, snap.docs[i].id),
        ));
      }
      // Ordenar en memoria por sortOrder
      results.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return results;
    } catch (_) {
      return [];
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // ESCRITURA — Crear / actualizar jugador + link en una sola operación
  // ══════════════════════════════════════════════════════════════════════════════

  /// Crea un jugador nuevo en el catálogo global Y lo añade al directorio
  /// del usuario con los datos del link.
  static Future<PlayerWithLink> createPlayer({
    required String name,
    double handicap = 0,
    int colorIndex = 0,
    bool isFavorite = false,
    String? customDisplayName,
    double defaultSlidingAdjustment = 0,
    String? notes,
  }) async {
    if (AuthService.uid == null) throw Exception('No autenticado');

    final uid = AuthService.uid!;

    // 1. Crear Player global
    final playerRef = _players.doc();
    final now = DateTime.now();
    final player = Player(
      id: playerRef.id,
      name: name,
      handicapBase: handicap,
      colorIndex: colorIndex,
    );
    await playerRef.set({
      ...player.toJson(),
      'createdByUserId': uid,
      'isShared':        false,
      'createdAt':       now.toIso8601String(),
      'updatedAt':       now.toIso8601String(),
    });

    // 2. Contar links actuales para asignar sortOrder
    final linkCount = (await _links().count().get()).count ?? 0;

    // 3. Crear PlayerLink
    final link = PlayerLink(
      playerId:                 player.id,
      isFavorite:               isFavorite,
      customDisplayName:        customDisplayName,
      defaultSlidingAdjustment: defaultSlidingAdjustment,
      notes:                    notes,
      sortOrder:                linkCount,
      createdAt:                now,
      updatedAt:                now,
    );
    await _links().doc(player.id).set(link.toFirestore());

    return PlayerWithLink(player: player, link: link);
  }

  /// Actualiza los datos del Player global (nombre, HCP, colorIndex).
  static Future<void> updatePlayerData(Player player) async {
    await _players.doc(player.id).update({
      'name':         player.name,
      'handicapBase': player.handicapBase,
      'colorIndex':   player.colorIndex,
      'updatedAt':    DateTime.now().toIso8601String(),
    });
  }

  /// Actualiza el PlayerLink del usuario (favorito, apodo, sliding).
  static Future<void> updateLink(PlayerLink link) async {
    if (AuthService.uid == null) return;
    await _links().doc(link.playerId).set(
      link.copyWith().toFirestore(),
      SetOptions(merge: true),
    );
  }

  /// Toggle favorito
  static Future<void> toggleFavorite(String playerId, bool current) async {
    if (AuthService.uid == null) return;
    await _links().doc(playerId).update({'isFavorite': !current});
  }

  /// Añade un jugador existente al directorio del usuario (crea el link).
  static Future<void> addToDirectory(String playerId) async {
    if (AuthService.uid == null) return;
    final now = DateTime.now();
    final linkCount = (await _links().count().get()).count ?? 0;
    final link = PlayerLink(
      playerId:   playerId,
      sortOrder:  linkCount,
      createdAt:  now,
      updatedAt:  now,
    );
    await _links().doc(playerId).set(link.toFirestore());
  }

  /// Elimina el link (quita del directorio, no borra el Player global).
  static Future<void> removeFromDirectory(String playerId) async {
    if (AuthService.uid == null) return;
    await _links().doc(playerId).delete();
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // VINCULACIÓN — Enlazar un Player a la cuenta Firebase de un usuario
  // ══════════════════════════════════════════════════════════════════════════════

  /// Busca un usuario registrado por email y vincula el Player a su cuenta.
  ///
  /// Efectos:
  ///   - players/{playerId}.linkedUserId = uid encontrado
  ///   - users/{currentUid}/playerLinks/{playerId}.linkedUserId = uid encontrado
  ///
  /// El nombre del Player NO se modifica; el organizador conserva el suyo.
  static Future<(LinkResult, String?)> linkPlayerByEmail({
    required String playerId,
    required String email,
  }) async {
    if (AuthService.uid == null) return (LinkResult.error, 'No autenticado');
    try {
      final trimmed = email.trim().toLowerCase();

      // 1. Buscar el uid del usuario por email en la colección 'users'
      final query = await _db
          .collection('users')
          .where('email', isEqualTo: trimmed)
          .limit(1)
          .get();

      if (query.docs.isEmpty) return (LinkResult.userNotFound, null);

      final targetUid  = query.docs.first.id;

      // 2. Verificar que el Player no esté ya vinculado con ese mismo uid
      final playerSnap = await _players.doc(playerId).get();
      if (!playerSnap.exists) return (LinkResult.error, 'Jugador no encontrado');
      final currentLinked = playerSnap.data()?['linkedUserId'] as String?;
      if (currentLinked == targetUid) return (LinkResult.alreadyLinked, null);

      // 3. Verificar que ese uid no esté ya vinculado a otro jugador del directorio
      //    Filtramos en memoria para evitar requerir un índice compuesto en Firestore.
      final allLinks = await _links().get();
      final duplicate = allLinks.docs.any((doc) {
        final linked = doc.data()['linkedUserId'] as String?;
        return linked == targetUid && doc.id != playerId;
      });
      if (duplicate) return (LinkResult.alreadyUsed, null);

      // 4. Actualizar el Player global
      await _players.doc(playerId).update({
        'linkedUserId': targetUid,
        'updatedAt':    DateTime.now().toIso8601String(),
      });

      // 5. Actualizar el PlayerLink del usuario actual (set+merge)
      await _links().doc(playerId).set({
        'linkedUserId': targetUid,
        'updatedAt':    DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));

      // NOTA: NO escribimos en users/{targetUid} desde aquí porque las reglas
      // de Firestore solo permiten a cada usuario escribir en su propio documento.
      // El usuario objetivo (targetUid) ya tiene su propio myPlayerId asignado
      // al registrarse. Si no lo tiene, lo actualizará la próxima vez que inicie
      // sesión en su propia app.

      return (LinkResult.success, null);
    } catch (e) {
      final msg = e.toString();
      if (kDebugMode) debugPrint('[PlayerService.linkPlayerByEmail] Error: $msg');
      // Detectar errores de permisos de Firestore
      if (msg.contains('permission-denied') || msg.contains('PERMISSION_DENIED')) {
        return (LinkResult.error, 'Sin permisos. Verifica las reglas de Firestore.');
      }
      if (msg.contains('unavailable') || msg.contains('network')) {
        return (LinkResult.error, 'Sin conexión. Revisa tu internet.');
      }
      return (LinkResult.error, msg.length > 120 ? '${msg.substring(0,120)}...' : msg);
    }
  }

  /// Elimina la vinculación de un jugador (borra linkedUserId).
  static Future<void> unlinkPlayer(String playerId) async {
    if (AuthService.uid == null) return;
    try {
      await _players.doc(playerId).update({
        'linkedUserId': FieldValue.delete(),
        'updatedAt':    DateTime.now().toIso8601String(),
      });
      await _links().doc(playerId).update({
        'linkedUserId': FieldValue.delete(),
        'updatedAt':    DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  /// Devuelve el email y displayName del usuario vinculado a un Player.
  /// Retorna null si no hay vinculación o el usuario no existe.
  static Future<Map<String, String>?> getLinkedUserInfo(String linkedUserId) async {
    try {
      final snap = await _db.collection('users').doc(linkedUserId).get();
      if (!snap.exists) return null;
      final d = snap.data()!;
      return {
        'email':       d['email']       as String? ?? '',
        'displayName': d['displayName'] as String? ?? '',
      };
    } catch (_) {
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // BÚSQUEDA — Jugadores globales (para añadir al directorio)
  // ══════════════════════════════════════════════════════════════════════════════

  /// Busca jugadores del catálogo global creados por este usuario.
  /// En el futuro podría incluir jugadores compartidos (isShared: true).
  static Future<List<Player>> searchPlayers(String query) async {
    if (AuthService.uid == null) return [];
    try {
      final snap = await _players
          .where('createdByUserId', isEqualTo: AuthService.uid)
          .limit(50)
          .get();
      final q = query.toLowerCase();
      return snap.docs
          .map((d) => _playerFromDoc(d))
          .where((p) => q.isEmpty || p.name.toLowerCase().contains(q))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  static Player _playerFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Player(
      id:           doc.id,
      name:         d['name'] as String? ?? '',
      handicapBase: (d['handicapBase'] as num?)?.toDouble() ?? 0,
      colorIndex:   (d['colorIndex'] as int?) ?? 0,
      linkedUserId: d['linkedUserId'] as String?,
    );
  }
}
