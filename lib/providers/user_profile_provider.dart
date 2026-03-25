// ─────────────────────────────────────────────────────────────────────────────
// USER PROFILE PROVIDER
// Estado del perfil del usuario y sus campos favoritos.
// Se inicia al autenticarse (igual que PlayerProvider).
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/user_profile_service.dart';
import '../services/golf_course_service.dart';

class UserProfileProvider extends ChangeNotifier {
  UserProfile?          _profile;
  List<FavoriteCourse>  _favCourses = [];
  bool                  _loading = false;
  String?               _error;
  StreamSubscription<UserProfile?>?        _profileSub;
  StreamSubscription<List<FavoriteCourse>>? _coursesSub;

  // ── Getters ────────────────────────────────────────────────────────────────
  UserProfile?         get profile    => _profile;
  List<FavoriteCourse> get favCourses => _favCourses;
  bool                 get loading    => _loading;
  String?              get error      => _error;
  bool                 get hasProfile => _profile != null;

  bool isFavCourse(String courseId) =>
      _favCourses.any((c) => c.courseId == courseId);

  // ── Suscripción en tiempo real ─────────────────────────────────────────────
  void startListening() {
    _loading = true;
    _error   = null;
    notifyListeners();

    _profileSub?.cancel();
    _profileSub = UserProfileService.profileStream().listen(
      (profile) {
        _profile = profile;
        _loading = false;
        notifyListeners();
      },
      onError: (e) {
        if (kDebugMode) debugPrint('UserProfileProvider profile error: $e');
        _error   = e.toString();
        _loading = false;
        notifyListeners();
      },
    );

    _coursesSub?.cancel();
    _coursesSub = UserProfileService.favCoursesStream().listen(
      (courses) {
        _favCourses = courses;
        notifyListeners();
      },
      onError: (e) {
        if (kDebugMode) debugPrint('UserProfileProvider courses error: $e');
      },
    );
  }

  void stopListening() {
    _profileSub?.cancel();
    _coursesSub?.cancel();
    _profileSub = null;
    _coursesSub = null;
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }

  // ── Guardar perfil completo ────────────────────────────────────────────────
  Future<void> saveProfile(UserProfile profile) =>
      UserProfileService.saveProfile(profile);

  /// Actualizar solo campos específicos (más eficiente)
  Future<void> updateFields(Map<String, dynamic> fields) =>
      UserProfileService.updateFields(fields);

  // ── Toggle campo favorito ──────────────────────────────────────────────────
  Future<void> toggleFavCourse(
    String courseId,
    String clubName, {
    String courseName = '',
    String? city,
    String? country,
    ApiCourse? apiCourse,
  }) async {
    // Actualización optimista local
    if (isFavCourse(courseId)) {
      _favCourses.removeWhere((c) => c.courseId == courseId);
    } else {
      _favCourses.insert(0, FavoriteCourse(
        courseId:     courseId,
        clubName:     clubName,
        courseName:   courseName,
        city:         city,
        country:      country,
        createdAt:    DateTime.now(),
        cachedCourse: apiCourse,
      ));
    }
    notifyListeners();

    // Persistir en Firestore
    await UserProfileService.toggleFavCourse(
      courseId, clubName,
      courseName:  courseName,
      city:        city,
      country:     country,
      apiCourse:   apiCourse,
    );
  }

  Future<void> removeFavCourse(String courseId) async {
    _favCourses.removeWhere((c) => c.courseId == courseId);
    notifyListeners();
    await UserProfileService.removeFavCourse(courseId);
  }

  /// Guarda el tee preferido del usuario para un campo favorito.
  /// Actualiza optimistamente la lista local y persiste en Firestore.
  Future<void> updateFavCourseTee(String courseId, String teeName) async {
    final idx = _favCourses.indexWhere((c) => c.courseId == courseId);
    if (idx == -1) return;
    final old = _favCourses[idx];
    _favCourses[idx] = FavoriteCourse(
      courseId:        old.courseId,
      clubName:        old.clubName,
      courseName:      old.courseName,
      city:            old.city,
      country:         old.country,
      nickname:        old.nickname,
      createdAt:       old.createdAt,
      cachedCourse:    old.cachedCourse,
      preferredTeeName: teeName,
    );
    notifyListeners();
    await UserProfileService.updateFavCourseTee(courseId, teeName);
  }
}
