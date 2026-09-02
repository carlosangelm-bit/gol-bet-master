// ─────────────────────────────────────────────────────────────────────────────
// SNAKE — la serpiente se queda con el último 3-putt de la ronda
//
// Motor aislado: no toca ninguno de los existentes. `_snake` es una rama nueva
// en computeModule y nada más.
//
// La decisión de estructura, que es la que importa: BUSCAR la serpiente y
// COBRARLA son dos funciones, y la búsqueda se expone. Snake tiene que poder
// decir "nadie hizo 3-putt" —un cero silencioso se lee como un fallo— y esa
// frase la escribe la capa de notas. Si las notas volvieran a recorrer los
// hoyos por su cuenta, tendríamos dos respuestas que pueden discrepar: la
// pantalla diría que la tiene RAFA y el ledger le cobraría a CAM.
//
// Una sola búsqueda, dos consumidores.
// ─────────────────────────────────────────────────────────────────────────────
import '../models/models.dart';

/// Dónde está la serpiente al terminar de recorrer los hoyos.
class SnakeResultado {
  /// El hoyo del último putt por encima del umbral. Null si no hubo ninguno.
  final int? hoyo;

  /// Quién se la queda. Más de uno si empataron en ese mismo hoyo.
  ///
  /// Ordenados por id, NO por el orden de la lista de jugadores: el resultado
  /// no puede depender de en qué orden se armó la ronda.
  final List<String> duenos;

  /// Los putts del hoyo, para poder decirlo.
  final int putts;

  /// El umbral con el que se buscó, para que la nota lo pueda citar.
  final int umbral;

  /// Hoyos donde algún participante todavía no tiene score.
  ///
  /// Mientras sea mayor que cero, "el último" puede cambiar: un 3-putt en un
  /// hoyo posterior aún sin capturar movería la serpiente. Por eso el resultado
  /// se marca provisional en vez de esperar al cierre — Snake es una apuesta
  /// social que se comenta durante la vuelta, y esconderla hasta el hoyo 18 le
  /// quita la gracia. Lo que no se puede es enseñarla como definitiva.
  final int hoyosSinCapturar;

  const SnakeResultado({
    required this.hoyo,
    required this.duenos,
    required this.putts,
    required this.umbral,
    required this.hoyosSinCapturar,
  });

  bool get hayDueno => duenos.isNotEmpty;
  bool get provisional => hoyosSinCapturar > 0;
  bool get empatada => duenos.length > 1;
}

class SnakeEngine {
  /// Busca la serpiente entre [pids] recorriendo los hoyos del campo.
  ///
  /// Va de atrás hacia adelante y para en el primer hoyo con alguien por encima
  /// del umbral: ese es el último. Recorrer hacia adelante guardando el máximo
  /// daría lo mismo, pero así queda dicho en el código que lo que se busca es
  /// EL ÚLTIMO y no el peor.
  /// [ordenDeJuego] es la secuencia real de hoyos. Con salida por el 10 es
  /// 10..18 seguido de 1..9, y ES OBLIGATORIO pasarla para que "el último"
  /// signifique el último JUGADO.
  ///
  /// ── El fallo, medido ──────────────────────────────────────────────────────
  ///
  /// Esto ordenaba los hoyos por NÚMERO y los recorría al revés. Con salida por
  /// el 10 eso hace que "el último" sea el 18, que se juega noveno. Ejecutado:
  /// A hace 3 putts en el 16 y B en el 5 —el 5 es el decimocuarto hoyo jugado,
  /// o sea el último de los dos— y la serpiente se le quedaba a A. **A le pagaba
  /// $100 a B teniendo B la serpiente.** No es una etiqueta: es el dinero al
  /// revés.
  ///
  /// Se pide por parámetro en vez de calcularlo aquí para no tener dos
  /// definiciones del orden de juego. La que manda es BetEngine.segmentsOf, y
  /// este motor no puede importarla —BetEngine lo importa a él—, así que la
  /// recibe. Un segundo cálculo del mismo orden es exactamente la clase de
  /// duplicado que esta sesión lleva entera persiguiendo.
  ///
  /// Null solo para los tests que no dependan del orden: entonces cae al orden
  /// por número, que es lo que había.
  static SnakeResultado buscar(
      Round round, List<String> pids, SnakeConfig cfg,
      {List<int>? ordenDeJuego}) {
    final hoyos = ordenDeJuego ??
        (round.course.holes.map((h) => h.hole).toList()..sort());

    var sinCapturar = 0;
    for (final h in hoyos) {
      if (pids.any((pid) => !round.getScore(pid, h).hasScore)) sinCapturar++;
    }

    for (final h in hoyos.reversed) {
      // Solo cuentan los hoyos con score: sin score el hoyo no se jugó, y los
      // putts de un HoleScore vacío son 0 por defecto —no una lectura.
      final culpables = pids.where((pid) {
        final s = round.getScore(pid, h);
        return s.hasScore && s.putts >= cfg.umbral;
      }).toList()
        ..sort();

      if (culpables.isEmpty) continue;

      final putts = culpables
          .map((pid) => round.getScore(pid, h).putts)
          .reduce((a, b) => a > b ? a : b);

      // ── EL ÚLTIMO EN LA SECUENCIA, SI SE DIJO ─────────────────────────────
      //
      // «La serpiente es del último en la secuencia del hoyo.» Con dos o más
      // pasando el umbral en el mismo hoyo, la tarjeta pregunta cuál fue, y la
      // respuesta vive en la ronda. Con ella, el empate desaparece: hay un
      // dueño y no dos.
      //
      // Sin ella —nadie contestó— se cae en la regla de empate, que es lo que
      // pasa cuando el orden no se sabe. Y eso es lo que sustituye a la opción
      // que salió de la configuración: no se pacta, se dice en la pregunta.
      //
      // Se comprueba que el nombrado ESTÉ entre los culpables: una respuesta
      // guardada y luego corregido el score —el que dijo tres putts ahora dice
      // dos— no puede quedarse mandando sobre un hoyo que ya no le toca.
      final dicho = round.ultimoEnPasarElUmbral[h];
      final duenos = culpables.length > 1 && dicho != null &&
              culpables.contains(dicho)
          ? <String>[dicho]
          : culpables;

      return SnakeResultado(
        hoyo: h,
        duenos: duenos,
        putts: putts,
        umbral: cfg.umbral,
        hoyosSinCapturar: sinCapturar,
      );
    }

    return SnakeResultado(
      hoyo: null,
      duenos: const [],
      putts: 0,
      umbral: cfg.umbral,
      hoyosSinCapturar: sinCapturar,
    );
  }

  /// Los asientos de la serpiente.
  ///
  /// El dueño paga [SnakeConfig.value] a cada uno de los demás. Con empate:
  ///
  ///   · ambosPagan → cada dueño paga el monto completo a cada NO dueño. No se
  ///     pagan entre ellos: los dos perdieron, cobrar uno al otro sería decir
  ///     que uno perdió menos.
  ///   · dividen    → el monto se reparte entre los dueños, así que el bolsillo
  ///     de cada uno de los demás recibe lo mismo que con un solo dueño.
  static List<LedgerEntry> liquidar(
      Round round, List<String> pids, BetModuleInstance mod,
      {List<int>? ordenDeJuego}) {
    final cfg = mod.snake;
    final r = buscar(round, pids, cfg, ordenDeJuego: ordenDeJuego);
    if (!r.hayDueno) return const [];

    final duenos = r.duenos.where(pids.contains).toList();
    final resto = pids.where((p) => !duenos.contains(p)).toList();
    if (duenos.isEmpty || resto.isEmpty) return const [];

    final porDueno = cfg.empate == SnakeEmpate.dividen
        ? cfg.value / duenos.length
        : cfg.value;
    if (porDueno <= 0) return const [];

    final motivo = 'Snake H${r.hoyo} · ${r.putts} putts';
    return [
      for (final d in duenos)
        for (final otro in resto)
          LedgerEntry(
            fromPlayerId: d,
            toPlayerId: otro,
            amount: porDueno,
            betType: BetModuleType.snake,
            reason: motivo,
          ),
    ];
  }
}
