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
  static Stream<List<PlayerWithLink>> directoryStream() {
    if (AuthService.uid == null) return Stream.value([]);

    return _links()
        .orderBy('sortOrder')
        .snapshots()
        .asyncMap((snap) async {
      if (snap.docs.isEmpty) return <PlayerWithLink>[];

      // Leer todos los Player globales referenciados de una vez (batch)
      final ids = snap.docs.map((d) => d.id).toList();
      final playerDocs = await Future.wait(
        ids.map((id) => _players.doc(id).get()),
      );

      final results = <PlayerWithLink>[];
      for (int i = 0; i < snap.docs.length; i++) {
        final linkDoc   = snap.docs[i];
        final playerDoc = playerDocs[i];
        if (!playerDoc.exists) continue;

        final player = _playerFromDoc(playerDoc);
        final link   = PlayerLink.fromFirestore(linkDoc.data(), linkDoc.id);
        results.add(PlayerWithLink(player: player, link: link));
      }
      return results;
    });
  }

  /// Carga puntual del directorio (sin stream).
  static Future<List<PlayerWithLink>> getDirectory() async {
    if (AuthService.uid == null) return [];
    try {
      final snap = await _links().orderBy('sortOrder').get();
      if (snap.docs.isEmpty) return [];

      final ids = snap.docs.map((d) => d.id).toList();
      final playerDocs = await Future.wait(ids.map((id) => _players.doc(id).get()));

      final results = <PlayerWithLink>[];
      for (int i = 0; i < snap.docs.length; i++) {
        if (!playerDocs[i].exists) continue;
        results.add(PlayerWithLink(
          player: _playerFromDoc(playerDocs[i]),
          link:   PlayerLink.fromFirestore(snap.docs[i].data(), snap.docs[i].id),
        ));
      }
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
      final targetData = query.docs.first.data();

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

      // 5. Actualizar el PlayerLink del usuario actual (set+merge por si no tiene el campo)
      await _links().doc(playerId).set({
        'linkedUserId': targetUid,
        'updatedAt':    DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));

      // 6. Si el usuario objetivo aún no tiene myPlayerId, asignarlo.
      //    Usamos set+merge para que no falle si el documento no tiene ese campo.
      final targetMyPlayerId = targetData['myPlayerId'] as String?;
      if (targetMyPlayerId == null || targetMyPlayerId.isEmpty) {
        await _db.collection('users').doc(targetUid).set({
          'myPlayerId': playerId,
          'updatedAt':  FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        // Crear PlayerLink en el directorio del usuario objetivo
        final now = DateTime.now();
        await _db
            .collection('users').doc(targetUid)
            .collection('playerLinks').doc(playerId)
            .set({
          'playerId':                 playerId,
          'isFavorite':               false,
          'defaultSlidingAdjustment': 0.0,
          'sortOrder':                0,
          'linkedUserId':             targetUid,
          'createdAt':                now.toIso8601String(),
          'updatedAt':                now.toIso8601String(),
        }, SetOptions(merge: true));
      }

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
