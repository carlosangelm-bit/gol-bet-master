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

  /// Si el torneo está cerrado y liquidado.
  ///
  /// Cerrado no significa "pagado" —la app no procesa pagos— significa que la
  /// tabla ya no va a cambiar y el reparto es el definitivo.
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
    this.participantes = const [],
    this.minimoRondas = 0,
    this.bote = BoteConfig.def,
    this.tokenCompartido,
    this.publicadoEn,
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
    List<String>? participantes,
    int? minimoRondas,
    BoteConfig? bote,
    String? tokenCompartido,
    DateTime? publicadoEn,
    bool limpiarCompartido = false,
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
        participantes: participantes ?? this.participantes,
        minimoRondas: minimoRondas ?? this.minimoRondas,
        bote: bote ?? this.bote,
        tokenCompartido:
            limpiarCompartido ? null : (tokenCompartido ?? this.tokenCompartido),
        publicadoEn:
            limpiarCompartido ? null : (publicadoEn ?? this.publicadoEn),
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
        if (participantes.isNotEmpty) 'participantes': participantes,
        if (minimoRondas > 0) 'minimoRondas': minimoRondas,
        if (bote.hayAlgunBote) 'bote': bote.toJson(),
        if (tokenCompartido != null) 'tokenCompartido': tokenCompartido,
        if (publicadoEn != null) 'publicadoEn': publicadoEn!.toIso8601String(),
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
        participantes: ((j['participantes'] as List?) ?? const [])
            .map((e) => '$e')
            .toList(),
        minimoRondas: (j['minimoRondas'] as num?)?.toInt() ?? 0,
        bote: j['bote'] == null
            ? BoteConfig.def
            : BoteConfig.fromJson(Map<String, dynamic>.from(j['bote'] as Map)),
        tokenCompartido: j['tokenCompartido'] as String?,
        publicadoEn: DateTime.tryParse((j['publicadoEn'] as String?) ?? ''),
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

  // Los inscritos que no han jugado ninguna: estar inscrito es un hecho aunque
  // no hayas ido, y no verte en la lista después de poner el bote sería raro.
  final sinJugar = <String>[];
  for (final pid in t.participantes) {
    if (porJugador.containsKey(pid)) continue;
    sinJugar.add(pid);
    filas.add(FilaDelTorneo(
      playerId: pid,
      nombre: nombres[pid] ?? pid,
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
BoteDelTorneo boteDe(Torneo t, TablaDelTorneo tabla) {
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
  if (tabla.rondas > 0 && tabla.filas.isNotEmpty && total > 0) {
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
        : 'El torneo está abierto: el reparto cambia con cada ronda que entre. '
            'Ciérralo cuando la temporada acabe para dejarlo fijo.',
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
  // Con lista de participantes el número lo decide el organizador, así que no
  // hay nada que avisar: el aviso existía porque la fuente arrastraba gente.
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
