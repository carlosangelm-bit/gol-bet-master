// ─────────────────────────────────────────────────────────────────────────────
// QUICK START — un punto de partida guardado es un ATAJO, no un formulario
//
// El reporte: "cuando quiero usar el grupo de apuesta me obliga a configurar
// todo nuevamente". Y era cierto aunque la precarga funcionara: el wizard se
// abría en "paso 1 de 8" sin un check, y había que pulsar Siguiente seis veces
// confirmando lo que el grupo ya respondía.
//
// Prellenar ahorra escribir pero se recorre igual. Un atajo lleva al final y
// solo para donde falta algo.
//
// Esta pantalla pregunta SOLO lo que el punto de partida no sabe —hoy campo y
// ventaja— y lanza. Las preguntas se CALCULAN con preguntasPendientes, así que
// el día que un punto de partida guarde el campo, esta pantalla se acorta sola.
//
// No reimplementa nada: el selector de campo es CoursePickerSheet, el mismo del
// wizard, y el lanzamiento pasa por SetupScreen con lanzarAlEntrar, o sea por
// _createAndStartRound. Un segundo camino de lanzamiento habría sido la tercera
// vez en la sesión que dos rutas al mismo sitio se comportan distinto.
//
// ── Y AHORA UN TORNEO TAMBIÉN ES UN PUNTO DE PARTIDA ────────────────────────
//
// Es la corrección de dirección: el torneo no es una vista sobre rondas que ya
// existen, es el evento del que salen. Y lo que responde por adelantado —el
// padrón, la ventaja, el campo, y que la ronda CUENTA— es exactamente la forma
// de un punto de partida. Así que entra por aquí en vez de por un asistente en
// blanco de diez pasos donde todas esas respuestas ya se sabían.
//
// Los dos puntos de partida caben en la misma pantalla porque preguntan lo
// mismo: qué falta. Un torneo con plantilla no deja NADA sin responder salvo el
// campo, así que lanza; uno sin plantilla —el caso del seguidor, que no puede
// leer las apuestas del organizador— deja abierto qué se juega y por eso lleva
// al asistente con todo lo demás puesto.
// ─────────────────────────────────────────────────────────────────────────────
import '../../core/golf_icons.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../models/models.dart';
import '../../models/punto_de_torneo.dart';
import '../../models/torneo.dart';
import '../../providers/round_provider.dart';
import '../../providers/user_profile_provider.dart';
import '../../providers/player_provider.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/course_picker_sheet.dart';
import '../../widgets/player_edit_sheet.dart';
import 'setup_flow.dart';
import 'setup_screen.dart';

class QuickStartScreen extends StatefulWidget {
  /// El grupo de apuesta del que se parte. Null si se parte de un torneo sin
  /// plantilla: entonces la ronda no hereda apuestas y se eligen en el asistente.
  final BettingGroup? grupo;

  /// El torneo del que sale esta ronda, si sale de uno.
  final PuntoDeTorneo? torneo;

  const QuickStartScreen({super.key, this.grupo, this.torneo})
      : assert(grupo != null || torneo != null,
            'Sin grupo ni torneo no hay punto de partida del que arrancar');

  @override
  State<QuickStartScreen> createState() => _QuickStartScreenState();
}

class _QuickStartScreenState extends State<QuickStartScreen> {
  late CourseInfo? _campo = widget.torneo?.campo;

  /// El punto de torneo con las fichas ya resueltas contra MI directorio.
  ///
  /// Se recalcula en cada build porque el directorio llega por stream y porque
  /// materializar a alguien lo cambia. Resolver por nombre normalizado es lo que
  /// evita que la segunda ronda del torneo cree a Luis Herrera otra vez.
  PuntoDeTorneo? get _tor {
    final t = widget.torneo;
    if (t == null) return null;
    final dir = context.read<PlayerProvider>().directory;
    final resuelto = t.conFichas({
      for (final pw in dir) pw.displayName: pw.player.id,
      // Los creados aquí mismo todavía no están en el directorio del provider.
      for (final e in _creados.entries) e.value.name: e.key,
    });
    // Y MI reclamación manda sobre el nombre. "Soy Carlos Angel" no dice "tengo
    // una ficha que se llama así": dice que ese de la lista soy yo, y mi ficha
    // puede llamarse "CAV". Sin esto me quedaba fuera de mi propio torneo, con la
    // consecuencia que no es cosmética: una ronda del torneo en la que no estoy.
    final mia = context.read<UserProfileProvider>().profile?.myPlayerId;
    return mia == null ? resuelto : resuelto.conMiFicha(mia);
  }

  /// Nombre de cada ficha, para resolver cómo llamo yo a los del padrón.
  Map<String, String> get _nombreDeFicha => {
        for (final pw in context.read<PlayerProvider>().directory)
          pw.player.id: pw.displayName,
        for (final e in _creados.entries) e.key: e.value.name,
      };

  /// Quiénes juegan HOY. Con grupo, sus habituales marcados.
  ///
  /// Es una COPIA: quitar a alguien de aquí no lo saca del grupo. Reutilizar la
  /// lista del grupo haría que jugar sin uno lo borrara para siempre.
  ///
  /// Desde un torneo sin plantilla arranca con QUIEN SOY YO y nadie más: marcar
  /// a los veinte del padrón sería peor que no marcar a ninguno, porque hay que
  /// desmarcar diecisiete para jugar un cuarteto. Los demás se añaden del padrón.
  /// Los DEMÁS que juegan hoy. Yo no estoy aquí, y es el arreglo.
  ///
  /// ── Yo no soy una casilla ─────────────────────────────────────────────────
  ///
  /// Un checkbox es una pregunta con dos respuestas útiles, y aquí la segunda no
  /// lo es: desmarcarme deja una ronda del torneo en la que no estoy, que es
  /// justo "contaría para el torneo sin contar para nadie". No se ofrece.
  ///
  /// Y sacarme del estado arregla además un fallo de tiempos que no se veía: la
  /// lista se sembraba UNA vez y quién soy yo se resuelve con el directorio y el
  /// perfil, que llegan por stream. Si la siembra pasaba antes de que llegaran,
  /// yo no entraba nunca. Derivado no puede pasar: se recalcula en cada build.
  late final List<String> _hoy =
      List.of(widget.grupo?.playerIds ?? const <String>[]);

  /// Quién juega la ronda: yo primero, y los demás.
  ///
  /// ── De dónde sale que alguien esté aquí ───────────────────────────────────
  ///
  /// Quién juega hoy no lo decide mi lista de compañeros. En una liga puedo jugar
  /// con cualquiera de los inscritos, con gente de fuera o con nadie del torneo.
  /// Así que solo entran de salida:
  ///
  ///   · YO, si reclamé un jugador del padrón. Soy el único que seguro juega.
  ///   · Los habituales de la PLANTILLA, si el torneo fija una — y ahí sí lo dice
  ///     el torneo. Es el caso del shotgun: el organizador armó el grupo.
  ///
  /// Nadie más, y cada fila lleva escrito de dónde viene.
  List<String> get _jugando {
    final mio = _tor?.miFicha;
    return [
      if (mio != null) mio,
      for (final id in _hoy)
        if (id != mio) id,
    ];
  }

  /// 'handicap' · 'sliding' · 'ninguna'. Sin elegir hasta que se toque.
  ///
  /// Si el torneo la fija, entra ya puesta: es el único parámetro de juego que un
  /// torneo tiene que fijar sí o sí, porque dos jornadas con ventajas distintas
  /// no son comparables y la tabla las suma como si lo fueran.
  late String? _ventaja = widget.torneo?.ventaja?.paraSetup;

  /// Lo que este punto de partida NO sabe. Calculado, no fijado.
  List<SetupStep> get _pendientes => preguntasPendientes(
        // Un grupo de apuesta no guarda campo; un torneo PUEDE fijarlo. En cuanto
        // lo trae, la pregunta desaparece sola — es para lo que se calculaba.
        traeCampo: widget.torneo?.campo != null,
        traeVentaja: widget.torneo?.ventaja != null,
      );

  bool get _listo =>
      _jugando.length >= 2 &&
      (!_pendientes.contains(SetupStep.campo) || _campo != null) &&
      (!_pendientes.contains(SetupStep.ventaja) || _ventaja != null);

  @override
  Widget build(BuildContext context) {
    final t = context.watch<RoundProvider>().theme;
    GolfThemeExt.setCurrent(t);
    final bg = widget.grupo;
    final tor = _tor;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        iconTheme: IconThemeData(color: t.text),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tor == null ? bg!.name : '${tor.emoji} ${tor.nombre}',
              style: TextStyle(
                  color: t.text, fontWeight: FontWeight.w800, fontSize: 18)),
          Text(faltaPorDecidir(_pendientes),
              style: TextStyle(color: t.sub, fontSize: 12)),
        ]),
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        // ── Lo que el punto de partida YA trae ────────────────────────────
        //
        // Va primero y como resumen, no como pasos: la pregunta que responde es
        // "¿es esto lo que quiero jugar?", no "¿confirmo cada campo?".
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.divider),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tor == null ? 'YA CONFIGURADO' : 'LO QUE FIJA EL TORNEO',
                style: GolfType.label(t.primary)),
            const SizedBox(height: 8),
            // Los jugadores NO faltan: vienen del grupo. Lo que se ofrece es
            // AJUSTAR una lista que ya está, así que van aquí y no en "falta
            // decidir".
            if (tor != null) ...[
              for (final linea in tor.loQueFija)
                _fila(t, Icons.check_circle_outline, linea),
              _fila(t, Icons.people_outline,
                  '$_marcados jugando esta ronda'),
            ] else
              _fila(t, Icons.people_outline,
                  '${_hoy.length} de ${bg!.playerIds.length} jugadores'),
            if (bg != null) ...[
              _fila(t, Icons.compare_arrows,
                  '$_duelosHoy duelos con apuesta'),
              _fila(t, Icons.paid_outlined,
                  '$_apuestasHoy apuestas con sus montos'),
            ],
            // Las apuestas de partida van en su propia línea: no son "una más"
            // de las de duelo, aplican a todos a la vez.
            if (_partidaJugables.isNotEmpty)
              _fila(t, Icons.groups_outlined,
                  '${_partidaJugables.length} de partida: '
                  '${_partidaJugables.map((a) => a.plantilla.type.label).join(', ')}'),
            const SizedBox(height: 4),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _abierto = !_abierto),
              child: Text(_abierto ? 'Cerrar' : '¿Quiénes juegan hoy?',
                  style: GolfType.label(t.primary)
                      .copyWith(fontWeight: FontWeight.w700)),
            ),
            if (_abierto) _bloqueNomina(t),
          ]),
        ),
        const SizedBox(height: 18),

        // Lo que el grupo trae y hoy NO se puede jugar.
        //
        // Va aquí, antes del botón, y no en "falta decidir": no hay nada que
        // decidir —la apuesta está guardada— lo que pasa es que con esta gente
        // no entra. Descubrirlo en el hoyo 1 es peor que leerlo aquí, y es el
        // mismo criterio de las tarjetas: decir qué falta, no encontrarlo
        // después.
        if (_partidaFuera.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.scoreOver.withValues(alpha: 0.45)),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('HOY NO ENTRA', style: GolfType.label(t.sub)),
                  const SizedBox(height: 6),
                  for (final a in _partidaFuera) ...[
                    Text('${a.plantilla.type.label}',
                        style: TextStyle(
                            color: t.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    Text(a.motivo!,
                        style: TextStyle(
                            color: t.sub, fontSize: 11.5, height: 1.35)),
                    const SizedBox(height: 4),
                  ],
                  Text(
                      'La ronda empieza sin ${_partidaFuera.length == 1 ? 'ella' : 'ellas'}. '
                      'Sigue guardada en el grupo para la próxima.',
                      style: TextStyle(
                          color: t.sub,
                          fontSize: 11,
                          fontStyle: FontStyle.italic)),
                ]),
          ),
          const SizedBox(height: 18),
        ],

        if (_pendientes.isEmpty)
          Text('No falta nada por decidir.', style: GolfType.body(t.sub))
        else
          Text('FALTA DECIDIR', style: GolfType.label(t.sub)),
        const SizedBox(height: 8),

        if (_pendientes.contains(SetupStep.campo)) _bloqueCampo(t),
        if (_pendientes.contains(SetupStep.ventaja)) _bloqueVentaja(t),

        const SizedBox(height: 22),

        // ── Y aquí se bifurca, según si hay apuestas que heredar ───────────
        //
        // Con plantilla no queda nada por decidir: se lanza y la ronda existe,
        // que es lo que "jugar mi ronda de Copa de Primavera" tiene que
        // significar.
        //
        // Sin plantilla —el seguidor, que no puede leer las apuestas del
        // organizador— falta lo más importante de una ronda, así que ofrecer
        // "empezar" a secas arrancaría una ronda sin apuestas sin decirlo. Lleva
        // al asistente con el padrón, la ventaja, el campo y la marca ya puestos:
        // lo que queda por responder es lo único que de verdad es suyo.
        if (!_pideApuestas) ...[
          GPrimaryButton(
            label: '⛳ Empezar ronda',
            onTap: _listo ? () => _empezar(directo: true) : null,
          ),
          const SizedBox(height: 8),
          // Salida para quien quiera cambiar algo de lo precargado. El wizard
          // completo sigue siendo el sitio donde se cambia cualquier cosa.
          GSecButton(
            label: 'Revisar todo antes de empezar',
            onTap: () => _empezar(directo: false),
          ),
        ] else
          GPrimaryButton(
            label: '⛳ Elegir qué se juega y empezar',
            onTap: _listo ? () => _empezar(directo: false) : null,
          ),
        const SizedBox(height: 10),
        Text(
            !_listo
                // Antes concatenaba la frase de la tarjeta y salía "Elige falta
                // elegir campo y ventaja para empezar".
                ? _queFaltaFrase
                : !_pideApuestas
                    ? (_heredaApuestas
                        ? 'Empezar usa los jugadores y las apuestas del grupo '
                            'tal cual.'
                        : 'Este torneo puntúa por score, así que no hace falta '
                            'apostar nada: empieza la ronda y ya cuenta.')
                    // Y se dice POR QUÉ hace falta el paso, en vez de que se
                    // note al llegar.
                    : '${_tor?.motivoApuestas ?? ''} Lo demás ya está puesto, '
                        'incluida la marca del torneo.',
            style: GolfType.label(t.sub)),
      ]),
    );
  }

  /// Panel de nómina abierto.
  ///
  /// Desde un torneo arranca ABIERTO: la lista de hoy es justo la pregunta que
  /// queda, y esconderla detrás de un toque sería el mismo fallo que ya nos costó
  /// tiempo —la lógica está y la superficie no se alcanza—.
  late bool _abierto = widget.torneo != null;

  /// Cuántos juegan hoy. Con torneo no hay "de N habituales" que enseñar.
  int get _marcados => _jugando.length;

  /// Reglas de hoy. Derivadas, para que el resumen se recalcule en vivo.
  List<PairBetRule> get _reglasHoy =>
      widget.grupo?.rulesForToday(_jugando) ?? const [];
  int get _duelosHoy => _reglasHoy.where((r) => r.modules.isNotEmpty).length;
  int get _apuestasHoy =>
      _reglasHoy.fold(0, (s, r) => s + r.modules.length);

  /// Las apuestas de partida del grupo, mirando quién viene hoy.
  ///
  /// Derivadas de _hoy, así que marcar o desmarcar a alguien recalcula en vivo:
  /// quitar un jugador puede volver jugable un Wolf que con seis no entraba, y
  /// eso se ve al momento.
  List<ApuestaDePartidaHoy> get _partidaHoy =>
      widget.grupo?.modulosDePartidaHoy(_jugando) ?? const [];
  List<ApuestaDePartidaHoy> get _partidaJugables =>
      _partidaHoy.where((a) => a.jugable).toList();
  List<ApuestaDePartidaHoy> get _partidaFuera =>
      _partidaHoy.where((a) => !a.jugable).toList();

  /// Qué falta, en una frase que se lee sola.
  String get _queFaltaFrase {
    // Los jugadores van primero porque sin dos no hay ronda, y decir "elige el
    // campo" cuando lo que falta es gente manda a la pregunta equivocada.
    if (_jugando.length < 2) {
      return _tor?.miFicha == null
          ? 'Marca al menos dos jugadores para empezar.'
          : 'Añade a alguien más: una ronda de uno no se puede apostar.';
    }
    final faltan = <String>[
      if (_pendientes.contains(SetupStep.campo) && _campo == null) 'el campo',
      if (_pendientes.contains(SetupStep.ventaja) && _ventaja == null)
        'la ventaja',
    ];
    if (faltan.isEmpty) return '';
    if (faltan.length == 1) return 'Elige ${faltan.first} para empezar.';
    return 'Elige ${faltan.join(' y ')} para empezar.';
  }

  /// Jugadores creados aquí mismo. No están en el directorio.
  ///
  /// Mismo comportamiento que el wizard, comprobado: _editPlayer solo escribía
  /// en _players y _playerTees, sin tocar PlayerProvider ni Firestore. Un
  /// jugador creado es LOCAL a la ronda por las dos rutas, así que crear desde
  /// aquí no introduce una diferencia nueva.
  ///
  /// Que convenga guardarlos —un invitado de hoy suele repetir— es cierto, pero
  /// cambiarlo aquí y no en el wizard sí crearía la divergencia que el criterio
  /// 5 trata de evitar. Se deja igual y se dice.
  final Map<String, Player> _creados = {};

  /// Quiénes juegan hoy. Los habituales marcados, y se puede invitar a alguien.
  Widget _bloqueNomina(GolfTheme t) {
    final dir = context.watch<PlayerProvider>().directory;
    final habituales = widget.grupo?.playerIds ?? const <String>[];
    final pat = widget.grupo?.patron;

    String nombre(String id) {
      final creado = _creados[id];
      if (creado != null) return creado.name;
      final pw = dir.where((x) => x.player.id == id).firstOrNull;
      return pw?.displayName ?? id;
    }

    // Los del padrón salen en SU sección, con su propio significado. Sin este
    // filtro la misma persona aparecía dos veces —una como inscrito y otra como
    // "del directorio"— y elegir entre dos chips idénticos no es una elección.
    final delPadron = _tor?.padron.map(nombreComparable).toSet() ?? const {};
    final invitables = dir
        // _jugando y no _hoy: yo no estoy en _hoy —soy un hecho, no una casilla—
        // y sin esto salía ofrecido como "del directorio" en mi propia ronda.
        .where((x) => !_jugando.contains(x.player.id))
        .where((x) => !habituales.contains(x.player.id))
        .where((x) => !delPadron.contains(nombreComparable(x.displayName)))
        .toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 10),
      // YO primero, y sin casilla: es un hecho, no una opción.
      if (_tor?.miFicha != null)
        _filaFija(t, nombre(_tor!.miFicha!)),
      for (final id in habituales)
        if (id != _tor?.miFicha)
          _filaJugador(t, nombre(id), _hoy.contains(id),
              etiqueta: _porQueEsta(id),
              onTap: () => setState(() {
                    if (!_hoy.remove(id)) _hoy.add(id);
                  })),
      // Los añadidos de hoy. La etiqueta dice de dónde vienen —del padrón, del
      // torneo, o a mano— para que "¿por qué está marcado este?" se conteste
      // mirando en vez de adivinando.
      for (final id in _hoy
          .where((x) => !habituales.contains(x) && x != _tor?.miFicha))
        _filaJugador(t, nombre(id), true,
            etiqueta: _porQueEsta(id) ?? 'invitado',
            onTap: () => setState(() => _hoy.remove(id))),

      // ── Y si no me pudieron resolver ─────────────────────────────────────
      //
      // Pasa si la cuenta no tiene jugador propio asignado. No se materializa en
      // silencio: hace falta el handicap, y sobre todo hace falta que se vea, que
      // la consecuencia de no estar no es cosmética.
      if (_tor?.yoSoy != null && _tor?.miFicha == null) ...[
        const SizedBox(height: 8),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _sumarDelPadron(t, _tor!.yoSoy!),
          child: Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: t.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.primary),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('+ Ponerme en la ronda (${_tor!.yoSoy})',
                      style: GolfType.body(t.text)
                          .copyWith(fontWeight: FontWeight.w700)),
                  Text(
                      'Sin ti, esta ronda contaría para el torneo sin contar '
                      'para nadie.',
                      style: GolfType.label(t.danger)),
                ]),
          ),
        ),
      ],

      // ── El padrón del torneo ─────────────────────────────────────────────
      //
      // El hueco que empezó todo esto: "los participantes del torneo no están en
      // mi directorio". Los define el torneo, así que salen de él, y quien sigue
      // el torneo los tiene por el nombre que viaja en la instantánea.
      if (_tor != null && _delPadronSinMarcar.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text('DEL PADRÓN DEL TORNEO', style: GolfType.label(t.sub)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final n in _delPadronSinMarcar)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _sumarDelPadron(t, n),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: t.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: t.primary.withValues(alpha: 0.35)),
                ),
                // El nombre que YO uso para esa persona, no el del padrón: es
                // el que va a salir en la captura y en el historial, y tener dos
                // vocabularios en la misma vista hacía parecer que eran dos
                // clases de gente distintas.
                child: Text('+ ${_tor!.comoLoLlamo(n, _nombreDeFicha)}',
                    style: GolfType.label(t.primary)),
              ),
            ),
        ]),
        if (_tor!.pideHandicap && _tor!.sinFicha.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                'A quien no tengas todavía se le pregunta el handicap al '
                'añadirlo: esta ronda lo usa.',
                style: GolfType.label(t.sub)),
          ),
      ],

      const SizedBox(height: 8),
      Text('INVITAR A ALGUIEN MÁS', style: GolfType.label(t.sub)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        // Crear a alguien que no está en el directorio.
        //
        // Sin esto, que aparezca un amigo nuevo el sábado rompía el atajo: había
        // que ir a "Revisar todo" y recorrer el wizard hasta el paso Jugadores.
        // El mismo problema que el atajo resuelve, un nivel más abajo.
        GestureDetector(
          onTap: () => _crearJugador(t),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: t.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: t.primary.withValues(alpha: 0.45)),
            ),
            child: Text('+ Jugador nuevo',
                style: GolfType.label(t.primary)
                    .copyWith(fontWeight: FontWeight.w700)),
          ),
        ),
      ]),

      if (invitables.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text('DEL DIRECTORIO', style: GolfType.label(t.sub)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final x in invitables.take(12))
            GestureDetector(
              onTap: () => setState(() => _hoy.add(x.player.id)),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: t.divider),
                ),
                child: Text('+ ${x.displayName}', style: GolfType.label(t.sub)),
              ),
            ),
        ]),
      ],

      // Qué juega un invitado. Si el grupo no es uniforme se DICE en vez de
      // adivinar: elegir por mayoría le inventaría un acuerdo que nadie pactó.
      if (pat != null &&
          _hoy.any((x) => !habituales.contains(x)) &&
          !pat.uniforme) ...[
        const SizedBox(height: 8),
        Text(pat.motivo!, style: GolfType.label(t.danger)),
      ],
      if (_jugando.length < 2) ...[
        const SizedBox(height: 8),
        Text('Hacen falta al menos dos para jugar.',
            style: GolfType.label(t.danger)),
      ],
    ]);
  }

  /// Los del padrón que hoy no están marcados, por nombre.
  ///
  /// Se compara por FICHA cuando la hay y por nombre cuando no: alguien del
  /// padrón sin ficha todavía no puede estar en _hoy, porque _hoy son ids.
  List<String> get _delPadronSinMarcar {
    final tor = _tor;
    if (tor == null) return const [];
    return tor.padron.where((n) {
      // YO nunca salgo aquí: no soy un tercero al que añadir. Si mi ficha no se
      // pudo resolver tengo mi propio bloque, que además dice qué pasa si no me
      // pongo.
      if (n == tor.yoSoy) return false;
      final id = tor.fichaDe[n];
      return id == null || !_hoy.contains(id);
    }).toList();
  }

  /// De dónde viene que esta ficha esté marcada. Null si es un añadido a mano.
  String? _porQueEsta(String id) {
    final tor = _tor;
    if (tor != null && tor.miFicha == id) return 'tú';
    if (widget.grupo?.playerIds.contains(id) ?? false) {
      return tor == null ? 'habitual' : 'del torneo';
    }
    if (tor?.fichaDe.values.contains(id) ?? false) return 'del padrón';
    return null;
  }

  /// Añade a alguien del padrón, materializando su ficha si hace falta.
  ///
  /// ── Aquí es donde el handicap 0 podía colar un número mal ─────────────────
  ///
  /// La instantánea no lleva handicaps —es un atributo personal de un tercero,
  /// no clasificación del torneo— así que una ficha nueva nace en 0. Con ventaja,
  /// un 0 falso da netos falsos sin avisar, que es la categoría que más caro nos
  /// ha salido.
  ///
  /// Con [VentajaDeTorneo.ninguna] el handicap no interviene en ningún cálculo,
  /// así que no se pregunta y entra directo: el riesgo desaparece POR
  /// CONSTRUCCIÓN, no por aviso, y de paso es una pregunta menos en el caso más
  /// común de un torneo. Con handicap o sliding se abre el formulario, con el
  /// nombre ya puesto, y lo único que hay que responder es el número.
  Future<void> _sumarDelPadron(GolfTheme t, String nombre) async {
    final tor = _tor;
    if (tor == null) return;

    // Ya tiene ficha: es un jugador más de la lista de hoy.
    final ya = tor.fichaDe[nombre];
    if (ya != null) {
      setState(() => _hoy.add(ya));
      return;
    }

    double hcp = 0;
    if (tor.pideHandicap) {
      final r = await showPlayerEditSheet(
        context,
        t: t,
        nombreInicial: nombre,
        handicapInicial: 0,
        teeInicial: TeeInfo.standard,
        nombreFallback: nombre,
        creando: true,
      );
      if (r == null || !mounted) return;
      hcp = r.handicap;
    }

    // El id se genera aquí y es el MISMO que va al directorio: si el directorio
    // le diera otro, la misma persona saldría dos veces y su historial se
    // partiría en dos. Es la lección del jugador creado en el asistente.
    final id = 'pad_${DateTime.now().microsecondsSinceEpoch}';
    final nuevo = Player(
        id: id, name: nombre, handicapBase: hcp, colorIndex: _jugando.length);
    setState(() {
      _creados[id] = nuevo;
      _hoy.add(id);
    });
    try {
      await context.read<PlayerProvider>().createPlayer(
          id: id, name: nombre, handicap: hcp, colorIndex: nuevo.colorIndex);
    } catch (e) {
      // Juega igual: la ficha es local a la ronda. Se dice porque la próxima
      // ronda del torneo volvería a pedirlo, y eso hay que poder explicarlo.
      debugPrint('[Torneo] no se pudo guardar $nombre en el directorio: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$nombre juega esta ronda, pero no se pudo guardar en '
            'tus compañeros.'),
        duration: const Duration(seconds: 4),
      ));
    }
  }

  /// Crea un jugador con EL formulario compartido.
  ///
  /// El mismo showPlayerEditSheet que usa el wizard, no una copia: dos
  /// formularios divergen en cuanto alguien añada un campo a uno de los dos.
  ///
  /// Sin apiCourse: aquí el campo puede no estar elegido todavía, y pedir un tee
  /// de un campo que no se ha decidido no significa nada. El tee se asigna solo
  /// al construir la ronda, como con cualquier otro jugador.
  /// No se aplica el límite de 8 del wizard, y es deliberado.
  ///
  /// Ese límite vive SOLO en dos gates de UI de SetupScreen —el botón de crear y
  /// el de añadir del directorio—. Ni el modelo ni el motor limitan, y
  /// _precargarDesdeGrupo tampoco lo comprueba: por eso Martes CGM carga sus 9
  /// jugadores y funciona.
  ///
  /// Es una inconsistencia anterior a este encargo: el wizard no te deja LLEGAR
  /// a 9 a mano, pero un grupo con 9 entra sin problema. Aplicar aquí el 8
  /// rompería un caso que hoy funciona, así que no se aplica y se dice.
  Future<void> _crearJugador(GolfTheme t) async {
    final r = await showPlayerEditSheet(
      context,
      t: t,
      nombreInicial: 'Jugador ${_jugando.length + 1}',
      handicapInicial: 0,
      teeInicial: TeeInfo.standard,
      nombreFallback: 'Jugador ${_jugando.length + 1}',
      creando: true,
    );
    if (r == null || !mounted) return;
    final id = 'nuevo_${DateTime.now().microsecondsSinceEpoch}';
    final nuevo = Player(
        id: id,
        name: r.name,
        handicapBase: r.handicap,
        colorIndex: _jugando.length);
    setState(() {
      _creados[id] = nuevo;
      _hoy.add(id);
    });
    // Al directorio, con el MISMO id que lleva a la ronda: si el directorio le
    // diera otro, la misma persona saldría dos veces y su historial se partiría.
    // No bloquea el arranque: si falla, juega igual y se dice.
    if (!r.guardarEnDirectorio) return;
    try {
      await context.read<PlayerProvider>().createPlayer(
            id: id,
            name: nuevo.name,
            handicap: nuevo.handicapBase,
            colorIndex: nuevo.colorIndex,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${nuevo.name} guardado en tus compañeros.'),
        duration: const Duration(seconds: 3),
      ));
    } catch (e) {
      debugPrint('[Arranque] no se pudo guardar $id en el directorio: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${nuevo.name} juega esta ronda, pero no se pudo guardar '
            'en tus compañeros.'),
        duration: const Duration(seconds: 5),
      ));
    }
  }

  /// Mi fila: marcada, con su etiqueta, y sin nada que tocar.
  ///
  /// No es un checkbox deshabilitado —eso sigue pareciendo una pregunta que no te
  /// dejan contestar— es un hecho de la ronda, como el torneo para el que cuenta.
  Widget _filaFija(GolfTheme t, String nombre) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Icon(Icons.check_circle, color: t.primary, size: 19),
          const SizedBox(width: 9),
          Expanded(
              child: Text(nombre,
                  style: GolfType.body(t.text)
                      .copyWith(fontWeight: FontWeight.w700))),
          Text('tú', style: GolfType.label(t.primary)),
        ]),
      );

  Widget _filaJugador(GolfTheme t, String nombre, bool dentro,
          {String? etiqueta, required VoidCallback onTap}) =>
      GestureDetector(
        // opaque: una fila o tarjeta de selección se toca donde caiga, no solo
        // sobre sus letras. Sin esto el GestureDetector responde únicamente donde
        // pintan los hijos, así que el hueco de la fila y el anillo alrededor de
        // un icono quedan muertos. Es el fallo que hacía que el + de la lista de
        // jugadores no respondiera.
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Icon(
                dentro
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                color: dentro ? t.primary : t.divider,
                size: 19),
            const SizedBox(width: 9),
            Expanded(
                child: Text(nombre,
                    style: GolfType.body(dentro ? t.text : t.sub).copyWith(
                        decoration:
                            dentro ? null : TextDecoration.lineThrough))),
            if (etiqueta != null)
              Text(etiqueta, style: GolfType.label(t.primary)),
          ]),
        ),
      );

  Widget _fila(GolfTheme t, IconData icono, String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(icono, size: 15, color: t.sub),
          const SizedBox(width: 8),
          Expanded(child: Text(texto, style: GolfType.body(t.text))),
        ]),
      );

  Widget _bloqueCampo(GolfTheme t) => GestureDetector(
        // opaque: una fila o tarjeta de selección se toca donde caiga, no solo
        // sobre sus letras. Sin esto el GestureDetector responde únicamente donde
        // pintan los hijos, así que el hueco de la fila y el anillo alrededor de
        // un icono quedan muertos. Es el fallo que hacía que el + de la lista de
        // jugadores no respondiera.
        behavior: HitTestBehavior.opaque,
        onTap: () => showModalBottomSheet(
          context: context,
          backgroundColor: t.card,
          isScrollControlled: true,
          useRootNavigator: true,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          // El MISMO selector del wizard: reimplementarlo daría dos listas de
          // campos que pueden divergir.
          builder: (_) => CoursePickerSheet(
            t: t,
            onSelected: (info, _) => setState(() => _campo = info),
          ),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: _campo != null ? t.primary.withValues(alpha: 0.08) : t.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: _campo != null ? t.primary : t.divider,
                width: _campo != null ? 1.5 : 1),
          ),
          child: Row(children: [
            const Text('📍', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 11),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Campo',
                      style: GolfType.body(t.text)
                          .copyWith(fontWeight: FontWeight.w600)),
                  Text(_campo?.name ?? 'Toca para elegir',
                      style: GolfType.label(t.sub)),
                ])),
            Icon(_campo != null ? Icons.check_circle : Icons.chevron_right,
                color: _campo != null ? t.primary : t.sub, size: 20),
          ]),
        ),
      );

  Widget _bloqueVentaja(GolfTheme t) {
    const opciones = [
      ('handicap', 'Handicap', 'Golpes según el handicap registrado.'),
      ('sliding', 'Sliding', 'Se ajusta según cómo terminó la anterior.'),
      ('ninguna', 'Sin ventaja', 'Todos brutos.'),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Ventaja',
            style:
                GolfType.body(t.text).copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        for (final (clave, titulo, detalle) in opciones)
          GestureDetector(
            onTap: () => setState(() => _ventaja = clave),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: _ventaja == clave
                    ? t.primary.withValues(alpha: 0.10)
                    : t.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: _ventaja == clave ? t.primary : t.divider),
              ),
              child: Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(titulo, style: GolfType.body(t.text)),
                      Text(detalle, style: GolfType.label(t.sub)),
                    ])),
                if (_ventaja == clave)
                  Icon(Icons.check, color: t.primary, size: 18),
              ]),
            ),
          ),
      ]),
    );
  }

  /// Lanza, o abre el wizard con todo puesto.
  ///
  /// Las dos salidas van por SetupScreen: con [directo] lanza al entrar sin
  /// mostrar los pasos, y sin él se queda en el wizard para cambiar lo que sea.
  /// Un solo camino de lanzamiento.
  /// Los pasos que esta pantalla deja respondidos.
  ///
  /// Se CALCULA de lo que hay, no se fija: el día que el punto de partida traiga
  /// una respuesta más, el aterrizaje se corre solo.
  Set<SetupStep> get _resueltos => {
        if (_campo != null) SetupStep.campo,
        // La nómina siempre: de aquí no se sale con la lista sin decidir.
        SetupStep.jugadores,
        if (_ventaja != null) SetupStep.ventaja,
        // Y con grupo, todo lo que el grupo responde.
        if (widget.grupo != null) ...resueltosPorGrupo(),
      };

  /// Si esta ronda hereda las apuestas de un punto de partida.
  ///
  /// Un grupo SIEMPRE las trae. Un torneo solo si tiene plantilla, y el seguidor
  /// nunca la tiene: vive en el espacio del organizador y sus reglas por duelo
  /// llevan ids de jugador, así que publicarla rompería la regla de qué no entra
  /// en la instantánea.
  bool get _heredaApuestas => widget.grupo != null;

  /// Si esta ronda tiene que pasar por el paso de elegir apuestas.
  ///
  /// Con grupo nunca: las trae. Sin grupo lo decide cómo puntúa el torneo —ver
  /// PuntoDeTorneo.pideApuestas—: por score no hace falta nada y se lanza; por
  /// dinero la medida sale de lo apostado y arrancar en blanco daría cero a todo
  /// el mundo.
  ///
  /// Y sin torneo ni grupo esta pantalla no existe, así que el caso no se da.
  bool get _pideApuestas => !_heredaApuestas && (_tor?.pideApuestas ?? true);

  void _empezar({required bool directo}) {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => SetupScreen(
        grupoInicial: widget.grupo,
        // Lo que esta pantalla YA respondió, para aterrizar en la primera
        // pregunta de verdad en vez de en "paso 1 de 8 · Campo".
        //
        // Sin esto, venir de aquí volvía a preguntar el campo, los jugadores y
        // la ventaja: el error de dirección reapareciendo en el último salto,
        // que es donde se ha roto tres veces.
        pasosResueltos: _resueltos,
        // LA MARCA. Sin esto la ronda se juega y no cuenta, que es el peor de los
        // dos silencios: todo parece funcionar y la tabla no se mueve.
        torneoInicial: widget.torneo?.torneoId,
        // La lista de HOY, no la de los habituales.
        nominaInicial: List.of(_jugando),
        // Los que no están en el directorio: sin esto se caerían al precargar,
        // porque _precargarDesdeGrupo los busca ahí y los omite si no aparecen.
        jugadoresNuevos: _creados.values.toList(),
        campoInicial: _campo,
        ventajaInicial: _ventaja,
        lanzarAlEntrar: directo,
      ),
    ));
  }
}
