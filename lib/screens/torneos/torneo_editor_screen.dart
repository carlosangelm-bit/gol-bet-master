// ─────────────────────────────────────────────────────────────────────────────
// CREAR O EDITAR UN TORNEO — cuatro decisiones, todas opción
//
// Ninguna es fija: qué rondas cuentan, cómo puntúa cada una, cómo se acumula y
// quién entra en la tabla.
//
// Y las combinaciones que no significan nada salen ATENUADAS CON SU MOTIVO, no
// elegibles y rotas: mejores N en un torneo de una ronda, puntuar por Stableford
// sin rondas que lo tengan guardado, un mínimo mayor que las rondas que hay. Es
// el mismo criterio del paso de qué se juega, y los motivos viven en torneo.dart
// para que la pantalla no los invente.
//
// El default de acumulación cambia con el tamaño: suma simple en un torneo
// corto, mejores N en uno de temporada. Sumar premia al que más juega, no al que
// mejor juega, y eso solo importa cuando hay muchas rondas.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../models/round_result.dart';
import '../../models/torneo.dart';
import '../../providers/betting_group_provider.dart';
import '../../providers/perfil_provider.dart';
import '../../providers/torneo_provider.dart';

class TorneoEditorScreen extends StatefulWidget {
  final Torneo? existente;
  const TorneoEditorScreen({super.key, required this.existente});

  @override
  State<TorneoEditorScreen> createState() => _TorneoEditorScreenState();
}

class _TorneoEditorScreenState extends State<TorneoEditorScreen> {
  late Torneo _t;
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _puntosCtrl;
  late final TextEditingController _entradaCtrl;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _t = widget.existente ?? const Torneo(id: '', nombre: '');
    _nombreCtrl = TextEditingController(text: _t.nombre);
    _puntosCtrl =
        TextEditingController(text: _t.puntosPorPuesto.join(', '));
    _entradaCtrl = TextEditingController(
        text: _t.bote.hayBote ? _t.bote.entrada.toStringAsFixed(0) : '');
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _puntosCtrl.dispose();
    _entradaCtrl.dispose();
    super.dispose();
  }

  /// Las rondas que el torneo tendría AHORA. Se recalcula en cada build para que
  /// los avisos hablen de la configuración que se está tocando, no de la que
  /// había al abrir.
  List<RoundResult> get _rondas =>
      rondasDelTorneo(_t, context.read<PerfilProvider>().resultados);

  /// Cuántos jugadores tendría la tabla con estas rondas. Para poder decir el
  /// total del bote mientras se configura, en vez de al guardar.
  int _jugadoresEnTabla(List<RoundResult> rondas) =>
      rondas.expand((r) => r.playerIds).toSet().length;

  @override
  Widget build(BuildContext context) {
    final t = context.gt;
    final rondas = _rondas;
    final grupos = context.watch<BettingGroupProvider>().groups;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        foregroundColor: t.text,
        title: Text(widget.existente == null ? 'Nuevo torneo' : 'Editar torneo'),
        elevation: 0,
        actions: [
          if (widget.existente != null)
            IconButton(
              icon: Icon(Icons.delete_outline, color: t.sub),
              onPressed: _borrar,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          TextField(
            controller: _nombreCtrl,
            style: TextStyle(color: t.text),
            decoration: InputDecoration(
              labelText: 'Nombre del torneo',
              labelStyle: TextStyle(color: t.sub),
              filled: true,
              fillColor: t.surface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: t.divider)),
            ),
          ),
          const SizedBox(height: 20),

          // ── 1 · Qué rondas cuentan ─────────────────────────────────────
          _titulo('1 · QUÉ RONDAS CUENTAN', t),
          for (final f in FuenteDeRondas.values)
            _opcion(
              t: t,
              titulo: f.label,
              detalle: f.descripcion,
              activa: _t.fuente == f,
              onTap: () => setState(() => _t = _t.copyWith(fuente: f)),
            ),
          if (_t.fuente == FuenteDeRondas.grupo) ...[
            const SizedBox(height: 8),
            if (grupos.isEmpty)
              _nota(
                  'No tienes grupos de apuesta guardados. Se crean en '
                  'Plantillas.',
                  t)
            else
              for (final g in grupos)
                _opcion(
                  t: t,
                  titulo: '${g.emoji} ${g.name}',
                  detalle: '${g.playerIds.length} habituales',
                  activa: _t.bettingGroupId == g.id,
                  onTap: () =>
                      setState(() => _t = _t.copyWith(bettingGroupId: g.id)),
                ),
          ],
          if (_t.fuente != FuenteDeRondas.manual) ...[
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _fecha(t, 'Desde', _t.desde,
                  (d) => setState(() => _t = _t.copyWith(desde: d)),
                  () => setState(() => _t = _t.copyWith(limpiarDesde: true)))),
              const SizedBox(width: 8),
              Expanded(child: _fecha(t, 'Hasta', _t.hasta,
                  (d) => setState(() => _t = _t.copyWith(hasta: d)),
                  () => setState(() => _t = _t.copyWith(limpiarHasta: true)))),
            ]),
          ],
          const SizedBox(height: 8),
          _nota(
              '${rondas.length} ronda${rondas.length == 1 ? '' : 's'} '
              '${rondas.length == 1 ? 'entra' : 'entran'} con esta fuente.',
              t),
          const SizedBox(height: 22),

          // ── 2 · Cómo puntúa cada ronda ─────────────────────────────────
          _titulo('2 · CÓMO PUNTÚA CADA RONDA', t),
          for (final m in MetodoDePuntuacion.values)
            _opcion(
              t: t,
              titulo: m.label,
              detalle: m.descripcion,
              // El motivo sale de torneo.dart, no de un if aquí: la pantalla no
              // decide qué es imposible.
              motivo: motivoSinMetodo(m, rondas),
              activa: _t.metodo == m,
              onTap: () => setState(() => _t = _t.copyWith(metodo: m)),
            ),
          if (_t.metodo == MetodoDePuntuacion.posicion) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _puntosCtrl,
              style: TextStyle(color: t.text),
              keyboardType: TextInputType.text,
              onChanged: (v) {
                final nums = v
                    .split(RegExp(r'[^0-9]+'))
                    .where((x) => x.isNotEmpty)
                    .map(int.parse)
                    .toList();
                if (nums.isNotEmpty) {
                  setState(() => _t = _t.copyWith(puntosPorPuesto: nums));
                }
              },
              decoration: InputDecoration(
                labelText: 'Puntos por puesto',
                helperText: 'El puesto que se sale de la lista no puntúa.',
                helperStyle: TextStyle(color: t.sub, fontSize: 11),
                labelStyle: TextStyle(color: t.sub),
                filled: true,
                fillColor: t.surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: t.divider)),
              ),
            ),
            const SizedBox(height: 12),
            _titulo('SI DOS EMPATAN EN UNA RONDA', t),
            for (final e in ReglaDeEmpate.values)
              _opcion(
                t: t,
                titulo: e.label,
                detalle: e.descripcion,
                activa: _t.empate == e,
                onTap: () => setState(() => _t = _t.copyWith(empate: e)),
              ),
          ],
          const SizedBox(height: 22),

          // ── 3 · Cómo se acumula ────────────────────────────────────────
          _titulo('3 · CÓMO SE ACUMULA', t),
          for (final a in Acumulacion.values)
            _opcion(
              t: t,
              titulo: a.label,
              detalle: a == Acumulacion.sumaSimple
                  ? 'Todas las rondas suman.'
                  : 'Solo las mejores de cada uno. Sumar premia al que más '
                      'juega; esto, al que mejor juega.',
              motivo: motivoSinAcumulacion(a, rondas.length),
              activa: _t.acumulacion == a,
              onTap: () => setState(() => _t = _t.copyWith(acumulacion: a)),
            ),
          if (_t.acumulacion == Acumulacion.mejoresDeN) ...[
            const SizedBox(height: 8),
            _contador(t, 'Cuántas cuentan', _t.mejoresN, 1, 40,
                (v) => setState(() => _t = _t.copyWith(mejoresN: v))),
          ],
          const SizedBox(height: 22),

          // ── 4 · Quién entra en la tabla ────────────────────────────────
          _titulo('4 · QUIÉN ENTRA EN LA TABLA', t),
          _contador(t, 'Rondas mínimas', _t.minimoRondas, 0, 40,
              (v) => setState(() => _t = _t.copyWith(minimoRondas: v))),
          const SizedBox(height: 6),
          _nota(
              _t.minimoRondas == 0
                  ? 'Con 0 entran todos, aunque hayan jugado una sola.'
                  : 'Quien no llegue sale aparte, con su cuenta: no desaparece.',
              t),
          if (motivoSinMinimo(_t.minimoRondas, rondas.length) != null) ...[
            const SizedBox(height: 6),
            Text(motivoSinMinimo(_t.minimoRondas, rondas.length)!,
                style: TextStyle(
                    color: t.scoreOver.withValues(alpha: 0.95),
                    fontSize: 11.5,
                    height: 1.35)),
          ],
          const SizedBox(height: 22),

          // ── 5 · El bote ────────────────────────────────────────────────
          _titulo('5 · EL BOTE', t),
          TextField(
            controller: _entradaCtrl,
            keyboardType: TextInputType.number,
            style: TextStyle(color: t.text),
            onChanged: (v) {
              final n = double.tryParse(v) ?? 0;
              setState(() => _t = _t.copyWith(bote: _t.bote.copyWith(entrada: n)));
            },
            decoration: InputDecoration(
              labelText: 'Entrada por jugador',
              prefixText: '\$ ',
              helperText: '0 = sin bote',
              helperStyle: TextStyle(color: t.sub, fontSize: 11),
              labelStyle: TextStyle(color: t.sub),
              filled: true,
              fillColor: t.surface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: t.divider)),
            ),
          ),
          if (_t.bote.hayBote) ...[
            const SizedBox(height: 6),
            _nota(
                'Total del bote con las rondas de ahora: '
                '\$${(_t.bote.entrada * _jugadoresEnTabla(rondas)).toStringAsFixed(0)}',
                t),
            const SizedBox(height: 12),
            _titulo('CÓMO SE REPARTE', t),
            for (final r in RepartoDelBote.values)
              _opcion(
                t: t,
                titulo: r.label,
                detalle: r == RepartoDelBote.podio
                    ? 'Porcentajes: ${_t.bote.porcentajes.join(' · ')}%'
                    : 'Todo para el primero de la tabla.',
                activa: _t.bote.reparto == r,
                onTap: () => setState(
                    () => _t = _t.copyWith(bote: _t.bote.copyWith(reparto: r))),
              ),
            if (_t.minimoRondas > 0) ...[
              const SizedBox(height: 10),
              _titulo('QUIEN NO LLEGA AL MÍNIMO', t),
              for (final s in EntradaSinMinimo.values)
                _opcion(
                  t: t,
                  titulo: s.label,
                  detalle: s.descripcion,
                  activa: _t.bote.sinMinimo == s,
                  onTap: () => setState(() =>
                      _t = _t.copyWith(bote: _t.bote.copyWith(sinMinimo: s))),
                ),
            ],
            const SizedBox(height: 10),
            // La restricción, dicha donde se configura el bote.
            _nota(
                'La app lleva la cuenta del bote; no cobra ni paga nada. El '
                'dinero se mueve entre ustedes.',
                t),
          ],
          const SizedBox(height: 18),

          // ── Cerrar el torneo ───────────────────────────────────────────
          _opcion(
            t: t,
            titulo: _t.cerrado ? 'Torneo cerrado' : 'Torneo abierto',
            detalle: _t.cerrado
                ? 'La tabla ya no cambia y el reparto es el definitivo. Cerrado '
                    'no significa pagado: la app no cobra nada.'
                : 'Sigue contando rondas nuevas. El reparto del bote es '
                    'provisional mientras esté abierto.',
            activa: _t.cerrado,
            onTap: () => setState(() => _t = _t.copyWith(cerrado: !_t.cerrado)),
          ),

          const SizedBox(height: 26),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _guardando ? null : _guardar,
              style: ElevatedButton.styleFrom(
                backgroundColor: t.primary,
                foregroundColor: t.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(_guardando ? 'Guardando…' : 'Guardar torneo',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Piezas ────────────────────────────────────────────────────────────────

  Widget _titulo(String txt, GolfTheme t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(txt,
            style: TextStyle(
                color: t.sub,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8)),
      );

  Widget _nota(String txt, GolfTheme t) => Text(txt,
      style: TextStyle(
          color: t.sub, fontSize: 11.5, fontStyle: FontStyle.italic));

  /// Una opción. Con [motivo] sale atenuada y explicada, nunca solo apagada.
  Widget _opcion({
    required GolfTheme t,
    required String titulo,
    required String detalle,
    required bool activa,
    required VoidCallback onTap,
    String? motivo,
  }) {
    final bloqueada = motivo != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: bloqueada ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: bloqueada
                ? t.surface
                : activa
                    ? t.primary.withValues(alpha: 0.1)
                    : t.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: activa && !bloqueada ? t.primary : t.divider,
                width: activa && !bloqueada ? 1.5 : 1),
          ),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: TextStyle(
                            color: bloqueada ? t.sub : t.text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700)),
                    Text(motivo ?? detalle,
                        style: TextStyle(
                            color: t.sub,
                            fontSize: 11,
                            height: 1.3,
                            fontStyle: bloqueada
                                ? FontStyle.italic
                                : FontStyle.normal)),
                  ]),
            ),
            const SizedBox(width: 8),
            if (bloqueada)
              Icon(Icons.block, color: t.sub, size: 16)
            else if (activa)
              Icon(Icons.check_circle, color: t.primary, size: 18)
            else
              Icon(Icons.circle_outlined, color: t.sub, size: 18),
          ]),
        ),
      ),
    );
  }

  Widget _contador(GolfTheme t, String etiqueta, int valor, int min, int max,
          ValueChanged<int> onChange) =>
      Row(children: [
        Expanded(
            child: Text(etiqueta,
                style: TextStyle(color: t.text, fontSize: 13))),
        IconButton(
          icon: Icon(Icons.remove_circle_outline, color: t.sub),
          onPressed: valor > min ? () => onChange(valor - 1) : null,
        ),
        SizedBox(
          width: 34,
          child: Text('$valor',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: t.text, fontSize: 16, fontWeight: FontWeight.w800)),
        ),
        IconButton(
          icon: Icon(Icons.add_circle_outline, color: t.primary),
          onPressed: valor < max ? () => onChange(valor + 1) : null,
        ),
      ]);

  Widget _fecha(GolfTheme t, String etiqueta, DateTime? valor,
      ValueChanged<DateTime> onPick, VoidCallback onClear) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: valor ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (d != null) onPick(d);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.divider),
        ),
        child: Row(children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(etiqueta,
                      style: TextStyle(color: t.sub, fontSize: 10)),
                  Text(
                      valor == null
                          ? 'Sin límite'
                          : '${valor.day}/${valor.month}/${valor.year}',
                      style: TextStyle(
                          color: t.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ]),
          ),
          if (valor != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClear,
              child: Icon(Icons.close, color: t.sub, size: 16),
            ),
        ]),
      ),
    );
  }

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ponle nombre al torneo')));
      return;
    }
    setState(() => _guardando = true);
    try {
      await context.read<TorneoProvider>().guardar(_t.copyWith(nombre: nombre));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
      }
    }
  }

  Future<void> _borrar() async {
    await context.read<TorneoProvider>().borrar(_t.id);
    if (mounted) Navigator.pop(context);
  }
}
