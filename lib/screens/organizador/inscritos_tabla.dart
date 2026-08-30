// ─────────────────────────────────────────────────────────────────────────────
// LA TABLA DE INSCRITOS — buscar, ordenar y editar sin salir de ella
//
// Es lo que más se usa del portal y lo que hoy peor funciona: la hoja del móvil
// con 150 personas es inviable, y su versión pequeña ya dio guerra montando la
// demo.
//
// El cálculo —buscar, ordenar, quitar, añadir— NO está aquí: está en
// models/inscritos.dart, donde se puede probar sin montar pantalla ni sesión.
// Aquí solo se pinta.
//
// ── El handicap que se edita es el GLOBAL ───────────────────────────────────
//
// El torneo no guarda handicaps: guarda una ventaja, y cuando toca handicap usa
// el `handicapBase` de la ficha del jugador —la misma que usan las demás
// rondas—. Así que editarlo aquí lo cambia en todas partes.
//
// No se esconde y no se bloquea: se dice en la propia columna. Bloquearlo
// dejaría al organizador sin poder corregir un handicap el día del torneo, que
// es justo cuando lo necesita; esconderlo lo convertiría en una sorpresa.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ancho.dart';
import '../../core/app_theme.dart';
import '../../models/inscritos.dart';
import '../../models/torneo.dart';
import '../../providers/player_provider.dart';
import '../../providers/torneo_provider.dart';
import 'organizador_screen.dart';

class InscritosTabla extends StatefulWidget {
  final Torneo torneo;
  final Ancho ancho;
  final GolfTheme t;
  const InscritosTabla({
    super.key,
    required this.torneo,
    required this.ancho,
    required this.t,
  });

  @override
  State<InscritosTabla> createState() => _InscritosTablaState();
}

class _InscritosTablaState extends State<InscritosTabla> {
  final _busca = TextEditingController();
  OrdenDeInscritos _orden = OrdenDeInscritos.inscripcion;
  bool _descendente = false;

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  void _ordenarPor(OrdenDeInscritos o) => setState(() {
        // Volver a pulsar la misma columna invierte, que es lo que espera
        // cualquiera que venga de una hoja de cálculo.
        if (_orden == o) {
          _descendente = !_descendente;
        } else {
          _orden = o;
          _descendente = false;
        }
      });

  Future<void> _anadir() async {
    final nuevo = await anadirInscritos(context, widget.torneo);
    if (nuevo == null || !mounted) return;
    await context.read<TorneoProvider>().guardar(nuevo);
  }

  Future<void> _quitar(FilaDeInscrito f) async {
    final prov = context.read<TorneoProvider>();
    final nuevo = sinInscrito(widget.torneo, f.playerId);
    if (identical(nuevo, widget.torneo)) return;
    await prov.guardar(nuevo);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${f.nombre} ya no está inscrito'),
      action: SnackBarAction(
        label: 'Deshacer',
        // Deshacer devuelve el id, pero al FINAL de la lista: el orden de
        // inscripción es un hecho de cuándo entró cada uno, y fingir que nunca
        // salió sería inventarse ese hecho.
        onPressed: () => prov.guardar(conInscritos(nuevo, [f.playerId])),
      ),
    ));
  }

  Future<void> _editarHandicap(FilaDeInscrito f) async {
    final prov = context.read<PlayerProvider>();
    final pw = prov.directory
        .where((x) => x.player.id == f.playerId)
        .cast<dynamic>()
        .firstWhere((_) => true, orElse: () => null);
    if (pw == null) return;
    final valor = await showDialog<double>(
      context: context,
      builder: (_) => _DialogoHandicap(nombre: f.nombre, actual: f.handicap),
    );
    if (valor == null || !mounted) return;
    final p = pw.player;
    p.handicapBase = valor;
    await prov.updatePlayer(p);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final ancho = widget.ancho;
    final dir = context.watch<PlayerProvider>().directory;
    final filas = filasDeInscritos(
      widget.torneo,
      dir,
      busca: _busca.text,
      orden: _orden,
      descendente: _descendente,
    );
    final total = widget.torneo.participantes.length;

    return Column(children: [
      Padding(
        padding: EdgeInsets.fromLTRB(ancho.esTabla ? 24 : 14, 14, ancho.esTabla ? 24 : 14, 10),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _busca,
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: t.text, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Buscar entre $total inscrito${total == 1 ? '' : 's'}',
                hintStyle: TextStyle(color: t.sub, fontSize: 13),
                prefixIcon: Icon(Icons.search, color: t.sub, size: 18),
                suffixIcon: _busca.text.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(Icons.close, size: 17, color: t.sub),
                        onPressed: () => setState(_busca.clear),
                      ),
                isDense: true,
                filled: true,
                fillColor: t.surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: t.divider)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: t.divider)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (ancho.esTabla)
            ElevatedButton.icon(
              onPressed: _anadir,
              style: ElevatedButton.styleFrom(
                  backgroundColor: t.primary,
                  foregroundColor: t.onPrimary,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 15)),
              icon: const Icon(Icons.person_add_alt, size: 17),
              label: const Text('Añadir',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            )
          else
            IconButton.filled(
              onPressed: _anadir,
              style: IconButton.styleFrom(
                  backgroundColor: t.primary, foregroundColor: t.onPrimary),
              icon: const Icon(Icons.person_add_alt, size: 19),
            ),
        ]),
      ),
      if (ancho.esTabla)
        _Cabeceras(
          ancho: ancho,
          t: t,
          orden: _orden,
          descendente: _descendente,
          onOrdenar: _ordenarPor,
        )
      else
        _OrdenCompacto(t: t, orden: _orden, onOrdenar: _ordenarPor),
      Expanded(
        child: filas.isEmpty
            ? _Vacio(t: t, buscando: _busca.text.isNotEmpty, total: total)
            : ListView.builder(
                padding: EdgeInsets.fromLTRB(
                    ancho.esTabla ? 24 : 14, 4, ancho.esTabla ? 24 : 14, 24),
                itemCount: filas.length,
                itemBuilder: (_, i) => _Fila(
                  fila: filas[i],
                  ancho: ancho,
                  t: t,
                  onHandicap: () => _editarHandicap(filas[i]),
                  onQuitar: () => _quitar(filas[i]),
                ),
              ),
      ),
    ]);
  }
}

class _Cabeceras extends StatelessWidget {
  final Ancho ancho;
  final GolfTheme t;
  final OrdenDeInscritos orden;
  final bool descendente;
  final void Function(OrdenDeInscritos) onOrdenar;
  const _Cabeceras({
    required this.ancho,
    required this.t,
    required this.orden,
    required this.descendente,
    required this.onOrdenar,
  });

  Widget _col(String texto, OrdenDeInscritos? o, {int flex = 1, double? w}) {
    final activa = o != null && o == orden;
    final hijo = InkWell(
      onTap: o == null ? null : () => onOrdenar(o),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(children: [
          Flexible(
            // ETIQUETA, con el token. Antes era 11.5 w800 con tracking 0.4:
            // casi el mismo peso visual que el "18" de debajo, así que el ojo
            // tenía que leer para saber cuál era cuál.
            child: Text(texto,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GolfType.label(activa ? t.primary : t.sub)),
          ),
          if (activa)
            Icon(descendente ? Icons.arrow_downward : Icons.arrow_upward,
                size: 12, color: t.primary),
        ]),
      ),
    );
    return w != null ? SizedBox(width: w, child: hijo) : Expanded(flex: flex, child: hijo);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          decoration:
              BoxDecoration(border: Border(bottom: BorderSide(color: t.divider))),
          child: Row(children: [
            if (ancho.columnasCompletas) _col('#', OrdenDeInscritos.inscripcion, w: 54),
            _col('NOMBRE', OrdenDeInscritos.nombre, flex: 3),
            _col('HANDICAP', OrdenDeInscritos.handicap, w: 120),
            if (ancho.columnasCompletas) _col('', null, w: 48),
          ]),
        ),
      );
}

/// En estrecho no hay cabeceras que pulsar, así que el orden va en chips.
class _OrdenCompacto extends StatelessWidget {
  final GolfTheme t;
  final OrdenDeInscritos orden;
  final void Function(OrdenDeInscritos) onOrdenar;
  const _OrdenCompacto(
      {required this.t, required this.orden, required this.onOrdenar});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          children: [
            for (final o in OrdenDeInscritos.values)
              Padding(
                padding: const EdgeInsets.only(right: 7),
                child: ChoiceChip(
                  label:
                      Text(o.labelCorto, style: const TextStyle(fontSize: 12)),
                  selected: orden == o,
                  onSelected: (_) => onOrdenar(o),
                ),
              ),
          ],
        ),
      );
}

class _Fila extends StatelessWidget {
  final FilaDeInscrito fila;
  final Ancho ancho;
  final GolfTheme t;
  final VoidCallback onHandicap;
  final VoidCallback onQuitar;
  const _Fila({
    required this.fila,
    required this.ancho,
    required this.t,
    required this.onHandicap,
    required this.onQuitar,
  });

  String get _hcp => fila.handicap == fila.handicap.roundToDouble()
      ? '${fila.handicap.round()}'
      : fila.handicap.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final nombre = Row(children: [
      Flexible(
        child: Text(fila.nombre,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: fila.huerfano ? t.sub : t.text,
                fontSize: 14.5,
                fontStyle: fila.huerfano ? FontStyle.italic : null,
                fontWeight: FontWeight.w600)),
      ),
      if (fila.huerfano) ...[
        const SizedBox(width: 6),
        Tooltip(
          message: 'Está inscrito pero su ficha ya no está en tu directorio.',
          child: Icon(Icons.help_outline, size: 15, color: t.sub),
        ),
      ],
    ]);

    final handicap = InkWell(
      onTap: fila.huerfano ? null : onHandicap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          // VALOR. El par label/value es lo que hace el trabajo: ninguno de los
          // dos arregla nada por su cuenta.
          Text(fila.huerfano ? '—' : _hcp,
              style: GolfType.value(fila.huerfano ? t.sub : t.text)),
          if (!fila.huerfano) ...[
            const SizedBox(width: 6),
            Icon(Icons.edit, size: 13, color: t.sub),
          ],
        ]),
      ),
    );

    if (!ancho.esTabla) {
      return Card(
        margin: const EdgeInsets.only(bottom: 7),
        color: t.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
            side: BorderSide(color: t.divider)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 8, 6, 8),
          child: Row(children: [
            Expanded(child: nombre),
            handicap,
            IconButton(
              onPressed: onQuitar,
              icon: Icon(Icons.person_remove_outlined, size: 17, color: t.sub),
              tooltip: 'Quitar del torneo',
            ),
          ]),
        ),
      );
    }

    return Container(
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: t.divider))),
      child: Row(children: [
        if (ancho.columnasCompletas)
          SizedBox(
            width: 54,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text('${fila.inscrito}',
                  style: GolfType.bodyNum(t.sub, size: 12.5)),
            ),
          ),
        Expanded(
          flex: 3,
          child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
              child: nombre),
        ),
        SizedBox(width: 120, child: handicap),
        if (ancho.columnasCompletas)
          SizedBox(
            width: 48,
            child: IconButton(
              onPressed: onQuitar,
              icon: Icon(Icons.person_remove_outlined, size: 17, color: t.sub),
              tooltip: 'Quitar del torneo',
            ),
          ),
      ]),
    );
  }
}

class _Vacio extends StatelessWidget {
  final GolfTheme t;
  final bool buscando;
  final int total;
  const _Vacio({required this.t, required this.buscando, required this.total});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(buscando ? Icons.search_off : Icons.groups_outlined,
                size: 32, color: t.sub),
            const SizedBox(height: 12),
            Text(
                buscando
                    ? 'Nadie con ese nombre entre los $total inscritos'
                    : 'Todavía no hay nadie inscrito',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: t.text, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
                buscando
                    ? 'Prueba con menos letras.'
                    : 'Añádelos uno a uno, o pega la lista entera desde un Excel.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.sub, fontSize: 12.5, height: 1.4)),
          ]),
        ),
      );
}

class _DialogoHandicap extends StatefulWidget {
  final String nombre;
  final double actual;
  const _DialogoHandicap({required this.nombre, required this.actual});

  @override
  State<_DialogoHandicap> createState() => _DialogoHandicapState();
}

class _DialogoHandicapState extends State<_DialogoHandicap> {
  late final _c = TextEditingController(
      text: widget.actual == widget.actual.roundToDouble()
          ? '${widget.actual.round()}'
          : widget.actual.toStringAsFixed(1));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double? get _valor => double.tryParse(_c.text.trim().replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) {
    final t = context.gt;
    return AlertDialog(
      backgroundColor: t.bg,
      title: Text('Handicap de ${widget.nombre}',
          style: TextStyle(color: t.text, fontSize: 17)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          style: TextStyle(color: t.text, fontSize: 16),
          decoration: InputDecoration(
            filled: true,
            fillColor: t.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 12),
        // El aviso que evita la sorpresa. Ver la cabecera de este archivo.
        Text(
            'Este es el handicap de su ficha, el mismo que usan las demás '
            'rondas. Cambiarlo aquí lo cambia en todas partes: el torneo no '
            'guarda un handicap propio.',
            style: TextStyle(color: t.sub, fontSize: 11.5, height: 1.4)),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        TextButton(
          onPressed:
              _valor == null ? null : () => Navigator.pop(context, _valor),
          child: const Text('Guardar',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}
