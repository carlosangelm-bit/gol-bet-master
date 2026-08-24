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
import '../../models/torneo_seguido.dart';
import '../../models/torneo_publicado.dart';
import '../../providers/perfil_provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/torneo_provider.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

/// Publica el resultado de [round] a los torneos AJENOS que sigo y que la ronda
/// marcó.
///
/// Solo a los ajenos: los míos ya tienen el resultado en mi propia colección, que
/// es de donde la tabla lo lee. Publicarlo también sería escribir dos veces lo
/// mismo.
Future<void> _publicarASeguidos(
    BuildContext context, Round round, TorneoProvider prov) async {
  if (round.torneoIds.isEmpty) return;
  final uid = AuthService.uid;
  if (uid == null) return;

  final mios = prov.torneos.map((t) => t.id).toSet();
  final resultado = RoundResult.fromRound(round, playedAt: round.createdAt);

  for (final id in round.torneoIds) {
    if (mios.contains(id)) continue; // el mío ya está donde tiene que estar
    final seg = prov.seguidos.where((s) => s.torneoId == id).firstOrNull;
    if (seg == null || !seg.utilizable) continue;
    try {
      await FirestoreService.publicarResultadoDeTorneo(ResultadoDeTorneo(
        torneoId: seg.torneoId,
        roundId: round.id,
        token: seg.token,
        torneoOwnerUid: seg.ownerUid,
        escritoPor: uid,
        // El nombre que esta persona reclamó de la lista del organizador. Es lo
        // que permite emparejar el resultado con un inscrito: el uid no puede,
        // porque es otro espacio de ids.
        jugadorNombre: seg.jugadorNombre,
        resultado: resultado.toJson(),
      ));
      debugPrint('[Torneo] resultado de ${round.id} publicado a ${seg.nombre}');
    } catch (e) {
      debugPrint('[Torneo] no se pudo publicar a ${seg.nombre}: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('La ronda se cerró, pero no se pudo enviar a '
              '${seg.nombre}. Vuelve a cerrarla cuando haya conexión.'),
          duration: const Duration(seconds: 5),
        ));
      }
    }
  }
}

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

  // ── Primero: publicar el resultado a los torneos AJENOS que sigo ─────────
  //
  // Es lo que hace que una liga funcione. Mi ronda la cierro yo, así que su
  // resultado cae en MI colección y el organizador no lo vería; publicarlo en
  // torneoResultados es la única forma de que su tabla lo cuente.
  //
  // Va antes de republicar y no bloquea: si falla, la ronda ya está cerrada y el
  // resultado se puede volver a publicar cerrándola otra vez —el id del documento
  // es determinista, así que no duplica—.
  await _publicarASeguidos(context, round, torneoProv);

  final afectados = torneosARepublicar(round, torneoProv.torneos);
  if (afectados.isEmpty) return const [];

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
  return hechos;
}
