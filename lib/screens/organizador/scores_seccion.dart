// ─────────────────────────────────────────────────────────────────────────────
// SCORES EN VIVO — el torneo entero, y lo que de verdad se puede ver
//
// ── QUÉ SE PUEDE LEER, Y POR QUÉ NO SE AÑADE NINGUNA REGLA ──────────────────
//
// Es la primera sección del portal que quiere datos de OTRAS CUENTAS, así que
// lo primero fue mirar qué conceden las reglas de hoy:
//
//   · liveRounds  → lee quien está en `participantUids` o es `ownerUid`
//   · torneoResultados → lee el `torneoOwnerUid`, o sea el organizador
//
// De ahí sale la frontera, y no de una decisión de diseño:
//
//   LO QUE SÍ, en vivo y hoyo a hoyo: las rondas que el organizador MONTÓ. En
//   un shotgun son todas —él arma los grupos—, y son las que puede corregir.
//
//   LO QUE NO: las rondas en vivo de otras cuentas. De esas se ve lo ÚLTIMO
//   QUE PUBLICARON al cerrar, que es un hecho con fecha, no un directo.
//
// ── Y por qué no se amplía la regla ─────────────────────────────────────────
//
// Se miraron las dos formas de conseguirlo y las dos dan de más:
//
//   1 · Meter al organizador en `participantUids` de las rondas marcadas para
//       su torneo. La regla de liveRounds es `allow read, update` JUNTAS: le
//       daría permiso de ESCRIBIR en la ronda de cualquiera que marque una
//       ronda para su torneo. Y la escribiría el dueño de la ronda, que no
//       tiene por qué conocer el uid del organizador.
//
//   2 · Una regla nueva del tipo "lee si `torneoIds` contiene un torneo tuyo".
//       Los torneos viven en `users/{uid}/torneos/{id}`, así que haría falta un
//       `get()` cruzado POR DOCUMENTO — y un `get()` dentro de una regla de
//       `list` no se puede acotar: la consulta entera pasa o falla, y cada
//       documento candidato cuesta una lectura.
//
// Con tres colecciones en el historial donde un `read` concedía un `list` que
// nadie usaba —sharedTorneos, players, userLookup—, ampliar aquí es exactamente
// el movimiento que este proyecto ya pagó tres veces.
//
// ── Y la pantalla lo DICE ───────────────────────────────────────────────────
//
// Es lo mismo que se decidió con el "Thru": mejor decir qué se está viendo que
// prometer tiempo real y enseñar algo de hace dos horas. Las dos listas van
// separadas y cada una con su fecha.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import '../../core/ancho.dart';
import '../../core/app_theme.dart';
import '../../core/golf_icons.dart';
import '../../models/correccion_de_score.dart';
import '../../models/models.dart';
import '../../models/torneo.dart';
import '../../services/auth_service.dart';
import '../../services/live_round_service.dart';

class ScoresSeccion extends StatefulWidget {
  final Torneo torneo;
  final Ancho ancho;
  final GolfTheme t;

  /// Lo que publicaron OTRAS cuentas al cerrar. Llega cargado del portal.
  final List<ResultadoPublicado> publicados;

  const ScoresSeccion({
    super.key,
    required this.torneo,
    required this.ancho,
    required this.t,
    required this.publicados,
  });

  @override
  State<ScoresSeccion> createState() => _ScoresSeccionState();
}

class _ScoresSeccionState extends State<ScoresSeccion> {
  List<GrupoDelTorneo>? _grupos;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final g = await LiveRoundService.gruposDelTorneo(widget.torneo.id);
    if (mounted) setState(() => _grupos = g);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final ancha = widget.ancho.esTabla;
    final grupos = _grupos;
    final ajenos = widget.publicados;

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: EdgeInsets.fromLTRB(ancha ? 24 : 14, 16, ancha ? 24 : 14, 32),
        children: [
          // ── LA VERDAD, ARRIBA ──────────────────────────────────────────
          //
          // Antes de cualquier número. Quien abre esto el día del torneo tiene
          // que saber en la primera frase qué está mirando.
          _Aviso(
            t: t,
            texto: grupos == null
                ? 'Cargando los grupos del torneo…'
                : 'Los grupos que montaste se ven EN VIVO y puedes corregirlos. '
                    'Las rondas que llevan otras cuentas se ven cuando las '
                    'cierran: de esas se enseña lo último que publicaron, con '
                    'su fecha.',
          ),
          const SizedBox(height: 18),

          _Etiqueta('TUS GRUPOS · EN VIVO', t: t),
          const SizedBox(height: 8),
          if (grupos == null)
            _Vacio(t: t, texto: 'Cargando…')
          else if (grupos.isEmpty)
            _Vacio(
                t: t,
                texto: 'Todavía no has montado ningún grupo de este torneo. '
                    'Los grupos que crees desde el torneo aparecen aquí, en '
                    'vivo y corregibles.')
          else
            for (final g in grupos)
              _FilaDeGrupo(
                grupo: g,
                t: t,
                onTap: () => _abrirTarjeta(g),
              ),

          const SizedBox(height: 22),
          _Etiqueta('DE OTRAS CUENTAS · AL CERRAR', t: t),
          const SizedBox(height: 8),
          if (ajenos.isEmpty)
            _Vacio(
                t: t,
                texto: 'Nadie de fuera ha cerrado todavía una ronda de este '
                    'torneo.')
          else
            for (final r in ajenos) _FilaAjena(publicado: r, t: t),
        ],
      ),
    );
  }

  Future<void> _abrirTarjeta(GrupoDelTorneo g) async {
    final messenger = ScaffoldMessenger.of(context);
    final ronda = await LiveRoundService.cargarRondaEnVivo(g.roundId);
    if (!mounted) return;
    if (ronda == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text('No se pudo abrir esa ronda. Recarga y vuelve a '
              'intentarlo.')));
      return;
    }
    final cambiada = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: widget.t.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _HojaDeTarjeta(ronda: ronda, t: widget.t),
    );
    if (cambiada == true) await _cargar();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LA TARJETA, CON CORRECCIÓN
// ─────────────────────────────────────────────────────────────────────────────
class _HojaDeTarjeta extends StatefulWidget {
  final Round ronda;
  final GolfTheme t;
  const _HojaDeTarjeta({required this.ronda, required this.t});

  @override
  State<_HojaDeTarjeta> createState() => _HojaDeTarjetaState();
}

class _HojaDeTarjetaState extends State<_HojaDeTarjeta> {
  late Round _r = widget.ronda;
  bool _guardando = false;
  bool _cambiada = false;

  Future<void> _corregir(Player jugador, int hoyo) async {
    final actual = _r.scores[jugador.id]?[hoyo]?.grossScore;
    final nuevo = await _pedirScore(context, widget.t, jugador, hoyo, actual);
    // null = canceló. El "borrar" viaja como un (true, null).
    if (nuevo == null || !mounted) return;

    final r2 = conCorreccion(
      _r,
      jugadorId: jugador.id,
      hoyo: hoyo,
      nuevo: nuevo.$1,
      porUid: AuthService.uid ?? '',
      // Quien corrige, con el nombre que tiene HOY: la corrección es un hecho
      // pasado y guarda el nombre de cuando pasó. Ver correccion_de_score.dart.
      porNombre: AuthService.currentUser?.displayName ?? 'El organizador',
      cuando: DateTime.now(),
    );
    if (identical(r2, _r)) return; // No cambió nada: no se anota ruido.

    setState(() => _guardando = true);
    final ok = await LiveRoundService.guardarCorregida(r2);
    if (!mounted) return;
    setState(() {
      _guardando = false;
      if (ok) {
        _r = r2;
        _cambiada = true;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? 'Corregido. Queda anotado quién lo cambió.'
            : 'No se pudo guardar la corrección. El score sigue como estaba.')));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final hoyos = List.generate(_r.totalHoles, (i) => i + 1);
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 14),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: t.divider, borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: Text(_r.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GolfType.title(t.text)),
            ),
            if (_guardando)
              SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: t.primary)),
          ]),
          const SizedBox(height: 2),
          Text('Toca un score para corregirlo. Queda anotado quién lo hizo.',
              style: TextStyle(color: t.sub, fontSize: 12)),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(children: [
              // La rejilla: una fila por jugador, una columna por hoyo. Se
              // desplaza en horizontal dentro de su caja, no la pantalla.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        SizedBox(width: 108, child: Text('', style: GolfType.label(t.sub))),
                        for (final h in hoyos)
                          SizedBox(
                            width: 34,
                            child: Text('$h',
                                textAlign: TextAlign.center,
                                style: GolfType.label(t.sub)),
                          ),
                      ]),
                      const SizedBox(height: 4),
                      for (final p in _r.realPlayers)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(children: [
                            SizedBox(
                              width: 108,
                              child: Text(p.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GolfType.value(t.text)),
                            ),
                            for (final h in hoyos)
                              _Casilla(
                                score: _r.scores[p.id]?[h]?.grossScore,
                                par: _r.course.holes
                                    .where((x) => x.hole == h)
                                    .map((x) => x.par)
                                    .firstOrNull,
                                t: t,
                                onTap:
                                    _guardando ? null : () => _corregir(p, h),
                              ),
                          ]),
                        ),
                    ]),
              ),
              if (_r.correcciones.isNotEmpty) ...[
                const SizedBox(height: 20),
                _Etiqueta('CORRECCIONES', t: t),
                const SizedBox(height: 6),
                // Las más recientes arriba: al mirar esto se busca la última.
                for (final c in _r.correcciones.reversed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(GolfIcons.arrastra,
                              size: GolfIcons.juntoAEtiqueta, color: t.sub),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c.frase, style: GolfType.value(t.text)),
                                  Text(
                                      '${c.porNombre} · '
                                      '${_cuando(c.cuando)}',
                                      style: GolfType.label(t.sub)),
                                ]),
                          ),
                        ]),
                  ),
              ],
              const SizedBox(height: 24),
            ]),
          ),
          SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context, _cambiada),
                style: TextButton.styleFrom(foregroundColor: t.sub),
                child: const Text('Cerrar'),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  static String _cuando(DateTime d) =>
      '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

/// Pide el score nuevo. Devuelve null si se cancela, `(valor,)` si se acepta.
///
/// El registro `(int?,)` distingue lo que un `int?` solo no puede: cancelar y
/// borrar el score son dos cosas y las dos serían null.
Future<(int?,)?> _pedirScore(
    BuildContext context, GolfTheme t, Player p, int hoyo, int? actual) async {
  final ctrl = TextEditingController(text: actual?.toString() ?? '');
  return showDialog<(int?,)?>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: t.card,
      title: Text('${p.name} · hoyo $hoyo', style: GolfType.title(t.text)),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        style: TextStyle(color: t.text),
        decoration: InputDecoration(
          labelText: 'Golpes',
          labelStyle: TextStyle(color: t.sub),
          helperText: actual == null ? 'Este hoyo está vacío' : 'Ahora: $actual',
          helperStyle: TextStyle(color: t.sub),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('Cancelar', style: TextStyle(color: t.sub)),
        ),
        if (actual != null)
          TextButton(
            onPressed: () => Navigator.pop(ctx, (null,)),
            child: Text('Borrar', style: TextStyle(color: t.loss)),
          ),
        TextButton(
          onPressed: () {
            final v = int.tryParse(ctrl.text.trim());
            // Fuera de rango no se guarda: un 0 o un 30 en un hoyo es un dedo,
            // no un score, y corregirlo mal es peor que no corregirlo.
            if (v == null || v < 1 || v > 20) {
              Navigator.pop(ctx);
              return;
            }
            Navigator.pop(ctx, (v,));
          },
          child: Text('Guardar', style: TextStyle(color: t.primary)),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// PIEZAS
// ─────────────────────────────────────────────────────────────────────────────
class _Casilla extends StatelessWidget {
  final int? score;
  final int? par;
  final GolfTheme t;
  final VoidCallback? onTap;
  const _Casilla({
    required this.score,
    required this.par,
    required this.t,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // El color dice la relación con el par, que es como se lee una tarjeta.
    // El hueco NO es cero: es "todavía no", y por eso va en el token de dato
    // ausente y no en el de resultado.
    final Color color;
    if (score == null || par == null) {
      color = t.sub;
    } else if (score! < par!) {
      color = t.profit;
    } else if (score! > par!) {
      color = t.loss;
    } else {
      color = t.text;
    }
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 30,
        alignment: Alignment.center,
        margin: const EdgeInsets.only(right: 1),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: t.divider),
        ),
        child: Text(score?.toString() ?? '·',
            style: GolfType.value(color)),
      ),
    );
  }
}

class _FilaDeGrupo extends StatelessWidget {
  final GrupoDelTorneo grupo;
  final GolfTheme t;
  final VoidCallback onTap;
  const _FilaDeGrupo(
      {required this.grupo, required this.t, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final falta = grupo.totalHoles - grupo.hoyosCapturados;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(children: [
              Icon(grupo.cerrada ? GolfIcons.bien : GolfIcons.golpe,
                  size: GolfIcons.juntoAValor,
                  color: grupo.cerrada ? t.primary : t.sub),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(grupo.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GolfType.value(t.text)),
                      Text(grupo.jugadores.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GolfType.label(t.sub)),
                    ]),
              ),
              const SizedBox(width: 8),
              // Por qué hoyo va: es LA pregunta del organizador, y aquí sí se
              // puede contestar porque la ronda es suya y se lee entera.
              Text(
                  grupo.cerrada
                      ? 'Cerrada'
                      : falta <= 0
                          ? 'Sin cerrar'
                          : 'Van ${grupo.hoyosCapturados}/${grupo.totalHoles}',
                  style: GolfType.label(grupo.cerrada ? t.primary : t.sub)),
              Icon(Icons.chevron_right, size: 18, color: t.sub),
            ]),
          ),
        ),
      ),
    );
  }
}

class _FilaAjena extends StatelessWidget {
  final ResultadoPublicado publicado;
  final GolfTheme t;
  const _FilaAjena({required this.publicado, required this.t});

  @override
  Widget build(BuildContext context) {
    final r = publicado.resultado;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.divider),
        ),
        child: Row(children: [
          Icon(GolfIcons.cerrado, size: GolfIcons.juntoAValor, color: t.sub),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.roundName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GolfType.value(t.text)),
                  Text(
                      '${publicado.jugadorNombre} · '
                      '${r.playerIds.length} jugador'
                      '${r.playerIds.length == 1 ? '' : 'es'}',
                      style: GolfType.label(t.sub)),
                ]),
          ),
          // La FECHA, siempre. Es lo que separa esto de un directo.
          Text('${r.playedAt.day}/${r.playedAt.month}',
              style: GolfType.label(t.sub)),
        ]),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final GolfTheme t;
  final String texto;
  const _Aviso({required this.t, required this.texto});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.divider),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(GolfIcons.pantalla,
              size: GolfIcons.juntoAValor, color: t.sub),
          const SizedBox(width: 9),
          Expanded(
            child: Text(texto,
                style: TextStyle(color: t.sub, fontSize: 12.5, height: 1.4)),
          ),
        ]),
      );
}

class _Etiqueta extends StatelessWidget {
  final String texto;
  final GolfTheme t;
  const _Etiqueta(this.texto, {required this.t});
  @override
  Widget build(BuildContext context) => Text(texto, style: GolfType.label(t.sub));
}

class _Vacio extends StatelessWidget {
  final GolfTheme t;
  final String texto;
  const _Vacio({required this.t, required this.texto});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(texto,
            style: TextStyle(color: t.sub, fontSize: 12, height: 1.35)),
      );
}
