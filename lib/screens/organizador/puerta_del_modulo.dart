// ─────────────────────────────────────────────────────────────────────────────
// LA PUERTA DEL MÓDULO — y qué ve quien no lo tiene
//
// «Se da clic en el logo de la app y se despliega el módulo de organizador. Y
// solo lo ve quien está marcado.»
//
// ── QUÉ VE QUIEN NO ESTÁ MARCADO, y por qué no es "nada" ────────────────────
//
// Tres opciones y solo una sirve:
//
//   · nada → un toque que no responde se lee como un fallo, y el logo es lo
//     primero que se ve al abrir la app
//   · un error → «no tienes permiso» sobre algo que no ha pedido, y encima
//     falso: no le falta un permiso, le falta un producto que no conoce
//   · qué es → dice qué hace el módulo, que es además la única forma de
//     venderlo desde dentro de la app
//
// Y una condición que decide si esto suma o resta: tiene que dejar CLARÍSIMO
// que crear torneos NO es esto. Un golfista que organiza su Match Play anual ya
// puede hacerlo y es gratis; si la hoja le hace creer que lo que ya tiene está
// detrás de un pago, el mensaje hace daño en vez de vender.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/golf_icons.dart';
import '../../providers/organizador_provider.dart';
import '../../providers/torneo_provider.dart';
import 'organizador_screen.dart';

/// Abre el módulo, o dice qué es.
Future<void> abrirModuloDeOrganizador(BuildContext context) async {
  final org = context.read<OrganizadorProvider>();
  final t = context.gt;

  // ── Mientras no se sepa, se espera ────────────────────────────────────────
  //
  // «Todavía no lo sé» no es «no». Sin esta distinción, tocar el logo en el
  // primer segundo de sesión enseñaría la hoja de venta a un organizador que
  // lleva pagando tres meses.
  if (!org.resuelto) {
    await org.comprobar();
    if (!context.mounted) return;
  }

  if (org.marcado != true) {
    await _hojaDeQueEs(context, t);
    return;
  }

  // ── Con módulo: al torneo que se está organizando ─────────────────────────
  //
  // El portal es de UN torneo, así que hace falta elegir. Con uno solo se entra
  // directo: preguntar cuando no hay pregunta es un paso de más el día del
  // torneo.
  final torneos = context.read<TorneoProvider>().torneos;
  if (torneos.isEmpty) {
    await _hojaSinTorneos(context, t);
    return;
  }
  final id = torneos.length == 1
      ? torneos.first.id
      : await _elegirTorneo(context, t);
  if (id == null || !context.mounted) return;
  await Navigator.push(context,
      MaterialPageRoute(builder: (_) => OrganizadorScreen(torneoId: id)));
}

Future<void> _hojaDeQueEs(BuildContext context, GolfTheme t) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: t.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(
              child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: t.divider,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 18),
            Icon(GolfIcons.pantalla, size: GolfIcons.juntoAlHeroe, color: t.primary),
            const SizedBox(height: 12),
            Text('Módulo de organizador', style: GolfType.title(t.text)),
            const SizedBox(height: 8),
            Text(
                'Para quien organiza torneos de forma formal: un portal de '
                'escritorio con el padrón, la pantalla para la casa club, el '
                'inventario de patrocinio y los grupos de un shotgun.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.sub, fontSize: 13, height: 1.45)),
            const SizedBox(height: 16),
            // ── LO QUE YA TIENES, dicho antes de nada más ─────────────────
            //
            // Es la línea que impide que esto haga daño. Sin ella, la hoja
            // parece decir que crear torneos es de pago — y crear torneos es
            // la función del jugador que se queda gratis.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.divider),
              ),
              child: Row(children: [
                Icon(GolfIcons.bien,
                    size: GolfIcons.juntoAValor, color: t.primary),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                      'Crear tus torneos, su tabla y compartirla ya lo tienes, '
                      'y seguirá siendo gratis. Esto es otra cosa.',
                      style: TextStyle(
                          color: t.text, fontSize: 12.5, height: 1.4)),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            // No hay botón de comprar: no es autoservicio. Se contrata
            // hablando, que es lo que encaja con pagar por evento.
            Text('Se activa por torneo. Escríbenos y lo dejamos listo.',
                textAlign: TextAlign.center,
                style: GolfType.label(t.sub)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                style: TextButton.styleFrom(foregroundColor: t.sub),
                child: const Text('Entendido'),
              ),
            ),
          ]),
        ),
      ),
    );

Future<void> _hojaSinTorneos(BuildContext context, GolfTheme t) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: t.card,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('El portal es de un torneo', style: GolfType.title(t.text)),
            const SizedBox(height: 8),
            Text(
                'Crea el torneo primero y el portal se abre sobre él: el '
                'padrón, la pantalla y el patrocinio son suyos.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.sub, fontSize: 13, height: 1.4)),
            const SizedBox(height: 14),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(foregroundColor: t.sub),
              child: const Text('Entendido'),
            ),
          ]),
        ),
      ),
    );

/// Cuál de los torneos. Solo se pregunta con más de uno.
Future<String?> _elegirTorneo(BuildContext context, GolfTheme t) {
  final torneos = context.read<TorneoProvider>().torneos;
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: t.card,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
        children: [
          Text('Qué torneo organizas', style: GolfType.title(t.text)),
          const SizedBox(height: 10),
          for (final x in torneos)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(GolfIcons.deClave(x.emoji), color: t.primary),
              title: Text(x.nombre, style: GolfType.value(t.text)),
              subtitle: Text(
                  '${x.participantes.length} inscrito'
                  '${x.participantes.length == 1 ? '' : 's'}',
                  style: GolfType.label(t.sub)),
              onTap: () => Navigator.pop(ctx, x.id),
            ),
        ],
      ),
    ),
  );
}
