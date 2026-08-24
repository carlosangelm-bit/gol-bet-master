// ─────────────────────────────────────────────────────────────────────────────
// CREAR O EDITAR UN TORNEO — cuatro decisiones, todas opción
//
// Ninguna es fija: qué rondas cuentan, cómo puntúa cada una, cómo se acumula y
// quién entra en la tabla.
//
// Y las combinaciones que no significan nada salen ATENUADAS CON SU MOTIVO, no
// elegibles y rotas: mejores N en un torneo de una ronda, puntuar por Stableford
// sin rondas que lo tengan guardado, un mínimo mayor que las rondas que hay. Es
// el mismo criterio del paso de qué se juega, y los motivos viven en torneo.dart
// para que la pantalla no los invente.
//
// El default de acumulación cambia con el tamaño: suma simple en un torneo
// corto, mejores N en uno de temporada. Sumar premia al que más juega, no al que
// mejor juega, y eso solo importa cuando hay muchas rondas.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../widgets/importar_jugadores_sheet.dart';
import '../../models/models.dart';
import '../../models/round_result.dart';
import '../../models/torneo.dart';
import '../../providers/betting_group_provider.dart';
import '../../providers/perfil_provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/torneo_provider.dart';

class TorneoEditorScreen extends StatefulWidget {
  final Torneo? existente;
  const TorneoEditorScreen({super.key, required this.existente});

  @override
  State<TorneoEditorScreen> createState() => _TorneoEditorScreenState();
}

class _TorneoEditorScreenState extends State<TorneoEditorScreen> {
  late Torneo _t;
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _puntosCtrl;
  late final TextEditingController _entradaCtrl;
  late final TextEditingController _jornadaCtrl;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _t = widget.existente ?? const Torneo(id: '', nombre: '');
    _nombreCtrl = TextEditingController(text: _t.nombre);
    _puntosCtrl =
        TextEditingController(text: _t.puntosPorPuesto.join(', '));
    _entradaCtrl = TextEditingController(
        text: _t.bote.hayBote ? _t.bote.entrada.toStringAsFixed(0) : '');
    _jornadaCtrl = TextEditingController(
        text: _t.bote.hayBoteJornada
            ? _t.bote.entradaPorJornada.toStringAsFixed(0)
            : '');
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _puntosCtrl.dispose();
    _entradaCtrl.dispose();
    _jornadaCtrl.dispose();
    super.dispose();
  }

  /// Las rondas que el torneo tendría AHORA. Se recalcula en cada build para que
  /// los avisos hablen de la configuración que se está tocando, no de la que
  /// había al abrir.
  List<RoundResult> get _rondas => rondasDelTorneo(_t, _todos);

  List<RoundResult> get _todos => context.read<PerfilProvider>().resultados;

  /// Cuántos ponen al bote: los INSCRITOS.
  ///
  /// Contaba los jugadores de las RONDAS, y por eso el total no se movía al
  /// quitar chips: seguía en $27500 con 47 inscritos porque las 79 rondas del
  /// rango tenían 55 personas. Dos bugs a la vez con el mismo síntoma —la lista
  /// que no se veía guardada y el total que no reaccionaba— y este era el
  /// segundo.
  int get _inscritos => _t.participantes.length;

  @override
  Widget build(BuildContext context) {
    final t = context.gt;
    final rondas = _rondas;
    final grupos = context.watch<BettingGroupProvider>().groups;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        foregroundColor: t.text,
        title: Text(widget.existente == null ? 'Nuevo torneo' : 'Editar torneo'),
        elevation: 0,
        actions: [
          if (widget.existente != null)
            IconButton(
              icon: Icon(Icons.delete_outline, color: t.sub),
              onPressed: _borrar,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          TextField(
            controller: _nombreCtrl,
            style: TextStyle(color: t.text),
            decoration: InputDecoration(
              labelText: 'Nombre del torneo',
              labelStyle: TextStyle(color: t.sub),
              filled: true,
              fillColor: t.surface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: t.divider)),
            ),
          ),
          const SizedBox(height: 20),

          // ── 1 · El formato ─────────────────────────────────────────────
          //
          // Va primero porque reencuadra todo lo de debajo: en un cuadro la
          // pregunta es a quién te toca, no cuánto acumulas. Y no cambia cómo se
          // juega —un torneo nunca lo cambia— solo qué se enseña.
          _titulo('1 · FORMATO', t),
          for (final f in FormatoDeTorneo.values)
            _opcion(
              t: t,
              titulo: f.label,
              detalle: f.descripcion,
              activa: _t.formato == f,
              onTap: () => setState(() => _t = _t.copyWith(formato: f)),
              // Solo se bloquea por la FUENTE, que es lo que impide que un
              // cuadro funcione. La falta de inscritos la dice el bloque de la
              // siembra: es un "todavía no", y bloquear por eso obligaría a
              // bajar al paso 3 y volver a subir.
              motivo: f == FormatoDeTorneo.eliminacion &&
                      _t.formato != FormatoDeTorneo.eliminacion
                  ? motivoSinCuadro(_t, exigirInscritos: false)
                  : null,
            ),
          if (_t.formato == FormatoDeTorneo.eliminacion) ...[
            const SizedBox(height: 8),
            _bloqueSiembra(t),
          ],
          const SizedBox(height: 22),

          // ── 2 · Qué rondas cuentan ─────────────────────────────────────
          _titulo('2 · QUÉ RONDAS CUENTAN', t),
          // Solo las fuentes que se OFRECEN. La retirada por fechas sigue en el
          // enum para que un torneo guardado se lea igual, pero no se puede
          // elegir de nuevo: un rango arrastra rondas que nadie marcó.
          for (final f in fuentesOfrecibles)
            _opcion(
              t: t,
              titulo: f.label,
              detalle: f.descripcion,
              activa: _t.fuente == f,
              onTap: () => setState(() => _t = _t.copyWith(fuente: f)),
            ),
          // Y si ESTE torneo la usa, se enseña —marcada, y con el motivo—. Callar
          // una fuente que el torneo está usando dejaría la pantalla mintiendo
          // sobre de dónde salen sus rondas.
          if (_t.fuente.motivoRetirada != null) ...[
            _opcion(
              t: t,
              titulo: '${_t.fuente.label} · retirada',
              detalle: '',
              activa: true,
              onTap: () {},
              motivo: 'En uso por este torneo. Ya no se puede elegir de nuevo.',
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.scoreOver.withValues(alpha: 0.5)),
              ),
              child: Text(_t.fuente.motivoRetirada!,
                  style: TextStyle(color: t.text, fontSize: 12, height: 1.4)),
            ),
          ],
          // ── Elegidas a mano: LAS RONDAS ────────────────────────────────
          //
          // Esto no existía. La opción estaba, su texto prometía "eliges de entre
          // las rondas ya jugadas", y el control no se había construido nunca:
          // el modelo guardaba roundIds y rondasDelTorneo los leía, pero no había
          // forma de ponerlos. Así que un torneo sobre el histórico —para lo que
          // la fuente existe— no se podía armar.
          if (_t.fuente == FuenteDeRondas.manual) ...[
            const SizedBox(height: 8),
            _bloqueRondasAMano(t),
          ],
          if (_t.fuente == FuenteDeRondas.grupo) ...[
            const SizedBox(height: 8),
            if (grupos.isEmpty)
              _nota(
                  'No tienes grupos de apuesta guardados. Se crean en '
                  'Plantillas.',
                  t)
            else
              for (final g in grupos)
                _opcion(
                  t: t,
                  titulo: '${g.emoji} ${g.name}',
                  detalle: '${g.playerIds.length} habituales',
                  activa: _t.bettingGroupId == g.id,
                  onTap: () =>
                      setState(() => _t = _t.copyWith(bettingGroupId: g.id)),
                ),
          ],
          // Las fechas solo donde filtran algo: la fuente por marcas no las mira
          // —cuenta lo que se marcó, no cuándo se jugó— y la manual tampoco.
          if (_t.fuente == FuenteDeRondas.grupo ||
              _t.fuente == FuenteDeRondas.rango) ...[
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _fecha(t, 'Desde', _t.desde,
                  (d) => setState(() => _t = _t.copyWith(desde: d)),
                  () => setState(() => _t = _t.copyWith(limpiarDesde: true)))),
              const SizedBox(width: 8),
              Expanded(child: _fecha(t, 'Hasta', _t.hasta,
                  (d) => setState(() => _t = _t.copyWith(hasta: d)),
                  () => setState(() => _t = _t.copyWith(limpiarHasta: true)))),
            ]),
          ],
          const SizedBox(height: 8),
          _nota(
              '${rondas.length} ronda${rondas.length == 1 ? '' : 's'} '
              '${rondas.length == 1 ? 'entra' : 'entran'} con esta fuente.',
              t),
          // El aviso que faltaba, y salió de usarlo con datos reales: una fuente
          // por fechas arrastró ochenta rondas de prueba y el bote dio una cifra
          // que nadie puso encima de la mesa. Se dice CON EL NÚMERO antes de
          // guardar, no se descubre en la tabla.
          if (avisoDeArrastre(_t, tablaDe(_t, _todos)) != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: t.scoreOver.withValues(alpha: 0.5)),
              ),
              child: Text(avisoDeArrastre(_t, tablaDe(_t, _todos))!,
                  style: TextStyle(
                      color: t.text, fontSize: 12, height: 1.4)),
            ),
          ],
          const SizedBox(height: 22),

          // ── 3 · Quién participa ────────────────────────────────────────
          //
          // La lista explícita. Participa quien SE INSCRIBE, no quien juegue: con
          // un bote de por medio, poner $500 es una decisión y no algo que te
          // pase por jugar un sábado.
          _titulo('3 · QUIÉN PARTICIPA', t),
          if (_t.participantes.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.scoreOver.withValues(alpha: 0.5)),
              ),
              child: Text(
                  motivoSinLista(_t, tablaDe(_t, _todos)) ??
                      'Sin lista de participantes.',
                  style: TextStyle(color: t.text, fontSize: 12, height: 1.4)),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => setState(() => _t = _t.copyWith(
                    participantes: participantesPropuestos(_t, _todos,
                        habitualesDelGrupo: _habitualesDelGrupo(grupos)))),
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: t.primary),
                    foregroundColor: t.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12)),
                child: Text(
                    _t.fuente == FuenteDeRondas.grupo &&
                            _habitualesDelGrupo(grupos).isNotEmpty
                        ? 'Proponer los habituales del grupo'
                        : 'Proponer a quien ha jugado',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ] else ...[
            _nota(
                '${_t.participantes.length} inscrito'
                '${_t.participantes.length == 1 ? '' : 's'}. '
                'Toca para sacar a alguien.',
                t),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final pid in _t.participantes)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _t = _t.copyWith(
                        participantes: _t.participantes
                            .where((x) => x != pid)
                            .toList())),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: t.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: t.primary),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(_nombreDe(pid),
                            style: TextStyle(
                                color: t.text,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(width: 5),
                        Icon(Icons.close, color: t.sub, size: 13),
                      ]),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          // Añadir a alguien del directorio que no ha jugado ninguna: se puede
          // estar inscrito sin haber ido todavía.
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _abrirDirectorio(t),
              style: OutlinedButton.styleFrom(
                  side: BorderSide(color: t.divider),
                  foregroundColor: t.text,
                  padding: const EdgeInsets.symmetric(vertical: 12)),
              icon: Icon(Icons.person_add_alt, size: 17, color: t.sub),
              label: const Text('Añadir del directorio',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ),
          const SizedBox(height: 22),

          // ── 3 · Cómo puntúa cada ronda ─────────────────────────────────
          _titulo(
              _t.formato == FormatoDeTorneo.eliminacion
                  ? '4 · QUIÉN GANA EL PARTIDO'
                  : '4 · CÓMO PUNTÚA CADA RONDA',
              t),
          // En un cuadro no se ofrece "por posición": entre dos personas el
          // puesto lo decide el dinero de la ronda —es lo que ese método
          // calcula— así que sería otro nombre para lo mismo.
          for (final m in metodosOfrecidos(_t.formato))
            _opcion(
              t: t,
              titulo: m.label,
              detalle: m.descripcion,
              // El motivo sale de torneo.dart, no de un if aquí: la pantalla no
              // decide qué es imposible.
              motivo: motivoSinMetodo(m, rondas),
              activa: metodoEfectivo(_t) == m,
              onTap: () => setState(() => _t = _t.copyWith(metodo: m)),
            ),
          // El torneo guardado con "por posición" antes de esta corrección. No se
          // reescribe el documento: se dice qué está pasando de verdad.
          if (_t.formato == FormatoDeTorneo.eliminacion &&
              _t.metodo == MetodoDePuntuacion.posicion) ...[
            const SizedBox(height: 4),
            _nota(
                'Este torneo se guardó con "por posición". En un cuadro el puesto '
                'lo decide el dinero de la ronda, así que se resuelve por dinero '
                '—y aparece marcado arriba—. Tócalo para dejarlo dicho con su '
                'nombre.',
                t),
          ],
          if (aplicaEnFormato(SeccionDelTorneo.puntosPorPuesto, _t.formato) &&
              _t.metodo == MetodoDePuntuacion.posicion) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _puntosCtrl,
              style: TextStyle(color: t.text),
              keyboardType: TextInputType.text,
              onChanged: (v) {
                final nums = v
                    .split(RegExp(r'[^0-9]+'))
                    .where((x) => x.isNotEmpty)
                    .map(int.parse)
                    .toList();
                if (nums.isNotEmpty) {
                  setState(() => _t = _t.copyWith(puntosPorPuesto: nums));
                }
              },
              decoration: InputDecoration(
                labelText: 'Puntos por puesto',
                helperText: 'El puesto que se sale de la lista no puntúa.',
                helperStyle: TextStyle(color: t.sub, fontSize: 11),
                labelStyle: TextStyle(color: t.sub),
                filled: true,
                fillColor: t.surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: t.divider)),
              ),
            ),
            const SizedBox(height: 12),
            // El empate de un PARTIDO no se configura: lo resuelve una persona
            // desde el cuadro, porque la app no puede jugar un hoyo 19.
            _titulo('SI DOS EMPATAN EN UNA RONDA', t),
            for (final e in ReglaDeEmpate.values)
              _opcion(
                t: t,
                titulo: e.label,
                detalle: e.descripcion,
                activa: _t.empate == e,
                onTap: () => setState(() => _t = _t.copyWith(empate: e)),
              ),
          ],
          const SizedBox(height: 22),

          // ── 5 · Cómo se acumula ────────────────────────────────────────
          //
          // Fuera con eliminación: un cuadro no acumula nada, ganas el partido y
          // pasas. Lo guardado NO se borra —volver a liga lo devuelve entero—
          // porque esconder y reescribir no son lo mismo.
          if (aplicaEnFormato(SeccionDelTorneo.acumulacion, _t.formato)) ...[
          _titulo('5 · CÓMO SE ACUMULA', t),
          for (final a in Acumulacion.values)
            _opcion(
              t: t,
              titulo: a.label,
              detalle: a == Acumulacion.sumaSimple
                  ? 'Todas las rondas suman.'
                  : 'Solo las mejores de cada uno. Sumar premia al que más '
                      'juega; esto, al que mejor juega.',
              motivo: motivoSinAcumulacion(a, rondas.length),
              activa: _t.acumulacion == a,
              onTap: () => setState(() => _t = _t.copyWith(acumulacion: a)),
            ),
          if (_t.acumulacion == Acumulacion.mejoresDeN) ...[
            const SizedBox(height: 8),
            _contador(t, 'Cuántas cuentan', _t.mejoresN, 1, 40,
                (v) => setState(() => _t = _t.copyWith(mejoresN: v))),
          ],
          const SizedBox(height: 22),
          ],

          // ── 5 · Cuántas rondas para optar al premio ────────────────────
          //
          // La etiqueta cambió porque el campo cambió de significado: ya no
          // decide quién ENTRA —eso lo hace la lista de participantes— sino
          // quién puede COBRAR. Es lo que quería decir desde el principio, y por
          // eso se sentía insuficiente pareciendo el adecuado.
          // Fuera con eliminación: no hay mínimo que valga, hay una final.
          if (aplicaEnFormato(SeccionDelTorneo.minimoRondas, _t.formato)) ...[
          _titulo('6 · CUÁNTAS RONDAS PARA OPTAR AL PREMIO', t),
          _contador(t, 'Rondas jugadas mínimas', _t.minimoRondas, 0, 40,
              (v) => setState(() => _t = _t.copyWith(minimoRondas: v))),
          const SizedBox(height: 6),
          _nota(
              _t.minimoRondas == 0
                  ? 'Con 0, todos los inscritos optan al premio.'
                  : 'Los inscritos que no lleguen salen aparte con su cuenta: no '
                      'desaparecen, pero no cobran.',
              t),
          if (motivoSinMinimo(_t.minimoRondas, rondas.length) != null) ...[
            const SizedBox(height: 6),
            Text(motivoSinMinimo(_t.minimoRondas, rondas.length)!,
                style: TextStyle(
                    color: t.scoreOver.withValues(alpha: 0.95),
                    fontSize: 11.5,
                    height: 1.35)),
          ],
          const SizedBox(height: 22),
          ],

          // ── 7 · El bote ────────────────────────────────────────────────
          _titulo('7 · EL BOTE', t),
          TextField(
            controller: _entradaCtrl,
            keyboardType: TextInputType.number,
            style: TextStyle(color: t.text),
            onChanged: (v) {
              final n = double.tryParse(v) ?? 0;
              setState(() => _t = _t.copyWith(bote: _t.bote.copyWith(entrada: n)));
            },
            decoration: InputDecoration(
              labelText: 'Entrada por jugador',
              prefixText: '\$ ',
              helperText: '0 = sin bote',
              helperStyle: TextStyle(color: t.sub, fontSize: 11),
              labelStyle: TextStyle(color: t.sub),
              filled: true,
              fillColor: t.surface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: t.divider)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _jornadaCtrl,
            keyboardType: TextInputType.number,
            style: TextStyle(color: t.text),
            onChanged: (v) {
              final n = double.tryParse(v) ?? 0;
              setState(() => _t = _t.copyWith(
                  bote: _t.bote.copyWith(entradaPorJornada: n)));
            },
            decoration: InputDecoration(
              labelText: 'Entrada por ronda jugada',
              prefixText: '\$ ',
              helperText: 'El bote del día, que cobra quien gana esa ronda. '
                  '0 = sin bote por jornada.',
              helperMaxLines: 3,
              helperStyle: TextStyle(color: t.sub, fontSize: 11),
              labelStyle: TextStyle(color: t.sub),
              filled: true,
              fillColor: t.surface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: t.divider)),
            ),
          ),
          if (_t.bote.hayBoteJornada) ...[
            const SizedBox(height: 10),
            _titulo('CÓMO SE REPARTE EL DEL DÍA', t),
            for (final r in RepartoDelBote.values)
              _opcion(
                t: t,
                titulo: r.label,
                detalle: r == RepartoDelBote.podio
                    ? 'Porcentajes: ${_t.bote.porcentajes.join(' · ')}%'
                    : 'Todo para el primero de esa ronda.',
                activa: _t.bote.repartoJornada == r,
                onTap: () => setState(() => _t = _t.copyWith(
                    bote: _t.bote.copyWith(repartoJornada: r))),
              ),
            const SizedBox(height: 6),
            // Los dos botes no se suman en ninguna cifra, y se dice donde se
            // configuran para que nadie espere un total único.
            _nota(
                'El del día se cobra al cerrar cada ronda; el final, al cerrar '
                'el torneo. Son dinero distinto y no se suman.',
                t),
          ],
          if (_t.bote.hayBote) ...[
            const SizedBox(height: 6),
            _nota(
                _inscritos == 0
                    // Sin lista no hay bote, así que tampoco un total que
                    // prometerlo. Es la misma regla que aplica el modelo.
                    ? 'Sin participantes no hay bote: define la lista arriba.'
                    : 'Total del bote ${_t.formato == FormatoDeTorneo.eliminacion ? "del cuadro" : "final"}: '
                        '\$${(_t.bote.entrada * _inscritos).toStringAsFixed(0)}'
                        ' · $_inscritos inscrito${_inscritos == 1 ? '' : 's'}',
                t),
            const SizedBox(height: 12),
            // En un cuadro no hay podio que repartir: hay un campeón. Así que
            // no se ofrece el reparto —no habría nada que elegir— y se dice a
            // quién le toca, que es la única duda razonable.
            if (_t.formato == FormatoDeTorneo.eliminacion)
              _nota(
                  'El bote final se lo lleva quien gane la final. En un cuadro no '
                  'hay podio que repartir, y mientras no haya campeón no cobra '
                  'nadie.',
                  t)
            else ...[
              _titulo('CÓMO SE REPARTE', t),
              for (final r in RepartoDelBote.values)
                _opcion(
                  t: t,
                  titulo: r.label,
                  detalle: r == RepartoDelBote.podio
                      ? 'Porcentajes: ${_t.bote.porcentajes.join(' · ')}%'
                      : 'Todo para el primero de la tabla.',
                  activa: _t.bote.reparto == r,
                  onTap: () => setState(
                      () => _t = _t.copyWith(bote: _t.bote.copyWith(reparto: r))),
                ),
            ],
            // El mínimo de rondas no existe en un cuadro, así que tampoco lo que
            // pasa con la entrada de quien no llega.
            if (aplicaEnFormato(SeccionDelTorneo.minimoRondas, _t.formato) &&
                _t.minimoRondas > 0) ...[
              const SizedBox(height: 10),
              _titulo('QUIEN NO LLEGA AL MÍNIMO (BOTE FINAL)', t),
              for (final s in EntradaSinMinimo.values)
                _opcion(
                  t: t,
                  titulo: s.label,
                  detalle: s.descripcion,
                  activa: _t.bote.sinMinimo == s,
                  onTap: () => setState(() =>
                      _t = _t.copyWith(bote: _t.bote.copyWith(sinMinimo: s))),
                ),
            ],
            const SizedBox(height: 10),
            // La restricción, dicha donde se configura el bote.
            _nota(
                'La app lleva la cuenta del bote; no cobra ni paga nada. El '
                'dinero se mueve entre ustedes.',
                t),
          ],
          const SizedBox(height: 18),

          // ── Cerrar el torneo ───────────────────────────────────────────
          _opcion(
            t: t,
            titulo: _t.cerrado ? 'Torneo cerrado' : 'Torneo abierto',
            detalle: _t.cerrado
                ? 'La tabla ya no cambia y el reparto es el definitivo. Cerrado '
                    'no significa pagado: la app no cobra nada.'
                : 'Sigue contando rondas nuevas. El reparto del bote es '
                    'provisional mientras esté abierto.',
            activa: _t.cerrado,
            onTap: () => setState(() => _t = _t.copyWith(cerrado: !_t.cerrado)),
          ),

          const SizedBox(height: 26),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _guardando ? null : _guardar,
              style: ElevatedButton.styleFrom(
                backgroundColor: t.primary,
                foregroundColor: t.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(_guardando ? 'Guardando…' : 'Guardar torneo',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  /// Las rondas del historial, para elegir a mano cuáles cuentan.
  ///
  /// Se listan de la más reciente a la más antigua, que es como se buscan: un
  /// torneo sobre el histórico se arma con lo de las últimas semanas, no con lo
  /// de hace un año.
  Widget _bloqueRondasAMano(GolfTheme t) {
    final todas = [..._todos]
      ..sort((a, b) => b.playedAt.compareTo(a.playedAt));

    if (todas.isEmpty) {
      return _nota(
          'No hay rondas cerradas en tu historial todavía. Esta fuente sirve '
          'para armar un torneo sobre lo ya jugado; si vas a jugarlo desde '
          'ahora, usa "Marcadas al configurar la ronda".',
          t);
    }

    final elegidas = _t.roundIds.toSet();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: t.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text('CUÁLES CUENTAN', style: GolfType.label(t.sub))),
          // Todas o ninguna: con veinte rondas, tocarlas una a una para armar
          // una temporada entera es trabajo que la pantalla puede evitar.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _t = _t.copyWith(
                roundIds: elegidas.length == todas.length
                    ? const []
                    : todas.map((r) => r.roundId).toList())),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                  elegidas.length == todas.length ? 'NINGUNA' : 'TODAS',
                  style: GolfType.label(t.primary)),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        for (final r in todas)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() {
                final nueva = elegidas.toSet();
                if (!nueva.remove(r.roundId)) nueva.add(r.roundId);
                _t = _t.copyWith(roundIds: nueva.toList());
              }),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  color: elegidas.contains(r.roundId)
                      ? t.primary.withValues(alpha: 0.1)
                      : t.surface,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                      color: elegidas.contains(r.roundId)
                          ? t.primary
                          : t.divider,
                      width: elegidas.contains(r.roundId) ? 1.5 : 1),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${r.playedAt.day}/${r.playedAt.month}/'
                              '${r.playedAt.year} · ${r.roundName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: t.text, fontSize: 13)),
                          // Con qué gente y en qué campo: es lo que distingue
                          // dos sábados con el mismo nombre.
                          Text(
                              '${r.courseName} · '
                              '${r.playerIds.length} jugadores',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: t.sub, fontSize: 11)),
                        ]),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                      elegidas.contains(r.roundId)
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      color: elegidas.contains(r.roundId) ? t.primary : t.sub,
                      size: 18),
                ]),
              ),
            ),
          ),
        const SizedBox(height: 4),
        _nota(
            elegidas.isEmpty
                ? 'Toca las rondas que cuenten. Sin ninguna elegida, el torneo '
                    'sale vacío.'
                : '${elegidas.length} de ${todas.length} rondas elegidas.',
            t),
      ]),
    );
  }

  // ── Piezas ────────────────────────────────────────────────────────────────

  /// La siembra: el orden del cuadro, con el cruce de la primera ronda a la
  /// vista.
  ///
  /// Es lo ÚNICO del cuadro que se guarda. Se enseña el emparejamiento resultante
  /// porque el orden por sí solo no dice nada: "1, 8, 4, 5" es una lista; "el 1
  /// contra el 8" es la información. Y así se ve el efecto de mover a alguien
  /// antes de guardar, en vez de descubrirlo en el cuadro.
  Widget _bloqueSiembra(GolfTheme t) {
    // La siembra efectiva: la guardada, filtrada por quien sigue inscrito, y
    // completada con los inscritos que no estén. Así borrar a alguien de la
    // lista o añadirlo no deja la siembra a medias.
    final orden = <String>[
      ..._t.siembra.where(_t.participantes.contains),
      ..._t.participantes.where((p) => !_t.siembra.contains(p)),
    ];

    if (orden.length < 2) {
      return _nota(
          'Un cuadro se arma con los inscritos. Añade al menos dos en el paso 3.',
          t);
    }

    // onReorderItem y no onReorder: el índice llega ya ajustado, así que no hay
    // que corregirlo a mano —que es donde se cuela el off-by-one al arrastrar
    // hacia abajo—.
    void mover(int desde, int hasta) {
      final copia = [...orden];
      copia.insert(hasta, copia.removeAt(desde));
      setState(() => _t = _t.copyWith(siembra: copia));
    }

    final llave = llaveDe(
        _t.copyWith(siembra: orden, formato: FormatoDeTorneo.eliminacion),
        const []);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: t.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('LA SIEMBRA', style: GolfType.label(t.sub)),
        const SizedBox(height: 4),
        Text(
            'El orden decide los cruces: el primero se cruza con el último, y '
            'los dos primeros solo se ven en la final. Arrastra para cambiarlo.',
            style: TextStyle(color: t.sub, fontSize: 11, height: 1.35)),
        const SizedBox(height: 10),
        // La lista es corta —son los inscritos— así que cabe entera sin
        // scroll propio dentro del formulario.
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: mover,
          children: [
            for (var i = 0; i < orden.length; i++)
              ReorderableDragStartListener(
                key: ValueKey(orden[i]),
                index: i,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: t.divider),
                    ),
                    child: Row(children: [
                      SizedBox(
                          width: 22,
                          child: Text('${i + 1}',
                              style: GolfType.bodyNum(t.sub, size: 12))),
                      Expanded(
                          child: Text(_nombreDe(orden[i]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: t.text, fontSize: 13))),
                      Icon(Icons.drag_handle, color: t.sub, size: 17),
                    ]),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text('CÓMO QUEDA LA PRIMERA RONDA', style: GolfType.label(t.sub)),
        const SizedBox(height: 5),
        for (final e in llave.rondas.isEmpty ? <Enfrentamiento>[] : llave.rondas.first)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
                e.bye
                    ? '${_nombreDe(e.ganador!)} · pasa sin jugar'
                    : '${_nombreDe(e.a!)}  vs  ${_nombreDe(e.b!)}',
                style: TextStyle(
                    color: e.bye ? t.sub : t.text, fontSize: 12, height: 1.35)),
          ),
        if (llave.byes > 0) ...[
          const SizedBox(height: 5),
          Text(
              'El cuadro tiene ${llave.plazas} plazas y hay ${orden.length} '
              'inscritos, así que ${llave.byes} '
              '${llave.byes == 1 ? "pasa" : "pasan"} sin jugar.',
              style: TextStyle(color: t.sub, fontSize: 11, height: 1.35)),
        ],
      ]),
    );
  }

  Widget _titulo(String txt, GolfTheme t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(txt,
            style: TextStyle(
                color: t.sub,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8)),
      );

  Widget _nota(String txt, GolfTheme t) => Text(txt,
      style: TextStyle(
          color: t.sub, fontSize: 11.5, fontStyle: FontStyle.italic));

  /// Una opción. Con [motivo] sale atenuada y explicada, nunca solo apagada.
  Widget _opcion({
    required GolfTheme t,
    required String titulo,
    required String detalle,
    required bool activa,
    required VoidCallback onTap,
    String? motivo,
  }) {
    final bloqueada = motivo != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: bloqueada ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: bloqueada
                ? t.surface
                : activa
                    ? t.primary.withValues(alpha: 0.1)
                    : t.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: activa && !bloqueada ? t.primary : t.divider,
                width: activa && !bloqueada ? 1.5 : 1),
          ),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: TextStyle(
                            color: bloqueada ? t.sub : t.text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700)),
                    Text(motivo ?? detalle,
                        style: TextStyle(
                            color: t.sub,
                            fontSize: 11,
                            height: 1.3,
                            fontStyle: bloqueada
                                ? FontStyle.italic
                                : FontStyle.normal)),
                  ]),
            ),
            const SizedBox(width: 8),
            if (bloqueada)
              Icon(Icons.block, color: t.sub, size: 16)
            else if (activa)
              Icon(Icons.check_circle, color: t.primary, size: 18)
            else
              Icon(Icons.circle_outlined, color: t.sub, size: 18),
          ]),
        ),
      ),
    );
  }

  Widget _contador(GolfTheme t, String etiqueta, int valor, int min, int max,
          ValueChanged<int> onChange) =>
      Row(children: [
        Expanded(
            child: Text(etiqueta,
                style: TextStyle(color: t.text, fontSize: 13))),
        IconButton(
          icon: Icon(Icons.remove_circle_outline, color: t.sub),
          onPressed: valor > min ? () => onChange(valor - 1) : null,
        ),
        SizedBox(
          width: 34,
          child: Text('$valor',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: t.text, fontSize: 16, fontWeight: FontWeight.w800)),
        ),
        IconButton(
          icon: Icon(Icons.add_circle_outline, color: t.primary),
          onPressed: valor < max ? () => onChange(valor + 1) : null,
        ),
      ]);

  Widget _fecha(GolfTheme t, String etiqueta, DateTime? valor,
      ValueChanged<DateTime> onPick, VoidCallback onClear) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: valor ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (d != null) onPick(d);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.divider),
        ),
        child: Row(children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(etiqueta,
                      style: TextStyle(color: t.sub, fontSize: 10)),
                  Text(
                      valor == null
                          ? 'Sin límite'
                          : '${valor.day}/${valor.month}/${valor.year}',
                      style: TextStyle(
                          color: t.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ]),
          ),
          if (valor != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClear,
              child: Icon(Icons.close, color: t.sub, size: 16),
            ),
        ]),
      ),
    );
  }

  List<String> _habitualesDelGrupo(List<BettingGroup> grupos) {
    if (_t.bettingGroupId == null) return const [];
    final g = grupos.where((x) => x.id == _t.bettingGroupId);
    return g.isEmpty ? const [] : g.first.playerIds;
  }

  String _nombreDe(String pid) {
    final dir = context.read<PlayerProvider>().directory;
    final p = dir.where((x) => x.player.id == pid);
    if (p.isNotEmpty) return p.first.player.name.split(' ').first;
    // Cae al nombre que guardó alguna ronda: el del día. Y al id si no hay ni
    // eso, que un id feo dice más que un hueco.
    for (final r in _todos) {
      final n = r.playerNames[pid];
      if (n != null) return n;
    }
    return pid;
  }

  /// Añadir del directorio a alguien que aún no ha jugado ninguna ronda.
  /// La hoja de añadir participantes.
  ///
  /// ── Por qué NO se cierra tras cada añadido ────────────────────────────────
  ///
  /// Se cerraba, y eso convertía inscribir a cuatro personas en ocho toques con
  /// reaperturas de por medio. Con treinta, inviable. La hoja es un SITIO donde
  /// se inscribe gente, no un diálogo de una pregunta: se queda abierta, va
  /// marcando lo añadido y se cierra cuando el usuario ha acabado.
  ///
  /// Lleva su propio estado —StatefulBuilder— porque el setState del editor no
  /// repinta el contenido de un bottom sheet: es otra ruta. Sin eso, lo añadido
  /// no se vería marcado hasta cerrar.
  void _abrirDirectorio(GolfTheme t) {
    final dir = context.read<PlayerProvider>().directory;
    final busca = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: t.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(builder: (ctx2, setHoja) {
          final ya = _t.participantes.toSet();
          final filtro = busca.text.trim().toLowerCase();
          final candidatos = dir
              .where((x) =>
                  filtro.isEmpty ||
                  x.displayName.toLowerCase().contains(filtro))
              .toList();

          void alternar(String pid) {
            // El editor y la hoja se repintan los dos: el editor guarda el
            // estado y la hoja lo enseña.
            setState(() => _t = _t.copyWith(
                participantes: ya.contains(pid)
                    ? _t.participantes.where((x) => x != pid).toList()
                    : [..._t.participantes, pid]));
            setHoja(() {});
          }

          return Padding(
            padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 18,
                bottom: MediaQuery.of(ctx2).viewInsets.bottom + 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(
                  child: Text('Añadir participantes',
                      style: TextStyle(
                          color: t.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 17)),
                ),
                // "Listo" y no una X: la hoja se cierra cuando se ha acabado de
                // inscribir, no tras cada uno.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.pop(ctx),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 4),
                    child: Text('Listo',
                        style: TextStyle(
                            color: t.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              Text(
                  '${_t.participantes.length} inscrito'
                  '${_t.participantes.length == 1 ? '' : 's'}. '
                  'Toca para añadir o sacar; puedes seguir añadiendo.',
                  style: TextStyle(color: t.sub, fontSize: 11.5)),
              const SizedBox(height: 10),
              // Buscador: con treinta en el directorio, bajar rodando es peor
              // que escribir tres letras.
              if (dir.length > 8)
                TextField(
                  controller: busca,
                  onChanged: (_) => setHoja(() {}),
                  style: TextStyle(color: t.text, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre',
                    hintStyle: TextStyle(color: t.sub, fontSize: 13),
                    prefixIcon: Icon(Icons.search, color: t.sub, size: 18),
                    isDense: true,
                    filled: true,
                    fillColor: t.surface,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: t.divider)),
                  ),
                ),
              const SizedBox(height: 10),
              // Importar desde aquí: van al directorio Y quedan inscritos, que
              // es lo que se venía a hacer. Sin salir de la pantalla.
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final ids =
                        await showImportarJugadoresSheet(ctx2, t: t);
                    if (ids == null || ids.isEmpty) return;
                    setState(() => _t = _t.copyWith(participantes: [
                          ..._t.participantes,
                          ...ids.where((x) => !_t.participantes.contains(x)),
                        ]));
                    setHoja(() {});
                  },
                  style: OutlinedButton.styleFrom(
                      side: BorderSide(color: t.divider),
                      foregroundColor: t.text,
                      padding: const EdgeInsets.symmetric(vertical: 10)),
                  icon: Icon(Icons.content_paste_go, size: 16, color: t.sub),
                  label: const Text('Importar una lista (pegar de Excel)',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 12.5)),
                ),
              ),
              const SizedBox(height: 10),
              if (dir.isEmpty)
                Text(
                    'Tu directorio está vacío. Pega una lista con el botón de '
                    'arriba, o añade compañeros desde Ajustes.',
                    style: TextStyle(color: t.sub, fontSize: 12))
              else if (candidatos.isEmpty)
                Text('Nadie del directorio coincide con "${busca.text}".',
                    style: TextStyle(color: t.sub, fontSize: 12))
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final c in candidatos)
                        ListTile(
                          dense: true,
                          // Los ya inscritos SIGUEN en la lista, marcados: si
                          // desaparecieran, la lista salta bajo el dedo y el
                          // siguiente toque cae en otra persona.
                          title: Text(c.displayName,
                              style: TextStyle(
                                  color: ya.contains(c.player.id)
                                      ? t.primary
                                      : t.text,
                                  fontSize: 14,
                                  fontWeight: ya.contains(c.player.id)
                                      ? FontWeight.w700
                                      : FontWeight.w500)),
                          subtitle: Text(
                              'HCP ${c.player.handicapBase.toStringAsFixed(1)}',
                              style: TextStyle(color: t.sub, fontSize: 11)),
                          trailing: Icon(
                              ya.contains(c.player.id)
                                  ? Icons.check_circle
                                  : Icons.add_circle_outline,
                              color: ya.contains(c.player.id)
                                  ? t.primary
                                  : t.sub),
                          onTap: () => alternar(c.player.id),
                        ),
                    ],
                  ),
                ),
            ]),
          );
        }),
      ),
    );
  }

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ponle nombre al torneo')));
      return;
    }
    setState(() => _guardando = true);
    try {
      await context.read<TorneoProvider>().guardar(_t.copyWith(nombre: nombre));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
      }
    }
  }

  Future<void> _borrar() async {
    await context.read<TorneoProvider>().borrar(_t.id);
    if (mounted) Navigator.pop(context);
  }
}
