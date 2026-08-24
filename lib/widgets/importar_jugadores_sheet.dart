// ─────────────────────────────────────────────────────────────────────────────
// LA HOJA DE IMPORTAR — enseña lo que va a pasar ANTES de que pase
//
// Dos pasos a propósito: se pega, se ve el resumen —cuántos nuevos, cuántos ya
// estaban, cuáles no se pudieron leer y por qué— y solo entonces se confirma.
//
// Importar treinta y descubrir después que dos fallaron obliga a revisar treinta
// fichas para encontrarlas. Decirlo antes cuesta una pantalla.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../models/importar_jugadores.dart';
import '../providers/player_provider.dart';
import 'common_widgets.dart';

/// Abre la hoja. Devuelve los ids de los jugadores que quedaron en el
/// directorio —nuevos y reutilizados—, o null si se canceló.
///
/// Devuelve ids y no nombres porque quien la llama suele querer inscribirlos en
/// algo: el torneo los añade a sus participantes sin volver a buscarlos.
Future<List<String>?> showImportarJugadoresSheet(
  BuildContext context, {
  required GolfTheme t,
}) =>
    showModalBottomSheet<List<String>>(
      context: context,
      backgroundColor: t.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ImportarSheet(t: t),
    );

class _ImportarSheet extends StatefulWidget {
  final GolfTheme t;
  const _ImportarSheet({required this.t});

  @override
  State<_ImportarSheet> createState() => _ImportarSheetState();
}

class _ImportarSheetState extends State<_ImportarSheet> {
  final _ctrl = TextEditingController();
  ResultadoDeImportacion? _res;
  bool _importando = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _revisar() {
    final dir = context.read<PlayerProvider>().directory;
    // nombre comparable → id. Si dos del directorio se llaman igual, gana el
    // primero: da lo mismo cuál, y lo que importa es no crear un tercero.
    final existentes = <String, String>{};
    for (final pw in dir) {
      existentes.putIfAbsent(
          nombreComparable(pw.displayName), () => pw.player.id);
    }
    setState(() {
      _error = null;
      _res = parsearJugadores(_ctrl.text, existentes: existentes);
    });
  }

  Future<void> _confirmar() async {
    final res = _res;
    if (res == null || !res.hayAlgo) return;
    setState(() => _importando = true);

    final prov = context.read<PlayerProvider>();
    final ids = <String>[];
    final fallidos = <String>[];

    // Los que ya estaban NO se crean: se reutilizan. Es la mitad del encargo.
    for (final j in res.existentes) {
      ids.add(j.idExistente!);
    }
    for (final j in res.nuevos) {
      try {
        final creado = await prov.createPlayer(
            name: j.nombre, handicap: j.handicap, isFavorite: false);
        ids.add(creado.player.id);
      } catch (e) {
        debugPrint('[Importar] ${j.nombre}: $e');
        fallidos.add(j.nombre);
      }
    }

    if (!mounted) return;
    if (fallidos.isNotEmpty) {
      // Lo que se guardó se queda; lo que no, se dice con nombres. Nunca "algo
      // falló".
      setState(() {
        _importando = false;
        _error = 'Se guardaron ${ids.length}. No se pudieron guardar: '
            '${fallidos.join(', ')}.';
      });
      return;
    }
    Navigator.pop(context, ids);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final res = _res;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 18,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(
              child: Text('Importar jugadores',
                  style: TextStyle(
                      color: t.text, fontWeight: FontWeight.w800, fontSize: 17)),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: Icon(Icons.close, color: t.sub),
            ),
          ]),
          const SizedBox(height: 6),
          // La instrucción, concreta. "Importa un CSV" no le dice a nadie qué
          // teclas tocar.
          Text(
              'En Excel, Numbers o Google Sheets: selecciona las celdas con los '
              'nombres y los handicaps, cópialas, y pégalas aquí. Una persona '
              'por línea.',
              style: TextStyle(color: t.sub, fontSize: 11.5, height: 1.35)),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            maxLines: 6,
            minLines: 4,
            style: TextStyle(color: t.text, fontSize: 13),
            onChanged: (_) {
              if (_res != null) setState(() => _res = null);
            },
            decoration: InputDecoration(
              hintText: 'Rafael Villalobos\t12\nAlan Betancourt\t18,5',
              hintStyle: TextStyle(color: t.sub, fontSize: 12),
              filled: true,
              fillColor: t.surface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: t.divider)),
            ),
          ),
          const SizedBox(height: 12),

          if (res == null)
            GPrimaryButton(
                label: 'Revisar la lista',
                onTap: _ctrl.text.trim().isEmpty ? null : _revisar)
          else ...[
            // El resumen ANTES de importar. Es el criterio: nunca a medias en
            // silencio.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                    color: res.rechazadas.isEmpty
                        ? t.divider
                        : t.scoreOver.withValues(alpha: 0.6)),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(res.resumen,
                        style: TextStyle(
                            color: t.text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800)),
                    if (res.existentes.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                          'Se reutilizan los que ya están en tu directorio, no '
                          'se crean otra vez: '
                          '${res.existentes.map((j) => j.nombre).join(', ')}.',
                          style: TextStyle(
                              color: t.sub, fontSize: 11, height: 1.3)),
                    ],
                    if (res.rechazadas.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('SIN LEER', style: GolfType.label(t.scoreOver)),
                      const SizedBox(height: 3),
                      // Con la línea y el motivo: "algo falló" obliga a revisar
                      // treinta filas para encontrar dos.
                      for (final r in res.rechazadas.take(8))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text('Línea ${r.linea}: ${r.motivo}',
                              style: TextStyle(
                                  color: t.text, fontSize: 11, height: 1.3)),
                        ),
                      if (res.rechazadas.length > 8)
                        Text('…y ${res.rechazadas.length - 8} más.',
                            style: TextStyle(color: t.sub, fontSize: 11)),
                    ],
                  ]),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(
                      color: t.scoreOver, fontSize: 11.5, height: 1.3)),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: GSecButton(
                    label: 'Cambiar la lista',
                    onTap: () => setState(() => _res = null)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GPrimaryButton(
                    label: _importando
                        ? 'Guardando…'
                        : 'Importar ${res.todos.length}',
                    onTap: !res.hayAlgo || _importando ? null : _confirmar),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}
