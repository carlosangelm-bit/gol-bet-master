import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';

enum AppThemeMode { light, dark, classic }

// ─── Paletas ──────────────────────────────────────────────────────────────────
class _P {
  // ── Vidrio (liquid glass) ──────────────────────────────────────────────────
  //
  // Cuatro capas hacen el efecto y las cuatro dependen del tema: relleno
  // translúcido, borde especular (más luz arriba-izquierda que abajo-derecha),
  // sombra difusa y el sigma del desenfoque.
  //
  // El relleno es más opaco en oscuro que en claro: sobre un fondo oscuro el
  // texto necesita más base para no flotar sobre el ruido del desenfoque.
  static const lGlassFill     = Color(0x26FFFFFF); // ~15% blanco
  // En claro el borde NO puede ser luz sobre luz: 0xB3FFFFFF sobre fondo
  // blanco es invisible —comprobado ampliando la tarjeta—. Se ancla contra el
  // fondo: blanco más opaco arriba-izquierda y NEGRO tenue abajo-derecha, que
  // es lo que dibuja el canto.
  static const lGlassBordHi   = Color(0xE6FFFFFF);
  static const lGlassBordLo   = Color(0x14000000); // negro ~8%
  static const lGlassShadow   = Color(0x1A000000);

  // Blanco al 10%, no al 25%. Con 25% la tarjeta se aclaraba tanto que el texto
  // —que en oscuro es claro— quedaba compitiendo contra un fondo casi de su
  // misma luminosidad y las cifras dejaban de leerse. En un tema oscuro el
  // relleno tiene que oscurecer, no iluminar.
  static const dGlassFill     = Color(0x1AFFFFFF); // ~10% blanco
  static const dGlassBordHi   = Color(0x59FFFFFF);
  static const dGlassBordLo   = Color(0x0DFFFFFF);
  static const dGlassShadow   = Color(0x40000000);

  // Mismo motivo: clásico también es un tema oscuro.
  static const cGlassFill     = Color(0x2166BB6A); // tinte verde, ~13%
  static const cGlassBordHi   = Color(0x66A5D6A7);
  static const cGlassBordLo   = Color(0x0DFFFFFF);
  static const cGlassShadow   = Color(0x40000000);

  // ── Sistema: peligro y saldo cero ──────────────────────────────────────────
  //
  // danger NO es loss. Rojo de error y rojo de "pagas" son dos mensajes
  // distintos, y compartir token impedía distinguirlos en código o cambiar uno
  // sin el otro. Arrancan con el mismo tono en claro y oscuro para que la
  // migración no altere nada visualmente; separarlos después es cambiar un
  // valor. En clásico sí difieren desde ya: cLoss es un rosa pálido que como
  // color de error no se lee.
  static const lDanger = Color(0xFFC62828);
  static const dDanger = Color(0xFFEF5350);
  static const cDanger = Color(0xFFE57373);

  // "En ceros" es un estado del dinero, no la ausencia de dato: mereces saber
  // que quedaste a mano, no ver un gris de campo vacío. Tono frío y neutro,
  // distinto tanto de sub como de los dos colores del dinero.
  static const lEven = Color(0xFF546E7A);
  static const dEven = Color(0xFFB0BEC5);
  static const cEven = Color(0xFFB0BEC5);

  // Light
  static const lBg      = Color(0xFFFFFFFF);
  static const lSurface = Color(0xFFF5F5F5);
  static const lCard    = Color(0xFFFFFFFF);
  static const lPrimary = Color(0xFF2E7D32);
  static const lOnPrim  = Color(0xFFFFFFFF);
  static const lText    = Color(0xFF1A1A1A);
  static const lSub     = Color(0xFF757575);
  static const lDiv     = Color(0xFFE0E0E0);
  static const lProfit  = Color(0xFF2E7D32);
  static const lLoss    = Color(0xFFC62828);
  static const lAccent  = Color(0xFF43A047);
  // ── Canal del SCORE ────────────────────────────────────────────────────────
  // Baja saturación a propósito: la información la lleva la FORMA —círculo,
  // cuadro— y estos tonos solo tiñen el trazo. Quitarlos entero dejaría el
  // score igual de legible.
  //
  // Antes lOver era EXACTAMENTE lLoss y en clásico cUnder era cProfit y cOver
  // era cLoss: el mismo rojo decía "bogey" y "pagas", y el mismo dorado decía
  // "birdie" y "cobras". Un canal, un significado.
  static const lUnder   = Color(0xFF37474F);  // blueGrey 800
  static const lOver    = Color(0xFF5D4037);  // brown 700

  // ── Dark: una ESCALERA DE ELEVACIÓN, no el invertido de Material ──────────
  //
  // Antes eran tres grises neutros elegidos por separado —111111, 1E1E1E,
  // 282828— y funcionaban, pero no decían nada: no había forma de saber si dos
  // superficies estaban al mismo nivel o si una flotaba sobre la otra.
  //
  // Ahora son un sistema con tres reglas, y las tres se comprueban:
  //
  //   1 · La BASE es #121212, no negro puro. El negro absoluto sobre una
  //       pantalla OLED apaga el píxel entero y los bordes de las tarjetas
  //       desaparecen; con un gris muy oscuro la geometría se sigue leyendo.
  //       El negro se reserva para trazos, no para fondos.
  //
  //   2 · Cada nivel ACLARA sobre el anterior. Es lo que crea la elevación sin
  //       sombras, que en oscuro casi no se ven.
  //
  //   3 · Y cada nivel se ENFRÍA un poco: el azul sube más que el rojo. Es lo
  //       que separa "elevado" de "descolorido" — una escalera de grises puros
  //       parece un error de calibración, y el mismo escalón con tinte frío se
  //       lee como luz.
  //
  //       nivel 0  bg       #121212   R18 G18 B18   base, neutra
  //       nivel 1  surface  #191B1F   R25 G27 B31   +7 luz, +6 de frío
  //       nivel 2  card     #21242A   R33 G36 B42   +8 luz, +9 de frío
  //                divider  #2E323A   la línea que separa el nivel 2
  //
  // Lo que NO cambia, y es a propósito: `sub` y los tonos del dinero. Están
  // fijados en design_tokens_test desde antes —"un canal, un significado"— y
  // teñirlos habría movido el significado además del tono.
  static const dBg      = Color(0xFF121212);
  static const dSurface = Color(0xFF191B1F);
  static const dCard    = Color(0xFF21242A);
  static const dPrimary = Color(0xFF4CAF50);
  // Negro sobre el verde primario: es un PRIMER PLANO, no un fondo. La regla
  // del negro absoluto habla de superficies, y aquí el contraste lo pide.
  static const dOnPrim  = Color(0xFF000000);
  static const dText    = Color(0xFFEEEEEE);
  static const dSub     = Color(0xFF9E9E9E);
  static const dDiv     = Color(0xFF2E323A);
  static const dProfit  = Color(0xFF66BB6A);
  static const dLoss    = Color(0xFFEF5350);
  static const dAccent  = Color(0xFF81C784);
  static const dUnder   = Color(0xFF90A4AE);  // blueGrey 300
  static const dOver    = Color(0xFFBCAAA4);  // brown 200

  // Classic (Verde premium · Crema · Oro) — mismo tono que hero screens
  static const cBg      = Color(0xFF0D2B0F);
  static const cSurface = Color(0xFF1A3A1C);
  static const cCard    = Color(0xFF1E4620);
  static const cPrimary = Color(0xFFF9A825);
  static const cOnPrim  = Color(0xFF0D2B0F);
  static const cText    = Color(0xFFFFF8E7);
  static const cSub     = Color(0xFFD4C89A);
  static const cDiv     = Color(0xFF245527);
  static const cProfit  = Color(0xFFF9A825);
  static const cLoss    = Color(0xFFFFCDD2);
  static const cAccent  = Color(0xFFFBC02D);
  static const cUnder   = Color(0xFFCFD8DC);  // blueGrey 100
  static const cOver    = Color(0xFFD7CCC8);  // brown 100
}

class GolfTheme {
  final Color bg, surface, card, primary, onPrimary;
  final Color text, sub, divider, profit, loss, accent;
  final Color scoreUnder, scoreOver;
  final Brightness brightness;

  // ── Vidrio ─────────────────────────────────────────────────────────────────
  /// Relleno translúcido que va SOBRE el desenfoque. Sin él el texto flota
  /// sobre el ruido del fondo y deja de leerse.
  final Color glassFill;

  /// Borde especular: [glassBorderHi] arriba-izquierda y [glassBorderLo]
  /// abajo-derecha. Es el detalle que más aporta al efecto y el que más se
  /// suele omitir; sin él la tarjeta parece plástico teñido.
  final Color glassBorderHi;
  final Color glassBorderLo;

  /// Sombra amplia y suave: separa la tarjeta del fondo sin dibujarle un marco.
  final Color glassShadow;

  /// Rojo de SISTEMA: error, validación fallida, acción destructiva.
  ///
  /// Distinto de [loss] a propósito, aunque hoy compartan tono: uno dice "algo
  /// va mal", el otro "pagas dinero". Con un solo token no se podía auditar
  /// cuál era cuál ni ajustar uno sin arrastrar el otro.
  final Color danger;

  /// Saldo cero: ni cobras ni pagas, quedaste a mano.
  ///
  /// Token propio y no [sub] porque es un RESULTADO del dinero, no un dato
  /// ausente. Verlo en el mismo gris que un campo vacío lo degrada a "no hay
  /// información" cuando en realidad la hay.
  final Color even;

  /// Sigma del desenfoque de fondo. Vive en el tema para poder calibrarlo en un
  /// solo sitio: es el parámetro que decide si el efecto se ve o si el frame
  /// time se dispara.
  final double glassBlur;

  const GolfTheme._({
    required this.bg, required this.surface, required this.card,
    required this.primary, required this.onPrimary,
    required this.text, required this.sub, required this.divider,
    required this.profit, required this.loss, required this.accent,
    required this.scoreUnder, required this.scoreOver,
    required this.brightness,
    required this.glassFill,
    required this.glassBorderHi,
    required this.glassBorderLo,
    required this.glassShadow,
    required this.danger,
    required this.even,
    this.glassBlur = 20,
  });

  static const light = GolfTheme._(
    bg: _P.lBg, surface: _P.lSurface, card: _P.lCard,
    primary: _P.lPrimary, onPrimary: _P.lOnPrim,
    text: _P.lText, sub: _P.lSub, divider: _P.lDiv,
    profit: _P.lProfit, loss: _P.lLoss, accent: _P.lAccent,
    scoreUnder: _P.lUnder, scoreOver: _P.lOver,
    brightness: Brightness.light,
    glassFill: _P.lGlassFill,
    glassBorderHi: _P.lGlassBordHi,
    glassBorderLo: _P.lGlassBordLo,
    glassShadow: _P.lGlassShadow,
    danger: _P.lDanger,
    even: _P.lEven,
  );

  static const dark = GolfTheme._(
    bg: _P.dBg, surface: _P.dSurface, card: _P.dCard,
    primary: _P.dPrimary, onPrimary: _P.dOnPrim,
    text: _P.dText, sub: _P.dSub, divider: _P.dDiv,
    profit: _P.dProfit, loss: _P.dLoss, accent: _P.dAccent,
    scoreUnder: _P.dUnder, scoreOver: _P.dOver,
    brightness: Brightness.dark,
    glassFill: _P.dGlassFill,
    glassBorderHi: _P.dGlassBordHi,
    glassBorderLo: _P.dGlassBordLo,
    glassShadow: _P.dGlassShadow,
    danger: _P.dDanger,
    even: _P.dEven,
  );

  static const classic = GolfTheme._(
    bg: _P.cBg, surface: _P.cSurface, card: _P.cCard,
    primary: _P.cPrimary, onPrimary: _P.cOnPrim,
    text: _P.cText, sub: _P.cSub, divider: _P.cDiv,
    profit: _P.cProfit, loss: _P.cLoss, accent: _P.cAccent,
    scoreUnder: _P.cUnder, scoreOver: _P.cOver,
    brightness: Brightness.dark,
    glassFill: _P.cGlassFill,
    glassBorderHi: _P.cGlassBordHi,
    glassBorderLo: _P.cGlassBordLo,
    glassShadow: _P.cGlassShadow,
    danger: _P.cDanger,
    even: _P.cEven,
  );

  ThemeData toMaterial() => ThemeData(
    brightness: brightness,
    fontFamily: 'Roboto',
    scaffoldBackgroundColor: bg,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: primary, onPrimary: onPrimary,
      secondary: accent, onSecondary: onPrimary,
      error: loss, onError: onPrimary,
      surface: surface, onSurface: text,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg, foregroundColor: text, elevation: 0, centerTitle: false,
      titleTextStyle: TextStyle(color: text, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5, fontFeatures: GolfType.tabular),
      iconTheme: IconThemeData(color: text),
    ),
    cardTheme: CardThemeData(
      color: card, elevation: brightness == Brightness.light ? 0.5 : 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: DividerThemeData(color: divider, thickness: 1, space: 1),
    // ── NÚMEROS TABULARES EN TODO, DESDE UN SOLO SITIO ──────────────────────
    //
    // Esto es el token que alcanza las cuarenta y seis pantallas sin abrir
    // ninguna, y funciona por una propiedad de Flutter que se comprobó antes de
    // apoyarse en ella: un `Text` con estilo inline se pinta con
    // `DefaultTextStyle.merge(estilo)`, y `merge` solo pisa los campos que el
    // estilo declara. Las pantallas escriben color y tamaño; `fontFeatures` lo
    // dejan en null, así que heredan el de aquí.
    //
    // Sonda, antes de escribir una línea:
    //
    //     DefaultTextStyle trae tnum:            (tnum)
    //     estilo EFECTIVO de un Text inline:     (tnum) · size 22.0
    //     y el que declara los suyos:            (pnum)
    //
    // O sea que quien quiera cifras proporcionales las declara y manda. Esto es
    // el suelo, no una imposición.
    //
    // El beneficio no es solo estético: las columnas dejan de bailar al
    // actualizarse, que es por lo que la pantalla de la casa club ya las usaba.
    textTheme: TextTheme(
      headlineLarge: TextStyle(color: text, fontWeight: FontWeight.w800, fontSize: 28, letterSpacing: -0.5, fontFeatures: GolfType.tabular),
      headlineMedium: TextStyle(color: text, fontWeight: FontWeight.w700, fontSize: 22, fontFeatures: GolfType.tabular),
      titleLarge: TextStyle(color: text, fontWeight: FontWeight.w700, fontSize: 18, fontFeatures: GolfType.tabular),
      titleMedium: TextStyle(color: text, fontWeight: FontWeight.w600, fontSize: 16, fontFeatures: GolfType.tabular),
      titleSmall: TextStyle(color: text, fontWeight: FontWeight.w600, fontSize: 14, fontFeatures: GolfType.tabular),
      bodyLarge: TextStyle(color: text, fontSize: 16, fontFeatures: GolfType.tabular),
      bodyMedium: TextStyle(color: text, fontSize: 14, fontFeatures: GolfType.tabular),
      bodySmall: TextStyle(color: sub, fontSize: 12, fontFeatures: GolfType.tabular),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: surface,
      labelStyle: TextStyle(color: sub),
      hintStyle: TextStyle(color: sub),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: divider)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: divider)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: primary, width: 2)),
    ),
  );
}

// ── Global theme holder ────────────────────────────────────────────────────────
class GolfThemeExt {
  static GolfTheme _currentTheme = GolfTheme.light;
  static GolfTheme get current => _currentTheme;
  static void setCurrent(GolfTheme t) => _currentTheme = t;
}

// Extension para acceder al tema desde context
extension GolfThemeContext on BuildContext {
  GolfTheme get gt => GolfThemeExt.current;
}

// ─────────────────────────────────────────────────────────────────────────────
// ESCALA TIPOGRÁFICA — cuatro pasos, ni uno más
//
// Minimalismo aquí no es quitar adornos: es reducir el número de decisiones que
// el ojo procesa. Con seis tamaños conviviendo en una tarjeta de 200px, el
// lector no sabe qué mirar primero.
//
// Lo que hoy vive entre escalones se colapsa al de arriba o al de abajo. No hay
// tamaños intermedios: si algo no encaja en ninguno de los cuatro, la pregunta
// es qué jerarquía tiene, no qué tamaño necesita.
//
// El contexto manda: se usa bajo sol directo, a una mano, mirando dos segundos.
// Por eso los pesos son altos y no hay nada por debajo de 11.
// ─────────────────────────────────────────────────────────────────────────────
class GolfType {
  const GolfType._();

  /// Cifras alineadas en columna. Sin esto las de ancho variable bailan al
  /// cambiar de hoyo y las columnas de montos dejan de leerse como columna.
  ///
  /// Público porque el TEMA lo consume: ver [GolfTheme.toMaterial]. Es lo que
  /// convierte "números tabulares en todos los datos" en un token en vez de en
  /// cuarenta y seis ediciones.
  static const tabular = [FontFeature.tabularFigures()];
  static const _tabular = tabular;

  /// HÉROE — la cifra que responde la pregunta de la pantalla. Una por pantalla.
  static TextStyle hero(Color color, {double size = 48}) => TextStyle(
        color: color,
        fontSize: size,
        fontWeight: FontWeight.w700,
        height: 1.0,
        letterSpacing: -1.5,
        fontFeatures: _tabular,
      );

  /// TÍTULO — nombre de tarjeta o de sección.
  static TextStyle title(Color color, {double size = 21}) => TextStyle(
        color: color,
        fontSize: size,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: -0.3,
      );

  /// CUERPO — contenido.
  static TextStyle body(Color color,
          {double size = 15, FontWeight weight = FontWeight.w400}) =>
      TextStyle(color: color, fontSize: size, fontWeight: weight, height: 1.35);

  /// CUERPO con cifras tabulares, para montos y scores dentro del texto.
  static TextStyle bodyNum(Color color,
          {double size = 15, FontWeight weight = FontWeight.w500}) =>
      TextStyle(
        color: color,
        fontSize: size,
        fontWeight: weight,
        height: 1.35,
        fontFeatures: _tabular,
      );

  /// ETIQUETA — encabezados de columna y unidades. Siempre en MAYÚSCULAS.
  static TextStyle label(Color color, {double size = 11}) => TextStyle(
        color: color,
        fontSize: size,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      );

  /// VALOR — la cifra que la etiqueta nombra.
  ///
  /// ── Por qué existe, y por qué NO trae un tamaño nuevo ─────────────────────
  ///
  /// El sistema pide que el ojo distinga al instante qué es ETIQUETA y qué es
  /// CUÁNTO. Donde eso fallaba —la cabecera "HANDICAP" y el "18" de debajo
  /// tenían casi el mismo peso— el problema no era que faltara un tamaño, era
  /// que las dos cosas se escribían igual.
  ///
  /// Así que [value] no añade un quinto escalón: se queda en los que ya hay y
  /// se separa de [label] por lo que sí distingue de un vistazo:
  ///
  ///     label  ·  11 px  ·  w500  ·  MAYÚSCULAS con tracking  ·  color sub
  ///     value  ·  15 px  ·  w700  ·  tabular                  ·  color text
  ///
  /// El par es lo que hace el trabajo. Usar [value] sin [label] al lado no
  /// arregla nada, y subirle el tamaño para que se note rompería los cuatro
  /// escalones que el sistema ya fijó.
  ///
  /// [size] existe para poder subir al escalón de [title] o [hero] cuando el
  /// valor es el protagonista de la pantalla. No para inventar medidas
  /// intermedias.
  static TextStyle value(Color color, {double size = 15}) => TextStyle(
        color: color,
        fontSize: size,
        fontWeight: FontWeight.w700,
        height: 1.15,
        letterSpacing: -0.2,
        fontFeatures: _tabular,
      );
}
