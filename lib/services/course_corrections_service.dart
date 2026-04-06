// ─────────────────────────────────────────────────────────────────────────────
// COURSE CORRECTIONS SERVICE
//
// Diseño correcto: la corrección vive en el CAMPO, no en el usuario.
//
// Colección global: courseCorrections/{courseId}
//   - correctionVersion: int        — versión de la corrección
//   - notes: string                 — qué se corrigió y por qué
//   - correctedCourse: {...}        — ApiCourse serializado con datos correctos
//   - updatedAt: Timestamp
//
// CUALQUIER usuario que seleccione ese campo recibe los datos corregidos
// automáticamente, sin necesitar ser favorito ni tener nada guardado
// en su perfil.
//
// El favorito del usuario (favoriteCourses/{courseId}) guarda SOLO
// preferencias personales: preferredTeeName, clubName, city, etc.
// NUNCA datos del campo (cachedCourse, manuallyEdited, etc.).
// ─────────────────────────────────────────────────────────────────────────────
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
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

  static CollectionReference<Map<String, dynamic>> get _corrections =>
      _db.collection('courseCorrections');

  // ── API PÚBLICA ─────────────────────────────────────────────────────────────

  /// Devuelve la corrección oficial para [courseId] si existe.
  /// No depende del usuario ni de sus favoritos.
  /// Retorna null si no hay corrección registrada para ese campo.
  static Future<CourseCorrection?> getForCourse(String courseId) async {
    try {
      debugPrint('[Corrections] Consultando courseCorrections/$courseId…');
      final snap = await _corrections.doc(courseId).get();
      if (!snap.exists) {
        debugPrint('[Corrections] courseCorrections/$courseId NO existe en Firestore');
        return null;
      }

      final data = snap.data()!;
      debugPrint('[Corrections] Documento encontrado para $courseId, keys: ${data.keys.toList()}');
      final result = _parse(courseId, data);
      if (result != null) {
        debugPrint('[Corrections] Corrección OK para $courseId: '
            '${result.correctedCourse.allTees.length} tees, v${result.correctionVersion}');
      } else {
        debugPrint('[Corrections] _parse devolvió null para $courseId');
      }
      return result;
    } catch (e) {
      debugPrint('[Corrections] ERROR en getForCourse($courseId): $e');
      return null;
    }
  }

  /// Alias de [getForCourse] — mantiene compatibilidad con llamadas existentes
  /// que usaban checkForCorrection o getGlobalCorrection.
  static Future<CourseCorrection?> checkForCorrection(String courseId) =>
      getForCourse(courseId);

  /// Alias de [getForCourse]
  static Future<CourseCorrection?> getGlobalCorrection(String courseId) =>
      getForCourse(courseId);

  // ── PRIVADO ─────────────────────────────────────────────────────────────────

  static CourseCorrection? _parse(String courseId, Map<String, dynamic> data) {
    try {
      final version = (data['correctionVersion'] is num
          ? (data['correctionVersion'] as num).toInt()
          : 1);

      // Normalizar el mapa de correctedCourse (Firestore Web devuelve Map<Object?,Object?>)
      final rawCc = data['correctedCourse'];
      if (rawCc == null) return null;

      // Normalización recursiva profunda — delegar a ApiCourse._deepNormalize
      // para garantizar que Map<Object?,Object?> y List<Object?> de Firestore Web
      // se convierten correctamente a tipos Dart antes de llamar a fromCached.
      final Map<String, dynamic> correctedJson;
      try {
        final normalized = ApiCourse.deepNormalize(rawCc);
        if (normalized is! Map<String, dynamic>) {
          debugPrint('[Corrections] correctedCourse no es un Map tras normalizar: ${normalized.runtimeType}');
          return null;
        }
        correctedJson = normalized;
      } catch (_) {
        debugPrint('[Corrections] No se pudo normalizar correctedCourse para $courseId');
        return null;
      }

      debugPrint('[Corrections] correctedJson keys: ${correctedJson.keys.toList()}');
      debugPrint('[Corrections] maleTees raw type: ${correctedJson['maleTees']?.runtimeType}');
      final course = ApiCourse.fromCached(correctedJson);
      debugPrint('[Corrections] fromCached → maleTees: ${course.maleTees.length}, femaleTees: ${course.femaleTees.length}');
      if (course.allTees.isEmpty) {
        debugPrint('[Corrections] allTees VACÍO para $courseId — revisa la estructura del documento');
        return null;
      }

      return CourseCorrection(
        courseId:          courseId,
        correctionVersion: version,
        notes:             data['notes']?.toString() ?? 'Datos del campo actualizados',
        correctedCourse:   course,
      );
    } catch (e) {
      debugPrint('[Corrections] EXCEPCIÓN en _parse($courseId): $e');
      return null;
    }
  }
}
