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
                      if (tabla.sinListaDeParticipantes)
                        Text('Sin lista de participantes · el bote no se calcula',
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

          // ── Sin lista de participantes ─────────────────────────────
          //
          // Va arriba de todo y con el número: la tabla que se ve debajo NO es
          // el torneo que se cree, y el bote no se está calculando. Enterarse al
          // entrar a editar sería tarde.
          if (motivoSinLista(torneo, tabla) != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.scoreOver.withValues(alpha: 0.6)),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('FALTA LA LISTA DE PARTICIPANTES',
                        style: TextStyle(
                            color: t.sub,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8)),
                    const SizedBox(height: 6),
                    Text(motivoSinLista(torneo, tabla)!,
                        style: TextStyle(
                            color: t.text, fontSize: 12, height: 1.4)),
                    const SizedBox(height: 6),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  TorneoEditorScreen(existente: torneo))),
                      child: Text('Definir participantes',
                          style: TextStyle(
                              color: t.primary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800)),
                    ),
                  ]),
            ),
            const SizedBox(height: 14),
          ],

          // ── Nombres que aparecen dos veces ─────────────────────────
          //
          // Se DICE, no se fusiona: dos personas pueden llamarse igual y
          // sumarlas en una fila sin que nadie lo pidiera sería peor. Decidir
          // que son la misma persona toca el directorio, que no es cosa de una
          // tabla de torneo.
          if (tabla.nombresDuplicados.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.scoreOver.withValues(alpha: 0.5)),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('DOS FILAS CON EL MISMO NOMBRE',
                        style: TextStyle(
                            color: t.sub,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8)),
                    const SizedBox(height: 6),
                    Text(
                        '${tabla.nombresDuplicados.keys.join(', ')} '
                        '${tabla.nombresDuplicados.length == 1 ? 'aparece' : 'aparecen'} '
                        'con más de una ficha. Suele pasar cuando alguien se '
                        'creó a mano en una ronda y en otra se usó el del '
                        'directorio: son dos jugadores distintos para la app, y '
                        'la temporada los cuenta por separado.',
                        style: TextStyle(
                            color: t.text, fontSize: 12, height: 1.4)),
                    const SizedBox(height: 4),
                    Text(
                        'No se fusionan solos: dos personas pueden llamarse '
                        'igual. Únelos desde el directorio de jugadores si son '
                        'la misma.',
                        style: TextStyle(
                            color: t.sub,
                            fontSize: 11,
                            fontStyle: FontStyle.italic)),
                  ]),
            ),
            const SizedBox(height: 14),
          ],

          // ── El bote del día ────────────────────────────────────────
          //
          // Va ANTES del final y con su propio total. Este ya está cobrado —esa
          // ronda se cerró— y el final es una expectativa. No se suman.
          if (torneo.bote.hayBoteJornada) ...[
            _BloqueJornadas(
                torneo: torneo,
                jornadas: botesPorJornada(torneo, tabla),
                t: t),
            const SizedBox(height: 14),
          ],

          // ── El bote ────────────────────────────────────────────────
          //
          // Su propio total, separado del balance de las rondas. Una está
          // cobrada y el otro es una expectativa mientras el torneo esté
          // abierto: una cifra que las junte no significa nada.
          if (torneo.bote.hayBote) ...[
            _BloqueBote(torneo: torneo, bote: boteDe(torneo, tabla), t: t),
            const SizedBox(height: 14),
          ],

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

// ── El bote ──────────────────────────────────────────────────────────────────
//
// LA APP NO PROCESA PAGOS: esto es una cuenta, no un cobro. No hay botón de
// pagar, no hay estado "pagado", no hay saldo. Hay quién puso, quién cobra y si
// el reparto ya es definitivo. La razón está escrita en torneo.dart, donde se
// decide.
//
// Y va con su propio total, nunca sumado al balance de las rondas: el dinero de
// un sábado está cobrado y el bote es una expectativa mientras el torneo esté
// abierto.
class _BloqueBote extends StatelessWidget {
  final Torneo torneo;
  final BoteDelTorneo bote;
  final GolfTheme t;
  const _BloqueBote(
      {required this.torneo, required this.bote, required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.accent.withValues(alpha: 0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('EL BOTE',
                style: TextStyle(
                    color: t.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (bote.cerrado ? t.primary : t.sub).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(bote.cerrado ? 'CERRADO' : 'ABIERTO',
                style: TextStyle(
                    color: bote.cerrado ? t.primary : t.sub,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6)),
          ),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic, children: [
          Text('\$${bote.total.toStringAsFixed(0)}',
              style: TextStyle(
                  color: t.text,
                  fontSize: 30,
                  height: 1.0,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: 8),
          Text(
              '\$${torneo.bote.entrada.toStringAsFixed(0)} por jugador · '
              '${bote.lineas.length}',
              style: TextStyle(color: t.sub, fontSize: 11.5)),
        ]),
        if (bote.recaudado != bote.total) ...[
          const SizedBox(height: 2),
          Text(
              'Entraron \$${bote.recaudado.toStringAsFixed(0)}; el resto se '
              'devuelve a quien no llegó al mínimo.',
              style: TextStyle(color: t.sub, fontSize: 11)),
        ],
        const SizedBox(height: 8),
        Text(torneo.bote.reparto.label,
            style: TextStyle(color: t.sub, fontSize: 11.5)),
        if (bote.provisional != null) ...[
          const SizedBox(height: 6),
          Text(bote.provisional!,
              style: TextStyle(
                  color: t.accent, fontSize: 11.5, height: 1.35)),
        ],
        const SizedBox(height: 10),
        Divider(color: t.divider, height: 1),
        const SizedBox(height: 8),
        for (final l in bote.lineas)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(
                width: 24,
                child: Text(l.puesto == null ? '—' : '${l.puesto}',
                    style: TextStyle(color: t.sub, fontSize: 12)),
              ),
              Expanded(
                child: Text(l.nombre,
                    style: TextStyle(
                        color: t.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
              if (l.devuelto > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('vuelve \$${l.devuelto.toStringAsFixed(0)}',
                      style: TextStyle(color: t.sub, fontSize: 10.5)),
                ),
              // El saldo del BOTE, no el de la ronda. Se dice en la etiqueta de
              // arriba para que nadie lo lea como lo que ganó el sábado.
              Text(
                  l.saldo > 0.005
                      ? '+\$${l.saldo.toStringAsFixed(0)}'
                      : (l.saldo < -0.005
                          ? '−\$${l.saldo.abs().toStringAsFixed(0)}'
                          : '\$0'),
                  style: TextStyle(
                      color: l.saldo > 0.005
                          ? t.profit
                          : (l.saldo < -0.005 ? t.loss : t.sub),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
        const SizedBox(height: 8),
        // La restricción, dicha al usuario y no solo en el código. Si algún día
        // alguien espera un botón de pagar, aquí está por qué no lo hay.
        Text(
            'La app lleva la cuenta; el dinero se mueve entre ustedes. No se '
            'cobra nada desde aquí.',
            style: TextStyle(
                color: t.sub, fontSize: 10.5, fontStyle: FontStyle.italic)),
      ]),
    );
  }
}

// ── Los botes de cada jornada ────────────────────────────────────────────────
//
// Con su propio total y NUNCA sumado al final: este está cobrado —la ronda se
// cerró— y el final es una expectativa mientras el torneo esté abierto. Es el
// mismo criterio que separa el bote de las apuestas de ronda, un nivel más
// adentro.
//
// Y no aparece en el balance de la ronda: el ledger de una ronda es lo que
// liquidó el motor de apuestas, y esto es contabilidad del torneo por encima.
// Meterlo ahí lo colaría en RoundResult.balances y de ahí al balance histórico.
class _BloqueJornadas extends StatelessWidget {
  final Torneo torneo;
  final List<BoteDeJornada> jornadas;
  final GolfTheme t;
  const _BloqueJornadas(
      {required this.torneo, required this.jornadas, required this.t});

  @override
  Widget build(BuildContext context) {
    if (jornadas.isEmpty) return const SizedBox.shrink();
    final repartido = jornadas.fold(0.0, (s, j) => s + j.total);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('BOTE DEL DÍA',
                style: TextStyle(
                    color: t.sub,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: t.profit.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            // La etiqueta es la mitad del mensaje: esto ya pasó por el bolsillo
            // de alguien, al contrario del bote final.
            child: Text('YA COBRADO',
                style: TextStyle(
                    color: t.profit,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
            '\$${torneo.bote.entradaPorJornada.toStringAsFixed(0)} por ronda '
            'jugada · \$${repartido.toStringAsFixed(0)} repartidos en '
            '${jornadas.length} jornada${jornadas.length == 1 ? '' : 's'}',
            style: TextStyle(color: t.sub, fontSize: 11.5)),
        const SizedBox(height: 4),
        Text('No se suma al bote final: son dinero distinto.',
            style: TextStyle(
                color: t.sub, fontSize: 10.5, fontStyle: FontStyle.italic)),
        const SizedBox(height: 10),
        Divider(color: t.divider, height: 1),
        for (final j in jornadas.take(10))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${j.fecha.day}/${j.fecha.month} · ${j.nombreRonda}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: t.text, fontSize: 12.5)),
                      Text(
                          j.cobran.isEmpty
                              ? '${j.jugadores} jugaron · sin ganador'
                              : '${j.jugadores} jugaron · cobra '
                                  '${j.cobran.keys.map((k) => j.nombres[k] ?? k).join(', ')}',
                          style: TextStyle(color: t.sub, fontSize: 11)),
                    ]),
              ),
              Text('\$${j.total.toStringAsFixed(0)}',
                  style: TextStyle(
                      color: t.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
        if (jornadas.length > 10)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                'Y ${jornadas.length - 10} jornadas más. El total de arriba las '
                'incluye todas.',
                style: TextStyle(color: t.sub, fontSize: 10.5)),
          ),
      ]),
    );
  }
}
