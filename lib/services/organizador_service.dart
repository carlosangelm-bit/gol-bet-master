// ─────────────────────────────────────────────────────────────────────────────
// QUIÉN ES ORGANIZADOR — la marca, y por qué está donde está
//
// «El módulo de organizador es exclusivo para ese segmento de negocio y no
// tiene que ver con la capacidad del usuario recreativo de crear torneos desde
// su perfil.»
//
// Son dos clientes, no dos roles del mismo. Un golfista que organiza su Match
// Play anual NO es un organizador: eso es una función del jugador y se queda
// gratis. El módulo es para quien organiza torneos de forma formal, y eso se
// contrata.
//
// ── LA MARCA NO PUEDE VIVIR EN users/{uid} ──────────────────────────────────
//
// La regla de ese documento deja escribir cualquier campo al propio usuario, así
// que un `esOrganizador` ahí se lo pondría él mismo con su token y una llamada
// a la API — sin abrir la app. Vive en `organizadores/{uid}`, que se lee y no se
// escribe: ver la regla, que lo explica con la cita.
//
// ── Y QUIÉN LA PONE ────────────────────────────────────────────────────────
//
// «Se debe marcar desde el master que debe ser administrado por mí.» No es
// autoservicio, y encaja con el pago por evento: un torneo formal se contrata
// hablando, no metiendo una tarjeta.
//
// Hoy se administra desde la CONSOLA DE FIREBASE: crear el documento
// `organizadores/{uid}` con lo que se quiera dentro. Una pantalla de
// administración es trabajo que no hace falta todavía, y además tendría su
// propio problema —quién es el master— que es más grande que el que resuelve.
// El día que haya cobro automático, lo escribe el webhook.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';

class OrganizadorService {
  static final _db = FirebaseFirestore.instance;

  /// Si esta cuenta tiene el módulo de organizador.
  ///
  /// ── La EXISTENCIA es la marca ─────────────────────────────────────────────
  ///
  /// No hay un campo `activo` que consultar: si el documento está, la cuenta lo
  /// tiene. Un booleano dentro daría dos estados para lo mismo —documento
  /// ausente y documento en false— y el día que alguien escriba solo uno de los
  /// dos, la cuenta quedaría en un limbo que nadie sabría leer.
  ///
  /// Lo que el documento lleve dentro es para que Carlos se acuerde de a quién
  /// se lo dio: no lo lee nadie.
  ///
  /// Devuelve false ante cualquier fallo. Sin sesión, sin red o con la regla
  /// denegando, la respuesta correcta es la MISMA: no se enseña el módulo. Un
  /// error de red no puede abrir un producto de pago.
  static Future<bool> esOrganizador() async {
    final uid = AuthService.uid;
    if (uid == null) return false;
    try {
      final snap = await _db.collection('organizadores').doc(uid).get();
      return snap.exists;
    } catch (e) {
      debugPrint('[Organizador] $uid: $e');
      return false;
    }
  }
}
