// ─────────────────────────────────────────────────────────────────────────────
// TORNEOS — la lista y la tabla
//
// La tabla no se guarda nunca: se llama a tablaDe() con los resultados que
// PerfilProvider ya tiene en memoria. Si una ronda cambia, la siguiente vez sale
// distinta sin que nadie recalcule nada. Es la lección del RoundResult
// desfasado: lo guardado se queda viejo en silencio.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../models/torneo.dart';
import '../../providers/perfil_provider.dart';
import '../../providers/torneo_provider.dart';
import 'torneo_editor_screen.dart';

String importePuntos(double v) {
  final s = v.abs().toStringAsFixed(v == v.roundToDouble() ? 0 : 1);
  if (v > 0.005) return '+$s';
  if (v < -0.005) return '−$s';
  return '0';
}

class TorneosScreen extends StatelessWidget {
  const TorneosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.gt;
    final prov = context.watch<TorneoProvider>();

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        foregroundColor: t.text,
        title: const Text('Torneos'),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: t.primary,
        foregroundColor: t.onPrimary,
        onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const TorneoEditorScreen(existente: null))),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo torneo'),
      ),
      body: prov.torneos.isEmpty
          ? _vacio(t)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
              children: [
                for (final tor in prov.torneos)
                  _TarjetaTorneo(torneo: tor, t: t),
              ],
            ),
    );
  }

  Widget _vacio(GolfTheme t) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🏆', style: TextStyle(fontSize: 44)),
              const SizedBox(height: 12),
              Text('Ningún torneo todavía',
                  style: TextStyle(
                      color: t.text, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                  'Un torneo no cambia cómo se juega: es una vista sobre las '
                  'rondas que ya tienes. Eliges cuáles cuentan y cómo puntúan.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.sub, fontSize: 13, height: 1.45)),
            ],
          ),
        ),
      );
}

class _TarjetaTorneo extends StatelessWidget {
  final Torneo torneo;
  final GolfTheme t;
  const _TarjetaTorneo({required this.torneo, required this.t});

  @override
  Widget build(BuildContext context) {
    final resultados = context.watch<PerfilProvider>().resultados;
    final tabla = tablaDe(torneo, resultados);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: t.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => TorneoTablaScreen(torneo: torneo))),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Text(torneo.emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(torneo.nombre,
                          style: TextStyle(
                              color: t.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                      Text(
                          '${tabla.rondas} ronda${tabla.rondas == 1 ? '' : 's'} · '
                          '${torneo.metodo.label}'
                          '${torneo.acumulacion == Acumulacion.mejoresDeN ? ' · mejores ${torneo.mejoresN}' : ''}',
                          style: TextStyle(color: t.sub, fontSize: 11.5)),
                      if (tabla.filas.isNotEmpty)
                        Text('Va ${tabla.filas.first.nombre}',
                            style: TextStyle(
                                color: t.primary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700)),
                      // Lo que el método no pudo puntuar se dice AQUÍ también:
                      // una tabla corta, desde fuera, parece completa.
                      if (tabla.rondasSinDato > 0)
                        Text(
                            '${tabla.rondasSinDato} sin el dato que pide este '
                            'método',
                            style: TextStyle(
                                color: t.scoreOver.withValues(alpha: 0.9),
                                fontSize: 10.5)),
                    ]),
              ),
              Icon(Icons.chevron_right_rounded, color: t.sub),
            ]),
          ),
        ),
      ),
    );
  }
}

class TorneoTablaScreen extends StatelessWidget {
  final Torneo torneo;
  const TorneoTablaScreen({super.key, required this.torneo});

  @override
  Widget build(BuildContext context) {
    final t = context.gt;
    final resultados = context.watch<PerfilProvider>().resultados;
    final tabla = tablaDe(torneo, resultados);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        foregroundColor: t.text,
        title: Text('${torneo.emoji} ${torneo.nombre}'),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.tune, color: t.sub),
            tooltip: 'Editar el torneo',
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => TorneoEditorScreen(existente: torneo))),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Las reglas a la vista. Una tabla sin ellas invita a discutir el
          // número en vez de la regla.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.divider),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CÓMO SE PUNTÚA',
                      style: TextStyle(
                          color: t.sub,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8)),
                  const SizedBox(height: 6),
                  Text(torneo.metodo.descripcion,
                      style: TextStyle(
                          color: t.text, fontSize: 12.5, height: 1.35)),
                  if (torneo.metodo == MetodoDePuntuacion.posicion) ...[
                    const SizedBox(height: 4),
                    Text(
                        'Puntos: ${torneo.puntosPorPuesto.join(' · ')}'
                        '   ·   Empates: ${torneo.empate.label.toLowerCase()}',
                        style: TextStyle(color: t.sub, fontSize: 11.5)),
                  ],
                  const SizedBox(height: 4),
                  Text(
                      torneo.acumulacion == Acumulacion.mejoresDeN
                          ? 'Solo cuentan las ${torneo.mejoresN} mejores de cada uno.'
                          : 'Suman todas las rondas.',
                      style: TextStyle(color: t.sub, fontSize: 11.5)),
                  if (torneo.minimoRondas > 0)
                    Text(
                        'Hacen falta ${torneo.minimoRondas} rondas para clasificar.',
                        style: TextStyle(color: t.sub, fontSize: 11.5)),
                  if (tabla.rondasSinDato > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                        '${tabla.rondasSinDato} ronda'
                        '${tabla.rondasSinDato == 1 ? '' : 's'} del torneo no '
                        'tiene${tabla.rondasSinDato == 1 ? '' : 'n'} el dato que '
                        'este método necesita, así que no cuenta'
                        '${tabla.rondasSinDato == 1 ? '' : 'n'}. Recalcula el '
                        'histórico en el Historial para incluirlas.',
                        style: TextStyle(
                            color: t.scoreOver.withValues(alpha: 0.95),
                            fontSize: 11.5,
                            height: 1.35)),
                  ],
                ]),
          ),
          const SizedBox(height: 14),

          if (tabla.vacia)
            Text(
                'Todavía no hay rondas en este torneo. Cuando cierres una que '
                'entre en la fuente elegida, aparecerá aquí.',
                style: TextStyle(color: t.sub, fontSize: 13, height: 1.4))
          else ...[
            for (final fila in tabla.filas)
              _Fila(fila: fila, torneo: torneo, t: t),
            if (tabla.bajoMinimo.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('SIN EL MÍNIMO DE RONDAS',
                  style: TextStyle(
                      color: t.sub,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8)),
              const SizedBox(height: 4),
              // Aparte, no escondidos: quien jugó dos rondas quiere ver sus dos
              // rondas.
              Text('No clasifican, pero su cuenta está aquí.',
                  style: TextStyle(color: t.sub, fontSize: 11.5)),
              const SizedBox(height: 8),
              for (final fila in tabla.bajoMinimo)
                _Fila(fila: fila, torneo: torneo, t: t),
            ],
          ],
        ],
      ),
    );
  }
}

class _Fila extends StatefulWidget {
  final FilaDelTorneo fila;
  final Torneo torneo;
  final GolfTheme t;
  const _Fila({required this.fila, required this.torneo, required this.t});

  @override
  State<_Fila> createState() => _FilaState();
}

class _FilaState extends State<_Fila> {
  bool _abierta = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final f = widget.fila;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: f.puesto == 1 && !f.bajoMinimo ? t.primary : t.divider),
        ),
        child: Column(children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _abierta = !_abierta),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(children: [
                SizedBox(
                  width: 26,
                  child: Text('${f.puesto}',
                      style: TextStyle(
                          color: f.puesto == 1 ? t.primary : t.sub,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.nombre,
                            style: TextStyle(
                                color: t.text,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700)),
                        Text(
                            widget.torneo.acumulacion == Acumulacion.mejoresDeN
                                ? '${f.contadas} de ${f.jugadas} rondas cuentan'
                                : '${f.jugadas} ronda${f.jugadas == 1 ? '' : 's'}',
                            style: TextStyle(color: t.sub, fontSize: 11)),
                      ]),
                ),
                Text(importePuntos(f.total),
                    style: TextStyle(
                        color: t.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(width: 6),
                Icon(_abierta ? Icons.expand_less : Icons.expand_more,
                    color: t.sub, size: 18),
              ]),
            ),
          ),
          if (_abierta) ...[
            Divider(color: t.divider, height: 1),
            for (final r in f.rondas)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(children: [
                  Expanded(
                    child: Text(
                        '${r.fecha.day}/${r.fecha.month} · ${r.nombreRonda}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: r.cuenta ? t.text : t.sub, fontSize: 12)),
                  ),
                  if (r.puesto != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text('${r.puesto}º',
                          style: TextStyle(color: t.sub, fontSize: 11)),
                    ),
                  Text(importePuntos(r.puntos),
                      style: TextStyle(
                          color: r.cuenta ? t.text : t.sub,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          // Tachado y no solo apagado: el color solo sería
                          // invisible en escala de grises.
                          decoration:
                              r.cuenta ? null : TextDecoration.lineThrough,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ]),
              ),
            const SizedBox(height: 6),
          ],
        ]),
      ),
    );
  }
}
