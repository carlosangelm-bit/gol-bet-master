// ─────────────────────────────────────────────────────────────────────────────
// PUBLICACIÓN A TORNEOS AJENOS — fuera del ciclo de vida de ninguna pantalla
//
// ── El fallo que esto arregla, con el dato de producción delante ─────────────
//
// Carlos cerró una ronda marcada para Liga por Score el 24 de agosto a las
// 14:17. La auditoría contra Firestore mostró que TODO estaba bien: la marca en
// la ronda, el seguimiento con su token y su ownerUid correctos, el nombre
// reclamado entre los inscritos, y el torneo perteneciendo a otra cuenta. Y la
// colección torneoResultados tenía CERO documentos.
//
// La causa no era el dato: era que el código no llegaba a ejecutarse.
// finishRound() pone _round = null; mainDestinations(hasRound: false) quita la
// pestaña Score; la CaptureScreen se destruye; y en su método de cierre, después
// del await del diálogo de sliding, `context.mounted` ya es false y el método
// vuelve ANTES de publicar. La pantalla que tiene que publicar la elimina la
// misma acción que dispara la publicación.
//
// Es la familia de siempre —el dato existe, la capa siguiente no lo lee— un
// nivel más abajo: la capa siguiente ni siquiera corre.
//
// ── Las dos reglas de este archivo ──────────────────────────────────────────
//
// 1 · NADA de BuildContext. Todo lo que hace falta entra por parámetro. Así no
//     hay ningún estado de pantalla del que dependa que el dinero se registre.
//
// 2 · Lo que falla SE ENCOLA y se reintenta. Que el cierre funcione no basta:
//     una ronda se cierra en el estacionamiento del club, con la conexión que
//     haya, y el resultado no puede depender de eso. El id del documento es
//     determinista —{torneoId}_{roundId}— así que reintentar ACTUALIZA y nunca
//     duplica; por eso reintentar es seguro por construcción y no por cuidado.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../models/round_result.dart';
import '../models/torneo.dart';
import '../models/torneo_seguido.dart';
import 'auth_service.dart';
import 'firestore_service.dart';

/// Qué pasó al intentar enviar el resultado a un torneo que sigo.
///
/// Existe porque el envío tenía CINCO salidas silenciosas —sin marca, sin
/// sesión, sin referencia, referencia incompleta, escritura fallida— y todas
/// devolvían lo mismo: nada. Desde fuera no se distinguía "no había nada que
/// enviar" de "se rompió", y eso costó tres entregas de diagnóstico a ciegas.
class EnvioAlTorneo {
  /// El nombre del torneo, o su id cuando no se conoce el nombre.
  final String torneo;
  final bool enviado;

  /// Por qué no se envió, o el matiz si se envió con reservas. Null si limpio.
  final String? motivo;

  /// Si quedó encolado para reintentar. Solo con [enviado] == false.
  final bool pendiente;

  const EnvioAlTorneo(this.torneo,
      {required this.enviado, this.motivo, this.pendiente = false});

  /// La frase para la interfaz.
  String get frase => enviado
      ? motivo == null
          ? 'Resultado enviado a $torneo.'
          : 'Resultado enviado a $torneo, pero $motivo'
      : pendiente
          ? 'No se pudo enviar a $torneo: $motivo. Queda pendiente y se '
              'reintenta solo.'
          : 'No se envió a $torneo: $motivo';
}

class PublicacionTorneoService {
  static const _kPendientes = 'torneo_publicaciones_pendientes';

  static Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  /// Publica el resultado de [round] a los torneos AJENOS que sigo y que la
  /// ronda marcó.
  ///
  /// Todo lo que necesita entra por parámetro, y quien llama lo lee ANTES de
  /// cualquier await. Ver la cabecera: de eso depende que esto se ejecute.
  ///
  /// [miFicha] es cuál de los jugadores de la ronda soy yo. El nombre reclamado
  /// dice quién publica; el id dice a quién hay que acreditar, y hacen falta las
  /// dos cosas porque los ids de la ronda son de MI directorio y los inscritos
  /// del directorio del organizador.
  static Future<List<EnvioAlTorneo>> publicar({
    required Round round,
    required List<Torneo> misTorneos,
    required List<TorneoSeguido> seguidos,
    String? miFicha,
  }) async {
    if (round.torneoIds.isEmpty) return const [];
    final uid = AuthService.uid;
    if (uid == null) {
      return [
        for (final id in round.torneoIds)
          EnvioAlTorneo(id, enviado: false, motivo: 'no hay sesión abierta')
      ];
    }

    final mios = misTorneos.map((t) => t.id).toSet();
    final resultado = RoundResult.fromRound(round, playedAt: round.createdAt);
    final yoJuego = miFicha != null && resultado.playerIds.contains(miFicha);

    final envios = <EnvioAlTorneo>[];
    for (final id in round.torneoIds) {
      if (mios.contains(id)) {
        // El mío ya está donde tiene que estar: el resultado cae en mi colección
        // y mi tabla lo lee de ahí. Pero SE DICE igual, para que toda ronda
        // marcada produzca una frase y la AUSENCIA de frase signifique una sola
        // cosa: que la ronda no quedó marcada.
        final mio = misTorneos.where((x) => x.id == id).firstOrNull;
        envios.add(EnvioAlTorneo(mio?.nombre ?? id,
            enviado: true, motivo: 'es tu torneo: ya cuenta en tu tabla'));
        continue;
      }
      final seg = seguidos.where((s) => s.torneoId == id).firstOrNull;
      if (seg == null) {
        envios.add(EnvioAlTorneo(id,
            enviado: false,
            motivo: 'no sigues ese torneo desde esta cuenta, o su lista no '
                'había cargado. Vuelve a abrir su enlace y ciérrala otra vez'));
        continue;
      }
      if (!seg.utilizable) {
        final falta = [
          if (seg.token.isEmpty) 'el enlace',
          if (seg.ownerUid.isEmpty) 'el organizador',
          if (seg.jugadorNombre.isEmpty) 'tu jugador',
        ].join(' y ');
        envios.add(EnvioAlTorneo(seg.nombre,
            enviado: false,
            motivo: 'la referencia que guardaste no trae $falta. Ábrelo de '
                'nuevo desde su enlace'));
        continue;
      }

      final doc = ResultadoDeTorneo(
        torneoId: seg.torneoId,
        roundId: round.id,
        token: seg.token,
        torneoOwnerUid: seg.ownerUid,
        escritoPor: uid,
        jugadorNombre: seg.jugadorNombre,
        jugadorId: yoJuego ? miFicha : '',
        resultado: resultado.toJson(),
      );

      try {
        await FirestoreService.publicarResultadoDeTorneo(doc);
        envios.add(EnvioAlTorneo(seg.nombre,
            enviado: true,
            motivo: yoJuego
                ? null
                : 'tú no juegas en esta ronda, así que no te va a contar'));
      } catch (e) {
        debugPrint('[Torneo] no se pudo publicar a ${seg.nombre}: $e');
        await _encolar(doc, seg.nombre);
        envios.add(EnvioAlTorneo(seg.nombre,
            enviado: false, pendiente: true, motivo: '$e'));
      }
    }
    return envios;
  }

  // ── La cola ───────────────────────────────────────────────────────────────
  //
  // Mismo patrón que las rondas finalizadas pendientes, y por el mismo motivo:
  // una ronda se cierra donde se acabó de jugar, no donde hay buena cobertura.

  static Future<void> _encolar(ResultadoDeTorneo d, String nombre) async {
    try {
      final p = await _prefs();
      final cola = p.getStringList(_kPendientes) ?? [];
      // Sin duplicados por documento: el id es determinista, así que la última
      // versión de la misma ronda sustituye a la anterior.
      cola.removeWhere((s) {
        try {
          return (jsonDecode(s) as Map)['docId'] == d.docId;
        } catch (_) {
          return false;
        }
      });
      cola.add(jsonEncode({'docId': d.docId, 'nombre': nombre, ...d.toJson()}));
      await p.setStringList(_kPendientes, cola);
      debugPrint('[Torneo] publicación encolada: ${d.docId}');
    } catch (e) {
      debugPrint('[Torneo] no se pudo encolar ${d.docId}: $e');
    }
  }

  /// Cuántas publicaciones esperan reintento.
  static Future<int> pendientes() async {
    try {
      final p = await _prefs();
      return (p.getStringList(_kPendientes) ?? []).length;
    } catch (_) {
      return 0;
    }
  }

  /// Los nombres de los torneos con publicación pendiente, para poder decirlo.
  static Future<List<String>> nombresPendientes() async {
    try {
      final p = await _prefs();
      return [
        for (final s in p.getStringList(_kPendientes) ?? const <String>[])
          (jsonDecode(s) as Map)['nombre'] as String? ?? '?'
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Reintenta lo pendiente. Devuelve cuántas salieron.
  ///
  /// Seguro de llamar tantas veces como haga falta: el id del documento es
  /// {torneoId}_{roundId}, así que volver a escribir ACTUALIZA. La regla de
  /// Firestore lo exige, y por eso reintentar no puede duplicar una ronda en la
  /// tabla de nadie.
  static Future<int> reintentarPendientes() async {
    if (AuthService.uid == null) return 0;
    try {
      final p = await _prefs();
      final cola = p.getStringList(_kPendientes) ?? [];
      if (cola.isEmpty) return 0;

      var hechas = 0;
      final quedan = <String>[];
      for (final s in cola) {
        try {
          final j = Map<String, dynamic>.from(jsonDecode(s) as Map);
          await FirestoreService.publicarResultadoDeTorneo(
              ResultadoDeTorneo.fromJson(j));
          hechas++;
        } catch (e) {
          debugPrint('[Torneo] reintento fallido: $e');
          quedan.add(s);
        }
      }
      if (quedan.isEmpty) {
        await p.remove(_kPendientes);
      } else {
        await p.setStringList(_kPendientes, quedan);
      }
      debugPrint('[Torneo] reintentos: $hechas/${cola.length}');
      return hechas;
    } catch (e) {
      debugPrint('[Torneo] error reintentando: $e');
      return 0;
    }
  }
}
