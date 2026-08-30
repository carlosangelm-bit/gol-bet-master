// ─────────────────────────────────────────────────────────────────────────────
// EL INVENTARIO DE PATROCINIO — §14.3 del anexo
//
// Vive aparte de la instantánea a propósito, y el motivo es de propiedad: el
// inventario es DEL TORNEO. Lo pacta el organizador con las marcas antes de que
// se juegue nada, sobrevive a cada republicación y sigue ahí cuando la tabla
// cambia doce veces en una tarde. La instantánea solo lo LLEVA.
//
// Tenerlo dentro de leaderboard_publico.dart obligaba además a que el torneo
// importara la instantánea para guardar lo suyo, que es justo del revés.
// ─────────────────────────────────────────────────────────────────────────────

/// Una pieza de patrocinio tal como se proyecta.
///
/// Los campos salen del §11 del manual —lo que el patrocinador entrega— y de las
/// reglas creativas del §6: una marca, un mensaje, una acción. El titular se
/// limita a siete palabras en la aprobación, no aquí: recortarlo en silencio
/// convertiría un incumplimiento en una frase a medias.
class PiezaDePatrocinio {
  /// "PATROCINADOR OFICIAL", "HOYO 9 PRESENTADO POR"… §6 exige que la
  /// naturaleza comercial sea clara, y esta es la etiqueta que lo hace.
  final String etiqueta;

  /// El titular, de siete palabras o menos. Vacío si la pieza es solo logotipo.
  final String titular;

  /// El logotipo. Vacío no es válido para publicar, pero se tolera al leer:
  /// una pieza a medias se omite en la pantalla en vez de romper el documento.
  final String logoUrl;

  /// UN CTA. §6: "Varios botones simultáneos" está prohibido.
  final String? cta;
  final String? destinoUrl;

  /// §6, accesibilidad: texto alternativo descriptivo.
  final String? textoAlternativo;

  const PiezaDePatrocinio({
    required this.etiqueta,
    this.titular = '',
    this.logoUrl = '',
    this.cta,
    this.destinoUrl,
    this.textoAlternativo,
  });

  /// Si la pieza tiene lo mínimo para pintarse.
  bool get pintable => logoUrl.isNotEmpty || titular.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'etiqueta': etiqueta,
        if (titular.isNotEmpty) 'titular': titular,
        if (logoUrl.isNotEmpty) 'logoUrl': logoUrl,
        if (cta != null) 'cta': cta,
        if (destinoUrl != null) 'destinoUrl': destinoUrl,
        if (textoAlternativo != null) 'textoAlternativo': textoAlternativo,
      };

  factory PiezaDePatrocinio.fromJson(Map<String, dynamic> j) =>
      PiezaDePatrocinio(
        etiqueta: (j['etiqueta'] as String?) ?? 'Patrocinado',
        titular: (j['titular'] as String?) ?? '',
        logoUrl: (j['logoUrl'] as String?) ?? '',
        cta: j['cta'] as String?,
        destinoUrl: j['destinoUrl'] as String?,
        textoAlternativo: j['textoAlternativo'] as String?,
      );
}

/// El inventario del §14.3, con lo que hoy tiene origen.
///
/// ── Los dos espacios que quedan fuera, y por qué ──────────────────────────
///
/// El §14.3 contempla además "Ranking de oyes" y "Longest drive" con patrocinio
/// propio. NO están aquí, y no es un olvido: el ranking de oyes existe como
/// formato de apuesta pero no se publica, y el longest drive ni siquiera se
/// captura en la app.
///
/// En un torneo real los mide alguien del staff en los par 3 y en el tee del
/// drive, y los carga el organizador. O sea que dependen de la web de
/// organizador, que todavía no existe. Cuando exista, entran aquí y su
/// patrocinio con ellos.
class InventarioProyectado {
  /// El titular del torneo. Persistente, §14.3.
  final PiezaDePatrocinio? cabecera;

  /// Los socios del evento. Rota, y aquí SÍ se puede: §14.2 — en una pantalla
  /// de TV la rotación es lo esperado, y la prohibición del manual (§5.4,
  /// "evitar carrusel automático obligatorio") habla de los socios dentro de la
  /// app, donde compiten con controles.
  final List<PiezaDePatrocinio> pie;

  /// 300×600, solo si el ancho lo permite. §14.3 y §5.3.
  final PiezaDePatrocinio? lateral;

  /// Cada cuántos segundos rota el pie. Cero o menos = sin rotación.
  final int segundosDeRotacion;

  const InventarioProyectado({
    this.cabecera,
    this.pie = const [],
    this.lateral,
    this.segundosDeRotacion = 12,
  });

  bool get vacio => cabecera == null && pie.isEmpty && lateral == null;

  Map<String, dynamic> toJson() => {
        if (cabecera != null) 'cabecera': cabecera!.toJson(),
        if (pie.isNotEmpty) 'pie': pie.map((p) => p.toJson()).toList(),
        if (lateral != null) 'lateral': lateral!.toJson(),
        'segundosDeRotacion': segundosDeRotacion,
      };

  factory InventarioProyectado.fromJson(Map<String, dynamic> j) =>
      InventarioProyectado(
        cabecera: j['cabecera'] is Map
            ? PiezaDePatrocinio.fromJson(
                Map<String, dynamic>.from(j['cabecera'] as Map))
            : null,
        pie: [
          for (final p in (j['pie'] as List?) ?? const [])
            if (p is Map)
              PiezaDePatrocinio.fromJson(Map<String, dynamic>.from(p))
        ],
        lateral: j['lateral'] is Map
            ? PiezaDePatrocinio.fromJson(
                Map<String, dynamic>.from(j['lateral'] as Map))
            : null,
        segundosDeRotacion:
            (j['segundosDeRotacion'] as num?)?.toInt() ?? 12,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// LOS ESPACIOS, CON SUS MEDIDAS — §5 y §14.3
//
// Existe como catálogo y no como texto suelto en la pantalla por lo mismo que
// el catálogo de configuración de apuestas: si las medidas se escriben en el
// editor, la tele acaba pintando una cosa y el organizador entregándole otra al
// patrocinador. Una definición, y las dos superficies la leen.
//
// Los dos espacios que faltan —ranking de oyes y longest drive— no están aquí a
// propósito: los mide alguien del staff en el campo y dependen de la web de
// organizador. Cuando existan, entran aquí y su patrocinio con ellos.
// ─────────────────────────────────────────────────────────────────────────────

enum EspacioDePatrocinio { cabecera, pie, lateral }

extension EspacioInfo on EspacioDePatrocinio {
  String get titulo => switch (this) {
        EspacioDePatrocinio.cabecera => 'Cabecera',
        EspacioDePatrocinio.pie => 'Pie rotatorio',
        EspacioDePatrocinio.lateral => 'Lateral',
      };

  /// La medida que hay que pedirle al patrocinador. §5 del manual.
  String get medida => switch (this) {
        EspacioDePatrocinio.cabecera => '728 × 90',
        EspacioDePatrocinio.pie => '240 × 60 por logotipo',
        EspacioDePatrocinio.lateral => '300 × 600',
      };

  /// Dónde sale y qué se juega ahí.
  String get donde => switch (this) {
        EspacioDePatrocinio.cabecera =>
          'Banner ancho en la pantalla del club, visible las ocho horas. Es la '
              'pieza más vista del día.',
        EspacioDePatrocinio.pie =>
          'Tira de logotipos al pie, rotando entre sí. En una TV la rotación es '
              'lo esperado; dentro de la app estaría prohibida.',
        EspacioDePatrocinio.lateral =>
          'Columna alta, solo si la pantalla es ancha. En una más estrecha '
              'desaparece antes de comprimir la tabla.',
      };

  /// El nombre del archivo en Storage. Sin espacios ni acentos.
  String get clave => name;
}

/// Lo que el patrocinador tiene que entregar. §11 del manual.
///
/// La pantalla PIDE esto, en este orden, y dice cuál es obligatorio. Se lista
/// aquí para que el editor no invente su propia lista: el día que el manual
/// añada un activo, se añade en un sitio.
class ActivoPedido {
  final String etiqueta;
  final String ejemplo;
  final String porQue;
  final bool obligatorio;

  const ActivoPedido({
    required this.etiqueta,
    required this.ejemplo,
    required this.porQue,
    this.obligatorio = false,
  });
}

const activosDelPatrocinador = <ActivoPedido>[
  ActivoPedido(
    etiqueta: 'Etiqueta de patrocinio',
    ejemplo: 'Patrocinador oficial',
    // §6: la naturaleza comercial tiene que ser clara. Sin esto se pinta una
    // marca sin decir que es publicidad.
    porQue: 'Obligatoria: sin ella se pinta una marca sin decir que es '
        'publicidad.',
    obligatorio: true,
  ),
  ActivoPedido(
    etiqueta: 'Logotipo',
    ejemplo: 'PNG con fondo transparente, o SVG',
    porQue: 'Se guarda con el torneo, no se enlaza al servidor de la marca: si '
        'su web cambia, el banner que pagaron sigue saliendo.',
  ),
  ActivoPedido(
    etiqueta: 'Titular',
    ejemplo: 'Eleva cada gran ronda',
    porQue: 'Máximo siete palabras. Se avisa si pasa, no se recorta.',
  ),
  ActivoPedido(
    etiqueta: 'Texto alternativo del logotipo',
    ejemplo: 'Logotipo de la marca',
    porQue: 'Para quien no ve la imagen. Lo entrega la marca, no se inventa.',
  ),
  ActivoPedido(
    etiqueta: 'Llamada a la acción',
    ejemplo: 'Conoce la experiencia',
    porQue: 'Una marca, un mensaje, UNA acción.',
  ),
  ActivoPedido(
    etiqueta: 'Enlace de destino',
    ejemplo: 'https://…',
    porQue: 'A dónde lleva la acción.',
  ),
];

/// Las palabras de un titular. Siete es el máximo del §6.2.
int palabrasDelTitular(String titular) =>
    titular.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

const maxPalabrasTitular = 7;
