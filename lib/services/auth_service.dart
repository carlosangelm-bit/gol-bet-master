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
      ..setCustomParameters({
        'client_id': DefaultFirebaseOptions.googleWebClientId,
      });

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

  // ── Crear o actualizar perfil + Player automático al primer login ──────────
  //
  // Flujo:
  //   1. Si el doc users/{uid} NO existe → usuario nuevo:
  //      a. Crear doc users/{uid} con los datos del perfil
  //      b. Crear Player global en players/{newId} con nombre + linkedUserId = uid
  //      c. Crear PlayerLink en users/{uid}/playerLinks/{playerId}
  //      d. Actualizar users/{uid}.myPlayerId = playerId
  //   2. Si el doc ya existe → solo actualizar campos vacíos (no sobreescribir)
  static Future<void> _upsertProfile(User user, {String? name}) async {
    try {
      final ref      = _db.collection('users').doc(user.uid);
      final snap     = await ref.get();
      final fullName = name ?? user.displayName ?? '';

      if (!snap.exists) {
        // ── Primer login: crear perfil + Player en una sola transacción ────
        await _db.runTransaction((tx) async {
          // 1. Crear Player global
          final playerRef = _db.collection('players').doc();
          final now       = DateTime.now().toIso8601String();
          tx.set(playerRef, {
            'id':           playerRef.id,
            'name':         fullName,
            'handicapBase': 0.0,
            'colorIndex':   0,
            'linkedUserId': user.uid,
            'createdByUserId': user.uid,
            'isShared':     false,
            'createdAt':    now,
            'updatedAt':    now,
          });

          // 2. Crear PlayerLink en directorio del usuario
          final linkRef = _db
              .collection('users').doc(user.uid)
              .collection('playerLinks').doc(playerRef.id);
          tx.set(linkRef, {
            'playerId':                 playerRef.id,
            'isFavorite':               false,
            'defaultSlidingAdjustment': 0.0,
            'sortOrder':                0,
            'linkedUserId':             user.uid,
            'createdAt':                now,
            'updatedAt':                now,
          });

          // 3. Crear perfil de usuario con myPlayerId ya enlazado
          tx.set(ref, {
            'uid':         user.uid,
            'email':       user.email ?? '',
            'displayName': fullName,
            'photoUrl':    user.photoURL ?? '',
            'myPlayerId':  playerRef.id,
            'createdAt':   FieldValue.serverTimestamp(),
            'updatedAt':   FieldValue.serverTimestamp(),
          });
        });

        if (kDebugMode) {
          debugPrint('[AuthService] Nuevo usuario creado con Player automático: ${user.uid}');
        }
      } else {
        // ── Login subsecuente: actualizar solo campos vacíos ───────────────
        final existing = snap.data()!;
        final patch    = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};

        if ((existing['displayName'] as String? ?? '').isEmpty && fullName.isNotEmpty) {
          patch['displayName'] = fullName;
        }
        if ((existing['photoUrl'] as String? ?? '').isEmpty &&
            (user.photoURL ?? '').isNotEmpty) {
          patch['photoUrl'] = user.photoURL;
        }
        // Si por alguna razón no tiene myPlayerId (usuarios legacy), crearlo ahora
        if ((existing['myPlayerId'] as String?) == null) {
          await _createMissingPlayer(user, fullName, ref, existing);
          return; // _createMissingPlayer ya hace el update completo
        }

        if (patch.length > 1) await ref.update(patch);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthService] _upsertProfile error: $e');
    }
  }

  // ── Crear Player para usuarios legacy que no tienen myPlayerId ─────────────
  static Future<void> _createMissingPlayer(
    User user,
    String fullName,
    DocumentReference<Map<String, dynamic>> userRef,
    Map<String, dynamic> existingData,
  ) async {
    try {
      await _db.runTransaction((tx) async {
        final playerRef = _db.collection('players').doc();
        final now       = DateTime.now().toIso8601String();
        final name      = fullName.isNotEmpty
            ? fullName
            : (existingData['displayName'] as String? ?? 'Jugador');

        tx.set(playerRef, {
          'id':           playerRef.id,
          'name':         name,
          'handicapBase': 0.0,
          'colorIndex':   0,
          'linkedUserId': user.uid,
          'createdByUserId': user.uid,
          'isShared':     false,
          'createdAt':    now,
          'updatedAt':    now,
        });

        final linkRef = _db
            .collection('users').doc(user.uid)
            .collection('playerLinks').doc(playerRef.id);
        tx.set(linkRef, {
          'playerId':                 playerRef.id,
          'isFavorite':               false,
          'defaultSlidingAdjustment': 0.0,
          'sortOrder':                0,
          'linkedUserId':             user.uid,
          'createdAt':                now,
          'updatedAt':                now,
        });

        tx.update(userRef, {
          'myPlayerId': playerRef.id,
          'updatedAt':  FieldValue.serverTimestamp(),
        });
      });

      if (kDebugMode) {
        debugPrint('[AuthService] Player creado retroactivamente para: ${user.uid}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthService] _createMissingPlayer error: $e');
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
