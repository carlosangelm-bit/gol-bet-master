// ─────────────────────────────────────────────────────────────────────────────
// GUEST INVITE SERVICE
// Gestiona los enlaces temporales de invitación para jugadores sin cuenta.
//
// Colección Firestore:
//   guestInvites/{token}  →  documento con datos del enlace
//   liveRounds/{roundId}  →  se modifica para agregar al invitado como jugador
//
// Flujo:
//   1. Admin genera enlace → createInviteLink()
//   2. Invitado abre URL   → getInviteData()
//   3. Invitado llena form → joinAsGuest()
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../providers/round_provider.dart';
import 'auth_service.dart';

// ── Resultado de joinAsGuest ──────────────────────────────────────────────────
class GuestJoinResult {
  final Round? round;
  final String? playerId;
  final String? error;
  const GuestJoinResult({this.round, this.playerId, this.error});
}

// ── Servicio ──────────────────────────────────────────────────────────────────
class GuestInviteService {
  static final _db = FirebaseFirestore.instance;
  static final _invites = _db.collection('guestInvites');
  static final _liveRounds = _db.collection('liveRounds');

  // ── Generar token único ─────────────────────────────────────────────────────
  static String _genToken() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random.secure();
    return List.generate(20, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  // ── Generar un jugador ID único ─────────────────────────────────────────────
  static String _genPlayerId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random.secure();
    return List.generate(16, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  // ────────────────────────────────────────────────────────────────────────────
  // createGuestInvite  →  recibe un Round y genera un token de invitación.
  // Usada por _InviteGuestButton en home_screen.dart.
  // Devuelve el token (String) o null si falla.
  // ────────────────────────────────────────────────────────────────────────────
  static Future<String?> createGuestInvite(Round round) async {
    try {
      final uid = AuthService.uid;
      if (uid == null) {
        debugPrint('GuestInviteService: uid es null, usuario no autenticado');
        return null;
      }

      // Verificar límite de 5 jugadores en el objeto Round local
      final realPlayers = round.players.where((p) => !p.isVirtual).toList();
      if (realPlayers.length >= 5) {
        debugPrint('GuestInviteService: ronda llena localmente (${realPlayers.length}/5)');
        return null;
      }

      // Intentar leer el documento de Firestore
      // Si no existe aún (ronda no publicada como live), publicarla ahora
      final roundDoc = await _liveRounds.doc(round.id).get();
      Map<String, dynamic> data;

      if (!roundDoc.exists) {
        debugPrint('GuestInviteService: ronda ${round.id} no está en liveRounds, publicando ahora...');
        // Publicar la ronda en Firestore con los datos actuales
        final roundJson = roundToJson(round.copyWith(isLive: true, ownerUid: uid));
        roundJson['publishedAt'] = FieldValue.serverTimestamp();
        roundJson['updatedAt']   = FieldValue.serverTimestamp();
        roundJson['isFinished']  = false;
        await _liveRounds.doc(round.id).set(roundJson);
        // Guardar ref en el directorio del owner
        await _db.collection('users').doc(uid)
            .collection('liveRoundRefs').doc(round.id).set({
          'roundId':  round.id,
          'liveCode': round.liveCode ?? '',
          'role':     'owner',
          'joinedAt': FieldValue.serverTimestamp(),
        });
        data = roundJson;
      } else {
        data = roundDoc.data()!;
        // Si está marcada como finalizada en Firestore, reactivarla
        if (data['isFinished'] == true) {
          debugPrint('GuestInviteService: ronda marcada como finished en FS, reactivando...');
          await _liveRounds.doc(round.id).update({
            'isFinished': false,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          data['isFinished'] = false;
        }
      }

      // Doble-verificar límite de 5 en Firestore
      final fsPlayers = (data['players'] as List? ?? [])
          .where((p) => (p as Map)['isVirtual'] != true)
          .toList();
      if (fsPlayers.length >= 5) {
        debugPrint('GuestInviteService: ronda llena en Firestore (${fsPlayers.length}/5)');
        return null;
      }

      // Obtener nombre del owner
      String ownerName = 'Admin';
      try {
        final userDoc = await _db.collection('users').doc(uid).get();
        if (userDoc.exists) {
          final userData = userDoc.data()!;
          ownerName = (userData['displayName'] as String?)
              ?? (userData['name'] as String?)
              ?? (userData['email'] as String?)
              ?? 'Admin';
        }
      } catch (e) {
        debugPrint('GuestInviteService: no se pudo leer nombre del owner: $e');
      }

      // Generar token y guardar en Firestore
      final token = _genToken();
      final inviteDoc = {
        'token': token,
        'roundId': round.id,
        'roundName': round.name,
        'courseName': round.course.name,
        'ownerName': ownerName,
        'ownerUid': uid,
        'scoringMode': round.scoringMode,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'guestName': null,
        'guestHcp': null,
        'guestPlayerId': null,
        'roundData': data,
      };

      await _invites.doc(token).set(inviteDoc);
      debugPrint('GuestInviteService: token creado → $token');

      // Registrar el token en el documento de la ronda
      await _liveRounds.doc(round.id).update({
        'guestInviteTokens': FieldValue.arrayUnion([token]),
      });

      return token;
    } catch (e, st) {
      debugPrint('GuestInviteService.createGuestInvite ERROR: $e\n$st');
      return null;
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // createInviteLink  →  el admin lo llama desde la pantalla de ronda activa.
  // Devuelve la URL completa del enlace.
  // ────────────────────────────────────────────────────────────────────────────
  static Future<String?> createInviteLink({
    required String roundId,
    required String roundName,
    required String courseName,
    required String ownerName,
    required String scoringMode,
  }) async {
    try {
      final uid = AuthService.uid;
      if (uid == null) return null;

      // Verificar que la ronda existe y tiene menos de 5 jugadores
      final roundDoc = await _liveRounds.doc(roundId).get();
      if (!roundDoc.exists) return null;

      final data = roundDoc.data()!;
      final players = (data['players'] as List? ?? [])
          .where((p) => (p as Map)['isVirtual'] != true)
          .toList();
      
      if (players.length >= 5) {
        return null; // Ronda llena
      }

      final token = _genToken();
      await _invites.doc(token).set({
        'token': token,
        'roundId': roundId,
        'roundName': roundName,
        'courseName': courseName,
        'ownerName': ownerName,
        'ownerUid': uid,
        'scoringMode': scoringMode,
        'status': 'pending',   // pending → used (cuando alguien se une)
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': null,     // expira al finalizar la ronda
        'guestName': null,
        'guestHcp': null,
        'guestPlayerId': null,
        // Copia del round para mostrar info en pantalla de bienvenida
        'roundData': data,
      });

      // Guardar referencia del token en el documento de la ronda
      await _liveRounds.doc(roundId).update({
        'guestInviteTokens': FieldValue.arrayUnion([token]),
      });

      // URL base: en producción usa el dominio real, en debug el sandbox
      const baseUrl = String.fromEnvironment(
        'GUEST_BASE_URL',
        defaultValue: '',
      );
      final effectiveBase = baseUrl.isNotEmpty
          ? baseUrl
          : 'https://golfbetmaster.app';

      return '$effectiveBase/guest/$token';
    } catch (e) {
      debugPrint('GuestInviteService.createInviteLink error: $e');
      return null;
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // getInviteData  →  el invitado llama al abrir el enlace.
  // Devuelve null si el enlace es inválido o la ronda terminó.
  // ────────────────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>?> getInviteData(String token) async {
    try {
      final doc = await _invites.doc(token).get();
      if (!doc.exists) return null;

      final data = doc.data()!;

      // Verificar que el enlace no esté usado o expirado
      final status = data['status'] as String? ?? 'pending';
      if (status == 'used' || status == 'expired') return null;

      // Verificar que la ronda no esté finalizada
      final roundId = data['roundId'] as String?;
      if (roundId == null) return null;

      // Intentar leer liveRounds (puede fallar si el invitado no está autenticado)
      // En ese caso, usar roundData almacenado en el propio documento guestInvites
      Map<String, dynamic> roundData = {};
      bool roundIsFinished = false;

      try {
        final roundDoc = await _liveRounds.doc(roundId).get();
        if (roundDoc.exists) {
          roundData = roundDoc.data()!;
          roundIsFinished = roundData['isFinished'] == true;
        }
      } catch (e) {
        debugPrint('GuestInviteService: no se pudo leer liveRounds (sin auth), usando roundData del invite: $e');
        // Usar los datos guardados en el documento guestInvites
        roundData = Map<String, dynamic>.from(data['roundData'] as Map? ?? {});
        // Si tenemos roundData guardado, asumir que la ronda está activa
        roundIsFinished = roundData['isFinished'] == true;
      }

      if (roundIsFinished) return null;

      // Devolver datos para la pantalla de bienvenida
      return {
        'token': token,
        'roundId': roundId,
        'roundName': data['roundName'] ?? roundData['name'] ?? 'Ronda Golf',
        'courseName': data['courseName'] ?? '',
        'ownerName': data['ownerName'] ?? 'Admin',
        'scoringMode': data['scoringMode'] ?? roundData['scoringMode'] ?? 'open',
        'roundData': roundData,
      };
    } catch (e) {
      debugPrint('GuestInviteService.getInviteData error: $e');
      return null;
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // joinAsGuest  →  el invitado envía su nombre y HCP.
  // Agrega al invitado como jugador en la ronda y marca el enlace como usado.
  // ────────────────────────────────────────────────────────────────────────────
  static Future<GuestJoinResult> joinAsGuest({
    required String token,
    required String guestName,
    required double guestHcp,
    String? guestInitials,
  }) async {
    try {
      // 0. Autenticar anónimamente si el invitado no tiene sesión
      //    Esto es necesario para que las reglas de Firestore permitan
      //    leer y escribir liveRounds al invitado.
      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) {
        debugPrint('GuestInviteService: signInAnonymously...');
        await auth.signInAnonymously();
        debugPrint('GuestInviteService: UID anónimo = ${auth.currentUser?.uid}');
      }

      // 1. Leer el enlace (guestInvites es de lectura pública)
      final inviteDoc = await _invites.doc(token).get();
      if (!inviteDoc.exists) {
        return const GuestJoinResult(error: 'Enlace no válido.');
      }
      final inviteData = inviteDoc.data()!;
      if (inviteData['status'] == 'used') {
        return const GuestJoinResult(error: 'Este enlace ya fue utilizado.');
      }
      if (inviteData['status'] == 'expired') {
        return const GuestJoinResult(error: 'Este enlace ha expirado.');
      }

      final roundId = inviteData['roundId'] as String?;
      if (roundId == null) {
        return const GuestJoinResult(error: 'Ronda no encontrada.');
      }

      // 2. Guardar el token en el documento del invitado para que las reglas
      //    de Firestore puedan verificarlo al escribir en liveRounds
      final guestUid = auth.currentUser!.uid;
      await _db.collection('guestSessions').doc(guestUid).set({
        'token': token,
        'roundId': roundId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 3. Leer la ronda actual (ahora con auth anónima funciona)
      final roundDoc = await _liveRounds.doc(roundId).get();
      if (!roundDoc.exists) {
        return const GuestJoinResult(error: 'La ronda no existe o ya terminó.');
      }
      final roundData = roundDoc.data()!;
      if (roundData['isFinished'] == true) {
        return const GuestJoinResult(error: 'Esta ronda ya ha finalizado.');
      }

      // 4. Verificar límite de 5 jugadores (contando solo los reales)
      final players = List<dynamic>.from(roundData['players'] ?? []);
      final realPlayers = players
          .where((p) => (p as Map)['isVirtual'] != true)
          .toList();
      if (realPlayers.length >= 5) {
        return const GuestJoinResult(
            error: 'La ronda ya tiene el máximo de 5 jugadores.');
      }

      // 5. Crear el nuevo jugador invitado
      final playerId = _genPlayerId();
      // Generar iniciales: usar las personalizadas si se proveen, si no las
      // primeras letras de cada palabra del nombre (máx 3 chars).
      final trimmedName = guestName.trim();
      final autoInitials = trimmedName
          .split(' ')
          .where((w) => w.isNotEmpty)
          .map((w) => w[0])
          .take(3)
          .join()
          .toUpperCase();
      final finalInitials = (guestInitials != null && guestInitials.trim().isNotEmpty)
          ? guestInitials.trim().toUpperCase()
          : autoInitials;

      final newPlayer = {
        'id': playerId,
        'name': trimmedName,          // nombre completo
        'initials': finalInitials,    // iniciales para espacios limitados
        'handicapBase': guestHcp,
        'colorIndex': realPlayers.length % 8,
        'isVirtual': false,
        'isGuest': true,
        'linkedUserId': null,
        'guestToken': token,
        'guestUid': guestUid,
      };

      // 6. Inicializar scores vacíos para el nuevo jugador
      final scores = Map<String, dynamic>.from(roundData['scores'] ?? {});
      scores[playerId] = {};

      // 6b. Agregar el invitado a TODOS los betGroups y sus módulos,
      //     para que aparezca en la tarjeta 1v1 y en los resultados.
      final rawGroups = List<dynamic>.from(roundData['betGroups'] ?? []);
      final updatedGroups = rawGroups.map((g) {
        final group = Map<String, dynamic>.from(g as Map);

        // Añadir al playerIds del grupo si no está
        final pids = List<String>.from(group['playerIds'] ?? []);
        if (!pids.contains(playerId)) pids.add(playerId);
        group['playerIds'] = pids;

        // Añadir al participantIds de cada módulo
        final rawMods = List<dynamic>.from(group['modules'] ?? []);
        group['modules'] = rawMods.map((m) {
          final mod = Map<String, dynamic>.from(m as Map);
          final mpids = List<String>.from(mod['participantIds'] ?? []);
          if (mpids.isNotEmpty && !mpids.contains(playerId)) {
            mpids.add(playerId);
          }
          mod['participantIds'] = mpids;
          return mod;
        }).toList();

        return group;
      }).toList();

      // 7. Actualizar la ronda en Firestore (batch)
      final batch = _db.batch();

      // Necesitamos sobrescribir players, scores y betGroups juntos.
      // Usamos update con los campos explícitos.
      final updatedPlayersList = List<dynamic>.from(players)..add(newPlayer);

      batch.update(_liveRounds.doc(roundId), {
        'players': updatedPlayersList,
        'scores': scores,
        'betGroups': updatedGroups,
        'guestUids': FieldValue.arrayUnion([guestUid]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.update(_invites.doc(token), {
        'status': 'used',
        'guestName': guestName.trim(),
        'guestHcp': guestHcp,
        'guestPlayerId': playerId,
        'guestUid': guestUid,
        'joinedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      // 8. Leer la ronda actualizada y parsearla
      final updatedDoc = await _liveRounds.doc(roundId).get();
      final updatedData = updatedDoc.data()!;
      updatedData['id'] = roundId;
      final round = roundFromJson(updatedData);

      return GuestJoinResult(round: round, playerId: playerId);
    } catch (e) {
      debugPrint('GuestInviteService.joinAsGuest error: $e');
      return GuestJoinResult(error: 'Error al unirse: $e');
    }
  }

  // ── Invalidar todos los enlaces de una ronda (al finalizar) ─────────────────
  static Future<void> invalidateRoundInvites(String roundId) async {
    try {
      final snap = await _invites
          .where('roundId', isEqualTo: roundId)
          .where('status', isEqualTo: 'pending')
          .get();
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'status': 'expired'});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('GuestInviteService.invalidateRoundInvites error: $e');
    }
  }

  // ── Color asignado al jugador según posición ────────────────────────────────
  static String _assignColor(int index) {
    const colors = ['#E53935', '#1E88E5', '#43A047', '#FB8C00', '#8E24AA'];
    return colors[index % colors.length];
  }
}
