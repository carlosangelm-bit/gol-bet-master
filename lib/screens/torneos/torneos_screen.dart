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
import '../../core/golf_icons.dart';
import '../../models/round_result.dart';
import '../../models/torneo.dart';
import '../../services/firestore_service.dart';
import '../../services/live_round_service.dart';
import '../../services/auth_service.dart';
import '../../models/torneo_publicado.dart';
import '../../models/punto_de_torneo.dart';
import '../../providers/betting_group_provider.dart';
import '../setup/quick_start_screen.dart';
import 'package:flutter/services.dart';
import '../../providers/perfil_provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/torneo_provider.dart';
import 'torneo_editor_screen.dart';
import 'torneo_enlace_screen.dart';
import 'llave_screen.dart';
import 'tele_sheet.dart';

/// La cifra con signo la define el modelo: la usan la tabla, el cuadro y la
/// vista de invitado, y tres copias habrían acabado dando tres formatos.
String importePuntos(double v) => importeDelTorneo(v);

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
      body: prov.torneos.isEmpty && prov.seguidos.isEmpty
          ? _vacio(t)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
              children: [
                for (final tor in prov.torneos)
                  _TarjetaTorneo(torneo: tor, t: t),

                // ── Los que sigo, de otros ────────────────────────────
                //
                // Es el camino de VUELTA, y sin él el bucle no cerraba: alguien
                // que llegó por un enlace, siguió el torneo y entró en la app se
                // quedaba sin forma de volver a verlo. Un enlace en WhatsApp no
                // es una manera de navegar.
                //
                // Van aparte y abren la vista compartida, no el editor: un torneo
                // de otro no se configura. La tarjeta lo dice.
                if (prov.seguidos.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('TORNEOS QUE SIGUES',
                      style: TextStyle(
                          color: t.sub,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8)),
                  const SizedBox(height: 8),
                  for (final seg in prov.seguidos)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Material(
                        color: t.card,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => TorneoEnlaceScreen(
                                      token: seg.token))),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(children: [
                              Icon(GolfIcons.deClave(seg.emoji), size: GolfIcons.juntoAlHeroe),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(seg.nombre,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: t.text,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w800)),
                                      Text(
                                          'De otro organizador · juegas como '
                                          '${seg.jugadorNombre}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: t.sub, fontSize: 11.5)),
                                    ]),
                              ),
                              Icon(Icons.chevron_right_rounded, color: t.sub),
                            ]),
                          ),
                        ),
                      ),
                    ),
                ],
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
              const Icon(GolfIcons.trofeo, size: GolfIcons.juntoAlHeroe),
              const SizedBox(height: 12),
              Text('Ningún torneo todavía',
                  style: TextStyle(
                      color: t.text, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                  'Eliges quién está inscrito, qué rondas cuentan y cómo '
                  'puntúan. Los participantes los define el torneo, no tu '
                  'lista de compañeros.',
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
    // Los nombres del DIRECTORIO: un inscrito que todavía no ha jugado no
    // aparece en ningún RoundResult, y sin esto la tarjeta enseñaba su id.
    final nombres = context.watch<PlayerProvider>().nombres;
    final tabla = tablaDe(torneo, resultados, nombres: nombres);
    final esCuadro = torneo.formato == FormatoDeTorneo.eliminacion;

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
              // El emoji del torneo no lo elige nadie: es siempre el mismo por
              // defecto. Así que es chrome, no contenido, y va como icono.
              Icon(GolfIcons.trofeo, size: 26, color: t.primary),
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
                      // Un cuadro NO se resume por rondas y posición: en
                      // eliminación no hay ninguna de las dos, hay partidos. Lo
                      // que hace falta de un vistazo es a quién le toca.
                      if (esCuadro) ...[
                        Text(
                            'Eliminación · ${torneo.participantes.length} '
                            'inscrito${torneo.participantes.length == 1 ? '' : 's'} · '
                            '${metodoEfectivo(torneo).label}',
                            style: TextStyle(color: t.sub, fontSize: 11.5)),
                        Text(resumenDeLlave(llaveDe(torneo, resultados), nombres),
                            style: TextStyle(
                                color: t.primary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700)),
                      ] else ...[
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
                      ],
                      // Lo que el método no pudo puntuar se dice AQUÍ también:
                      // una tabla corta, desde fuera, parece completa.
                      if (tabla.rondasSinDato > 0)
                        Text(
                            '${tabla.rondasSinDato} sin el dato que pide este '
                            'método',
                            style: TextStyle(
                                color: t.scoreOver.withValues(alpha: 0.9),
                                fontSize: 10.5)),
                      // Sin bote no se habla de bote. Un torneo que se juega sin
                      // dinero —que es lo normal en eliminación— no debería
                      // mencionarlo en ninguna línea.
                      if (tabla.sinListaDeParticipantes)
                        Text(
                            torneo.bote.hayAlgunBote
                                ? 'Sin lista de participantes · el bote no se calcula'
                                : 'Sin lista de participantes',
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

/// La pantalla de un torneo, con los resultados PUBLICADOS por otros incluidos.
///
/// Es la mitad que faltaba de la agregación. La tabla salía de
/// users/{miUid}/roundResults, así que en una liga —donde cada jugador cierra su
/// ronda— contaba menos rondas de las que había, y sin avisar.
///
/// Los publicados se cargan una vez al abrir. No en tiempo real a propósito: una
/// tabla que cambia mientras la lees es peor que una que se refresca al volver, y
/// una consulta por torneo cada vez que alguien cierra una ronda cuesta.
class TorneoTablaScreen extends StatefulWidget {
  final Torneo torneo;
  const TorneoTablaScreen({super.key, required this.torneo});

  @override
  State<TorneoTablaScreen> createState() => _TorneoTablaScreenState();
}

class _TorneoTablaScreenState extends State<TorneoTablaScreen> {
  List<RoundResult> _publicados = const [];
  int _descartados = 0;

  /// Cuántos resultados de seguidores LLEGARON, contados antes de filtrar.
  ///
  /// Es la cifra que resuelve el diagnóstico de un solo golpe: con cero, la
  /// cadena se paró antes —marca o envío—; con más de cero y todos descartados,
  /// se paró en el filtro. Sin ella las dos cosas se ven igual: una tabla vacía.
  int _llegaron = 0;

  /// Si la lectura falló. Distinto de "no ha llegado nada".
  String? _errorAlLeer;
  bool _cargado = false;

  @override
  void initState() {
    super.initState();
    _cargarPublicados();
  }

  Future<void> _cargarPublicados() async {
    final leido =
        await FirestoreService.resultadosPublicados(widget.torneo.id);
    if (!mounted) return;
    final crudos = leido.lista;
    // Solo los de gente INSCRITA. Es la comprobación que la regla no puede
    // hacer, y por eso se hace aquí. Ver resultadosQueCuentan.
    final vivo = context.read<TorneoProvider>().torneos
        .where((x) => x.id == widget.torneo.id)
        .firstOrNull ??
        widget.torneo;
    // Los nombres del directorio: el filtro empareja por nombre porque es lo
    // único que el organizador y quien publica comparten.
    final buenos = resultadosQueCuentan(vivo, crudos,
        nombres: context.read<PlayerProvider>().nombres);
    setState(() {
      _publicados = buenos;
      _descartados = crudos.length - buenos.length;
      _llegaron = crudos.length;
      _errorAlLeer = leido.error;
      _cargado = true;
    });
  }

  @override
  Widget build(BuildContext context) => _TorneoTabla(
        torneo: widget.torneo,
        publicados: _publicados,
        descartados: _descartados,
        llegaron: _llegaron,
        errorAlLeer: _errorAlLeer,
        cargado: _cargado,
      );
}

class _TorneoTabla extends StatelessWidget {
  /// El torneo con el que se abrió la pantalla.
  ///
  /// **No se pinta desde aquí.** Se usa solo para saber QUÉ torneo es; lo que se
  /// enseña sale del provider por id.
  final Torneo torneo;

  /// Los resultados que otros publicaron a este torneo, ya filtrados.
  final List<RoundResult> publicados;

  /// Cuántos se descartaron por venir de alguien no inscrito. Se DICE: un
  /// silencio aquí es exactamente el fallo que esto viene a arreglar.
  final int descartados;

  /// Cuántos LLEGARON, antes de filtrar, y si la lectura falló. Ver el aviso.
  final int llegaron;
  final String? errorAlLeer;
  final bool cargado;

  const _TorneoTabla(
      {required this.torneo,
      this.publicados = const [],
      this.descartados = 0,
      this.llegaron = 0,
      this.errorAlLeer,
      this.cargado = false});

  /// El torneo VIVO. Es la diferencia entre enseñar lo guardado y enseñar lo que
  /// llegó al abrir la pantalla.
  ///
  /// El bug que arregla: se editaba la lista de participantes, se guardaba, se
  /// volvía, y la pantalla seguía diciendo "falta la lista" con el bote a cero.
  /// La lista SÍ se había guardado —el modelo la persiste bien, comprobado— pero
  /// esta pantalla renderizaba el objeto que recibió al construirse, que es de
  /// antes de editar.
  ///
  /// Es el mismo patrón de siempre en otra dirección: no que la UI reaccione y el
  /// modelo no se entere, sino que el modelo cambie y la UI mire una copia vieja.
  /// Yo mismo escribí un helper para esquivarlo al compartir —"para no publicar
  /// una versión vieja"— y no arreglé la pantalla que tenía el mismo problema.
  Torneo _vivo(BuildContext context) {
    final lista = context.watch<TorneoProvider>().torneos;
    final match = lista.where((x) => x.id == torneo.id);
    // Si ya no está —lo borraron desde otro sitio— se enseña el último que se
    // conoce en vez de una pantalla vacía.
    return match.isEmpty ? torneo : match.first;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.gt;
    final torneo = _vivo(context);
    // Lo propio MÁS lo que otros publicaron, sin contar una ronda dos veces.
    final resultados = resultadosUnidos(
        context.watch<PerfilProvider>().resultados, publicados);
    final nombres = context.watch<PlayerProvider>().nombres;
    final tabla = tablaDe(torneo, resultados, nombres: nombres);
    // El cuadro se deriva una vez y se usa para todo: el bloque de arriba, y el
    // bote —que en eliminación es del campeón, no del líder de la tabla—.
    final llave = llaveDe(torneo, resultados);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        foregroundColor: t.text,
        title: Text(torneo.nombre),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.ios_share, color: t.sub),
            tooltip: 'Compartir',
            onPressed: () => _compartir(context, torneo, tabla, llave),
          ),
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
          // ── Qué ha llegado de quien sigue el torneo ───────────────────────
          //
          // Va arriba y se dice SIEMPRE que el torneo esté compartido, porque es
          // la línea que contesta "¿por qué está la tabla en cero?" sin tener
          // que abrir la consola de Firestore. Tres respuestas distintas con
          // tres arreglos distintos, y antes las tres se veían igual.
          if (torneo.tokenCompartido != null && cargado)
            _AvisoDeLoQuePublicaron(
                t: t,
                llegaron: llegaron,
                descartados: descartados,
                error: errorAlLeer),

          // ── Jugar una ronda DEL torneo ────────────────────────────────────
          //
          // La corrección de dirección, en el sitio donde más se nota: el torneo
          // es el evento del que salen las rondas, no una vista sobre las que ya
          // hay. Va PRIMERO porque durante un torneo en marcha es lo que se viene
          // a hacer; la tabla se mira después de jugar.
          _BotonJugarDelTorneo(torneo: torneo, t: t, nombres: nombres),
          const SizedBox(height: 14),

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
                  Text(
                      torneo.formato == FormatoDeTorneo.eliminacion
                          ? 'CÓMO SE GANA UN PARTIDO'
                          : 'CÓMO SE PUNTÚA',
                      style: TextStyle(
                          color: t.sub,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8)),
                  const SizedBox(height: 6),
                  Text(metodoEfectivo(torneo).descripcion,
                      style: TextStyle(
                          color: t.text, fontSize: 12.5, height: 1.35)),
                  if (aplicaEnFormato(
                          SeccionDelTorneo.puntosPorPuesto, torneo.formato) &&
                      torneo.metodo == MetodoDePuntuacion.posicion) ...[
                    const SizedBox(height: 4),
                    Text(
                        'Puntos: ${torneo.puntosPorPuesto.join(' · ')}'
                        '   ·   Empates: ${torneo.empate.label.toLowerCase()}',
                        style: TextStyle(color: t.sub, fontSize: 11.5)),
                  ],
                  const SizedBox(height: 4),
                  // En un cuadro no hay acumulación ni mínimo: se dice lo que sí
                  // hay, que es que el que pierde queda fuera.
                  if (torneo.formato == FormatoDeTorneo.eliminacion)
                    Text(
                        'Eliminación directa: los dos del partido juegan la misma '
                        'ronda y el que pierde queda fuera.',
                        style: TextStyle(color: t.sub, fontSize: 11.5))
                  else ...[
                    Text(
                        torneo.acumulacion == Acumulacion.mejoresDeN
                            ? 'Solo cuentan las ${torneo.mejoresN} mejores de cada uno.'
                            : 'Suman todas las rondas.',
                        style: TextStyle(color: t.sub, fontSize: 11.5)),
                    if (torneo.minimoRondas > 0)
                      Text(
                          'Hacen falta ${torneo.minimoRondas} rondas para clasificar.',
                          style: TextStyle(color: t.sub, fontSize: 11.5)),
                  ],
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

          // Lo que llegó y NO se contó. Decirlo es la diferencia entre una tabla
          // incompleta y una tabla incompleta que se sabe.
          if (descartados > 0) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(11),
                border:
                    Border.all(color: t.scoreOver.withValues(alpha: 0.6)),
              ),
              child: Text(
                  '$descartados resultado${descartados == 1 ? '' : 's'} '
                  '${descartados == 1 ? 'llegó' : 'llegaron'} de alguien que no '
                  'está en la lista de participantes, así que no '
                  '${descartados == 1 ? 'cuenta' : 'cuentan'}. Si debería '
                  'contar, añádelo a la lista.',
                  style:
                      TextStyle(color: t.text, fontSize: 11.5, height: 1.35)),
            ),
            const SizedBox(height: 14),
          ],

          // ── Los grupos que están jugando ──────────────────────────
          //
          // Solo para el organizador, y es LA PIEZA DE LA AGREGACIÓN: la tabla
          // sale de sus roundResults, y ahí entra lo que él cierra. Con
          // veinticinco grupos, poder cerrarlos sin cargarlos uno a uno es la
          // diferencia entre un torneo y una tarde de tocar el teléfono.
          _GruposDelTorneo(torneoId: torneo.id, t: t),

          // ── El cuadro, si es de eliminación ────────────────────────
          //
          // Va ANTES de la tabla porque en un cuadro la pregunta es a quién te
          // toca, no cuánto acumulas. La tabla se sigue enseñando debajo —son
          // las mismas rondas y el dinero cuenta igual— pero deja de ser lo
          // primero que se lee.
          if (torneo.formato == FormatoDeTorneo.eliminacion) ...[
            LlaveDelTorneoVista(
                torneo: torneo, llave: llave),
            const SizedBox(height: 22),
            Text('Y LA CUENTA DE SIEMPRE', style: GolfType.label(t.sub)),
            const SizedBox(height: 8),
          ],

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
            _BloqueBote(
                torneo: torneo,
                bote: boteDe(torneo, tabla, campeon: llave.campeon),
                t: t),
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

/// Publica la copia y ofrece el enlace.
///
/// Publicar es una ACCIÓN, no algo automático: es más predecible y más barato, y
/// con el sello de fecha en la vista de invitado un enlace rancio se ve. Volver a
/// tocar aquí actualiza el MISMO enlace, así que quien ya lo tiene en WhatsApp no
/// se queda con una copia muerta.
Future<void> _compartir(BuildContext context, Torneo torneoArg,
    TablaDelTorneo tabla, LlaveDelTorneo llave) async {
  final t = context.gt;
  final prov = context.read<TorneoProvider>();

  // Llega el torneo VIVO desde la pantalla, que ya lo resuelve contra el
  // provider. Antes había aquí un findAncestorWidgetOfExactType para esquivar la
  // copia vieja: era un parche sobre el bug de al lado, y con la pantalla
  // arreglada sobra.
  if (tabla.sinListaDeParticipantes) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text(
          'Define primero los participantes: compartir una tabla con gente que '
          'no se inscribió empeora el problema en vez de arreglarlo.'),
      duration: Duration(seconds: 5),
    ));
    return;
  }

  final uid = AuthService.uid;
  if (uid == null) return;

  final token = torneoArg.tokenCompartido ??
      'tor_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
  final ahora = DateTime.now();
  final copia = TorneoPublicado.desde(
    token: token,
    ownerUid: uid,
    torneo: torneoArg,
    tabla: tabla,
    bote: boteDe(torneoArg, tabla, campeon: llave.campeon),
    jornadas: botesPorJornada(torneoArg, tabla),
    cuando: ahora,
    // El cuadro entra solo si el torneo es de eliminación: llaveDe() devuelve
    // vacío en una liga, y un campo vacío no se escribe.
    llave: llave,
    nombres: {
      for (final pw in context.read<PlayerProvider>().directory)
        pw.player.id: pw.displayName,
    },
  );

  try {
    await FirestoreService.publicarTorneo(copia);
    await prov.guardar(torneoArg.copyWith(
        tokenCompartido: token, publicadoEn: ahora));
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo publicar: $e')));
    }
    return;
  }
  if (!context.mounted) return;

  final enlace = 'https://golf-bet-master.web.app/torneo/$token';
  showModalBottomSheet(
    context: context,
    backgroundColor: t.bg,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Enlace del torneo',
              style: TextStyle(
                  color: t.text, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
              'Quien lo abra ve la tabla en solo lectura. Lo que se publica es '
              'una COPIA con fecha: si añades rondas, vuelve aquí para '
              'actualizarla.',
              style: TextStyle(color: t.sub, fontSize: 12, height: 1.4)),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: t.divider),
            ),
            child: SelectableText(enlace,
                style: TextStyle(color: t.text, fontSize: 12.5)),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: enlace));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Enlace copiado')));
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: t.primary,
                  foregroundColor: t.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 13)),
              icon: const Icon(Icons.copy, size: 17),
              label: const Text('Copiar para WhatsApp',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
              'Este enlace es el mismo toda la vida del torneo: al actualizar la '
              'tabla no cambia, así que no hay que reenviarlo.',
              style: TextStyle(color: t.sub, fontSize: 11, height: 1.35)),
          // La pantalla de la casa club. Va DESPUÉS y con separador porque es
          // otro enlace, otra tabla y otras reglas: la de arriba pide cuenta y
          // lleva el bote; esta se ve sin cuenta y no lleva un importe.
          BloqueTele(torneo: torneoArg, tabla: tabla),
          const SizedBox(height: 10),
          // APAGAR, no borrar. Un enlace de WhatsApp acaba donde no se previó, así
          // que hay que poder cortarlo; pero borrarlo obligaba a generar otro
          // token al volver a publicar, o sea a reenviárselo a doce personas.
          //
          // Apagar deja el documento con solo el dueño y la bandera: los nombres
          // y las cifras dejan de servirse de verdad. Lo que sobrevive es el
          // token.
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () async {
                await FirestoreService.apagarEnlace(token);
                // Y LA PANTALLA CON ÉL. "Dejar de compartir" tiene que apagar
                // las dos superficies, porque la de la tele es la MÁS expuesta
                // —se lee sin cuenta— y dejarla encendida haría del botón una
                // mentira. Ver la cabecera de tele_sheet.dart.
                final vivo = prov.torneos.firstWhere(
                    (x) => x.id == torneoArg.id,
                    orElse: () => torneoArg);
                await apagarTele(vivo);
                // Los tokens SE CONSERVAN: volver a publicar usa los mismos.
                await prov.guardar(
                    vivo.copyWith(publicadoEn: null, apagarTele: true));
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(vivo.tokenTele != null
                          ? 'Enlace y pantalla apagados. Los mismos enlaces '
                              'vuelven a servir si lo compartes otra vez.'
                          : 'Enlace apagado. Quien lo tenga verá que ya no se '
                              'comparte; el mismo enlace vuelve a servir si lo '
                              'compartes otra vez.'),
                      duration: Duration(seconds: 5)));
                }
              },
              style: OutlinedButton.styleFrom(
                  side: BorderSide(color: t.divider),
                  foregroundColor: t.sub,
                  padding: const EdgeInsets.symmetric(vertical: 12)),
              child: const Text('Dejar de compartir'),
            ),
          ),
        ]),
      ),
    ),
  );
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
        // Wrap y no Row. Es la TERCERA vez en la sesión que el mismo patrón
        // —cifra grande a 30 px más una etiqueta al lado— se sale por la
        // derecha: pasó con la fila de contadores del tablero, con la cifra del
        // balance y su chip de racha, y aquí. La forma es la culpable, no los
        // números concretos: dos Text sin Flexible en un Row toman su ancho
        // intrínseco y no hay quien los ceda.
        //
        // Con Wrap la etiqueta baja de línea en vez de recortarse, y deja de
        // importar cuánto midan el importe o el número de jugadores.
        Wrap(
          spacing: 8,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text('\$${bote.total.toStringAsFixed(0)}',
                style: TextStyle(
                    color: t.text,
                    fontSize: 30,
                    height: 1.0,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                  '\$${torneo.bote.entrada.toStringAsFixed(0)} por jugador · '
                  '${bote.lineas.length} inscrito'
                  '${bote.lineas.length == 1 ? '' : 's'}',
                  style: TextStyle(color: t.sub, fontSize: 11.5)),
            ),
          ],
        ),
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

/// Los grupos en juego de un torneo, para el organizador.
///
/// De dónde sale la agregación: la tabla del torneo lee los roundResults de quien
/// la mira, y el resultado de una ronda se escribe al CERRARLA, en la colección
/// de quien cierra. Como cerrar una ronda en vivo está reservado al dueño, si el
/// organizador es dueño de las rondas de su torneo los resultados caen solos
/// donde la tabla los busca.
///
/// Así que esto no es una pantalla de conveniencia: es el sitio por donde entran
/// los datos. Sin ella, con veinticinco grupos había que cargar cada ronda como
/// "la actual" para cerrarla, y el estado de la app sostiene una sola.
class _GruposDelTorneo extends StatefulWidget {
  final String torneoId;
  final GolfTheme t;
  const _GruposDelTorneo({required this.torneoId, required this.t});

  @override
  State<_GruposDelTorneo> createState() => _GruposDelTorneoState();
}

class _GruposDelTorneoState extends State<_GruposDelTorneo> {
  List<({
    String roundId,
    String nombre,
    List<String> jugadores,
    int hoyosCapturados,
    int totalHoles,
    bool cerrada,
  })>? _grupos;
  String? _cerrando;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final g = await LiveRoundService.gruposDelTorneo(widget.torneoId);
    if (mounted) setState(() => _grupos = g);
  }

  Future<void> _cerrar(String roundId) async {
    setState(() => _cerrando = roundId);
    final ok = await LiveRoundService.cerrarRondaDelTorneo(roundId);
    if (!mounted) return;
    setState(() => _cerrando = null);
    await _cargar();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Ronda cerrada. Su resultado ya cuenta para el torneo.'
          : 'No se pudo cerrar. Solo la cierra quien la organizó.'),
      duration: const Duration(seconds: 4),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final g = _grupos;
    // Mientras carga, nada: un hueco con un spinner encima de la tabla
    // distraería de lo que sí está.
    if (g == null || g.isEmpty) return const SizedBox.shrink();

    final abiertas = g.where((x) => !x.cerrada).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.divider),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('GRUPOS DE ESTE TORNEO', style: GolfType.label(t.sub)),
          const SizedBox(height: 4),
          Text(
              abiertas.isEmpty
                  ? '${g.length} ronda${g.length == 1 ? '' : 's'}, '
                      '${g.length == 1 ? 'cerrada' : 'todas cerradas'}. Sus '
                      'resultados ya cuentan.'
                  : '${abiertas.length} sin cerrar de ${g.length}. Una ronda '
                      'cuenta para la tabla cuando la cierras.',
              style: TextStyle(color: t.sub, fontSize: 11.5, height: 1.35)),
          const SizedBox(height: 8),
          for (final x in g)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: t.divider),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(x.nombre,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: t.text,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                          Text(
                              '${x.jugadores.join(', ')} · '
                              '${x.hoyosCapturados}/${x.totalHoles} hoyos',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: t.sub, fontSize: 11)),
                        ]),
                  ),
                  const SizedBox(width: 8),
                  if (x.cerrada)
                    Icon(Icons.check_circle, color: t.primary, size: 18)
                  else
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _cerrando == null ? () => _cerrar(x.roundId) : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: t.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: t.primary),
                        ),
                        child: Text(
                            _cerrando == x.roundId ? 'Cerrando…' : 'Cerrar',
                            style: TextStyle(
                                color: t.primary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800)),
                      ),
                    ),
                ]),
              ),
            ),
          // Lo que un grupo a medio capturar significa, dicho: cerrar una ronda
          // incompleta la mete en la tabla con los hoyos que tenga.
          if (abiertas.any((x) => x.hoyosCapturados < x.totalHoles)) ...[
            const SizedBox(height: 4),
            Text(
                'Cerrar una ronda a medias la cuenta con los hoyos que tenga. '
                'Si el grupo sigue en el campo, espera.',
                style: TextStyle(color: t.sub, fontSize: 10.5, height: 1.3)),
          ],
        ]),
      ),
    );
  }
}


/// "Jugar mi ronda de Copa de Primavera" — desde el torneo, no desde un
/// asistente en blanco.
///
/// Lo que decide qué se ofrece es lo que el torneo puede responder:
///
///   · Sin participantes → no hay padrón, y sin padrón esto no ahorra nada. Se
///     dice qué falta en vez de ofrecer un atajo que no atajaría.
///   · Con padrón y plantilla → la ronda existe con su gente y sus apuestas.
///   · Con padrón y sin plantilla → la gente y la ventaja puestas, las apuestas
///     se eligen. Es el mismo trato que recibe quien sigue el torneo.
class _BotonJugarDelTorneo extends StatelessWidget {
  final Torneo torneo;
  final GolfTheme t;
  final Map<String, String> nombres;
  const _BotonJugarDelTorneo(
      {required this.torneo, required this.t, required this.nombres});

  @override
  Widget build(BuildContext context) {
    // Un torneo cerrado ya no admite rondas: la tabla no va a cambiar. Ofrecer
    // jugar ahí sería prometer que cuenta cuando no cuenta.
    if (torneo.cerrado) return const SizedBox.shrink();

    final punto = PuntoDeTorneo.propio(torneo, nombres: nombres);
    if (!punto.utilizable) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.divider),
        ),
        child: Text(
            'Define los participantes y este torneo podrá crear sus rondas: con '
            'el padrón puesto, una ronda del torneo sale con su gente y su '
            'ventaja sin volver a elegirlas.',
            style: TextStyle(color: t.sub, fontSize: 12, height: 1.35)),
      );
    }

    final grupos = context.watch<BettingGroupProvider>().groups;
    final plantilla = torneo.plantillaId == null
        ? null
        : grupos.where((g) => g.id == torneo.plantillaId).firstOrNull;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      QuickStartScreen(grupo: plantilla, torneo: punto))),
          style: ElevatedButton.styleFrom(
              backgroundColor: t.primary,
              foregroundColor: t.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 13)),
          child: Text('Jugar una ronda de ${torneo.nombre}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ),
      const SizedBox(height: 5),
      Text(
          plantilla == null
              ? 'Sale con los inscritos y la ventaja del torneo, y ya marcada. '
                  'Fija una plantilla en el editor y traerá también las apuestas.'
              : 'Sale con los inscritos, la ventaja y las apuestas del torneo, '
                  'y ya marcada.',
          style: TextStyle(color: t.sub, fontSize: 10.5, height: 1.3)),
    ]);
  }
}


/// La línea que contesta "¿por qué está la tabla en cero?".
///
/// ── Tres causas, tres frases ──────────────────────────────────────────────
///
/// Un resultado de alguien que sigue el torneo pasa por tres puertas: que su
/// ronda quede MARCADA, que al cerrarla se PUBLIQUE, y que el filtro de
/// inscritos la CUENTE. Las tres fallan igual de callado y tienen arreglos
/// distintos, así que llevaron una entrega entera de diagnóstico a ciegas.
///
/// Esto las separa con la única cifra que hace falta: cuántos documentos
/// LLEGARON, contados antes de filtrar.
///
///   · Error al leer      → no es la cadena, es el acceso
///   · 0 llegaron         → se paró antes: la marca o el envío. Y quien cerró la
///                          ronda vio en su pantalla cuál de los dos —ver
///                          EnvioAlTorneo—
///   · N llegaron, N fuera → se paró en el filtro: el nombre reclamado no está
///                          entre los inscritos
///   · N llegaron, algunos dentro → funciona, y se dice cuántos
class _AvisoDeLoQuePublicaron extends StatelessWidget {
  final GolfTheme t;
  final int llegaron;
  final int descartados;
  final String? error;
  const _AvisoDeLoQuePublicaron(
      {required this.t,
      required this.llegaron,
      required this.descartados,
      this.error});

  @override
  Widget build(BuildContext context) {
    final err = error;
    final (texto, alerta) = switch (0) {
      _ when err != null => (
          'No se pudieron leer los resultados que otros publicaron. No es que no '
              'haya llegado nada: es que no se pudo consultar. ($err)',
          true
        ),
      _ when llegaron == 0 => (
          'Todavía no ha llegado ningún resultado de quien sigue este torneo. Si '
              'alguien cerró una ronda marcada para el torneo y no aparece aquí, '
              'el aviso que vio al cerrarla dice si se envió o no.',
          false
        ),
      _ when descartados == llegaron => (
          '$llegaron resultado${llegaron == 1 ? '' : 's'} '
              '${llegaron == 1 ? 'llegó' : 'llegaron'}, y '
              '${llegaron == 1 ? 'se descartó' : 'se descartaron'} '
              '${llegaron == 1 ? 'el' : 'todos'}: el nombre que '
              '${llegaron == 1 ? 'reclama' : 'reclaman'} no está entre los '
              'inscritos. Si debería estar, añádelo a los participantes con ese '
              'nombre exacto.',
          true
        ),
      _ => (
          '${llegaron - descartados} de $llegaron resultado'
              '${llegaron == 1 ? '' : 's'} publicado'
              '${llegaron == 1 ? '' : 's'} '
              '${llegaron - descartados == 1 ? 'cuenta' : 'cuentan'} en esta '
              'tabla.',
          false
        ),
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: alerta ? t.scoreOver.withValues(alpha: 0.55) : t.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('LO QUE HAN PUBLICADO', style: GolfType.label(t.sub)),
        const SizedBox(height: 5),
        Text(texto,
            style: TextStyle(color: t.text, fontSize: 12, height: 1.4)),
      ]),
    );
  }
}
