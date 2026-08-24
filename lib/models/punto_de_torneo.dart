// ─────────────────────────────────────────────────────────────────────────────
// PUNTO DE TORNEO — el torneo como punto de partida de una ronda
//
// La corrección de dirección, en un objeto. Durante todo el diseño el torneo fue
// "una vista sobre rondas que ya existen", y de ahí salieron cinco huecos que
// parecían independientes: los participantes no están en mi directorio, hay que
// marcar la ronda, hay que repetir el formato, hay que elegir jugadores, seguir
// un torneo no deja jugarlo con su gente. Uno solo visto desde cinco sitios.
//
// Aquí el torneo va en la otra dirección: RESPONDE preguntas de la ronda en vez
// de esperar a que la ronda le diga que existe.
//
// Lógica pura, sin Flutter. Y sin BettingGroup a propósito: la plantilla se pasa
// aparte, porque es lo único de esto que un seguidor NO puede tener.
// ─────────────────────────────────────────────────────────────────────────────
import 'models.dart';
import 'torneo.dart';
import 'torneo_publicado.dart';

/// Lo que un torneo responde por adelantado para una ronda que cuenta.
///
/// Se construye de dos sitios y sale igual de los dos, que es lo que permite una
/// sola pantalla de arranque: del torneo propio —donde está todo— y de la
/// instantánea publicada —donde está todo menos la plantilla—.
class PuntoDeTorneo {
  final String torneoId;
  final String nombre;
  final String emoji;

  /// EL PADRÓN, como nombres. Siempre nombres, por los dos caminos.
  ///
  /// El organizador tiene ids y el seguidor no, así que si esto fueran ids el
  /// objeto tendría dos formas y la pantalla dos ramas. El nombre es además el
  /// puente que ya elegimos para que un resultado publicado cuente, así que es
  /// la misma moneda de punta a punta.
  final List<String> padron;

  /// Nombre → ficha local que ya existe, para los que la tienen.
  ///
  /// Vacío no significa "no hay nadie": significa que hay que materializarlos.
  /// Se resuelve con [conFichas], por nombre normalizado, y es lo que evita que
  /// la segunda ronda del torneo cree a Luis Herrera por segunda vez.
  final Map<String, String> fichaDe;

  final VentajaDeTorneo? ventaja;
  final CourseInfo? campo;

  /// Con qué nombre juego yo en este torneo, si lo he reclamado.
  final String? yoSoy;

  /// Cómo puntúa el torneo. Null = no se sabe, así que hay que preguntar.
  final MetodoDePuntuacion? metodo;

  /// Si la ronda puede heredar las apuestas del torneo.
  ///
  /// ── Por qué el seguidor no puede, y no es un descuido ─────────────────────
  ///
  /// La plantilla vive en el espacio del organizador y sus reglas por duelo
  /// llevan ids de jugador. Publicarla en la instantánea rompería la regla de qué
  /// no entra —ids que identifican personas—, y darle lectura al seguidor sobre
  /// los grupos del organizador obligaría a reglas condicionales sobre `users/**`,
  /// que es exactamente lo que dijimos que no íbamos a hacer.
  ///
  /// Así que el seguidor hereda CON QUIÉN juega, CON QUÉ VENTAJA y DÓNDE, y elige
  /// qué se apuesta. Que además es lo suyo: en una liga cada uno juega su sábado.
  final bool conPlantilla;

  const PuntoDeTorneo({
    required this.torneoId,
    required this.nombre,
    required this.emoji,
    required this.padron,
    this.fichaDe = const {},
    this.ventaja,
    this.campo,
    this.yoSoy,
    this.conPlantilla = false,
    this.metodo,
  });

  /// Desde MI torneo. El padrón son los inscritos, con el nombre del directorio.
  ///
  /// El inscrito sin nombre resoluble se queda fuera en vez de entrar como '—':
  /// un id crudo en una lista de jugadores es lo que ya nos dijo "esto está a
  /// medias" más alto que cualquier otra cosa.
  factory PuntoDeTorneo.propio(
    Torneo t, {
    required Map<String, String> nombres,
    String? yoSoy,
  }) {
    final padron = <String>[];
    final fichas = <String, String>{};
    for (final pid in t.participantes) {
      final n = nombres[pid];
      if (n == null || n.isEmpty || n == sinNombre) continue;
      padron.add(n);
      fichas[n] = pid;
    }
    return PuntoDeTorneo(
      torneoId: t.id,
      nombre: t.nombre,
      emoji: t.emoji,
      padron: padron,
      fichaDe: fichas,
      ventaja: t.ventaja,
      campo: t.campo,
      yoSoy: yoSoy,
      conPlantilla: t.plantillaId != null,
      metodo: metodoEfectivo(t),
    );
  }

  /// Desde la instantánea de un torneo que sigo.
  ///
  /// El padrón sale de [TorneoPublicado.padron], que es la misma lista con la que
  /// se elige "¿cuál eres tú?" — verificado que viaja incluso en una liga sin
  /// ninguna ronda jugada, que es justo cuando hace falta para la primera.
  ///
  /// [torneoId] vacío significa que la instantánea es anterior al campo: sin él
  /// la ronda no puede marcarse y no sirve de nada crearla, así que quien lo lea
  /// tiene que comprobarlo con [utilizable].
  factory PuntoDeTorneo.seguido(TorneoPublicado c, {String? yoSoy}) =>
      PuntoDeTorneo(
        torneoId: c.torneoId,
        nombre: c.nombre,
        emoji: c.emoji,
        padron: c.padron,
        ventaja: c.ventaja,
        campo: c.campo,
        yoSoy: yoSoy,
        // Nunca. Ver [conPlantilla].
        conPlantilla: false,
        metodo: c.metodo,
      );

  /// Si con esto se puede crear una ronda que de verdad cuente.
  ///
  /// Sin torneoId no hay marca, y sin marca la ronda se juega y no cuenta: el
  /// silencio peor de los dos. Se comprueba antes de ofrecer el botón.
  bool get utilizable => torneoId.isNotEmpty && padron.isNotEmpty;

  /// Resuelve el padrón contra las fichas que YA existen, por nombre normalizado.
  ///
  /// [idPorNombre] es el directorio de quien juega: nombre → playerId. Se
  /// normaliza con [nombreComparable], el mismo puente que decide si un resultado
  /// publicado cuenta. Normalizar distinto aquí daría el fallo más silencioso de
  /// todos: el nombre coincide para el ojo, no para el código, y la misma persona
  /// entra dos veces con la mitad de su historial cada una.
  PuntoDeTorneo conFichas(Map<String, String> idPorNombre) {
    final porComparable = {
      for (final e in idPorNombre.entries) nombreComparable(e.key): e.value,
    };
    return PuntoDeTorneo(
      torneoId: torneoId,
      nombre: nombre,
      emoji: emoji,
      padron: padron,
      fichaDe: {
        ...fichaDe,
        for (final n in padron)
          if (porComparable[nombreComparable(n)] != null)
            n: porComparable[nombreComparable(n)]!,
      },
      ventaja: ventaja,
      campo: campo,
      yoSoy: yoSoy,
      conPlantilla: conPlantilla,
      metodo: metodo,
    );
  }

  /// Mi ficha en este torneo, si la reclamación se pudo resolver.
  ///
  /// Es el jugador que SEGURO juega la ronda: por eso viene marcado y no se
  /// ofrece como si fuera un tercero al que añadir.
  String? get miFicha => yoSoy == null ? null : fichaDe[yoSoy];

  /// Fija cuál de MIS fichas soy yo en este torneo.
  ///
  /// ── Por qué la reclamación manda sobre el nombre ──────────────────────────
  ///
  /// "Soy Carlos Angel" no dice "tengo una ficha que se llama Carlos Angel":
  /// dice "ese de la lista soy yo". Y mi ficha propia puede llamarse "CAV",
  /// porque así me llamo en mi app. Emparejar solo por nombre me dejaría fuera
  /// de mi propio torneo, o peor, me emparejaría con otra ficha que sí se llama
  /// así y que no soy yo.
  ///
  /// Se aplica DESPUÉS de [conFichas] para que gane: el nombre es una pista, la
  /// reclamación es una decisión.
  PuntoDeTorneo conMiFicha(String playerId) {
    final quien = yoSoy;
    if (quien == null) return this;
    return PuntoDeTorneo(
      torneoId: torneoId,
      nombre: nombre,
      emoji: emoji,
      padron: padron,
      fichaDe: {...fichaDe, quien: playerId},
      ventaja: ventaja,
      campo: campo,
      yoSoy: yoSoy,
      conPlantilla: conPlantilla,
      metodo: metodo,
    );
  }

  /// Cómo se llama alguien del padrón EN MI APP.
  ///
  /// Una sola regla para toda la pantalla: si tengo ficha suya, su nombre es el
  /// que uso en todas partes —el que va a salir en la captura y en el historial—
  /// y si no la tengo, el del padrón, que es lo único que hay.
  ///
  /// Sin esta regla la pantalla mezclaba dos vocabularios —"Luis Herrera" del
  /// torneo junto a "RAFA" del directorio— y parecían dos clases de gente
  /// distintas cuando lo único distinto era por dónde entró la ficha.
  String comoLoLlamo(String nombreDelPadron, Map<String, String> nombreDeFicha) {
    final id = fichaDe[nombreDelPadron];
    final local = id == null ? null : nombreDeFicha[id];
    return local == null || local.isEmpty ? nombreDelPadron : local;
  }

  /// Los del padrón que todavía no tienen ficha. Hay que crearlas al entrar.
  List<String> get sinFicha =>
      padron.where((n) => fichaDe[n] == null).toList();

  /// Si hay que PREGUNTAR el handicap al materializar a alguien del padrón.
  ///
  /// ── El sitio donde esto produce un número mal en silencio ─────────────────
  ///
  /// La instantánea no lleva handicaps, y no debe llevarlos: es un atributo
  /// personal de un tercero, no clasificación del torneo. Así que una ficha
  /// materializada nace en 0, y una apuesta con ventaja calculada sobre 0 da
  /// netos falsos sin avisar de nada. Es la categoría que más caro nos ha
  /// salido: un número plausible y equivocado.
  ///
  /// Con [VentajaDeTorneo.ninguna] el handicap no interviene en ningún cálculo,
  /// así que la pregunta no se hace: el riesgo desaparece POR CONSTRUCCIÓN, que
  /// es mejor que desaparecer por aviso, y de paso es una pregunta menos en el
  /// caso más común de un torneo. Con handicap o sliding SÍ se pregunta, visible,
  /// porque los dos lo miran —sliding parte del handicap y se mueve desde ahí—.
  ///
  /// Sin ventaja decidida se pregunta: no saber no es lo mismo que no importar.
  bool get pideHandicap => ventaja?.usaHandicap ?? true;

  /// Si una ronda de este torneo NECESITA que se configuren apuestas.
  ///
  /// ── Lo que decide si el arranque lanza o pregunta ─────────────────────────
  ///
  /// Con plantilla nunca hace falta: las apuestas vienen puestas.
  ///
  /// Sin plantilla —el seguidor, que no puede leer las del organizador— depende
  /// de cómo puntúe el torneo. Por score neto o Stableford la medida es el score,
  /// así que una tarjeta sin nada apostado cuenta igual y no hay NADA que
  /// preguntar: se lanza. Por dinero o por posición la medida es el dinero, y
  /// arrancar sin apuestas le daría cero a todo el mundo sin que la tabla lo
  /// distinguiera de un empate.
  ///
  /// Sin método conocido se pregunta. Preguntar de más cuesta un paso; arrancar
  /// de menos cuesta una tabla en blanco.
  bool get pideApuestas =>
      !conPlantilla && (metodo?.necesitaApuestas ?? true);

  /// Por qué hace falta configurar apuestas, para decirlo en vez de que se note.
  String? get motivoApuestas => !pideApuestas
      ? null
      : metodo == null
          ? 'Este enlace no dice cómo puntúa el torneo, así que hace falta '
              'elegir qué se juega.'
          : 'Este torneo puntúa ${metodo!.label.toLowerCase()}, así que la '
              'medida sale de lo apostado: hay que decir qué se juega.';

  /// Qué fija el torneo, en una línea. Para el resumen de la pantalla.
  List<String> get loQueFija => [
        '${padron.length} inscrito${padron.length == 1 ? '' : 's'} en el padrón',
        if (ventaja != null) 'Ventaja: ${ventaja!.label}',
        if (campo != null) 'Campo: ${campo!.name}',
        if (conPlantilla) 'Las apuestas del torneo',
        if (metodo != null) 'Puntúa ${metodo!.label.toLowerCase()}',
        'La ronda cuenta para $nombre',
      ];
}
