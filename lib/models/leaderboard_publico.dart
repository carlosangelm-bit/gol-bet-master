// ─────────────────────────────────────────────────────────────────────────────
// LEADERBOARD PÚBLICO — la instantánea que ve cualquiera que pase
//
// Es la superficie del §14 del anexo de patrocinios: una vista del torneo para
// PROYECTAR en la casa club, con su propio enlace y sin sesión.
//
// ── Por qué es un documento aparte y no un permiso más suelto ────────────────
//
// `sharedTorneos` exige cuenta, y la razón está escrita en las propias reglas:
// "se pide cuenta porque aquí hay dinero y nombres de terceros a la vista".
// Una tele en la casa club no tiene sesión, así que la tentación es relajar esa
// regla. Sería el error.
//
// Una pantalla proyectada es la superficie MÁS EXPUESTA de todo el sistema: la
// ve cualquiera que pase por delante, incluidos los que no juegan, los que no
// están invitados y el que entrega los palos. El dinero no puede estar ahí — y
// la forma de garantizarlo no es no mostrarlo, es QUE NO ESTÉ. Mismo principio
// que ya sostiene la instantánea del enlace: si al construirla dudas de si un
// campo entra, no entra.
//
// Así que son dos documentos con dos reglas: `sharedTorneos` sigue pidiendo
// cuenta y llevando botes y balances; este se lee sin sesión y no lleva un solo
// importe.
//
// ── LA MEDICIÓN ES POR TORNEO, NUNCA POR PERSONA ────────────────────────────
//
// Decisión de Carlos, y sustituye a la §9 del manual v1.0 en un punto: la
// métrica "Frecuencia — exposiciones promedio por jugador" DESAPARECE, junto a
// cualquier otra que exija saber quién vio qué.
//
// El motivo, para que no se "recupere" más adelante creyendo que falta: "el
// banner se mostró 1.240 veces durante el torneo" le sirve igual al patrocinador
// que saber quién lo vio, y no requiere seguir a nadie. Es la misma razón por la
// que se descartó el correo en el módulo de organizador: llega antes al
// formulario de privacidad de App Store que a la pantalla.
//
// Por eso este archivo no tiene ni un identificador de persona. Los contadores
// que vengan después se suman por torneo y por pieza, no por jugador.
// ─────────────────────────────────────────────────────────────────────────────
import 'patrocinio.dart';
import 'torneo.dart';

export 'patrocinio.dart';

/// Una fila de la clasificación proyectada. **Sin importes.**
class FilaProyectada {
  final int puesto;
  final String nombre;

  /// Cuántas rondas jugó. Un número de partidas, no de dinero.
  final int jugadas;

  /// La medida con la que va clasificado, si NO es dinero.
  ///
  /// ── El caso que obliga a que esto sea opcional ────────────────────────────
  ///
  /// La tabla del torneo guarda un `total` cuyo significado depende del método:
  /// con "por posición" son puntos, con "por score neto" son golpes, y con "por
  /// dinero ganado" SON PESOS. Copiar el total sin mirar el método publicaría
  /// dinero en la pantalla más expuesta del sistema, y sin que nada avisara.
  ///
  /// Así que se copia solo cuando la medida no es dinero, y cuando lo es, esto
  /// queda en null y la pantalla dice por qué —ver [ocultaLaMedida]—. Un torneo
  /// que se clasifica por dinero se puede proyectar igual: se ve quién va
  /// primero, no cuánto lleva.
  final double? medida;

  /// El score CONTRA EL PAR, cuando el torneo se puntúa por score.
  ///
  /// ── Es la columna que hace que se reconozca un leaderboard de golf ────────
  ///
  /// `-7` en rojo y el par en blanco es lo primero que identifica la pantalla,
  /// antes de leer un solo nombre. Sin esto la columna dice `284` y podría ser
  /// cualquier tabla ordenada.
  ///
  /// Null en tres casos distintos, y los tres son honestos:
  ///
  ///   · el torneo NO se puntúa por score —por dinero, por posición o por
  ///     Stableford—, y entonces "bajo par" no significa nada
  ///   · alguna de las rondas que cuentan es anterior a que se guardara el par
  ///   · el jugador no ha jugado ninguna
  ///
  /// En los tres la pantalla enseña la medida a secas. Inventar un par de 72
  /// sería un número plausible sustituyendo a uno que falta.
  final int? bajoPar;

  const FilaProyectada({
    required this.puesto,
    required this.nombre,
    required this.jugadas,
    this.medida,
    this.bajoPar,
  });

  Map<String, dynamic> toJson() => {
        'puesto': puesto,
        'nombre': nombre,
        'jugadas': jugadas,
        if (medida != null) 'medida': medida,
        if (bajoPar != null) 'bajoPar': bajoPar,
      };

  factory FilaProyectada.fromJson(Map<String, dynamic> j) => FilaProyectada(
        puesto: (j['puesto'] as num?)?.toInt() ?? 0,
        nombre: (j['nombre'] as String?) ?? '—',
        jugadas: (j['jugadas'] as num?)?.toInt() ?? 0,
        medida: (j['medida'] as num?)?.toDouble(),
        bajoPar: (j['bajoPar'] as num?)?.toInt(),
      );
}


/// La instantánea que se proyecta. Vive en `leaderboards/{token}`.
class LeaderboardPublico {
  /// El token del enlace. Es el id del documento.
  final String token;

  /// Quién lo publicó. Lo usa la regla para saber quién puede actualizarlo;
  /// no se enseña. Es un uid de cuenta, no identifica a un jugador de la tabla.
  final String ownerUid;

  final String nombre;
  final String emoji;

  /// Cuándo se publicó esta copia. Igual que en la instantánea con dinero: es
  /// lo que separa esto de un total guardado en silencio.
  final DateTime publicadoEn;

  /// Cómo puntúa, en texto ya resuelto.
  final String comoSePuntua;

  /// Si la medida de la clasificación se oculta por ser dinero.
  ///
  /// Cuando es true la pantalla enseña puestos y nombres sin cifra, y lo dice.
  /// Un hueco sin explicación se lee como un fallo de carga.
  final bool ocultaLaMedida;

  final int rondas;
  final bool cerrado;

  /// Si el enlace está encendido. Apagado deja el documento con solo el dueño y
  /// esta bandera, igual que sharedTorneos: revocar sin romper el enlace.
  final bool activo;

  final List<FilaProyectada> tabla;
  final InventarioProyectado inventario;

  /// Por dónde va cada equipo, en vivo. Clave: el id del equipo.
  ///
  /// ── UN MAPA, y no una columna más de la tabla ─────────────────────────────
  ///
  /// La tabla es una LISTA, y una lista no se puede escribir por partes: para
  /// tocar una fila hay que reescribir el array entero, y eso significa que
  /// quien publique tiene que traer la tabla completa. Con veintidós equipos
  /// anotando, dos publicaciones a la vez se pisan y la que llega segunda borra
  /// el avance de la primera.
  ///
  /// Un MAPA sí: `thru.e07` es una ruta de campo, y Firestore la actualiza sin
  /// tocar `thru.e12` ni la tabla ni el inventario. Es lo que hace que esto se
  /// pueda escribir cada pocos minutos sin arriesgar lo demás.
  ///
  /// Vacío en los torneos individuales, y por eso no ocupa nada en ellos.
  final Map<String, ThruDeEquipo> thru;

  /// Cómo quiere verse este torneo en la pared.
  ///
  /// Viaja con la instantánea y no se lee del torneo, por el mismo motivo que
  /// todo lo demás de aquí: la tele no tiene sesión y no puede leer el
  /// documento del torneo. Lo que se proyecta es lo que se publicó.
  final IdentidadDeTorneo identidad;

  const LeaderboardPublico({
    required this.token,
    required this.ownerUid,
    required this.nombre,
    required this.emoji,
    required this.publicadoEn,
    required this.comoSePuntua,
    required this.rondas,
    this.ocultaLaMedida = false,
    this.cerrado = false,
    this.activo = true,
    this.tabla = const [],
    this.inventario = const InventarioProyectado(),
    this.identidad = const IdentidadDeTorneo(),
    this.thru = const {},
  });

  /// Construye la copia proyectable desde la tabla YA CALCULADA.
  ///
  /// Recibe lo derivado, como [TorneoPublicado.desde], y por el mismo motivo: un
  /// segundo cálculo aquí podría discrepar del que se ve en la app.
  ///
  /// Los que no llegan al mínimo entran también: jugaron, y en una pantalla de
  /// casa club no verse es peor que verse al final.
  factory LeaderboardPublico.desde({
    required String token,
    required String ownerUid,
    required Torneo torneo,
    required TablaDelTorneo tabla,
    required DateTime cuando,
    InventarioProyectado inventario = const InventarioProyectado(),
  }) {
    final metodo = metodoEfectivo(torneo);
    // La medida solo viaja si NO es dinero. Ver FilaProyectada.medida.
    final esDinero = metodo == MetodoDePuntuacion.dinero;

    // El score contra el par solo tiene sentido cuando la medida ES el score.
    // Con Stableford más es mejor y el par no entra; con dinero o por posición
    // la medida ni siquiera son golpes.
    final porScore = metodo == MetodoDePuntuacion.scoreNeto;

    FilaProyectada fila(FilaDelTorneo f) => FilaProyectada(
          puesto: f.puesto,
          nombre: f.nombre,
          jugadas: f.jugadas,
          medida: esDinero ? null : f.total,
          bajoPar: porScore && f.parDeLasQueCuentan != null && f.jugadas > 0
              ? f.total.round() - f.parDeLasQueCuentan!
              : null,
        );

    return LeaderboardPublico(
      token: token,
      ownerUid: ownerUid,
      nombre: torneo.nombre,
      emoji: torneo.emoji,
      publicadoEn: cuando,
      comoSePuntua: metodo.descripcion,
      ocultaLaMedida: esDinero,
      rondas: tabla.rondas,
      cerrado: torneo.cerrado,
      tabla: [
        ...tabla.filas.map(fila),
        ...tabla.bajoMinimo.map(fila),
      ],
      inventario: inventario,
      identidad: torneo.identidad,
    );
  }

  /// El Thru de la fila cuyo nombre es [nombreDeFila], si está vigente.
  ///
  /// Se busca por NOMBRE porque es lo único que la fila proyectada lleva —no
  /// hay ids de persona en este documento, y no los va a haber—. El nombre de
  /// una fila de equipo es su etiqueta, «Equipo 07 · Sierra», y el equipo
  /// guarda la misma. Es un emparejamiento por texto y conviene saberlo: si el
  /// equipo se renombra a mitad de ronda, su Thru se queda sin fila hasta la
  /// siguiente publicación de la tabla.
  ///
  /// Null cuando no hay dato, cuando el torneo es individual, o cuando el dato
  /// ha caducado. Los tres se pintan igual: con lo que sí es cierto.
  ThruDeEquipo? thruDe(String nombreDeFila, DateTime ahora) {
    if (thru.isEmpty) return null;
    for (final e in thru.entries) {
      final suyo = e.value;
      if (!suyo.vigente(ahora)) continue;
      // La clave es el id del equipo —«e07»— y la fila lleva su etiqueta. El
      // número es lo que las une, y es lo que no cambia al renombrar.
      final numero = e.key.replaceAll(RegExp(r'[^0-9]'), '');
      if (numero.isNotEmpty &&
          nombreDeFila.contains(numero.padLeft(2, '0'))) {
        return suyo;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'ownerUid': ownerUid,
        'nombre': nombre,
        'emoji': emoji,
        'publicadoEn': publicadoEn.toIso8601String(),
        'comoSePuntua': comoSePuntua,
        'rondas': rondas,
        if (ocultaLaMedida) 'ocultaLaMedida': true,
        if (cerrado) 'cerrado': true,
        // Solo cuando está apagado: un enlace vivo no engorda el documento.
        if (!activo) 'activo': false,
        'tabla': tabla.map((f) => f.toJson()).toList(),
        if (!inventario.vacio) 'inventario': inventario.toJson(),
        if (!identidad.vacia) 'identidad': identidad.toJson(),
        if (thru.isNotEmpty)
          'thru': {for (final e in thru.entries) e.key: e.value.toJson()},
      };

  factory LeaderboardPublico.fromJson(String token, Map<String, dynamic> j) =>
      LeaderboardPublico(
        token: token,
        ownerUid: (j['ownerUid'] as String?) ?? '',
        nombre: (j['nombre'] as String?) ?? 'Torneo',
        emoji: (j['emoji'] as String?) ?? 'trofeo',
        publicadoEn:
            DateTime.tryParse((j['publicadoEn'] as String?) ?? '') ??
                DateTime(2000),
        comoSePuntua: (j['comoSePuntua'] as String?) ?? '',
        rondas: (j['rondas'] as num?)?.toInt() ?? 0,
        ocultaLaMedida: j['ocultaLaMedida'] == true,
        cerrado: j['cerrado'] == true,
        activo: j['activo'] != false,
        tabla: [
          for (final f in (j['tabla'] as List?) ?? const [])
            if (f is Map)
              FilaProyectada.fromJson(Map<String, dynamic>.from(f))
        ],
        inventario: j['inventario'] is Map
            ? InventarioProyectado.fromJson(
                Map<String, dynamic>.from(j['inventario'] as Map))
            : const InventarioProyectado(),
        identidad: j['identidad'] is Map
            ? IdentidadDeTorneo.fromJson(
                Map<String, dynamic>.from(j['identidad'] as Map))
            : const IdentidadDeTorneo(),
        thru: {
          for (final e in ((j['thru'] as Map?) ?? const {}).entries)
            if (e.value is Map)
              '${e.key}':
                  ThruDeEquipo.fromJson(Map<String, dynamic>.from(e.value as Map))
        },
      );
}
