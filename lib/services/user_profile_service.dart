// ─────────────────────────────────────────────────────────────────────────────
// USER PROFILE SERVICE
// Gestiona el perfil del usuario en Firestore:
//   users/{uid}                        → perfil base
//   users/{uid}/favoriteCourses/{id}   → campos favoritos
//
// El "yo como jugador" es un concepto derivado del perfil:
//   - displayName / nickname  → nombre que aparece en rondas
//   - defaultHandicap         → HCP por defecto al crear ronda
//   - colorIndex              → color de avatar
//   - defaultCurrency         → moneda (USD, MXN, EUR…)
// ─────────────────────────────────────────────────────────────────────────────
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import 'auth_service.dart';
import 'golf_course_service.dart';

// ── Modelo de perfil completo ─────────────────────────────────────────────────
class UserProfile {
  final String uid;
  final String displayName;
  final String email;
  final String photoUrl;
  final String? nickname;           // apodo corto que verá en la app
  final double defaultHandicap;     // HCP por defecto al sumarse a una ronda
  final int    colorIndex;          // color de avatar (0-7)
  final String defaultCurrency;     // 'USD', 'MXN', 'EUR', etc.
  final double defaultUnitValue;    // valor base de apuesta
  final String? defaultScoringMode; // 'gross' | 'net'
  final String? favoriteView;       // pestaña favorita al abrir la app
  final String? myPlayerId;          // ID del jugador en el directorio que soy 'yo'
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const UserProfile({
    required this.uid,
    required this.displayName,
    required this.email,
    this.photoUrl = '',
    this.nickname,
    this.defaultHandicap = 0,
    this.colorIndex = 0,
    this.defaultCurrency = 'USD',
    this.defaultUnitValue = 5,
    this.defaultScoringMode,
    this.favoriteView,
    this.myPlayerId,
    this.createdAt,
    this.updatedAt,
  });

  UserProfile copyWith({
    String? displayName,
    String? nickname,
    double? defaultHandicap,
    int? colorIndex,
    String? defaultCurrency,
    double? defaultUnitValue,
    String? defaultScoringMode,
    String? favoriteView,
    String? myPlayerId,
    bool clearMyPlayerId = false,
  }) => UserProfile(
    uid: uid,
    email: email,
    photoUrl: photoUrl,
    displayName: displayName ?? this.displayName,
    nickname: nickname ?? this.nickname,
    defaultHandicap: defaultHandicap ?? this.defaultHandicap,
    colorIndex: colorIndex ?? this.colorIndex,
    defaultCurrency: defaultCurrency ?? this.defaultCurrency,
    defaultUnitValue: defaultUnitValue ?? this.defaultUnitValue,
    defaultScoringMode: defaultScoringMode ?? this.defaultScoringMode,
    favoriteView: favoriteView ?? this.favoriteView,
    myPlayerId: clearMyPlayerId ? null : (myPlayerId ?? this.myPlayerId),
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  /// Nombre a mostrar: nickname si existe, sino displayName
  String get shortName =>
      (nickname?.isNotEmpty == true) ? nickname! : displayName;

  /// Convierte el perfil en un Player para usarlo en la ronda
  Player toPlayer() => Player(
    id: uid,
    name: shortName,
    handicapBase: defaultHandicap,
    colorIndex: colorIndex,
  );

  Map<String, dynamic> toFirestore() => {
    'displayName':       displayName,
    'email':             email,
    'photoUrl':          photoUrl,
    if (nickname != null) 'nickname': nickname,
    'defaultHandicap':   defaultHandicap,
    'colorIndex':        colorIndex,
    'defaultCurrency':   defaultCurrency,
    'defaultUnitValue':  defaultUnitValue,
    if (defaultScoringMode != null) 'defaultScoringMode': defaultScoringMode,
    if (favoriteView != null) 'favoriteView': favoriteView,
    if (myPlayerId != null) 'myPlayerId': myPlayerId,
    'updatedAt':         FieldValue.serverTimestamp(),
  };

  factory UserProfile.fromFirestore(Map<String, dynamic> d, String uid) =>
      UserProfile(
        uid:               uid,
        displayName:       d['displayName'] as String? ?? '',
        email:             d['email'] as String? ?? '',
        photoUrl:          d['photoUrl'] as String? ?? '',
        nickname:          d['nickname'] as String?,
        defaultHandicap:   (d['defaultHandicap'] as num?)?.toDouble() ?? 0,
        colorIndex:        (d['colorIndex'] as int?) ?? 0,
        defaultCurrency:   d['defaultCurrency'] as String? ?? 'USD',
        defaultUnitValue:  (d['defaultUnitValue'] as num?)?.toDouble() ?? 5,
        defaultScoringMode: d['defaultScoringMode'] as String?,
        favoriteView:      d['favoriteView'] as String?,
        myPlayerId:        d['myPlayerId'] as String?,
        createdAt: _ts(d['createdAt']),
        updatedAt: _ts(d['updatedAt']),
      );

  static DateTime? _ts(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}

// ── Modelo de campo favorito ──────────────────────────────────────────────────
class FavoriteCourse {
  final String courseId;    // ID numérico de la API (como string)
  final String clubName;    // nombre del club (principal)
  final String courseName;  // nombre del curso/layout (puede estar vacío)
  final String? city;
  final String? country;
  final String? nickname;   // apodo personal del usuario
  final DateTime createdAt;
  /// Datos completos del campo (tees + hoyos) para evitar llamadas a la API.
  /// Puede ser null si se guardó antes de esta versión (retrocompatibilidad).
  final ApiCourse? cachedCourse;

  const FavoriteCourse({
    required this.courseId,
    required this.clubName,
    this.courseName = '',
    this.city,
    this.country,
    this.nickname,
    required this.createdAt,
    this.cachedCourse,
  });

  /// Nombre completo del campo (mismo formato que en la tarjeta de ronda)
  String get fullName {
    if (courseName.isNotEmpty && courseName != clubName) {
      return '$clubName — $courseName';
    }
    return clubName;
  }

  /// Nombre a mostrar: apodo si existe, sino nombre completo
  String get displayName =>
      (nickname?.isNotEmpty == true) ? nickname! : fullName;

  String get location {
    final parts = [city, country].whereType<String>().where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? '' : parts.join(', ');
  }

  /// True si tenemos los datos del campo en cache (sin necesidad de API)
  bool get hasCachedData => cachedCourse != null && cachedCourse!.allTees.isNotEmpty;

  Map<String, dynamic> toFirestore() => {
    'courseId':   courseId,
    'clubName':   clubName,
    'courseName': courseName,
    if (city != null)     'city':     city,
    if (country != null)  'country':  country,
    if (nickname != null) 'nickname': nickname,
    'createdAt':  FieldValue.serverTimestamp(),
    if (cachedCourse != null) 'cachedCourse': cachedCourse!.toJson(),
  };

  factory FavoriteCourse.fromFirestore(Map<String, dynamic> d, String id) {
    final cached = d['cachedCourse'] as Map<String, dynamic>?;
    return FavoriteCourse(
      courseId:    id,
      clubName:    d['clubName']   as String? ?? d['name'] as String? ?? '',
      courseName:  d['courseName'] as String? ?? '',
      city:        d['city']       as String?,
      country:     d['country']    as String?,
      nickname:    d['nickname']   as String?,
      createdAt:   _ts(d['createdAt']) ?? DateTime.now(),
      cachedCourse: cached != null ? ApiCourse.fromCached(cached) : null,
    );
  }

  static DateTime? _ts(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}

// ── Servicio ──────────────────────────────────────────────────────────────────
class UserProfileService {
  static final _db = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _userDoc() =>
      _db.collection('users').doc(AuthService.uid!);

  static CollectionReference<Map<String, dynamic>> _favCourses() =>
      _userDoc().collection('favoriteCourses');

  // ── Stream del perfil ──────────────────────────────────────────────────────
  static Stream<UserProfile?> profileStream() {
    if (AuthService.uid == null) return Stream.value(null);
    return _userDoc().snapshots().map((snap) {
      if (!snap.exists) return null;
      return UserProfile.fromFirestore(snap.data()!, snap.id);
    });
  }

  // ── Guardar perfil ─────────────────────────────────────────────────────────
  static Future<void> saveProfile(UserProfile profile) async {
    if (AuthService.uid == null) return;
    await _userDoc().set(profile.toFirestore(), SetOptions(merge: true));
  }

  // ── Actualizar campos específicos ──────────────────────────────────────────
  static Future<void> updateFields(Map<String, dynamic> fields) async {
    if (AuthService.uid == null) return;
    await _userDoc().set(
      {...fields, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  // ── Campos favoritos ───────────────────────────────────────────────────────

  static Stream<List<FavoriteCourse>> favCoursesStream() {
    if (AuthService.uid == null) return Stream.value([]);
    // Sin orderBy para evitar índice compuesto — ordenamos en memoria
    return _favCourses()
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => FavoriteCourse.fromFirestore(d.data(), d.id))
              .toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  static Future<List<FavoriteCourse>> getFavCourses() async {
    if (AuthService.uid == null) return [];
    try {
      // Sin orderBy para evitar índice compuesto — ordenamos en memoria
      final snap = await _favCourses().get();
      final list = snap.docs
          .map((d) => FavoriteCourse.fromFirestore(d.data(), d.id))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (e) {
      if (kDebugMode) debugPrint('getFavCourses error: $e');
      return [];
    }
  }

  static Future<void> addFavCourse(FavoriteCourse course) async {
    if (AuthService.uid == null) return;
    await _favCourses().doc(course.courseId).set(course.toFirestore());
  }

  static Future<void> removeFavCourse(String courseId) async {
    if (AuthService.uid == null) return;
    await _favCourses().doc(courseId).delete();
  }

  static Future<bool> isFavCourse(String courseId) async {
    if (AuthService.uid == null) return false;
    final doc = await _favCourses().doc(courseId).get();
    return doc.exists;
  }

  /// Agrega o elimina un campo favorito.
  /// [apiCourse] es el ApiCourse completo (con tees+hoyos). Si se pasa,
  /// se cachea en Firestore para no volver a llamar a la API.
  static Future<void> toggleFavCourse(
    String courseId,
    String clubName, {
    String courseName = '',
    String? city,
    String? country,
    ApiCourse? apiCourse,
  }) async {
    if (AuthService.uid == null) return;
    final doc = _favCourses().doc(courseId);
    final snap = await doc.get();
    if (snap.exists) {
      await doc.delete();
    } else {
      await doc.set(FavoriteCourse(
        courseId:     courseId,
        clubName:     clubName,
        courseName:   courseName,
        city:         city,
        country:      country,
        createdAt:    DateTime.now(),
        cachedCourse: apiCourse,
      ).toFirestore());
    }
  }
}
