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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../../models/torneo_seguido.dart';
import '../../providers/torneo_provider.dart';
import '../../services/auth_service.dart';
import '../../core/app_theme.dart';
import '../../widgets/bracket_tree.dart';
import '../../models/torneo_publicado.dart';

// ══════════════════════════════════════════════════════════════════════════════
// ELEGIR TU JUGADOR — libre, y por qué eso no es un agujero
// ══════════════════════════════════════════════════════════════════════════════
//
// El invitado abre el enlace, ve la lista y dice "soy Luis Herrera". A partir de
// ahí ve SU llave y SU partido. No hace falta cuenta, ni correo, ni que el
// organizador apruebe nada.
//
// Y ESO NO SE VA A ENDURECER DESPUÉS. Que dos personas elijan el mismo nombre no
// tiene coste, porque en un torneo donde no se conoce la gente difícilmente hay
// dinero; y donde hay dinero, la gente se registra igual porque es el suyo. La
// fricción se autorregula, así que NO se construye aprobación del organizador ni
// resolución de conflictos: sería una capa de permisos para un problema que el
// caso no tiene.
//
// La autoridad la da LA CUENTA, no la selección. Elegir jugador es una preferencia
// de visualización guardada en este teléfono; escribir un score exige cuenta, y
// esa puerta está en el momento en que se intenta, no antes.
//
// Queda escrito aquí para que nadie añada luego lo que este encargo descartó a
// propósito.
class TorneoInvitadoScreen extends StatefulWidget {
  final TorneoPublicado copia;
  const TorneoInvitadoScreen({super.key, required this.copia});

  @override
  State<TorneoInvitadoScreen> createState() => _TorneoInvitadoScreenState();
}

class _TorneoInvitadoScreenState extends State<TorneoInvitadoScreen> {
  TorneoPublicado get copia => widget.copia;

  /// El nombre que el invitado dijo que es. null = todavía no lo dijo.
  String? _yoSoy;

  /// La clave donde se recuerda, por token: quien mira dos torneos distintos es
  /// una persona distinta en cada uno.
  String get _clave => 'invitado_soy_${copia.token}';

  /// Los nombres entre los que elegir.
  ///
  /// De la tabla Y del cuadro, unidos. Solo de la tabla no basta: un torneo de
  /// eliminación recién armado no tiene rondas jugadas, y entonces las filas
  /// salen sin nombre —el guion— así que la lista habría sido de guiones. Lo
  /// destapó el test.
  List<String> get _candidatos {
    final out = <String>{};
    for (final f in copia.tabla) {
      if (f.nombre.isNotEmpty && f.nombre != '—') out.add(f.nombre);
    }
    for (final p in copia.llave) {
      for (final n in [p.a, p.b]) {
        if (n != null && n.isNotEmpty && n != '—') out.add(n);
      }
    }
    final lista = out.toList()..sort();
    return lista;
  }

  @override
  void initState() {
    super.initState();
    _recordar();
  }

  Future<void> _recordar() async {
    final prefs = await SharedPreferences.getInstance();
    final guardado = prefs.getString(_clave);
    // Solo si sigue en la lista: si el organizador lo saca, la preferencia deja
    // de valer y se vuelve a preguntar.
    if (!mounted || guardado == null) return;
    if (_candidatos.contains(guardado)) {
      setState(() => _yoSoy = guardado);
    }
  }

  Future<void> _elegir(String? nombre) async {
    setState(() => _yoSoy = nombre);
    final prefs = await SharedPreferences.getInstance();
    if (nombre == null) {
      await prefs.remove(_clave);
    } else {
      await prefs.setString(_clave, nombre);
    }
  }

  /// La puerta de la cuenta: se abre cuando se intenta ESCRIBIR, no antes.
  void _pedirCuenta(GolfTheme t, String queIba) {
    showModalBottomSheet(
      context: context,
      backgroundColor: t.bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('⛳', style: TextStyle(fontSize: 34)),
            const SizedBox(height: 10),
            Text('Para $queIba hace falta cuenta',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: t.text, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            // Se explica la diferencia, que es la que justifica la puerta: mirar
            // es leer una copia; anotar es escribir en la ronda de otros.
            Text(
                'Ver el torneo no necesita nada: es una copia. Anotar scores sí, '
                'porque se escribe en la ronda que están jugando los demás, y ahí '
                'hay que saber quién eres.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.sub, fontSize: 12.5, height: 1.45)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                    backgroundColor: t.primary,
                    foregroundColor: t.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 13)),
                child: const Text('Descargar la app y crear cuenta',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 8),
            Text('Seguir mirando no necesita nada.',
                style: TextStyle(color: t.sub, fontSize: 11)),
          ]),
        ),
      ),
    );
  }

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

              // ── ¿Quién eres? ──────────────────────────────────────
              //
              // Va arriba: lo que alguien quiere de un enlace de torneo es SU
              // llave, y todo lo de abajo se lee distinto una vez dicho.
              _bloqueYoSoy(t),
              const SizedBox(height: 14),

              // ── Que mis rondas cuenten aquí ───────────────────────
              //
              // AL NIVEL DEL TORNEO, no dentro del bloque de identidad. Ahí es
              // donde estaba y por eso no se veía: ese bloque hace return en la
              // rama de "todavía no has dicho quién eres", que es justo la que ve
              // cualquiera al abrir el enlace. La lógica estaba construida y
              // probada; la superficie no llegaba.
              //
              // Y va aquí porque no es una pregunta sobre QUIÉN eres: es sobre si
              // lo que juegues cuenta para este torneo. Son dos decisiones
              // distintas y una no depende de la otra —se puede seguir un torneo
              // sin decir cuál eres, y al contrario—.
              _BotonSeguir(
                  copia: copia,
                  t: t,
                  // El nombre reclamado. Sin él no se puede seguir, y eso NO es
                  // una restricción técnica: la lista del enlace solo trae
                  // inscritos, así que encontrarse en ella ES la comprobación de
                  // estar inscrito. Quien no se encuentra, no está.
                  jugadorNombre: _yoSoy,
                  onPedirCuenta: () => _pedirCuenta(
                      t, 'que tus rondas cuenten para este torneo')),
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

              // El cuadro, si lo hay. Va antes de la clasificación por lo mismo
              // que dentro de la app: en una eliminación la pregunta es quién
              // pasó, no quién acumula más.
              if (copia.llave.isNotEmpty) ...[
                if (copia.campeon != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: t.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: t.primary),
                    ),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        const Text('🏆', style: TextStyle(fontSize: 24)),
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('CAMPEÓN',
                                  style: TextStyle(
                                      color: t.sub,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.8)),
                              Text(copia.campeon!,
                                  style: TextStyle(
                                      color: t.text,
                                      fontSize: 19,
                                      fontWeight: FontWeight.w800)),
                            ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Text('EL CUADRO',
                    style: TextStyle(
                        color: t.sub,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8)),
                const SizedBox(height: 8),
                // El MISMO árbol que la app, no un dibujo aparte. Es la pantalla
                // que alguien abre desde WhatsApp sin tener la app instalada, así
                // que es donde un cuadro bien dibujado hace más trabajo.
                //
                // Sin resaltado: aquí no se sabe quién mira.
                // Con el nombre elegido, el árbol resalta su camino y arranca en
                // su fase: es el mismo widget que la app, y ya sabía hacerlo.
                ArbolDeLlaveVista(arbol: _arbol(), t: t, miNombre: _yoSoy),
                const SizedBox(height: 18),
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

  /// "Soy Luis Herrera", y lo que eso enseña.
  Widget _bloqueYoSoy(GolfTheme t) {
    final mio = _yoSoy;
    final fila = mio == null
        ? null
        : copia.tabla.where((f) => f.nombre == mio).firstOrNull;

    if (mio == null) {
      // Sin elegir: la pregunta, y la lista. Nada más —ni cuenta, ni correo—
      // porque la selección es una preferencia, no una credencial.
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: t.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.primary.withValues(alpha: 0.5)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('¿CUÁL ERES TÚ?',
              style: TextStyle(
                  color: t.sub,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8)),
          const SizedBox(height: 4),
          Text(
              'Dilo y se marca tu camino en el cuadro. No hace falta cuenta ni '
              'correo: se guarda solo en este teléfono.',
              style: TextStyle(color: t.text, fontSize: 12, height: 1.35)),
          const SizedBox(height: 9),
          if (_candidatos.isEmpty)
            Text('El organizador todavía no ha publicado la lista.',
                style: TextStyle(color: t.sub, fontSize: 11.5)),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final nombre in _candidatos)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _elegir(nombre),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: t.divider),
                  ),
                  child: Text(nombre,
                      style: TextStyle(
                          color: t.text,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                ),
              ),
          ]),
        ]),
      );
    }

    // Elegido: lo suyo. El partido pendiente primero, que es la pregunta.
    final arbol = _arbol();
    final mios = [
      for (final fase in arbol.rondas)
        for (final n in fase)
          if (n.a == mio || n.b == mio) n
    ];
    final pendiente = mios.where((n) => n.ganador == null).firstOrNull;
    final ultimo = mios.isEmpty ? null : mios.last;
    final fuera = pendiente == null &&
        ultimo != null &&
        ultimo.ganador != null &&
        ultimo.ganador != mio;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: t.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.primary),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(mio,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: t.text, fontSize: 16, fontWeight: FontWeight.w800)),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _elegir(null),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text('No soy yo', style: GolfType.label(t.primary)),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
            copia.campeon == mio
                ? '🏆 Campeón del torneo.'
                : fuera
                    ? 'Fuera del cuadro: perdiste en '
                        '${ArbolDeLlave.nombreDeFase(arbol.rondas[ultimo.ronda].length)}.'
                    : pendiente == null
                        ? 'Sin partido pendiente ahora mismo.'
                        : 'Te toca en '
                            '${ArbolDeLlave.nombreDeFase(arbol.rondas[pendiente.ronda].length)}'
                            '${_rivalDe(pendiente, mio, arbol)}',
            style: TextStyle(color: t.text, fontSize: 12.5, height: 1.35)),
        if (fila != null) ...[
          const SizedBox(height: 3),
          Text('Puesto ${fila.puesto} · ${fila.jugadas} rondas jugadas',
              style: TextStyle(color: t.sub, fontSize: 11)),
        ],
        // La puerta de la cuenta, ofrecida solo cuando hay algo que jugar.
        if (pendiente != null) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _pedirCuenta(t, 'anotar los scores de tu partido'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: t.primary,
                  foregroundColor: t.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 12)),
              child: const Text('Jugar este partido',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ]),
    );
  }

  /// " contra Luis" o " contra el ganador de Cuartos 2", según se sepa.
  String _rivalDe(NodoDeLlave n, String mio, ArbolDeLlave arbol) {
    final otro = n.a == mio ? n.b : n.a;
    if (otro != null) return ' contra $otro.';
    final lado = n.a == mio ? 1 : 0;
    final de = arbol.procedenciaDe(n, lado);
    return de == null ? '.' : ' contra el ${de.toLowerCase()}.';
  }

  /// El cuadro publicado, en la forma que dibuja el árbol.
  ///
  /// La instantánea trae los partidos PLANOS —con su fase y su posición— para que
  /// el documento sea una lista y no un árbol anidado. El árbol se reconstruye
  /// aquí: el partido i de la fase n lo alimentan el 2i y el 2i+1 de la n-1.
  ArbolDeLlave _arbol() => ArbolDeLlave(
        rondas: [
          for (final fase in _fases())
            [
              for (final p in fase)
                NodoDeLlave(
                  ronda: p.ronda,
                  posicion: p.posicion,
                  a: p.a,
                  b: p.b,
                  ganador: p.ganador,
                  bye: p.bye,
                  empatado: p.empatado,
                  nota: p.enRonda,
                ),
            ],
        ],
        campeon: copia.campeon,
        // La instantánea no publica plazas ni byes —no hacían falta para la
        // lista— y el árbol los deduce: las plazas son el doble de partidos de la
        // primera fase, y los byes los partidos con un solo lado.
        plazas: copia.llave.isEmpty
            ? 0
            : copia.llave.where((p) => p.ronda == 0).length * 2,
        byes: copia.llave.where((p) => p.ronda == 0 && p.bye).length,
      );

  /// Los partidos agrupados por fase, en orden. La instantánea los trae planos
  /// para que el documento sea una lista y no un árbol anidado.
  List<List<PartidoPublicado>> _fases() {
    final por = <int, List<PartidoPublicado>>{};
    for (final p in copia.llave) {
      (por[p.ronda] ??= []).add(p);
    }
    final claves = por.keys.toList()..sort();
    // Dentro de la fase, por POSICIÓN: el orden de la lista del documento no es
    // garantía, y el árbol sí depende de él para saber qué alimenta a qué.
    for (final k in claves) {
      por[k]!.sort((a, b) => a.posicion.compareTo(b.posicion));
    }
    return [for (final k in claves) por[k]!];
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

/// "Que mis rondas cuenten para este torneo".
///
/// Con cuenta, guarda la referencia —id, token y dueño— para que el asistente
/// pueda marcar rondas a este torneo y el cierre publique su resultado. Sin
/// cuenta, ofrece hacerse una: seguir escribe, y escribir necesita saber quién
/// eres.
class _BotonSeguir extends StatefulWidget {
  final TorneoPublicado copia;
  final GolfTheme t;

  /// El nombre de la lista que esta persona dijo que es. null = todavía no lo
  /// dijo, y entonces no se puede seguir: el resultado no se podría emparejar
  /// con ningún inscrito y se descartaría en silencio.
  final String? jugadorNombre;

  final VoidCallback onPedirCuenta;

  const _BotonSeguir(
      {required this.copia,
      required this.t,
      required this.jugadorNombre,
      required this.onPedirCuenta});

  @override
  State<_BotonSeguir> createState() => _BotonSeguirState();
}

class _BotonSeguirState extends State<_BotonSeguir> {
  bool _ocupado = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final prov = context.watch<TorneoProvider>();
    // El id DEL TORNEO, no el token. Es lo que la tabla del organizador consulta,
    // así que usar el token como identidad dejaba lo escrito y lo consultado sin
    // coincidir. Ver TorneoPublicado.torneoId.
    final id = widget.copia.torneoId;
    final siguiendo = prov.seguidos.any((s) => s.torneoId == id);
    final sinSesion = AuthService.uid == null;

    // ── El DUEÑO no sigue su propio torneo ──────────────────────────────────
    //
    // Intencionado: sus rondas ya cuentan sin hacer nada, porque la tabla lee su
    // propia colección. Ofrecerle "que mis rondas cuenten aquí" sería ofrecerle
    // algo que ya tiene, y seguirlo crearía una referencia que además duplicaría
    // sus resultados —los publicaría en torneoResultados además de tenerlos en su
    // colección—. Se dice en vez de callarlo, para que no parezca que falta.
    final soyElDueno = AuthService.uid != null &&
        AuthService.uid == widget.copia.ownerUid;
    if (soyElDueno) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: t.divider),
        ),
        child: Text(
            'Este torneo es tuyo: tus rondas ya cuentan sin hacer nada. Este '
            'enlace es lo que ven los demás.',
            style: TextStyle(color: t.sub, fontSize: 11.5, height: 1.35)),
      );
    }

    // ── Sin decir cuál eres, no se puede seguir ─────────────────────────────
    //
    // Y aquí está el aviso que faltaba, el del OTRO lado del filtro. La tabla
    // descarta los resultados que no puede emparejar con un inscrito —y lo dice—
    // pero eso se ve DESPUÉS de jugar. Esto lo dice antes.
    //
    // La lista de arriba solo trae inscritos, así que no encontrarse en ella es
    // la señal de que no lo estás. Se dice con la salida: pídeselo al
    // organizador.
    final mio = widget.jugadorNombre;
    if (mio == null || mio.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: t.scoreOver.withValues(alpha: 0.5)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('PARA QUE TUS RONDAS CUENTEN',
              style: TextStyle(
                  color: t.sub,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8)),
          const SizedBox(height: 4),
          Text(
              'Di arriba cuál eres de la lista. Si no te encuentras, no estás '
              'entre los participantes: pídele al organizador que te añada, y '
              'entonces podrás elegirte y tus rondas contarán.',
              style: TextStyle(color: t.text, fontSize: 11.5, height: 1.35)),
        ]),
      );
    }

    // Instantánea vieja, publicada antes de que el id viajara. Seguirla crearía
    // una referencia que no funcionaría, así que se dice qué hace falta en vez de
    // dejar un botón que no lleva a nada.
    if (id.isEmpty) {
      return Text(
          'Para que tus rondas cuenten aquí, el organizador tiene que volver a '
          'compartir el torneo: este enlace se publicó antes de que se pudiera.',
          style: TextStyle(color: t.sub, fontSize: 11, height: 1.35));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _ocupado
            ? null
            : () async {
                if (AuthService.uid == null) {
                  widget.onPedirCuenta();
                  return;
                }
                setState(() => _ocupado = true);
                try {
                  if (siguiendo) {
                    await prov.dejarDeSeguir(id);
                  } else {
                    await prov.seguir(TorneoSeguido(
                      torneoId: id,
                      token: widget.copia.token,
                      ownerUid: widget.copia.ownerUid,
                      nombre: widget.copia.nombre,
                      emoji: widget.copia.emoji,
                      desde: DateTime.now(),
                      jugadorNombre: mio,
                    ));
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('No se pudo guardar: $e')));
                  }
                }
                if (mounted) setState(() => _ocupado = false);
              },
        style: OutlinedButton.styleFrom(
            side: BorderSide(color: siguiendo ? t.primary : t.divider),
            foregroundColor: siguiendo ? t.primary : t.text,
            padding: const EdgeInsets.symmetric(vertical: 11)),
        icon: Icon(
            siguiendo
                ? Icons.check
                : sinSesion
                    ? Icons.login
                    : Icons.add,
            size: 16),
        // Sin sesión NO se esconde la opción: se dice qué hace falta. Ocultarla
        // dejaría a alguien que quiere que sus rondas cuenten sin saber que
        // existe, que es el mismo criterio que aplicamos al capturar scores —la
        // cuenta se pide al escribir, y explicando la diferencia—.
        label: Text(
            siguiendo
                ? 'Tus rondas cuentan para este torneo'
                : sinSesion
                    ? 'Inicia sesión para que tus rondas cuenten aquí'
                    : 'Que mis rondas cuenten aquí',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
      ),
      ),
      const SizedBox(height: 5),
      // PARA QUÉ sirve, siempre. Un botón que dice "que mis rondas cuenten aquí"
      // sin explicar qué significa se toca a ciegas o no se toca.
      Text(
          siguiendo
              ? 'Al cerrar una ronda marcada para este torneo, su resultado se '
                  'envía a la tabla del organizador como $mio.'
              : 'Las rondas que juegues podrás marcarlas para este torneo, y su '
                  'resultado contará en su tabla como $mio.',
          style: TextStyle(color: t.sub, fontSize: 10.5, height: 1.3)),
    ]);
  }
}
