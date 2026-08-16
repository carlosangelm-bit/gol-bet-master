// ─────────────────────────────────────────────────────────────────────────────
// design_tokens_test.dart — el sistema de color, verificable
//
// La regla del sistema visual es "un canal, un significado": el color saturado
// se reserva para el DINERO, y todo lo demás usa la escala neutra o el primary.
//
// Estos tests fijan la parte del sistema que ya es correcta, para que no se
// erosione mientras se aplica el resto por fases. Lo que todavía NO cumple
// —los tokens de score que colisionan con los de dinero— está documentado abajo
// con su test pendiente, para que la fase que los toque tenga el criterio ya
// escrito y no haya que reconstruirlo.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/widgets/common_widgets.dart';

void main() {
  group('canal del dinero', () {
    test('claro y oscuro usan los valores acordados', () {
      expect(GolfTheme.light.profit, const Color(0xFF2E7D32));
      expect(GolfTheme.light.loss, const Color(0xFFC62828));
      expect(GolfTheme.light.sub, const Color(0xFF757575));

      expect(GolfTheme.dark.profit, const Color(0xFF66BB6A));
      expect(GolfTheme.dark.loss, const Color(0xFFEF5350));
      expect(GolfTheme.dark.sub, const Color(0xFF9E9E9E));
    });

    test('cobrar y pagar nunca son el mismo color', () {
      for (final t in [GolfTheme.light, GolfTheme.dark, GolfTheme.classic]) {
        expect(t.profit, isNot(t.loss));
      }
    });
  });

  group('canal de identidad', () {
    // La identidad —quién es este jugador— es un canal distinto del dinero.
    // Si reutilizara sus tonos, un equipo pintado de rojo se leería como
    // "pagas", y eso pasaba justo en la barra proporcional del marcador.
    test('la paleta de jugador no reutiliza los tonos del dinero', () {
      final temas = [GolfTheme.light, GolfTheme.dark, GolfTheme.classic];
      for (var i = 0; i < 8; i++) {
        final c = GAvatar.colorFor(i);
        for (final t in temas) {
          expect(c, isNot(t.profit),
              reason: 'el color de jugador $i es el verde de "cobras"');
          expect(c, isNot(t.loss),
              reason: 'el color de jugador $i es el rojo de "pagas"');
        }
      }
    });

    test('los colores de jugador son distinguibles entre sí', () {
      final vistos = <int>{};
      for (var i = 0; i < 8; i++) {
        expect(vistos.add(GAvatar.colorFor(i).toARGB32()), isTrue,
            reason: 'el color $i está repetido');
      }
    });
  });

  group('escala tipográfica', () {
    test('cuatro escalones, sin tamaños intermedios', () {
      final negro = GolfTheme.light.text;
      expect(GolfType.hero(negro).fontSize, greaterThanOrEqualTo(44));
      expect(GolfType.title(negro).fontSize, inInclusiveRange(20, 22));
      expect(GolfType.body(negro).fontSize, inInclusiveRange(15, 16));
      expect(GolfType.label(negro).fontSize, inInclusiveRange(11, 12));
    });

    test('las cifras van en tabular donde se alinean en columna', () {
      final negro = GolfTheme.light.text;
      for (final estilo in [GolfType.hero(negro), GolfType.bodyNum(negro)]) {
        expect(estilo.fontFeatures?.map((f) => f.feature),
            contains('tnum'),
            reason: 'sin tabular las cifras bailan al cambiar de valor');
      }
    });

    test('la etiqueta lleva tracking: va en mayúsculas', () {
      expect(GolfType.label(GolfTheme.light.sub).letterSpacing,
          greaterThanOrEqualTo(0.5));
    });
  });

  group('vidrio', () {
    test('el borde especular se ve en los tres temas', () {
      // En claro el borde era 0xB3FFFFFF sobre fondo blanco: invisible.
      // El canto se dibuja por contraste contra el fondo, no por luminosidad
      // absoluta, así que en tema claro el lado en sombra debe ser oscuro.
      expect(GolfTheme.light.glassBorderLo.computeLuminance(),
          lessThan(GolfTheme.light.glassBorderHi.computeLuminance()),
          reason: 'en claro el borde bajo debe anclar contra el fondo');

      for (final t in [GolfTheme.light, GolfTheme.dark, GolfTheme.classic]) {
        expect(t.glassBorderHi.a, greaterThan(0.3),
            reason: 'el borde iluminado tiene que existir');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // PENDIENTE — se activa con la fase de formas de score.
  //
  // Hoy fallaría: en tema claro scoreOver es EXACTAMENTE loss, y en clásico
  // scoreUnder es profit y scoreOver es loss. O sea que "bogey" y "pagas"
  // comparten color.
  //
  // No se arregla aquí a propósito: mientras el score se comunique por color de
  // fondo, quitarle el rojo lo deja indistinguible de un par. El token y la
  // forma tienen que cambiar juntos, o se pierde información en el intervalo.
  // ══════════════════════════════════════════════════════════════════════════
  // ══════════════════════════════════════════════════════════════════════════
  // Los tokens nuevos del sistema.
  // ══════════════════════════════════════════════════════════════════════════
  group('canal de sistema', () {
    test('danger existe y es distinto de profit en los tres temas', () {
      for (final t in [GolfTheme.light, GolfTheme.dark, GolfTheme.classic]) {
        expect(t.danger, isNot(t.profit));
      }
    });

    test('even no es sub ni ninguno de los dos colores del dinero', () {
      // "En ceros" es un resultado del dinero, no un dato ausente: verlo en el
      // gris de campo vacío lo degradaría a "no hay información".
      for (final t in [GolfTheme.light, GolfTheme.dark, GolfTheme.classic]) {
        expect(t.even, isNot(t.sub));
        expect(t.even, isNot(t.profit));
        expect(t.even, isNot(t.loss));
      }
    });
  });

  group('canal del score', () {
    test('el score no reutiliza los tonos del dinero', () {
      for (final t in [GolfTheme.light, GolfTheme.dark, GolfTheme.classic]) {
        expect(t.scoreUnder, isNot(t.profit));
        expect(t.scoreUnder, isNot(t.loss));
        expect(t.scoreOver, isNot(t.profit));
        expect(t.scoreOver, isNot(t.loss));
      }
    }, skip: 'Se activa con la fase de formas de score — ver comentario arriba.');
  });
}
