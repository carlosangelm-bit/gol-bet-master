// ─────────────────────────────────────────────────────────────────────────────
// AUTH SERVICE — Firebase Authentication (Email/Password + Google Web)
// ─────────────────────────────────────────────────────────────────────────────
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../core/firebase_options.dart';

class AuthService {
  static final _auth = FirebaseAuth.instance;
  static final _db   = FirebaseFirestore.instance;

  static User?   get currentUser => _auth.currentUser;
  static String? get uid         => _auth.currentUser?.uid;

  // ── Registro con email/contraseña ──────────────────────────────────────────
  static Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email, password: password,
    );
    await cred.user?.updateDisplayName(displayName);
    await _upsertProfile(cred.user!, name: displayName);
    return cred;
  }

  // ── Login con email/contraseña ─────────────────────────────────────────────
  static Future<UserCredential> loginWithEmail({
    required String email,
    required String password,
  }) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email, password: password,
    );
    await _upsertProfile(cred.user!);
    return cred;
  }

  // ── Google Sign-In (Web: signInWithPopup) ──────────────────────────────────
  static Future<UserCredential?> signInWithGoogle() async {
    final provider = GoogleAuthProvider()
      ..addScope('email')
      ..addScope('profile')
      // Client ID necesario para que el popup de Google funcione en Web
      ..setCustomParameters({
        'client_id': DefaultFirebaseOptions.googleWebClientId,
      });

    // signInWithPopup funciona en Flutter Web sin paquetes extra
    final cred = await _auth.signInWithPopup(provider);
    await _upsertProfile(cred.user!);
    return cred;
  }

  // ── Cerrar sesión ───────────────────────────────────────────────────────────
  static Future<void> signOut() => _auth.signOut();

  // ── Reset password ──────────────────────────────────────────────────────────
  static Future<void> resetPassword(String email) =>
      _auth.sendPasswordResetEmail(email: email);

  // ── Actualizar nombre ──────────────────────────────────────────────────────
  static Future<void> updateDisplayName(String name) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.updateDisplayName(name);
    await _db.collection('users').doc(user.uid)
        .update({'displayName': name, 'updatedAt': FieldValue.serverTimestamp()});
  }

  // ── Crear o actualizar perfil en Firestore ─────────────────────────────────
  static Future<void> _upsertProfile(User user, {String? name}) async {
    try {
      final ref  = _db.collection('users').doc(user.uid);
      final snap = await ref.get();
      final data = <String, dynamic>{
        'uid':         user.uid,
        'email':       user.email ?? '',
        'displayName': name ?? user.displayName ?? '',
        'photoUrl':    user.photoURL ?? '',
        'updatedAt':   FieldValue.serverTimestamp(),
      };
      if (!snap.exists) {
        data['createdAt'] = FieldValue.serverTimestamp();
        await ref.set(data);
      } else {
        // Solo actualizar campos vacíos para no sobreescribir cambios del usuario
        final existing = snap.data()!;
        final patch = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
        if ((existing['displayName'] as String? ?? '').isEmpty && data['displayName'] != '') {
          patch['displayName'] = data['displayName'];
        }
        if ((existing['photoUrl'] as String? ?? '').isEmpty && data['photoUrl'] != '') {
          patch['photoUrl'] = data['photoUrl'];
        }
        await ref.update(patch);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('_upsertProfile error: $e');
    }
  }

  // ── Traducir errores Firebase → español ────────────────────────────────────
  static String errorMessage(FirebaseAuthException e) {
    if (kDebugMode) debugPrint('FirebaseAuthException [${e.code}]: ${e.message}');
    switch (e.code) {
      case 'email-already-in-use':
        return 'Este correo ya está registrado.';
      case 'invalid-email':
        return 'El formato del correo no es válido.';
      case 'weak-password':
        return 'La contraseña debe tener al menos 6 caracteres.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Correo o contraseña incorrectos.';
      case 'too-many-requests':
        return 'Demasiados intentos. Espera unos minutos.';
      case 'network-request-failed':
        return 'Sin conexión a internet.';
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
        return ''; // Sin mensaje — el usuario canceló
      case 'account-exists-with-different-credential':
        return 'Ya existe una cuenta con ese correo usando otro método.';
      case 'popup-blocked':
        return 'El navegador bloqueó el popup. Permite popups para este sitio.';
      default:
        return 'Error (${e.code}): ${e.message ?? "desconocido"}';
    }
  }
}
