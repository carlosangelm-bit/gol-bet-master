// ─────────────────────────────────────────────────────────────────────────────
// LA VISTA DE INVITADO — solo lectura, y se nota
//
// Es la puerta de entrada de gente que no tiene la app. Así que dos cosas
// gobiernan la pantalla:
//
//   1. NO HAY NADA QUE TOCAR. Ni editar, ni cerrar, ni republicar. No es que los
//      botones estén deshabilitados: no existen. Un botón apagado invita a
//      buscar cómo encenderlo.
//   2. LO QUE SE VE ES UNA COPIA FECHADA, y el sello va arriba. Un total sin
//      fecha pretende ser la verdad de ahora; con "actualizada hace tres días"
//      es lo que es.
//
// Y la cintilla de descarga, permanente, sin tapar el contenido: va fija abajo
// con el ListView dejándole sitio, no flotando encima.
import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../models/torneo_publicado.dart';

class TorneoInvitadoScreen extends StatelessWidget {
  final TorneoPublicado copia;
  const TorneoInvitadoScreen({super.key, required this.copia});

  @override
  Widget build(BuildContext context) {
    final t = context.gt;
    final ahora = DateTime.now();
    final rancia = copia.estaRancia(ahora);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        foregroundColor: t.text,
        elevation: 0,
        title: Text('${copia.emoji} ${copia.nombre}'),
        // Sin acciones: no hay nada que hacer aquí.
      ),
      body: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              // El sello. Va PRIMERO porque cambia cómo se lee todo lo de abajo.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: t.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: rancia
                          ? t.scoreOver.withValues(alpha: 0.55)
                          : t.divider),
                ),
                child: Row(children: [
                  Icon(Icons.visibility_outlined, size: 15, color: t.sub),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        'Estás viendo una copia de esta tabla, actualizada '
                        '${copia.antiguedad(ahora)}'
                        '${rancia ? '. Puede haber rondas nuevas que no salen aquí' : ''}.',
                        style: TextStyle(
                            color: t.sub, fontSize: 11.5, height: 1.35)),
                  ),
                ]),
              ),
              const SizedBox(height: 14),

              _tarjeta(t, 'CÓMO SE PUNTÚA', [
                copia.comoSePuntua,
                copia.comoSeAcumula,
                '${copia.rondas} ronda${copia.rondas == 1 ? '' : 's'}'
                    '${copia.cerrado ? ' · torneo cerrado' : ' · torneo abierto'}',
              ]),
              const SizedBox(height: 14),

              if (copia.boteTotal > 0) ...[
                _bote(t),
                const SizedBox(height: 14),
              ],

              if (copia.jornadas.isNotEmpty) ...[
                _jornadas(t),
                const SizedBox(height: 14),
              ],

              Text('CLASIFICACIÓN',
                  style: TextStyle(
                      color: t.sub,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8)),
              const SizedBox(height: 8),
              for (final f in copia.tabla.where((x) => !x.bajoMinimo))
                _fila(t, f),
              if (copia.tabla.any((x) => x.bajoMinimo)) ...[
                const SizedBox(height: 14),
                Text('SIN EL MÍNIMO DE RONDAS',
                    style: TextStyle(
                        color: t.sub,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8)),
                const SizedBox(height: 8),
                for (final f in copia.tabla.where((x) => x.bajoMinimo))
                  _fila(t, f),
              ],
            ],
          ),
        ),
        _CintillaDescarga(t: t),
      ]),
    );
  }

  Widget _tarjeta(GolfTheme t, String titulo, List<String> lineas) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.divider),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo,
              style: TextStyle(
                  color: t.sub,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8)),
          const SizedBox(height: 6),
          for (final l in lineas)
            if (l.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(l,
                    style: TextStyle(
                        color: t.text, fontSize: 12.5, height: 1.35)),
              ),
        ]),
      );

  Widget _bote(GolfTheme t) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.accent.withValues(alpha: 0.45)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('EL BOTE',
              style: TextStyle(
                  color: t.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8)),
          const SizedBox(height: 6),
          Text('\$${copia.boteTotal.toStringAsFixed(0)}',
              style: TextStyle(
                  color: t.text,
                  fontSize: 28,
                  height: 1.0,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          if (copia.boteReparto != null) ...[
            const SizedBox(height: 4),
            Text(copia.boteReparto!,
                style: TextStyle(color: t.sub, fontSize: 11.5)),
          ],
          if (copia.boteProvisional != null) ...[
            const SizedBox(height: 6),
            Text(copia.boteProvisional!,
                style: TextStyle(color: t.accent, fontSize: 11.5, height: 1.35)),
          ],
          const SizedBox(height: 8),
          // La restricción, también aquí: es la pantalla que va a ver alguien que
          // no conoce la app, y es donde más falta hace decirlo.
          Text(
              'La app lleva la cuenta; el dinero se mueve entre los jugadores. '
              'No se cobra nada desde aquí.',
              style: TextStyle(
                  color: t.sub, fontSize: 10.5, fontStyle: FontStyle.italic)),
        ]),
      );

  Widget _jornadas(GolfTheme t) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
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
            Text('ya cobrado',
                style: TextStyle(color: t.profit, fontSize: 10)),
          ]),
          const SizedBox(height: 6),
          Text(
              '\$${copia.boteJornadaEntrada.toStringAsFixed(0)} por ronda '
              'jugada. No se suma al bote de arriba: son dinero distinto.',
              style: TextStyle(color: t.sub, fontSize: 11.5, height: 1.3)),
          const SizedBox(height: 8),
          for (final j in copia.jornadas.take(10))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(
                  child: Text(
                      '${j.fecha.day}/${j.fecha.month} · '
                      '${j.cobran.isEmpty ? 'sin ganador' : j.cobran.join(', ')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.text, fontSize: 12)),
                ),
                Text('\$${j.total.toStringAsFixed(0)}',
                    style: TextStyle(
                        color: t.sub,
                        fontSize: 12,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
            ),
        ]),
      );

  Widget _fila(GolfTheme t, FilaPublicada f) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: f.puesto == 1 && !f.bajoMinimo ? t.primary : t.divider),
          ),
          child: Row(children: [
            SizedBox(
              width: 24,
              child: Text('${f.puesto}',
                  style: TextStyle(
                      color: f.puesto == 1 ? t.primary : t.sub,
                      fontSize: 14,
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
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    Text(
                        f.contadas != f.jugadas
                            ? '${f.contadas} de ${f.jugadas} rondas cuentan'
                            : '${f.jugadas} ronda${f.jugadas == 1 ? '' : 's'}',
                        style: TextStyle(color: t.sub, fontSize: 11)),
                  ]),
            ),
            if (f.cobraBote > 0)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text('+\$${f.cobraBote.toStringAsFixed(0)}',
                    style: TextStyle(
                        color: t.profit,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            Text(f.total.toStringAsFixed(f.total == f.total.roundToDouble() ? 0 : 1),
                style: TextStyle(
                    color: t.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        ),
      );
}

// ── La cintilla ──────────────────────────────────────────────────────────────
//
// Permanente y visible, pero SIN TAPAR el contenido: va fija abajo dentro de la
// Column, con el ListView ocupando el resto. Flotando encima taparía la última
// fila de la tabla, que es justo la que alguien viene a mirar cuando va último.
class _CintillaDescarga extends StatelessWidget {
  final GolfTheme t;
  const _CintillaDescarga({required this.t});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: t.primary,
      child: SafeArea(
        top: false,
        child: InkWell(
          onTap: () => _abrirTienda(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(children: [
              const Text('⛳', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Descarga la app para más funciones',
                          style: TextStyle(
                              color: t.onPrimary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800)),
                      Text('Lleva la cuenta de tus apuestas y tu handicap',
                          style: TextStyle(
                              color: t.onPrimary.withValues(alpha: 0.85),
                              fontSize: 11)),
                    ]),
              ),
              Icon(Icons.arrow_forward_rounded, color: t.onPrimary, size: 18),
            ]),
          ),
        ),
      ),
    );
  }

  void _abrirTienda(BuildContext context) {
    // La URL de la tienda todavía no existe: la app no está publicada. Se dice
    // en vez de abrir una página que no está — un enlace roto en la primera
    // pantalla que ve un usuario nuevo es peor que un aviso honesto.
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text(
          'La app está en camino a las tiendas. Pídele el enlace a quien te '
          'compartió el torneo.'),
      duration: Duration(seconds: 4),
    ));
  }
}
