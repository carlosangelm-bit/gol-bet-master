// ─────────────────────────────────────────────────────────────────────────────
// LA TABLA DE INSCRITOS — buscar, ordenar y editar sin salir de ella
//
// Es lo que más se usa del portal y lo que hoy peor funciona: la hoja del móvil
// con 150 personas es inviable, y su versión pequeña ya dio guerra montando la
// demo.
//
// El cálculo —buscar, ordenar, quitar, añadir— NO está aquí: está en
// models/inscritos.dart, donde se puede probar sin montar pantalla ni sesión.
// Aquí solo se pinta.
//
// ── QUITAR EN BLOQUE, y por qué de uno en uno no era una molestia ──────────
//
// «153 inscritos y 22 salidas: hay que bajar a 88. Sesenta y cinco fuera, y solo
// se puede de una en una.»
//
// Y no era solo lento. Cada quitado guardaba el torneo, la lista se recomponía,
// y seis clics seguidos en la misma posición contaban UNO: los otros cinco
// caían mientras la fila se recolocaba. Encima el aviso de «Deshacer» aparecía
// justo encima del botón de quitar de la fila siguiente, así que el clic
// siguiente iba al aviso.
//
// Tres síntomas de la misma causa: se estaba repitiendo una acción sobre una
// lista que se movía debajo. La selección múltiple no los arregla uno a uno —
// los quita de raíz:
//
//   · nada se mueve hasta confirmar, así que marcar veinte es marcar veinte
//   · un solo aviso al final, cuando ya no se está repitiendo nada
//   · una escritura en vez de sesenta y cinco
//
// Y con el buscador, «marcar los que se ven» convierte «quitar a los que no
// juegan» en dos gestos: buscar y marcar.
//
// ── El handicap que se edita es el GLOBAL ───────────────────────────────────
//
// El torneo no guarda handicaps: guarda una ventaja, y cuando toca handicap usa
// el `handicapBase` de la ficha del jugador —la misma que usan las demás
// rondas—. Así que editarlo aquí lo cambia en todas partes.
//
// No se esconde y no se bloquea: se dice en la propia columna. Bloquearlo
// dejaría al organizador sin poder corregir un handicap el día del torneo, que
// es justo cuando lo necesita; esconderlo lo convertiría en una sorpresa.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ancho.dart';
import '../../core/app_theme.dart';
import '../../core/golf_icons.dart';
import '../../models/inscritos.dart';
import '../../models/models.dart';
import '../../models/torneo.dart';
import '../../services/player_service.dart';
import '../../providers/player_provider.dart';
import '../../providers/torneo_provider.dart';
import 'organizador_screen.dart';

class InscritosTabla extends StatefulWidget {
  final Torneo torneo;
  final Ancho ancho;
  final GolfTheme t;

  /// id → nombre de quien ya jugó, sacado de la tabla del torneo.
  ///
  /// ── Por qué llega de fuera y no se calcula aquí ──────────────────────────
  ///
  /// El portal YA construye la tabla completa —y con ella el nombre de cada
  /// inscrito, incluidos los que solo existen dentro de una ronda y los de
  /// otras cuentas, cuyos ids hay que traducir—. Calcularlo otra vez aquí daría
  /// dos resoluciones del mismo nombre con dos precedencias, que es la clase de
  /// diferencia que aparece meses después en una sola fila.
  ///
  /// Sin esto, esta pantalla era la única del portal que NO leía esos nombres:
  /// la pared los enseñaba y la lista de inscritos ponía «Ficha no encontrada».
  final Map<String, String> nombresDeRondas;

  const InscritosTabla({
    super.key,
    required this.torneo,
    required this.ancho,
    required this.t,
    this.nombresDeRondas = const {},
  });

  @override
  State<InscritosTabla> createState() => _InscritosTablaState();
}

class _InscritosTablaState extends State<InscritosTabla> {
  final _busca = TextEditingController();
  OrdenDeInscritos _orden = OrdenDeInscritos.inscripcion;
  bool _descendente = false;

  /// Las fichas del catálogo global de los inscritos que esta cuenta no tiene
  /// vinculados.
  ///
  /// ── El fallo que esto arregla ────────────────────────────────────────────
  ///
  /// El portal abría Copa CGM 2026 y enseñaba «Ficha no encontrada» en las 47
  /// filas. Y no era cierto: la ficha existía, lo que faltaba era el VÍNCULO.
  /// El directorio de una cuenta son sus `playerLinks`, y un torneo cuyos
  /// inscritos se juntaron desde rondas tiene ids de gente que esta cuenta
  /// nunca vinculó.
  ///
  /// Se resuelven al abrir, por id, que es exactamente lo que la regla de
  /// `players` permite: `allow get`, sin `list`.
  Map<String, ({Player ficha, bool mia})> _globales = const {};
  bool _resolviendo = false;

  /// Los marcados para quitar. Vacío = no hay modo selección.
  ///
  /// No hay una bandera de "modo": el modo ES tener algo marcado. Una bandera
  /// aparte daría dos estados que hay que mantener de acuerdo, y el que se
  /// quedara atrás sería una pantalla en modo selección sin nada seleccionado.
  Set<String> _marcados = {};

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  /// Pide las fichas que faltan. Una vez, y solo las que faltan.
  ///
  /// Se llama desde `build` porque el directorio llega por stream: cuáles
  /// faltan no se sabe hasta que ha llegado, y puede llegar después de montar.
  /// El `_resolviendo` impide que un rebuild dispare la misma tanda otra vez.
  Future<void> _resolverQueFaltan(Set<String> faltan) async {
    if (_resolviendo || faltan.isEmpty) return;
    _resolviendo = true;
    final nuevas = await PlayerService.fichasGlobales(faltan);
    if (!mounted) {
      _resolviendo = false;
      return;
    }
    setState(() {
      _globales = {..._globales, ...nuevas};
      _resolviendo = false;
    });
  }

  void _ordenarPor(OrdenDeInscritos o) => setState(() {
        // Volver a pulsar la misma columna invierte, que es lo que espera
        // cualquiera que venga de una hoja de cálculo.
        if (_orden == o) {
          _descendente = !_descendente;
        } else {
          _orden = o;
          _descendente = false;
        }
      });

  Future<void> _anadir() async {
    final nuevo = await anadirInscritos(context, widget.torneo);
    if (nuevo == null || !mounted) return;
    await context.read<TorneoProvider>().guardar(nuevo);
  }

  /// Quita todos los marcados, de una vez.
  ///
  /// Una escritura, un aviso, y ninguna recomposición por el camino: la lista
  /// se recompone UNA vez, al final, cuando ya no se está repitiendo nada.
  Future<void> _quitarMarcados() async {
    final prov = context.read<TorneoProvider>();
    final ids = {..._marcados};
    final nuevo = sinInscritos(widget.torneo, ids);
    if (identical(nuevo, widget.torneo)) return;
    final cuantos = widget.torneo.participantes.length -
        nuevo.participantes.length;
    final messenger = ScaffoldMessenger.of(context);

    // ── Si el guardado falla, las MARCAS se quedan ──────────────────────────
    //
    // Marcar veinte cuesta veinte toques. Perderlos porque la red falló, y sin
    // decir nada, obligaría a repetirlos — que es exactamente el trabajo que
    // esto viene a quitar. Se limpian solo cuando el guardado salió bien.
    try {
      await prov.guardar(nuevo);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          content: Text('No se pudo quitar a $cuantos. Siguen marcados: '
              'vuelve a intentarlo.')));
      return;
    }
    if (!mounted) return;
    setState(() => _marcados = {});
    messenger.showSnackBar(SnackBar(
      content: Text('$cuantos ya no está${cuantos == 1 ? '' : 'n'} inscrito'
          '${cuantos == 1 ? '' : 's'}'),
      action: SnackBarAction(
        label: 'Deshacer',
        // Deshacer devuelve los ids, pero al FINAL de la lista: el orden de
        // inscripción es un hecho de cuándo entró cada uno, y fingir que nunca
        // salieron sería inventarse ese hecho.
        onPressed: () => prov.guardar(conInscritos(nuevo, ids.toList())),
      ),
    ));
  }

  /// Marca o desmarca uno. Es lo único que hace un toque en la casilla: nada
  /// se guarda y nada se mueve.
  void _alternar(String playerId) => setState(() {
        final nuevos = {..._marcados};
        if (!nuevos.remove(playerId)) nuevos.add(playerId);
        _marcados = nuevos;
      });

  /// Marca los que se ven AHORA, con el filtro puesto.
  ///
  /// Es lo que convierte «quitar a los que no juegan» en dos gestos. Y marca
  /// los VISIBLES, no todos: con un buscador puesto, marcar los 153 sería lo
  /// contrario de lo que pide quien acaba de filtrar.
  void _marcarVisibles(List<FilaDeInscrito> filas) => setState(() {
        _marcados = {..._marcados, ...filas.map((f) => f.playerId)};
      });

  Future<void> _editarHandicap(FilaDeInscrito f) async {
    final prov = context.read<PlayerProvider>();
    final pw = prov.directory
        .where((x) => x.player.id == f.playerId)
        .cast<dynamic>()
        .firstWhere((_) => true, orElse: () => null);
    if (pw == null) return;
    final valor = await showDialog<double>(
      context: context,
      builder: (_) => _DialogoHandicap(nombre: f.nombre, actual: f.handicap),
    );
    if (valor == null || !mounted) return;
    final p = pw.player;
    p.handicapBase = valor;
    await prov.updatePlayer(p);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final ancho = widget.ancho;
    final dir = context.watch<PlayerProvider>().directory;
    // Las que el directorio no resuelve y todavía no se han pedido. Se piden
    // después del fotograma: hacerlo dentro del build sería un setState en
    // pleno pintado.
    final enDirectorio = {for (final pw in dir) pw.player.id};
    final faltan = widget.torneo.participantes
        .where((p) =>
            !enDirectorio.contains(p) &&
            !_globales.containsKey(p) &&
            // Lo que una ronda ya resolvió no se le pide al catálogo: en Copa
            // CGM 2026 son 28 lecturas que no hacen falta, y ninguna habría
            // encontrado nada porque esos ids nunca pasaron por `players`.
            !widget.nombresDeRondas.containsKey(p))
        .toSet();
    if (faltan.isNotEmpty && !_resolviendo) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _resolverQueFaltan(faltan));
    }

    final filas = filasDeInscritos(
      widget.torneo,
      dir,
      busca: _busca.text,
      orden: _orden,
      descendente: _descendente,
      globales: _globales,
      nombresDeRondas: widget.nombresDeRondas,
    );
    final total = widget.torneo.participantes.length;

    return Column(children: [
      Padding(
        padding: EdgeInsets.fromLTRB(ancho.esTabla ? 24 : 14, 14, ancho.esTabla ? 24 : 14, 10),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _busca,
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: t.text, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Buscar entre $total inscrito${total == 1 ? '' : 's'}',
                hintStyle: TextStyle(color: t.sub, fontSize: 13),
                prefixIcon: Icon(Icons.search, color: t.sub, size: 18),
                suffixIcon: _busca.text.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(Icons.close, size: 17, color: t.sub),
                        onPressed: () => setState(_busca.clear),
                      ),
                isDense: true,
                filled: true,
                fillColor: t.surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: t.divider)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: t.divider)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // «Marcar los que se ven». Solo cuando hay algo que marcar y no está
          // ya todo marcado: un botón que no puede hacer nada es peor que no
          // tenerlo.
          if (filas.isNotEmpty &&
              !filas.every((f) => _marcados.contains(f.playerId)))
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: OutlinedButton(
                onPressed: () => _marcarVisibles(filas),
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: t.divider),
                    foregroundColor: t.text,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 15)),
                child: Text(
                    _busca.text.isEmpty
                        ? 'Marcar ${filas.length}'
                        : 'Marcar los ${filas.length}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          if (ancho.esTabla)
            ElevatedButton.icon(
              onPressed: _anadir,
              style: ElevatedButton.styleFrom(
                  backgroundColor: t.primary,
                  foregroundColor: t.onPrimary,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 15)),
              icon: const Icon(Icons.person_add_alt, size: 17),
              label: const Text('Añadir',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            )
          else
            IconButton.filled(
              onPressed: _anadir,
              style: IconButton.styleFrom(
                  backgroundColor: t.primary, foregroundColor: t.onPrimary),
              icon: const Icon(Icons.person_add_alt, size: 19),
            ),
        ]),
      ),
      // ── LA BARRA DE SELECCIÓN ──────────────────────────────────────────
      //
      // Aparece solo con algo marcado, y va ARRIBA: el aviso de deshacer sale
      // abajo, y ponerla ahí repetiría el problema que esto viene a arreglar.
      if (_marcados.isNotEmpty)
        _BarraDeSeleccion(
          t: t,
          ancho: ancho,
          marcados: _marcados.length,
          onQuitar: _quitarMarcados,
          onLimpiar: () => setState(() => _marcados = {}),
        ),
      if (ancho.esTabla)
        _Cabeceras(
          ancho: ancho,
          t: t,
          orden: _orden,
          descendente: _descendente,
          onOrdenar: _ordenarPor,
        )
      else
        _OrdenCompacto(t: t, orden: _orden, onOrdenar: _ordenarPor),
      Expanded(
        child: filas.isEmpty
            ? _Vacio(t: t, buscando: _busca.text.isNotEmpty, total: total)
            : ListView.builder(
                padding: EdgeInsets.fromLTRB(
                    ancho.esTabla ? 24 : 14, 4, ancho.esTabla ? 24 : 14, 24),
                itemCount: filas.length,
                itemBuilder: (_, i) => _Fila(
                  fila: filas[i],
                  ancho: ancho,
                  t: t,
                  marcado: _marcados.contains(filas[i].playerId),
                  onHandicap: () => _editarHandicap(filas[i]),
                  // La X de la fila MARCA en vez de quitar. Quitar de una en
                  // una era la acción que no escalaba; marcar sí, porque la
                  // lista no se mueve.
                  onQuitar: () => _alternar(filas[i].playerId),
                ),
              ),
      ),
    ]);
  }
}

class _Cabeceras extends StatelessWidget {
  final Ancho ancho;
  final GolfTheme t;
  final OrdenDeInscritos orden;
  final bool descendente;
  final void Function(OrdenDeInscritos) onOrdenar;
  const _Cabeceras({
    required this.ancho,
    required this.t,
    required this.orden,
    required this.descendente,
    required this.onOrdenar,
  });

  Widget _col(String texto, OrdenDeInscritos? o, {int flex = 1, double? w}) {
    final activa = o != null && o == orden;
    final hijo = InkWell(
      onTap: o == null ? null : () => onOrdenar(o),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(children: [
          Flexible(
            // ETIQUETA, con el token. Antes era 11.5 w800 con tracking 0.4:
            // casi el mismo peso visual que el "18" de debajo, así que el ojo
            // tenía que leer para saber cuál era cuál.
            child: Text(texto,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GolfType.label(activa ? t.primary : t.sub)),
          ),
          if (activa)
            Icon(descendente ? Icons.arrow_downward : Icons.arrow_upward,
                size: 12, color: t.primary),
        ]),
      ),
    );
    return w != null ? SizedBox(width: w, child: hijo) : Expanded(flex: flex, child: hijo);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          decoration:
              BoxDecoration(border: Border(bottom: BorderSide(color: t.divider))),
          child: Row(children: [
            if (ancho.columnasCompletas) _col('#', OrdenDeInscritos.inscripcion, w: 54),
            _col('NOMBRE', OrdenDeInscritos.nombre, flex: 3),
            _col('HANDICAP', OrdenDeInscritos.handicap, w: 120),
            if (ancho.columnasCompletas) _col('', null, w: 48),
          ]),
        ),
      );
}

/// La barra que aparece con algo marcado.
///
/// ── Va ARRIBA, y no es indiferente ─────────────────────────────────────────
///
/// El aviso de «Deshacer» sale abajo, y ahí es donde tapaba el botón de quitar
/// de la fila siguiente. Poner la acción en bloque también abajo repetiría el
/// problema que esto viene a arreglar: dos cosas peleándose por el mismo sitio.
class _BarraDeSeleccion extends StatelessWidget {
  final GolfTheme t;
  final Ancho ancho;
  final int marcados;
  final VoidCallback onQuitar;
  final VoidCallback onLimpiar;
  const _BarraDeSeleccion({
    required this.t,
    required this.ancho,
    required this.marcados,
    required this.onQuitar,
    required this.onLimpiar,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: EdgeInsets.fromLTRB(
            ancho.esTabla ? 24 : 14, 0, ancho.esTabla ? 24 : 14, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: t.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.primary.withValues(alpha: 0.45)),
        ),
        child: Row(children: [
          Expanded(
            child: Text(
                '$marcados marcado${marcados == 1 ? '' : 's'} para quitar',
                style: GolfType.value(t.text)),
          ),
          TextButton(
            onPressed: onLimpiar,
            style: TextButton.styleFrom(foregroundColor: t.sub),
            child: const Text('Cancelar'),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: onQuitar,
            style: FilledButton.styleFrom(
                backgroundColor: t.loss,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
            child: Text('Quitar $marcados',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
      );
}

/// En estrecho no hay cabeceras que pulsar, así que el orden va en chips.
class _OrdenCompacto extends StatelessWidget {
  final GolfTheme t;
  final OrdenDeInscritos orden;
  final void Function(OrdenDeInscritos) onOrdenar;
  const _OrdenCompacto(
      {required this.t, required this.orden, required this.onOrdenar});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          children: [
            for (final o in OrdenDeInscritos.values)
              Padding(
                padding: const EdgeInsets.only(right: 7),
                child: ChoiceChip(
                  label:
                      Text(o.labelCorto, style: const TextStyle(fontSize: 12)),
                  selected: orden == o,
                  onSelected: (_) => onOrdenar(o),
                ),
              ),
          ],
        ),
      );
}

class _Fila extends StatelessWidget {
  final FilaDeInscrito fila;
  final Ancho ancho;
  final GolfTheme t;
  final VoidCallback onHandicap;

  /// Marca o desmarca. Ya no quita: quitar es una acción de la barra de arriba,
  /// y por eso encadenar veinte funciona.
  final VoidCallback onQuitar;

  final bool marcado;

  const _Fila({
    required this.fila,
    required this.ancho,
    required this.t,
    required this.onHandicap,
    required this.onQuitar,
    this.marcado = false,
  });

  String get _hcp => fila.handicap == fila.handicap.roundToDouble()
      ? '${fila.handicap.round()}'
      : fila.handicap.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final nombre = Row(children: [
      Flexible(
        child: Text(fila.nombre,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: fila.origen == OrigenDeLaFicha.sinFicha
                    ? t.loss
                    : t.text,
                fontSize: 14.5,
                fontStyle: fila.origen == OrigenDeLaFicha.sinFicha
                    ? FontStyle.italic
                    : null,
                fontWeight: FontWeight.w600)),
      ),
      // ── EL MOTIVO, no «no encontrada» ──────────────────────────────────
      //
        // El aviso decía «su ficha ya no está en tu directorio» para todos, y son
      // casos distintos: uno se añade, otro se ve y no se toca, otro pide crear
      // ficha y el último se quita. Con 47 filas iguales, saber el motivo es lo
      // único que permite arreglarlo.
      //
      // Y la sonda contra producción dice cuál pesa: de los 47 de Copa CGM
      // 2026, 10 del directorio, 0 del catálogo, 28 de rondas y 9 huérfanos.
      if (fila.origen != OrigenDeLaFicha.directorio) ...[
        const SizedBox(width: 6),
        Tooltip(
          message: switch (fila.origen) {
            OrigenDeLaFicha.directorio => '',
            OrigenDeLaFicha.global => fila.editable
                ? 'Su ficha existe pero no está en tu directorio: el nombre y '
                    'el handicap salen del catálogo. Añádelo a tu directorio '
                    'para tenerlo a mano al crear rondas.'
                : 'Su ficha la creó otra cuenta. Puedes verlo e inscribirlo, '
                    'pero su handicap se edita desde donde se creó.',
            // El mayoritario. Dice de dónde sale el nombre, por qué falta el
            // handicap, y qué hacer para que deje de faltar.
            OrigenDeLaFicha.rondas =>
              'Su nombre sale de una ronda que ya jugó: nunca se le creó ficha, '
                  'y por eso no tiene handicap. Créale una ficha en tu '
                  'directorio para poder fijarlo.',
            OrigenDeLaFicha.sinFicha =>
              'Está inscrito y no aparece en ningún sitio: ni ficha, ni una '
                  'ronda jugada. Suele ser una ficha borrada: quítalo del '
                  'torneo y vuelve a inscribirlo.',
          },
          child: Icon(
              switch (fila.origen) {
                // La nube: está en el catálogo, fuera de tu directorio.
                OrigenDeLaFicha.global => Icons.cloud_outlined,
                // Jugó. No es un aviso: es un dato incompleto, y el icono del
                // golpe dice de dónde viene el nombre.
                OrigenDeLaFicha.rondas => GolfIcons.golpe,
                _ => GolfIcons.aviso,
              },
              size: 15,
              color: fila.origen == OrigenDeLaFicha.sinFicha ? t.loss : t.sub),
        ),
      ],
    ]);

    final handicap = InkWell(
      onTap: fila.editable ? onHandicap : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          // VALOR. El par label/value es lo que hace el trabajo: ninguno de los
          // dos arregla nada por su cuenta.
          // `—` en cuanto NO haya ficha. Antes solo cuando faltaba del todo, y
          // los 28 que solo existen en una ronda enseñaban un 0 que se lee como
          // el handicap de un scratch.
          Text(fila.handicapConocido ? _hcp : '—',
              style:
                  GolfType.value(fila.handicapConocido ? t.text : t.sub)),
          // El lápiz solo si de verdad se puede: ofrecer un campo que va a
          // fallar al guardar es peor que no ofrecerlo.
          if (fila.editable) ...[
            const SizedBox(width: 6),
            Icon(Icons.edit, size: 13, color: t.sub),
          ],
        ]),
      ),
    );

    if (!ancho.esTabla) {
      return Card(
        margin: const EdgeInsets.only(bottom: 7),
        // La fila marcada se ve DE UN VISTAZO: con veinte marcadas, un icono de
        // 19 px no dice cuántas van.
        color: marcado ? t.primary.withValues(alpha: 0.10) : t.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
            side: BorderSide(color: t.divider)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 8, 6, 8),
          child: Row(children: [
            Expanded(child: nombre),
            handicap,
            IconButton(
              onPressed: onQuitar,
              icon: Icon(
                  marcado
                      ? Icons.check_box_outlined
                      : Icons.check_box_outline_blank,
                  size: 19,
                  color: marcado ? t.primary : t.sub),
              tooltip: marcado ? 'No quitarlo' : 'Marcar para quitar',
            ),
          ]),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: marcado ? t.primary.withValues(alpha: 0.10) : null,
        border: Border(bottom: BorderSide(color: t.divider)),
      ),
      child: Row(children: [
        if (ancho.columnasCompletas)
          SizedBox(
            width: 54,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text('${fila.inscrito}',
                  style: GolfType.bodyNum(t.sub, size: 12.5)),
            ),
          ),
        Expanded(
          flex: 3,
          child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
              child: nombre),
        ),
        SizedBox(width: 120, child: handicap),
        if (ancho.columnasCompletas)
          SizedBox(
            width: 48,
            child: IconButton(
              onPressed: onQuitar,
              icon: Icon(
                  marcado
                      ? Icons.check_box_outlined
                      : Icons.check_box_outline_blank,
                  size: 19,
                  color: marcado ? t.primary : t.sub),
              tooltip: marcado ? 'No quitarlo' : 'Marcar para quitar',
            ),
          ),
      ]),
    );
  }
}

class _Vacio extends StatelessWidget {
  final GolfTheme t;
  final bool buscando;
  final int total;
  const _Vacio({required this.t, required this.buscando, required this.total});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(buscando ? Icons.search_off : Icons.groups_outlined,
                size: 32, color: t.sub),
            const SizedBox(height: 12),
            Text(
                buscando
                    ? 'Nadie con ese nombre entre los $total inscritos'
                    : 'Todavía no hay nadie inscrito',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: t.text, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
                buscando
                    ? 'Prueba con menos letras.'
                    : 'Añádelos uno a uno, o pega la lista entera desde un Excel.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.sub, fontSize: 12.5, height: 1.4)),
          ]),
        ),
      );
}

class _DialogoHandicap extends StatefulWidget {
  final String nombre;
  final double actual;
  const _DialogoHandicap({required this.nombre, required this.actual});

  @override
  State<_DialogoHandicap> createState() => _DialogoHandicapState();
}

class _DialogoHandicapState extends State<_DialogoHandicap> {
  late final _c = TextEditingController(
      text: widget.actual == widget.actual.roundToDouble()
          ? '${widget.actual.round()}'
          : widget.actual.toStringAsFixed(1));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double? get _valor => double.tryParse(_c.text.trim().replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) {
    final t = context.gt;
    return AlertDialog(
      backgroundColor: t.bg,
      title: Text('Handicap de ${widget.nombre}',
          style: TextStyle(color: t.text, fontSize: 17)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          style: TextStyle(color: t.text, fontSize: 16),
          decoration: InputDecoration(
            filled: true,
            fillColor: t.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 12),
        // El aviso que evita la sorpresa. Ver la cabecera de este archivo.
        Text(
            'Este es el handicap de su ficha, el mismo que usan las demás '
            'rondas. Cambiarlo aquí lo cambia en todas partes: el torneo no '
            'guarda un handicap propio.',
            style: TextStyle(color: t.sub, fontSize: 11.5, height: 1.4)),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        TextButton(
          onPressed:
              _valor == null ? null : () => Navigator.pop(context, _valor),
          child: const Text('Guardar',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}
