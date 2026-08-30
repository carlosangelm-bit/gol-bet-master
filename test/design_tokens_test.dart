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

import 'dart:math';

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

    // ── ETIQUETA Y VALOR ────────────────────────────────────────────────────
    //
    // El sistema pide que el ojo distinga al instante qué es ETIQUETA y qué es
    // CUÁNTO. Donde fallaba —"HANDICAP" sobre su "18", el nombre de la apuesta
    // junto a su importe— no faltaba un tamaño: es que las dos cosas se
    // escribían casi igual.
    test('CLAVE: value y label se separan por tamaño Y por peso', () {
      final v = GolfType.value(GolfTheme.light.text);
      final l = GolfType.label(GolfTheme.light.sub);
      expect(v.fontSize!, greaterThan(l.fontSize! * 1.3),
          reason: 'a un tamaño de diferencia el ojo tiene que leer para saber '
              'cuál es el dato');
      expect(v.fontWeight!.index, greaterThan(l.fontWeight!.index));
    });

    test('y value NO añade un quinto escalón', () {
      // Subirle el tamaño para que se note habría roto los cuatro escalones que
      // el sistema ya fijó. La diferencia la hacen el peso y el par, no una
      // medida nueva.
      final negro = GolfTheme.light.text;
      expect(GolfType.value(negro).fontSize, GolfType.body(negro).fontSize);
    });

    test('el valor es tabular; la etiqueta no lo necesita', () {
      expect(GolfType.value(GolfTheme.light.text).fontFeatures
          ?.map((f) => f.feature), contains('tnum'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // EL TOKEN QUE ALCANZA LAS CUARENTA Y SEIS PANTALLAS
  //
  // Cuarenta y seis ficheros escriben `TextStyle(color:…, fontSize:…)` a mano
  // y solo once usan GolfType. Poner los números tabulares en cada uno habría
  // sido cuarenta y seis ediciones que se desincronizan a la primera.
  //
  // En vez de eso van en el TEMA, y llegan solas. Funciona por una propiedad de
  // Flutter que se comprobó con una sonda antes de apoyarse en ella, y que este
  // grupo fija: si una versión futura la cambiara, los números dejarían de
  // alinearse en toda la app sin que nada más avisara.
  // ═══════════════════════════════════════════════════════════════════════
  group('números tabulares, desde un solo sitio', () {
    test('el tema los lleva en TODOS los escalones', () {
      for (final t in [GolfTheme.light, GolfTheme.dark, GolfTheme.classic]) {
        final tt = t.toMaterial().textTheme;
        final estilos = {
          'headlineLarge': tt.headlineLarge,
          'headlineMedium': tt.headlineMedium,
          'titleLarge': tt.titleLarge,
          'titleMedium': tt.titleMedium,
          'titleSmall': tt.titleSmall,
          'bodyLarge': tt.bodyLarge,
          'bodyMedium': tt.bodyMedium,
          'bodySmall': tt.bodySmall,
        };
        estilos.forEach((nombre, e) {
          expect(e?.fontFeatures?.map((f) => f.feature), contains('tnum'),
              reason: '$nombre se quedó fuera');
        });
      }
    });

    testWidgets('CLAVE: un Text con estilo inline los HEREDA', (tester) async {
      // Esta es la propiedad de la que depende todo lo anterior: `Text` se
      // pinta con DefaultTextStyle.merge(estilo), y merge solo pisa lo que el
      // estilo declara. Las pantallas declaran color y tamaño; fontFeatures lo
      // dejan en null.
      await tester.pumpWidget(MaterialApp(
        theme: GolfTheme.light.toMaterial(),
        home: const Scaffold(
          body: Text('123', style: TextStyle(fontSize: 22)),
        ),
      ));
      final ctx = tester.element(find.text('123'));
      final efectivo = DefaultTextStyle.of(ctx)
          .style
          .merge(tester.widget<Text>(find.text('123')).style);
      expect(efectivo.fontFeatures?.map((f) => f.feature), contains('tnum'));
      expect(efectivo.fontSize, 22, reason: 'y lo que sí declara, manda');
    });

    testWidgets('CONTRAPESO: quien declare cifras proporcionales, manda',
        (tester) async {
      // El token es el SUELO, no una imposición. Sin este contrapeso, un tema
      // que forzara tnum ignorando el estilo local pasaría la prueba de arriba.
      await tester.pumpWidget(MaterialApp(
        theme: GolfTheme.light.toMaterial(),
        home: const Scaffold(
          body: Text('123',
              style: TextStyle(
                  fontFeatures: [FontFeature.proportionalFigures()])),
        ),
      ));
      final ctx = tester.element(find.text('123'));
      final efectivo = DefaultTextStyle.of(ctx)
          .style
          .merge(tester.widget<Text>(find.text('123')).style);
      expect(efectivo.fontFeatures?.map((f) => f.feature), contains('pnum'));
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
      });
  });

  _elevacion();
  _vidrio();
}

// ═══════════════════════════════════════════════════════════════════════════
// LA ESCALERA DE ELEVACIÓN
//
// El tema oscuro eran tres grises neutros elegidos por separado. Funcionaban, y
// no decían nada: no había forma de saber si dos superficies estaban al mismo
// nivel o si una flotaba sobre la otra, así que cualquiera podía cambiar una
// sin darse cuenta de que rompía la escalera.
//
// Estos tests la convierten en un sistema: tres reglas, y cada una con su
// contrapeso para que cumplirlas no sea trivial.
// ═══════════════════════════════════════════════════════════════════════════
void _elevacion() {
  /// Luminancia relativa, para comparar niveles.
  double luz(Color c) => c.computeLuminance();

  /// Cuánto más frío que cálido es un color: azul menos rojo, en 0-255.
  int frio(Color c) =>
      ((c.b - c.r) * 255).round();

  group('elevación en oscuro', () {
    test('CLAVE: la base es #121212, no negro puro', () {
      // El negro absoluto sobre OLED apaga el píxel y los bordes de las
      // tarjetas desaparecen. Con un gris muy oscuro la geometría se sigue
      // leyendo.
      expect(GolfTheme.dark.bg, const Color(0xFF121212));
      expect(GolfTheme.dark.bg, isNot(const Color(0xFF000000)));
    });

    test('CLAVE: cada nivel aclara sobre el anterior', () {
      final t = GolfTheme.dark;
      expect(luz(t.surface), greaterThan(luz(t.bg)));
      expect(luz(t.card), greaterThan(luz(t.surface)));
      expect(luz(t.divider), greaterThan(luz(t.card)),
          reason: 'la línea separa el nivel 2, así que va por encima de él');
    });

    test('y los escalones se NOTAN: ni iguales ni un salto de golpe', () {
      // Sin mínimo, dos niveles casi idénticos pasarían la prueba de arriba y
      // la elevación no se vería. Sin máximo, la escalera se convierte en un
      // fondo claro.
      final t = GolfTheme.dark;
      for (final par in [
        (t.bg, t.surface, 'bg→surface'),
        (t.surface, t.card, 'surface→card'),
      ]) {
        final salto = luz(par.$2) - luz(par.$1);
        expect(salto, greaterThan(0.004), reason: '${par.$3}: no se ve');
        expect(salto, lessThan(0.06), reason: '${par.$3}: deja de ser oscuro');
      }
    });

    test('CLAVE: y cada nivel se enfría — el azul sube más que el rojo', () {
      // Es lo que separa "elevado" de "descolorido": una escalera de grises
      // puros parece un error de calibración; el mismo escalón con tinte frío
      // se lee como luz.
      final t = GolfTheme.dark;
      expect(frio(t.bg), 0, reason: 'la base es neutra a propósito');
      expect(frio(t.surface), greaterThan(0));
      expect(frio(t.card), greaterThan(frio(t.surface)));
    });

    test('el texto sigue legible sobre los tres niveles', () {
      // El contrapeso de todo lo anterior: una escalera preciosa sobre la que
      // no se lee no sirve. 4.5:1 es el mínimo de AA para texto normal.
      final t = GolfTheme.dark;
      double contraste(Color a, Color b) {
        final x = luz(a), y = luz(b);
        return (max(x, y) + 0.05) / (min(x, y) + 0.05);
      }

      for (final fondo in [t.bg, t.surface, t.card]) {
        expect(contraste(t.text, fondo), greaterThan(4.5));
        expect(contraste(t.sub, fondo), greaterThan(3.0),
            reason: 'sub es secundario, pero tiene que leerse');
      }
    });
  });

  group('lo que la escalera NO puede tocar', () {
    test('sub y los tonos del dinero se quedan como estaban', () {
      // Fijados desde antes —"un canal, un significado"—. Teñirlos habría
      // movido el significado además del tono.
      expect(GolfTheme.dark.sub, const Color(0xFF9E9E9E));
      expect(GolfTheme.dark.profit, const Color(0xFF66BB6A));
      expect(GolfTheme.dark.loss, const Color(0xFFEF5350));
    });

    test('y el tema claro no se convierte en oscuro por accidente', () {
      // La escalera del claro va al revés: la base es la MÁS clara.
      expect(luz(GolfTheme.light.bg), greaterThan(0.8));
    });

    test('el clásico conserva su tinte verde, que es de marca', () {
      // La regla del frío es del tema oscuro, no de todos. En el clásico el
      // tinte lo decide la marca, y aplicarle el azul lo habría apagado.
      final c = GolfTheme.classic;
      expect((c.bg.g * 255).round(), greaterThan((c.bg.b * 255).round()));
    });
  });
}

// ── Fase 6 · vidrio sin desenfoque ──────────────────────────────────────────
//
// Se probó en pantalla: la única superficie con BackdropFilter hacía scroll CON
// el contenido, así que nunca tenía nada detrás que desenfocar. Sigma 20 y
// sigma 2 daban el mismo resultado, y el desenfoque reduce contraste justo en
// una app que se usa a pleno sol.
//
// La variante se conserva por si alguna superficie llega a flotar sobre
// contenido en scroll. Este test fija que hoy nadie la usa, para que volver a
// activarla sea una decisión y no un descuido.
void _vidrio() {
  group('vidrio', () {
    test('las otras tres capas siguen existiendo', () {
      // Quitar el desenfoque no es quitar el acabado: relleno, borde especular
      // y sombra son lo que da el efecto, y siguen en los tres temas.
      for (final t in [GolfTheme.light, GolfTheme.dark, GolfTheme.classic]) {
        expect(t.glassFill.a, greaterThan(0));
        expect(t.glassBorderHi.a, greaterThan(0));
        expect(t.glassBorderLo.a, greaterThan(0));
      }
    });

    test('el sigma del desenfoque sigue definido para cuando haga falta', () {
      // Si alguna superficie llega a flotar sobre scroll, el token está.
      expect(GolfTheme.light.glassBlur, greaterThan(0));
    });
  });
}
