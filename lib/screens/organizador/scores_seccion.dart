// ─────────────────────────────────────────────────────────────────────────────
// SCORES EN VIVO — el torneo entero, y lo que de verdad se puede ver
//
// ── QUÉ SE PUEDE LEER, Y POR QUÉ NO SE AÑADE NINGUNA REGLA ──────────────────
//
// Es la primera sección del portal que quiere datos de OTRAS CUENTAS, así que
// lo primero fue mirar qué conceden las reglas de hoy:
//
//   · liveRounds  → lee quien está en `participantUids` o es `ownerUid`
//   · torneoResultados → lee el `torneoOwnerUid`, o sea el organizador
//
// De ahí sale la frontera, y no de una decisión de diseño:
//
//   LO QUE SÍ, en vivo y hoyo a hoyo: las rondas que el organizador MONTÓ. En
//   un shotgun son todas —él arma los grupos—, y son las que puede corregir.
//
//   LO QUE NO: las rondas en vivo de otras cuentas. De esas se ve lo ÚLTIMO
//   QUE PUBLICARON al cerrar, que es un hecho con fecha, no un directo.
//
// ── Y por qué no se amplía la regla ─────────────────────────────────────────
//
// Se miraron las dos formas de conseguirlo y las dos dan de más:
//
//   1 · Meter al organizador en `participantUids` de las rondas marcadas para
//       su torneo. La regla de liveRounds es `allow read, update` JUNTAS: le
//       daría permiso de ESCRIBIR en la ronda de cualquiera que marque una
//       ronda para su torneo. Y la escribiría el dueño de la ronda, que no
//       tiene por qué conocer el uid del organizador.
//
//   2 · Una regla nueva del tipo "lee si `torneoIds` contiene un torneo tuyo".
//       Los torneos viven en `users/{uid}/torneos/{id}`, así que haría falta un
//       `get()` cruzado POR DOCUMENTO — y un `get()` dentro de una regla de
//       `list` no se puede acotar: la consulta entera pasa o falla, y cada
//       documento candidato cuesta una lectura.
//
// Con tres colecciones en el historial donde un `read` concedía un `list` que
// nadie usaba —sharedTorneos, players, userLookup—, ampliar aquí es exactamente
// el movimiento que este proyecto ya pagó tres veces.
//
// ── Y la pantalla lo DICE ───────────────────────────────────────────────────
//
// Es lo mismo que se decidió con el "Thru": mejor decir qué se está viendo que
// prometer tiempo real y enseñar algo de hace dos horas. Las dos listas van
// separadas y cada una con su fecha.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/ancho.dart';
import '../../core/app_theme.dart';
import '../../core/golf_icons.dart';
import '../../models/correccion_de_score.dart';
import '../../models/models.dart';
import '../../models/torneo.dart';
import '../../services/auth_service.dart';
import '../../services/live_round_service.dart';

class ScoresSeccion extends StatefulWidget {
  final Torneo torneo;
  final Ancho ancho;
  final GolfTheme t;

  /// Lo que publicaron OTRAS cuentas al cerrar. Llega cargado del portal.
  final List<ResultadoPublicado> publicados;

  const ScoresSeccion({
    super.key,
    required this.torneo,
    required this.ancho,
    required this.t,
    required this.publicados,
  });

  @override
  State<ScoresSeccion> createState() => _ScoresSeccionState();
}

class _ScoresSeccionState extends State<ScoresSeccion> {
  List<GrupoDelTorneo>? _grupos;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final g = await LiveRoundService.gruposDelTorneo(widget.torneo.id);
    if (mounted) setState(() => _grupos = g);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final ancha = widget.ancho.esTabla;
    final grupos = _grupos;
    final ajenos = widget.publicados;

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: EdgeInsets.fromLTRB(ancha ? 24 : 14, 16, ancha ? 24 : 14, 32),
        children: [
          // ── LA VERDAD, ARRIBA ──────────────────────────────────────────
          //
          // Antes de cualquier número. Quien abre esto el día del torneo tiene
          // que saber en la primera frase qué está mirando.
          _Aviso(
            t: t,
            texto: grupos == null
                ? 'Cargando los grupos del torneo…'
                : 'Los grupos que montaste se ven EN VIVO y puedes corregirlos. '
                    'Las rondas que llevan otras cuentas se ven cuando las '
                    'cierran: de esas se enseña lo último que publicaron, con '
                    'su fecha.',
          ),
          const SizedBox(height: 18),

          _Etiqueta('TUS GRUPOS · EN VIVO', t: t),
          const SizedBox(height: 8),
          if (grupos == null)
            _Vacio(t: t, texto: 'Cargando…')
          else if (grupos.isEmpty)
            _Vacio(
                t: t,
                texto: 'Todavía no has montado ningún grupo de este torneo. '
                    'Los grupos que crees desde el torneo aparecen aquí, en '
                    'vivo y corregibles.')
          else
            for (final g in grupos)
              _FilaDeGrupo(
                grupo: g,
                t: t,
                onTap: () => _abrirTarjeta(g),
              ),

          const SizedBox(height: 22),
          _Etiqueta('DE OTRAS CUENTAS · AL CERRAR', t: t),
          const SizedBox(height: 8),
          if (ajenos.isEmpty)
            _Vacio(
                t: t,
                texto: 'Nadie de fuera ha cerrado todavía una ronda de este '
                    'torneo.')
          else
            for (final r in ajenos) _FilaAjena(publicado: r, t: t),
        ],
      ),
    );
  }

  Future<void> _abrirTarjeta(GrupoDelTorneo g) async {
    final messenger = ScaffoldMessenger.of(context);
    final ronda = await LiveRoundService.cargarRondaEnVivo(g.roundId);
    if (!mounted) return;
    if (ronda == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text('No se pudo abrir esa ronda. Recarga y vuelve a '
              'intentarlo.')));
      return;
    }
    final cambiada = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: widget.t.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => HojaDeTarjeta(ronda: ronda, t: widget.t),
    );
    if (cambiada == true) await _cargar();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LA TARJETA, CON CORRECCIÓN
// ─────────────────────────────────────────────────────────────────────────────
/// La tarjeta de un grupo, con corrección.
///
/// Pública para poder montarla en un test con una ronda cualquiera: el camino
/// real pasa por Firestore, y el fallo de las cuatro filas vivía justo en el
/// trozo que ninguna prueba alcanzaba.
class HojaDeTarjeta extends StatefulWidget {
  final Round ronda;
  final GolfTheme t;
  const HojaDeTarjeta({super.key, required this.ronda, required this.t});

  @override
  State<HojaDeTarjeta> createState() => _HojaDeTarjetaState();
}

class _HojaDeTarjetaState extends State<HojaDeTarjeta> {
  late Round _r = widget.ronda;
  bool _guardando = false;
  bool _cambiada = false;

  // Un FocusNode por (jugador, hoyo): el llenado de corrido avanza el foco al
  // hoyo siguiente de la MISMA fila. Al llegar al último, para.
  final Map<String, List<FocusNode>> _focos = {};
  // El guardado a Firestore va con debounce: tecleando 18 hoyos de corrido no se
  // hacen 18 escrituras; se acumula en `_r` (local, inmediato) y se sube el
  // round entero poco después de la última tecla, o al cerrar.
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    for (final p in _r.scoringPlayers) {
      _focos[p.id] = List.generate(_r.totalHoles, (_) => FocusNode());
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    for (final l in _focos.values) {
      for (final f in l) {
        f.dispose();
      }
    }
    super.dispose();
  }

  /// Anota (o corrige) el hoyo `holeIndex` (0-based) de `jugador` y avanza el
  /// foco. Rellenar un hueco pasa por el mismo `conCorreccion` que corregir, así
  /// que el registro lo distingue solo: "se anotó 6" vs "5 → 4".
  void _anotar(Player jugador, int holeIndex, int valor, {bool advance = true}) {
    final hoyo = holeIndex + 1;
    final r2 = conCorreccion(
      _r,
      jugadorId: jugador.id,
      hoyo: hoyo,
      nuevo: valor,
      porUid: AuthService.uid ?? '',
      porNombre: AuthService.currentUser?.displayName ?? 'El organizador',
      cuando: DateTime.now(),
    );
    if (!identical(r2, _r)) {
      setState(() {
        _r = r2;
        _cambiada = true;
      });
      _programarGuardado();
    }
    if (!advance) return; // blur: se guardó, pero no se mueve el foco
    // El salto es al HOYO, dentro de la fila. Al acabar la fila PARA: no salta
    // al jugador siguiente (decisión de Carlos) — un número de más se escribiría
    // en la fila de otro sin que nadie lo viera.
    final focos = _focos[jugador.id];
    if (focos != null && holeIndex + 1 < focos.length) {
      focos[holeIndex + 1].requestFocus();
    } else {
      FocusScope.of(context).unfocus(); // fila completa
    }
  }

  void _programarGuardado() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _guardar);
  }

  Future<void> _guardar() async {
    _saveTimer?.cancel();
    if (_guardando) {
      _programarGuardado(); // ya hay uno en curso; reintenta al terminar
      return;
    }
    final snapshot = _r;
    setState(() => _guardando = true);
    final ok = await LiveRoundService.guardarCorregida(snapshot);
    if (!mounted) return;
    setState(() => _guardando = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo guardar. Revisa la conexión; los '
              'números siguen en pantalla.')));
    }
  }

  Future<void> _cerrar() async {
    // Sube cualquier cambio pendiente antes de salir: no se pierde el último.
    if (_saveTimer?.isActive ?? false) {
      await _guardar();
    }
    if (mounted) Navigator.pop(context, _cambiada);
  }

  Future<void> _corregir(Player jugador, int hoyo) async {
    final actual = _r.scores[jugador.id]?[hoyo]?.grossScore;
    final nuevo = await _pedirScore(context, widget.t, jugador, hoyo, actual);
    // null = canceló. El "borrar" viaja como un (true, null).
    if (nuevo == null || !mounted) return;

    final r2 = conCorreccion(
      _r,
      jugadorId: jugador.id,
      hoyo: hoyo,
      nuevo: nuevo.$1,
      porUid: AuthService.uid ?? '',
      // Quien corrige, con el nombre que tiene HOY: la corrección es un hecho
      // pasado y guarda el nombre de cuando pasó. Ver correccion_de_score.dart.
      porNombre: AuthService.currentUser?.displayName ?? 'El organizador',
      cuando: DateTime.now(),
    );
    if (identical(r2, _r)) return; // No cambió nada: no se anota ruido.

    setState(() => _guardando = true);
    final ok = await LiveRoundService.guardarCorregida(r2);
    if (!mounted) return;
    setState(() {
      _guardando = false;
      if (ok) {
        _r = r2;
        _cambiada = true;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? 'Corregido. Queda anotado quién lo cambió.'
            : 'No se pudo guardar la corrección. El score sigue como estaba.')));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final hoyos = List.generate(_r.totalHoles, (i) => i + 1);
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 14),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: t.divider, borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: Text(_r.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GolfType.title(t.text)),
            ),
            if (_guardando)
              SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: t.primary)),
          ]),
          const SizedBox(height: 2),
          Text(
              'Teclea los golpes de corrido: el foco pasa al hoyo siguiente '
              'solo y para al 18. Mantén pulsada una casilla para corregir o '
              'borrar. Queda anotado quién anotó qué.',
              style: TextStyle(color: t.sub, fontSize: 12)),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(children: [
              // La rejilla: una fila por jugador, una columna por hoyo. Se
              // desplaza en horizontal dentro de su caja, no la pantalla.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        SizedBox(width: 108, child: Text('', style: GolfType.label(t.sub))),
                        for (final h in hoyos)
                          SizedBox(
                            width: 34,
                            child: Text('$h',
                                textAlign: TextAlign.center,
                                style: GolfType.label(t.sub)),
                          ),
                      ]),
                      const SizedBox(height: 4),
                      // ── QUIÉN LLEVA TARJETA, no quién juega ────────────
                      //
                      // Aquí ponía `realPlayers` y por eso la tarjeta de un
                      // equipo salía con CUATRO filas, una por miembro — justo
                      // lo que el modo equipos viene a evitar—.
                      //
                      // El mecanismo estaba: `scoringPlayers` respeta el
                      // `equipoId` que la ronda declara, y la captura del
                      // jugador ya lo usaba en sus seis sitios. Esta hoja no lo
                      // consultaba. La familia de siempre: el dato existe y la
                      // superficie no lo lee.
                      //
                      // Los cuatro siguen viéndose: están en la fila del grupo,
                      // en la lista de Scores en vivo. Lo que no tienen es
                      // score propio, porque juegan una bola.
                      for (final p in _r.scoringPlayers)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(children: [
                            SizedBox(
                              width: 108,
                              child: Text(p.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GolfType.value(t.text)),
                            ),
                            for (final h in hoyos)
                              _CasillaEditable(
                                key: ValueKey('${p.id}-$h'),
                                score: _r.scores[p.id]?[h]?.grossScore,
                                par: _r.course.holes
                                    .where((x) => x.hole == h)
                                    .map((x) => x.par)
                                    .firstOrNull,
                                t: t,
                                focusNode: _focos[p.id]![h - 1],
                                onCommitted: (v, {bool advance = true}) =>
                                    _anotar(p, h - 1, v, advance: advance),
                                // Mantener pulsado: diálogo clásico (corregir con
                                // teclado numérico grande, o BORRAR el hoyo).
                                onLongPress: () => _corregir(p, h),
                              ),
                          ]),
                        ),
                    ]),
              ),
              if (_r.correcciones.isNotEmpty) ...[
                const SizedBox(height: 20),
                _Etiqueta('CORRECCIONES', t: t),
                const SizedBox(height: 6),
                // Las más recientes arriba: al mirar esto se busca la última.
                for (final c in _r.correcciones.reversed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(GolfIcons.arrastra,
                              size: GolfIcons.juntoAEtiqueta, color: t.sub),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c.frase, style: GolfType.value(t.text)),
                                  Text(
                                      '${c.porNombre} · '
                                      '${_cuando(c.cuando)}',
                                      style: GolfType.label(t.sub)),
                                ]),
                          ),
                        ]),
                  ),
              ],
              const SizedBox(height: 24),
            ]),
          ),
          SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _cerrar,
                style: TextButton.styleFrom(foregroundColor: t.sub),
                child: const Text('Cerrar'),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  static String _cuando(DateTime d) =>
      '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

/// Pide el score nuevo. Devuelve null si se cancela, `(valor,)` si se acepta.
///
/// El registro `(int?,)` distingue lo que un `int?` solo no puede: cancelar y
/// borrar el score son dos cosas y las dos serían null.
Future<(int?,)?> _pedirScore(
    BuildContext context, GolfTheme t, Player p, int hoyo, int? actual) async {
  final ctrl = TextEditingController(text: actual?.toString() ?? '');
  return showDialog<(int?,)?>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: t.card,
      title: Text('${p.name} · hoyo $hoyo', style: GolfType.title(t.text)),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        style: TextStyle(color: t.text),
        decoration: InputDecoration(
          labelText: 'Golpes',
          labelStyle: TextStyle(color: t.sub),
          helperText: actual == null ? 'Este hoyo está vacío' : 'Ahora: $actual',
          helperStyle: TextStyle(color: t.sub),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('Cancelar', style: TextStyle(color: t.sub)),
        ),
        if (actual != null)
          TextButton(
            onPressed: () => Navigator.pop(ctx, (null,)),
            child: Text('Borrar', style: TextStyle(color: t.loss)),
          ),
        TextButton(
          onPressed: () {
            final v = int.tryParse(ctrl.text.trim());
            // Fuera de rango no se guarda: un 0 o un 30 en un hoyo es un dedo,
            // no un score, y corregirlo mal es peor que no corregirlo.
            if (v == null || v < 1 || v > 20) {
              Navigator.pop(ctx);
              return;
            }
            Navigator.pop(ctx, (v,));
          },
          child: Text('Guardar', style: TextStyle(color: t.primary)),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// PIEZAS
// ─────────────────────────────────────────────────────────────────────────────
/// Casilla EDITABLE en línea: se teclea el score encima y el foco pasa solo al
/// siguiente hoyo (lo hace el padre en `onCommitted`). Rellenar una tarjeta de
/// 18 se siente como en papel, sin abrir un diálogo por hoyo.
///
/// El salto y los dos dígitos (criterio 1 y 2 del encargo):
///  - Un dígito 3–9 es inequívoco (30+ no existe en golf): guarda y avanza YA.
///  - Un 1 o un 2 puede ser el score o el inicio de 10–20: espera 650 ms un 2º
///    dígito. Si llega, forma el número (10–20) y avanza; si no, guarda el
///    único y avanza. Enter/Tab fuerzan el avance sin esperar.
///  - Al salir de la casilla sin avanzar, un valor válido pendiente se guarda
///    igual (no se pierde).
class _CasillaEditable extends StatefulWidget {
  final int? score;
  final int? par;
  final GolfTheme t;
  final FocusNode focusNode;
  // advance=true (tecleo): guarda y avanza al hoyo siguiente. advance=false
  // (blur): guarda el valor pendiente pero NO mueve el foco — si el usuario tocó
  // otra casilla, no se lo robamos.
  final void Function(int value, {bool advance}) onCommitted;
  final VoidCallback? onLongPress;
  const _CasillaEditable({
    super.key,
    required this.score,
    required this.par,
    required this.t,
    required this.focusNode,
    required this.onCommitted,
    this.onLongPress,
  });

  @override
  State<_CasillaEditable> createState() => _CasillaEditableState();
}

class _CasillaEditableState extends State<_CasillaEditable> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.score?.toString() ?? '');
  Timer? _ambiguo; // espera de un posible 2º dígito tras un 1 o un 2

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFoco);
  }

  @override
  void didUpdateWidget(covariant _CasillaEditable old) {
    super.didUpdateWidget(old);
    // Si el score cambió por fuera (guardado/otra corrección) y esta casilla no
    // está enfocada, se refleja; si está enfocada, manda lo que se teclea.
    if (widget.score != old.score && !widget.focusNode.hasFocus) {
      final txt = widget.score?.toString() ?? '';
      if (_ctrl.text != txt) _ctrl.text = txt;
    }
  }

  @override
  void dispose() {
    _ambiguo?.cancel();
    widget.focusNode.removeListener(_onFoco);
    _ctrl.dispose();
    super.dispose();
  }

  void _onFoco() {
    if (widget.focusNode.hasFocus) {
      // Al entrar, selecciona todo: teclear reemplaza (sirve para corregir).
      _ctrl.selection =
          TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
    } else {
      // Al salir: un valor válido que aún esperaba 2º dígito se guarda igual,
      // pero SIN avanzar el foco (el usuario ya movió el foco a otra parte).
      _ambiguo?.cancel();
      final v = int.tryParse(_ctrl.text.trim());
      if (v != null && v >= 1 && v <= 20 && v != widget.score) {
        widget.onCommitted(v, advance: false);
      }
    }
    if (mounted) setState(() {}); // repinta el borde de foco
  }

  void _commit(int v) {
    _ambiguo?.cancel();
    widget.onCommitted(v, advance: true); // el padre persiste y avanza el foco
  }

  void _esperar(int d) {
    _ambiguo?.cancel();
    _ambiguo = Timer(const Duration(milliseconds: 650), () {
      if (mounted) _commit(d);
    });
  }

  void _setText(String s) {
    if (_ctrl.text == s) return;
    _ctrl.value = TextEditingValue(
      text: s,
      selection: TextSelection.collapsed(offset: s.length),
    );
  }

  void _onChanged(String raw) {
    _ambiguo?.cancel();
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      _setText('');
      return;
    }
    if (digits.length >= 2) {
      final two = int.parse(digits.substring(0, 2));
      if (two >= 10 && two <= 20) {
        _setText(digits.substring(0, 2));
        _commit(two); // 2 dígitos válidos → completo
      } else {
        // 2º dígito imposible (p. ej. 25): se descarta, se sigue sobre el 1º.
        final first = digits.substring(0, 1);
        _setText(first);
        _esperar(int.parse(first));
      }
      return;
    }
    final d = int.parse(digits);
    _setText(digits);
    if (d >= 3 && d <= 9) {
      _commit(d); // inequívoco de una cifra → avanza ya
    } else if (d == 1 || d == 2) {
      _esperar(d); // podría crecer a 10–20
    }
    // d == 0: no es un score; no se guarda (se espera corrección).
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final v = int.tryParse(_ctrl.text);
    final Color color;
    if (v == null || widget.par == null) {
      color = t.sub;
    } else if (v < widget.par!) {
      color = t.profit;
    } else if (v > widget.par!) {
      color = t.loss;
    } else {
      color = t.text;
    }
    final enfocada = widget.focusNode.hasFocus;
    return GestureDetector(
      onLongPress: widget.onLongPress,
      child: Container(
        width: 34,
        height: 30,
        alignment: Alignment.center,
        margin: const EdgeInsets.only(right: 1),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: enfocada ? t.primary : t.divider),
        ),
        child: TextField(
          controller: _ctrl,
          focusNode: widget.focusNode,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          textInputAction: TextInputAction.next,
          maxLength: 2,
          buildCounter: (_,
                  {required int currentLength,
                  required bool isFocused,
                  int? maxLength}) =>
              null,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: GolfType.value(color),
          cursorColor: t.primary,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.zero,
            border: InputBorder.none,
            hintText: '·',
            hintStyle: GolfType.value(t.sub),
          ),
          onChanged: _onChanged,
          onSubmitted: (_) {
            final val = int.tryParse(_ctrl.text.trim());
            if (val != null && val >= 1 && val <= 20) _commit(val);
          },
        ),
      ),
    );
  }
}

class _FilaDeGrupo extends StatelessWidget {
  final GrupoDelTorneo grupo;
  final GolfTheme t;
  final VoidCallback onTap;
  const _FilaDeGrupo(
      {required this.grupo, required this.t, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final falta = grupo.totalHoles - grupo.hoyosCapturados;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(children: [
              Icon(grupo.cerrada ? GolfIcons.bien : GolfIcons.golpe,
                  size: GolfIcons.juntoAValor,
                  color: grupo.cerrada ? t.primary : t.sub),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(grupo.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GolfType.value(t.text)),
                      Text(grupo.jugadores.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GolfType.label(t.sub)),
                    ]),
              ),
              const SizedBox(width: 8),
              // Por qué hoyo va: es LA pregunta del organizador, y aquí sí se
              // puede contestar porque la ronda es suya y se lee entera.
              Text(
                  grupo.cerrada
                      ? 'Cerrada'
                      : falta <= 0
                          ? 'Sin cerrar'
                          : 'Van ${grupo.hoyosCapturados}/${grupo.totalHoles}',
                  style: GolfType.label(grupo.cerrada ? t.primary : t.sub)),
              Icon(Icons.chevron_right, size: 18, color: t.sub),
            ]),
          ),
        ),
      ),
    );
  }
}

class _FilaAjena extends StatelessWidget {
  final ResultadoPublicado publicado;
  final GolfTheme t;
  const _FilaAjena({required this.publicado, required this.t});

  @override
  Widget build(BuildContext context) {
    final r = publicado.resultado;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.divider),
        ),
        child: Row(children: [
          Icon(GolfIcons.cerrado, size: GolfIcons.juntoAValor, color: t.sub),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.roundName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GolfType.value(t.text)),
                  Text(
                      '${publicado.jugadorNombre} · '
                      '${r.playerIds.length} jugador'
                      '${r.playerIds.length == 1 ? '' : 'es'}',
                      style: GolfType.label(t.sub)),
                ]),
          ),
          // La FECHA, siempre. Es lo que separa esto de un directo.
          Text('${r.playedAt.day}/${r.playedAt.month}',
              style: GolfType.label(t.sub)),
        ]),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final GolfTheme t;
  final String texto;
  const _Aviso({required this.t, required this.texto});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.divider),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(GolfIcons.pantalla,
              size: GolfIcons.juntoAValor, color: t.sub),
          const SizedBox(width: 9),
          Expanded(
            child: Text(texto,
                style: TextStyle(color: t.sub, fontSize: 12.5, height: 1.4)),
          ),
        ]),
      );
}

class _Etiqueta extends StatelessWidget {
  final String texto;
  final GolfTheme t;
  const _Etiqueta(this.texto, {required this.t});
  @override
  Widget build(BuildContext context) => Text(texto, style: GolfType.label(t.sub));
}

class _Vacio extends StatelessWidget {
  final GolfTheme t;
  final String texto;
  const _Vacio({required this.t, required this.texto});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(texto,
            style: TextStyle(color: t.sub, fontSize: 12, height: 1.35)),
      );
}
