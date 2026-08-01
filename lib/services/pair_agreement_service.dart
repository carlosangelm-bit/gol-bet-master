// ─────────────────────────────────────────────────────────────────────────────
// PAIR AGREEMENT SERVICE
//
// Persiste los acuerdos de apuesta entre parejas de jugadores:
//   users/{uid}/pairAgreements/{pairKey}  →  PairAgreement
//
// El doc id ES la pairKey canónica, así que el propio Firestore garantiza que
// no puedan existir dos versiones del acuerdo entre los mismos dos jugadores.
//
// Vive bajo el uid del usuario, no en un documento compartido: no hay autoridad
// común sobre lo que dos terceros acordaron entre sí. Ver la nota de diseño en
// [PairAgreement].
//
// La lógica de resolución (instanciar, comparar) está en PairAgreementEngine;
// aquí solo hay entrada y salida de datos.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

import '../models/models.dart';
import 'auth_service.dart';

class PairAgreementService {
  static final _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>>? _col() {
    final uid = AuthService.uid;
    if (uid == null) return null;
    return _db.collection('users').doc(uid).collection('pairAgreements');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LECTURA
  // ══════════════════════════════════════════════════════════════════════════

  /// Todos los acuerdos del usuario, indexados por pairKey.
  ///
  /// Devuelve mapa vacío si no hay sesión o si falla la lectura: sin acuerdos
  /// la app sigue funcionando como antes —configurando a mano— así que un fallo
  /// aquí no debe impedir crear la ronda.
  static Future<Map<String, PairAgreement>> getAll() async {
    final col = _col();
    if (col == null) return {};
    try {
      final snap = await col.get();
      final result = <String, PairAgreement>{};
      for (final doc in snap.docs) {
        try {
          final a = PairAgreement.fromFirestore(doc.data(), doc.id);
          if (a != null && !a.isEmpty) result[a.pairKey] = a;
        } catch (_) {
          continue; // un acuerdo corrupto no invalida los demás
        }
      }
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('[PairAgreementService.getAll] $e');
      return {};
    }
  }

  /// Solo los acuerdos de las parejas formables entre [playerIds].
  ///
  /// Firestore no permite leer por id con más de 30 valores en un `whereIn`, y
  /// el número de parejas crece cuadráticamente, así que se lee todo y se filtra
  /// en cliente. El volumen es pequeño: son los compañeros habituales de una
  /// persona, no un catálogo.
  static Future<Map<String, PairAgreement>> getForPlayers(
      List<String> playerIds) async {
    if (playerIds.length < 2) return {};
    final wanted = _pairKeysAmong(playerIds);
    if (wanted.isEmpty) return {};
    final all = await getAll();
    return {
      for (final k in wanted)
        if (all[k] != null) k: all[k]!,
    };
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ESCRITURA
  // ══════════════════════════════════════════════════════════════════════════

  /// Guarda (o reemplaza) el acuerdo de una pareja.
  ///
  /// [templates] se persiste tal cual: son plantillas, así que los ids y
  /// participantes que traigan dentro son irrelevantes —[PairAgreement]
  /// los sobrescribe al instanciar.
  ///
  /// Una lista vacía BORRA el acuerdo, que es lo que el usuario espera al
  /// quitar todas las apuestas de una pareja.
  static Future<void> save({
    required String p1Id,
    required String p2Id,
    required List<BetModuleInstance> templates,
  }) async {
    final col = _col();
    if (col == null) return;
    if (p1Id.isEmpty || p2Id.isEmpty || p1Id == p2Id) return;

    final key = BetModuleInstance.pairKey(p1Id, p2Id);
    try {
      if (templates.isEmpty) {
        await col.doc(key).delete();
        return;
      }
      final now = DateTime.now();
      final agreement = PairAgreement.forPair(
        playerAId: p1Id,
        playerBId: p2Id,
        templates: templates,
        createdAt: now,
        updatedAt: now,
      );
      // merge:false a propósito — el acuerdo se reemplaza completo. Con merge
      // quedarían plantillas viejas mezcladas con las nuevas.
      await col.doc(key).set(agreement.toFirestore());
    } catch (e) {
      if (kDebugMode) debugPrint('[PairAgreementService.save] $e');
    }
  }

  /// Borra el acuerdo de una pareja.
  static Future<void> remove(String p1Id, String p2Id) =>
      save(p1Id: p1Id, p2Id: p2Id, templates: const []);

  /// Guarda varios acuerdos en una sola operación atómica.
  /// Se usa al confirmar el diálogo de "¿guardar estos acuerdos?": o entran
  /// todos o no entra ninguno, para no dejar la mitad recordada.
  ///
  /// Un acuerdo sin plantillas borra su documento.
  static Future<void> saveAll(List<PairAgreement> agreements) async {
    final col = _col();
    if (col == null || agreements.isEmpty) return;
    try {
      final batch = _db.batch();
      for (final a in agreements) {
        final doc = col.doc(a.pairKey);
        if (a.isEmpty) {
          batch.delete(doc);
        } else {
          batch.set(doc, a.toFirestore());
        }
      }
      await batch.commit();
    } catch (e) {
      if (kDebugMode) debugPrint('[PairAgreementService.saveAll] $e');
    }
  }

  // Duplica PairAgreementEngine.pairKeysAmong a propósito: importar el engine
  // aquí acoplaría la capa de datos a la de lógica por una función de 6 líneas.
  static List<String> _pairKeysAmong(List<String> playerIds) {
    final ids = playerIds.where((id) => id.isNotEmpty).toSet().toList()..sort();
    final keys = <String>[];
    for (var i = 0; i < ids.length; i++) {
      for (var k = i + 1; k < ids.length; k++) {
        keys.add(BetModuleInstance.pairKey(ids[i], ids[k]));
      }
    }
    return keys;
  }
}
