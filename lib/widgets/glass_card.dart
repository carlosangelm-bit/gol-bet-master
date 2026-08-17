// ─────────────────────────────────────────────────────────────────────────────
// GLASS CARD — superficie translúcida tipo liquid glass
//
// Cuatro capas, y hacen falta las cuatro:
//   1. Desenfoque del fondo   → lo que distingue el vidrio de un color con alfa
//   2. Relleno translúcido    → base para que el texto no flote sobre el ruido
//   3. Borde especular        → luz arriba-izquierda, sombra abajo-derecha
//   4. Sombra difusa          → separa del fondo sin marcar un contorno
//
// Todos los valores salen de GolfTheme. Ninguna pantalla define los suyos: el
// sigma se calibra en un sitio y el efecto queda coherente en toda la app.
//
// ── Coste ────────────────────────────────────────────────────────────────────
// BackdropFilter obliga a un saveLayer del contenido de atrás, y en Flutter web
// con CanvasKit eso es caro. Una lista con seis tarjetas serían seis
// desenfoques recomputándose en cada frame, justo mientras se hace scroll.
//
// Por eso el desenfoque es OPCIONAL y no el default: [GlassCard.solid] da las
// otras tres capas sin coste de saveLayer.
//
// HOY NO SE USA EL DESENFOQUE EN NINGÚN SITIO, y no es un descuido. Se probó en
// pantalla en la única superficie que lo llevaba —la tarjeta del duelo por
// equipos— y no aportaba nada: la tarjeta hace scroll CON el contenido, así que
// nunca tiene nada detrás que desenfocar. Sigma 20 y sigma 2 daban el mismo
// resultado, y el desenfoque reduce contraste justo en una app que se usa a
// pleno sol.
//
// La variante se conserva por si alguna superficie llega a FLOTAR sobre
// contenido en scroll —una barra inferior fija sería el caso—. Ahí sí habría
// algo detrás y el desenfoque significaría algo. Si se activa, medirlo.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../core/app_theme.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final GolfTheme t;

  /// Tinte de estado (ganando, perdiendo, seleccionado…).
  ///
  /// El estado es INFORMACIÓN, no adorno, y el vidrio baja el contraste por
  /// definición. El tinte se aplica dentro del vidrio con saturación suficiente
  /// para leerse de un vistazo; ver [tintStrength] para ajustarlo.
  final Color? tint;

  /// Cuánto tiñe. Sube si el estado tiene que ganarle al fondo.
  final double tintStrength;

  /// true = desenfoca el fondo (vidrio real). Cuesta un saveLayer.
  ///
  /// Usar solo en superficies destacadas. En listas con scroll, [GlassCard.solid].
  final bool blur;

  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    required this.t,
    this.tint,
    this.tintStrength = 0.16,
    this.blur = true,
    this.padding = const EdgeInsets.all(14),
    this.margin,
    this.radius = 22,
    this.onTap,
  });

  /// Vidrio sin desenfoque: mismas tres capas restantes, sin saveLayer.
  /// Es la variante para tarjetas de lista.
  const GlassCard.solid({
    super.key,
    required this.child,
    required this.t,
    this.tint,
    this.tintStrength = 0.16,
    this.padding = const EdgeInsets.all(14),
    this.margin,
    this.radius = 22,
    this.onTap,
  }) : blur = false;

  @override
  Widget build(BuildContext context) {
    final borde = BorderRadius.circular(radius);

    final contenido = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borde,
        // Relleno + tinte de estado. El tinte va encima del relleno para que
        // conserve su saturación en vez de diluirse con el blanco de base.
        color: tint == null
            ? t.glassFill
            : Color.alphaBlend(tint!.withValues(alpha: tintStrength), t.glassFill),
        // Borde especular: el gradiente hace que la luz caiga arriba-izquierda
        // y se apague abajo-derecha, como en un canto biselado.
        border: GradientBoxBorder(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [t.glassBorderHi, t.glassBorderLo],
          ),
        ),
      ),
      child: Padding(padding: padding, child: child),
    );

    Widget capa = ClipRRect(
      borderRadius: borde,
      child: blur
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: t.glassBlur, sigmaY: t.glassBlur),
              child: contenido,
            )
          : contenido,
    );

    if (onTap != null) {
      capa = Material(
        color: Colors.transparent,
        child: InkWell(borderRadius: borde, onTap: onTap, child: capa),
      );
    }

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: borde,
        boxShadow: [
          BoxShadow(
            color: t.glassShadow,
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      // Aísla el repintado: sin esto, cualquier cambio dentro de una tarjeta
      // obliga a recomponer el desenfoque de las demás.
      child: RepaintBoundary(child: capa),
    );
  }
}

/// Borde con gradiente. Flutter no trae uno: [Border] admite un color por lado
/// pero no una transición, y el borde especular ES una transición.
class GradientBoxBorder extends BoxBorder {
  final Gradient gradient;
  final double width;

  const GradientBoxBorder({required this.gradient, this.width = 1});

  @override
  BorderSide get bottom => BorderSide.none;
  @override
  BorderSide get top => BorderSide.none;
  @override
  bool get isUniform => true;
  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(width);

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    TextDirection? textDirection,
    BoxShape shape = BoxShape.rectangle,
    BorderRadius? borderRadius,
  }) {
    final pincel = Paint()
      ..strokeWidth = width
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke;

    if (borderRadius != null) {
      canvas.drawRRect(borderRadius.toRRect(rect).deflate(width / 2), pincel);
    } else {
      canvas.drawRect(rect.deflate(width / 2), pincel);
    }
  }

  @override
  ShapeBorder scale(double factor) =>
      GradientBoxBorder(gradient: gradient, width: width * factor);
}
