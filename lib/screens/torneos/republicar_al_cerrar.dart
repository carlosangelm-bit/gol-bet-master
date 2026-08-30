// ─────────────────────────────────────────────────────────────────────────────
// REPUBLICAR AL CERRAR — el enlace se refresca solo; crearlo sigue siendo tuyo
//
// La ronda se marcó para un torneo, la ronda se cerró: si ese torneo ya tiene
// enlace compartido, la tabla que ven los invitados acaba de quedar vieja. Esto
// la vuelve a publicar en el MISMO token, así que quien lo tenga en WhatsApp no
// se queda con una copia muerta.
//
// Qué NO hace, y a propósito:
//
//   · no crea enlaces        → publicar por primera vez es una decisión
//   · no toca torneos cerrados → una instantánea final es final
//   · no avisa si falla      → cerrar la ronda ya salió bien; un error rojo
//                              aquí haría dudar de lo que sí se guardó. Queda
//                              en el log, y el botón de compartir sigue estando
//
// El acompañante que cierra una ronda ajena no republica nada, y sin condición
// especial: su TorneoProvider solo trae SUS torneos, así que la marca del
// organizador no encuentra pareja en la lista. Las reglas lo rechazarían de
// todos modos —hay una prueba que lo comprueba—, pero ni se intenta.
//
// El detalle que importa: la instantánea se calcula con el RoundResult de la
// ronda que se acaba de cerrar AÑADIDO a mano. El stream de PerfilProvider tarda
// en traerlo, y publicar antes de que llegue enseñaría la tabla sin la última
// ronda —exactamente el problema que esto viene a resolver—.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../models/round_result.dart';
import '../../models/torneo.dart';
import '../../models/torneo_publicado.dart';
import '../../providers/perfil_provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/torneo_provider.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/tele_service.dart';

/// Refresca los enlaces de los torneos para los que contaba [round].
///
/// Devuelve los nombres de los torneos republicados, para poder decirlo en la
/// interfaz y para que los tests lo comprueben.
Future<List<String>> republicarTorneosDe(
    BuildContext context, Round round) async {
  final uid = AuthService.uid;
  if (uid == null) return const [];

  final torneoProv = context.read<TorneoProvider>();
  final perfilProv = context.read<PerfilProvider>();

  // OJO: publicar el resultado a los torneos AJENOS ya NO se hace aquí.
  //
  // Vivía en esta función, que se llama desde el método de cierre de una
  // pantalla que el propio cierre DESTRUYE — así que después del await no se
  // ejecutaba, y el resultado nunca salía. Ahora es parte de
  // RoundProvider.finishRound(), que no se puede saltar, y lo que hizo se lee
  // en RoundProvider.ultimosEnvios.
  //
  // Esto se queda con la otra mitad: refrescar los enlaces de MIS torneos, que
  // sí necesita el directorio y cuyo fallo no cuesta dinero.
  // ─────────────────────────────────────────────────────────────────────────

  // La condición vive en el modelo —hayQueRefrescarAlgo— y no aquí porque este
  // `return` ya se equivocó una vez: miraba solo los enlaces y se comía el bucle
  // entero de la tele. Ahí se puede probar; dentro de esta función, que exige
  // sesión y tres providers, no.
  if (!hayQueRefrescarAlgo(round, torneoProv.torneos)) return const [];
  final afectados = torneosARepublicar(round, torneoProv.torneos);
  final conTele = torneosConTeleARefrescar(round, torneoProv.torneos);

  // La ronda recién cerrada, calculada aquí en vez de esperada del stream.
  final propio = RoundResult.fromRound(round);
  final resultados = [
    ...perfilProv.resultados.where((r) => r.roundId != propio.roundId),
    propio,
  ];

  // Los nombres del directorio, para el cuadro: el que pasa con bye no aparece
  // en ninguna fila de la tabla y se quedaría sin nombre.
  final nombres = {
    for (final pw in context.read<PlayerProvider>().directory)
      pw.player.id: pw.displayName,
  };

  final ahora = DateTime.now();
  final hechos = <String>[];

  for (final torneo in afectados) {
    final tabla = tablaDe(torneo, resultados, nombres: nombres);
    // El cuadro decide el bote en eliminación, no la tabla.
    final llave = llaveDe(torneo, resultados);
    // Sin lista de inscritos no se publica: es el mismo criterio que el botón
    // de compartir, y publicar una tabla con gente que no se inscribió empeora
    // el problema en vez de arreglarlo.
    if (tabla.sinListaDeParticipantes) continue;

    final copia = TorneoPublicado.desde(
      token: torneo.tokenCompartido!,
      ownerUid: uid,
      torneo: torneo,
      tabla: tabla,
      bote: boteDe(torneo, tabla, campeon: llave.campeon),
      jornadas: botesPorJornada(torneo, tabla),
      cuando: ahora,
      llave: llave,
      nombres: nombres,
    );
    try {
      await FirestoreService.publicarTorneo(copia);
      await torneoProv.guardar(torneo.copyWith(publicadoEn: ahora));
      hechos.add(torneo.nombre);
    } catch (e) {
      debugPrint('[republicar] ${torneo.nombre}: $e');
    }
  }

  // ── Y LA PANTALLA DE LA CASA CLUB ──────────────────────────────────────────
  //
  // Bucle propio, no una línea dentro del de arriba. Aquel exige que el enlace
  // de WhatsApp siga vivo, y atar la pantalla a esa condición dejaba la peor de
  // las dos quedándose vieja en silencio: el enlace lo abre alguien que ve la
  // fecha de la copia; la pantalla está proyectada en una pared y nadie
  // comprueba nada.
  //
  // Lo que NO hace: encenderla. `encender` se queda en false, así que cerrar una
  // ronda no empieza a proyectar en una pared por su cuenta. Eso lo decide el
  // organizador, igual que crear el enlace.
  for (final torneo in conTele) {
    final tabla = tablaDe(torneo, resultados, nombres: nombres);
    await Tele.publicar(
      ownerUid: uid,
      torneo: torneo,
      tabla: tabla,
      cuando: ahora,
    );
  }

  return hechos;
}
