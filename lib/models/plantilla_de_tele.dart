// ─────────────────────────────────────────────────────────────────────────────
// LAS PLANTILLAS DE LA TELE — identidad del torneo sin poder romperla
//
// «La pantalla no se parece a un gráfico de la PGA. Creo que debería haber
// varios diseños a elegir que fueran en línea con la identidad que quiere el
// torneo.»
//
// ── QUÉ SE PUEDE TOCAR, Y POR QUÉ ESO Y NO MÁS ──────────────────────────────
//
// Un selector de color libre para todo es lo que produce, el día del torneo y
// con prisa, un texto gris sobre fondo gris proyectado ocho horas. Y una
// plantilla totalmente cerrada no deja que un torneo corporativo se vea suyo,
// que es justo lo que se pedía.
//
// El reparto sale de separar lo que da IDENTIDAD de lo que da LEGIBILIDAD:
//
//   · EL ACENTO es libre. Es el color de la marca del organizador, y ahí no
//     vale una lista de ocho tonos: o es su azul exacto o no es suyo. Es lo
//     único verdaderamente abierto.
//   · EL FONDO se elige de los que trae la plantilla. Tres profundidades, las
//     tres comprobadas contra su propio texto. El fondo decide si la pantalla
//     se lee, así que no se negocia carácter a carácter.
//   · EL TEXTO no se elige. Sale de la plantilla y del fondo, y es lo que
//     sostiene el contraste.
//
// ── Y SI EL ACENTO ELEGIDO NO CONTRASTA ─────────────────────────────────────
//
// No se avisa: se CORRIGE. Un aviso el día del torneo es un aviso que nadie
// lee, y dejarle romperlo es lo que hay que impedir.
//
// La corrección conserva el TONO y la SATURACIÓN —sigue siendo su azul— y
// mueve solo la luminosidad hasta que el contraste llega al mínimo. Alguien que
// eligió el azul de su empresa ve su azul, un poco más claro. Cambiarle el tono
// sería devolverle otro color y decirle que es el suyo.
//
// ── LO QUE NO CAMBIA ENTRE PLANTILLAS ───────────────────────────────────────
//
// «De acuerdo en legibilidad y jerarquía.» Ninguna plantilla toca la unidad
// derivada del alto, ni los tamaños que salen de ella, ni el orden de las
// columnas. Un diseño elegible que pudiera encoger el texto no sería un diseño:
// sería un modo de romper la pantalla con permiso.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart' show HSLColor;
import 'dart:ui';

/// El contraste mínimo de cada papel, en la escala de WCAG.
///
/// No es un número copiado: cada uno responde a qué pasa si ESE elemento no se
/// lee desde diez metros.
class MinimoDeContraste {
  const MinimoDeContraste._();

  /// El texto principal —nombres, puestos, la medida—. AA para texto normal.
  ///
  /// El texto de esta pantalla es enorme, y por tamaño le bastaría el 3:1 de
  /// "texto grande". Pero "grande" en WCAG significa cerca; aquí es enorme y
  /// lejos, que no es lo mismo. Se exige el 4.5 completo.
  static const double texto = 4.5;

  /// El texto secundario: etiquetas, el pie, cuántas rondas lleva cada uno.
  static const double secundario = 3.0;

  /// El acento sobre el fondo. Marca el podio y el líder, así que tiene que
  /// distinguirse, pero no lleva texto encima.
  static const double acento = 3.0;
}

/// Un color y sus cuentas de contraste.
extension ContrasteDeColor on Color {
  /// La luminancia relativa de WCAG. `computeLuminance` de Flutter ya la
  /// calcula con esta misma fórmula, así que no se reimplementa.
  double get _luz => computeLuminance();

  /// La razón de contraste contra [otro]. Entre 1 (idénticos) y 21.
  double contrasteCon(Color otro) {
    final a = _luz, b = otro._luz;
    final claro = a > b ? a : b;
    final oscuro = a > b ? b : a;
    return (claro + 0.05) / (oscuro + 0.05);
  }
}

/// Cómo se ve una plantilla ya resuelta: con el acento del organizador puesto
/// y el contraste garantizado.
class PielDeTele {
  final Color fondo;

  /// El relleno de una fila normal y el de una fila del podio.
  final Color fila;
  final Color filaPodio;

  /// El texto principal y el secundario.
  final Color texto;
  final Color textoSuave;

  /// El acento del organizador, ya corregido si hacía falta.
  final Color acento;

  /// El rojo del bajo par. NO es configurable, y ese es el punto: en golf el
  /// rojo bajo par es una convención, no una decisión de diseño. Un torneo que
  /// lo pintara de morado dejaría de parecer un torneo de golf.
  final Color bajoPar;

  /// La línea que separa al líder del resto.
  final Color separador;

  const PielDeTele({
    required this.fondo,
    required this.fila,
    required this.filaPodio,
    required this.texto,
    required this.textoSuave,
    required this.acento,
    required this.bajoPar,
    required this.separador,
  });
}

/// Una plantilla: la estética cerrada, con sus tres fondos.
class PlantillaDeTele {
  final String clave;
  final String nombre;

  /// Para qué torneo es. Lo lee el organizador al elegir, así que dice el CASO
  /// y no el estilo: "el de siempre" no ayuda a decidir.
  final String paraQue;

  /// Las tres profundidades de fondo, de la más oscura a la más clara.
  final List<Color> fondos;

  /// Los rellenos de fila, en el mismo orden que [fondos].
  final List<Color> filas;
  final List<Color> filasPodio;

  final Color texto;
  final Color textoSuave;
  final Color acentoPorDefecto;
  final Color bajoPar;

  const PlantillaDeTele({
    required this.clave,
    required this.nombre,
    required this.paraQue,
    required this.fondos,
    required this.filas,
    required this.filasPodio,
    required this.texto,
    required this.textoSuave,
    required this.acentoPorDefecto,
    required this.bajoPar,
  });

  /// Cuántos fondos ofrece. Siempre tres: ver [fondos].
  static const int profundidades = 3;

  /// Resuelve la piel con las decisiones del organizador.
  ///
  /// [profundidad] se recorta al rango en vez de lanzar: un documento con un
  /// valor raro tiene que seguir proyectándose.
  PielDeTele resolver({int profundidad = 0, Color? acento}) {
    final i = profundidad.clamp(0, fondos.length - 1);
    final fondo = fondos[i];
    return PielDeTele(
      fondo: fondo,
      fila: filas[i],
      filaPodio: filasPodio[i],
      texto: texto,
      textoSuave: textoSuave,
      acento: corregirContra(acento ?? acentoPorDefecto, fondo),
      bajoPar: corregirContra(bajoPar, fondo),
      // El separador del líder sale del acento ya corregido: es una raya, no
      // un color propio, y tener dos colores que decir lo mismo es ruido.
      separador: corregirContra(acento ?? acentoPorDefecto, fondo)
          .withValues(alpha: 0.55),
    );
  }

  /// Sube o baja la luminosidad de [color] hasta que contrasta con [fondo].
  ///
  /// Conserva tono y saturación —ver la cabecera—. Se mueve hacia el lado
  /// contrario al fondo: sobre fondo oscuro aclara, sobre claro oscurece.
  ///
  /// Termina siempre: el bucle tiene tope y el extremo —blanco puro sobre un
  /// fondo oscuro, negro sobre uno claro— siempre cumple.
  static Color corregirContra(Color color, Color fondo,
      {double minimo = MinimoDeContraste.acento}) {
    if (color.contrasteCon(fondo) >= minimo) return color;

    final hsl = HSLColor.fromColor(color);
    final aclarar = fondo.computeLuminance() < 0.5;
    var l = hsl.lightness;

    // Pasos de 2 %: suficientemente fino para no saltarse el mínimo por mucho,
    // y con tope para no depender de que la aritmética converja.
    for (var n = 0; n < 50; n++) {
      l = (aclarar ? l + 0.02 : l - 0.02).clamp(0.0, 1.0);
      final probado = hsl.withLightness(l).toColor();
      if (probado.contrasteCon(fondo) >= minimo) return probado;
      if (l <= 0.0 || l >= 1.0) break;
    }
    // El extremo. Si ni blanco ni negro llegan, el fondo sería imposible — y
    // los fondos son de la plantilla, así que no puede pasar.
    return aclarar
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF000000);
  }
}

/// El catálogo. Cuatro, y cada una para un caso distinto.
///
/// No son cuatro paletas: son cuatro respuestas a "qué torneo es este". Si dos
/// sirvieran para lo mismo, sobraría una.
class PlantillasDeTele {
  const PlantillasDeTele._();

  /// La de siempre: verde de campo sobre negro. Es la que ya existía, y sigue
  /// siendo la de por defecto para que ningún torneo publicado cambie de cara
  /// solo porque esto se añadió.
  static const club = PlantillaDeTele(
    clave: 'club',
    nombre: 'Casa club',
    paraQue: 'El torneo del club, de toda la vida. Verde de campo.',
    fondos: [Color(0xFF07130C), Color(0xFF0A1A11), Color(0xFF0E2317)],
    filas: [Color(0xFF0C1A12), Color(0xFF102217), Color(0xFF152D1F)],
    filasPodio: [Color(0xFF12241A), Color(0xFF17301F), Color(0xFF1D3C28)],
    texto: Color(0xFFFFFFFF),
    textoSuave: Color(0xFF9FBFAC),
    acentoPorDefecto: Color(0xFF6FE39A),
    bajoPar: Color(0xFFFF5A52),
  );

  /// Tinta sobre papel oscuro, sin color de club. Es la que más se parece a la
  /// retransmisión: gris neutro para que el acento del patrocinador sea LO
  /// ÚNICO con color en la pared.
  static const retransmision = PlantillaDeTele(
    clave: 'retransmision',
    nombre: 'Retransmisión',
    paraQue: 'Neutra y seria. El único color es el del torneo.',
    fondos: [Color(0xFF0B0B0D), Color(0xFF141417), Color(0xFF1D1D21)],
    filas: [Color(0xFF141417), Color(0xFF1C1C20), Color(0xFF25252A)],
    filasPodio: [Color(0xFF1E1E23), Color(0xFF26262C), Color(0xFF303037)],
    texto: Color(0xFFFFFFFF),
    textoSuave: Color(0xFFA0A0A8),
    acentoPorDefecto: Color(0xFFE8B84B),
    bajoPar: Color(0xFFFF5A52),
  );

  /// Para el torneo de empresa. Azul frío y mucho aire: la pantalla que se
  /// proyecta en un salón con logotipos, no en una terraza.
  static const corporativa = PlantillaDeTele(
    clave: 'corporativa',
    nombre: 'Corporativa',
    paraQue: 'Torneo de empresa. Sobria, pensada para que encaje una marca.',
    fondos: [Color(0xFF071018), Color(0xFF0C1826), Color(0xFF122234)],
    filas: [Color(0xFF0C1725), Color(0xFF122032), Color(0xFF1A2C42)],
    filasPodio: [Color(0xFF122335), Color(0xFF192F45), Color(0xFF223C56)],
    texto: Color(0xFFFFFFFF),
    textoSuave: Color(0xFF9BB2C8),
    acentoPorDefecto: Color(0xFF4FA8FF),
    bajoPar: Color(0xFFFF6B60),
  );

  /// La de última hora de la tarde: fondo cálido, contraste alto. Pensada para
  /// una tele que da el sol de frente, donde una pantalla gris desaparece.
  static const atardecer = PlantillaDeTele(
    clave: 'atardecer',
    nombre: 'Atardecer',
    paraQue: 'Para una pantalla con luz de frente. Contraste alto.',
    fondos: [Color(0xFF14100A), Color(0xFF1E1810), Color(0xFF2A2116)],
    filas: [Color(0xFF1D1710), Color(0xFF272016), Color(0xFF342A1D)],
    filasPodio: [Color(0xFF2A2014), Color(0xFF37291A), Color(0xFF463522)],
    texto: Color(0xFFFFF6E8),
    textoSuave: Color(0xFFC4AE90),
    acentoPorDefecto: Color(0xFFFFC24D),
    bajoPar: Color(0xFFFF7A6B),
  );

  static const todas = <PlantillaDeTele>[
    club,
    retransmision,
    corporativa,
    atardecer,
  ];

  /// La plantilla de una clave guardada.
  ///
  /// Cualquier valor desconocido cae en la de siempre. Un torneo publicado con
  /// una clave que ya no existe se sigue proyectando.
  static PlantillaDeTele deClave(String? clave) => todas.firstWhere(
        (p) => p.clave == clave,
        orElse: () => club,
      );

  static const claveInicial = 'club';
}

/// Lo que el organizador eligió para SU torneo.
///
/// ── Identidad y marca son dos cosas, y van en el mismo sitio ────────────────
///
/// «La identidad debería convivir con la marca en la cabecera.» Son dos cosas
/// distintas que comparten una franja:
///
///   · la IDENTIDAD dice QUIÉN ORGANIZA — el logo del evento, sus colores
///   · la MARCA dice QUIÉN PAGA — el banner del §14.3, que ya existía
///
/// Y por eso viven en clases distintas. El §6 exige que la naturaleza comercial
/// sea clara, y esa exigencia se cumple con la etiqueta de la pieza de
/// patrocinio ("PATROCINADOR OFICIAL"). Si la identidad del torneo se guardara
/// en la misma estructura, un logo de organizador acabaría heredando esa
/// etiqueta —o peor, un patrocinador acabaría sin ella—.
///
/// Aquí no hay etiqueta comercial, y es a propósito: quien organiza no se
/// anuncia, encabeza.
class IdentidadDeTorneo {
  /// La clave de la plantilla. Ver [PlantillasDeTele.deClave].
  final String plantilla;

  /// Cuál de las tres profundidades de fondo.
  final int profundidad;

  /// El acento, en ARGB. Null usa el de la plantilla.
  final int? acento;

  /// El logotipo del EVENTO. Vacío es lo normal: la mayoría de los torneos no
  /// tienen logo, y entonces la cabecera enseña el nombre, que ya la identifica.
  final String logoUrl;

  const IdentidadDeTorneo({
    this.plantilla = PlantillasDeTele.claveInicial,
    this.profundidad = 0,
    this.acento,
    this.logoUrl = '',
  });

  /// True si el organizador tocó algo. Un torneo sin identidad no engorda su
  /// documento con los valores por defecto.
  bool get vacia =>
      plantilla == PlantillasDeTele.claveInicial &&
      profundidad == 0 &&
      acento == null &&
      logoUrl.isEmpty;

  PielDeTele get piel => PlantillasDeTele.deClave(plantilla)
      .resolver(profundidad: profundidad, acento: acento == null ? null : Color(acento!));

  IdentidadDeTorneo copyWith({
    String? plantilla,
    int? profundidad,
    int? acento,
    bool borrarAcento = false,
    String? logoUrl,
  }) =>
      IdentidadDeTorneo(
        plantilla: plantilla ?? this.plantilla,
        profundidad: profundidad ?? this.profundidad,
        acento: borrarAcento ? null : (acento ?? this.acento),
        logoUrl: logoUrl ?? this.logoUrl,
      );

  Map<String, dynamic> toJson() => {
        'plantilla': plantilla,
        if (profundidad != 0) 'profundidad': profundidad,
        if (acento != null) 'acento': acento,
        if (logoUrl.isNotEmpty) 'logoUrl': logoUrl,
      };

  factory IdentidadDeTorneo.fromJson(Map<String, dynamic> j) =>
      IdentidadDeTorneo(
        plantilla: (j['plantilla'] as String?) ?? PlantillasDeTele.claveInicial,
        profundidad: (j['profundidad'] as num?)?.toInt() ?? 0,
        acento: (j['acento'] as num?)?.toInt(),
        logoUrl: (j['logoUrl'] as String?) ?? '',
      );
}
