// ─────────────────────────────────────────────────────────────────────────────
// GRUPOS Y SALIDAS — el shotgun, y el botón que lo hace posible
//
// La última sección del portal, y la que decide si un torneo de 88 personas
// cabe en esta app: crear las veintidós rondas es UNA acción, no veintidós
// pasadas por el asistente de diez pasos.
//
// ── El reparto es automático Y a mano, en ese orden ─────────────────────────
//
// Con 150 personas, formar los grupos a mano no es una opción — son cuarenta
// decisiones antes de la primera. Pero un organizador siempre quiere mover a
// alguien: el que llegó tarde, los dos que vienen juntos, el socio al que le
// toca salir con el presidente.
//
// Así que el automático es el PUNTO DE PARTIDA y mover es lo normal, no la
// excepción. Y se mueve eligiendo destino, no arrastrando: arrastrar entre
// treinta y ocho grupos en una lista que se desplaza es la interacción que
// falla en el móvil, y el día del torneo el organizador tiene el teléfono en
// una mano y una hoja en la otra.
//
// ── Todo el cálculo está en shotgun.dart ────────────────────────────────────
//
// Aquí no se reparte nada ni se cuentan salidas. Esta pantalla elige el tamaño
// de grupo, enseña el plan, deja mover gente y llama al lote. El reparto de 150
// personas es aritmética con casos raros —cinco jugadores no se parten en
// grupos de tres o cuatro de ninguna forma— y eso se prueba sin pantalla.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ancho.dart';
import '../../core/app_theme.dart';
import '../../core/golf_icons.dart';
import '../../models/shotgun.dart';
import '../../models/torneo.dart';
import '../../providers/player_provider.dart';
import '../../services/live_round_service.dart';

class SalidasSeccion extends StatefulWidget {
  final Torneo torneo;
  final Ancho ancho;
  final GolfTheme t;
  const SalidasSeccion({
    super.key,
    required this.torneo,
    required this.ancho,
    required this.t,
  });

  @override
  State<SalidasSeccion> createState() => _SalidasSeccionState();
}

class _SalidasSeccionState extends State<SalidasSeccion> {
  int _tamano = 4;
  bool _dosEnPar3 = true;
  bool _creando = false;

  /// Los grupos ya tocados a mano. Null mientras el reparto sea el automático.
  ///
  /// Se guarda el resultado y no las mudanzas: el organizador ve lo que hay, no
  /// una lista de cambios. Y cambiar el tamaño de grupo VUELVE al automático,
  /// porque un reparto a mano sobre otro tamaño no significa nada.
  List<GrupoDeSalida>? _aMano;

  PlanDeShotgun _plan() {
    final base = planDeShotgun(
      padron: widget.torneo.participantes,
      campo: widget.torneo.campo,
      tamano: _tamano,
      dosEnPar3: _dosEnPar3,
    );
    final tocados = _aMano;
    if (tocados == null) return base;
    // El plan a mano conserva las salidas del automático y sus avisos: mover a
    // alguien no cambia cuántas salidas hay.
    return PlanDeShotgun(
      grupos: tocados,
      salidas: base.salidas,
      impedimento: base.impedimento,
      aviso: base.aviso,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final ancha = widget.ancho.esTabla;
    final plan = _plan();
    final nombres = context.watch<PlayerProvider>().nombres;

    return ListView(
      padding: EdgeInsets.fromLTRB(ancha ? 24 : 14, 16, ancha ? 24 : 14, 32),
      children: [
        Text(
            'Reparte el padrón en grupos y asigna cada uno a una salida. Al '
            'final, las rondas se crean todas de una vez.',
            style: TextStyle(color: t.sub, fontSize: 12.5, height: 1.4)),
        const SizedBox(height: 18),

        // ── El impedimento, arriba y con su número ──────────────────────────
        if (plan.impedimento != null) ...[
          _Nota(t: t, texto: plan.impedimento!, grave: true),
          const SizedBox(height: 14),
        ] else if (plan.aviso != null) ...[
          _Nota(t: t, texto: plan.aviso!, grave: false),
          const SizedBox(height: 14),
        ],

        _Etiqueta('TAMAÑO DE GRUPO', t: t),
        const SizedBox(height: 8),
        Row(children: [
          for (final n in [3, 4]) ...[
            Expanded(
              child: _Opcion(
                texto: '$n jugadores',
                elegida: _tamano == n,
                t: t,
                // Cambiar el tamaño descarta las mudanzas: ver _aMano.
                onTap: () => setState(() {
                  _tamano = n;
                  _aMano = null;
                }),
              ),
            ),
            if (n == 3) const SizedBox(width: 8),
          ],
        ]),
        const SizedBox(height: 12),

        _Interruptor(
          t: t,
          valor: _dosEnPar3,
          titulo: 'Dos salidas en los par 3',
          detalle: plan.salidas.isEmpty
              ? 'Sin hoyos cargados no se puede saber cuáles son par 3.'
              : '${plan.salidas.length} salidas con esta opción. '
                  '${plan.grupos.length} grupo'
                  '${plan.grupos.length == 1 ? '' : 's'} que colocar.',
          onCambio: (v) => setState(() {
            _dosEnPar3 = v;
            _aMano = null;
          }),
        ),
        const SizedBox(height: 22),

        _Etiqueta('LOS GRUPOS', t: t),
        const SizedBox(height: 4),
        Text('Toca un jugador para moverlo a otro grupo.',
            style: TextStyle(color: t.sub, fontSize: 11.5)),
        const SizedBox(height: 8),
        if (plan.grupos.isEmpty)
          Text('Nada que repartir todavía.',
              style: TextStyle(color: t.sub, fontSize: 12))
        else
          for (var i = 0; i < plan.grupos.length; i++)
            _Grupo(
              indice: i,
              grupo: plan.grupos[i],
              nombres: nombres,
              t: t,
              onMover: (pid) => _mover(plan, pid),
            ),

        const SizedBox(height: 22),
        // ── EL BOTÓN: una acción, no veintidós ─────────────────────────────
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: !plan.utilizable || _creando ? null : () => _crear(plan),
            style: FilledButton.styleFrom(
                backgroundColor: t.primary,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            icon: Icon(_creando ? GolfIcons.arrastra : GolfIcons.bandera,
                size: GolfIcons.juntoAValor),
            label: Text(_creando
                ? 'Creando…'
                : 'Crear ${plan.grupos.length} ronda'
                    '${plan.grupos.length == 1 ? '' : 's'}'),
          ),
        ),
        const SizedBox(height: 8),
        Text(
            'Se crean como tus rondas, así que aparecen en Scores en vivo y '
            'puedes capturar y corregir desde ahí. Volver a darle al botón las '
            'actualiza; no las duplica.',
            style: TextStyle(color: t.sub, fontSize: 11.5, height: 1.35)),
      ],
    );
  }

  Future<void> _mover(PlanDeShotgun plan, String pid) async {
    final t = widget.t;
    final nombres = context.read<PlayerProvider>().nombres;
    final destino = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: t.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          children: [
            Text('Mover a ${nombres[pid] ?? pid}',
                style: GolfType.title(t.text)),
            const SizedBox(height: 10),
            for (var i = 0; i < plan.grupos.length; i++)
              if (!plan.grupos[i].jugadores.contains(pid))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                      plan.grupos[i].salida?.etiqueta ?? 'Grupo ${i + 1}',
                      style: GolfType.value(t.text)),
                  subtitle: Text(
                      '${plan.grupos[i].jugadores.length} jugador'
                      '${plan.grupos[i].jugadores.length == 1 ? '' : 'es'}',
                      style: GolfType.label(t.sub)),
                  onTap: () => Navigator.pop(ctx, i),
                ),
          ],
        ),
      ),
    );
    if (destino == null || !mounted) return;
    setState(() => _aMano = moviendo(plan.grupos, pid, destino));
  }

  Future<void> _crear(PlanDeShotgun plan) async {
    final campo = widget.torneo.campo;
    if (campo == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final directorio = context.read<PlayerProvider>().directory;
    final porId = {for (final pw in directorio) pw.player.id: pw.player};
    final handicaps = {
      for (final pw in directorio) pw.player.id: pw.player.handicapBase,
    };

    final rondas = rondasDelPlan(
      plan: plan,
      torneoId: widget.torneo.id,
      campo: campo,
      porId: porId,
      cuando: DateTime.now(),
      // La ventaja del torneo decide si el handicap entra: con "sin ventaja"
      // meterlo aquí daría golpes que el torneo dijo que no se dan.
      handicaps: widget.torneo.ventaja == VentajaDeTorneo.handicap
          ? handicaps
          : const {},
    );

    setState(() => _creando = true);
    final hechas = await LiveRoundService.publicarPorLotes(rondas);
    if (!mounted) return;
    setState(() => _creando = false);
    messenger.showSnackBar(SnackBar(
      content: Text(hechas == null
          // Todo o nada: si falló, no hay grupos a medias que buscar.
          ? 'No se creó ninguna ronda. No quedó nada a medias: vuelve a '
              'intentarlo.'
          : '$hechas ronda${hechas == 1 ? '' : 's'} creada'
              '${hechas == 1 ? '' : 's'}. Ya salen en Scores en vivo.'),
      duration: const Duration(seconds: 5),
    ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PIEZAS
// ─────────────────────────────────────────────────────────────────────────────
class _Grupo extends StatelessWidget {
  final int indice;
  final GrupoDeSalida grupo;
  final Map<String, String> nombres;
  final GolfTheme t;
  final void Function(String) onMover;
  const _Grupo({
    required this.indice,
    required this.grupo,
    required this.nombres,
    required this.t,
    required this.onMover,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                // Un grupo sin salida se marca: es el que sobra, y el motivo
                // de arriba dice cuántos son.
                color: grupo.salida == null ? t.loss : t.divider),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              // La SALIDA como título, no "Grupo 14": es lo que se canta por
              // megafonía y lo que el jugador busca.
              Text(grupo.salida?.etiqueta ?? 'Sin salida',
                  style: GolfType.value(
                      grupo.salida == null ? t.loss : t.primary)),
              const Spacer(),
              Text('${grupo.jugadores.length}', style: GolfType.label(t.sub)),
            ]),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final pid in grupo.jugadores)
                  InkWell(
                    onTap: () => onMover(pid),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: t.card,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: t.divider),
                      ),
                      child: Text(nombres[pid] ?? pid,
                          style: GolfType.label(t.text)),
                    ),
                  ),
              ],
            ),
          ]),
        ),
      );
}

class _Nota extends StatelessWidget {
  final GolfTheme t;
  final String texto;
  final bool grave;
  const _Nota({required this.t, required this.texto, required this.grave});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: (grave ? t.loss : t.sub).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: (grave ? t.loss : t.divider).withValues(alpha: 0.5)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(grave ? GolfIcons.aviso : GolfIcons.equilibrio,
              size: GolfIcons.juntoAValor, color: grave ? t.loss : t.sub),
          const SizedBox(width: 9),
          Expanded(
            child: Text(texto,
                style: TextStyle(
                    color: grave ? t.text : t.sub,
                    fontSize: 12.5,
                    height: 1.4)),
          ),
        ]),
      );
}

class _Opcion extends StatelessWidget {
  final String texto;
  final bool elegida;
  final GolfTheme t;
  final VoidCallback onTap;
  const _Opcion({
    required this.texto,
    required this.elegida,
    required this.t,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: elegida ? t.primary.withValues(alpha: 0.10) : t.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: elegida ? t.primary : t.divider,
                width: elegida ? 1.5 : 1),
          ),
          child: Text(texto,
              style: GolfType.value(elegida ? t.primary : t.text)),
        ),
      );
}

class _Interruptor extends StatelessWidget {
  final GolfTheme t;
  final bool valor;
  final String titulo;
  final String detalle;
  final ValueChanged<bool> onCambio;
  const _Interruptor({
    required this.t,
    required this.valor,
    required this.titulo,
    required this.detalle,
    required this.onCambio,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.divider),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo, style: GolfType.value(t.text)),
              Text(detalle, style: GolfType.label(t.sub)),
            ]),
          ),
          Switch(value: valor, onChanged: onCambio, activeThumbColor: t.primary),
        ]),
      );
}

class _Etiqueta extends StatelessWidget {
  final String texto;
  final GolfTheme t;
  const _Etiqueta(this.texto, {required this.t});
  @override
  Widget build(BuildContext context) =>
      Text(texto, style: GolfType.label(t.sub));
}
