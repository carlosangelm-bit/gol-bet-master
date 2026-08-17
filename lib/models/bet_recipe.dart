// ─────────────────────────────────────────────────────────────────────────────
// BET RECIPE — de los ejes del flujo rápido a un módulo de apuesta
//
// El flujo rápido no pregunta "¿qué tipo de apuesta?", pregunta dos cosas
// independientes: QUÉ SE CUENTA y CÓMO SE DIVIDE la ronda. Con equipos añade
// una tercera, QUÉ BOLA CUENTA. "Nassau" deja de ser un tipo y pasa a ser
// puntos × Front·Back·Total, que es como lo describe un jugador.
//
// Esta es la traducción a lo que el motor ya sabe liquidar. Es una función
// pura: sin UI, sin estado, sin tocar el cálculo. Si una combinación no se
// puede expresar, [BetRecipeResult] la rechaza CON MOTIVO en vez de producir
// un módulo que liquide algo distinto de lo que el usuario eligió.
//
// Ese rechazo es el punto de la pieza. Las combinaciones imposibles aparecen
// aquí, en una función testeable, y no a mitad de una pantalla.
// ─────────────────────────────────────────────────────────────────────────────
import 'models.dart';

/// Qué se cuenta. Eje independiente de cómo se divide la ronda.
enum BetCount { puntos, skins, scoreTotal, putts, cercania, logros }

/// Cómo se reparte la ronda en apuestas.
enum BetDivision {
  /// Una sola apuesta por los 18 hoyos.
  todaLaRonda,

  /// Tres apuestas: Front 9, Back 9 y Total. Lo que siempre se llamó Nassau.
  frontBackTotal,

  /// Una apuesta por la vuelta que se juega.
  soloNueve,
}

/// Qué bola cuenta en cada hoyo. Solo aplica con equipos.
enum TeamBall {
  /// El mejor score del equipo.
  mejor,

  /// La mejor y la peor: dos puntos por hoyo.
  mejorYPeor,

  /// El equipo juega un balón y registra un score.
  unaSola,
}

extension BetCountLabel on BetCount {
  String get label => switch (this) {
        BetCount.puntos => 'Puntos',
        BetCount.skins => 'Skins',
        BetCount.scoreTotal => 'Score total',
        BetCount.putts => 'Putts',
        BetCount.cercania => 'Cercanía',
        BetCount.logros => 'Logros',
      };

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
      BetCount.cercania => BetModuleType.oyeses,
      BetCount.logros => BetModuleType.units,
    };
  }

  /// true si el conteo admite el reparto "un solo bote".
  ///
  /// Verificado contra el motor, no supuesto: consumen BetFormatMode los
  /// motores _skins, _medal, _putts y _oyeses. _units NO lo lee ni una vez —
  /// liquida siempre par a par— así que ofrecerlo en Logros mostraría un
  /// control que no hace nada.
  bool get admiteBote => switch (this) {
        BetCount.skins ||
        BetCount.scoreTotal ||
        BetCount.putts ||
        BetCount.cercania =>
          true,
        BetCount.puntos || BetCount.logros => false,
      };

  /// Por qué no admite bote, para la opción atenuada.
  String? get sinBote => switch (this) {
        BetCount.logros =>
          'Los logros se acreditan a la persona: el motor los liquida siempre '
              'de uno contra uno.',
        BetCount.puntos =>
          'Los puntos se ganan contra un rival concreto, no contra una bolsa.',
        _ => null,
      };
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
  /// [bola] es null en individual. [sides] solo con equipos.
  /// [id] permite fijarlo en tests; si no, se genera como en [defaultFor].
  static BetRecipeResult build({
    required BetCount cuenta,
    required BetDivision division,
    TeamBall? bola,
    required List<String> participantIds,
    List<BetSide>? sides,
    String? id,
  }) {
    final tipo = cuenta.tipoCon(bola);

    // ── El conteo, ¿admite equipos? ────────────────────────────────────────
    if (sides != null && !tipo.rules.teams) {
      return BetRecipeResult.no(tipo.rules.sinEquipos!);
    }
    if (sides == null && tipo.rules.requiresTeams) {
      return BetRecipeResult.no(
          '${cuenta.label} con esta bola se juega 2 vs 2: hacen falta dos lados.');
    }

    // ── La división, ¿la sabe liquidar? ────────────────────────────────────
    if (division == BetDivision.frontBackTotal && !tipo.rules.segments) {
      return BetRecipeResult.no(tipo.rules.sinSegmentos!);
    }

    // ── Puntos por toda la ronda: no se puede expresar ─────────────────────
    //
    // Sería un Nassau con Front y Back a cero y el Total con el importe. Pero
    // _addNassauSegment no comprueba si el valor es cero: emitiría dos asientos
    // de $0 por pareja, que saldrían como filas vacías en Resultados.
    //
    // La salida limpia sería que NassauConfig tuviera flags de segmento, como
    // sí los tiene NassauLowHighConfig. Añadirlos es modelo; hacer que
    // _addNassauSegment los respete es tocar el cálculo. Por eso no se ofrece.
    if (cuenta == BetCount.puntos && division == BetDivision.todaLaRonda) {
      return BetRecipeResult.no(
          'Un match a los 18 hoyos tendría que ser un Front y un Back a cero, '
          'y eso deja apuntes de \$0 en el resultado. Usa Front · Back · Total '
          'o una sola vuelta.');
    }

    // ── Módulo ─────────────────────────────────────────────────────────────
    //
    // Se construye con defaultFor, el MISMO camino que usa el flujo manual, y
    // luego se ajusta la división. Así los dos flujos no pueden divergir en la
    // configuración de partida.
    var mod = BetModuleInstance.defaultFor(tipo, participantIds,
        id: id, sides: sides);

    mod = _aplicarDivision(mod, cuenta, division);
    return BetRecipeResult.ok(mod);
  }

  /// Traduce la división al campo que cada motor entiende.
  ///
  /// Solo Puntos la usa: es el único conteo que liquida por segmentos. Para el
  /// resto, la división ya quedó validada arriba y no hay nada que ajustar.
  static BetModuleInstance _aplicarDivision(
      BetModuleInstance mod, BetCount cuenta, BetDivision division) {
    if (cuenta != BetCount.puntos) return mod;

    // Bola Baja / Bola Alta sí tiene interruptores de segmento.
    if (mod.type == BetModuleType.nassauLowHigh) {
      return switch (division) {
        BetDivision.frontBackTotal => mod,
        // Una sola vuelta: el motor ya colapsa Front y Overall cuando la ronda
        // es de 9 hoyos, así que no hay que desactivar nada aquí.
        BetDivision.soloNueve => mod,
        BetDivision.todaLaRonda => mod, // rechazado antes de llegar
      };
    }

    // Nassau clásico: la segmentación la resuelve segmentsOf a partir de los
    // hoyos que se jueguen. No hay campo que tocar.
    return mod;
  }

  /// Divisiones ofrecibles para un conteo, con el motivo de las que no.
  ///
  /// Lo consume la UI para atenuar en vez de validar: una opción en gris que
  /// dice por qué enseña el modelo; un error después de elegirla, no.
  static Map<BetDivision, String?> divisionesPara(BetCount cuenta,
      {TeamBall? bola}) {
    final r = <BetDivision, String?>{};
    for (final d in BetDivision.values) {
      final res = build(
        cuenta: cuenta, division: d, bola: bola,
        participantIds: const ['a', 'b'],
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
}
