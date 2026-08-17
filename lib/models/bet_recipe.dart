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
enum BetCount { puntos, skins, scoreTotal, putts, oyes, unidades }

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
        BetCount.puntos || BetCount.unidades => false,
      };

  /// Por qué no admite bote, para la opción atenuada.
  String? get sinBote => switch (this) {
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
}
