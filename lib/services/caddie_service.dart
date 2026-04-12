// ─────────────────────────────────────────────────────────────────────────────
// CADDIE SERVICE
// Acceso de solo visualización para caddies — sin token de jugador.
//
// Diferencias clave vs GuestInviteService:
//   • El caddie NO se agrega como jugador a la ronda.
//   • NO consume el cupo de 5 jugadores.
//   • El token es reutilizable (multi-uso): cualquier caddie con el link entra.
//   • La ruta es /caddie/:token (distinta de /guest/:token).
//   • El acceso solo requiere auth anónima para leer liveRounds.
//
// Colección Firestore:
//   caddieTokens/{token}  →  documento con datos del enlace de visualización
//
// Flujo:
//   1. Admin genera enlace  → createCaddieLink(round)
//   2. Caddie abre la URL   → getCaddieData(token)
//   3. Caddie entra directo → no hace joinAsGuest, solo escucha liveRounds
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../providers/round_provider.dart' show roundFromJson, roundToJson;
import 'auth_service.dart';

class CaddieService {
  static final _db           = FirebaseFirestore.instance;
  static final _tokens       = _db.collection('caddieTokens');
  static final _liveRounds   = _db.collection('liveRounds');

  // ── Token alfanumérico de 20 chars ─────────────────────────────────────────
  static String _genToken() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng   = Random.secure();
    return List.generate(20, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // createCaddieLink  →  llamado por el admin desde la pantalla de ronda activa.
  // Retorna la URL completa del enlace o null si falla.
  //
  // El token es reutilizable: puede ser abierto por múltiples caddies/espectadores.
  // Al finalizar la ronda, se marca como 'expired' en invalidateCaddieToken().
  // ──────────────────────────────────────────────────────────────────────────
  static Future<String?> createCaddieLink(Round round) async {
    try {
      final uid = AuthService.uid;
      if (uid == null) return null;

      // Asegurar que la ronda esté publicada en liveRounds
      final roundDoc = await _liveRounds.doc(round.id).get();
      Map<String, dynamic> data;

      if (!roundDoc.exists) {
        // Publicar la ronda si aún no está en liveRounds
        final roundJson = roundToJson(round.copyWith(isLive: true, ownerUid: uid));
        roundJson['isFinished']  = false;
        roundJson['publishedAt'] = FieldValue.serverTimestamp();
        roundJson['updatedAt']   = FieldValue.serverTimestamp();
        await _liveRounds.doc(round.id).set(roundJson);
        data = roundJson;
      } else {
        data = roundDoc.data()!;
      }

      // Leer nombre del owner
      String ownerName = 'Admin';
      try {
        final userDoc = await _db.collection('users').doc(uid).get();
        if (userDoc.exists) {
          final d = userDoc.data()!;
          ownerName = (d['displayName'] as String?)
              ?? (d['name'] as String?)
              ?? (d['email'] as String?)
              ?? 'Admin';
        }
      } catch (_) {}

      // Generar token y guardar en caddieTokens
      final token = _genToken();
      await _tokens.doc(token).set({
        'token':      token,
        'roundId':    round.id,
        'roundName':  round.name,
        'courseName': round.course.name,
        'ownerName':  ownerName,
        'ownerUid':   uid,
        'status':     'active',      // active | expired
        'createdAt':  FieldValue.serverTimestamp(),
        'roundData':  data,          // snapshot para la pantalla de bienvenida
      });

      // Registrar token en el documento de la ronda (para invalidar al finalizar)
      await _liveRounds.doc(round.id).update({
        'caddieTokens': FieldValue.arrayUnion([token]),
        'updatedAt':    FieldValue.serverTimestamp(),
      });

      debugPrint('[CaddieService] Token caddie creado: $token');

      // Construir URL final
      final baseUrl = kIsWeb
          ? '${Uri.base.scheme}://${Uri.base.host}'
              '${(Uri.base.port != 80 && Uri.base.port != 443 && Uri.base.port != 0) ? ':${Uri.base.port}' : ''}'
          : 'https://golf-bet-master.web.app';

      return '$baseUrl/caddie/$token';
    } catch (e, st) {
      debugPrint('[CaddieService] createCaddieLink error: $e\n$st');
      return null;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // getCaddieData  →  llamado al abrir el enlace.
  // Retorna null si el token es inválido, expirado o la ronda finalizó.
  // ──────────────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>?> getCaddieData(String token) async {
    try {
      final doc = await _tokens.doc(token).get();
      if (!doc.exists) return null;

      final data   = doc.data()!;
      final status = data['status'] as String? ?? 'active';
      if (status == 'expired') return null;

      final roundId = data['roundId'] as String?;
      if (roundId == null) return null;

      // Intentar leer la ronda desde liveRounds
      Map<String, dynamic> roundData = {};
      bool roundIsFinished = false;
      try {
        final roundDoc = await _liveRounds.doc(roundId).get();
        if (roundDoc.exists) {
          roundData       = roundDoc.data()!;
          roundIsFinished = roundData['isFinished'] == true;
        }
      } catch (e) {
        // Sin auth todavía — usar snapshot guardado en caddieTokens
        debugPrint('[CaddieService] Sin acceso a liveRounds, usando snapshot: $e');
        roundData       = Map<String, dynamic>.from(data['roundData'] as Map? ?? {});
        roundIsFinished = roundData['isFinished'] == true;
      }

      if (roundIsFinished) return null;

      return {
        'token':      token,
        'roundId':    roundId,
        'roundName':  data['roundName']  ?? roundData['name']        ?? 'Ronda Golf',
        'courseName': data['courseName'] ?? '',
        'ownerName':  data['ownerName']  ?? 'Admin',
        'roundData':  roundData,
      };
    } catch (e) {
      debugPrint('[CaddieService] getCaddieData error: $e');
      return null;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // enterAsViewer  →  auth anónima y carga la ronda para lectura.
  // No modifica ningún documento de la ronda.
  // Retorna (round, error).
  // ──────────────────────────────────────────────────────────────────────────
  static Future<({Round? round, String? error})> enterAsViewer(String token) async {
    try {
      // Auth anónima si es necesaria (para Firestore rules de lectura)
      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) {
        await auth.signInAnonymously();
        debugPrint('[CaddieService] Auth anónima: ${auth.currentUser?.uid}');
      }

      // Leer token
      final doc = await _tokens.doc(token).get();
      if (!doc.exists) {
        return (round: null, error: 'Enlace no válido.');
      }
      final tokenData = doc.data()!;
      if (tokenData['status'] == 'expired') {
        return (round: null, error: 'Este enlace ha expirado o la ronda ya finalizó.');
      }

      final roundId = tokenData['roundId'] as String?;
      if (roundId == null) {
        return (round: null, error: 'Ronda no encontrada.');
      }

      // Leer la ronda (con auth anónima ya funciona)
      final roundDoc = await _liveRounds.doc(roundId).get();
      if (!roundDoc.exists) {
        return (round: null, error: 'La ronda no existe o ya terminó.');
      }
      final roundData = roundDoc.data()!;
      if (roundData['isFinished'] == true) {
        return (round: null, error: 'Esta ronda ya ha finalizado.');
      }

      roundData['id'] = roundId;
      final round = roundFromJson(roundData);
      return (round: round, error: null);
    } catch (e) {
      debugPrint('[CaddieService] enterAsViewer error: $e');
      return (round: null, error: 'Error al conectar: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // invalidateCaddieTokens  →  marca como 'expired' todos los tokens de una ronda.
  // Llamar al finalizar la ronda (junto con invalidateRoundInvites).
  // ──────────────────────────────────────────────────────────────────────────
  static Future<void> invalidateCaddieTokens(String roundId) async {
    try {
      final snap = await _tokens
          .where('roundId', isEqualTo: roundId)
          .where('status', isEqualTo: 'active')
          .get();
      if (snap.docs.isEmpty) return;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'status': 'expired'});
      }
      await batch.commit();
      debugPrint('[CaddieService] ${snap.docs.length} token(s) de caddie invalidados para ronda $roundId');
    } catch (e) {
      debugPrint('[CaddieService] invalidateCaddieTokens error: $e');
    }
  }
}
