// ─────────────────────────────────────────────────────────────────────────────
// TORNEO — una VISTA sobre rondas que ya existen
//
// La idea que ordena todo el archivo: un torneo no cambia cómo se juega. Es
// *qué rondas cuentan* + *cómo puntúa cada una* + *cómo se acumula* + *quién
// entra*. Nada de eso toca el motor de apuestas, y por eso el formato corto y el
// de temporada son EL MISMO objeto con parámetros distintos, no dos
// funcionalidades.
//
// Y la tabla se DERIVA, nunca se guarda calculada. Es la lección del RoundResult
// desfasado: el tablero de Inicio guardó los balances al cerrar la ronda y
// cuando la liquidación se corrigió, esos números se quedaron viejos sin avisar.
// Aquí no puede pasar: [tablaDe] recibe los resultados y calcula. Si una ronda
// cambia, la tabla siguiente ya sale distinta.
// ─────────────────────────────────────────────────────────────────────────────
import 'round_result.dart';

/// De dónde salen las rondas que cuentan.
enum FuenteDeRondas {
  /// Elegidas a mano, una por una.
  manual,

  /// Todas las cerradas entre dos fechas.
  rango,

  /// Todas las de un grupo de apuesta guardado, opcionalmente con rango.
  ///
  /// Es la más natural para el uso real —"todas las de Viernes CGM entre marzo y
  /// noviembre"— y por eso combina grupo Y fechas en vez de ser excluyentes.
  grupo,
}

extension FuenteDeRondasLabel on FuenteDeRondas {
  String get label => switch (this) {
        FuenteDeRondas.manual => 'Elegidas a mano',
        FuenteDeRondas.rango => 'Por fechas',
        FuenteDeRondas.grupo => 'De un grupo de apuesta',
      };

  String get descripcion => switch (this) {
        FuenteDeRondas.manual =>
          'Tú marcas qué rondas cuentan. Para un torneo de un fin de semana.',
        FuenteDeRondas.rango =>
          'Todas las rondas cerradas entre dos fechas, sean del grupo que sean.',
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
class Torneo {
  final String id;
  final String nombre;
  final String emoji;

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

  /// Rondas mínimas para salir en la tabla. 0 = todos.
  final int minimoRondas;

  /// Si el torneo está cerrado y liquidado.
  final bool cerrado;

  const Torneo({
    required this.id,
    required this.nombre,
    this.emoji = '🏆',
    this.fuente = FuenteDeRondas.grupo,
    this.roundIds = const [],
    this.desde,
    this.hasta,
    this.bettingGroupId,
    this.metodo = MetodoDePuntuacion.posicion,
    this.puntosPorPuesto = const [10, 6, 4, 2, 1],
    this.empate = ReglaDeEmpate.reparten,
    this.acumulacion = Acumulacion.sumaSimple,
    this.mejoresN = 10,
    this.minimoRondas = 0,
    this.cerrado = false,
  });

  Torneo copyWith({
    String? nombre,
    String? emoji,
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
    int? minimoRondas,
    bool? cerrado,
  }) =>
      Torneo(
        id: id,
        nombre: nombre ?? this.nombre,
        emoji: emoji ?? this.emoji,
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
        minimoRondas: minimoRondas ?? this.minimoRondas,
        cerrado: cerrado ?? this.cerrado,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'emoji': emoji,
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
        if (minimoRondas > 0) 'minimoRondas': minimoRondas,
        if (cerrado) 'cerrado': true,
      };

  factory Torneo.fromJson(Map<String, dynamic> j) => Torneo(
        id: (j['id'] as String?) ?? '',
        nombre: (j['nombre'] as String?) ?? 'Torneo',
        emoji: (j['emoji'] as String?) ?? '🏆',
        fuente: FuenteDeRondas.values.firstWhere((f) => f.name == j['fuente'],
            orElse: () => FuenteDeRondas.grupo),
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
        minimoRondas: (j['minimoRondas'] as num?)?.toInt() ?? 0,
        cerrado: j['cerrado'] == true,
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

  const RondaDelTorneo({
    required this.roundId,
    required this.nombreRonda,
    required this.fecha,
    required this.medida,
    required this.puntos,
    required this.puesto,
    required this.cuenta,
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
  });

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
      nombreDe[pid] = nombres[pid] ?? r.playerNames[pid] ?? pid;
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
    filas.add(FilaDelTorneo(
      playerId: entrada.key,
      nombre: nombreDe[entrada.key] ?? entrada.key,
      rondas: marcadas,
      total: _redondea(total),
      puesto: 0, // se asigna al ordenar
      bajoMinimo: marcadas.length < t.minimoRondas,
    ));
  }

  // El orden de la TABLA. Con score neto, menos es mejor.
  filas.sort((a, b) => t.metodo.masEsMejor
      ? b.total.compareTo(a.total)
      : a.total.compareTo(b.total));

  final clasificados = filas.where((f) => !f.bajoMinimo).toList();
  final fuera = filas.where((f) => f.bajoMinimo).toList();

  return TablaDelTorneo(
    filas: _conPuestos(clasificados),
    bajoMinimo: _conPuestos(fuera),
    rondas: rondas.length - sinDato,
    rondasSinDato: sinDato,
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
