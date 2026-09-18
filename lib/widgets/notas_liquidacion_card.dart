// ─────────────────────────────────────────────────────────────────────────────
// LA TARJETA DE NOTAS — lo que una apuesta dice sin que sea un error
//
// Deliberadamente distinta del banner de integridad. Ese es rojo y significa
// "esto no liquidó, arréglalo". Esto es informativo y significa "liquidó bien, y
// hay algo que un número no cuenta":
//
//   · Nadie hizo 3-putt: la serpiente no se cobra
//   · El conejo quedó suelto al cerrar el 9
//   · El hoyo 7 no tiene compañero elegido
//
// Que compartieran superficie sería el error: un usuario que aprende que el
// bloque de avisos es "cosas rotas" deja de leerlo cuando dice algo normal, y
// al revés, uno que aprende que es "información" ignora los rotos.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../engines/settlement_notes.dart';
import '../models/models.dart';

class NotasLiquidacionCard extends StatelessWidget {
  final List<NotaDeLiquidacion> notas;
  final GolfTheme t;

  /// En una línea por nota, para el Resumen.
  ///
  ///     «No tiene por qué mostrarse todo eso en la pantalla de resumen.»
  ///
  /// El Resumen es para el resultado y estos párrafos lo tapaban. No se quitan
  /// de ahí: un cero sin explicación se lee como un fallo, y el Resumen es
  /// justo donde se lee el cero. Se dicen cortas — «Snake · la tiene RAFA
  /// (H17), provisional».
  final bool breve;

  const NotasLiquidacionCard(
      {super.key,
      required this.notas,
      required this.t,
      this.breve = false});

  @override
  Widget build(BuildContext context) {
    if (notas.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < notas.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _Fila(nota: notas[i], t: t, breve: breve),
        ],
      ]),
    );
  }
}

class _Fila extends StatelessWidget {
  final NotaDeLiquidacion nota;
  final GolfTheme t;
  final bool breve;
  const _Fila({required this.nota, required this.t, this.breve = false});

  @override
  Widget build(BuildContext context) {
    // El icono distingue los tres tonos sin depender del color: faltaDato pide
    // una acción del usuario y provisional avisa de que el número puede cambiar.
    final (icono, color) = switch (nota.tono) {
      TonoNota.informativa => (Icons.info_outline_rounded, t.sub),
      TonoNota.provisional => (Icons.hourglass_empty_rounded, t.accent),
      TonoNota.faltaDato => (Icons.help_outline_rounded, t.scoreOver),
    };

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Icon(icono, size: 15, color: color),
      ),
      const SizedBox(width: 9),
      Expanded(
        child: RichText(
          text: TextSpan(children: [
            TextSpan(
              text: '${nota.tipo.label} · ',
              style: TextStyle(
                  color: t.text, fontSize: 12, fontWeight: FontWeight.w800),
            ),
            TextSpan(
              text: breve ? nota.corto : nota.texto,
              style: TextStyle(color: t.sub, fontSize: 12, height: 1.35),
            ),
          ]),
        ),
      ),
    ]);
  }
}
