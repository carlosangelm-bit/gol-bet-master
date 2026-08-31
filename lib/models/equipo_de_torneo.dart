// ─────────────────────────────────────────────────────────────────────────────
// LOS EQUIPOS DEL TORNEO — el caso normal, no un formato más
//
// «La inmensa mayoría de los torneos recreativos se juegan por equipos de 4. Es
// importante mantener la funcionalidad individual porque habrá algunos torneos
// individuales, pero la gran mayoría son en equipo.»
//
// ── EL EQUIPO ES EL GRUPO DE SALIDA. No una capa encima ─────────────────────
//
// «En juego de equipos es posible que en los par 3 salgan Hoyo 5A, Hoyo 5B, y
// cada hoyo con dos equipos de 4.»
//
// O sea: lo que `Grupos y salidas` ya reparte SON los equipos. Un equipo no es
// una agrupación que se define aparte y luego se cruza con las salidas — es la
// misma cosa mirada desde otro lado. Por eso este archivo no tiene ninguna
// función para "formar equipos": los forma `planDeShotgun`, y esto solo les
// pone número y nombre.
//
// Modelarlo aparte habría dado dos listas que hay que mantener de acuerdo, y la
// que se desincronizara sería la que nadie mira hasta el sábado.
//
// ── EL NÚMERO ES LA IDENTIDAD; EL NOMBRE, UN AÑADIDO ────────────────────────
//
// «Si el equipo decide agregar nombre a su equipo puede hacerlo, si no se queda
// con su número.»
//
// Así que el número no es opcional y el nombre sí. Y el número va con dos
// cifras —Equipo 07— porque en una lista de veintidós, "Equipo 7" y "Equipo 17"
// no se alinean y el ojo los confunde a diez metros.
// ─────────────────────────────────────────────────────────────────────────────

/// Un equipo del torneo: su número, su gente y desde dónde sale.
class EquipoDeTorneo {
  /// Desde 1. Es la identidad: existe siempre, aunque no haya nombre.
  final int numero;

  /// El que se pone el equipo. Vacío = se queda con su número.
  final String nombre;

  /// Los ids del padrón que juegan en él.
  final List<String> miembros;

  /// El hoyo de salida y su letra, si comparte tee.
  final int hoyoDeSalida;
  final String? letraDeSalida;

  const EquipoDeTorneo({
    required this.numero,
    this.nombre = '',
    required this.miembros,
    required this.hoyoDeSalida,
    this.letraDeSalida,
  });

  /// El identificador estable del equipo dentro del torneo.
  ///
  /// Sale del NÚMERO y no del nombre, que puede cambiar: el equipo 7 sigue
  /// siendo el 7 cuando se llame Sierra. Es la sexta vez en el proyecto que
  /// esto importa, y aquí estaba fácil equivocarse porque el nombre es lo que
  /// se ve.
  String get id => 'e${numero.toString().padLeft(2, '0')}';

  /// «Equipo 07» o «Equipo 07 · Sierra».
  String get etiqueta {
    final base = 'Equipo ${numero.toString().padLeft(2, '0')}';
    return nombre.isEmpty ? base : '$base · $nombre';
  }

  /// De dónde sale. «Hoyo 7» o «Hoyo 7B».
  String get salida => 'Hoyo $hoyoDeSalida${letraDeSalida ?? ''}';

  EquipoDeTorneo con({String? nombre, List<String>? miembros}) =>
      EquipoDeTorneo(
        numero: numero,
        nombre: nombre ?? this.nombre,
        miembros: miembros ?? this.miembros,
        hoyoDeSalida: hoyoDeSalida,
        letraDeSalida: letraDeSalida,
      );

  Map<String, dynamic> toJson() => {
        'numero': numero,
        if (nombre.isNotEmpty) 'nombre': nombre,
        'miembros': miembros,
        'hoyoDeSalida': hoyoDeSalida,
        if (letraDeSalida != null) 'letraDeSalida': letraDeSalida,
      };

  factory EquipoDeTorneo.fromJson(Map<String, dynamic> j) => EquipoDeTorneo(
        numero: (j['numero'] as num?)?.toInt() ?? 0,
        nombre: (j['nombre'] as String?) ?? '',
        miembros:
            ((j['miembros'] as List?) ?? const []).map((e) => '$e').toList(),
        hoyoDeSalida: (j['hoyoDeSalida'] as num?)?.toInt() ?? 1,
        letraDeSalida: j['letraDeSalida'] as String?,
      );
}

/// Por dónde va un equipo. Es el `Thru` del leaderboard.
///
/// ── Por qué es un tipo y no un int ─────────────────────────────────────────
///
/// «Un jugador mirando el leaderboard desde el campo espera saber por dónde va
/// el líder.» Y para que eso sea CIERTO hace falta más que el número del hoyo:
/// hace falta saber CUÁNDO se supo. Un "va por el 12" de hace dos horas es peor
/// que no decir nada, y es exactamente el motivo por el que el Thru se había
/// descartado.
///
/// Así que el dato lleva su hora, y la pantalla decide si todavía vale.
class ThruDeEquipo {
  /// El último hoyo con score. 0 = no ha empezado.
  final int hoyo;

  /// Cuántos hoyos lleva anotados. Con salida en el 7, el hoyo 3 puede ser el
  /// catorceavo jugado: los dos números dicen cosas distintas y hacen falta
  /// los dos.
  final int llevados;

  /// De cuántos. Sale de la ronda, no se supone 18.
  final int total;

  final DateTime cuando;

  const ThruDeEquipo({
    required this.hoyo,
    required this.llevados,
    required this.total,
    required this.cuando,
  });

  /// Terminó todos sus hoyos.
  bool get termino => total > 0 && llevados >= total;

  /// Lo que se pinta: `F` al terminar, el hoyo si va jugando, `—` si no empezó.
  String get etiqueta =>
      termino ? 'F' : (llevados == 0 ? '—' : '$hoyo');

  /// Si este dato es lo bastante reciente para enseñarlo como "en vivo".
  ///
  /// Media hora es el tope, y sale de lo que tarda un grupo en un hoyo: por
  /// encima de eso, o el equipo se paró o dejó de anotar, y en los dos casos el
  /// número ya no dice por dónde van.
  bool vigente(DateTime ahora) =>
      ahora.difference(cuando).inMinutes.abs() <= 30;

  Map<String, dynamic> toJson() => {
        'hoyo': hoyo,
        'llevados': llevados,
        'total': total,
        'cuando': cuando.toIso8601String(),
      };

  factory ThruDeEquipo.fromJson(Map<String, dynamic> j) => ThruDeEquipo(
        hoyo: (j['hoyo'] as num?)?.toInt() ?? 0,
        llevados: (j['llevados'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toInt() ?? 0,
        cuando:
            DateTime.tryParse((j['cuando'] as String?) ?? '') ?? DateTime(2000),
      );
}

/// Un grupo del torneo tal como lo ve el organizador: quién juega y por dónde va.
///
/// ── Por qué es una clase y no un registro anónimo ──────────────────────────
///
/// Era un `({String roundId, String nombre, ...})` escrito CUATRO veces: en la
/// firma del servicio, en su variable local, en la pantalla del torneo y en la
/// del portal. Añadirle un campo obligó a tocar las cuatro, y las cuatro
/// dejaron de compilar a la vez — que fue la suerte. Con una quinta copia en
/// otro paquete, la que se quedara atrás habría sido un `as` silencioso.
class GrupoDelTorneo {
  final String roundId;
  final String nombre;
  final List<String> jugadores;

  /// Cuántos hoyos tienen ya score de alguien.
  final int hoyosCapturados;

  /// El ÚLTIMO hoyo con score. Distinto de [hoyosCapturados]: con salida en el
  /// 7, el catorceavo hoyo jugado es el 3.
  final int ultimoHoyo;

  final int totalHoles;
  final bool cerrada;

  const GrupoDelTorneo({
    required this.roundId,
    required this.nombre,
    required this.jugadores,
    required this.hoyosCapturados,
    required this.ultimoHoyo,
    required this.totalHoles,
    required this.cerrada,
  });

  /// El Thru de este grupo, con la hora de ahora.
  ThruDeEquipo thru(DateTime ahora) => ThruDeEquipo(
        hoyo: ultimoHoyo,
        llevados: hoyosCapturados,
        total: totalHoles,
        cuando: ahora,
      );
}
