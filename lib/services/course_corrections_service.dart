// ─────────────────────────────────────────────────────────────────────────────
// COURSE CORRECTIONS SERVICE
// Gestiona correcciones manuales de datos de campos de golf.
//
// Colección global: courseCorrections/{courseId}
//   - correctionVersion: int        — versión del conjunto de correcciones
//   - notes: string                 — descripción de qué se corrigió
//   - correctedCourse: {...}        — ApiCourse serializado con datos correctos
//   - updatedAt: Timestamp
//
// Caché local del usuario: users/{uid}/favoriteCourses/{courseId}
//   - appliedCorrectionVersion: int — versión que ya aplicó el usuario
//   - manuallyEdited: true          — marca para no sobreescribir con API
// ─────────────────────────────────────────────────────────────────────────────
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';
import 'golf_course_service.dart';

/// Datos de una corrección disponible para un campo.
class CourseCorrection {
  final String courseId;
  final int correctionVersion;
  final String notes;
  final ApiCourse correctedCourse;

  const CourseCorrection({
    required this.courseId,
    required this.correctionVersion,
    required this.notes,
    required this.correctedCourse,
  });
}

class CourseCorrectionsService {
  static final _db = FirebaseFirestore.instance;

  /// Colección global con correcciones oficiales.
  static CollectionReference<Map<String, dynamic>> get _corrections =>
      _db.collection('courseCorrections');

  /// Referencia al favoriteCourse del usuario actual (puede no existir).
  static DocumentReference<Map<String, dynamic>>? _favDoc(String courseId) {
    final uid = AuthService.uid;
    if (uid == null) return null;
    return _db
        .collection('users')
        .doc(uid)
        .collection('favoriteCourses')
        .doc(courseId);
  }

  // ── Obtener corrección global (sin depender de favoritos del usuario) ───────

  /// Devuelve la corrección oficial para [courseId] si existe en Firestore,
  /// independientemente de si el usuario tiene el campo como favorito.
  /// Devuelve null si no hay corrección registrada para ese campo.
  static Future<CourseCorrection?> getGlobalCorrection(String courseId) async {
    try {
      final globalSnap = await _corrections.doc(courseId).get();
      if (!globalSnap.exists) return null;

      final globalData = globalSnap.data()!;
      final globalVersion = (globalData['correctionVersion'] as num?)?.toInt() ?? 1;

      final correctedJson = globalData['correctedCourse'] as Map<String, dynamic>?;
      if (correctedJson == null) return null;

      final correctedCourse = ApiCourse.fromCached(correctedJson);
      if (correctedCourse.allTees.isEmpty) return null;

      return CourseCorrection(
        courseId: courseId,
        correctionVersion: globalVersion,
        notes: globalData['notes'] as String? ?? 'Datos del campo actualizados',
        correctedCourse: correctedCourse,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('getGlobalCorrection error: $e');
      return null;
    }
  }

  // ── Verificar si hay corrección nueva para el usuario ──────────────────────

  /// Devuelve una [CourseCorrection] si el campo [courseId] tiene una corrección
  /// oficial **más nueva** que la versión ya aplicada por el usuario.
  /// Funciona aunque el usuario NO tenga el campo como favorito.
  static Future<CourseCorrection?> checkForCorrection(String courseId) async {
    try {
      // 1. Obtener corrección global
      final globalSnap = await _corrections.doc(courseId).get();
      if (!globalSnap.exists) return null;

      final globalData = globalSnap.data()!;
      final globalVersion = (globalData['correctionVersion'] as num?)?.toInt() ?? 1;

      // 2. Obtener versión ya aplicada por el usuario (si tiene favorito)
      int appliedVersion = 0;
      final favDoc = _favDoc(courseId);
      if (favDoc != null) {
        final favSnap = await favDoc.get();
        appliedVersion = favSnap.exists
            ? (favSnap.data()?['appliedCorrectionVersion'] as num?)?.toInt() ?? 0
            : 0;
      }

      // 3. Si la corrección global es más nueva, devolver la corrección
      if (globalVersion <= appliedVersion) return null;

      // 4. Deserializar el campo corregido
      final correctedJson = globalData['correctedCourse'] as Map<String, dynamic>?;
      if (correctedJson == null) return null;

      final correctedCourse = ApiCourse.fromCached(correctedJson);
      if (correctedCourse.allTees.isEmpty) return null;

      return CourseCorrection(
        courseId: courseId,
        correctionVersion: globalVersion,
        notes: globalData['notes'] as String? ?? 'Datos del campo actualizados',
        correctedCourse: correctedCourse,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('checkForCorrection error: $e');
      return null;
    }
  }

  // ── Aplicar corrección ──────────────────────────────────────────────────────

  /// Aplica una corrección a la caché del usuario.
  /// Usa set() con merge para funcionar aunque el documento NO exista todavía.
  /// Actualiza [cachedCourse], marca [manuallyEdited=true] y guarda
  /// [appliedCorrectionVersion] para no volver a aplicarla.
  static Future<void> applyCorrection(CourseCorrection correction) async {
    final favDoc = _favDoc(correction.courseId);
    if (favDoc == null) return;

    try {
      // set() con SetOptions(merge: true) crea el documento si no existe,
      // o actualiza solo los campos especificados si ya existe.
      await favDoc.set({
        'cachedCourse':             correction.correctedCourse.toJson(),
        'manuallyEdited':           true,
        'appliedCorrectionVersion': correction.correctionVersion,
      }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) debugPrint('applyCorrection error: $e');
      rethrow;
    }
  }
}
