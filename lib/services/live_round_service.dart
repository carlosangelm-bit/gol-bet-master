// ─────────────────────────────────────────────────────────────────────────────
// LIVE ROUND SERVICE — Rondas en vivo compartidas en tiempo real
//
// Estructura Firestore:
//   liveRounds/{roundId}                   → documento de la ronda compartida
//   liveRounds/{roundId}/invitations/{uid} → invitación por usuario
//   users/{uid}/liveRoundRefs/{roundId}    → referencia rápida para buscar inv.
//
// Convención:
//   • El organizador escribe la ronda completa en liveRounds/{id}
//   • Cada jugador invitado tiene un doc en liveRounds/{id}/invitations/{uid}
//   • Cuando un jugador acepta, su app escucha liveRounds/{id} en tiempo real
//   • Cualquier escritura de score va a liveRounds/{id} (merge)
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../providers/round_provider.dart' show roundToJson, roundFromJson;
import 'auth_service.dart';

// ── Modelo de invitación ──────────────────────────────────────────────────────
class LiveRoundInvitation {
  final String roundId;
  final String roundName;
  final String liveCode;
  final String ownerUid;
  final String ownerName;
  final List<String> playerNames;
  final String courseName;
  final DateTime createdAt;
  final InvitationStatus status;
  // ID del Player dentro de la ronda que corresponde a este usuario
  final String? myPlayerId;

  const LiveRoundInvitation({
    required this.roundId,
    required this.roundName,
    required this.liveCode,
    required this.ownerUid,
    required this.ownerName,
    required this.playerNames,
    required this.courseName,
    required this.createdAt,
    required this.status,
    this.myPlayerId,
  });

  bool get isPending  => status == InvitationStatus.pending;
  bool get isAccepted => status == InvitationStatus.accepted;

  factory LiveRoundInvitation.fromFirestore(Map<String, dynamic> d, String roundId) {
    return LiveRoundInvitation(
      roundId:     roundId,
      roundName:   d['roundName']   as String? ?? 'Ronda',
      liveCode:    d['liveCode']    as String? ?? '',
      ownerUid:    d['ownerUid']    as String? ?? '',
      ownerName:   d['ownerName']   as String? ?? 'Organizador',
      playerNames: List<String>.from(d['playerNames'] as List? ?? []),
      courseName:  d['courseName']  as String? ?? '',
      createdAt:   (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status:      InvitationStatus.values.firstWhere(
        (s) => s.name == (d['status'] as String? ?? 'pending'),
        orElse: () => InvitationStatus.pending,
      ),
      myPlayerId: d['myPlayerId'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'roundName':   roundName,
    'liveCode':    liveCode,
    'ownerUid':    ownerUid,
    'ownerName':   ownerName,
    'playerNames': playerNames,
    'courseName':  courseName,
    'createdAt':   FieldValue.serverTimestamp(),
    'status':      status.name,
    'role':        'invited',   // siempre incluir role para que los queries funcionen
    if (myPlayerId != null) 'myPlayerId': myPlayerId,
  };
}

enum InvitationStatus { pending, accepted, declined }

// ── Servicio principal ────────────────────────────────────────────────────────
class LiveRoundService {
  static final _db = FirebaseFirestore.instance;

  // ── Paths ──────────────────────────────────────────────────────────────────
  static CollectionReference<Map<String, dynamic>> get _liveRounds =>
      _db.collection('liveRounds');

  static CollectionReference<Map<String, dynamic>> _invitations(String roundId) =>
      _liveRounds.doc(roundId).collection('invitations');

  static CollectionReference<Map<String, dynamic>> _myRefs() =>
      _db.collection('users').doc(AuthService.uid).collection('liveRoundRefs');

  // ── Generar código de 6 chars (letras+números, legible) ───────────────────
  static String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // sin 0,O,1,I
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CREAR / PUBLICAR RONDA EN VIVO
  // ══════════════════════════════════════════════════════════════════════════

  /// Publica una ronda en liveRounds y envía invitaciones a los jugadores
  /// que tienen linkedUserId. Retorna la ronda actualizada con isLive=true.
  static Future<Round> publishRound(Round round) async {
    final uid = AuthService.uid;
    if (uid == null) throw Exception('No autenticado');

    final code = _generateCode();
    final liveRound = round.copyWith(
      isLive: true,
      ownerUid: uid,
      liveCode: code,
    );

    // 1. Guardar ronda en colección compartida
    final data = roundToJson(liveRound);
    data['publishedAt'] = FieldValue.serverTimestamp();
    data['updatedAt']   = FieldValue.serverTimestamp();
    await _liveRounds.doc(round.id).set(data);

    // 2. Guardar referencia en el directorio del organizador
    await _myRefs().doc(round.id).set({
      'roundId':  round.id,
      'liveCode': code,
      'role':     'owner',
      'joinedAt': FieldValue.serverTimestamp(),
    });

    // 3. Enviar invitaciones a los jugadores con linkedUserId
    final ownerName = AuthService.currentUser?.displayName ?? 'Organizador';
    final playerNames = round.players.map((p) => p.name).toList();
    final batch = _db.batch();

    for (final player in round.players) {
      if (player.hasLinkedAccount && player.linkedUserId != uid) {
        final invitedUid = player.linkedUserId!;

        // Doc en liveRounds/{id}/invitations/{uid}
        final invRef = _invitations(round.id).doc(invitedUid);
        batch.set(invRef, LiveRoundInvitation(
          roundId:     round.id,
          roundName:   round.name,
          liveCode:    code,
          ownerUid:    uid,
          ownerName:   ownerName,
          playerNames: playerNames,
          courseName:  round.course.name,
          createdAt:   DateTime.now(),
          status:      InvitationStatus.pending,
          myPlayerId:  player.id,
        ).toFirestore());

        // Ref rápida en users/{uid}/liveRoundRefs/{roundId}
        final refDoc = _db.collection('users').doc(invitedUid)
            .collection('liveRoundRefs').doc(round.id);
        batch.set(refDoc, {
          'roundId':     round.id,
          'liveCode':    code,
          'role':        'invited',
          'status':      'pending',
          'myPlayerId':  player.id,
          'invitedAt':   FieldValue.serverTimestamp(),
        });
      }
    }

    await batch.commit();
    if (kDebugMode) debugPrint('[LiveRound] Ronda publicada: ${round.id} ($code)');
    return liveRound;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // INVITACIONES — Lectura y acciones
  // ══════════════════════════════════════════════════════════════════════════

  /// Stream de invitaciones pendientes para el usuario actual
  static Stream<List<LiveRoundInvitation>> pendingInvitationsStream() {
    final uid = AuthService.uid;
    if (uid == null) return Stream.value([]);

    return _db.collection('users').doc(uid)
        .collection('liveRoundRefs')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .asyncMap((snap) async {
      if (snap.docs.isEmpty) return <LiveRoundInvitation>[];

      final invitations = <LiveRoundInvitation>[];
      for (final ref in snap.docs) {
        try {
          final roundId = ref.data()['roundId'] as String? ?? ref.id;
          final invDoc = await _invitations(roundId).doc(uid).get();
          if (invDoc.exists && invDoc.data() != null) {
            invitations.add(LiveRoundInvitation.fromFirestore(
              invDoc.data()!, roundId,
            ));
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[LiveRound] Error leyendo inv: $e');
        }
      }
      return invitations;
    });
  }

  /// Carga la ronda en vivo activa donde el usuario es el organizador.
  /// Revisa users/{uid}/liveRoundRefs con role='owner' y carga desde liveRounds.
  static Future<Round?> loadOwnerActiveLiveRound() async {
    final uid = AuthService.uid;
    if (uid == null) return null;
    try {
      final refs = await _myRefs()
          .where('role', isEqualTo: 'owner')
          .limit(5)
          .get();
      if (refs.docs.isEmpty) return null;

      // Buscar la primera ronda no finalizada
      for (final ref in refs.docs) {
        final roundId = ref.data()['roundId'] as String? ?? ref.id;
        final snap = await _liveRounds.doc(roundId).get();
        if (!snap.exists || snap.data() == null) continue;
        final data = snap.data()!;
        final isFinished = data['isFinished'] as bool? ?? false;
        if (!isFinished) {
          try {
            return roundFromJson(data);
          } catch (e) {
            if (kDebugMode) debugPrint('[LiveRound] Error parseando ronda del dueño: $e');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[LiveRound] Error buscando ronda del dueño: $e');
    }
    return null;
  }

  /// Carga la ronda en vivo activa donde el usuario es invitado con status='accepted'.
  /// Revisa users/{uid}/liveRoundRefs con role='invited' y status='accepted'.
  static Future<Round?> loadAcceptedLiveRound() async {
    final uid = AuthService.uid;
    if (uid == null) return null;
    try {
      // Query con dos filtros — si Firestore requiere índice, usamos fallback
      QuerySnapshot<Map<String, dynamic>> refs;
      try {
        refs = await _myRefs()
            .where('role', isEqualTo: 'invited')
            .where('status', isEqualTo: 'accepted')
            .limit(5)
            .get();
      } catch (_) {
        // Fallback: filtrar solo por role y verificar status en memoria
        final all = await _myRefs()
            .where('role', isEqualTo: 'invited')
            .limit(10)
            .get();
        final filtered = all.docs
            .where((d) => (d.data()['status'] as String?) == 'accepted')
            .toList();
        // Procesar docs filtrados directamente
        for (final ref in filtered) {
          final roundId = ref.data()['roundId'] as String? ?? ref.id;
          final snap = await _liveRounds.doc(roundId).get();
          if (!snap.exists || snap.data() == null) continue;
          final data = snap.data()!;
          final isFinished = data['isFinished'] as bool? ?? false;
          if (!isFinished) {
            try {
              return roundFromJson(data);
            } catch (e) {
              if (kDebugMode) debugPrint('[LiveRound] Error parseando ronda del invitado: $e');
            }
          }
        }
        return null;
      }

      if (refs.docs.isEmpty) return null;

      // Buscar la primera ronda no finalizada
      for (final ref in refs.docs) {
        final roundId = ref.data()['roundId'] as String? ?? ref.id;
        final snap = await _liveRounds.doc(roundId).get();
        if (!snap.exists || snap.data() == null) continue;
        final data = snap.data()!;
        final isFinished = data['isFinished'] as bool? ?? false;
        if (!isFinished) {
          try {
            return roundFromJson(data);
          } catch (e, st) {
            // Loguear siempre (no solo en debug) para diagnosticar errores de producción
            debugPrint('[LiveRound] Error parseando ronda del invitado: $e');
            debugPrint('[LiveRound] StackTrace: $st');
          }
        }
      }
    } catch (e, st) {
      debugPrint('[LiveRound] Error buscando ronda aceptada del invitado: $e');
      debugPrint('[LiveRound] StackTrace: $st');
    }
    return null;
  }

  /// Acepta una invitación: actualiza status y retorna la ronda cargada
  static Future<Round?> acceptInvitation(LiveRoundInvitation inv) async {
    final uid = AuthService.uid;
    if (uid == null) return null;

    // 1. Actualizar status (con manejo de errores individual para no bloquear el flujo)
    try {
      await _invitations(inv.roundId).doc(uid).update({'status': 'accepted'});
    } catch (e) {
      if (kDebugMode) debugPrint('[LiveRound] Error actualizando invitation status: $e');
      // No bloqueamos: el usuario puede unirse aunque falle el update del status
    }
    try {
      await _myRefs().doc(inv.roundId).update({
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[LiveRound] Error actualizando liveRoundRef status: $e');
    }

    // 2. Cargar la ronda desde liveRounds
    try {
      final snap = await _liveRounds.doc(inv.roundId).get();
      if (!snap.exists || snap.data() == null) {
        if (kDebugMode) debugPrint('[LiveRound] Documento de ronda no encontrado: ${inv.roundId}');
        return null;
      }
      return roundFromJson(snap.data()!);
    } catch (e, st) {
      debugPrint('[LiveRound] Error cargando/parseando ronda en acceptInvitation: $e');
      debugPrint('[LiveRound] StackTrace: $st');
      return null;
    }
  }

  /// Rechaza una invitación
  static Future<void> declineInvitation(LiveRoundInvitation inv) async {
    final uid = AuthService.uid;
    if (uid == null) return;
    await Future.wait([
      _invitations(inv.roundId).doc(uid).update({'status': 'declined'}),
      _myRefs().doc(inv.roundId).update({'status': 'declined'}),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STREAM EN TIEMPO REAL — Escuchar cambios de la ronda
  // ══════════════════════════════════════════════════════════════════════════

  /// Stream de la ronda en vivo (actualización en tiempo real para todos)
  static Stream<Round?> liveRoundStream(String roundId) {
    return _liveRounds.doc(roundId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      try {
        return roundFromJson(snap.data()!);
      } catch (e) {
        if (kDebugMode) debugPrint('[LiveRound] Error parseando stream: $e');
        return null;
      }
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ESCRITURA — Actualizar score en ronda en vivo
  // ══════════════════════════════════════════════════════════════════════════

  /// Persiste la ronda completa en liveRounds (merge para no pisar otros campos)
  static Future<void> saveRound(Round round) async {
    if (!round.isLive) return;
    final data = roundToJson(round);
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _liveRounds.doc(round.id).set(data, SetOptions(merge: false));
  }

  /// Finaliza la ronda en vivo: marca isFinished y limpia refs
  static Future<void> finishLiveRound(String roundId) async {
    await _liveRounds.doc(roundId).update({
      'isFinished':  true,
      'finishedAt':  FieldValue.serverTimestamp(),
      'updatedAt':   FieldValue.serverTimestamp(),
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BÚSQUEDA DE USUARIO — Para vincular jugador a cuenta
  // ══════════════════════════════════════════════════════════════════════════

  /// Busca usuarios por email para vincular jugador a cuenta
  static Future<List<Map<String, dynamic>>> searchUsersByEmail(String email) async {
    if (email.length < 3) return [];
    try {
      final snap = await _db.collection('users')
          .where('email', isEqualTo: email.toLowerCase().trim())
          .limit(5)
          .get();
      return snap.docs.map((d) => {'uid': d.id, ...d.data()}).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[LiveRound] searchUsers error: $e');
      return [];
    }
  }

  /// Busca usuarios por displayName (búsqueda parcial, hasta 10 resultados)
  static Future<List<Map<String, dynamic>>> searchUsersByName(String query) async {
    if (query.length < 2) return [];
    try {
      // Firestore no tiene full-text search; usamos prefix match
      final q = query.trim();
      final snap = await _db.collection('users')
          .where('displayName', isGreaterThanOrEqualTo: q)
          .where('displayName', isLessThan: '${q}z')
          .limit(10)
          .get();
      return snap.docs.map((d) => {'uid': d.id, ...d.data()}).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[LiveRound] searchByName error: $e');
      return [];
    }
  }

  /// Vincula un Player del directorio a un UID de usuario
  /// Actualiza players/{playerId} y users/{uid}/playerLinks/{playerId}
  static Future<void> linkPlayerToUser({
    required String playerId,
    required String targetUid,
  }) async {
    final uid = AuthService.uid;
    if (uid == null) return;
    await Future.wait([
      // Actualizar el Player global
      _db.collection('players').doc(playerId).update({
        'linkedUserId': targetUid,
        'updatedAt': DateTime.now().toIso8601String(),
      }),
      // Actualizar el link del usuario actual
      _db.collection('users').doc(uid)
          .collection('playerLinks').doc(playerId)
          .update({'linkedUserId': targetUid}),
    ]);
  }
}
