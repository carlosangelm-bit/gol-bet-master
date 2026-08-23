// ─────────────────────────────────────────────────────────────────────────────
// BET RECIPE — de los ejes del flujo rápido a un módulo de apuesta
//
// El flujo rápido no pregunta "¿qué tipo de apuesta?". Pregunta QUÉ SE CUENTA
// y, con equipos, QUÉ BOLA CUENTA. "Nassau" deja de ser un tipo y pasa a ser
// puntos × Front·Back·Total, que es como lo describe un jugador.
//
// La PARTICIÓN no se pregunta: se deriva de (conteo, bola, longitud). De las
// 36 celdas posibles solo UNA admite dos caminos —Puntos con bola baja y alta
// a 18 hoyos—; en las otras 35 la respuesta ya está determinada. Preguntar lo
// que el sistema sabe enseña a pulsar Continuar sin leer, y entonces tampoco
// se lee la celda que sí importaba. Cuando no hay elección se explica; cuando
// la hay, se ofrece.
//
// La LONGITUD de la ronda —9 o 18 hoyos— se decide en el paso Campo y todos
// los motores la respetan vía playOrder. Entra aquí como dato porque determina
// qué particiones existen.
//
// Es una función pura: sin UI, sin estado, sin tocar el cálculo. Si una
// combinación no se puede expresar, [BetRecipeResult] la rechaza CON MOTIVO en
// vez de producir un módulo que liquide algo distinto de lo que se eligió.
//
// Ese rechazo es el punto de la pieza. Las combinaciones imposibles aparecen
// aquí, en una función testeable, y no a mitad de una pantalla.
// ─────────────────────────────────────────────────────────────────────────────
import 'models.dart';

/// Qué se cuenta. Eje independiente de si la apuesta se parte.
///
/// Los nombres son los que usa el grupo, no los del modelo: Oyes y Unidades,
/// no "oyeses" y "units". Un nombre que hay que traducir mentalmente ya cuesta
/// un paso.
enum BetCount { puntos, skins, scoreTotal, putts, oyes, unidades, snake, rabbit, wolf }

/// Si la apuesta se parte en sub-apuestas.
///
/// No confundir con la longitud de la ronda: una ronda de 9 hoyos con
/// [unaSolaApuesta] es una apuesta sobre esos 9, y una de 18 con lo mismo es
/// una apuesta sobre los 18.
enum BetDivision {
  /// Una sola apuesta sobre la ronda completa, sean 9 hoyos o 18.
  unaSolaApuesta,

  /// Tres apuestas: Front 9, Back 9 y Total. Lo que siempre se llamó Nassau.
  frontBackTotal,
}

/// Qué bola cuenta en cada hoyo. Solo aplica con equipos.
enum TeamBall {
  /// El mejor score del equipo. Un punto por hoyo.
  mejor,

  /// La mejor y la peor: dos puntos por hoyo.
  mejorYPeor,

  /// El equipo juega un balón y registra un score.
  unaSola,
}

/// Cómo se juega esa única bola.
///
/// Solo aplica con [TeamBall.unaSola]. Ambos registran UN score por equipo
/// —por eso los dos son TeamPlayMode.scramble y no hace falta un modo nuevo—:
/// lo que cambia es el handicap. En alterna los dos pegan golpes de verdad,
/// así que el equipo no queda tan por debajo de sus miembros como en scramble.
enum SingleBallMode { scramble, alterna }

extension SingleBallModeInfo on SingleBallMode {
  String get label => switch (this) {
        SingleBallMode.scramble => 'Scramble',
        SingleBallMode.alterna => 'Bola alterna',
      };

  String get description => switch (this) {
        SingleBallMode.scramble =>
          'Ambos pegan y se juega desde la mejor posición.',
        SingleBallMode.alterna =>
          'Se turnan los golpes. Handicap: 50% de la suma.',
      };

  TeamHandicapConfig get handicap => switch (this) {
        SingleBallMode.scramble => TeamHandicapConfig.scramble,
        SingleBallMode.alterna => TeamHandicapConfig.alterna,
      };
}

extension TeamBallPoints on TeamBall? {
  /// Puntos que reparte cada hoyo. Con uno solo, el marcador se lee "2 UP".
  int get puntosPorHoyo => this == TeamBall.mejorYPeor ? 2 : 1;
}

extension BetCountLabel on BetCount {
  /// Nombre con la bola ya resuelta.
  ///
  /// Puntos es el único conteo cuyo nombre depende del contexto: con un punto
  /// por hoyo el marcador se lleva en hoyos arriba y llamarlo "puntos" sería
  /// impreciso, así que es **Match**. Con dos —bola baja y alta— sí son
  /// puntos. El nombre se deriva, no se elige.
  String labelCon(TeamBall? bola) {
    if (this == BetCount.puntos) {
      return bola.puntosPorHoyo == 2 ? 'Puntos' : 'Match';
    }
    return switch (this) {
      BetCount.skins => 'Skins',
      BetCount.scoreTotal => 'Score total',
      BetCount.putts => 'Putts',
      BetCount.oyes => 'Oyes',
      BetCount.unidades => 'Unidades',
      BetCount.snake => 'Snake',
      BetCount.rabbit => 'Rabbit',
      BetCount.wolf => 'Wolf',
      BetCount.puntos => 'Match', // inalcanzable
    };
  }

  /// Nombre sin contexto de bola, para listados neutros.
  String get label => labelCon(null);

  /// El tipo del motor que liquida este conteo, con la bola ya resuelta.
  ///
  /// Solo [BetCount.puntos] depende de la bola: con la mejor y la peor pasa a
  /// ser Bola Baja / Bola Alta, que es otro motor.
  BetModuleType tipoCon(TeamBall? bola) {
    if (this == BetCount.puntos && bola == TeamBall.mejorYPeor) {
      return BetModuleType.nassauLowHigh;
    }
    return switch (this) {
      BetCount.puntos => BetModuleType.nassau,
      BetCount.skins => BetModuleType.skins,
      BetCount.scoreTotal => BetModuleType.medal,
      BetCount.putts => BetModuleType.putts,
      BetCount.oyes => BetModuleType.oyeses,
      BetCount.unidades => BetModuleType.units,
      BetCount.snake => BetModuleType.snake,
      BetCount.rabbit => BetModuleType.rabbit,
      BetCount.wolf => BetModuleType.wolf,
    };
  }

  /// true si el conteo admite el reparto "un solo bote".
  ///
  /// Verificado contra el motor, no supuesto: consumen BetFormatMode los
  /// motores _skins, _medal, _putts y _oyeses — cuatro. _units NO lo lee ni
  /// una vez, así que ofrecerlo en Unidades sería un control que no hace nada.
  bool get admiteBote => switch (this) {
        BetCount.skins ||
        BetCount.scoreTotal ||
        BetCount.putts ||
        BetCount.oyes =>
          true,
        // Snake ya ES un bote: la serpiente es una y su dueño paga a todos.
        // Ofrecer "un solo bote" contra "todos vs todos" sería un control sin
        // efecto —_snake no lee BetFormatMode—, y un control que no hace nada
        // enseña a no leer los que sí.
        // Rabbit tampoco: el conejo es uno y su dueño cobra a todos.
        BetCount.puntos ||
        BetCount.unidades ||
        BetCount.snake ||
        BetCount.rabbit ||
        // Wolf tampoco: el enfrentamiento del hoyo ya define quién cobra a
        // quién, y cambia cada hoyo.
        BetCount.wolf =>
          false,
      };

  /// Por qué no admite bote, para la opción atenuada.
  ///
  /// [jugadores] permite decir el número REAL en vez de uno fijo. Wolf decía
  /// "contra los otros dos" y con cinco jugadores son tres: el mismo fallo que
  /// el prefijo de elegibilidad, que sí se genera del conjunto {4, 5} y por eso
  /// no quedó hablando de otro número. Aquí estaba en la descripción en vez de
  /// en el motivo.
  String? sinBoteCon(int? jugadores) => switch (this) {
        BetCount.wolf => 'Cada hoyo enfrenta a la pareja del Wolf contra '
            '${jugadores == null ? 'los demás' : 'los otros ${jugadores - 2}'}: '
            'el reparto ya está definido.',
        _ => sinBote,
      };

  String? get sinBote => switch (this) {
        BetCount.snake =>
          'La serpiente es una sola y su dueño paga a todos: ya es un bote.',
        BetCount.rabbit =>
          'El conejo es uno y su dueño cobra a todos: ya es un bote.',
        BetCount.wolf =>
          'Cada hoyo enfrenta a la pareja del Wolf contra los demás: el '
              'reparto ya está definido.',
        BetCount.unidades =>
          'El motor de Unidades acredita cada unidad contra cada rival por '
              'separado.',
        BetCount.puntos =>
          'Los puntos se ganan contra un rival concreto, no contra una bolsa.',
        _ => null,
      };

  /// true si este conteo solo tiene sentido entre todo el grupo.
  ///
  /// Oyes y Unidades no se pactan en un duelo suelto: quien no juegue sale en
  /// el paso de participantes.
  bool get esDeGrupo => this == BetCount.oyes || this == BetCount.unidades;

  String? get soloDeGrupo => esDeGrupo
      ? 'Se juega entre todo el grupo. Configúrala como apuesta de la ronda y '
          'saca a quien no entre en el paso de participantes.'
      : null;
}

/// Importe pactado en una celda `enfrentamiento × apuesta × segmento`.
///
/// Una apuesta sin partición tiene UN segmento y la celda es un número. Una
/// partida en Front · Back · Total tiene tres, y son tres campos: el ajuste de
/// un enfrentamiento no cabe en un solo importe.
///
/// Eso es lo que hace que pairConfigOverrides no sirva aquí:
/// effectiveValueForDuel devuelve un único double, así que el mecanismo de
/// override por pareja solo puede llevar el importe de una apuesta de un
/// segmento. Para las partidas hace falta un módulo por cruce con su propia
/// config, que es lo que hace [BetRecipe.conCrucesFuera].
class MontoPorCruce {
  /// Importe único, para los tipos que solo tienen uno.
  final double? unico;

  /// Importes por segmento, para las apuestas partidas.
  final double? front, back, total;

  const MontoPorCruce({this.unico, this.front, this.back, this.total});

  bool get vacio =>
      unico == null && front == null && back == null && total == null;
}

/// Particiones que existen para una celda concreta, y cuál queda elegida.
///
/// Salida derivada, no entrada del usuario. Cuando [hayEleccion] es false la
/// UI muestra [explicacion] como constatación —"a 9 hoyos esta apuesta solo
/// puede jugarse entera"— y no como opción.
class DivisionOptions {
  /// Las que el motor sabe liquidar en esta celda. Nunca vacía.
  final List<BetDivision> disponibles;

  /// La que queda puesta: la preferida si es válida, si no la única posible.
  final BetDivision elegida;

  /// Por qué no hay alternativa. null cuando sí la hay.
  final String? explicacion;

  const DivisionOptions({
    required this.disponibles,
    required this.elegida,
    this.explicacion,
  });

  /// true solo donde el usuario tiene algo que decidir.
  bool get hayEleccion => disponibles.length > 1;
}

/// Resultado de traducir una combinación de ejes.
///
/// O sale un módulo, o sale el motivo por el que esa combinación no existe.
/// Nunca las dos cosas, y nunca ninguna.
class BetRecipeResult {
  final BetModuleInstance? module;

  /// Motivo del rechazo, listo para mostrarse en la opción atenuada.
  final String? rechazo;

  const BetRecipeResult._(this.module, this.rechazo);

  factory BetRecipeResult.ok(BetModuleInstance m) => BetRecipeResult._(m, null);
  factory BetRecipeResult.no(String motivo) => BetRecipeResult._(null, motivo);

  bool get ok => module != null;
}

/// Traductor de ejes a módulo.
class BetRecipe {
  const BetRecipe._();

  /// Qué particiones existen en esta celda, y cuál queda elegida.
  ///
  /// **Derivación, no pregunta.** El resultado sale de tres datos que el
  /// usuario ya dio antes: el conteo, la bola y la longitud de la ronda.
  ///
  ///   · el conteo no segmenta        → una sola apuesta, siempre
  ///   · ronda de 9 hoyos             → una sola apuesta (singleNine ya emite
  ///                                    un asiento único; no hay dos vueltas)
  ///   · 18 hoyos + bola baja y alta  → las dos (tiene flags de segmento)
  ///   · 18 hoyos + Match liso        → solo partido (entero exigiría dos
  ///                                    segmentos a cero)
  ///
  /// [preferida] solo se honra si está entre las disponibles. Sirve para
  /// conservar la elección del usuario en la única celda donde la hay, sin que
  /// una elección vieja sobreviva a un cambio de bola o de longitud.
  static DivisionOptions divisionDe(
    BetCount cuenta, {
    TeamBall? bola,
    int holesInRound = 18,
    BetDivision? preferida,
  }) {
    final tipo = cuenta.tipoCon(bola);

    DivisionOptions unica(BetDivision d, String porQue) => DivisionOptions(
        disponibles: [d], elegida: d, explicacion: porQue);

    if (!tipo.rules.segments) {
      return unica(BetDivision.unaSolaApuesta, tipo.rules.sinSegmentos!);
    }

    if (holesInRound <= 9) {
      return unica(
          BetDivision.unaSolaApuesta,
          'La ronda es de 9 hoyos: no hay un Front y un Back que separar, así '
          'que se juega entera.');
    }

    // Bola baja y alta: la única config con interruptores de segmento, y por
    // tanto la única celda con dos caminos reales.
    if (tipo == BetModuleType.nassauLowHigh) {
      const todas = [BetDivision.unaSolaApuesta, BetDivision.frontBackTotal];
      return DivisionOptions(
        disponibles: todas,
        elegida: todas.contains(preferida)
            ? preferida!
            : BetDivision.frontBackTotal,
      );
    }

    return unica(
        BetDivision.frontBackTotal,
        'A 18 hoyos un Match entero tendría que ser un Front y un Back a cero, '
        'y eso deja apuntes de \$0 en el resultado. Se juega partido.');
  }

  /// Construye el módulo para una combinación de ejes.
  ///
  /// La partición NO es parámetro: se deriva con [divisionDe]. [preferida] solo
  /// se honra en la celda donde hay elección real.
  ///
  /// [bola] es null en individual. [sides] solo con equipos. [holesInRound] es
  /// la longitud elegida en el paso Campo.
  static BetRecipeResult build({
    required BetCount cuenta,
    TeamBall? bola,
    required List<String> participantIds,
    int holesInRound = 18,
    List<BetSide>? sides,
    BetDivision? preferida,
    String? id,
  }) {
    final tipo = cuenta.tipoCon(bola);

    // ── El conteo, ¿admite equipos? ────────────────────────────────────────
    if (sides != null && !tipo.rules.teams) {
      return BetRecipeResult.no(tipo.rules.sinEquipos!);
    }
    if (sides == null && tipo.rules.requiresTeams) {
      return BetRecipeResult.no(
          '${cuenta.labelCon(bola)} se juega 2 vs 2: hacen falta dos lados.');
    }

    // ── ¿Cuántos jugadores necesita? ───────────────────────────────────────
    // Mecanismo existente, no uno nuevo: devolver `no(motivo)` es lo que ya
    // atenúa la opción en el selector con su explicación.
    final motivoCardinalidad =
        tipo.motivoNoDisponible(participantIds.length);
    if (motivoCardinalidad != null) {
      return BetRecipeResult.no(motivoCardinalidad);
    }

    final div = divisionDe(cuenta,
        bola: bola, holesInRound: holesInRound, preferida: preferida);

    var mod = BetModuleInstance.defaultFor(tipo, participantIds,
        id: id, sides: sides);

    // Solo Bola Baja / Bola Alta necesita ajuste: es la única con flags de
    // segmento. Nassau y los conteos que no segmentan ya salen bien de
    // defaultFor, porque su partición es la única que sabían hacer.
    if (tipo == BetModuleType.nassauLowHigh &&
        div.elegida == BetDivision.unaSolaApuesta) {
      mod = mod.copyWith(
        nassauLowHighConfig: mod.lowHigh.copyWith(
          front9Enabled: false,
          back9Enabled: false,
          overallEnabled: true,
        ),
      );
    }

    return BetRecipeResult.ok(mod);
  }

  /// Traduce la bola elegida al modo de juego del lado.
  ///
  /// Con la mejor y la peor cada jugador juega SU bola —hacen falta las dos
  /// para sacar la baja y la alta—, así que es best ball igual que "la mejor".
  /// Lo que cambia entre ambas es cuántos puntos reparte el hoyo, no cómo se
  /// juega. Una sola bola sí es scramble: el equipo entrega un score.
  static TeamPlayMode playModeDe(TeamBall bola) => switch (bola) {
        TeamBall.mejor || TeamBall.mejorYPeor => TeamPlayMode.bestBall,
        TeamBall.unaSola => TeamPlayMode.scramble,
      };

  /// Escribe en el módulo la decisión de ronda: quiénes compiten y qué bola.
  ///
  /// Sin esto, elegir "Por equipos" solo cambiaba qué pantallas se veían: el
  /// módulo salía sin lados y la ronda se creaba individual. La parte visible
  /// funcionando y la que resuelve el problema sin conectar.
  ///
  /// Tres cosas que NO hace, a propósito:
  ///
  ///   · No toca un módulo que ya trae lados. Si el usuario los configuró a
  ///     mano en la hoja de la apuesta, esa decisión es más específica que la
  ///     de la ronda y pisarla sería perder trabajo suyo.
  ///   · No pone lados en un conteo sin motor de equipo. Medal, Putts, Oyes y
  ///     Unidades caen al fallback individual: darles lados no los haría de
  ///     equipo, solo dejaría una configuración que miente.
  ///   · No cambia el TIPO del módulo. Que "la mejor y la peor" implique Bola
  ///     Baja / Bola Alta es cosa del paso de qué se cuenta, no de aquí.
  ///
  /// Devuelve el módulo tal cual si no hay nada que aplicar.
  static BetModuleInstance conEquiposDeRonda(
    BetModuleInstance mod, {
    required bool porEquipos,
    required List<String> equipoA,
    required List<String> equipoB,
    TeamBall? bola,
    SingleBallMode submodo = SingleBallMode.scramble,
  }) {
    if (!porEquipos) return mod;
    if (mod.sides != null && mod.sides!.isNotEmpty) return mod;
    if (!mod.type.rules.teams) return mod;
    if (equipoA.isEmpty || equipoB.isEmpty) return mod;

    final modo = playModeDe(bola ?? TeamBall.mejor);
    // El submodo solo cambia el handicap del equipo: scramble y bola alterna
    // registran igual —una tarjeta— y por eso comparten TeamPlayMode.
    final hcp = modo == TeamPlayMode.scramble
        ? submodo.handicap
        : TeamHandicapConfig.defaultFor(modo);
    return mod.copyWith(
      participantIds: [...equipoA, ...equipoB],
      teamHandicapConfig: hcp,
      sides: [
        BetSide(
            id: '${mod.id}_A',
            name: 'Equipo A',
            playerIds: List.of(equipoA),
            playMode: modo),
        BetSide(
            id: '${mod.id}_B',
            name: 'Equipo B',
            playerIds: List.of(equipoB),
            playMode: modo),
      ],
    );
  }

  /// Clave estable de un cruce. Ordenada, para que (a,b) y (b,a) sean el mismo.
  ///
  /// El separador es '|', el mismo que MatchAutoPressConfig.pairKey y
  /// round_provider._pairKeyOf. Esta sesión ya costó un bug por tener tres
  /// separadores distintos conviviendo —'|' y '__'— así que aquí no se inventa
  /// uno nuevo.
  static String cruceKey(String a, String b) {
    final o = [a, b]..sort();
    return '${o[0]}|${o[1]}';
  }

  /// Todos los cruces posibles entre [pids], en orden estable.
  static List<(String, String)> crucesDe(List<String> pids) {
    final out = <(String, String)>[];
    for (var i = 0; i < pids.length; i++) {
      for (var j = i + 1; j < pids.length; j++) {
        out.add((pids[i], pids[j]));
      }
    }
    return out;
  }

  /// Materializa una apuesta respetando los cruces que quedan FUERA.
  ///
  /// Excluir un cruce no es lo mismo que excluir un jugador. El caso que lo
  /// motiva: cinco jugadores donde todos juegan Nassau salvo J4 contra J5.
  /// Sacar a J4 y J5 como jugadores los quitaría del Nassau con los demás;
  /// dejar fuera el cruce los deja jugando contra todos menos entre ellos.
  ///
  /// No hace falta tocar el motor. _nassau enumera TODAS las parejas de sus
  /// participantes y no tiene mecanismo de exclusión, pero expandBetModules ya
  /// sabe partir una apuesta en módulos 1v1 con BetScope.pair, compartiendo
  /// betGroupId para que la UI los agrupe como una sola familia. Excluir es
  /// omitir uno de esos módulos.
  ///
  /// Sin exclusiones se devuelve UN módulo con todos los participantes, no la
  /// expansión: liquida igual y es más barato de guardar y de leer. Hay test de
  /// que las dos formas pagan lo mismo.
  static List<BetModuleInstance> conCrucesFuera(
    BetModuleInstance base, {
    required List<String> participantIds,
    Set<String> fuera = const {},
    Map<String, MontoPorCruce> importes = const {},
  }) {
    if (participantIds.length < 2) return const [];

    final vivos = crucesDe(participantIds)
        .where((c) => !fuera.contains(cruceKey(c.$1, c.$2)))
        .toList();
    if (vivos.isEmpty) return const [];

    final conImportePropio = importes.entries
        .where((e) => !e.value.vacio)
        .map((e) => e.key)
        .toSet();

    // Nada excluido y nada ajustado → un solo módulo, como siempre.
    if (vivos.length == crucesDe(participantIds).length &&
        conImportePropio.isEmpty) {
      return [base.copyWith(participantIds: participantIds)];
    }

    // Con exclusiones: un módulo por cruce vivo, todos de la misma familia.
    //
    // copyWith no puede cambiar el id, y cada módulo necesita el suyo: con uno
    // compartido el segundo sobreescribiría al primero al guardarse. Se
    // reconstruye con defaultFor y se le trasplanta la config del base, para no
    // duplicar la lista de campos tipados y que un formato nuevo no se quede
    // fuera en silencio.
    //
    // Ajustar un importe por enfrentamiento FUERZA uno contra uno. Con un solo
    // bote no hay importes distintos que repartir: el bote es uno. Expandir un
    // onePot en cruces cambiaría el cálculo, no lo recortaría.
    final familia = '${base.id}_fam';
    var i = 0;
    return [
      for (final (a, b) in vivos)
        _conImporte(
          _mismoPero(base,
              id: '${base.id}_${i++}', a: a, b: b, familia: familia),
          importes[cruceKey(a, b)],
        ),
    ];
  }

  /// Fija el importe base de un módulo, sea de uno o de tres segmentos.
  ///
  /// En las apuestas partidas el Total sube al doble del segmento, que es la
  /// convención del Nassau: los dos nueves valen lo mismo y el total vale por
  /// los dos. Se puede cambiar después en el detalle.
  static BetModuleInstance aplicarBase(BetModuleInstance m, double base) {
    if (m.type == BetModuleType.nassau) {
      return m.copyWith(
        nassauConfig: m.nassau.copyWith(
            frontValue: base, backValue: base, totalValue: base * 2),
      );
    }
    return m.withBaseValue(base) ?? m;
  }

  /// Público: aplica el importe pactado de un cruce a un módulo suelto.
  ///
  /// Lo usan los duelos pactados aparte, que no pasan por la expansión porque
  /// son un módulo por cruce desde el principio.
  static BetModuleInstance conMontoDeCruce(
          BetModuleInstance m, MontoPorCruce monto) =>
      _conImporte(m, monto);

  /// Aplica el importe pactado para este cruce, si hay uno.
  ///
  /// Los tipos partidos llevan tres valores; los demás, uno. Un importe que el
  /// tipo no sabe guardar se ignora en vez de perderse a medias.
  static BetModuleInstance _conImporte(
      BetModuleInstance m, MontoPorCruce? monto) {
    if (monto == null || monto.vacio) return m;

    if (m.type == BetModuleType.nassau) {
      return m.copyWith(
        nassauConfig: m.nassau.copyWith(
          frontValue: monto.front,
          backValue: monto.back,
          totalValue: monto.total,
        ),
      );
    }
    if (monto.unico != null) {
      // withBaseValue devuelve null en los tipos con más de un importe: ahí no
      // hay "el" monto que fijar, y forzarlo escribiría uno de los tres.
      return m.withBaseValue(monto.unico!) ?? m;
    }
    return m;
  }

  /// El mismo módulo con otro id y limitado a un cruce.
  static BetModuleInstance _mismoPero(
    BetModuleInstance base, {
    required String id,
    required String a,
    required String b,
    required String familia,
  }) {
    return BetModuleInstance(
      id: id,
      type: base.type,
      name: base.name,
      participantIds: [a, b],
      scope: BetScope.pair(a, b),
      betGroupId: familia,
      betGroupName: base.name,
      formatMode: base.formatMode,
      structure: BetStructure.headToHead,
      teamHandicapConfig: base.teamHandicapConfig,
      skinsConfig: base.skinsConfig,
      nassauConfig: base.nassauConfig,
      nassauLowHighConfig: base.nassauLowHighConfig,
      matchAutoPressConfig: base.matchAutoPressConfig,
      medalConfig: base.medalConfig,
      puttsConfig: base.puttsConfig,
      oyesesConfig: base.oyesesConfig,
      unitsConfig: base.unitsConfig,
      snakeConfig: base.snakeConfig,
      rabbitConfig: base.rabbitConfig,
      wolfConfig: base.wolfConfig,
    );
  }

  /// Fija bruto o neto en un módulo.
  ///
  /// GrossNetMode aparece repetido en Skins, Nassau, Medal, Match y Bola
  /// Baja/Alta, y un grupo no juega skins en bruto y nassau en neto. Es una
  /// pregunta de RONDA con override por apuesta en el detalle.
  ///
  /// El campo por módulo se conserva para no romper la serialización: lo que
  /// cambia es que el flujo lo fija una vez y lo propaga.
  ///
  /// No hace falta preguntarlo aparte, y esa es la parte que importa: neto
  /// significa "con handicap aplicado", así que la respuesta ya está en el paso
  /// de ventaja. Sin ventaja → bruto. Con handicap o sliding → neto. Preguntarlo
  /// otra vez sería pedir dos veces la misma decisión, y permitir contradecirla.
  ///
  /// Los tipos que no leen el modo —Putts, Oyes, Unidades— se devuelven
  /// intactos: sus reglas no dependen del score neto.
  static BetModuleInstance conModo(BetModuleInstance m, GrossNetMode modo) =>
      switch (m.type) {
        BetModuleType.skins =>
          m.copyWith(skinsConfig: m.skins.copyWith(mode: modo)),
        BetModuleType.nassau =>
          m.copyWith(nassauConfig: m.nassau.copyWith(mode: modo)),
        BetModuleType.nassauLowHigh =>
          m.copyWith(nassauLowHighConfig: m.lowHigh.copyWith(mode: modo)),
        BetModuleType.medal =>
          m.copyWith(medalConfig: m.medal.copyWith(mode: modo)),
        BetModuleType.matchAutoPress => m.copyWith(
            matchAutoPressConfig: m.matchAutoPress.copyWith(mode: modo)),
        _ => m,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// VENTAJA DE LA RONDA — de qué fuentes sale el pairSliding que se guarda
//
// Estaba dentro de _createAndStartRound, y por eso una regresión aquí solo se
// notaba jugando: no había forma de contradecirla con un test.
//
// El bug que la saca: una ronda creada con Handicap descartaba en silencio el
// sliding acumulado del grupo. En la tarjeta 1v1 aparecía otra ventaja —la
// diferencia de handicap— y solo al editar el sliding a mano se aplicaba lo
// correcto, porque ese editor escribe pairSliding directo.
//
// La distinción que faltaba: el acumulado NO es "el sistema de ventaja de hoy",
// es el acuerdo bilateral que ya existía entre esas dos personas. Elegir
// Handicap para la ronda no lo retira.
// ─────────────────────────────────────────────────────────────────────────────

/// Cómo se reparte la ventaja en la ronda.
enum SistemaDeVentaja { handicap, sliding, ninguna }

/// El mapa `pairSliding` que le toca a la ronda, por prioridad creciente.
///
///   1. [acumuladoDelGrupo] — el acuerdo que ya existía. Entra salvo con
///      "sin ventaja", donde la instrucción es explícita: todos brutos.
///   2. [editadoEnElPaso]   — solo si se ELIGIÓ sliding. El motor prioriza
///      pairSliding sobre el handicap, así que escribirlo con handicap elegido
///      aplicaría una ventaja que nadie pidió.
///   3. [duelosConVentajaPropia] — entra SIEMPRE, sea cual sea la de la ronda:
///      es el caso que no se podía expresar —la ronda va con handicap y dos
///      jugadores acuerdan lo suyo a scratch—.
///
/// Se filtra al final por [participantIds]: un par cuyo rival no juega hoy no
/// tiene ventaja que aplicar.
Map<String, double> slidingDeRonda({
  required SistemaDeVentaja ventaja,
  required Map<String, double> acumuladoDelGrupo,
  required List<String> participantIds,
  double Function(String a, String b)? editadoEnElPaso,
  Iterable<({String a, String b, double delta})> duelosConVentajaPropia =
      const [],
}) {
  final fuente = <String, double>{
    if (ventaja != SistemaDeVentaja.ninguna) ...acumuladoDelGrupo,

    if (ventaja == SistemaDeVentaja.sliding && editadoEnElPaso != null)
      for (final (a, b) in BetRecipe.crucesDe(participantIds))
        BetRecipe.cruceKey(a, b): editadoEnElPaso(a, b),

    // El signo del mapa es recv(idMenor, idMayor), y delta es lo que recibe
    // `a` de `b`: si `a` no es el menor, se invierte.
    for (final d in duelosConVentajaPropia)
      BetRecipe.cruceKey(d.a, d.b):
          d.a.compareTo(d.b) <= 0 ? d.delta : -d.delta,
  };

  final dentro = participantIds.toSet();
  return Map<String, double>.fromEntries(fuente.entries.where((e) {
    final partes = e.key.split('|');
    return partes.length == 2 &&
        dentro.contains(partes[0]) &&
        dentro.contains(partes[1]);
  }));
}
