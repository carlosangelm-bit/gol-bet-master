// ─────────────────────────────────────────────────────────────────────────────
// LA PANTALLA DE LA CASA CLUB — publicarla, refrescarla y apagarla
//
// Hasta aquí el leaderboard proyectable no tenía origen: la pantalla existía,
// la regla existía, el modelo existía, y NADIE escribía el documento. Es la
// forma que más veces se ha repetido en este proyecto —el dato existe, la capa
// siguiente no lo lee— y esta vez le tocaba al último eslabón.
//
// ── Sin BuildContext, y no por estilo ───────────────────────────────────────
//
// La otra mitad de esta historia ya pasó: publicar el resultado a los torneos
// ajenos vivía en un método de pantalla al que el propio cierre DESTRUÍA, así
// que después del await no se ejecutaba y el resultado nunca salía. Esto no
// toca la interfaz: recibe datos, devuelve lo que hizo, y quien llama decide
// qué contar.
//
// ── Las tres decisiones que hay escritas aquí ───────────────────────────────
//
// 1 · TOKEN PROPIO, distinto del de `sharedTorneos`. Ver [nuevoToken].
// 2 · ENCENDER ES UNA DECISIÓN; APAGAR APAGA LAS DOS. Ver [debeRefrescar] y
//     [apagar].
// 3 · SE REFRESCA SOLA al cerrar una ronda, porque una tele con la tabla de
//     hace tres horas es peor que no tener tele: nadie la mira dos veces.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/foundation.dart';

import '../models/leaderboard_publico.dart';
import '../models/torneo.dart';
import 'firestore_service.dart';

/// Qué pasó al intentar encender o refrescar una pantalla.
enum ResultadoTele {
  publicada,

  /// No se intentó: el organizador no ha encendido la pantalla de este torneo.
  apagada,

  /// No se intentó: sin lista de inscritos, proyectar empeora el problema.
  sinParticipantes,

  /// Se intentó y falló. Queda en el log; ver [Tele.refrescar].
  fallo,
}

class Tele {
  /// Un token NUEVO para la pantalla, del espacio `tv_`.
  ///
  /// ── Por qué no se reutiliza el de `sharedTorneos` ─────────────────────────
  ///
  /// Era la idea inicial —"una dirección para la gente y otra para la tele"— y
  /// está mal por una razón que solo se ve mirando la regla:
  ///
  ///   sharedTorneos → allow get: if request.auth != null
  ///
  /// O sea: CUALQUIER cuenta con el token lee el bote y los balances. No se
  /// comprueba que estés invitado; el token ES la credencial.
  ///
  /// Y el token de la tele es el string menos secreto del sistema: se proyecta
  /// en una pared durante ocho horas y se le manda al del club para que lo abra
  /// en el navegador de la sala. Con un solo token, quien leyera la URL de la
  /// pantalla y se registrara gratis leería el dinero.
  ///
  /// Dos espacios distintos, y la pantalla de la pared no abre nada más.
  static String nuevoToken() =>
      'tv_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  /// Si a este torneo hay que refrescarle la pantalla.
  ///
  /// Encender es una DECISIÓN del organizador, igual que compartir el enlace:
  /// cerrar una ronda no puede empezar a proyectar en una pared por su cuenta.
  /// Así que esto solo mira si ya está encendida.
  static bool debeRefrescar(Torneo t) => t.teleEncendida && !t.cerrado;

  /// Construye la instantánea pública de [torneo]. Sin un solo importe.
  static LeaderboardPublico instantanea({
    required String token,
    required String ownerUid,
    required Torneo torneo,
    required TablaDelTorneo tabla,
    required DateTime cuando,
  }) =>
      LeaderboardPublico.desde(
        token: token,
        ownerUid: ownerUid,
        torneo: torneo,
        tabla: tabla,
        cuando: cuando,
        // El inventario viaja con la instantánea, pero VIVE en el torneo: lo
        // pactó el organizador con las marcas y no lo decide esta función.
        inventario: torneo.inventario,
      );

  /// Enciende la pantalla, o refresca la que ya está encendida.
  ///
  /// Devuelve el token si quedó publicada. [encender] en true es la decisión
  /// explícita del organizador; en false solo refresca lo que ya estaba.
  static Future<(ResultadoTele, String?)> publicar({
    required String ownerUid,
    required Torneo torneo,
    required TablaDelTorneo tabla,
    required DateTime cuando,
    bool encender = false,
  }) async {
    // Mismo criterio que el botón de compartir: proyectar una tabla con gente
    // que no se inscribió empeora el problema en vez de arreglarlo, y en una
    // pared lo empeora delante de todo el club.
    if (tabla.sinListaDeParticipantes) {
      return (ResultadoTele.sinParticipantes, null);
    }
    if (!encender && !debeRefrescar(torneo)) {
      return (ResultadoTele.apagada, null);
    }
    final token = torneo.tokenTele ?? nuevoToken();
    try {
      await FirestoreService.publicarLeaderboard(instantanea(
        token: token,
        ownerUid: ownerUid,
        torneo: torneo,
        tabla: tabla,
        cuando: cuando,
      ));
      return (ResultadoTele.publicada, token);
    } catch (e) {
      debugPrint('[Tele] ${torneo.nombre}: $e');
      return (ResultadoTele.fallo, null);
    }
  }

  /// Apaga la pantalla sin romper el enlace.
  ///
  /// El token SOBREVIVE, igual que en el enlace de WhatsApp y por el mismo
  /// motivo: se le dio al del club, y obligarle a pedir otro cada vez que se
  /// apaga no es apagar, es romper.
  static Future<void> apagar(Torneo t) async {
    final token = t.tokenTele;
    if (token == null) return;
    await FirestoreService.apagarLeaderboard(token);
  }
}
