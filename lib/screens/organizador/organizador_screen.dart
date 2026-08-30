// ─────────────────────────────────────────────────────────────────────────────
// PORTAL DE ORGANIZADOR — /organizador/{torneoId}
//
// No es otra aplicación: es otra VISTA de la misma app, con el mismo auth, el
// mismo directorio, el mismo tema y los mismos providers. Lo único que cambia
// es que está diseñada para un navegador ancho.
//
// ── Por qué existe ──────────────────────────────────────────────────────────
//
// Lo que un teléfono hace mal: 150 inscritos editables, arrastrar grupos a
// salidas de shotgun, cargar logotipos de patrocinadores. Un organizador
// subiendo creatividades desde un móvil no es un producto que se pueda vender.
//
// Lo que NO entra aquí, y no por falta de tiempo: capturar los scores de una
// ronda. Eso es del jugador y del móvil, con guante y entre golpe y golpe.
//
// ── QUIÉN PUEDE ABRIRLO ─────────────────────────────────────────────────────
//
// Solo el dueño, y NO hace falta regla nueva. Un torneo vive en
// `users/{uid}/torneos/{id}`, y esa regla ya dice
// `request.auth.uid == userId`. TorneoProvider transmite únicamente la
// subcolección del que ha entrado, así que un torneo ajeno no es que se
// esconda: no llega. Escribir una regla nueva habría sido una segunda
// definición de lo mismo, que es de donde salen las contradicciones.
//
// Lo que sí hace esta pantalla es DECIRLO: con la sesión abierta y el torneo
// ausente, un id que no es tuyo y un id que no existe se ven igual desde aquí, y
// eso es correcto —no se confirma la existencia de nada ajeno—.
//
// ── LA PUERTA DE SESIÓN ─────────────────────────────────────────────────────
//
// Esta ruta no pasa por AppShell, igual que /tv/. Y ahí está la trampa: los
// streams de Firestore no arrancan solos, los arrancaba AppShell. Sin
// arrancarlos aquí, el portal habría abierto siempre con "torneo no encontrado"
// para su propio dueño. La lista vive en core/escuchas.dart, una sola vez.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ancho.dart';
import '../../core/app_theme.dart';
import '../../core/escuchas.dart';
import '../../models/inscritos.dart';
import '../../models/torneo.dart';
import '../../providers/auth_provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/round_provider.dart';
import '../../providers/torneo_provider.dart';
import '../../widgets/importar_jugadores_sheet.dart';
import '../auth/auth_screen.dart';
import 'inscritos_tabla.dart';

class OrganizadorScreen extends StatefulWidget {
  final String torneoId;
  const OrganizadorScreen({super.key, required this.torneoId});

  @override
  State<OrganizadorScreen> createState() => _OrganizadorScreenState();
}

class _OrganizadorScreenState extends State<OrganizadorScreen> {
  /// Prendieron de VERDAD. No "se intentó".
  ///
  /// ── El fallo que costó esto ───────────────────────────────────────────────
  ///
  /// Antes esto se llamaba "ya lo intenté" y se ponía en true ANTES de arrancar
  /// nada. `TorneoProvider.startListening()` se rinde en silencio si todavía no
  /// hay uid —no lanza, no avisa, no se suscribe—, así que un intento medio
  /// segundo pronto se convertía en no arrancar en toda la sesión. Y lo que se
  /// veía era el portal diciéndole al dueño de un torneo que no era suyo.
  bool _prendidas = false;

  /// Aquí NO hay reloj de reintento, y es deliberado.
  ///
  /// Lo tuvo un rato y era la duplicación de siempre: si cada pantalla se pone
  /// su propio reintento, la quinta que se escriba no lo tendrá. Quien espera al
  /// uid es TorneoProvider.startListening(), que es quien sabe si le falta, y
  /// cuando lo consigue avisa — y ese aviso ya reconstruye esta pantalla.
  void _arrancarSiHaceFalta() {
    if (_prendidas) return;
    if (!context.read<AuthProvider>().isAuth) return;
    _prendidas = iniciarEscuchas(context);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _arrancarSiHaceFalta());
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final t = context.watch<RoundProvider>().theme;
    GolfThemeExt.setCurrent(t);

    if (auth.status == AuthStatus.unknown) {
      return _Espera(t: t, mensaje: 'Abriendo el portal…');
    }
    if (auth.status == AuthStatus.unauthenticated) {
      // El portal necesita sesión, al revés que la tele: aquí se EDITA.
      return const AuthScreen();
    }
    if (!_prendidas) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(_arrancarSiHaceFalta);
      });
    }

    final prov = context.watch<TorneoProvider>();

    // TODAVÍA NO LO SÉ ≠ NO ES TUYO.
    //
    // Es la distinción que faltaba y la que causó el fallo. `loading` no vale
    // para separarlas: nace en false, así que antes de que nadie se suscriba hay
    // un hueco en el que la lista está vacía y no está cargando — y eso se leía
    // como "no está en tu cuenta". Un mensaje de permiso denegado cuando lo que
    // pasaba era que no había llegado el primer dato.
    if (!prov.cargado) {
      return _Espera(
          t: t,
          mensaje: 'Cargando tus torneos…',
          // Se DICE qué está esperando. Si esto sale en pantalla, el problema es
          // el arranque, y quien lo vea puede contarlo en vez de describir un
          // síntoma — que es lo que costó encontrar este fallo.
          detalle: prov.reintentando ? 'Esperando a la sesión…' : null);
    }

    final torneo = prov.torneos
        .where((x) => x.id == widget.torneoId)
        .cast<Torneo?>()
        .firstWhere((_) => true, orElse: () => null);

    // Solo aquí: la lista está CARGADA y el torneo no está en ella.
    if (torneo == null) return _NoEsTuyo(t: t, cuantos: prov.torneos.length);

    return LayoutBuilder(builder: (context, c) {
      // El layout sale del ancho DISPONIBLE, no de la plataforma. Ver
      // core/ancho.dart: es la misma decisión que la unidad de la tele.
      final ancho = anchoDe(c.maxWidth);
      return _Portal(torneo: torneo, ancho: ancho, t: t);
    });
  }
}

class _Espera extends StatelessWidget {
  final GolfTheme t;
  final String mensaje;
  final String? detalle;
  const _Espera({required this.t, required this.mensaje, this.detalle});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: t.bg,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                    color: t.primary, strokeWidth: 2.5)),
            const SizedBox(height: 16),
            Text(mensaje, style: TextStyle(color: t.sub, fontSize: 13.5)),
            if (detalle != null) ...[
              const SizedBox(height: 6),
              Text(detalle!,
                  style: TextStyle(color: t.sub, fontSize: 11.5)),
            ],
          ]),
        ),
      );
}

class _NoEsTuyo extends StatelessWidget {
  final GolfTheme t;

  /// Cuántos torneos SÍ llegaron. Si son cero, lo que pasa probablemente no es
  /// que el torneo sea ajeno: es que no llegó nada, y decir lo contrario manda a
  /// buscar el problema al sitio equivocado.
  final int cuantos;
  const _NoEsTuyo({required this.t, required this.cuantos});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: t.bg,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock_outline, size: 40, color: t.sub),
              const SizedBox(height: 14),
              Text('Este torneo no está en tu cuenta',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: t.text, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                  cuantos == 0
                      ? 'No llegó ningún torneo de esta cuenta, así que puede '
                          'que el problema no sea el enlace. Prueba a recargar.'
                      : 'El portal solo abre los torneos que organizas tú. Si lo '
                          'creaste con otra cuenta, entra con esa.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.sub, fontSize: 13, height: 1.45)),
              const SizedBox(height: 10),
              Text('$cuantos torneo${cuantos == 1 ? '' : 's'} en esta cuenta',
                  style: TextStyle(color: t.sub, fontSize: 11)),
            ]),
          ),
        ),
      );
}

/// El armazón: cabecera, secciones y contenido.
class _Portal extends StatefulWidget {
  final Torneo torneo;
  final Ancho ancho;
  final GolfTheme t;
  const _Portal({required this.torneo, required this.ancho, required this.t});

  @override
  State<_Portal> createState() => _PortalState();
}

/// Las secciones del portal. Solo la primera está construida; las otras se
/// nombran para que se vea que el armazón las espera —y para no inventar un
/// menú distinto cuando lleguen—.
enum SeccionDelPortal { inscritos, patrocinio, scores, salidas }

extension SeccionTexto on SeccionDelPortal {
  String get label => switch (this) {
        SeccionDelPortal.inscritos => 'Inscritos',
        SeccionDelPortal.patrocinio => 'Patrocinio',
        SeccionDelPortal.scores => 'Scores en vivo',
        SeccionDelPortal.salidas => 'Grupos y salidas',
      };

  IconData get icono => switch (this) {
        SeccionDelPortal.inscritos => Icons.groups_outlined,
        SeccionDelPortal.patrocinio => Icons.workspace_premium_outlined,
        SeccionDelPortal.scores => Icons.table_chart_outlined,
        SeccionDelPortal.salidas => Icons.flag_outlined,
      };

  /// Lo que falta para que exista. Se dice en vez de enseñar un botón muerto.
  String? get pendiente => switch (this) {
        SeccionDelPortal.inscritos => null,
        SeccionDelPortal.patrocinio =>
          'Hoy se configura desde la app. Aquí irá con carga de creatividades.',
        SeccionDelPortal.scores =>
          'El torneo entero en una tabla, y corregir con constancia.',
        SeccionDelPortal.salidas =>
          'Arrastrar grupos a salidas de shotgun. Necesita modelo nuevo.',
      };
}

class _PortalState extends State<_Portal> {
  SeccionDelPortal _seccion = SeccionDelPortal.inscritos;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final ancho = widget.ancho;
    final torneo = widget.torneo;

    final contenido = switch (_seccion) {
      SeccionDelPortal.inscritos =>
        InscritosTabla(torneo: torneo, ancho: ancho, t: t),
      final s => _Pendiente(t: t, seccion: s),
    };

    return Scaffold(
      backgroundColor: t.bg,
      // En estrecho la navegación va abajo, donde llega el pulgar; en ancho, a
      // la izquierda, que es donde la busca quien viene de un navegador.
      bottomNavigationBar: ancho.esTabla
          ? null
          : NavigationBar(
              backgroundColor: t.surface,
              selectedIndex: _seccion.index,
              onDestinationSelected: (i) =>
                  setState(() => _seccion = SeccionDelPortal.values[i]),
              destinations: [
                for (final s in SeccionDelPortal.values)
                  NavigationDestination(icon: Icon(s.icono), label: s.label),
              ],
            ),
      body: SafeArea(
        child: Row(children: [
          if (ancho.esTabla)
            NavigationRail(
              backgroundColor: t.surface,
              extended: ancho.columnasCompletas,
              selectedIndex: _seccion.index,
              onDestinationSelected: (i) =>
                  setState(() => _seccion = SeccionDelPortal.values[i]),
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(torneo.emoji, style: const TextStyle(fontSize: 26)),
              ),
              destinations: [
                for (final s in SeccionDelPortal.values)
                  NavigationRailDestination(
                      icon: Icon(s.icono), label: Text(s.label)),
              ],
            ),
          Expanded(
            child: Column(children: [
              _Cabecera(torneo: torneo, ancho: ancho, t: t),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(maxWidth: ancho.anchoDeContenido),
                    child: contenido,
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Cabecera extends StatelessWidget {
  final Torneo torneo;
  final Ancho ancho;
  final GolfTheme t;
  const _Cabecera(
      {required this.torneo, required this.ancho, required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          ancho.esTabla ? 24 : 16, 16, ancho.esTabla ? 24 : 16, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.divider)),
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: ancho.anchoDeContenido),
          child: Row(children: [
            if (!ancho.esTabla) ...[
              Text(torneo.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 9),
            ],
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(torneo.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: t.text,
                            fontSize: ancho.esTabla ? 22 : 18,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                        '${torneo.participantes.length} inscrito'
                        '${torneo.participantes.length == 1 ? '' : 's'}'
                        ' · ${torneo.metodo.label}'
                        '${torneo.cerrado ? ' · cerrado' : ''}',
                        style: TextStyle(color: t.sub, fontSize: 12.5)),
                  ]),
            ),
            // Volver a la app: el portal es otra vista de lo mismo, no una
            // salida sin retorno.
            IconButton(
              tooltip: 'Ir a la app',
              // A '/app', no a '/': home vuelve a leer Uri.base, que sigue
              // diciendo /organizador/…, y devolvería aquí mismo.
              onPressed: () => Navigator.of(context)
                  .pushNamedAndRemoveUntil('/app', (_) => false),
              icon: Icon(Icons.apps, size: 20, color: t.sub),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Pendiente extends StatelessWidget {
  final GolfTheme t;
  final SeccionDelPortal seccion;
  const _Pendiente({required this.t, required this.seccion});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(seccion.icono, size: 34, color: t.sub),
            const SizedBox(height: 14),
            Text(seccion.label,
                style: TextStyle(
                    color: t.text, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 7),
            Text(seccion.pendiente ?? '',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.sub, fontSize: 13, height: 1.45)),
            const SizedBox(height: 6),
            Text('Todavía no está en el portal.',
                style: TextStyle(color: t.sub, fontSize: 11.5)),
          ]),
        ),
      );
}

/// Abre el selector del directorio y la importación por pegado, y devuelve el
/// torneo con los nuevos inscritos. Null si no se añadió nadie.
///
/// Reutiliza la hoja que ya existe: aquí es donde la importación por pegado gana
/// sentido de verdad, con 150 nombres saliendo de un Excel.
Future<Torneo?> anadirInscritos(BuildContext context, Torneo torneo) async {
  final ids = await showImportarJugadoresSheet(context, t: context.gt);
  if (ids == null || ids.isEmpty) return null;
  final nuevo = conInscritos(torneo, ids);
  return identical(nuevo, torneo) ? null : nuevo;
}

/// El directorio ordenado, para el selector.
List<String> idsDelDirectorio(BuildContext context) =>
    context.read<PlayerProvider>().directory.map((p) => p.player.id).toList();
