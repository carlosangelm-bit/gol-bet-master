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

  /// Referencia al favoriteCourse del usuario actual.
  static DocumentReference<Map<String, dynamic>>? _favDoc(String courseId) {
    final uid = AuthService.uid;
    if (uid == null) return null;
    return _db
        .collection('users')
        .doc(uid)
        .collection('favoriteCourses')
        .doc(courseId);
  }

  // ── Verificar si hay corrección disponible ──────────────────────────────────

  /// Devuelve una [CourseCorrection] si el campo [courseId] tiene una corrección
  /// oficial **más nueva** que la versión ya aplicada por el usuario.
  /// Devuelve null si no hay corrección disponible o ya está actualizado.
  static Future<CourseCorrection?> checkForCorrection(String courseId) async {
    try {
      // 1. Obtener corrección global
      final globalSnap = await _corrections.doc(courseId).get();
      if (!globalSnap.exists) return null;

      final globalData = globalSnap.data()!;
      final globalVersion = (globalData['correctionVersion'] as num?)?.toInt() ?? 1;

      // 2. Obtener versión ya aplicada por el usuario
      final favDoc = _favDoc(courseId);
      if (favDoc == null) return null;

      final favSnap = await favDoc.get();
      final appliedVersion = favSnap.exists
          ? (favSnap.data()?['appliedCorrectionVersion'] as num?)?.toInt() ?? 0
          : 0;

      // 3. Si la corrección global es más nueva, devolver la corrección
      if (globalVersion <= appliedVersion) return null;

      // 4. Deserializar el campo corregido
      final correctedJson = globalData['correctedCourse'] as Map<String, dynamic>?;
      if (correctedJson == null) return null;

      final correctedCourse = ApiCourse.fromCached(correctedJson);
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
  /// Actualiza [cachedCourse], marca [manuallyEdited=true] y guarda
  /// [appliedCorrectionVersion] para no volver a mostrar el aviso.
  static Future<void> applyCorrection(CourseCorrection correction) async {
    final favDoc = _favDoc(correction.courseId);
    if (favDoc == null) return;

    try {
      await favDoc.update({
        'cachedCourse':               correction.correctedCourse.toJson(),
        'manuallyEdited':             true,
        'appliedCorrectionVersion':   correction.correctionVersion,
      });
    } catch (e) {
      if (kDebugMode) debugPrint('applyCorrection error: $e');
      rethrow;
    }
  }
}
