// ─────────────────────────────────────────────────────────────────────────────
// EL CUADRO — a quién te toca, y por qué pasó el otro
//
// Un cuadro completo de ocho es difícil de leer en un teléfono, y la pregunta
// que trae a alguien a esta pantalla casi siempre es una sola: **a quién me
// toca**. Así que eso va arriba, con el botón de crear la ronda, y el cuadro
// entero debajo para quien quiera verlo.
//
// Nada de esto se guarda: el cuadro sale de llaveDe() con los resultados que
// PerfilProvider ya tiene. Corregir una ronda cambia el campeón sin que nadie
// recalcule nada.
//
// Lo que la pantalla NO hace: decidir un empate por su cuenta. Cuando dos quedan
// iguales el partido se queda a la vista, en ámbar, y alguien lo resuelve con un
// toque. La app no puede jugar un hoyo 19.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../models/torneo.dart';
import '../../providers/perfil_provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/torneo_provider.dart';
import '../../providers/user_profile_provider.dart';
import '../../services/user_profile_service.dart';
import '../../widgets/bracket_tree.dart';
import '../setup/setup_screen.dart';

/// El nombre para enseñar de un playerId.
///
/// Se busca en el directorio y, si no está, en lo que las rondas recuerdan. Un
/// id crudo en pantalla es peor que un nombre viejo.
String nombreDeJugador(BuildContext context, String pid) {
  final dir = context.read<PlayerProvider>().directory;
  final enDir = dir.where((x) => x.player.id == pid).firstOrNull;
  if (enDir != null) return enDir.displayName;
  for (final r in context.read<PerfilProvider>().resultados) {
    final n = r.playerNames[pid];
    if (n != null && n.isNotEmpty) return n;
  }
  return '—';
}

class LlaveDelTorneoVista extends StatelessWidget {
  final Torneo torneo;
  final LlaveDelTorneo llave;

  const LlaveDelTorneoVista(
      {super.key, required this.torneo, required this.llave});

  @override
  Widget build(BuildContext context) {
    final t = context.gt;

    if (llave.vacia) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.divider),
        ),
        child: Text(llave.motivo ?? 'Todavía no hay cuadro.',
            style: TextStyle(color: t.text, fontSize: 12.5, height: 1.4)),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (llave.campeon != null) _campeon(context, t),
      if (llave.pendientesDeDesempate.isNotEmpty) ...[
        _titulo('HAY QUE DESEMPATAR', t),
        for (final e in llave.pendientesDeDesempate) _tarjetaEmpate(context, t, e),
        const SizedBox(height: 16),
      ],
      if (llave.jugables.isNotEmpty) ...[
        _titulo('A QUIÉN LE TOCA', t),
        for (final e in llave.jugables) _tarjetaPendiente(context, t, e),
        const SizedBox(height: 16),
      ],
      _titulo('EL CUADRO', t),
      // El ÁRBOL, no la lista de fases. La lista se leía de un vistazo pero no
      // decía contra quién te podrías enfrentar, que es la mitad de para qué
      // existe un cuadro.
      //
      // El mismo widget que usa la vista de invitado, a través de una forma
      // neutra: dos dibujos del mismo cuadro habrían divergido en cuanto alguien
      // tocara uno.
      ArbolDeLlaveVista(
        arbol: _arbol(context, llave),
        t: t,
        // La identidad ya resuelta, la misma que usa la cifra héroe de Inicio.
        // Montar otra resolución habría dado dos respuestas a "cuál soy yo".
        miNombre: _miNombre(context),
      ),
    ]);
  }

  /// El cuadro en la forma que dibuja el árbol, con los nombres resueltos.
  ArbolDeLlave _arbol(BuildContext context, LlaveDelTorneo llave) {
    String? nom(String? pid) =>
        pid == null ? null : nombreDeJugador(context, pid);
    String? cifra(double? v) => v == null ? null : importeDelTorneo(v);

    return ArbolDeLlave(
      rondas: [
        for (final fase in llave.rondas)
          [
            for (final e in fase)
              NodoDeLlave(
                ronda: e.ronda,
                posicion: e.posicion,
                a: nom(e.a),
                b: nom(e.b),
                ganador: nom(e.ganador),
                bye: e.bye,
                empatado: e.empatado,
                desempatadoAMano: e.desempatadoAMano,
                nota: e.roundName,
                medidaA: torneo.metodo == MetodoDePuntuacion.dinero ||
                        torneo.metodo == MetodoDePuntuacion.posicion
                    ? cifra(e.medidaA)
                    : e.medidaA?.toStringAsFixed(0),
                medidaB: torneo.metodo == MetodoDePuntuacion.dinero ||
                        torneo.metodo == MetodoDePuntuacion.posicion
                    ? cifra(e.medidaB)
                    : e.medidaB?.toStringAsFixed(0),
              ),
          ],
      ],
      campeon: nom(llave.campeon),
      plazas: llave.plazas,
      byes: llave.byes,
    );
  }

  /// Mi nombre, para resaltar mi camino.
  ///
  /// Sale de la identidad que ya existe —la del tablero de Inicio— y no de una
  /// resolución nueva: dos respuestas a "cuál de estos soy yo" es exactamente el
  /// fallo que aquella identidad vino a arreglar.
  String? _miNombre(BuildContext context) {
    final mio = context.read<UserProfileProvider>().profile?.myPlayerId ??
        UserProfileService.miJugadorId;
    if (mio == null) return null;
    return nombreDeJugador(context, mio);
  }

  Widget _titulo(String txt, GolfTheme t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(txt,
            style: TextStyle(
                color: t.sub,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8)),
      );

  Widget _campeon(BuildContext context, GolfTheme t) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.primary),
        ),
        // Wrap y no Row: el nombre largo con la etiqueta al lado es el overflow
        // que ya salió tres veces en esta app.
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 4,
          children: [
            const Text('🏆', style: TextStyle(fontSize: 26)),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('CAMPEÓN', style: GolfType.label(t.sub)),
              Text(nombreDeJugador(context, llave.campeon!),
                  style: GolfType.title(t.text, size: 20)),
            ]),
          ],
        ),
      );

  /// Un partido que se puede jugar ya, con el atajo para crear la ronda.
  Widget _tarjetaPendiente(BuildContext context, GolfTheme t, Enfrentamiento e) {
    final na = nombreDeJugador(context, e.a!);
    final nb = nombreDeJugador(context, e.b!);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(nombreDeRondaDeLlave(llave.rondas[e.ronda].length),
            style: GolfType.label(t.sub)),
        const SizedBox(height: 4),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(na, style: GolfType.body(t.text)),
            Text('vs', style: TextStyle(color: t.sub, fontSize: 11)),
            Text(nb, style: GolfType.body(t.text)),
          ],
        ),
        const SizedBox(height: 10),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => SetupScreen(
                        partidoInicial: (
                          torneoId: torneo.id,
                          jugadores: [e.a!, e.b!],
                        ),
                      ))),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: t.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text('Crear la ronda de este partido',
                  style: TextStyle(
                      color: t.onPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
            'El otro entra a la MISMA ronda con el código en vivo. Si juegan '
            'cuatro, la ronda resuelve los dos partidos.',
            style: TextStyle(color: t.sub, fontSize: 11, height: 1.35)),
      ]),
    );
  }

  /// Un partido jugado que quedó igualado. Lo decide una persona.
  Widget _tarjetaEmpate(BuildContext context, GolfTheme t, Enfrentamiento e) {
    Future<void> resolver(String pid) async {
      final prov = context.read<TorneoProvider>();
      await prov.guardar(torneo.copyWith(desempates: {
        ...torneo.desempates,
        parKey(e.a!, e.b!): pid,
      }));
    }

    Widget boton(String pid) => Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => resolver(pid),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: t.divider),
              ),
              child: Center(
                child: Text('Pasa ${nombreDeJugador(context, pid)}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: t.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.scoreOver.withValues(alpha: 0.6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('EMPATE EN ${nombreDeRondaDeLlave(llave.rondas[e.ronda].length).toUpperCase()}',
            style: GolfType.label(t.sub)),
        const SizedBox(height: 4),
        Text(
            '${nombreDeJugador(context, e.a!)} y '
            '${nombreDeJugador(context, e.b!)} quedaron iguales en '
            '${e.roundName ?? "la ronda"}. La app no decide esto: lo decidís '
            'vosotros y aquí se apunta.',
            style: TextStyle(color: t.text, fontSize: 12, height: 1.4)),
        const SizedBox(height: 10),
        Row(children: [
          boton(e.a!),
          const SizedBox(width: 8),
          boton(e.b!),
        ]),
      ]),
    );
  }

}
