// ─────────────────────────────────────────────────────────────────────────────
// TORNEO — y CUÁL de las dos cosas es, porque son dos
//
// Durante todo el diseño este archivo dijo: "un torneo no cambia cómo se juega:
// es una VISTA sobre rondas que ya existen". Es cierto para el caso con el que
// nació —una liga de amigos que ya juegan cada sábado, donde el torneo solo suma
// lo que iba a pasar igual— y es FALSO para el evento organizado, donde el
// torneo ES el evento: define quién juega, en qué formato y qué día, y las
// rondas ocurren dentro de él.
//
// Queda escrito aquí porque el principio equivocado no produjo un error: produjo
// CINCO, y todos parecían independientes. Los participantes no están en mi
// directorio; hay que marcar la ronda para que cuente; hay que repetir el
// formato; hay que elegir jugadores otra vez; seguir un torneo no deja jugarlo
// con su gente. Cinco parches, cada uno correcto en su sitio, que juntos
// describen un flujo que nadie querría usar en un torneo real. Es el mismo fallo
// que las cuatro cifras distintas del asistente, un nivel más arriba: pasos
// correctos por separado e incoherentes puestos en fila.
//
// LO QUE ESTE MODELO NO GUARDA, y hay que saberlo antes de decir "lo fija el
// torneo": nada de cómo se juega una ronda. No hay campo, ni ventaja, ni
// apuestas, ni equipos. [formato] es liga o cuadro —la estructura— y [metodo] es
// cómo puntúa la TABLA. Ninguno de los dos dice cómo se juega. Así que "el
// formato lo fija el torneo" no es una dirección que se esté ignorando: es un
// campo que todavía no existe. El día que exista, el atajo ya está construido
// —ver preguntasPendientes en setup_flow.dart— y se acorta solo.
//
// Y la tabla se DERIVA, nunca se guarda calculada. Es la lección del RoundResult
// desfasado: el tablero de Inicio guardó los balances al cerrar la ronda y
// cuando la liquidación se corrigió, esos números se quedaron viejos sin avisar.
// Aquí no puede pasar: [tablaDe] recibe los resultados y calcula. Si una ronda
// cambia, la tabla siguiente ya sale distinta.
// ─────────────────────────────────────────────────────────────────────────────
import 'models.dart';
import 'patrocinio.dart';
import 'plantilla_de_tele.dart';
import '../engines/bet_engine.dart';
import 'round_result.dart';

export 'plantilla_de_tele.dart';

/// De dónde salen las rondas que cuentan.
enum FuenteDeRondas {
  /// Marcadas al configurar la ronda: cuenta para este torneo porque se dijo.
  ///
  /// Es la fuente por defecto y la que resuelve el problema de raíz. Un rango
  /// arrastra todo lo que cae dentro —Copa CGM 2026 salió con 79 rondas y 55
  /// personas— mientras que una marca explícita cuenta lo que se dijo que cuenta.
  ///
  /// Mismo principio que la lista de participantes: participa quien se inscribe,
  /// y cuenta la ronda que se marcó.
  marcadas,

  /// Elegidas a mano de entre las ya jugadas.
  ///
  /// Se conserva porque sirve para lo que la marca no puede: armar un torneo
  /// sobre rondas del pasado, que se jugaron antes de que existiera la marca.
  manual,

  /// Todas las cerradas entre dos fechas. **RETIRADA.**
  ///
  /// No se puede elegir en un torneo nuevo: es la que causó el problema. Sigue
  /// existiendo en el enum porque los torneos ya guardados la usan y tienen que
  /// abrir y leerse igual; lo único que desaparece es la posibilidad de
  /// elegirla. Es el mismo trato que se le dio a Match + Press.
  rango,

  /// Todas las de un grupo de apuesta guardado, opcionalmente con rango.
  grupo,
}

/// Las fuentes que se pueden elegir hoy. **Todo selector debe usar esto.**
///
/// [FuenteDeRondas.rango] queda fuera. Una fuente retirada ofrecida en un torneo
/// nuevo es la promesa de un problema que ya conocemos.
List<FuenteDeRondas> get fuentesOfrecibles =>
    FuenteDeRondas.values.where((f) => f.seOfrece).toList();

extension FuenteRetirada on FuenteDeRondas {
  bool get seOfrece => this != FuenteDeRondas.rango;

  /// Por qué esta fuente ya no se ofrece, y qué hacer. Null si sí se ofrece.
  String? get motivoRetirada => this == FuenteDeRondas.rango
      ? 'La fuente por fechas ya no se puede elegir: un rango arrastra todas '
          'las rondas que caen dentro, sean de este torneo o no. Este torneo la '
          'sigue usando, pero para acotarlo cambia a "Marcadas al configurar la '
          'ronda" —y marca las que cuenten— o a "Elegidas a mano".'
      : null;
}

extension FuenteDeRondasLabel on FuenteDeRondas {
  String get label => switch (this) {
        FuenteDeRondas.marcadas => 'Marcadas al configurar la ronda',
        FuenteDeRondas.manual => 'Elegidas a mano',
        FuenteDeRondas.rango => 'Por fechas (retirada)',
        FuenteDeRondas.grupo => 'De un grupo de apuesta',
      };

  String get descripcion => switch (this) {
        FuenteDeRondas.marcadas =>
          'Al crear una ronda dices si cuenta para este torneo. Cuenta lo que se '
              'marcó, ni una más.',
        FuenteDeRondas.manual =>
          'Eliges de entre las rondas ya jugadas. Para armar un torneo sobre el '
              'histórico.',
        FuenteDeRondas.rango =>
          'Todas las cerradas entre dos fechas. Arrastra lo que caiga dentro.',
        FuenteDeRondas.grupo =>
          'Todas las de un grupo guardado, y si quieres solo las de un tramo '
              'de fechas.',
      };
}

/// Cómo puntúa cada ronda.
enum MetodoDePuntuacion {
  /// Tabla de puntos por puesto: 10-6-4-2…
  posicion,

  /// Los puntos son el dinero ganado en la ronda.
  dinero,

  /// Menos score neto es mejor. Los puntos son el neto, y se ordena al revés.
  scoreNeto,

  /// Más puntos Stableford es mejor.
  stableford,
}

extension MetodoLabel on MetodoDePuntuacion {
  String get label => switch (this) {
        MetodoDePuntuacion.posicion => 'Por posición',
        MetodoDePuntuacion.dinero => 'Por dinero ganado',
        MetodoDePuntuacion.scoreNeto => 'Por score neto',
        MetodoDePuntuacion.stableford => 'Por puntos Stableford',
      };

  String get descripcion => switch (this) {
        MetodoDePuntuacion.posicion =>
          'El primero de cada ronda se lleva los puntos de la tabla, el segundo '
              'los siguientes, y así.',
        MetodoDePuntuacion.dinero =>
          'Lo que ganaste en la ronda son tus puntos. Perder resta.',
        MetodoDePuntuacion.scoreNeto =>
          'Tu score neto son tus puntos, y gana quien menos sume.',
        MetodoDePuntuacion.stableford =>
          'Tus puntos Stableford de la ronda. Es como se juegan casi todos los '
              'torneos.',
      };

  /// true si más puntos es mejor. Solo el score neto va al revés.
  bool get masEsMejor => this != MetodoDePuntuacion.scoreNeto;

  /// De qué campo del [RoundResult] sale el dato.
  ///
  /// Los dos últimos NO existen en las rondas cerradas antes de que se
  /// guardaran, y por eso hay que poder decirlo: una tabla corta se lee como una
  /// tabla, no como un dato que falta.
  bool get necesitaScore =>
      this == MetodoDePuntuacion.scoreNeto ||
      this == MetodoDePuntuacion.stableford;

  /// Si la medida de este método SALE de las apuestas.
  ///
  /// Decide si una ronda de este torneo puede empezar sin configurar apuestas.
  /// Con score neto o Stableford la medida es el score, así que una tarjeta sin
  /// nada apostado cuenta perfectamente y no hay ninguna pregunta que hacer.
  ///
  /// Con dinero o por posición la medida ES el dinero —la posición se decide por
  /// el dinero de la ronda—, así que arrancar sin apuestas daría cero a todo el
  /// mundo y la tabla no lo distinguiría de un empate. Otro número plausible y
  /// equivocado, que es la categoría que más caro nos ha salido.
  bool get necesitaApuestas => !necesitaScore;
}

/// Qué pasa cuando dos empatan en una ronda.
enum ReglaDeEmpate {
  /// Se reparten los puntos de las posiciones que ocupan. Es lo estándar.
  reparten,

  /// Los empatados cobran los del puesto mejor.
  mejorPuesto,

  /// Los empatados cobran los del puesto peor.
  peorPuesto,
}

extension ReglaDeEmpateLabel on ReglaDeEmpate {
  String get label => switch (this) {
        ReglaDeEmpate.reparten => 'Se reparten',
        ReglaDeEmpate.mejorPuesto => 'Los dos cobran el mejor',
        ReglaDeEmpate.peorPuesto => 'Los dos cobran el peor',
      };

  String get descripcion => switch (this) {
        ReglaDeEmpate.reparten =>
          'Dos empatados en el primer puesto con 10 y 6 se llevan 8 cada uno. '
              'Es lo estándar.',
        ReglaDeEmpate.mejorPuesto =>
          'Dos empatados en el primero se llevan 10 cada uno. Reparte más '
              'puntos de los que hay.',
        ReglaDeEmpate.peorPuesto =>
          'Dos empatados en el primero se llevan 6 cada uno. Reparte menos.',
      };
}

/// Cómo se suman las rondas.
enum Acumulacion {
  /// Todas suman.
  sumaSimple,

  /// Solo las N mejores.
  ///
  /// Es la que resuelve el problema real de un torneo largo: uno juega veinte
  /// sábados y otro ocho, y sumar premia al que más juega, no al que mejor
  /// juega. Es lo que hacen la FedEx Cup y casi todas las ligas.
  mejoresDeN,
}

extension AcumulacionLabel on Acumulacion {
  String get label => switch (this) {
        Acumulacion.sumaSimple => 'Suma simple',
        Acumulacion.mejoresDeN => 'Mejores N',
      };
}

/// Un torneo.
/// Lo que se enseña cuando no hay nombre para un jugador.
///
/// NUNCA el id. Un nombre viejo es peor que el actual, pero un id de Firestore en
/// pantalla es peor que las dos cosas: no dice nada y parece un error. El nombre
/// sale del directorio; esto es el último recurso, para el inscrito que ya no
/// está en él y no ha jugado ninguna ronda.
const sinNombre = '—';

/// Liga o eliminación directa.
///
/// Aditivo: [liga] es lo que había, así que un torneo guardado se lee igual. La
/// diferencia no está en cómo se juega —eso no lo cambia un torneo— sino en QUÉ
/// se enseña: una tabla acumulada, o una llave donde cada partido elimina.
enum FormatoDeTorneo {
  /// La tabla de siempre: todos suman, gana quien más acumula.
  liga,

  /// Eliminación directa. Los dos del partido juegan LA MISMA ronda —siempre—,
  /// así que el partido se resuelve comparando lo que esa ronda ya produjo. Es
  /// lo que hace que Stableford deje de ser un caso especial: es un método de
  /// puntuación más, no un formato aparte.
  eliminacion,
}

extension FormatoInfo on FormatoDeTorneo {
  String get label => switch (this) {
        FormatoDeTorneo.liga => 'Liga · todos suman',
        FormatoDeTorneo.eliminacion => 'Eliminación directa',
      };

  String get descripcion => switch (this) {
        FormatoDeTorneo.liga =>
          'Cada ronda suma a una tabla. Gana quien más acumula.',
        FormatoDeTorneo.eliminacion =>
          'Cuadro de partidos. Los dos del partido juegan la misma ronda y el '
              'que pierde queda fuera.',
      };
}

/// La ventaja que fija el torneo para sus rondas.
///
/// Es el ÚNICO parámetro de juego que un torneo tiene que fijar sí o sí, porque
/// cambia el resultado: dos jornadas de la misma liga, una con handicap y otra
/// sin, no son comparables y la tabla las suma como si lo fueran.
///
/// Y fijarla tiene una consecuencia que va más allá de ahorrar una pregunta: con
/// [ninguna], el handicap NO INTERVIENE en nada. Eso es lo que permite no
/// preguntarlo al materializar a los del padrón —ver [PuntoDeTorneo]— y que el
/// riesgo del handicap 0 desaparezca por construcción en vez de por aviso.
enum VentajaDeTorneo { handicap, sliding, ninguna }

extension VentajaDeTorneoInfo on VentajaDeTorneo {
  String get label => switch (this) {
        VentajaDeTorneo.handicap => 'Handicap',
        VentajaDeTorneo.sliding => 'Sliding',
        VentajaDeTorneo.ninguna => 'Sin ventaja',
      };

  String get descripcion => switch (this) {
        VentajaDeTorneo.handicap => 'Golpes según el handicap registrado.',
        VentajaDeTorneo.sliding => 'Se ajusta según cómo terminó la anterior.',
        VentajaDeTorneo.ninguna => 'Todos brutos. El handicap no interviene.',
      };

  /// El vocabulario que ya entiende SetupScreen.ventajaInicial.
  ///
  /// Se traduce en vez de guardar el texto suelto: el enum es lo que se
  /// almacena y se compara, y la cadena existe solo en la frontera. Guardar
  /// cadenas libres habría dado dos vocabularios para lo mismo.
  String get paraSetup => name;

  /// Si el handicap de un jugador cambia algo en una ronda con esta ventaja.
  ///
  /// Sliding SÍ lo mira: el ajuste parte del handicap y se mueve con el
  /// resultado, así que un 0 falso arrastra igual.
  bool get usaHandicap => this != VentajaDeTorneo.ninguna;
}

class Torneo {
  final String id;
  final String nombre;
  final String emoji;

  /// Cómo se ve este torneo en la pantalla proyectada.
  ///
  /// Vive en el torneo y no en el enlace de la tele porque es una decisión del
  /// EVENTO, no de una publicación: si el enlace se apaga y se vuelve a
  /// encender, el torneo sigue teniendo la misma cara.
  final IdentidadDeTorneo identidad;

  final FuenteDeRondas fuente;

  /// Rondas elegidas a mano. Solo con [FuenteDeRondas.manual].
  final List<String> roundIds;

  /// Tramo de fechas. Usable con [FuenteDeRondas.rango] y con [grupo].
  final DateTime? desde;
  final DateTime? hasta;

  /// El grupo guardado. Solo con [FuenteDeRondas.grupo].
  final String? bettingGroupId;

  final MetodoDePuntuacion metodo;

  /// La tabla de puntos por puesto. Solo con [MetodoDePuntuacion.posicion].
  ///
  /// El puesto que se sale de la tabla no puntúa. Configurable porque cada liga
  /// usa la suya.
  final List<int> puntosPorPuesto;

  final ReglaDeEmpate empate;

  final Acumulacion acumulacion;

  /// Cuántas cuentan con [Acumulacion.mejoresDeN].
  final int mejoresN;

  /// Quién está INSCRITO en el torneo.
  ///
  /// ── La raíz del problema de los 55 participantes ──────────────────────────
  ///
  /// El modelo asumía "participa quien juegue" cuando lo real es "participa
  /// quien se inscribe". Con un bote de por medio deja de ser cosmético: poner
  /// $500 es una decisión, no algo que te pase por jugar un sábado.
  ///
  /// Y [minimoRondas] no lo resolvía porque filtra por COMPORTAMIENTO —cuántas
  /// jugaste— cuando hacía falta filtrar por DECISIÓN. Por eso el campo se
  /// sentía insuficiente pareciendo el adecuado.
  ///
  /// Vacía significa "sin definir", no "todos": la tabla sigue enseñando
  /// resultados —son útiles— pero el BOTE no se calcula, porque apuntar dinero a
  /// nombre de quien no dijo que entraba es el fallo que esto arregla.
  final List<String> participantes;

  /// Cuántas rondas hay que jugar para OPTAR AL PREMIO. 0 = ninguna.
  ///
  /// Ya no decide quién entra —eso lo hace [participantes]— sino quién puede
  /// cobrar. Es lo que el campo quería decir desde el principio.
  final int minimoRondas;

  /// El bote, si el grupo pone uno. Aditivo: por defecto no hay.
  final BoteConfig bote;

  /// El token del enlace compartido, si se ha publicado alguna vez.
  ///
  /// Se guarda para que republicar actualice el MISMO enlace en vez de crear
  /// otro: quien ya lo tiene en WhatsApp no se queda con una copia muerta.
  /// Revocar lo borra, y volver a publicar genera uno nuevo — así un enlace
  /// reenviado donde no se quería deja de valer.
  final String? tokenCompartido;

  /// Cuándo se publicó la última copia. Null si nunca.
  final DateTime? publicadoEn;

  /// El token de la PANTALLA DE LA CASA CLUB. `/tv/{tokenTele}`.
  ///
  /// ── Por qué no es el mismo que [tokenCompartido] ──────────────────────────
  ///
  /// Era la idea original y está mal. El token de la tele es el string MENOS
  /// secreto del sistema: se proyecta en una pared ocho horas, lo lee cualquiera
  /// que pase, y se manda al del club para que lo abra en el navegador de la
  /// sala. El de `sharedTorneos` es lo contrario: es la única credencial que
  /// protege el bote y los balances, porque la regla pide cuenta —cualquiera—
  /// pero no comprueba que estés invitado.
  ///
  /// Con un solo token, quien leyera la URL de la tele y se registrara gratis
  /// leería el dinero. Dos tokens, y la pantalla de la pared no abre nada más.
  final String? tokenTele;

  /// Cuándo se publicó la pantalla. Null = nunca, o apagada.
  final DateTime? teleDesde;

  /// Si la pantalla de la casa club está EN ANTENA ahora mismo.
  ///
  /// El token solo no basta: sobrevive al apagado a propósito, para no tener que
  /// darle otro enlace al del club cada vez. Lo que dice "encendida" es la
  /// fecha.
  bool get teleEncendida => tokenTele != null && teleDesde != null;

  /// Lo que el organizador pactó con las marcas para la pantalla. §14.3.
  ///
  /// Vive en el TORNEO y no en la instantánea porque es del torneo: se acuerda
  /// antes de jugar nada y sobrevive a las doce republicaciones de una tarde.
  final InventarioProyectado inventario;

  /// Liga o eliminación directa. Por defecto liga: es lo que había.
  final FormatoDeTorneo formato;

  /// El orden del cuadro, solo con [FormatoDeTorneo.eliminacion].
  ///
  /// Es lo ÚNICO del cuadro que se guarda: quién se cruza con quién en la
  /// primera ronda. Todo lo demás —quién pasa, quién juega la semifinal, quién
  /// es campeón— se deriva de las rondas marcadas. Misma regla que la tabla, y
  /// por el mismo motivo: si el cuadro se guardara resuelto, corregir una ronda
  /// dejaría un campeón viejo sin avisar a nadie.
  ///
  /// Vacía significa "usa el orden de [participantes]".
  final List<String> siembra;

  /// Los empates que el organizador resolvió a mano.
  ///
  /// Clave: los dos ids ordenados y unidos por '|' —ver [parKey]—. Valor: quién
  /// pasa. Se guarda por PAREJA y no por posición en el cuadro para que
  /// reordenar la siembra no le adjudique el desempate a otros dos.
  ///
  /// Existe porque la app no puede jugar un hoyo 19: cuando dos empatan, el
  /// partido se queda sin resolver a la vista y alguien lo decide. Inventar un
  /// criterio —el de mejor score bruto, el mejor sembrado— sería inventarse una
  /// regla que el grupo no pactó.
  final Map<String, String> desempates;

  /// La PLANTILLA DE RONDA: cómo se juega una ronda de este torneo.
  ///
  /// Es el campo que faltaba, y el que convierte "hay que configurar el formato
  /// otra vez" de error de dirección en campo inexistente. Apunta a un
  /// [BettingGroup] porque ese objeto ya lleva jugadores, reglas por duelo y
  /// módulos de partida con sus montos, y [resueltosPorGrupo] ya declara qué
  /// pasos del asistente responde. Inventar una segunda forma de plantilla
  /// habría sido la tercera vez que dos caminos al mismo sitio se comportan
  /// distinto.
  ///
  /// ── Y POR QUÉ NO ES [bettingGroupId] ──────────────────────────────────────
  ///
  /// Aquel campo significa otra cosa: QUÉ RONDAS CUENTAN. [rondasDelTorneo]
  /// filtra con él —`r.bettingGroupIds.contains(t.bettingGroupId)`— así que
  /// reutilizarlo haría que elegir una plantilla cambiara en silencio las filas
  /// de la tabla, añadiendo o quitando rondas. Dos significados, dos campos.
  /// Pueden apuntar al mismo grupo, y eso es normal; lo que no puede es que uno
  /// mueva al otro.
  final String? plantillaId;

  /// La ventaja de las rondas del torneo. Null = sin decidir, se pregunta.
  final VentajaDeTorneo? ventaja;

  /// El campo, si el torneo lo fija. Null = se pregunta cada jornada.
  ///
  /// Opcional a propósito, y con eso caben los dos modelos sin bandera de modo:
  /// en una liga el campo varía por jornada y se deja vacío; en un shotgun es
  /// uno para todos y puesto aquí desaparece la pregunta. [preguntasPendientes]
  /// ya calcula lo que queda por preguntar, así que la pantalla de arranque se
  /// acorta sola.
  final CourseInfo? campo;

  /// Si el torneo está cerrado y liquidado.
  ///
  /// Cerrado no significa "pagado" —la app no procesa pagos— significa que la
  /// tabla ya no va a cambiar y el reparto es el definitivo.
  final bool cerrado;

  const Torneo({
    required this.id,
    required this.nombre,
    this.emoji = 'trofeo',
    this.identidad = const IdentidadDeTorneo(),
    this.fuente = FuenteDeRondas.marcadas,
    this.roundIds = const [],
    this.desde,
    this.hasta,
    this.bettingGroupId,
    this.metodo = MetodoDePuntuacion.posicion,
    this.puntosPorPuesto = const [10, 6, 4, 2, 1],
    this.empate = ReglaDeEmpate.reparten,
    this.acumulacion = Acumulacion.sumaSimple,
    this.mejoresN = 10,
    this.participantes = const [],
    this.minimoRondas = 0,
    this.bote = BoteConfig.def,
    this.tokenCompartido,
    this.publicadoEn,
    this.tokenTele,
    this.teleDesde,
    this.inventario = const InventarioProyectado(),
    this.cerrado = false,
    this.formato = FormatoDeTorneo.liga,
    this.siembra = const [],
    this.desempates = const {},
    this.plantillaId,
    this.ventaja,
    this.campo,
  });

  Torneo copyWith({
    String? nombre,
    String? emoji,
    IdentidadDeTorneo? identidad,
    FuenteDeRondas? fuente,
    List<String>? roundIds,
    DateTime? desde,
    DateTime? hasta,
    bool limpiarDesde = false,
    bool limpiarHasta = false,
    String? bettingGroupId,
    MetodoDePuntuacion? metodo,
    List<int>? puntosPorPuesto,
    ReglaDeEmpate? empate,
    Acumulacion? acumulacion,
    int? mejoresN,
    List<String>? participantes,
    int? minimoRondas,
    BoteConfig? bote,
    String? tokenCompartido,
    DateTime? publicadoEn,
    bool limpiarCompartido = false,
    String? tokenTele,
    DateTime? teleDesde,
    InventarioProyectado? inventario,
    /// Apaga la pantalla SIN perder el token, igual que [limpiarCompartido]
    /// conserva el suyo: el enlace de la tele se le dio al del club, y
    /// obligarle a pedir otro cada vez que se apaga no es apagar, es romper.
    bool apagarTele = false,
    bool? cerrado,
    FormatoDeTorneo? formato,
    List<String>? siembra,
    Map<String, String>? desempates,
    String? plantillaId,
    VentajaDeTorneo? ventaja,
    CourseInfo? campo,
    bool limpiarPlantilla = false,
    bool limpiarVentaja = false,
    bool limpiarCampo = false,
  }) =>
      Torneo(
        id: id,
        nombre: nombre ?? this.nombre,
        emoji: emoji ?? this.emoji,
        identidad: identidad ?? this.identidad,
        fuente: fuente ?? this.fuente,
        roundIds: roundIds ?? this.roundIds,
        desde: limpiarDesde ? null : (desde ?? this.desde),
        hasta: limpiarHasta ? null : (hasta ?? this.hasta),
        bettingGroupId: bettingGroupId ?? this.bettingGroupId,
        metodo: metodo ?? this.metodo,
        puntosPorPuesto: puntosPorPuesto ?? this.puntosPorPuesto,
        empate: empate ?? this.empate,
        acumulacion: acumulacion ?? this.acumulacion,
        mejoresN: mejoresN ?? this.mejoresN,
        participantes: participantes ?? this.participantes,
        minimoRondas: minimoRondas ?? this.minimoRondas,
        bote: bote ?? this.bote,
        tokenCompartido:
            limpiarCompartido ? null : (tokenCompartido ?? this.tokenCompartido),
        publicadoEn:
            limpiarCompartido ? null : (publicadoEn ?? this.publicadoEn),
        tokenTele: limpiarCompartido ? null : (tokenTele ?? this.tokenTele),
        teleDesde: (limpiarCompartido || apagarTele)
            ? null
            : (teleDesde ?? this.teleDesde),
        inventario: inventario ?? this.inventario,
        cerrado: cerrado ?? this.cerrado,
        formato: formato ?? this.formato,
        siembra: siembra ?? this.siembra,
        desempates: desempates ?? this.desempates,
        plantillaId:
            limpiarPlantilla ? null : (plantillaId ?? this.plantillaId),
        ventaja: limpiarVentaja ? null : (ventaja ?? this.ventaja),
        campo: limpiarCampo ? null : (campo ?? this.campo),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'emoji': emoji,
        if (!identidad.vacia) 'identidad': identidad.toJson(),
        'fuente': fuente.name,
        if (roundIds.isNotEmpty) 'roundIds': roundIds,
        if (desde != null) 'desde': desde!.toIso8601String(),
        if (hasta != null) 'hasta': hasta!.toIso8601String(),
        if (bettingGroupId != null) 'bettingGroupId': bettingGroupId,
        'metodo': metodo.name,
        'puntosPorPuesto': puntosPorPuesto,
        'empate': empate.name,
        'acumulacion': acumulacion.name,
        'mejoresN': mejoresN,
        if (participantes.isNotEmpty) 'participantes': participantes,
        if (minimoRondas > 0) 'minimoRondas': minimoRondas,
        if (bote.hayAlgunBote) 'bote': bote.toJson(),
        if (tokenCompartido != null) 'tokenCompartido': tokenCompartido,
        if (publicadoEn != null) 'publicadoEn': publicadoEn!.toIso8601String(),
        if (tokenTele != null) 'tokenTele': tokenTele,
        if (teleDesde != null) 'teleDesde': teleDesde!.toIso8601String(),
        if (!inventario.vacio) 'inventario': inventario.toJson(),
        if (cerrado) 'cerrado': true,
        // Aditivos: solo se escriben cuando hay algo que decir, así que un
        // torneo de liga guardado hoy se lee igual que ayer.
        if (formato != FormatoDeTorneo.liga) 'formato': formato.name,
        if (siembra.isNotEmpty) 'siembra': siembra,
        if (desempates.isNotEmpty) 'desempates': desempates,
        if (plantillaId != null) 'plantillaId': plantillaId,
        if (ventaja != null) 'ventaja': ventaja!.name,
        if (campo != null) 'campo': campo!.toJson(),
      };

  factory Torneo.fromJson(Map<String, dynamic> j) => Torneo(
        id: (j['id'] as String?) ?? '',
        nombre: (j['nombre'] as String?) ?? 'Torneo',
        emoji: (j['emoji'] as String?) ?? 'trofeo',
        identidad: j['identidad'] is Map
            ? IdentidadDeTorneo.fromJson(
                Map<String, dynamic>.from(j['identidad'] as Map))
            : const IdentidadDeTorneo(),
        fuente: FuenteDeRondas.values.firstWhere((f) => f.name == j['fuente'],
            orElse: () => FuenteDeRondas.marcadas),
        roundIds:
            ((j['roundIds'] as List?) ?? const []).map((e) => '$e').toList(),
        desde: DateTime.tryParse((j['desde'] as String?) ?? ''),
        hasta: DateTime.tryParse((j['hasta'] as String?) ?? ''),
        bettingGroupId: j['bettingGroupId'] as String?,
        metodo: MetodoDePuntuacion.values.firstWhere(
            (m) => m.name == j['metodo'],
            orElse: () => MetodoDePuntuacion.posicion),
        puntosPorPuesto: ((j['puntosPorPuesto'] as List?) ?? const [10, 6, 4, 2, 1])
            .map((e) => (e as num).toInt())
            .toList(),
        empate: ReglaDeEmpate.values.firstWhere((e) => e.name == j['empate'],
            orElse: () => ReglaDeEmpate.reparten),
        acumulacion: Acumulacion.values.firstWhere(
            (a) => a.name == j['acumulacion'],
            orElse: () => Acumulacion.sumaSimple),
        mejoresN: (j['mejoresN'] as num?)?.toInt() ?? 10,
        participantes: ((j['participantes'] as List?) ?? const [])
            .map((e) => '$e')
            .toList(),
        minimoRondas: (j['minimoRondas'] as num?)?.toInt() ?? 0,
        bote: j['bote'] == null
            ? BoteConfig.def
            : BoteConfig.fromJson(Map<String, dynamic>.from(j['bote'] as Map)),
        plantillaId: j['plantillaId'] as String?,
        ventaja: j['ventaja'] == null
            ? null
            : VentajaDeTorneo.values
                .firstWhere((v) => v.name == j['ventaja'], orElse: () => VentajaDeTorneo.handicap),
        // `is Map` y no `!= null`: es la misma familia del "holes: 3" que tiró
        // el buscador de campos. Un campo malformado deja el torneo sin campo,
        // no ilegible.
        campo: j['campo'] is Map
            ? CourseInfo.fromJson(Map<String, dynamic>.from(j['campo'] as Map))
            : null,
        tokenCompartido: j['tokenCompartido'] as String?,
        tokenTele: j['tokenTele'] as String?,
        teleDesde: j['teleDesde'] == null
            ? null
            : DateTime.tryParse(j['teleDesde'] as String),
        inventario: j['inventario'] is Map
            ? InventarioProyectado.fromJson(
                Map<String, dynamic>.from(j['inventario'] as Map))
            : const InventarioProyectado(),
        publicadoEn: DateTime.tryParse((j['publicadoEn'] as String?) ?? ''),
        cerrado: j['cerrado'] == true,
        formato: FormatoDeTorneo.values.firstWhere(
            (f) => f.name == j['formato'],
            orElse: () => FormatoDeTorneo.liga),
        siembra:
            ((j['siembra'] as List?) ?? const []).map((e) => '$e').toList(),
        desempates: ((j['desempates'] as Map?) ?? const {})
            .map((k, v) => MapEntry('$k', '$v')),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// LA TABLA — derivada, nunca guardada
// ─────────────────────────────────────────────────────────────────────────────

/// Lo que un jugador sacó en UNA ronda del torneo.
class RondaDelTorneo {
  final String roundId;
  final String nombreRonda;
  final DateTime fecha;

  /// El dato bruto del método elegido: dinero, score neto, puntos Stableford, o
  /// el puesto si se puntúa por posición.
  final double medida;

  /// Los puntos del torneo que dio esta ronda.
  final double puntos;

  /// El puesto en la ronda. Null si el método no ordena por puesto.
  final int? puesto;

  /// True si esta ronda entra en el total. Con "mejores N" las peores no.
  final bool cuenta;

  /// El par de los hoyos que esta ronda jugó. Null si la ronda es anterior a
  /// que se guardara — ver [RoundResult.parDeLaRonda].
  final int? par;

  const RondaDelTorneo({
    required this.roundId,
    required this.nombreRonda,
    required this.fecha,
    required this.medida,
    required this.puntos,
    required this.puesto,
    required this.cuenta,
    this.par,
  });
}

/// Una fila de la tabla.
class FilaDelTorneo {
  final String playerId;
  final String nombre;

  /// Las rondas que jugó, más recientes primero.
  final List<RondaDelTorneo> rondas;

  /// La suma de las que cuentan.
  final double total;

  /// El par acumulado de las rondas que CUENTAN, para restarlo del total.
  ///
  /// Null si alguna de las que cuentan no lo trae: un par a medias daría un
  /// "bajo par" que no es el de nadie, y un número plausible que sustituye a
  /// uno que falta es el fallo más caro que tiene este proyecto. O están todas
  /// o no hay columna.
  final int? parDeLasQueCuentan;

  /// Cuántas jugó, y cuántas suman.
  int get jugadas => rondas.length;
  int get contadas => rondas.where((r) => r.cuenta).length;

  /// Puesto en la tabla. 1 es el primero; empatados comparten puesto.
  final int puesto;

  /// True si no llega al mínimo de rondas y sale aparte.
  final bool bajoMinimo;

  const FilaDelTorneo({
    required this.playerId,
    required this.nombre,
    required this.rondas,
    this.parDeLasQueCuentan,
    required this.total,
    required this.puesto,
    required this.bajoMinimo,
  });
}

/// La tabla completa, con lo que hay que poder decir en pantalla.
class TablaDelTorneo {
  /// Clasificados, en orden.
  final List<FilaDelTorneo> filas;

  /// Los que no llegan al mínimo. Se enseñan aparte en vez de esconderse: quien
  /// jugó dos rondas quiere ver sus dos rondas.
  final List<FilaDelTorneo> bajoMinimo;

  /// Cuántas rondas entran en el torneo.
  final int rondas;

  /// True si el torneo NO tiene lista de participantes.
  ///
  /// Con la lista vacía la tabla enseña a todo el que jugó —los resultados son
  /// útiles— pero el bote no se calcula. Verlo es lo que empuja a definirla.
  final bool sinListaDeParticipantes;

  /// Inscritos que todavía no han jugado ninguna ronda del torneo.
  ///
  /// Salen en la tabla con cero rondas: estar inscrito es un hecho aunque no
  /// hayas ido, y no verte en la lista después de poner el bote sería raro.
  final List<String> inscritosSinJugar;

  /// Nombres que aparecen con MÁS DE UN id: nombre → los ids.
  ///
  /// Pasa de verdad y afectaría a cualquier torneo real: si alguien creó a
  /// "Rafa" a mano en una ronda y en otra usó el Rafa del directorio, son dos
  /// ids y la temporada lo cuenta como dos personas.
  ///
  /// Se DETECTA y se dice; no se fusiona. Agrupar por nombre sería peligroso
  /// —dos personas pueden llamarse igual y quedarían sumadas en una fila sin que
  /// nadie lo pidiera— y decidir que son la misma persona toca el directorio,
  /// que no es cosa de una tabla de torneo. Las dos filas siguen ahí, marcadas.
  final Map<String, List<String>> nombresDuplicados;

  /// Rondas que el método NO pudo puntuar por falta de dato.
  ///
  /// Pasa con "por score neto" y "por Stableford" en rondas cerradas antes de
  /// que RoundResult guardara el score. Se dice en vez de dar una tabla corta
  /// por buena — es el mismo criterio que el conejo suelto y la serpiente que
  /// nadie agarró.
  final int rondasSinDato;

  const TablaDelTorneo({
    required this.filas,
    required this.bajoMinimo,
    required this.rondas,
    required this.rondasSinDato,
    this.nombresDuplicados = const {},
    this.sinListaDeParticipantes = false,
    this.inscritosSinJugar = const [],
  });

  /// Cuántos jugadores distintos aparecen, clasifiquen o no.
  ///
  /// Lo consume el aviso del editor: una fuente por fechas puede arrastrar
  /// decenas de personas de rondas viejas, y el bote se calcularía sobre todas.
  int get jugadores => filas.length + bajoMinimo.length;

  bool get vacia => filas.isEmpty && bajoMinimo.isEmpty;
}

/// Las rondas de [resultados] que entran en [t].
///
/// Pura: se le pasan todos los resultados y filtra. Así la misma función sirve
/// para la tabla, para el contador de la tarjeta y para los tests.
List<RoundResult> rondasDelTorneo(Torneo t, List<RoundResult> resultados) {
  bool enRango(RoundResult r) {
    if (t.desde != null && r.playedAt.isBefore(t.desde!)) return false;
    // El "hasta" incluye el día entero: un torneo "hasta el 30 de noviembre" no
    // puede dejar fuera la ronda de esa mañana.
    if (t.hasta != null &&
        r.playedAt.isAfter(
            DateTime(t.hasta!.year, t.hasta!.month, t.hasta!.day, 23, 59, 59))) {
      return false;
    }
    return true;
  }

  return switch (t.fuente) {
    // La marca vive en la RONDA, puesta al configurarla. Así el torneo no tiene
    // que adivinar nada: pregunta quién dijo que contaba.
    FuenteDeRondas.marcadas =>
      resultados.where((r) => r.torneoIds.contains(t.id)).toList(),
    FuenteDeRondas.manual =>
      resultados.where((r) => t.roundIds.contains(r.roundId)).toList(),
    FuenteDeRondas.rango => resultados.where(enRango).toList(),
    FuenteDeRondas.grupo => resultados
        .where((r) =>
            t.bettingGroupId != null &&
            r.bettingGroupIds.contains(t.bettingGroupId) &&
            enRango(r))
        .toList(),
  };
}

/// La tabla del torneo.
///
/// [nombres] permite resolver el nombre actual de cada jugador; si no viene se
/// usa el que guardó la ronda, que es el nombre del día.
TablaDelTorneo tablaDe(
  Torneo t,
  List<RoundResult> resultados, {
  Map<String, String> nombres = const {},
}) {
  final inscritos = t.participantes.toSet();

  final rondas = rondasDelTorneo(t, resultados)
    ..sort((a, b) => b.playedAt.compareTo(a.playedAt));

  // Lo acumulado por jugador, ronda a ronda.
  final porJugador = <String, List<RondaDelTorneo>>{};
  final nombreDe = <String, String>{};
  var sinDato = 0;

  for (final r in rondas) {
    final medidas = _medidasDe(t.metodo, r);
    if (medidas.isEmpty) {
      sinDato++;
      continue;
    }

    // El orden de la ronda, para el puesto y para la puntuación por posición.
    final orden = medidas.keys.toList()
      ..sort((a, b) => t.metodo.masEsMejor
          ? medidas[b]!.compareTo(medidas[a]!)
          : medidas[a]!.compareTo(medidas[b]!));

    // Puestos con empates: los que tienen la misma medida comparten puesto.
    final puestoDe = <String, int>{};
    final empatadosCon = <String, List<String>>{};
    var i = 0;
    while (i < orden.length) {
      final grupo = <String>[orden[i]];
      var j = i + 1;
      while (j < orden.length && medidas[orden[j]] == medidas[orden[i]]) {
        grupo.add(orden[j]);
        j++;
      }
      for (final pid in grupo) {
        puestoDe[pid] = i + 1;
        empatadosCon[pid] = grupo;
      }
      i = j;
    }

    for (final pid in orden) {
      // Solo los INSCRITOS. Con la lista vacía entra todo el que jugó, que es el
      // estado heredado y se marca para poder decirlo.
      if (inscritos.isNotEmpty && !inscritos.contains(pid)) continue;
      nombreDe[pid] = nombres[pid] ?? r.playerNames[pid] ?? sinNombre;
      final puesto = puestoDe[pid]!;
      final puntos = t.metodo == MetodoDePuntuacion.posicion
          ? _puntosDelPuesto(t, puesto, empatadosCon[pid]!.length)
          : medidas[pid]!;
      (porJugador[pid] ??= []).add(RondaDelTorneo(
        roundId: r.roundId,
        nombreRonda: r.roundName,
        fecha: r.playedAt,
        medida: medidas[pid]!,
        puntos: puntos,
        puesto: puesto,
        cuenta: true, // se decide abajo, con todas las rondas del jugador
        par: r.parDeLaRonda,
      ));
    }
  }

  // Ahora sí: qué rondas cuentan para cada jugador.
  final filas = <FilaDelTorneo>[];
  for (final entrada in porJugador.entries) {
    final suyas = entrada.value;
    final marcadas = _marcarLasQueCuentan(t, suyas);
    final total = marcadas
        .where((x) => x.cuenta)
        .fold(0.0, (s, x) => s + x.puntos);
    // El par de las que cuentan: entero o nada. Ver parDeLasQueCuentan.
    final cuentan = marcadas.where((x) => x.cuenta).toList();
    final par = cuentan.isEmpty || cuentan.any((x) => x.par == null)
        ? null
        : cuentan.fold<int>(0, (acc, x) => acc + x.par!);
    filas.add(FilaDelTorneo(
      playerId: entrada.key,
      nombre: nombreDe[entrada.key] ?? sinNombre,
      rondas: marcadas,
      total: _redondea(total),
      parDeLasQueCuentan: par,
      puesto: 0, // se asigna al ordenar
      bajoMinimo: marcadas.length < t.minimoRondas,
    ));
  }

  // Los inscritos que no han jugado ninguna: estar inscrito es un hecho aunque
  // no hayas ido, y no verte en la lista después de poner el bote sería raro.
  final sinJugar = <String>[];
  for (final pid in t.participantes) {
    if (porJugador.containsKey(pid)) continue;
    sinJugar.add(pid);
    filas.add(FilaDelTorneo(
      playerId: pid,
      // El inscrito que no ha jugado NINGUNA ronda no tiene nombre en ningún
      // RoundResult, así que sale del directorio o no sale. Antes caía al id y
      // la tarjeta enseñaba "Va 6uX3jmCVlYNxCJxWBJQe": un id de Firestore en la
      // primera pantalla dice "esto está a medias" más alto que nada.
      nombre: nombres[pid] ?? sinNombre,
      rondas: const [],
      total: 0,
      puesto: 0,
      // Con mínimo 0 clasifica igual; con mínimo, no. Es coherente: no ha
      // jugado nada.
      bajoMinimo: t.minimoRondas > 0,
    ));
  }

  // Va ANTES de ordenar y de partir clasificados/fuera. Estaba después, y esas
  // filas no llegaban a la salida: el inscrito que no había jugado desaparecía.
  // El orden de la TABLA. Con score neto, menos es mejor.
  filas.sort((a, b) => t.metodo.masEsMejor
      ? b.total.compareTo(a.total)
      : a.total.compareTo(b.total));

  final clasificados = filas.where((f) => !f.bajoMinimo).toList();
  final fuera = filas.where((f) => f.bajoMinimo).toList();

  // Nombres con más de un id. Se calcula al final, con todos los que salieron.
  final porNombre = <String, Set<String>>{};
  for (final f in filas) {
    (porNombre[f.nombre] ??= {}).add(f.playerId);
  }
  final duplicados = {
    for (final e in porNombre.entries)
      if (e.value.length > 1) e.key: e.value.toList()..sort(),
  };

  return TablaDelTorneo(
    filas: _conPuestos(clasificados),
    bajoMinimo: _conPuestos(fuera),
    rondas: rondas.length - sinDato,
    rondasSinDato: sinDato,
    nombresDuplicados: duplicados,
    sinListaDeParticipantes: t.participantes.isEmpty,
    inscritosSinJugar: sinJugar,
  );
}

/// La medida de cada jugador en una ronda, según el método. Vacío si la ronda no
/// tiene el dato que ese método necesita.
Map<String, double> _medidasDe(MetodoDePuntuacion m, RoundResult r) {
  switch (m) {
    case MetodoDePuntuacion.dinero:
      return {for (final p in r.playerIds) p: r.netoDe(p)};
    case MetodoDePuntuacion.posicion:
      // La posición se decide por el DINERO de la ronda: es el resultado que la
      // ronda produjo, y el único que existe en todas. Puntuar "por posición"
      // con otro criterio sería otro método.
      return {for (final p in r.playerIds) p: r.netoDe(p)};
    case MetodoDePuntuacion.scoreNeto:
      if (r.netByPlayer.isEmpty) return const {};
      return {
        for (final e in r.netByPlayer.entries) e.key: e.value.toDouble(),
      };
    case MetodoDePuntuacion.stableford:
      if (r.stablefordByPlayer.isEmpty) return const {};
      return {
        for (final e in r.stablefordByPlayer.entries) e.key: e.value.toDouble(),
      };
  }
}

/// Los puntos que le tocan a un puesto, con [empatados] compartiéndolo.
double _puntosDelPuesto(Torneo t, int puesto, int empatados) {
  double delPuesto(int p) =>
      p >= 1 && p <= t.puntosPorPuesto.length
          ? t.puntosPorPuesto[p - 1].toDouble()
          : 0.0;

  if (empatados <= 1) return delPuesto(puesto);

  return switch (t.empate) {
    // Se reparten los puntos de las posiciones que ocupan. Es lo estándar y lo
    // único que conserva el total de puntos que la ronda reparte.
    ReglaDeEmpate.reparten => () {
        var suma = 0.0;
        for (var p = puesto; p < puesto + empatados; p++) {
          suma += delPuesto(p);
        }
        return _redondea(suma / empatados);
      }(),
    ReglaDeEmpate.mejorPuesto => delPuesto(puesto),
    ReglaDeEmpate.peorPuesto => delPuesto(puesto + empatados - 1),
  };
}

/// Marca qué rondas suman.
///
/// Con "mejores N" se ordenan por puntos y solo las N primeras cuentan. Es la
/// diferencia que resuelve el problema real: sumar premia al que más juega, no
/// al que mejor juega.
List<RondaDelTorneo> _marcarLasQueCuentan(
    Torneo t, List<RondaDelTorneo> suyas) {
  if (t.acumulacion == Acumulacion.sumaSimple) return suyas;

  final ordenadas = suyas.toList()
    ..sort((a, b) => t.metodo.masEsMejor
        ? b.puntos.compareTo(a.puntos)
        : a.puntos.compareTo(b.puntos));
  final cuentan = ordenadas.take(t.mejoresN).map((r) => r.roundId).toSet();

  // Se devuelven en el orden original —por fecha— con la marca puesta: la tabla
  // quiere contar la temporada, no el ranking interno de cada jugador.
  return [
    for (final r in suyas)
      RondaDelTorneo(
        roundId: r.roundId,
        nombreRonda: r.nombreRonda,
        fecha: r.fecha,
        medida: r.medida,
        puntos: r.puntos,
        puesto: r.puesto,
        cuenta: cuentan.contains(r.roundId),
        // Sin esto el par se pierde justo aquí, al reconstruir la ronda para
        // ponerle la marca: la columna quedaría vacía solo con "mejores N".
        par: r.par,
      ),
  ];
}

/// Asigna puestos, compartiéndolos entre empatados.
List<FilaDelTorneo> _conPuestos(List<FilaDelTorneo> filas) {
  final salida = <FilaDelTorneo>[];
  var i = 0;
  while (i < filas.length) {
    var j = i + 1;
    while (j < filas.length && filas[j].total == filas[i].total) {
      j++;
    }
    for (var k = i; k < j; k++) {
      salida.add(FilaDelTorneo(
        playerId: filas[k].playerId,
        nombre: filas[k].nombre,
        rondas: filas[k].rondas,
        total: filas[k].total,
        // Segunda reconstrucción que se comía el par —la otra estaba en
        // _marcarLasQueCuentan—. Reconstruir un objeto campo a campo pierde
        // en silencio todo lo que se añada después, y aquí el síntoma habría
        // sido una columna que nunca aparece.
        parDeLasQueCuentan: filas[k].parDeLasQueCuentan,
        puesto: i + 1,
        bajoMinimo: filas[k].bajoMinimo,
      ));
    }
    i = j;
  }
  return salida;
}

double _redondea(double v) => (v * 100).round() / 100;

// ─────────────────────────────────────────────────────────────────────────────
// COMBINACIONES QUE NO TIENEN SENTIDO
//
// Cuatro decisiones con varias opciones cada una son muchas combinaciones, y
// algunas no significan nada. No se dejan elegibles y rotas: se atenúan con su
// motivo, igual que en el paso de qué se juega.
// ─────────────────────────────────────────────────────────────────────────────

/// Por qué [acumulacion] no aplica a un torneo de [rondas] rondas. Null si sí.
String? motivoSinAcumulacion(Acumulacion a, int rondas) {
  if (a != Acumulacion.mejoresDeN) return null;
  if (rondas <= 1) {
    return 'Con una sola ronda no hay mejores que elegir: la única cuenta.';
  }
  return null;
}

/// Por qué [metodo] no se puede usar con estas rondas. Null si sí.
///
/// El caso real: las rondas cerradas ANTES de que se guardara el score no tienen
/// el dato, así que puntuar por score neto o por Stableford las dejaría fuera.
/// Se dice al elegir, no al ver la tabla corta.
String? motivoSinMetodo(
    MetodoDePuntuacion metodo, List<RoundResult> rondas) {
  if (!metodo.necesitaScore) return null;
  if (rondas.isEmpty) return null;
  final con = rondas
      .where((r) => metodo == MetodoDePuntuacion.stableford
          ? r.stablefordByPlayer.isNotEmpty
          : r.netByPlayer.isNotEmpty)
      .length;
  if (con == rondas.length) return null;
  if (con == 0) {
    return 'Ninguna de las ${rondas.length} rondas tiene el score guardado. '
        'Se guarda al cerrar desde ahora; para las de antes, recalcula el '
        'histórico en el Historial.';
  }
  return 'Solo $con de ${rondas.length} rondas tienen el score guardado. '
      'Recalcula el histórico en el Historial para incluir las demás.';
}

/// El mínimo de rondas no puede pedir más de las que hay.
String? motivoSinMinimo(int minimo, int rondas) =>
    minimo > rondas
        ? 'El torneo tiene $rondas rondas: con un mínimo de $minimo nadie '
            'saldría en la tabla.'
        : null;

// ─────────────────────────────────────────────────────────────────────────────
// EL BOTE
//
// ══════════════════════════════════════════════════════════════════════════════
// LA APP NO PROCESA PAGOS. NUNCA.
//
// El bote es CONTABILIDAD, exactamente igual que las apuestas de cada ronda: la
// app lleva la cuenta de quién puso qué y a quién le toca cobrar, y el dinero se
// mueve entre las personas fuera de aquí.
//
// Y no es una limitación técnica que alguien pueda "arreglar" más adelante: es la
// línea que separa "llevar la cuenta entre amigos" de "facilitar apuestas con
// dinero real". La segunda cosa cambia lo que la app ES —para las tiendas de
// aplicaciones y para la ley— así que si algún día alguien propone cobrar la
// entrada desde la app, la respuesta está aquí y es no.
//
// Consecuencia de diseño, no accidente: no hay estado "pagado", no hay pasarela,
// no hay saldo. Hay una cuenta.
// ══════════════════════════════════════════════════════════════════════════════

/// Cómo se reparte el bote.
enum RepartoDelBote {
  /// El primero se lo lleva todo.
  ganadorTodo,

  /// Los tres primeros, con porcentajes configurables.
  podio,
}

extension RepartoLabel on RepartoDelBote {
  String get label => switch (this) {
        RepartoDelBote.ganadorTodo => 'El primero se lo lleva todo',
        RepartoDelBote.podio => 'Los tres primeros',
      };
}

/// Qué pasa con la entrada de quien no llega al mínimo de rondas.
///
/// Es una decisión DEL GRUPO, así que va configurable. El default es el más
/// común en ligas, y se dice al configurar el mínimo en vez de descubrirse en
/// noviembre.
enum EntradaSinMinimo {
  /// Se queda en el bote y engorda el premio de los que sí clasificaron.
  pierde,

  /// Se le devuelve: si no clasifica, no juega el bote.
  ///
  /// Es el DEFAULT, y por lo que se vio con datos reales: con "pierde", subir el
  /// mínimo no acota el bote —los que no clasifican siguen aportando— así que un
  /// torneo con la fuente mal acotada daba una cifra que nadie puso.
  devolver,

  /// Aporta en proporción a las rondas que jugó, y le vuelve el resto.
  prorratear,
}

extension EntradaSinMinimoLabel on EntradaSinMinimo {
  String get label => switch (this) {
        EntradaSinMinimo.pierde => 'Se queda en el bote',
        EntradaSinMinimo.devolver => 'Se le devuelve',
        EntradaSinMinimo.prorratear => 'Aporta lo proporcional',
      };

  String get descripcion => switch (this) {
        EntradaSinMinimo.pierde =>
          'Su entrada engorda el premio de los que sí clasificaron. Es lo más '
              'común en ligas.',
        EntradaSinMinimo.devolver =>
          'Si no clasifica no juega el bote y su dinero vuelve. El premio final '
              'es menor que el que se ve durante la temporada.',
        EntradaSinMinimo.prorratear =>
          'Puso por toda la temporada y jugó una parte: aporta esa parte y le '
              'vuelve el resto.',
      };
}

class BoteConfig {
  // ── DOS BOTES, DOS ENTRADAS ───────────────────────────────────────────────
  //
  // El de temporada y el del día son dinero distinto y se financian por
  // separado: pones lo del día cuando juegas y lo de la temporada al empezar.
  //
  // Se descartó la entrada única repartida entre los dos. Es más difícil de
  // explicar —"de tus $500, $200 van al bote del día y $300 al final"— y no se
  // parece a cómo se juega: quien falta tres sábados no puso el bote de esos
  // tres días, y con una entrada única sí lo habría puesto.
  //
  // Y no se suman en ninguna cifra. El del día está COBRADO —esa ronda ya se
  // cerró— y el final es una EXPECTATIVA mientras el torneo esté abierto. Es el
  // mismo criterio que separa el bote de las apuestas de ronda, un nivel más
  // adentro.

  /// Lo que pone cada jugador por la TEMPORADA. 0 = sin bote final.
  final double entrada;

  final RepartoDelBote reparto;

  /// Lo que pone cada jugador POR RONDA que juegue. 0 = sin bote del día.
  final double entradaPorJornada;

  /// Cómo se reparte el bote del día. Puede ser distinto del final.
  final RepartoDelBote repartoJornada;

  /// Porcentajes del podio. Deben sumar 100; si no, se normalizan al calcular.
  final List<int> porcentajes;

  final EntradaSinMinimo sinMinimo;

  const BoteConfig({
    this.entrada = 0,
    this.reparto = RepartoDelBote.ganadorTodo,
    this.entradaPorJornada = 0,
    this.repartoJornada = RepartoDelBote.ganadorTodo,
    this.porcentajes = const [60, 30, 10],
    // ── Por qué el default cambió a "devolver" ──────────────────────────────
    //
    // Era "pierde", y con datos reales salió el problema: una fuente por fechas
    // arrastró ochenta rondas de prueba, la tabla se llenó de 55 personas y el
    // bote dio $27500 — una cifra que nadie puso encima de la mesa. Con
    // "pierde", subir el mínimo NO arregla el número: los 50 que no clasifican
    // siguen aportando.
    //
    // "Devolver" implementa exactamente "quien no clasifica tampoco puso", que
    // es la lectura correcta: el bote a repartir es el de los que compiten por
    // él. Sigue habiendo las otras dos opciones para el grupo que las quiera.
    this.sinMinimo = EntradaSinMinimo.devolver,
  });

  static const def = BoteConfig();

  bool get hayBote => entrada > 0;
  bool get hayBoteJornada => entradaPorJornada > 0;
  bool get hayAlgunBote => hayBote || hayBoteJornada;

  BoteConfig copyWith({
    double? entrada,
    RepartoDelBote? reparto,
    double? entradaPorJornada,
    RepartoDelBote? repartoJornada,
    List<int>? porcentajes,
    EntradaSinMinimo? sinMinimo,
  }) =>
      BoteConfig(
        entrada: entrada ?? this.entrada,
        reparto: reparto ?? this.reparto,
        entradaPorJornada: entradaPorJornada ?? this.entradaPorJornada,
        repartoJornada: repartoJornada ?? this.repartoJornada,
        porcentajes: porcentajes ?? this.porcentajes,
        sinMinimo: sinMinimo ?? this.sinMinimo,
      );

  Map<String, dynamic> toJson() => {
        'entrada': entrada,
        'reparto': reparto.name,
        if (hayBoteJornada) 'entradaPorJornada': entradaPorJornada,
        if (hayBoteJornada) 'repartoJornada': repartoJornada.name,
        if (reparto == RepartoDelBote.podio ||
            repartoJornada == RepartoDelBote.podio)
          'porcentajes': porcentajes,
        // Se escribe lo que se aparta del default, que ahora es devolver.
        if (sinMinimo != EntradaSinMinimo.devolver) 'sinMinimo': sinMinimo.name,
      };

  factory BoteConfig.fromJson(Map<String, dynamic> j) => BoteConfig(
        entrada: (j['entrada'] as num?)?.toDouble() ?? 0,
        reparto: RepartoDelBote.values.firstWhere(
            (r) => r.name == j['reparto'],
            orElse: () => RepartoDelBote.ganadorTodo),
        entradaPorJornada: (j['entradaPorJornada'] as num?)?.toDouble() ?? 0,
        repartoJornada: RepartoDelBote.values.firstWhere(
            (r) => r.name == j['repartoJornada'],
            orElse: () => RepartoDelBote.ganadorTodo),
        porcentajes: ((j['porcentajes'] as List?) ?? const [60, 30, 10])
            .map((e) => (e as num).toInt())
            .toList(),
        sinMinimo: EntradaSinMinimo.values.firstWhere(
            (s) => s.name == j['sinMinimo'],
            orElse: () => EntradaSinMinimo.devolver),
      );
}

/// Lo que un jugador pone y cobra del bote.
class LineaDelBote {
  final String playerId;
  final String nombre;

  /// Lo que aporta al bote.
  final double aporta;

  /// Lo que se le devuelve sin jugar.
  final double devuelto;

  /// Lo que cobra del reparto.
  final double cobra;

  /// Su puesto en la tabla, o null si no clasificó.
  final int? puesto;

  const LineaDelBote({
    required this.playerId,
    required this.nombre,
    required this.aporta,
    required this.devuelto,
    required this.cobra,
    required this.puesto,
  });

  /// El neto del bote para esta persona. Positivo, sale ganando.
  double get neto => cobra + devuelto - (aporta + devuelto);

  /// Lo que de verdad queda: cobra menos lo que puso de su bolsillo.
  double get saldo => cobra - aporta;
}

/// El bote resuelto.
class BoteDelTorneo {
  /// Lo que hay en el bote, ya descontado lo devuelto.
  final double total;

  /// Lo que entró en bruto, antes de devoluciones.
  final double recaudado;

  final List<LineaDelBote> lineas;

  /// True si el torneo está cerrado y el reparto es definitivo.
  final bool cerrado;

  /// Por qué el reparto todavía no es definitivo. Null si lo es.
  final String? provisional;

  const BoteDelTorneo({
    required this.total,
    required this.recaudado,
    required this.lineas,
    required this.cerrado,
    required this.provisional,
  });

  bool get hayBote => recaudado > 0;
}

/// Resuelve el bote de [t] con la [tabla] ya calculada.
///
/// Puro, como la tabla: no se guarda nada. Y no se mezcla con el balance de las
/// rondas — el bote es una expectativa mientras el torneo está abierto, y el
/// dinero de un sábado ya está cobrado. Sumarlos daría una cifra que no
/// significa nada.
/// El bote del torneo.
///
/// [campeon] solo se usa con [FormatoDeTorneo.eliminacion], y ahí manda sobre la
/// tabla: en un cuadro el premio es del que gana la final, no del que más dinero
/// acumuló por el camino. Sin él, un bote de eliminación pagaba al líder de la
/// tabla —una cifra correcta a nombre de la persona equivocada—.
///
/// Mientras no haya campeón nadie cobra, igual que con cero rondas jugadas: el
/// bote existe porque pusieron; el ganador, todavía no.
BoteDelTorneo boteDe(Torneo t, TablaDelTorneo tabla, {String? campeon}) {
  final cfg = t.bote;
  final todos = [...tabla.filas, ...tabla.bajoMinimo];

  // Sin lista de participantes no hay bote. Apuntar dinero a nombre de quien no
  // dijo que entraba es exactamente el fallo que la lista arregla, y calcularlo
  // "de mientras" lo dejaría a la vista como si fuera cierto.
  if (tabla.sinListaDeParticipantes || !cfg.hayBote || todos.isEmpty) {
    return BoteDelTorneo(
      total: 0, recaudado: 0, lineas: const [], cerrado: t.cerrado,
      provisional: null,
    );
  }

  final recaudado = cfg.entrada * todos.length;

  // Cuánto aporta cada uno de los que no clasificaron.
  double aportaDe(FilaDelTorneo f) {
    if (!f.bajoMinimo) return cfg.entrada;
    return switch (cfg.sinMinimo) {
      EntradaSinMinimo.pierde => cfg.entrada,
      EntradaSinMinimo.devolver => 0,
      // Proporcional a las rondas que jugó sobre las del torneo. Con cero
      // rondas en el torneo no se divide por cero.
      EntradaSinMinimo.prorratear => tabla.rondas == 0
          ? 0
          : _redondea(cfg.entrada * (f.jugadas / tabla.rondas)
              .clamp(0.0, 1.0)),
    };
  }

  final aportes = {for (final f in todos) f.playerId: aportaDe(f)};
  final total = _redondea(aportes.values.fold(0.0, (s, v) => s + v));

  // El reparto, solo entre los clasificados.
  //
  // Con CERO rondas jugadas no hay reparto. Matemáticamente todos empatan a 0 y
  // la regla de empate les devolvería su entrada a cada uno —consistente— pero
  // enseñar "cobra $100" cuando no se ha jugado nada dice que pasó algo que no
  // pasó. El bote existe porque pusieron; el ganador, todavía no.
  final cobra = <String, double>{};
  if (t.formato == FormatoDeTorneo.eliminacion) {
    // El cuadro decide, no la tabla. Y no se reparte por puestos: en una
    // eliminación no hay podio que repartir, hay un campeón.
    if (campeon != null && total > 0) cobra[campeon] = total;
  } else if (tabla.rondas > 0 && tabla.filas.isNotEmpty && total > 0) {
    final porcentajes = cfg.reparto == RepartoDelBote.ganadorTodo
        ? <int>[100]
        : cfg.porcentajes;
    // Se normaliza: unos porcentajes que no suman 100 repartirían más o menos
    // dinero del que hay, y eso no puede pasar con un bote.
    final suma = porcentajes.fold(0, (s, v) => s + v);
    if (suma > 0) {
      // Los premios por PUESTO, no por posición en la lista: los empatados
      // comparten puesto y se reparten sus premios, igual que los puntos.
      final porPuesto = <int, double>{};
      for (var i = 0; i < porcentajes.length; i++) {
        porPuesto[i + 1] = total * porcentajes[i] / suma;
      }
      // Agrupar por puesto.
      final porPuestoJugadores = <int, List<String>>{};
      for (final f in tabla.filas) {
        (porPuestoJugadores[f.puesto] ??= []).add(f.playerId);
      }
      for (final entrada in porPuestoJugadores.entries) {
        final puesto = entrada.key;
        final empatados = entrada.value;
        // Los premios de los puestos que este grupo de empatados ocupa.
        var premio = 0.0;
        for (var p = puesto; p < puesto + empatados.length; p++) {
          premio += porPuesto[p] ?? 0;
        }
        if (premio <= 0) continue;
        final cada = _redondea(premio / empatados.length);
        for (final pid in empatados) {
          cobra[pid] = cada;
        }
      }
    }
  }

  final lineas = [
    for (final f in todos)
      LineaDelBote(
        playerId: f.playerId,
        nombre: f.nombre,
        aporta: aportes[f.playerId] ?? 0,
        devuelto: _redondea(cfg.entrada - (aportes[f.playerId] ?? 0)),
        cobra: cobra[f.playerId] ?? 0,
        puesto: f.bajoMinimo ? null : f.puesto,
      ),
  ];

  return BoteDelTorneo(
    total: total,
    recaudado: _redondea(recaudado),
    lineas: lineas,
    cerrado: t.cerrado,
    // Mientras el torneo esté abierto el reparto puede cambiar con la siguiente
    // ronda. Decirlo es la diferencia entre una cuenta y una promesa.
    provisional: t.cerrado
        ? null
        : t.formato == FormatoDeTorneo.eliminacion
            ? (campeon == null
                // Sin campeón no hay a quién pagarle, y decirlo es la diferencia
                // entre una cuenta y una promesa.
                ? 'El cuadro no ha terminado: el bote se lo lleva quien gane la '
                    'final.'
                : 'El cuadro ya tiene campeón. Ciérralo para dejar el reparto '
                    'fijo.')
            : 'El torneo está abierto: el reparto cambia con cada ronda que '
                'entre. Ciérralo cuando la temporada acabe para dejarlo fijo.',
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// EL BOTE DE LA JORNADA
//
// Cada ronda tiene el suyo: pones al jugar y lo cobra quien gana ESE día. Se
// liquida al cerrar la ronda, así que cuando lo ves ya está cobrado — y esa es
// la diferencia con el final, que es una expectativa mientras el torneo esté
// abierto.
//
// LOS DOS NO SE SUMAN EN NINGUNA CIFRA. Es el mismo criterio que separa el bote
// de las apuestas de ronda, un nivel más adentro: mezclar dinero cobrado con
// dinero esperado da un número que no significa nada.
//
// Y NO entra en el balance de la ronda. El ledger de una ronda es lo que liquidó
// el motor de apuestas; el bote del torneo es contabilidad por encima. Meterlo
// ahí lo colaría en RoundResult.balances y de ahí al balance histórico del
// tablero, rompiendo la separación que existe justo para esto. Se enseña en el
// torneo, marcado como cobrado.
// ─────────────────────────────────────────────────────────────────────────────

/// El bote de UNA ronda del torneo.
class BoteDeJornada {
  final String roundId;
  final String nombreRonda;
  final DateTime fecha;

  /// Cuántos jugaron esa ronda y pusieron.
  final int jugadores;

  /// Lo que hay: entrada × jugadores.
  final double total;

  /// Quién cobra, y cuánto cada uno. Vacío si el día quedó sin ganador.
  final Map<String, double> cobran;

  /// Nombres, para no resolverlos otra vez en pantalla.
  final Map<String, String> nombres;

  const BoteDeJornada({
    required this.roundId,
    required this.nombreRonda,
    required this.fecha,
    required this.jugadores,
    required this.total,
    required this.cobran,
    required this.nombres,
  });

  /// Lo que puso cada uno.
  double get entrada => jugadores == 0 ? 0 : total / jugadores;
}

/// Los botes de cada jornada, derivados de la tabla ya calculada.
///
/// Se saca de [TablaDelTorneo] y no de un segundo recorrido de las rondas: los
/// puestos de cada día ya están ahí. Un segundo cálculo podría discrepar del
/// primero, y sería el mismo error que dos recorridos independientes sobre los
/// mismos datos.
List<BoteDeJornada> botesPorJornada(Torneo t, TablaDelTorneo tabla) {
  final cfg = t.bote;
  // Mismo criterio que el bote final: sin lista de inscritos no se apunta
  // dinero de nadie.
  if (tabla.sinListaDeParticipantes || !cfg.hayBoteJornada) return const [];

  // Quién jugó cada ronda y en qué puesto quedó, desde las filas de la tabla.
  // Entran TODOS los que jugaron ese día, clasifiquen o no en la temporada: el
  // bote del día es del día, y el mínimo es una regla de la temporada.
  final porRonda = <String, List<({String pid, String nombre, int puesto})>>{};
  final datos = <String, ({String nombre, DateTime fecha})>{};
  for (final fila in [...tabla.filas, ...tabla.bajoMinimo]) {
    for (final r in fila.rondas) {
      (porRonda[r.roundId] ??= []).add(
          (pid: fila.playerId, nombre: fila.nombre, puesto: r.puesto ?? 1));
      datos[r.roundId] = (nombre: r.nombreRonda, fecha: r.fecha);
    }
  }

  final salida = <BoteDeJornada>[];
  for (final entrada in porRonda.entries) {
    final jugadores = entrada.value;
    if (jugadores.isEmpty) continue;
    final total = _redondea(cfg.entradaPorJornada * jugadores.length);

    // Los premios del día, por PUESTO, con los empatados repartiendo el suyo.
    final porcentajes = cfg.repartoJornada == RepartoDelBote.ganadorTodo
        ? <int>[100]
        : cfg.porcentajes;
    final suma = porcentajes.fold(0, (s, v) => s + v);
    final cobran = <String, double>{};
    if (suma > 0 && total > 0) {
      final premioDelPuesto = <int, double>{
        for (var i = 0; i < porcentajes.length; i++)
          i + 1: total * porcentajes[i] / suma,
      };
      final porPuesto = <int, List<String>>{};
      for (final j in jugadores) {
        (porPuesto[j.puesto] ??= []).add(j.pid);
      }
      for (final grupo in porPuesto.entries) {
        var premio = 0.0;
        for (var p = grupo.key; p < grupo.key + grupo.value.length; p++) {
          premio += premioDelPuesto[p] ?? 0;
        }
        if (premio <= 0) continue;
        final cada = _redondea(premio / grupo.value.length);
        for (final pid in grupo.value) {
          cobran[pid] = cada;
        }
      }
    }

    salida.add(BoteDeJornada(
      roundId: entrada.key,
      nombreRonda: datos[entrada.key]?.nombre ?? 'Ronda',
      fecha: datos[entrada.key]?.fecha ?? DateTime(2000),
      jugadores: jugadores.length,
      total: total,
      cobran: cobran,
      nombres: {for (final j in jugadores) j.pid: j.nombre},
    ));
  }

  salida.sort((a, b) => b.fecha.compareTo(a.fecha));
  return salida;
}

/// Lo que un jugador lleva ganado o perdido EN LOS BOTES DE JORNADA.
///
/// Es dinero ya cobrado, y por eso va aparte del bote final: sumarlos daría una
/// cifra mitad hecho mitad promesa.
double saldoDeJornadas(String pid, List<BoteDeJornada> jornadas) {
  var saldo = 0.0;
  for (final j in jornadas) {
    if (!j.nombres.containsKey(pid)) continue;
    saldo += (j.cobran[pid] ?? 0) - j.entrada;
  }
  return _redondea(saldo);
}

// ─────────────────────────────────────────────────────────────────────────────
// EL AVISO DEL EDITOR
//
// Salió de usarlo con datos reales: una fuente por fechas arrastró ochenta
// rondas de prueba, la tabla se llenó de 55 personas y el bote dio $27500 — una
// cifra que nadie puso encima de la mesa.
//
// El campo del mínimo existe justo para eso y estaba en 0. Lo que faltaba era
// DECIRLO CON EL NÚMERO antes de guardar, en vez de descubrirlo en la tabla. Es
// el mismo criterio del resto de la app.
// ─────────────────────────────────────────────────────────────────────────────

/// Por qué falta la lista de participantes, si falta. Null si está.
///
/// Con la lista vacía la tabla enseña resultados pero el bote no se calcula, y
/// eso hay que decirlo con el número: "entran 55" es lo que hace evidente que el
/// torneo no es lo que se creía.
String? motivoSinLista(Torneo t, TablaDelTorneo tabla) {
  if (!tabla.sinListaDeParticipantes) return null;
  final n = tabla.jugadores;
  return 'Este torneo no tiene lista de participantes, así que entra cualquiera '
      'que haya jugado una ronda de la fuente: ahora mismo $n '
      '${n == 1 ? 'persona' : 'personas'}.'
      '${t.bote.hayAlgunBote ? ' El bote no se calcula hasta que la definas: '
          'apuntar dinero a nombre de quien no dijo que entraba sería peor que '
          'no apuntarlo.' : ''}';
}

/// A quién proponer como participante, según la fuente.
///
/// Es una PROPUESTA, no la lista: el organizador ajusta. Con fuente de grupo
/// salen sus habituales —los que se inscribirían— y con las demás, quien haya
/// jugado, que es lo único que se sabe.
List<String> participantesPropuestos(
  Torneo t,
  List<RoundResult> resultados, {
  List<String> habitualesDelGrupo = const [],
}) {
  if (t.fuente == FuenteDeRondas.grupo && habitualesDelGrupo.isNotEmpty) {
    return List.of(habitualesDelGrupo);
  }
  final vistos = <String>{};
  for (final r in rondasDelTorneo(t, resultados)) {
    vistos.addAll(r.playerIds);
  }
  return vistos.toList()..sort();
}

/// Aviso si la configuración arrastra más gente de la que parece. Null si no.
///
/// [umbral] es a partir de cuántos jugadores conviene decirlo. Ocho es una
/// partida grande; más que eso en un torneo casi siempre significa que la fuente
/// está cogiendo rondas que no son de este grupo.
String? avisoDeArrastre(Torneo t, TablaDelTorneo tabla, {int umbral = 8}) {
  // Solo la fuente retirada arrastra. Con marca, con lista manual o con grupo el
  // número lo decide el organizador.
  if (t.fuente != FuenteDeRondas.rango) return null;
  if (!tabla.sinListaDeParticipantes) return null;
  if (tabla.jugadores <= umbral) return null;

  final bote = t.bote.hayBote
      ? ' El bote final saldría de '
          '\$${(t.bote.entrada * tabla.filas.length).toStringAsFixed(0)}.'
      : '';

  return '${tabla.jugadores} jugadores entran con esta configuración, de '
      '${tabla.rondas} rondas.$bote '
      'Si esperabas menos, la fuente está cogiendo rondas de otros grupos: '
      'acótala por fechas, elige el grupo, o sube el mínimo de rondas.';
}

// ══════════════════════════════════════════════════════════════════════════════
// REPUBLICAR AL CERRAR — qué enlaces quedan viejos cuando termina una ronda
// ══════════════════════════════════════════════════════════════════════════════
//
// Publicar sigue siendo una ACCIÓN: nadie crea un enlace sin querer. Lo que se
// automatiza es solo REFRESCAR uno que ya existe, porque es justo lo que nadie
// se acuerda de hacer. Un torneo compartido cuya última ronda no aparece es
// peor que no compartirlo: la gente lee una tabla que ya no es la tabla.
//
// Función pura y con nombre, para que la condición se pueda probar sin Firestore
// —y para que no se repita en los tres sitios que cierran una ronda—.
//
/// Los torneos cuyo enlace hay que volver a publicar tras cerrar [round].
///
/// Tres condiciones, y las tres importan:
///
///   · la ronda lo MARCÓ           → si no cuenta, la tabla no cambió
///   · el torneo ya tiene enlace   → refrescar, nunca crear
///   · el torneo no está cerrado    → una instantánea final es final
///
/// La fuente tiene que ser [FuenteDeRondas.marcadas]: en las demás la marca no
/// la mira nadie, así que cerrar la ronda no mueve la clasificación.
List<Torneo> torneosARepublicar(Round round, List<Torneo> torneos) => torneos
    .where((t) =>
        t.tokenCompartido != null &&
        !t.cerrado &&
        t.fuente == FuenteDeRondas.marcadas &&
        round.torneoIds.contains(t.id))
    .toList();

/// Los torneos cuya PANTALLA hay que refrescar tras cerrar [round].
///
/// ── Por qué es una lista aparte y no la misma ────────────────────────────────
///
/// Empezó dentro del bucle de arriba, que es lo cómodo: mismo disparador, misma
/// ronda. Pero ese bucle exige `tokenCompartido != null`, así que la pantalla de
/// la casa club solo se refrescaba si además el enlace de WhatsApp seguía vivo
/// —dos superficies independientes atadas por un `where` que no las nombra—.
///
/// Y la que se quedaba vieja en silencio era la peor de las dos: el enlace de
/// WhatsApp lo abre alguien que ve la fecha de la copia; la pantalla del club
/// está proyectada en una pared y nadie comprueba nada.
///
/// Así que cada superficie decide por su cuenta. Lo único que comparten es el
/// disparador: una ronda de este torneo acaba de cerrarse.
List<Torneo> torneosConTeleARefrescar(Round round, List<Torneo> torneos) =>
    torneos
        .where((t) =>
            t.teleEncendida &&
            !t.cerrado &&
            t.fuente == FuenteDeRondas.marcadas &&
            round.torneoIds.contains(t.id))
        .toList();

/// Si cerrar [round] tiene que mover algo hacia fuera: un enlace, una pantalla,
/// o los dos.
///
/// Existe como función y no como un `&&` dentro del cierre porque ese `&&` ya
/// se equivocó una vez. Miraba solo los enlaces —lo natural cuando solo había
/// enlaces— y con la pantalla añadida se comía el bucle entero de la tele: un
/// torneo con la pantalla encendida y el enlace apagado cerraba rondas todo el
/// día sin que la pared se enterara.
///
/// Aquí se puede probar. Dentro de un método de pantalla que necesita sesión,
/// no.
bool hayQueRefrescarAlgo(Round round, List<Torneo> torneos) =>
    torneosARepublicar(round, torneos).isNotEmpty ||
    torneosConTeleARefrescar(round, torneos).isNotEmpty;

/// Los torneos que se pueden marcar al configurar una ronda.
///
/// Uno cerrado no admite rondas nuevas, y uno con otra fuente no mira la marca
/// —ofrecerlo sería un control que no hace nada—. Si la lista sale vacía, el
/// bloque entero no aparece en el asistente.
List<Torneo> torneosMarcables(List<Torneo> torneos) => torneos
    .where((t) => !t.cerrado && t.fuente == FuenteDeRondas.marcadas)
    .toList();

// ══════════════════════════════════════════════════════════════════════════════
// LA LLAVE — eliminación directa, derivada de las rondas marcadas
// ══════════════════════════════════════════════════════════════════════════════
//
// Lo único que se guarda es la SIEMBRA: quién se cruza con quién al empezar. El
// resto —quién pasó, quién juega la semifinal, quién es campeón— se calcula aquí
// cada vez. Es la misma regla que la tabla, y por el mismo motivo: un cuadro
// guardado resuelto dejaría un campeón viejo cuando se corrija una ronda.
//
// Cómo se resuelve un partido, y por qué así:
//
//   · Los dos juegan LA MISMA ronda. No hay que cuadrar dos tarjetas de días
//     distintos ni decidir qué hacer si uno jugó un campo más fácil.
//   · Gana quien va mejor según el MÉTODO del torneo, el que ya existe. Por eso
//     Stableford deja de ser un caso especial: es un método, no un formato.
//   · Una ronda de cuatro puede resolver DOS partidos a la vez. Es el caso
//     normal entre amigos, y sale gratis: cada partido lee sus dos jugadores.
//   · Un partido solo lo puede decidir una ronda jugada DESPUÉS de las que
//     clasificaron a los dos. Sin esto, una ronda antigua entre dos que se
//     cruzan en la final resolvería la final antes de las semis.
//   · Si empatan, el partido se queda SIN RESOLVER y se ve. La app no puede
//     jugar un hoyo 19; el desempate lo pone una persona.
//
// Y lo que no se hace: elegir la ronda "más favorable", promediar varias, o
// inventar un criterio de desempate. Las tres serían reglas que nadie pactó.

/// Una cifra del torneo con su signo, para pantalla.
///
/// Vive aquí y no en una pantalla porque la usan la tabla, el cuadro y la vista
/// de invitado: tres copias de esto habrían acabado dando tres formatos.
String importeDelTorneo(double v) {
  final s = v.abs().toStringAsFixed(v == v.roundToDouble() ? 0 : 1);
  if (v > 0.005) return '+$s';
  if (v < -0.005) return '−$s';
  return '0';
}

// ══════════════════════════════════════════════════════════════════════════════
// QUÉ APLICA A CADA FORMATO — una sola fuente, no un `if` por pantalla
// ══════════════════════════════════════════════════════════════════════════════
//
// El editor enseñaba "puntos por puesto", "si dos empatan en una ronda", "cómo se
// acumula" y "cuántas rondas para optar al premio" con eliminación marcada. Ni una
// aplica a un cuadro: ganas el partido y pasas, no acumulas nada, no hay puesto y
// no hay mínimo que valga.
//
// Es el mismo patrón que ya se cerró varias veces en esta app: una superficie que
// no se enteró de que hay dos formatos. La lógica estaba en el paso 1 y las
// secciones siguientes no la consultaban. Así que la respuesta no es un `if` por
// sección —eso es lo que se rompe la próxima vez— sino una tabla que se pueda
// probar y que la pantalla consulte.

/// Cada cosa que se configura en un torneo.
enum SeccionDelTorneo {
  formato,
  siembra,
  fuente,
  participantes,
  metodo,

  /// La tabla de puntos por puesto. Sin puesto no hay puntos por puesto.
  puntosPorPuesto,

  /// Qué pasa si dos empatan EN UNA RONDA. En un cuadro el empate de un partido
  /// lo resuelve una persona, y eso ya vive en el cuadro.
  empateEnRonda,

  /// Suma simple o mejores N.
  acumulacion,

  /// El mínimo de rondas para optar al premio.
  minimoRondas,

  bote,
  botePorJornada,
}

/// Si [s] significa algo en [f].
///
/// Lo que se oculta NO se borra: el valor guardado sigue ahí y volver a liga lo
/// devuelve entero. Esconder es distinto de reescribir, y reescribir la
/// configuración de alguien porque cambió una opción es peor que enseñar un
/// control de más.
bool aplicaEnFormato(SeccionDelTorneo s, FormatoDeTorneo f) =>
    switch (f) {
      FormatoDeTorneo.liga => s != SeccionDelTorneo.siembra,
      FormatoDeTorneo.eliminacion => switch (s) {
          // Fuera: un cuadro no acumula, no tiene puestos y no tiene mínimo.
          SeccionDelTorneo.puntosPorPuesto => false,
          SeccionDelTorneo.empateEnRonda => false,
          SeccionDelTorneo.acumulacion => false,
          SeccionDelTorneo.minimoRondas => false,
          // Se queda: decide QUIÉN GANA EL PARTIDO, que es lo único que hay que
          // decidir. Y el bote se queda porque el dinero cuenta igual.
          _ => true,
        },
    };

/// Los métodos que se pueden elegir con [f].
///
/// En un cuadro no se ofrece "por posición": entre dos personas el puesto lo
/// decide el dinero de la ronda —es literalmente lo que calcula— así que ofrecerlo
/// sería un nombre distinto para la misma cosa, y encima el peor de los dos.
List<MetodoDePuntuacion> metodosOfrecidos(FormatoDeTorneo f) =>
    f == FormatoDeTorneo.eliminacion
        ? MetodoDePuntuacion.values
            .where((m) => m != MetodoDePuntuacion.posicion)
            .toList()
        : MetodoDePuntuacion.values;

/// El método con el que de verdad se resuelve este torneo.
///
/// Se DERIVA en vez de reescribirse al guardar. Un torneo de eliminación con
/// "por posición" guardado —los que se crearon antes de esta corrección— se
/// resuelve por dinero, que es lo que ese método calcula en un duelo, y se
/// enseña con ese nombre. Sin migración, sin tocar el documento y sin que ninguna
/// pantalla diga "Por posición" de un cuadro.
MetodoDePuntuacion metodoEfectivo(Torneo t) =>
    t.formato == FormatoDeTorneo.eliminacion &&
            t.metodo == MetodoDePuntuacion.posicion
        ? MetodoDePuntuacion.dinero
        : t.metodo;

/// La clave con la que se guarda un desempate: los dos ids, ordenados.
///
/// Ordenados a propósito, para que dé igual quién sea A y quién sea B: un mismo
/// partido tiene una sola clave, la reordene el cuadro como quiera.
String parKey(String a, String b) => ([a, b]..sort()).join('|');

/// Un partido del cuadro.
class Enfrentamiento {
  /// 0 = primera ronda del cuadro.
  final int ronda;

  /// Índice dentro de su ronda, de arriba abajo.
  final int posicion;

  /// Los dos lados. Null = plaza todavía por decidir.
  final String? a;
  final String? b;

  /// Quién pasa. Null si aún no está resuelto.
  final String? ganador;

  /// Pasa sin jugar porque le tocó bye.
  final bool bye;

  /// Jugaron y quedaron iguales. Hace falta que alguien lo decida.
  final bool empatado;

  /// El desempate lo puso una persona, no el resultado.
  final bool desempatadoAMano;

  /// La ronda que lo resolvió, y cuándo. Para poder decir POR QUÉ pasó.
  final String? roundId;
  final String? roundName;
  final DateTime? cuando;

  /// Lo que sacó cada uno en esa ronda, con el método del torneo.
  final double? medidaA;
  final double? medidaB;

  const Enfrentamiento({
    required this.ronda,
    required this.posicion,
    this.a,
    this.b,
    this.ganador,
    this.bye = false,
    this.empatado = false,
    this.desempatadoAMano = false,
    this.roundId,
    this.roundName,
    this.cuando,
    this.medidaA,
    this.medidaB,
  });

  /// Los dos están puestos y todavía no hay resultado: se puede jugar ya.
  bool get jugable => a != null && b != null && ganador == null && !empatado;

  /// Falta que alguien acabe su partido anterior.
  bool get esperando => (a == null || b == null) && !bye;

  /// Quién queda fuera. Null mientras no haya ganador.
  String? get perdedor => ganador == null
      ? null
      : ganador == a
          ? b
          : a;
}

/// El cuadro resuelto hasta donde las rondas jugadas permiten.
class LlaveDelTorneo {
  /// Los partidos por ronda: `rondas[0]` es la primera, la última es la final.
  final List<List<Enfrentamiento>> rondas;

  /// Quién ganó la final. Null mientras no se juegue.
  final String? campeon;

  /// Plazas del cuadro: 2, 4, 8, 16… Con byes es mayor que los inscritos.
  final int plazas;

  /// Cuántos pasan sin jugar la primera ronda.
  final int byes;

  /// Por qué no hay cuadro, si no lo hay.
  final String? motivo;

  const LlaveDelTorneo({
    this.rondas = const [],
    this.campeon,
    this.plazas = 0,
    this.byes = 0,
    this.motivo,
  });

  bool get vacia => rondas.isEmpty;

  /// Los partidos que se pueden jugar ya. Es lo que la pantalla enseña arriba:
  /// un cuadro entero es difícil de leer, y "a quién te toca" es la pregunta.
  List<Enfrentamiento> get jugables =>
      rondas.expand((r) => r).where((e) => e.jugable).toList();

  /// Los que esperan que alguien decida un empate.
  List<Enfrentamiento> get pendientesDeDesempate =>
      rondas.expand((r) => r).where((e) => e.empatado).toList();
}

/// El nombre de una ronda del cuadro, contando desde el final.
///
/// Se nombra por lo que FALTA, que es como se llaman de verdad: la ronda con dos
/// partidos es la semifinal, tenga el cuadro ocho plazas o treinta y dos.
String nombreDeRondaDeLlave(int partidos) => switch (partidos) {
      1 => 'Final',
      2 => 'Semifinales',
      4 => 'Cuartos de final',
      8 => 'Octavos de final',
      16 => 'Dieciseisavos',
      _ => 'Ronda de ${partidos * 2}',
    };

/// El orden estándar de siembra para un cuadro de [plazas].
///
/// Devuelve los NÚMEROS de sembrado por hueco: para ocho, `[1,8,4,5,2,7,3,6]`.
/// Así el 1 y el 2 solo se cruzan en la final, que es para lo que sirve sembrar.
/// Se genera en vez de escribirse a mano para que valga con cualquier tamaño.
List<int> ordenDeSiembra(int plazas) {
  var orden = <int>[1];
  var tam = 1;
  while (tam < plazas) {
    tam *= 2;
    orden = [
      for (final s in orden) ...[s, tam + 1 - s],
    ];
  }
  return orden;
}

/// El cuadro del torneo, resuelto con las rondas que ya se jugaron.
LlaveDelTorneo llaveDe(Torneo t, List<RoundResult> resultados) {
  if (t.formato != FormatoDeTorneo.eliminacion) {
    return const LlaveDelTorneo(motivo: 'Este torneo es una liga, no un cuadro.');
  }

  // La siembra manda; sin ella, el orden de la lista de inscritos. Un cuadro no
  // puede armarse con quien no se inscribió: es la misma decisión que el bote.
  final base = t.siembra.isNotEmpty
      ? t.siembra.where(t.participantes.contains).toList()
      : t.participantes;
  final plazasReales = base.length;

  if (plazasReales < 2) {
    return LlaveDelTorneo(
        motivo: t.participantes.isEmpty
            ? 'Define primero los participantes: un cuadro se arma con quien se '
                'inscribió, no con quien juegue.'
            : 'Hacen falta al menos dos inscritos para un cuadro.');
  }

  var plazas = 2;
  while (plazas < plazasReales) {
    plazas *= 2;
  }
  final byes = plazas - plazasReales;

  // Los huecos de la primera ronda, en orden de siembra. El sembrado que se sale
  // de los inscritos queda vacío, y eso ES el bye del de enfrente.
  final huecos = ordenDeSiembra(plazas)
      .map((s) => s <= plazasReales ? base[s - 1] : null)
      .toList();

  // Solo las rondas del torneo, y en orden. La fuente ya decide cuáles cuentan
  // —con marcas, desde la fase A— así que aquí no se vuelve a decidir.
  // El método EFECTIVO: un cuadro guardado con "por posición" se resuelve por
  // dinero, que es lo que ese método calcula entre dos personas.
  final metodo = metodoEfectivo(t);

  final rondas = rondasDelTorneo(t, resultados)
    ..sort((x, y) => x.playedAt.compareTo(y.playedAt));

  // Desde cuándo cada jugador está clasificado. Un partido no se puede resolver
  // con una ronda anterior a la que metió a los dos en él.
  final listoDesde = <String, DateTime>{};
  // Qué rondas ya gastó cada jugador. Una ronda de cuatro resuelve DOS partidos
  // —A contra B, C contra D— y eso está bien; lo que no puede es resolver
  // también la semifinal entre A y C, porque ese golf ya se jugó. Sin esto, un
  // cuadro de cuatro amigos en una sola ronda se resolvía entero de una vez.
  //
  // Va por jugador y no por ronda porque el criterio es el jugador: dos partidos
  // que no comparten a nadie sí pueden salir de la misma tarjeta.
  final usadas = <String, Set<String>>{};
  final salida = <List<Enfrentamiento>>[];

  var actual = huecos;
  var nivel = 0;

  while (actual.length >= 2) {
    final partidos = <Enfrentamiento>[];
    final siguiente = <String?>[];

    for (var i = 0; i < actual.length; i += 2) {
      final a = actual[i];
      final b = actual[i + 1];
      final pos = i ~/ 2;

      // Bye: uno de los dos huecos NO EXISTE, así que el otro pasa sin jugar.
      //
      // Solo en la primera ronda. Es la distinción que se me escapó: en la ronda
      // 0 un hueco vacío significa "ese sembrado no existe" —un bye de verdad—
      // pero en una ronda posterior significa "todavía no se sabe quién viene".
      // Tratarlo igual hacía que, con una semifinal sin jugar, el otro finalista
      // pasara a campeón sin jugar la final.
      if (nivel == 0 && (a == null) != (b == null)) {
        final pasa = a ?? b;
        partidos.add(Enfrentamiento(
            ronda: nivel, posicion: pos, a: a, b: b, ganador: pasa, bye: true));
        siguiente.add(pasa);
        continue;
      }

      // Todavía no se sabe quién viene. Se enseña vacío, que es información.
      if (a == null || b == null) {
        partidos.add(Enfrentamiento(ronda: nivel, posicion: pos, a: a, b: b));
        siguiente.add(null);
        continue;
      }

      final desde = [listoDesde[a], listoDesde[b]]
          .whereType<DateTime>()
          .fold<DateTime?>(null, (m, d) => m == null || d.isAfter(m) ? d : m);

      RoundResult? decide;
      Map<String, double> medidas = const {};
      for (final r in rondas) {
        if (!r.playerIds.contains(a) || !r.playerIds.contains(b)) continue;
        if (desde != null && r.playedAt.isBefore(desde)) continue;
        // Ninguno de los dos puede haber gastado ya esta ronda en un partido
        // anterior del cuadro. La fecha no basta: se juegan dos el mismo día.
        if ((usadas[a]?.contains(r.roundId) ?? false) ||
            (usadas[b]?.contains(r.roundId) ?? false)) {
          continue;
        }
        final m = _medidasDe(metodo, r);
        if (!m.containsKey(a) || !m.containsKey(b)) continue;
        decide = r;
        medidas = m;
        break; // La PRIMERA vez que se cruzan. Un partido se juega una vez.
      }

      if (decide == null) {
        partidos.add(Enfrentamiento(ronda: nivel, posicion: pos, a: a, b: b));
        siguiente.add(null);
        continue;
      }

      final ma = medidas[a]!;
      final mb = medidas[b]!;
      String? gana;
      var empatado = false;
      var aMano = false;
      if (ma == mb) {
        // Empataron. Solo pasa quien el organizador diga, y si no ha dicho nada
        // el partido se queda a la vista sin resolver.
        gana = t.desempates[parKey(a, b)];
        if (gana != a && gana != b) gana = null;
        empatado = gana == null;
        aMano = gana != null;
      } else {
        gana = (metodo.masEsMejor ? ma > mb : ma < mb) ? a : b;
      }

      partidos.add(Enfrentamiento(
        ronda: nivel,
        posicion: pos,
        a: a,
        b: b,
        ganador: gana,
        empatado: empatado,
        desempatadoAMano: aMano,
        roundId: decide.roundId,
        roundName: decide.roundName,
        cuando: decide.playedAt,
        medidaA: ma,
        medidaB: mb,
      ));
      siguiente.add(gana);
      (usadas[a] ??= {}).add(decide.roundId);
      (usadas[b] ??= {}).add(decide.roundId);
      if (gana != null) listoDesde[gana] = decide.playedAt;
    }

    salida.add(partidos);
    actual = siguiente;
    nivel++;
  }

  return LlaveDelTorneo(
    rondas: salida,
    campeon: salida.isEmpty ? null : salida.last.first.ganador,
    plazas: plazas,
    byes: byes,
  );
}

/// En qué punto está el cuadro, en una línea.
///
/// La tarjeta de la lista resumía un cuadro como si fuera una liga —"0 rondas ·
/// Por posición"— cuando en eliminación no hay rondas acumuladas ni posición: hay
/// partidos. Lo que hace falta saber de un vistazo es a quién le toca, o quién
/// ganó.
///
/// El orden importa: lo que BLOQUEA va primero. Un empate sin resolver detiene el
/// cuadro entero, así que se dice antes que el partido que se puede jugar.
String resumenDeLlave(LlaveDelTorneo llave, Map<String, String> nombres) {
  String nom(String? pid) =>
      pid == null ? sinNombre : (nombres[pid] ?? sinNombre);

  if (llave.vacia) return 'Cuadro sin armar';

  if (llave.pendientesDeDesempate.isNotEmpty) {
    final e = llave.pendientesDeDesempate.first;
    final mas = llave.pendientesDeDesempate.length - 1;
    return 'Hay que desempatar: ${nom(e.a)} y ${nom(e.b)}'
        '${mas > 0 ? ' · y $mas más' : ''}';
  }

  if (llave.campeon != null) return 'Campeón: ${nom(llave.campeon)}';

  final jugables = llave.jugables;
  if (jugables.isNotEmpty) {
    final e = jugables.first;
    final fase = nombreDeRondaDeLlave(llave.rondas[e.ronda].length);
    final mas = jugables.length - 1;
    return '$fase · ${nom(e.a)} vs ${nom(e.b)}'
        '${mas > 0 ? ' · y $mas partido${mas == 1 ? '' : 's'} más' : ''}';
  }

  // Ni campeón, ni empates, ni nada jugable: todo espera que alguien acabe.
  return '${llave.plazas} plazas · esperando resultados';
}

/// Los resultados publicados que SÍ cuentan para [t].
///
/// ══════════════════════════════════════════════════════════════════════════
/// LA GARANTÍA ESTÁ REPARTIDA EN DOS SITIOS. ESTE ES UNO DE LOS DOS.
/// ══════════════════════════════════════════════════════════════════════════
///
/// La regla de Firestore comprueba que quien publica firma con su uid y que el
/// organizador que declara es el del enlace. Lo que NO puede comprobar es que
/// JUGÓ esa ronda: la ronda de una liga no es una ronda en vivo, así que no hay
/// documento compartido donde mirarlo.
///
/// Eso se cierra AQUÍ, en la lectura, donde sí está la lista de inscritos. Cuenta
/// el resultado si quien lo escribió está inscrito; con la lista vacía no cuenta
/// ninguno —sin saber quién entra, aceptar lo que llegue es peor que no aceptar
/// nada, y es el mismo criterio que el bote—.
///
/// ── Por qué está anotado en los DOS lados ────────────────────────────────
///
/// Es la lección de _BetInfo.all aplicada a seguridad. Allí el catálogo de tipos
/// vivía duplicado sin que ninguna de las copias dijera que la otra existía, y se
/// quedó vieja en silencio. Aquí el riesgo es peor: quien lea la REGLA puede
/// pensar "esto ya valida la procedencia" y quitar este filtro; quien lea ESTE
/// filtro puede pensar "la regla ya lo hace" y quitarlo.
///
/// Ninguno de los dos lados es redundante. Quitar cualquiera deja que alguien con
/// el enlace meta una fila inventada en la tabla de otro. Está dicho en firestore
/// .rules —bloque torneoResultados— y está dicho aquí, y las dos notas se nombran
/// la una a la otra a propósito.
/// ── EL PUENTE ES EL NOMBRE, y esto costó un fallo entero ──────────────────
///
/// La primera versión comparaba `escritoPor` contra [Torneo.participantes]. Son
/// ESPACIOS DE IDS DISTINTOS: escritoPor es un uid de cuenta —currentUser.uid— y
/// los participantes son ids de jugador del directorio del organizador. Un uid no
/// puede ser igual a un id de jugador NUNCA, así que el filtro descartaba TODO, y
/// en silencio: la tabla contaba cero rondas publicadas y parecía que nadie había
/// jugado.
///
/// Y no hay id compartido entre las dos partes: el organizador inscribe jugadores
/// de SU directorio, y quien llega por el enlace tiene su propia cuenta. Lo único
/// que las dos partes comparten es el NOMBRE, que es justo para lo que se
/// inventó "elegir tu jugador": el invitado se señala en la lista del organizador.
///
/// Así que el resultado publicado declara QUÉ NOMBRE de la lista reclama su autor,
/// y aquí se compara contra los nombres de los inscritos. [nombres] es id de
/// jugador → nombre, que el organizador resuelve con su directorio.
///
/// Se compara normalizado —sin acentos ni mayúsculas— por lo mismo que la
/// importación: es lo único que las dos partes escriben a mano.
/// Un resultado publicado por alguien que sigue el torneo.
///
/// Clase y no registro porque [jugadorId] es opcional —los resultados publicados
/// antes de que existiera no lo traen— y un registro obliga a rellenar todos sus
/// campos en cada sitio que lo construye, incluidos los tests.
class ResultadoPublicado {
  /// El nombre de la lista del organizador que su autor reclama.
  final String jugadorNombre;

  /// El id que ESA PERSONA usa para sí misma dentro de su propia ronda.
  ///
  /// ── Por qué hace falta, y por qué no lo vio ningún test ───────────────────
  ///
  /// El nombre reclamado dice QUIÉN publica. No dice cuál de los jugadores de la
  /// ronda es. Y hacen falta las dos cosas, porque los ids de la ronda son del
  /// directorio de su autor y los inscritos son del directorio del organizador:
  /// sin traducir, la tabla suma sobre ids que no reconoce y le da cero a todo
  /// el mundo. Contando la ronda, eso sí — "1 ronda" arriba y nadie con nada.
  ///
  /// Los tests de agregación no lo cazaron porque modelaban al seguidor con los
  /// ids DEL ORGANIZADOR, o sea confirmando la suposición en vez de probarla.
  ///
  /// No basta con emparejar por [RoundResult.playerNames]: quien juega tiene a
  /// su gente con los apodos de siempre —"CAV", "RAFA"— y el padrón lleva nombres
  /// completos. El id resuelve al autor sin depender de cómo se llame a sí mismo.
  ///
  /// Null en lo publicado antes de que el campo existiera: entonces se empareja
  /// solo por nombre, que es lo que se podía hacer.
  final String? jugadorId;

  final RoundResult resultado;

  const ResultadoPublicado({
    required this.jugadorNombre,
    required this.resultado,
    this.jugadorId,
  });
}

/// Traduce los ids de un resultado publicado a los del organizador.
///
/// [participantePorNombre] va con la clave ya normalizada: nombreComparable del
/// nombre del inscrito → su id en el directorio del organizador.
///
/// Regla por jugador de la ronda:
///
///   · Si es el AUTOR —[jugadorId]— se traduce al inscrito que reclamó, sin
///     mirar cómo se llame en su propia ficha. La reclamación manda: eso es lo
///     que "soy este de la lista" significa.
///   · Si no, se intenta por su nombre. Un compañero apuntado con el mismo
///     nombre que un inscrito ES ese inscrito, y así una sola ronda publicada
///     acredita a todos los del torneo que jugaron en ella.
///   · Y si no cruza, se queda como está. No es inscrito, y la tabla ya lo
///     descarta por su cuenta.
///
/// Dos jugadores no pueden acabar en el mismo id: fundiría dos personas en una
/// fila y el dinero de una se le sumaría a la otra. El autor gana el sitio y el
/// otro se queda con el suyo.
RoundResult conIdsDelTorneo(
  RoundResult r, {
  required Map<String, String> participantePorNombre,
  String? jugadorNombre,
  String? jugadorId,
}) {
  final destino = <String, String>{};
  final tomados = <String>{};

  // El autor primero, para que gane el sitio si hay colisión.
  if (jugadorId != null &&
      jugadorNombre != null &&
      r.playerIds.contains(jugadorId)) {
    final pid = participantePorNombre[nombreComparable(jugadorNombre)];
    if (pid != null) {
      destino[jugadorId] = pid;
      tomados.add(pid);
    }
  }
  for (final x in r.playerIds) {
    if (destino.containsKey(x)) continue;
    final n = r.playerNames[x];
    final pid = n == null ? null : participantePorNombre[nombreComparable(n)];
    if (pid == null || tomados.contains(pid)) continue;
    destino[x] = pid;
    tomados.add(pid);
  }
  if (destino.isEmpty) return r;

  String tr(String x) => destino[x] ?? x;
  Map<String, V> porJugador<V>(Map<String, V> m) =>
      {for (final e in m.entries) tr(e.key): e.value};

  // Los pares se reconstruyen con pairKey porque la clave guarda la vista del id
  // MENOR: traducir los ids sin recalcularla invertiría el signo de un duelo sin
  // que nada avisara.
  final pares = <String, double>{};
  for (final e in r.pairBalances.entries) {
    // El separador es '|', el de BetEngine.pairKey. Está aquí y no en una
    // constante porque pairKey lo tiene literal: una constante nueva sería un
    // cuarto sitio donde puede desincronizarse.
    final partes = e.key.split('|');
    if (partes.length != 2) {
      pares[e.key] = e.value;
      continue;
    }
    final a = partes[0], b = partes[1];
    final na = tr(a), nb = tr(b);
    final clave = BetEngine.pairKey(na, nb);
    // El mapa guarda lo que le sacó el id menor al mayor. Si traducir cambia
    // quién es el menor, el valor cambia de signo.
    final antesMenor = a.compareTo(b) <= 0;
    final ahoraMenor = na.compareTo(nb) <= 0;
    pares[clave] = antesMenor == ahoraMenor ? e.value : -e.value;
  }

  return RoundResult(
    roundId: r.roundId,
    roundName: r.roundName,
    courseName: r.courseName,
    playedAt: r.playedAt,
    holesPlayed: r.holesPlayed,
    playerIds: r.playerIds.map(tr).toList(),
    playerNames: porJugador(r.playerNames),
    balances: porJugador(r.balances),
    pairBalances: pares,
    grossByPlayer: porJugador(r.grossByPlayer),
    netByPlayer: porJugador(r.netByPlayer),
    stablefordByPlayer: porJugador(r.stablefordByPlayer),
    bettingGroupIds: r.bettingGroupIds,
    torneoIds: r.torneoIds,
  );
}

List<RoundResult> resultadosQueCuentan(
  Torneo t,
  Iterable<ResultadoPublicado> publicados, {
  Map<String, String> nombres = const {},
}) {
  if (t.participantes.isEmpty) return const [];
  final porNombre = <String, String>{
    for (final pid in t.participantes)
      if (nombres[pid] != null) nombreComparable(nombres[pid]!): pid,
  };
  if (porNombre.isEmpty) return const [];
  return [
    for (final p in publicados)
      if (p.jugadorNombre.isNotEmpty &&
          porNombre.containsKey(nombreComparable(p.jugadorNombre)))
        // Filtrar y TRADUCIR van juntos a propósito. Separarlos dejaría un
        // tercer sitio donde alguien puede olvidarse de la mitad, y la mitad que
        // se olvida no da error: da ceros.
        conIdsDelTorneo(p.resultado,
            participantePorNombre: porNombre,
            jugadorNombre: p.jugadorNombre,
            jugadorId: p.jugadorId),
  ];
}

/// Un nombre comparable: sin acentos, sin mayúsculas, sin espacios de más.
///
/// Igual que en la importación por pegado, y por el mismo motivo: es lo único que
/// las dos partes escriben a mano.
///
/// Público porque el puente por nombre se usa ya en tres sitios y tienen que
/// normalizar IGUAL o el puente no cruza: filtrar los resultados publicados por
/// inscrito, importar participantes pegados, y resolver el padrón de un torneo
/// contra las fichas que ya existen para no crear a la misma persona dos veces.
/// Dos normalizaciones distintas darían un fallo silencioso: el nombre coincide
/// para el ojo y no para el código.
String nombreComparable(String s) {
  const con = 'áàäâãéèëêíìïîóòöôõúùüûñçÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇ';
  const sin = 'aaaaaeeeeiiiiooooouuuuncAAAAAEEEEIIIIOOOOOUUUUNC';
  final b = StringBuffer();
  for (final ch in s.trim().toLowerCase().split('')) {
    final i = con.indexOf(ch);
    b.write(i >= 0 ? sin[i] : ch);
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Une lo propio con lo publicado, sin contar una ronda dos veces.
///
/// Pasa de verdad: el organizador cierra una ronda suya —va a su colección— y
/// además está publicada porque alguien la siguió. Sin deduplicar, esa ronda
/// contaría doble y el dinero saldría al doble.
///
/// ── Por qué esto necesita SU PROPIO test ──────────────────────────────────
///
/// Es el caso que ningún test de "publica bien" ve, porque las dos mitades
/// funcionan por separado: la ronda propia se cuenta bien, y la publicada se
/// cuenta bien. Lo que falla es TENERLAS LAS DOS, y eso solo aparece si el test
/// monta las dos a la vez con el mismo roundId.
///
/// O sea que la cobertura de las partes no implica la cobertura de la suma. Es la
/// misma familia que el hueco tratado como bye y el contador que retrocedía:
/// fallos que solo existen en la composición.
///
/// Gana lo PROPIO: es lo que el dueño de la tabla cerró con sus manos.
List<RoundResult> resultadosUnidos(
  List<RoundResult> propios,
  List<RoundResult> publicados,
) {
  final vistos = propios.map((r) => r.roundId).toSet();
  return [
    ...propios,
    for (final r in publicados)
      if (vistos.add(r.roundId)) r,
  ];
}

/// Por qué un torneo de liga no puede pasar a eliminación, si no puede.
///
/// El cuadro se alimenta de rondas MARCADAS: con otra fuente, los partidos no se
/// pueden emparejar con la ronda que los resolvió.
///
/// [exigirInscritos] separa dos cosas que no son iguales. La fuente es un NO —el
/// cuadro no puede funcionar así— pero la falta de inscritos es un TODAVÍA NO, y
/// bloquear por eso obligaría a bajar tres secciones a rellenar la lista y volver
/// a subir. El editor lo pone en false y deja que el bloque de la siembra diga lo
/// que falta.
String? motivoSinCuadro(Torneo t, {bool exigirInscritos = true}) {
  if (t.fuente != FuenteDeRondas.marcadas) {
    return 'Un cuadro necesita rondas marcadas: cada partido se resuelve con la '
        'ronda que jugaron los dos, y hay que saber cuál es. Cambia la fuente a '
        '"Marcadas al configurar la ronda".';
  }
  if (exigirInscritos && t.participantes.length < 2) {
    return 'Un cuadro se arma con los inscritos, y hacen falta al menos dos.';
  }
  return null;
}
