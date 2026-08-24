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
import '../../providers/user_profile_provider.dart';
import '../../providers/torneo_provider.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

/// Qué pasó al intentar enviar el resultado a un torneo que sigo.
///
/// ── Por qué esto existe ───────────────────────────────────────────────────
///
/// Esta función tenía CINCO salidas silenciosas: sin marca, sin sesión, sin
/// referencia al torneo, con la referencia incompleta, y con la escritura
/// fallando. Todas devolvían igual —nada— y desde fuera no se podía distinguir
/// "no había nada que enviar" de "se rompió".
///
/// Y eso es exactamente lo que costó una entrega entera de diagnóstico: una
/// tabla en cero y ninguna forma de saber en cuál de los tres puntos de la
/// cadena se paraba. El envío tiene que decir lo que hizo, en el momento en que
/// lo hace, porque después ya no queda rastro.
class EnvioAlTorneo {
  /// El nombre del torneo, o su id cuando no se conoce el nombre.
  final String torneo;
  final bool enviado;

  /// Por qué no se envió, o el matiz si se envió con reservas. Null si fue
  /// limpio.
  final String? motivo;

  const EnvioAlTorneo(this.torneo, {required this.enviado, this.motivo});

  /// La frase para la interfaz.
  String get frase => enviado
      ? motivo == null
          ? 'Resultado enviado a $torneo.'
          : 'Resultado enviado a $torneo, pero $motivo'
      : 'No se envió a $torneo: $motivo';
}

/// Publica el resultado de [round] a los torneos AJENOS que sigo y que la ronda
/// marcó.
///
/// Solo a los ajenos: los míos ya tienen el resultado en mi propia colección, que
/// es de donde la tabla lo lee. Publicarlo también sería escribir dos veces lo
/// mismo.
Future<List<EnvioAlTorneo>> _publicarASeguidos(
    BuildContext context, Round round, TorneoProvider prov) async {
  if (round.torneoIds.isEmpty) return const [];
  final uid = AuthService.uid;
  if (uid == null) {
    return [
      for (final id in round.torneoIds)
        EnvioAlTorneo(id, enviado: false, motivo: 'no hay sesión abierta')
    ];
  }

  final mios = prov.torneos.map((t) => t.id).toSet();
  final resultado = RoundResult.fromRound(round, playedAt: round.createdAt);

  // CUÁL de los jugadores de esta ronda soy yo. El nombre reclamado dice quién
  // publica; esto dice a quién hay que acreditar, y las dos cosas hacen falta:
  // los ids de la ronda son de MI directorio y los inscritos son del directorio
  // del organizador.
  //
  // Si no juego en la ronda —la anoté para otros— se publica sin id y la tabla
  // empareja por nombre, que es lo que se puede hacer. Y se dice en el aviso de
  // más abajo, porque una ronda del torneo en la que no estoy es raro.
  final miFicha = context.read<UserProfileProvider>().profile?.myPlayerId;
  final yoJuego = miFicha != null && resultado.playerIds.contains(miFicha);

  final envios = <EnvioAlTorneo>[];
  for (final id in round.torneoIds) {
    if (mios.contains(id)) {
      // El mío ya está donde tiene que estar: el resultado cae en mi colección y
      // mi tabla lo lee de ahí. Pero SE DICE igual, porque así toda ronda marcada
      // produce una frase y la AUSENCIA de frase significa una sola cosa: que la
      // ronda no quedó marcada. Un silencio que puede significar dos cosas no
      // sirve para diagnosticar, y es lo que nos ha costado esta cadena.
      final mio = prov.torneos.where((x) => x.id == id).firstOrNull;
      envios.add(EnvioAlTorneo(mio?.nombre ?? id,
          enviado: true, motivo: 'es tu torneo: ya cuenta en tu tabla'));
      continue;
    }
    final seg = prov.seguidos.where((s) => s.torneoId == id).firstOrNull;
    if (seg == null) {
      // Pasa si dejé de seguirlo, o si la lista de seguidos no había cargado
      // cuando cerré. Las dos cosas tienen arreglo y ninguna se puede adivinar
      // desde una tabla en cero.
      envios.add(EnvioAlTorneo(id,
          enviado: false,
          motivo: 'no sigues ese torneo desde esta cuenta, o su lista no había '
              'cargado. Vuelve a abrir su enlace y ciérrala otra vez'));
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
          motivo: 'la referencia que guardaste no trae $falta. Ábrelo de nuevo '
              'desde su enlace'));
      continue;
    }
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
        jugadorId: yoJuego ? miFicha : '',
        resultado: resultado.toJson(),
      ));
      debugPrint('[Torneo] resultado de ${round.id} publicado a ${seg.nombre}');
      envios.add(EnvioAlTorneo(seg.nombre,
          enviado: true,
          // Enviado, pero con un matiz que hay que decir: si yo no juego en la
          // ronda, el organizador no puede acreditar mi nombre a ningún jugador
          // y su tabla contará la ronda sin darme nada.
          motivo: yoJuego
              ? null
              : 'tú no juegas en esta ronda, así que no te va a contar'));
    } catch (e) {
      debugPrint('[Torneo] no se pudo publicar a ${seg.nombre}: $e');
      envios.add(EnvioAlTorneo(seg.nombre,
          enviado: false,
          motivo: 'la escritura falló. Vuelve a cerrarla cuando haya conexión '
              '—no duplica— ($e)'));
    }
  }
  return envios;
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
  final envios = await _publicarASeguidos(context, round, torneoProv);
  if (envios.isNotEmpty && context.mounted) {
    // Se dice SIEMPRE, no solo cuando falla: "enviado" es la mitad del
    // diagnóstico. Sin ella, una tabla en cero no distingue "no salió" de "salió
    // y no lo cuentan", que son arreglos distintos.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(envios.map((e) => e.frase).join(' ')),
      duration: Duration(seconds: envios.any((e) => !e.enviado) ? 9 : 4),
    ));
  }

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
