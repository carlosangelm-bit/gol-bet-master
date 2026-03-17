// ─────────────────────────────────────────────────────────────────────────────
// AUTH PROVIDER — Estado de autenticación Firebase
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  AuthStatus _status = AuthStatus.unknown;
  User?      _user;
  String?    _error;
  bool       _loading = false;
  StreamSubscription<User?>? _sub;
  Timer?     _unknownTimer;

  AuthStatus get status      => _status;
  User?      get user        => _user;
  String?    get error       => _error;
  bool       get loading     => _loading;
  bool       get isAuth      => _status == AuthStatus.authenticated;
  String     get displayName =>
      _user?.displayName?.isNotEmpty == true
          ? _user!.displayName!
          : (_user?.email?.split('@').first ?? 'Usuario');
  String     get email       => _user?.email ?? '';
  String     get photoUrl    => _user?.photoURL ?? '';

  AuthProvider() {
    // Timeout de seguridad: si Firebase no responde en 6s, mostramos el login
    _unknownTimer = Timer(const Duration(seconds: 6), () {
      if (_status == AuthStatus.unknown) {
        if (kDebugMode) debugPrint('AuthProvider: timeout → unauthenticated');
        _status = AuthStatus.unauthenticated;
        notifyListeners();
      }
    });

    try {
      _sub = FirebaseAuth.instance.authStateChanges().listen(
        (user) {
          _unknownTimer?.cancel();
          _user   = user;
          _status = user != null
              ? AuthStatus.authenticated
              : AuthStatus.unauthenticated;
          notifyListeners();
        },
        onError: (e) {
          if (kDebugMode) debugPrint('AuthProvider stream error: $e');
          _unknownTimer?.cancel();
          _status = AuthStatus.unauthenticated;
          notifyListeners();
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('AuthProvider init error: $e');
      _unknownTimer?.cancel();
      _status = AuthStatus.unauthenticated;
      notifyListeners();
    }
  }

  // ── Helpers internos ────────────────────────────────────────────────────────
  void _busy()           { _loading = true;  _error = null; notifyListeners(); }
  void _done()           { _loading = false;                notifyListeners(); }
  void _fail(String msg) { _loading = false; _error = msg;  notifyListeners(); }

  // ── Email + contraseña ──────────────────────────────────────────────────────
  Future<bool> register({
    required String email,
    required String password,
    required String name,
  }) async {
    _busy();
    try {
      await AuthService.registerWithEmail(
          email: email, password: password, displayName: name);
      _done();
      return true;
    } on FirebaseAuthException catch (e) {
      _fail(AuthService.errorMessage(e)); return false;
    } catch (e) {
      _fail('Error inesperado: $e'); return false;
    }
  }

  Future<bool> login({required String email, required String password}) async {
    _busy();
    try {
      await AuthService.loginWithEmail(email: email, password: password);
      _done();
      return true;
    } on FirebaseAuthException catch (e) {
      _fail(AuthService.errorMessage(e)); return false;
    } catch (e) {
      _fail('Error inesperado: $e'); return false;
    }
  }

  // ── Google ──────────────────────────────────────────────────────────────────
  Future<bool> loginWithGoogle() async {
    _busy();
    try {
      final cred = await AuthService.signInWithGoogle();
      _done();
      return cred != null;
    } on FirebaseAuthException catch (e) {
      _fail(AuthService.errorMessage(e)); return false;
    } catch (e) {
      _fail('Error con Google Sign-In: $e'); return false;
    }
  }

  // ── Otras acciones ──────────────────────────────────────────────────────────
  Future<bool> resetPassword(String email) async {
    _busy();
    try {
      await AuthService.resetPassword(email);
      _done(); return true;
    } on FirebaseAuthException catch (e) {
      _fail(AuthService.errorMessage(e)); return false;
    } catch (e) {
      _fail('Error: $e'); return false;
    }
  }

  Future<bool> updateName(String name) async {
    _busy();
    try {
      await AuthService.updateDisplayName(name);
      _done(); return true;
    } catch (e) {
      _fail('No se pudo actualizar el nombre.'); return false;
    }
  }

  Future<void> signOut() => AuthService.signOut();

  void clearError() { _error = null; notifyListeners(); }

  @override
  void dispose() {
    _unknownTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
