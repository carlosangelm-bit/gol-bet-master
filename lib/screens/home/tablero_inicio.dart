// ─────────────────────────────────────────────────────────────────────────────
// TABLERO DE INICIO — quién eres, cómo vas, y qué dejaste a medias
//
// Vive en Inicio SIN ronda activa. No pide un destino nuevo: la fase 5 bajó la
// barra de siete a cuatro a propósito, y arrancar una ronda sigue siendo la
// acción primera de esta pantalla —el tablero va debajo, no encima—.
//
// De dónde sale cada número, y qué cuesta:
//
//   · Perfil    → UserProfileProvider, que app_shell ya escucha
//   · HCP       → HandicapProvider, ídem. Índice WHS real
//   · Dinero    → PerfilProvider sobre roundResults, documentos de ~1KB
//                 escritos al cerrar cada ronda
//
// Cero lecturas nuevas al abrir. La alternativa —sumar el histórico desde las
// rondas— habría descargado cada ronda cerrada entera, porque Firestore no
// proyecta campos.
//
// La regla que ordena la pantalla: NO ADIVINAR. El bloque del dinero tiene
// cuatro estados y tres de ellos no son números. Es el mismo criterio que la
// cifra héroe de Resultados, que pregunta de quién es en vez de suponerlo.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../models/perfil_resumen.dart';
import '../../models/serie_balance.dart';
import '../../models/tendencia.dart';
import '../../widgets/grafico_tendencia.dart';
import '../../widgets/grafico_balance.dart';
import '../../providers/handicap_provider.dart';
import '../../providers/perfil_provider.dart';
import '../../providers/torneo_provider.dart';
import '../../models/torneo.dart';
import '../../providers/user_profile_provider.dart';
import '../../services/user_profile_service.dart';
import '../../widgets/app_destinations.dart';
import '../../widgets/common_widgets.dart';

/// `+$150` / `−$150`. El signo se escribe: el color solo no basta en escala de
/// grises ni para quien no lo distingue.
String importe(double v) {
  final s = v.abs().toStringAsFixed(0);
  if (v > 0.005) return '+\$$s';
  if (v < -0.005) return '−\$$s';
  return '\$0';
}

Color colorDe(double v, GolfTheme t) =>
    v > 0.005 ? t.profit : (v < -0.005 ? t.loss : t.sub);

// ─────────────────────────────────────────────────────────────────────────────

// Dos piezas públicas en vez de una, y por un motivo de orden, no de código:
// arrancar una ronda tiene que quedar ENTRE la identidad y el histórico. Inicio
// es donde se empieza a jugar; un tablero que empujara la acción hacia abajo
// convertiría la pantalla de arranque en una de consulta.

/// Quién eres y tu índice. Va arriba de todo.
class TiraIdentidadInicio extends StatelessWidget {
  final GolfTheme t;
  const TiraIdentidadInicio({super.key, required this.t});

  @override
  Widget build(BuildContext context) {
    final perfil = context.watch<UserProfileProvider>().profile;
    final hcp = context.watch<HandicapProvider>();

    return _TiraIdentidad(
      t: t,
      // ── La FORMA del índice, no solo la cifra ─────────────────────────────
      //
      // «4,7 de 20 rondas, no el 6,0 de hace unas entregas. Cambió y no lo
      // habíamos visto.» Una cifra sola no dice si estás bajando, y esa es la
      // pregunta que se hace quien mira su índice.
      //
      // La serie ya existía y ya estaba probada: vivía en Ajustes, a dos
      // pantallas de aquí. Lo que faltaba era enseñarla donde se mira.
      tendencia: tendenciaDeHandicap(hcp.result.allDifferentials),
      nombre: perfil?.nickname?.trim().isNotEmpty == true
          ? perfil!.nickname!.trim()
          : (perfil?.displayName ?? 'Tu perfil'),
      correo: perfil?.email ?? '',
      colorIndex: perfil?.colorIndex ?? 0,
      indice: hcp.displayIndex,
      rondasDelIndice: hcp.result.totalRounds,
    );
  }
}

/// Tu balance, tu rival y tus últimas rondas. Va debajo de la acción.
class HistoricoInicio extends StatelessWidget {
  final GolfTheme t;
  const HistoricoInicio({super.key, required this.t});

  @override
  Widget build(BuildContext context) {
    final perfil = context.watch<UserProfileProvider>().profile;
    final hcp = context.watch<HandicapProvider>();
    final perfilProv = context.watch<PerfilProvider>();

    final resumen = perfilProv.resumen(miId: perfil?.myPlayerId);
    final estado = estadoDelTablero(
      identificado: resumen.identificado,
      conResultado: perfilProv.rondasConDatos,
      // Un diferencial por ronda cerrada, escrito en el mismo momento. Es el
      // recuento que ya está en memoria.
      rondasCerradas: hcp.result.totalRounds,
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _BloqueBalance(
          t: t,
          estado: estado,
          r: resumen,
          // El mismo id que usa el resumen: si fueran dos, la cifra y la línea
          // podrían acabar contando a personas distintas.
          miId: perfil?.myPlayerId ?? UserProfileService.miJugadorId),
      // ── Lo que hay EN JUEGO, en su propio bloque ──────────────────────────
      //
      // Separado del balance y NUNCA sumado a él. El dinero de las rondas está
      // cobrado; el bote de un torneo abierto es una expectativa. Un total que
      // los junte no significa nada: ni es lo que tienes ni es lo que vas a
      // tener.
      //
      // Y no se esconde: si tienes dinero puesto en tres torneos, quieres
      // saberlo sin ir a buscarlo.
      _BloqueEnJuego(
          t: t,
          miId: perfil?.myPlayerId ?? UserProfileService.miJugadorId),
      if (estado == EstadoTablero.listo) ...[
        if (resumen.rival != null) ...[
          const SizedBox(height: 14),
          _TarjetaRival(t: t, rival: resumen.rival!),
        ],
        if (resumen.ultimas.isNotEmpty) ...[
          const SizedBox(height: 14),
          _UltimasRondas(t: t, rondas: resumen.ultimas),
        ],
      ],
    ]);
  }
}

// ── Quién eres, y tu índice ──────────────────────────────────────────────────
//
// Las dos cosas juntas porque responden a la misma pregunta: cómo te presenta la
// app. Toca y vas a Ajustes, que es donde se cambian las dos.
class _TiraIdentidad extends StatelessWidget {
  final GolfTheme t;

  /// Cómo ha ido el índice. Se dibuja solo si tiene suficientes puntos: una
  /// línea de dos puntos siempre sube o baja, y eso decora en vez de decir.
  final SerieDeTendencia tendencia;

  final String nombre, correo;
  final int colorIndex;
  final String indice;
  final int rondasDelIndice;

  const _TiraIdentidad({
    required this.t,
    required this.nombre,
    required this.correo,
    required this.colorIndex,
    required this.tendencia,
    required this.indice,
    required this.rondasDelIndice,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => openSettings(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            GAvatar(name: nombre, colorIndex: colorIndex, size: 46),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: t.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                  if (correo.isNotEmpty)
                    Text(correo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: t.sub, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // La línea, entre el nombre y la cifra. Pequeña a propósito: es la
            // forma del dato, no la hoja completa —esa está en Ajustes, con sus
            // diferenciales—.
            if (tendencia.suficiente) ...[
              SizedBox(
                width: 54,
                height: 26,
                child: CustomPaint(
                  painter: PintorDeSerie(
                    valores: tendencia.puntos.map((p) => p.indice).toList(),
                    // En el handicap, menos es mejor: la línea baja cuando el
                    // jugador mejora, y el color lo dice con el canal del score
                    // —el dinero tiene el suyo reservado—.
                    menosEsMejor: true,
                    linea: t.primary,
                    reja: t.divider,
                    fondo: Colors.transparent,
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('ÍNDICE',
                  style: TextStyle(
                      color: t.sub,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1)),
              const SizedBox(height: 2),
              Text(indice,
                  style: TextStyle(
                      color: t.text,
                      fontSize: 24,
                      height: 1.0,
                      fontWeight: FontWeight.w900,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              // Un índice se lee distinto con 3 rondas que con 20. La tabla WHS
              // ajusta por pocas rondas, así que el número de arriba ya lo
              // refleja; decir de cuántas sale evita leerlo como definitivo.
              Text(
                  rondasDelIndice == 0
                      ? 'sin rondas'
                      : 'de $rondasDelIndice ronda${rondasDelIndice == 1 ? '' : 's'}',
                  style: TextStyle(color: t.sub, fontSize: 10)),
            ]),
            Icon(Icons.chevron_right_rounded, color: t.sub, size: 20),
          ]),
        ),
      ),
    );
  }
}

// ── El dinero ────────────────────────────────────────────────────────────────
//
// Cuatro estados, y solo uno es un número. Los otros tres existen porque
// enseñar "+$0 · 0 rondas" cuando no se sabe quién eres, o cuando el histórico
// está sin calcular, es afirmar algo falso con la misma cara con la que se
// afirmaría algo cierto.
class _BloqueBalance extends StatelessWidget {
  final GolfTheme t;
  final EstadoTablero estado;
  final PerfilResumen r;

  /// Quién soy. Hace falta para acumular MI balance, no el de la ronda.
  final String? miId;

  const _BloqueBalance(
      {required this.t,
      required this.estado,
      required this.r,
      required this.miId});

  @override
  Widget build(BuildContext context) {
    return switch (estado) {
      EstadoTablero.sinIdentidad => _Aviso(
          t: t,
          icono: Icons.person_search_rounded,
          titulo: 'Falta decir quién eres',
          cuerpo:
              'Elige cuál de los jugadores del directorio eres tú y aquí verás '
              'tu balance, tu índice y contra quién juegas.',
          accion: 'Elegir en Ajustes',
          onTap: () => openSettings(context),
        ),
      EstadoTablero.historialPendiente => _Aviso(
          t: t,
          icono: Icons.calculate_outlined,
          titulo: 'Tu histórico está sin calcular',
          cuerpo:
              'Tienes rondas cerradas de antes de que se guardara el resultado '
              'en dinero. Se calcula una vez desde el Historial.',
          accion: 'Calcular en Historial',
          onTap: () => openHistory(context),
        ),
      EstadoTablero.sinRondas => _Aviso(
          t: t,
          icono: Icons.flag_outlined,
          titulo: 'Aún no has cerrado una ronda',
          cuerpo:
              'Cuando termines la primera, aquí aparecerá lo que te dejó y cómo '
              'te va contra los demás.',
          accion: null,
          onTap: null,
        ),
      EstadoTablero.listo => _Cifra(t: t, r: r, miId: miId),
    };
  }
}

/// El número grande.
///
/// Es el único sitio de la pantalla con rojo saturado. La fase 4 movió el score
/// a FORMAS justamente para dejar el canal del color libre para el dinero.
class _Cifra extends StatelessWidget {
  /// Quién soy, para poder acumular MI balance y no el de la ronda.
  final String? miId;
  final GolfTheme t;
  final PerfilResumen r;
  const _Cifra({required this.t, required this.r, required this.miId});

  @override
  Widget build(BuildContext context) {
    final c = colorDe(r.balanceTotal, t);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('BALANCE HISTÓRICO',
            style: TextStyle(
                color: t.sub,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2)),
        const SizedBox(height: 6),
        // Wrap y no Row, por lo mismo que la fila de contadores: medido, la
        // cifra a 38 px más el chip de racha se salían 120 px. Y no lo cazó
        // ningún test durante dos tareas porque los fixtures de geometría
        // tenían racha 0 —el chip no se dibujaba— así que el caso más ancho era
        // justo el que no se probaba. Ahora hay test con racha.
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(importe(r.balanceTotal),
                style: TextStyle(
                    color: c,
                    fontSize: 38,
                    height: 1.0,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            if (r.racha != 0)
              _Chip(
                t: t,
                texto: r.racha > 0
                    ? '${r.racha} seguidas ganando'
                    : '${-r.racha} seguidas perdiendo',
                color: r.racha > 0 ? t.profit : t.loss,
              ),
          ],
        ),
        const SizedBox(height: 12),
        // ── LA FORMA DEL SALDO ────────────────────────────────────────────
        //
        // La cifra de arriba no distingue dos historias muy distintas: un +500
        // que nunca bajó de cero, y un +500 que estuvo en −800 y se recuperó.
        // La línea sí, y es el mismo argumento que acabó destapando los
        // diferenciales imposibles del handicap.
        //
        // Acumulada: la ALTURA es el saldo de entonces y el ESCALÓN es lo que
        // se movió esa ronda, así que se leen las dos preguntas del mismo
        // trazo.
        Builder(builder: (ctx) {
          final resultados = ctx.watch<PerfilProvider>().resultados;
          final yo = miId;
          if (yo == null) return const SizedBox.shrink();
          return GraficoBalance(
            serie: serieDeBalance(resultados, yo),
            t: t,
            // El formato del dinero ya está decidido: no puede haber dos.
            importe: importe,
          );
        }),
        const SizedBox(height: 12),
        Divider(color: t.divider, height: 1),
        const SizedBox(height: 10),
        // Wrap y no Row, y no por gusto: medido, los cuatro contadores con
        // separadores suman 390 px justos, así que en un Row se salían 77 px de
        // la tarjeta a 390 —y más en cualquier teléfono estrecho—. Las
        // etiquetas miden entre 65 y 86 px cada una, bastante más de lo que
        // parece al escribirlas.
        //
        // Con Wrap caen a una segunda línea en vez de recortarse. Un contador
        // que dice "perdi…" es peor que uno en la línea de abajo.
        Wrap(
          spacing: 22,
          runSpacing: 12,
          children: [
            _Dato(t: t, valor: '${r.rondas}', etiqueta: 'rondas'),
            _Dato(t: t, valor: '${r.ganadas}', etiqueta: 'ganadas', color: t.profit),
            _Dato(t: t, valor: '${r.perdidas}', etiqueta: 'perdidas', color: t.loss),
            if (r.tablas > 0)
              _Dato(t: t, valor: '${r.tablas}', etiqueta: 'tablas'),
          ],
        ),
      ]),
    );
  }
}

// ── Contra quién juegas ──────────────────────────────────────────────────────
class _TarjetaRival extends StatelessWidget {
  final GolfTheme t;
  final RivalHabitual rival;
  const _TarjetaRival({required this.t, required this.rival});

  @override
  Widget build(BuildContext context) {
    final c = colorDe(rival.balance, t);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.divider),
      ),
      child: Row(children: [
        GAvatar(name: rival.nombre, colorIndex: 0, size: 38),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('TU RIVAL HABITUAL',
                style: TextStyle(
                    color: t.sub,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1)),
            const SizedBox(height: 2),
            Text(rival.nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: t.text, fontSize: 16, fontWeight: FontWeight.w800)),
            Text(
                '${rival.rondasJuntos} ronda${rival.rondasJuntos == 1 ? '' : 's'} juntos',
                style: TextStyle(color: t.sub, fontSize: 11)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(importe(rival.balance),
              style: TextStyle(
                  color: c,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          Text(
              rival.balance > 0.005
                  ? 'le ganas'
                  : (rival.balance < -0.005 ? 'te gana' : 'en tablas'),
              style: TextStyle(color: t.sub, fontSize: 10)),
        ]),
      ]),
    );
  }
}

// ── Las últimas rondas ───────────────────────────────────────────────────────
class _UltimasRondas extends StatelessWidget {
  final GolfTheme t;
  final List<RondaEnResumen> rondas;
  const _UltimasRondas({required this.t, required this.rondas});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.divider),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(children: [
            Expanded(
              child: Text('ÚLTIMAS RONDAS',
                  style: TextStyle(
                      color: t.sub,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2)),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => openHistory(context),
              child: Text('Ver todo',
                  style: TextStyle(
                      color: t.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
        for (var i = 0; i < rondas.length; i++) ...[
          if (i > 0) Divider(color: t.divider, height: 1, indent: 16, endIndent: 16),
          _FilaRonda(t: t, r: rondas[i]),
        ],
        const SizedBox(height: 6),
      ]),
    );
  }
}

class _FilaRonda extends StatelessWidget {
  final GolfTheme t;
  final RondaEnResumen r;
  const _FilaRonda({required this.t, required this.r});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.campo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: t.text, fontSize: 14, fontWeight: FontWeight.w700)),
            Text(_fecha(r.fecha),
                style: TextStyle(color: t.sub, fontSize: 11)),
          ]),
        ),
        // El score. Ausente se dibuja como raya, NUNCA como cero: un cero se
        // lee como "hizo 0", que es imposible.
        SizedBox(
          width: 52,
          child: Text(
            r.gross == null ? '–' : '${r.gross}',
            textAlign: TextAlign.right,
            style: TextStyle(
                color: r.gross == null ? t.sub : t.text,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
        SizedBox(
          width: 78,
          child: Text(
            importe(r.neto),
            textAlign: TextAlign.right,
            style: TextStyle(
                color: colorDe(r.neto, t),
                fontSize: 15,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
      ]),
    );
  }

  static const _meses = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];

  String _fecha(DateTime d) => '${d.day} ${_meses[d.month - 1]} ${d.year}';
}

// ── Piezas menores ───────────────────────────────────────────────────────────

/// Un estado que no es un número: dice qué falta y cómo resolverlo.
class _Aviso extends StatelessWidget {
  final GolfTheme t;
  final IconData icono;
  final String titulo, cuerpo;
  final String? accion;
  final VoidCallback? onTap;

  const _Aviso({
    required this.t,
    required this.icono,
    required this.titulo,
    required this.cuerpo,
    required this.accion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icono, color: t.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(titulo,
                style: TextStyle(
                    color: t.text, fontSize: 15, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(cuerpo,
            style: TextStyle(color: t.sub, fontSize: 12.5, height: 1.4)),
        if (accion != null && onTap != null) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 36),
                  foregroundColor: t.primary),
              child: Text(accion!,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ]),
    );
  }
}

class _Dato extends StatelessWidget {
  final GolfTheme t;
  final String valor, etiqueta;
  final Color? color;
  const _Dato(
      {required this.t, required this.valor, required this.etiqueta, this.color});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(valor,
              style: TextStyle(
                  color: color ?? t.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          Text(etiqueta, style: TextStyle(color: t.sub, fontSize: 10.5)),
        ],
      );
}

class _Chip extends StatelessWidget {
  final GolfTheme t;
  final String texto;
  final Color color;
  const _Chip({required this.t, required this.texto, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(texto,
            style: TextStyle(
                color: color, fontSize: 10.5, fontWeight: FontWeight.w800)),
      );
}

// ── El bote de los torneos abiertos ──────────────────────────────────────────
//
// Dos bloques, dos totales, nunca una suma. La etiqueta dice "no cobrado"
// porque es exactamente la diferencia: el balance de arriba ya pasó por el
// bolsillo de alguien y esto todavía no.
class _BloqueEnJuego extends StatelessWidget {
  final GolfTheme t;
  final String? miId;
  const _BloqueEnJuego({required this.t, required this.miId});

  @override
  Widget build(BuildContext context) {
    final torneos = context.watch<TorneoProvider>().torneos;
    final resultados = context.watch<PerfilProvider>().resultados;

    final abiertos = torneos.where((x) => !x.cerrado && x.bote.hayBote).toList();
    if (abiertos.isEmpty || miId == null) return const SizedBox.shrink();

    var enJuego = 0.0;
    final voy = <String>[];
    for (final tor in abiertos) {
      // Sin el directorio a propósito: este bloque no enseña NINGÚN nombre de
      // jugador —solo el del torneo— así que pedirlo sería una dependencia que
      // no compra nada. Los nombres se resuelven donde se ven.
      final tabla = tablaDe(tor, resultados);
      // En un cuadro el bote es del campeón, no del líder de la tabla.
      final llave = llaveDe(tor, resultados);
      final bote = boteDe(tor, tabla, campeon: llave.campeon);
      final mia = bote.lineas.where((l) => l.playerId == miId);
      if (mia.isEmpty) continue;
      enJuego += bote.total;
      if (tor.formato == FormatoDeTorneo.eliminacion) {
        // "3º en Match Play" no significa nada: o sigues en el cuadro o no.
        final sigo = llave.rondas
            .expand((r) => r)
            .any((e) => e.ganador == miId || e.jugable && (e.a == miId || e.b == miId));
        voy.add(llave.campeon == miId
            ? 'campeón de ${tor.nombre}'
            : sigo
                ? 'sigues en ${tor.nombre}'
                : 'fuera de ${tor.nombre}');
        continue;
      }
      final fila = tabla.filas.where((f) => f.playerId == miId);
      if (fila.isNotEmpty) {
        voy.add('${fila.first.puesto}º en ${tor.nombre}');
      }
    }
    if (enJuego <= 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.accent.withValues(alpha: 0.45)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('EN JUEGO',
                style: TextStyle(
                    color: t.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1)),
            const SizedBox(width: 6),
            Text('· no cobrado',
                style: TextStyle(color: t.sub, fontSize: 10)),
          ]),
          const SizedBox(height: 6),
          Text('\$${enJuego.toStringAsFixed(0)}',
              style: TextStyle(
                  color: t.text,
                  fontSize: 26,
                  height: 1.0,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(height: 4),
          Text(
              'en ${abiertos.length} torneo${abiertos.length == 1 ? '' : 's'} '
              'abierto${abiertos.length == 1 ? '' : 's'}'
              '${voy.isEmpty ? '' : ' · vas ${voy.join(', ')}'}',
              style: TextStyle(color: t.sub, fontSize: 11.5, height: 1.3)),
        ]),
      ),
    );
  }
}
