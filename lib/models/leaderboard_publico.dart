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

  const FilaProyectada({
    required this.puesto,
    required this.nombre,
    required this.jugadas,
    this.medida,
  });

  Map<String, dynamic> toJson() => {
        'puesto': puesto,
        'nombre': nombre,
        'jugadas': jugadas,
        if (medida != null) 'medida': medida,
      };

  factory FilaProyectada.fromJson(Map<String, dynamic> j) => FilaProyectada(
        puesto: (j['puesto'] as num?)?.toInt() ?? 0,
        nombre: (j['nombre'] as String?) ?? '—',
        jugadas: (j['jugadas'] as num?)?.toInt() ?? 0,
        medida: (j['medida'] as num?)?.toDouble(),
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

    FilaProyectada fila(FilaDelTorneo f) => FilaProyectada(
          puesto: f.puesto,
          nombre: f.nombre,
          jugadas: f.jugadas,
          medida: esDinero ? null : f.total,
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
    );
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
      };

  factory LeaderboardPublico.fromJson(String token, Map<String, dynamic> j) =>
      LeaderboardPublico(
        token: token,
        ownerUid: (j['ownerUid'] as String?) ?? '',
        nombre: (j['nombre'] as String?) ?? 'Torneo',
        emoji: (j['emoji'] as String?) ?? '🏆',
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
      );
}
