// ─────────────────────────────────────────────────────────────────────────────
// BET RECIPE — de los ejes del flujo rápido a un módulo de apuesta
//
// El flujo rápido no pregunta "¿qué tipo de apuesta?", pregunta dos cosas
// independientes: QUÉ SE CUENTA y SI LA APUESTA SE PARTE. Con equipos añade una
// tercera, QUÉ BOLA CUENTA. "Nassau" deja de ser un tipo y pasa a ser
// puntos × Front·Back·Total, que es como lo describe un jugador.
//
// La LONGITUD de la ronda —9 o 18 hoyos— NO es uno de estos ejes: se decide en
// el paso Campo y todos los motores la respetan vía playOrder. Pero sí cambia
// qué particiones tienen sentido, así que entra como dato, no como pregunta.
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

  /// Construye el módulo para una combinación de ejes.
  ///
  /// [bola] es null en individual. [sides] solo con equipos. [holesInRound] es
  /// la longitud elegida en el paso Campo: cambia qué particiones existen.
  static BetRecipeResult build({
    required BetCount cuenta,
    required BetDivision division,
    TeamBall? bola,
    required List<String> participantIds,
    int holesInRound = 18,
    List<BetSide>? sides,
    String? id,
  }) {
    final tipo = cuenta.tipoCon(bola);
    final nueveHoyos = holesInRound <= 9;

    // ── El conteo, ¿admite equipos? ────────────────────────────────────────
    if (sides != null && !tipo.rules.teams) {
      return BetRecipeResult.no(tipo.rules.sinEquipos!);
    }
    if (sides == null && tipo.rules.requiresTeams) {
      return BetRecipeResult.no(
          '${cuenta.labelCon(bola)} se juega 2 vs 2: hacen falta dos lados.');
    }

    // ── Partir en Front · Back · Total ─────────────────────────────────────
    if (division == BetDivision.frontBackTotal) {
      if (!tipo.rules.segments) {
        return BetRecipeResult.no(tipo.rules.sinSegmentos!);
      }
      // Una ronda de 9 hoyos no tiene dos vueltas que separar.
      if (nueveHoyos) {
        return BetRecipeResult.no(
            'La ronda es de 9 hoyos: no hay un Front y un Back que separar.');
      }
    }

    var mod = BetModuleInstance.defaultFor(tipo, participantIds,
        id: id, sides: sides);

    // ── Una sola apuesta ───────────────────────────────────────────────────
    if (division == BetDivision.unaSolaApuesta) {
      final r = _colapsarAUnaApuesta(mod, tipo, nueveHoyos);
      if (!r.ok) return r;
      mod = r.module!;
    }

    return BetRecipeResult.ok(mod);
  }

  /// Deja el módulo como una sola apuesta sobre la ronda completa.
  ///
  /// Los conteos que no segmentan ya son una sola apuesta y no hay nada que
  /// hacer. Los dos que sí segmentan se comportan distinto, y la asimetría es
  /// del modelo, no un capricho:
  ///
  ///   · Bola Baja / Bola Alta tiene front9Enabled / back9Enabled /
  ///     overallEnabled, así que basta con dejar solo el Total.
  ///
  ///   · Nassau NO tiene esos interruptores. Habría que poner Front y Back a
  ///     cero, y _addNassauSegment no comprueba si el valor es cero: emitiría
  ///     dos asientos de $0 por pareja, visibles como filas vacías en
  ///     Resultados. Añadir los flags es modelo; hacer que
  ///     _addNassauSegment los respete es tocar el cálculo.
  ///
  /// En una ronda de 9 hoyos el problema no existe: _nassauPair ya colapsa a
  /// un único asiento 'Nassau 9 hoyos' cuando segmentsOf marca singleNine.
  static BetRecipeResult _colapsarAUnaApuesta(
      BetModuleInstance mod, BetModuleType tipo, bool nueveHoyos) {
    if (tipo == BetModuleType.nassauLowHigh) {
      return BetRecipeResult.ok(mod.copyWith(
        nassauLowHighConfig: mod.lowHigh.copyWith(
          front9Enabled: false,
          back9Enabled: false,
          overallEnabled: true,
        ),
      ));
    }

    if (tipo == BetModuleType.nassau && !nueveHoyos) {
      return BetRecipeResult.no(
          'Un Match a los 18 hoyos tendría que ser un Front y un Back a cero, '
          'y eso deja apuntes de \$0 en el resultado. Pártelo en '
          'Front · Back · Total, o juega una ronda de 9.');
    }

    return BetRecipeResult.ok(mod);
  }

  /// Divisiones ofrecibles para un conteo, con el motivo de las que no.
  ///
  /// Lo consume la UI para atenuar en vez de validar: una opción en gris que
  /// dice por qué enseña el modelo; un error después de elegirla, no.
  static Map<BetDivision, String?> divisionesPara(
    BetCount cuenta, {
    TeamBall? bola,
    int holesInRound = 18,
  }) {
    final r = <BetDivision, String?>{};
    for (final d in BetDivision.values) {
      final res = build(
        cuenta: cuenta, division: d, bola: bola,
        participantIds: const ['a', 'b'],
        holesInRound: holesInRound,
        sides: bola == null
            ? null
            : const [
                BetSide(id: 'A', name: 'A', playerIds: ['a']),
                BetSide(id: 'B', name: 'B', playerIds: ['b']),
              ],
      );
      r[d] = res.ok ? null : res.rechazo;
    }
    return r;
  }

  /// true si este conteo tiene más de una división posible.
  ///
  /// El paso "¿se parte en varias apuestas?" solo existe si alguna apuesta
  /// elegida admite partirse. Con una sola opción no hay nada que preguntar.
  static bool admiteParticion(BetCount cuenta,
      {TeamBall? bola, int holesInRound = 18}) {
    final d = divisionesPara(cuenta, bola: bola, holesInRound: holesInRound);
    return d.values.where((motivo) => motivo == null).length > 1;
  }
}
