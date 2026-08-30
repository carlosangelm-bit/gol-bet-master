// ─────────────────────────────────────────────────────────────────────────────
// LEADERBOARD PROYECTABLE — /tv/{token}
//
// La pantalla de la casa club. No es la app en grande: es otra superficie con
// otras reglas, y las dos que la definen no aparecen en ninguna otra pantalla
// del proyecto.
//
// ── 1 · SE MIRA DESDE DIEZ METROS ───────────────────────────────────────────
//
// El tamaño de fuente que funciona en un móvil a medio metro es ilegible en una
// TV al otro lado del salón. Y no es cuestión de "poner el texto más grande":
// una talla fija en píxeles se ve distinta en un monitor de 24" y en una tele de
// 65", porque lo que cambia no es la resolución sino la DISTANCIA.
//
// Así que todo se dimensiona contra el ALTO de la pantalla, no en píxeles
// sueltos: una fila ocupa una fracción del alto, y esa fracción se mantiene en
// cualquier panel. Doce filas visibles a pantalla completa es el número que hace
// que la fila mida ~1/16 del alto — en una tele de 65" a diez metros eso es
// aproximadamente el tamaño angular de un titular de periódico a un brazo.
//
// De ahí también sale el resto de la estética: fondo oscuro (una tele encendida
// ocho horas con fondo blanco es un foco), números tabulares para que las
// columnas no bailen al actualizarse, y peso alto en el puesto y en la medida,
// que son las dos cosas que se leen de lejos.
//
// ── 2 · SE QUEDA SOLA OCHO HORAS ────────────────────────────────────────────
//
// Nadie va a tocar esta pantalla. Si algo se rompe a las dos de la tarde, sigue
// roto hasta que alguien pase por delante y lo note — y para entonces el torneo
// terminó.
//
// Tres cosas la sostienen, y cada una cubre un fallo distinto:
//
//   · El STREAM entrega los cambios en segundos. Es la vía normal.
//   · El LATIDO relee cada pocos minutos, porque una conexión que lleva ocho
//     horas abierta es justo donde se cae en silencio.
//   · El REMONTAJE, que es lo que faltaba: si un error de render deja el árbol
//     roto, releer no arregla nada — el widget sigue muerto. El latido cambia
//     la clave del subárbol cada vez, así que un fallo de pintado se limpia
//     solo en el siguiente ciclo en vez de quedarse en blanco todo el día.
//
// Y ErrorWidget.builder se sustituye MIENTRAS esta pantalla vive: el de la app
// enseña detalles del error, que aquí sería un volcado técnico proyectado en una
// pared delante de los socios del club.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/golf_icons.dart';
import '../../models/leaderboard_publico.dart';
import '../../services/firestore_service.dart';

class LeaderboardTvScreen extends StatefulWidget {
  final String token;

  /// Salta Firestore y arranca con estos datos —o sin ninguno—. **Para tests.**
  ///
  /// Firestore no existe en el harness, y lo que hay que poder probar es lo que
  /// esta pantalla decide —los tamaños, la paginación, que nunca se quede en
  /// blanco— no que Firestore entregue. Con [modoDePrueba] no se abre el stream
  /// ni el latido; el paso de página sí, que es de esta pantalla.
  final bool modoDePrueba;
  final LeaderboardPublico? datosDePrueba;

  const LeaderboardTvScreen({
    super.key,
    required this.token,
    this.modoDePrueba = false,
    this.datosDePrueba,
  });

  /// Cuántas filas caben en una pantalla.
  static const int filasPorPagina = 12;

  /// La unidad de la que sale TODO el tamaño de esta pantalla.
  ///
  /// Es lo que hace verificable "se ve desde diez metros": un test fija que el
  /// texto no baje de cierta fracción del alto, y entonces nadie puede
  /// encogerlo más adelante sin que salte una prueba.
  static double unidadDe(double altoDePantalla) => altoDePantalla / 16;

  @override
  State<LeaderboardTvScreen> createState() => _LeaderboardTvScreenState();
}

class _LeaderboardTvScreenState extends State<LeaderboardTvScreen> {
  /// Cada cuánto relee el latido. Ver la cabecera: no es para traer datos
  /// —de eso vive el stream— es para sobrevivir a que el stream ya no traiga
  /// nada y nadie se entere.
  static const _latido = Duration(minutes: 3);

  /// Cada cuánto pasa de página cuando la tabla no cabe.
  static const _paso = Duration(seconds: 12);

  StreamSubscription<LeaderboardPublico?>? _sub;
  Timer? _timerLatido;
  Timer? _timerPagina;

  LeaderboardPublico? _datos;
  bool _cargando = true;

  /// Cambia en cada latido. Es la clave del subárbol, así que un error de
  /// render no sobrevive a un ciclo.
  int _generacion = 0;

  int _pagina = 0;
  int _logo = 0;

  /// El `ErrorWidget.builder` de la app, para devolverlo al salir.
  ErrorWidgetBuilder? _builderPrevio;

  @override
  void initState() {
    super.initState();
    if (widget.modoDePrueba) {
      _datos = widget.datosDePrueba;
      _cargando = false;
      _timerPagina = Timer.periodic(_paso, (_) => _avanzar());
      return;
    }
    _escuchar();
    _timerLatido = Timer.periodic(_latido, (_) => _latir());
    _timerPagina = Timer.periodic(_paso, (_) => _avanzar());
  }

  @override
  void dispose() {
    // Se devuelve el de la app: `ErrorWidget.builder` es global, y dejar el
    // nuestro puesto convertiría cualquier error de otra pantalla en un
    // "Actualizando…" que no dice nada al que sí puede arreglarlo.
    if (_builderPrevio != null) ErrorWidget.builder = _builderPrevio!;
    _sub?.cancel();
    _timerLatido?.cancel();
    _timerPagina?.cancel();
    super.dispose();
  }

  void _escuchar() {
    _sub?.cancel();
    _sub = FirestoreService.leaderboardStream(widget.token).listen(
      (d) {
        if (!mounted) return;
        setState(() {
          _datos = d;
          _cargando = false;
        });
      },
      // Sin onError la excepción sube y mata la suscripción en silencio, que es
      // exactamente el fallo que esta pantalla no puede permitirse.
      onError: (_) {
        if (mounted) setState(() => _cargando = false);
      },
    );
  }

  /// El latido: releer, remontar y, si el stream murió, resucitarlo.
  Future<void> _latir() async {
    final fresco = await FirestoreService.leerLeaderboard(widget.token);
    if (!mounted) return;
    setState(() {
      if (fresco != null) _datos = fresco;
      _cargando = false;
      _generacion++;
    });
    // Volver a suscribirse es barato y cubre el caso que no se puede detectar
    // desde dentro: un stream que sigue "vivo" y ya no entrega nada.
    _escuchar();
  }

  void _avanzar() {
    if (!mounted) return;
    final d = _datos;
    if (d == null) return;
    final paginas = (d.tabla.length / LeaderboardTvScreen.filasPorPagina).ceil().clamp(1, 999);
    final logos = d.inventario.pie.length;
    setState(() {
      _pagina = paginas <= 1 ? 0 : (_pagina + 1) % paginas;
      if (logos > 0) _logo = (_logo + 1) % logos;
    });
  }

  @override
  Widget build(BuildContext context) {
    // El volcado técnico de la app no puede acabar proyectado en una pared. Se
    // sustituye mientras esta pantalla vive; el latido lo limpia.
    _builderPrevio ??= ErrorWidget.builder;
    ErrorWidget.builder = (_) => _PantallaDeEspera(
        titulo: _datos?.nombre ?? 'Torneo', mensaje: 'Actualizando…');

    return Scaffold(
      backgroundColor: const Color(0xFF07130C),
      body: KeyedSubtree(
        // La clave del remontaje. Ver la cabecera, punto 2.
        key: ValueKey(_generacion),
        child: _contenido(context),
      ),
    );
  }

  Widget _contenido(BuildContext context) {
    final d = _datos;
    if (_cargando) {
      return const _PantallaDeEspera(
          titulo: 'Leaderboard', mensaje: 'Conectando…');
    }
    if (d == null || !d.activo) {
      return _PantallaDeEspera(
          titulo: d?.nombre ?? 'Leaderboard',
          mensaje: d == null
              ? 'Este enlace todavía no tiene tabla publicada.'
              : 'El organizador apagó esta pantalla.');
    }

    final alto = MediaQuery.of(context).size.height;
    final ancho = MediaQuery.of(context).size.width;
    // De esta unidad sale el tamaño de TODO. Ver la cabecera, punto 1.
    final u = LeaderboardTvScreen.unidadDe(alto);
    final conLateral = ancho >= 1280 && d.inventario.lateral != null;

    return SafeArea(
      child: Row(children: [
        Expanded(
          child: Column(children: [
            _Cabecera(datos: d, u: u),
            Expanded(child: _Tabla(datos: d, u: u, pagina: _pagina,
                porPagina: LeaderboardTvScreen.filasPorPagina)),
            _Pie(datos: d, u: u, indice: _logo),
          ]),
        ),
        // §5.3 y §7 del manual: la columna desaparece antes de comprimir nada.
        if (conLateral)
          Padding(
            padding: EdgeInsets.all(u * 0.25),
            child: _Lateral(pieza: d.inventario.lateral!, alto: alto),
          ),
      ]),
    );
  }
}

/// Lo que se ve cuando no hay nada que enseñar todavía.
///
/// Nunca en blanco y nunca un error técnico: una pantalla proyectada en blanco
/// no se distingue de una tele apagada, y un volcado de Flutter delante de los
/// socios del club es peor que la tele apagada.
class _PantallaDeEspera extends StatelessWidget {
  final String titulo;
  final String mensaje;
  const _PantallaDeEspera({required this.titulo, required this.mensaje});

  @override
  Widget build(BuildContext context) {
    final u = LeaderboardTvScreen.unidadDe(MediaQuery.of(context).size.height);
    return Container(
      color: const Color(0xFF07130C),
      alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(titulo,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: const Color(0xFFE8F5E9),
                fontSize: u * 0.9,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5)),
        SizedBox(height: u * 0.3),
        Text(mensaje,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: const Color(0xFF7E9E88), fontSize: u * 0.42)),
      ]),
    );
  }
}

class _Cabecera extends StatelessWidget {
  final LeaderboardPublico datos;
  final double u;
  const _Cabecera({required this.datos, required this.u});

  @override
  Widget build(BuildContext context) {
    final banner = datos.inventario.cabecera;
    return Padding(
      padding: EdgeInsets.fromLTRB(u * 0.5, u * 0.3, u * 0.5, u * 0.15),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // ICONO, no emoji. Esta es la superficie que se proyecta delante de
          // los patrocinadores, y un emoji ahí es el peor sitio para los tres
          // problemas que tiene: no hereda el color de la pantalla oscura,
          // cambia de dibujo según el navegador del club, y a color sobre una
          // paleta de tres niveles es el pico visual de la pared.
          //
          // El emoji del torneo no lo elige nadie —es siempre el mismo por
          // defecto—, así que sustituirlo no pierde nada de lo que el
          // organizador puso.
          Icon(GolfIcons.trofeo,
              size: u * 0.72, color: const Color(0xFF6FE39A)),
          SizedBox(width: u * 0.25),
          Expanded(
            child: Text(datos.nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: u * 0.78,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1)),
          ),
          Text(
              '${datos.rondas} ronda${datos.rondas == 1 ? '' : 's'}'
              '${datos.cerrado ? ' · cerrado' : ''}',
              style: TextStyle(
                  color: const Color(0xFF7E9E88),
                  fontSize: u * 0.34,
                  fontWeight: FontWeight.w600)),
        ]),
        // §14.3: el titular del torneo, persistente.
        if (banner != null && banner.pintable) ...[
          SizedBox(height: u * 0.22),
          _Banner(pieza: banner, u: u),
        ],
      ]),
    );
  }
}

class _Banner extends StatelessWidget {
  final PiezaDePatrocinio pieza;
  final double u;
  const _Banner({required this.pieza, required this.u});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: u * 0.4, vertical: u * 0.2),
        decoration: BoxDecoration(
          // §6.3: no imitar el verde funcional del score. Este bloque es
          // deliberadamente neutro para que se distinga de la tabla.
          color: const Color(0xFF15211A),
          borderRadius: BorderRadius.circular(u * 0.16),
          border: Border.all(color: const Color(0xFF2A3B31)),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // §6: la naturaleza comercial tiene que ser clara.
              Text(pieza.etiqueta.toUpperCase(),
                  style: TextStyle(
                      color: const Color(0xFF7E9E88),
                      fontSize: u * 0.2,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4)),
              if (pieza.titular.isNotEmpty) ...[
                SizedBox(height: u * 0.06),
                Text(pieza.titular,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: u * 0.4,
                        fontWeight: FontWeight.w700)),
              ],
            ]),
          ),
          if (pieza.cta != null) ...[
            SizedBox(width: u * 0.3),
            Text(pieza.cta!,
                style: TextStyle(
                    color: const Color(0xFFB9D4C2),
                    fontSize: u * 0.28,
                    fontWeight: FontWeight.w700)),
          ],
        ]),
      );
}

class _Tabla extends StatelessWidget {
  final LeaderboardPublico datos;
  final double u;
  final int pagina;
  final int porPagina;
  const _Tabla({
    required this.datos,
    required this.u,
    required this.pagina,
    required this.porPagina,
  });

  @override
  Widget build(BuildContext context) {
    final desde = pagina * porPagina;
    final filas = datos.tabla.skip(desde).take(porPagina).toList();
    final paginas = (datos.tabla.length / porPagina).ceil();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: u * 0.5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(datos.comoSePuntua,
              style: TextStyle(
                  color: const Color(0xFF7E9E88),
                  fontSize: u * 0.26,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          if (paginas > 1)
            Text('${pagina + 1} / $paginas',
                style: TextStyle(
                    color: const Color(0xFF7E9E88),
                    fontSize: u * 0.26,
                    fontWeight: FontWeight.w700)),
        ]),
        SizedBox(height: u * 0.12),
        Expanded(
          // ── QUE EL CAMBIO DE POSICIÓN SE VEA ────────────────────────────
          //
          // Antes las filas simplemente aparecían en su sitio nuevo: si alguien
          // adelantaba a otro entre dos actualizaciones, en la pared no pasaba
          // nada. Y esa pantalla se mira precisamente para ver quién sube.
          //
          // Con la clave puesta en el JUGADOR y no en la posición, Flutter
          // reconoce que es la misma fila y la desplaza en vez de repintarla en
          // otro sitio. Es lo único que hace falta para que el adelantamiento
          // se lea.
          //
          // Aquí la duración es larga a propósito —es de las pocas cosas de la
          // app que se miran desde diez metros— y no pasa por GolfMotion.de:
          // una tele proyectada no tiene "reducir movimiento", y quedarse sin
          // el movimiento es justo perder la información.
          child: Column(
            children: [
              for (final f in filas)
                Expanded(
                    child: AnimatedSwitcher(
                  duration: GolfMotion.escena,
                  switchInCurve: GolfMotion.entrada,
                  child: _Fila(
                      key: ValueKey(f.nombre), fila: f, u: u, datos: datos),
                )),
              // Sin relleno las filas de la última página se estirarían al doble
              // y la tabla cambiaría de forma al rotar.
              for (var i = filas.length; i < porPagina; i++)
                const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
        // El hueco de la medida se explica en vez de dejarse vacío: un hueco sin
        // motivo se lee como un fallo de carga.
        if (datos.ocultaLaMedida)
          Padding(
            padding: EdgeInsets.only(bottom: u * 0.1),
            child: Text('La clasificación no muestra importes en pantalla.',
                style: TextStyle(
                    color: const Color(0xFF5C7A66), fontSize: u * 0.22)),
          ),
      ]),
    );
  }
}

class _Fila extends StatelessWidget {
  final FilaProyectada fila;
  final double u;
  final LeaderboardPublico datos;
  const _Fila(
      {super.key, required this.fila, required this.u, required this.datos});

  @override
  Widget build(BuildContext context) {
    final podio = fila.puesto <= 3;
    return Container(
      margin: EdgeInsets.only(bottom: u * 0.06),
      padding: EdgeInsets.symmetric(horizontal: u * 0.3),
      decoration: BoxDecoration(
        color: podio ? const Color(0xFF12241A) : const Color(0xFF0C1A12),
        borderRadius: BorderRadius.circular(u * 0.12),
      ),
      child: Row(children: [
        SizedBox(
          width: u * 1.1,
          child: Text('${fila.puesto}',
              style: TextStyle(
                  color: podio
                      ? const Color(0xFF6FE39A)
                      : const Color(0xFF7E9E88),
                  fontSize: u * 0.52,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ),
        Expanded(
          child: Text(fila.nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: u * 0.46,
                  fontWeight: FontWeight.w700)),
        ),
        Text('${fila.jugadas}',
            style: TextStyle(
                color: const Color(0xFF5C7A66),
                fontSize: u * 0.3,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()])),
        SizedBox(width: u * 0.4),
        SizedBox(
          width: u * 1.6,
          child: Text(
              fila.medida == null ? '—' : _cifra(fila.medida!),
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: fila.medida == null
                      ? const Color(0xFF3E5647)
                      : Colors.white,
                  fontSize: u * 0.52,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ),
      ]),
    );
  }

  /// Sin decimales cuando no los necesita: en una pantalla que se lee de lejos,
  /// un ",0" es ruido que ocupa el sitio de un dígito que sí importa.
  static String _cifra(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
}

class _Pie extends StatelessWidget {
  final LeaderboardPublico datos;
  final double u;
  final int indice;
  const _Pie({required this.datos, required this.u, required this.indice});

  @override
  Widget build(BuildContext context) {
    final logos =
        datos.inventario.pie.where((p) => p.pintable).toList();
    if (logos.isEmpty) {
      // §13.2 aplicado al pie: sin patrocinador no se enseña un hueco.
      return SizedBox(height: u * 0.2);
    }
    // §14.2: aquí la rotación SÍ se permite. Fundido corto, §6.4.
    final pieza = logos[indice % logos.length];
    return Container(
      height: u * 1.1,
      width: double.infinity,
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: u * 0.5),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        child: Row(
          key: ValueKey(pieza.logoUrl + pieza.etiqueta),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(pieza.etiqueta.toUpperCase(),
                style: TextStyle(
                    color: const Color(0xFF5C7A66),
                    fontSize: u * 0.2,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4)),
            SizedBox(width: u * 0.3),
            Flexible(
              child: Text(
                  pieza.titular.isNotEmpty ? pieza.titular : pieza.logoUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: const Color(0xFFB9D4C2),
                      fontSize: u * 0.34,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Lateral extends StatelessWidget {
  final PiezaDePatrocinio pieza;
  final double alto;
  const _Lateral({required this.pieza, required this.alto});

  @override
  Widget build(BuildContext context) {
    final u = LeaderboardTvScreen.unidadDe(alto);
    return Container(
      width: 300,
      height: 600,
      padding: EdgeInsets.all(u * 0.3),
      decoration: BoxDecoration(
        color: const Color(0xFF15211A),
        borderRadius: BorderRadius.circular(u * 0.16),
        border: Border.all(color: const Color(0xFF2A3B31)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(pieza.etiqueta.toUpperCase(),
            style: const TextStyle(
                color: Color(0xFF7E9E88),
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4)),
        const SizedBox(height: 12),
        if (pieza.titular.isNotEmpty)
          Text(pieza.titular,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  height: 1.2,
                  fontWeight: FontWeight.w800)),
        const Spacer(),
        if (pieza.cta != null)
          Text(pieza.cta!,
              style: const TextStyle(
                  color: Color(0xFFB9D4C2),
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
