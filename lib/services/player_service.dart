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
    /// Id propio, para cuando el jugador YA existe en una ronda en curso.
    ///
    /// El asistente crea el jugador local con un uuid y lo mete en la ronda al
    /// instante —tiene que funcionar sin conexión—. Si luego se guarda en el
    /// directorio con OTRO id, la misma persona sale dos veces y su historial se
    /// parte en dos. Con el id de la ronda, la ficha del directorio y lo que se
    /// jugó son la misma persona.
    String? id,
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
    final playerRef = id == null ? _players.doc() : _players.doc(id);
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

  /// Retorna un mapa de playerId → PlayerLink para el usuario dado.
  /// Útil para calcular sugerencias de sliding al finalizar ronda.
  static Future<Map<String, PlayerLink>> getLinksForUser(String uid) async {
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('playerLinks')
        .get();
    final result = <String, PlayerLink>{};
    for (final doc in snap.docs) {
      try {
        result[doc.id] = PlayerLink.fromFirestore(doc.data(), doc.id);
      } catch (_) {}
    }
    return result;
  }

  /// Retorna el PlayerLink existente para [playerId] o crea uno por defecto.
  static Future<PlayerLink> getLinkOrDefault(String playerId) async {
    final uid = AuthService.uid;
    if (uid == null) {
      return PlayerLink(
        playerId:  playerId,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('playerLinks')
        .doc(playerId)
        .get();
    if (doc.exists && doc.data() != null) {
      return PlayerLink.fromFirestore(doc.data()!, doc.id);
    }
    return PlayerLink(
      playerId:  playerId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
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

      // 1. Buscar el uid del usuario en la colección pública /userLookup/{email}
      //    Esta colección evita hacer queries sobre /users (que requieren permisos
      //    de leer datos de otros usuarios). Cada usuario registra su email aquí.
      final lookupDoc = await _db
          .collection('userLookup')
          .doc(trimmed)
          .get();

      if (!lookupDoc.exists) return (LinkResult.userNotFound, null);

      final targetUid = lookupDoc.data()?['uid'] as String?;
      if (targetUid == null || targetUid.isEmpty) return (LinkResult.userNotFound, null);

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

  /// Las fichas GLOBALES de [ids], para los inscritos que esta cuenta no tiene
  /// vinculados.
  ///
  /// ── El fallo que esto arregla ─────────────────────────────────────────────
  ///
  /// El directorio de una cuenta es `users/{uid}/playerLinks`: sus VÍNCULOS al
  /// catálogo global. Un inscrito puede tener ficha en el catálogo sin que esta
  /// cuenta la haya vinculado —pasa cuando el torneo se llena con gente de otras
  /// cuentas—, y entonces «no encontrada» era «no vinculada»: la ficha existe, y
  /// la regla de `players` permite pedirla —`allow get`, y la app siempre pide
  /// por id—. Es exactamente para esto.
  ///
  /// ── Lo que esto NO arregló, medido ────────────────────────────────────────
  ///
  /// Se escribió para los 47 de Copa CGM 2026 que salían como «Ficha no
  /// encontrada», y la sonda contra producción dijo que resuelve a CERO de
  /// ellos: sus ids son UUID creados en el aparato y nunca pasaron por
  /// `players`. Los 28 que se arreglaron salen de `RoundResult.playerNames`,
  /// en [OrigenDeLaFicha.rondas].
  ///
  /// Se queda porque el caso que cubre es real y distinto —una ficha ajena, que
  /// el directorio no tiene y el catálogo sí— y porque ahora solo se le pregunta
  /// por los ids que ninguna ronda resolvió: nueve en ese torneo, no cuarenta y
  /// siete.
  ///
  /// ── Y NO se vincula al leerla ─────────────────────────────────────────────
  ///
  /// Leer para enseñar un nombre no puede meter cuarenta y siete personas en el
  /// directorio de nadie. Vincular es una decisión, y se ofrece aparte.
  ///
  /// Los ids que no existan se omiten: un inscrito cuya ficha se borró de
  /// verdad sigue siendo un huérfano, y hay que poder decirlo.
  /// Devuelve la ficha y SI ES DE ESTA CUENTA.
  ///
  /// La propiedad va aparte y no dentro de `Player` a propósito: es un hecho del
  /// almacén —quién creó el documento— y no un atributo de la persona. Metido en
  /// el modelo viajaría a sitios donde no significa nada.
  ///
  /// Importa porque la regla de `players` deja modificar al CREADOR: el handicap
  /// de una ficha ajena se puede ver y no tocar, y la pantalla tiene que decirlo
  /// en vez de ofrecer un campo que va a fallar al guardar.
  static Future<Map<String, ({Player ficha, bool mia})>> fichasGlobales(
      Iterable<String> ids) async {
    final uid = AuthService.uid;
    if (uid == null || ids.isEmpty) return const {};
    final unicos = ids.toSet().toList();
    try {
      final docs =
          await Future.wait(unicos.map((id) => _players.doc(id).get()));
      final out = <String, ({Player ficha, bool mia})>{};
      for (final d in docs) {
        if (!d.exists) continue;
        final creador = d.data()?['createdByUserId'] as String?;
        out[d.id] = (
          ficha: _playerFromDoc(d),
          // Sin creador es de las viejas: la regla las deja editar a cualquiera,
          // así que decir que no se puede sería mentir en el otro sentido.
          mia: creador == null || creador == uid,
        );
      }
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('fichasGlobales: $e');
      // Vacío, no a medias: media resolución dejaría unas filas con nombre y
      // otras sin él, y eso se lee como que a esas les pasa algo distinto.
      return const {};
    }
  }

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

  // ── Métodos para ajuste bilateral de sliding ───────────────────────────────

  /// Lee el PlayerLink que [uid] tiene hacia [playerId].
  /// Retorna null si no existe ese link (el oponente no tiene al usuario en su directorio).
  static Future<PlayerLink?> getLinkForUserAndPlayer({
    required String uid,
    required String playerId,
  }) async {
    try {
      final doc = await _db
          .collection('users')
          .doc(uid)
          .collection('playerLinks')
          .doc(playerId)
          .get();
      if (!doc.exists || doc.data() == null) return null;
      return PlayerLink.fromFirestore(doc.data()!, doc.id);
    } catch (_) {
      return null;
    }
  }

  /// Actualiza el PlayerLink de [uid] hacia el jugador del link con merge.
  static Future<void> updateLinkForUser({
    required String uid,
    required PlayerLink link,
  }) async {
    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('playerLinks')
          .doc(link.playerId)
          .set(link.toFirestore(), SetOptions(merge: true));
    } catch (_) {}
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
