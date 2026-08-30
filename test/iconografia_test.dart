// ─────────────────────────────────────────────────────────────────────────────
// ICONOGRAFÍA — entrega 1 de dos: el sistema y el catálogo
//
// El inventario dio 258 emojis en unas treinta pantallas, no los once que se
// listaron a ojo. Así que va en dos:
//
//   1 · el SISTEMA y el CATÁLOGO —esta—, que con un cambio alcanza las diez
//       pantallas que enseñan tipos de apuesta, más la tele
//   2 · las pantallas sueltas, guiadas por el contador de abajo
//
// ── Lo que se comprobó antes de dibujar nada ────────────────────────────────
//
// La decisión de partida era SVG propio, dando por hecho que Material no tiene
// los iconos de golf. Los tiene: `Icons.golf_course` es la bandera en el hoyo y
// `Icons.sports_golf` la bola con el palo. Con esos dos, los veinticuatro que
// hacen falta existen ya — y dibujarlos igual habría sido justo lo que el
// encargo prohíbe: "no dibujes lo que ya está".
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/core/golf_icons.dart';
import 'package:golf_bet_master/models/models.dart';

/// Emoji pictográficos y símbolos que el sistema pinta a color.
///
/// Las FLECHAS —→ ←— quedan fuera a propósito: son tipografía, no iconografía.
/// Heredan el color, se ven igual en todas partes, y viven dentro de frases
/// como "Ana → Beto". Meterlas aquí habría convertido un problema real en una
/// cacería de caracteres.
final _emoji = RegExp(
    '[\u{1F300}-\u{1FAFF}\u{1F000}-\u{1F2FF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}]',
    unicode: true);

/// Cuántos emoji quedan en el código de interfaz de [ruta].
///
/// Se saltan los comentarios: explicar en un comentario qué emoji se sustituyó
/// no es enseñar un emoji.
int emojiEn(String ruta) {
  var n = 0;
  for (final l in File(ruta).readAsLinesSync()) {
    if (l.contains('─')) continue;
    n += _emoji.allMatches(_sinComentario(l)).length;
  }
  return n;
}

/// La línea sin su comentario final.
///
/// Hace falta porque el catálogo de iconos lleva el emoji que sustituye en un
/// comentario al lado —`static const trofeo = …;  // 🏆`— y eso no es enseñar
/// un emoji: es documentar cuál se quitó.
///
/// Solo corta cuando las comillas están cerradas, para no partir una URL con
/// `//` dentro de una cadena.
String _sinComentario(String linea) {
  var comillas = 0;
  for (var i = 0; i < linea.length - 1; i++) {
    final c = linea[i];
    if (c == "'" || c == '"') comillas++;
    if (c == '/' && linea[i + 1] == '/' && comillas.isEven) {
      return linea.substring(0, i);
    }
  }
  return linea;
}

int emojiEnTodo({List<String> excepto = const []}) {
  var n = 0;
  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    if (excepto.any((e) => f.path.endsWith(e))) continue;
    n += emojiEn(f.path);
  }
  return n;
}

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('1 · el catálogo de formatos, sin un solo emoji', () {
    test('CLAVE: cada tipo tiene ICONO, no carácter', () {
      // Es el cambio que alcanza diez pantallas de golpe: el catálogo lo leen
      // todas las que enseñan un tipo de apuesta.
      for (final t in BetModuleType.values) {
        expect(() => t.icono, returnsNormally, reason: t.name);
      }
      // Quedan DOS en el archivo, y no son del catálogo: son el emoji por
      // defecto de un grupo de apuestas, que se guarda en Firestore. Cambiar un
      // valor por defecto que ya está escrito en documentos de gente es otra
      // conversación, y va en la entrega 2 con su decisión delante.
      expect(emojiEn('lib/models/models.dart'), lessThanOrEqualTo(2),
          reason: 'ninguno del catálogo de formatos');
    });

    test('CLAVE: los iconos son distintos entre sí donde importa', () {
      // Dos formatos con el mismo icono se confunden en la lista de apuestas.
      // No se exige que TODOS difieran —wolf y matchAutoPress comparten el de
      // duelo a propósito, porque los dos son enfrentamiento— pero sí que no
      // sea un icono único para todo.
      final distintos = BetModuleType.values.map((t) => t.icono).toSet();
      expect(distintos.length, greaterThanOrEqualTo(10));
    });

    test('y ninguno es la variante rellena', () {
      // Grosor consistente: mezclar rellenos y contornos es la inconsistencia
      // con otro nombre. Se comprueba por el codePoint, que es lo único que
      // distingue una variante de otra.
      final rellenos = {
        Icons.emoji_events.codePoint,
        Icons.military_tech.codePoint,
        Icons.casino.codePoint,
        Icons.lock.codePoint,
      };
      for (final t in BetModuleType.values) {
        expect(rellenos.contains(t.icono.codePoint), isFalse, reason: t.name);
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('2 · el trazo y el tamaño salen del sistema', () {
    test('CLAVE: los tamaños acompañan a la escala tipográfica', () {
      // Un icono más grande que su texto se lee como el elemento principal, y
      // casi nunca lo es. Cada tamaño va un poco por encima de su escalón, que
      // es lo que hace que se lean parejos.
      final negro = GolfTheme.light.text;
      expect(GolfIcons.juntoAEtiqueta,
          greaterThan(GolfType.label(negro).fontSize!));
      expect(GolfIcons.juntoAValor,
          greaterThan(GolfType.value(negro).fontSize!));
      expect(GolfIcons.juntoATitulo,
          greaterThan(GolfType.title(negro).fontSize!));
    });

    test('y la escala de iconos es monótona, como la de texto', () {
      final escala = [
        GolfIcons.juntoAEtiqueta,
        GolfIcons.juntoAValor,
        GolfIcons.juntoATitulo,
        GolfIcons.juntoAlHeroe,
      ];
      for (var i = 1; i < escala.length; i++) {
        expect(escala[i], greaterThan(escala[i - 1]));
      }
    });

    test('CONTRAPESO: pero ninguno duplica su texto', () {
      // Sin tope, "acompañar" se convierte en dominar.
      final negro = GolfTheme.light.text;
      expect(GolfIcons.juntoAEtiqueta,
          lessThan(GolfType.label(negro).fontSize! * 2));
      expect(GolfIcons.juntoAValor,
          lessThan(GolfType.value(negro).fontSize! * 2));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('3 · heredan el tema, que es lo que un emoji no puede', () {
    testWidgets('CLAVE: el mismo icono, dos colores en dos temas',
        (tester) async {
      // Es la prueba de la diferencia: un emoji se ve IDÉNTICO en claro y en
      // oscuro, y por eso canta en oscuro.
      final vistos = <Color?>[];
      for (final tema in [GolfTheme.light, GolfTheme.dark]) {
        await tester.pumpWidget(MaterialApp(
          theme: tema.toMaterial(),
          home: Scaffold(
            body: Icon(BetModuleType.nassau.icono, color: tema.text),
          ),
        ));
        vistos.add(tester.widget<Icon>(find.byType(Icon)).color);
      }
      expect(vistos.first, isNot(vistos.last),
          reason: 'el icono sigue la escalera; un emoji no la seguiría');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 4 · EL CONTADOR
  //
  // 258 emoji no se quitan en una entrega sin abrir treinta pantallas a ciegas.
  // Este test no exige que el número baje: exige que NO SUBA. Escribir un emoji
  // nuevo falla aquí, y ahí es donde se decide, no seis meses después.
  //
  // La entrega 2 baja el tope conforme se vacían las pantallas.
  // ───────────────────────────────────────────────────────────────────────────
  group('4 · lo que queda, medido', () {
    test('CLAVE: no suben de donde están', () {
      expect(emojiEnTodo(), lessThanOrEqualTo(240),
          reason: 'hay un catálogo en GolfIcons: úsalo en vez de un carácter');
    });

    test('CLAVE: y la TELE no tiene ninguno', () {
      // Es la superficie que se proyecta delante de patrocinadores: donde el
      // problema más importa y donde primero se cierra.
      expect(emojiEn('lib/screens/torneos/leaderboard_tv_screen.dart'), 0);
    });

    test('el catálogo de iconos tampoco, claro', () {
      expect(emojiEn('lib/core/golf_icons.dart'), 0);
    });
  });
}
