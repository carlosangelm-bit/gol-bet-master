// ─────────────────────────────────────────────────────────────────────────────
// ICONOGRAFÍA — las dos entregas, cerradas
//
// El inventario dio 258 emojis en unas treinta pantallas, no los once que se
// listaron a ojo. Fue en dos:
//
//   1 · el SISTEMA y el CATÁLOGO, que con un cambio alcanzó las diez pantallas
//       que enseñan tipos de apuesta, más la tele: 258 → 240
//   2 · las pantallas sueltas, guiadas por el contador de abajo: 240 → 0
//
// El contador ya no es un tope que baja. Es un CERO, y por eso ahora dice otra
// cosa: el primer emoji que alguien escriba a partir de hoy falla aquí.
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
      // Los DOS que quedaban eran el ⛳ por defecto de un grupo de apuestas,
      // que se guarda en Firestore. Ya no está: ahora se guarda una CLAVE.
      expect(emojiEn('lib/models/models.dart'), 0,
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
  // 4 · EL CONTADOR, ya en cero
  //
  // Durante la entrega 1 esto era un tope que solo pedía NO SUBIR, porque 258
  // emoji no se quitan de treinta pantallas a ciegas. Ya está en cero, y un
  // cero se defiende solo: escribir un emoji nuevo falla aquí, que es donde se
  // decide, y no seis meses después cuando ya hay veinte.
  // ───────────────────────────────────────────────────────────────────────────
  group('4 · lo que queda, medido', () {
    test('CLAVE: no queda ninguno en toda la interfaz', () {
      expect(emojiEnTodo(), 0,
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

  // ───────────────────────────────────────────────────────────────────────────
  // 5 · LA MARCA QUE SE GUARDA
  //
  // El contador de arriba lee el CÓDIGO. Y había una segunda vía que no mide:
  // emoji que llegan como DATO. Un grupo de apuestas, un torneo y una plantilla
  // guardan cada uno su marca, elegida por su dueño de una lista de veinte
  // caracteres. El contador podía marcar cero y la pantalla seguir pintando un
  // 🏆 salido de Firestore.
  //
  // Ahora se guarda una CLAVE del catálogo. Y como Carlos borra la base al
  // lanzar, esto va SIN MIGRACIÓN: lo que se exige aquí no es que los valores
  // viejos se conviertan, sino que NO ROMPAN mientras existan.
  // ───────────────────────────────────────────────────────────────────────────
  group('5 · la marca guardada es una clave, no un carácter', () {
    test('CLAVE: un valor viejo NO rompe, cae en la bandera', () {
      // Es la promesa entera del "sin migración". Un grupo guardado ayer con
      // '⛳' enseña la marca por defecto, no un hueco ni una excepción.
      for (final viejo in ['⛳', '⛳️', '🏆', '🤑', '', null, 'inventada']) {
        expect(() => GolfIcons.deClave(viejo), returnsNormally, reason: '$viejo');
        expect(GolfIcons.deClave(viejo), GolfIcons.bandera, reason: '$viejo');
      }
    });

    test('y una clave buena devuelve SU icono, no el de por defecto', () {
      // El contrapeso del test de arriba: si `deClave` devolviera siempre la
      // bandera, aquel pasaría igual y la paleta no serviría para nada.
      expect(GolfIcons.deClave('trofeo'), GolfIcons.trofeo);
      expect(GolfIcons.deClave('dinero'), GolfIcons.dinero);
      expect(GolfIcons.deClave('trofeo'), isNot(GolfIcons.deClave('dinero')));
    });

    test('la clave inicial está en la paleta', () {
      // Si no lo estuviera, un grupo NUEVO nacería cayendo en el respaldo, que
      // es el mismo síntoma que teníamos con los viejos.
      expect(GolfIcons.paleta.containsKey(GolfIcons.claveInicial), isTrue);
    });

    test('CONTRAPESO: la paleta no puede encogerse por debajo de lo que había',
        () {
      // Las listas que sustituye tenían diez, doce y veinte emoji. Recortarla a
      // cinco "para simplificar" deja sin marca a quien ya eligió una, y el
      // fallo se vería como grupos idénticos, no como un error.
      expect(GolfIcons.paleta.length, greaterThanOrEqualTo(12));
      expect(GolfIcons.paleta.values.toSet().length, GolfIcons.paleta.length,
          reason: 'dos claves con el mismo icono son dos marcas indistinguibles');
    });

    test('CLAVE: un grupo nuevo nace con clave, y un torneo con la suya', () {
      // Un dato por defecto que no es del catálogo vuelve a meter caracteres por
      // la puerta de atrás.
      final g = BettingGroup(
          id: 'g', name: 'Los de siempre', updatedAt: DateTime(2026, 8, 30));
      expect(GolfIcons.paleta.containsKey(g.emoji), isTrue,
          reason: 'el grupo guarda una clave, no un carácter');

      // Y cada cosa nace con la marca que la describe: el torneo con el trofeo,
      // no con la bandera de todo lo demás.
      expect(GolfIcons.deClave('trofeo'), GolfIcons.trofeo);
    });

    testWidgets('CLAVE: y la marca vieja se DIBUJA, no se escribe',
        (tester) async {
      // La prueba de que la segunda vía está cerrada: se monta con el valor de
      // ayer y lo que sale es un Icon del tema, no un Text con el carácter.
      const marcaDeAyer = '⛳';
      await tester.pumpWidget(MaterialApp(
        theme: GolfTheme.light.toMaterial(),
        home: Scaffold(
          body: Icon(GolfIcons.deClave(marcaDeAyer),
              size: GolfIcons.juntoATitulo),
        ),
      ));
      expect(find.text(marcaDeAyer), findsNothing);
      expect(find.byIcon(GolfIcons.bandera), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 6 · LOS QUE NO TENÍAN EQUIVALENTE
  //
  // Seis eventos pagaban unidades con emoji de ANIMALES y de PLAYA: 🐦 un
  // birdie, 🦅 un eagle, 🏖️ un par salvado desde arena. Ninguno DICE lo que
  // mide: el pájaro es un chiste del inglés, no un símbolo. Se resolvieron por
  // significado, igual que la serpiente y el lobo en la entrega 1.
  // ───────────────────────────────────────────────────────────────────────────
  group('6 · los seis eventos, resueltos por significado', () {
    test('CLAVE: los seis se distinguen entre sí', () {
      // Dos eventos con el mismo icono son dos filas idénticas en el detalle
      // de unidades, que es donde se comprueba cuánto pagó cada cosa.
      final seis = {
        GolfIcons.bajoPar,
        GolfIcons.dobleBajoPar,
        GolfIcons.bunker,
        GolfIcons.unico,
        GolfIcons.destello,
        GolfIcons.hoyoDirecto,
      };
      expect(seis.length, 6);
    });

    test('y el doble es el doble, no otro dibujo cualquiera', () {
      // Un eagle es un birdie por dos. Que el icono lo diga es la diferencia
      // entre un símbolo y una etiqueta de color.
      expect(GolfIcons.dobleBajoPar, isNot(GolfIcons.bajoPar));
      expect(GolfIcons.bajoPar, Icons.trending_down);
      expect(GolfIcons.dobleBajoPar, Icons.keyboard_double_arrow_down);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 7 · EL REPERTORIO: lo que el contador de emojis NO cazaba
  //
  // Apareció un ▯ en el estado vacío de Plantillas y el contador marcaba cero.
  // Al mirarlo salieron DOS problemas distintos, y merecen dos pruebas:
  //
  //   · RESIDUOS. `1️⃣` son TRES puntos de código: el dígito, un selector de
  //     variación y un keycap envolvente. El barrido se llevó el selector y
  //     dejó el keycap huérfano — un carácter que no se ve, no se busca y no
  //     se distingue leyendo el código. Es el residuo que deja este tipo de
  //     barrido, y es exactamente lo que hay que impedir que vuelva.
  //
  //   · GLIFOS QUE NO EXISTEN. El ▯ NO era un residuo: era `⋮` (U+22EE), un
  //     carácter completo y bien formado del que la fuente no tiene dibujo.
  //     Contra eso no vale una regla sobre codificación: la única defensa es
  //     un REPERTORIO CERRADO —lo que se ha visto pintar en pantalla— donde
  //     cada símbolo nuevo entra a mano y después de verlo.
  //
  // Las flechas → ← siguen dentro: son tipografía, heredan el color y están
  // comprobadas en pantalla. Lo que cambia es que ahora hay una lista, y no
  // un criterio en la cabeza de alguien.
  // ───────────────────────────────────────────────────────────────────────────

  /// El repertorio: lo único no ASCII que puede aparecer en la interfaz.
  ///
  /// Para añadir uno: míralo primero en pantalla, en los dos temas. Ese es el
  /// trámite entero, y es el que faltaba.
  const repertorio = '·—→←×¿¡…–−•°«»½±ªº';

  /// Puntos de código que están ROTOS o son INVISIBLES.
  ///
  /// No es cuestión de gusto: un selector de variación suelto o una marca
  /// combinante huérfana no dibujan nada por sí solos y no se ven al revisar.
  bool esResiduo(int c) =>
      (c >= 0xFE00 && c <= 0xFE0F) ||    // selectores de variación
      (c >= 0x200B && c <= 0x200F) ||    // ancho cero y bidi
      (c >= 0x2060 && c <= 0x2064) ||    // juntadores invisibles
      c == 0xFEFF ||                     // marca de orden de bytes
      (c >= 0x0300 && c <= 0x036F) ||    // diacríticos combinantes
      (c >= 0x20D0 && c <= 0x20F0) ||    // combinantes de símbolo (el keycap)
      (c >= 0xD800 && c <= 0xDFFF) ||    // mitades sueltas de un par sustituto
      (c < 0x20 && c != 0x0A && c != 0x09) ||
      c == 0x7F;

  /// Una letra latina con tilde, diéresis o eñe. Texto normal.
  bool esLetraLatina(int c) => c >= 0xC0 && c <= 0x24F && c != 0xD7 && c != 0xF7;

  /// Recorre la interfaz carácter a carácter.
  ///
  /// Mira la LÍNEA ENTERA sin su comentario, no las cadenas extraídas con una
  /// expresión regular: el código Dart es ASCII, así que lo que queda no ASCII
  /// está dentro de una cadena. Y no se le escapan las cadenas partidas o con
  /// interpolación, que es justo donde se escondían los ordinales `1ª` `2º`.
  ///
  /// Se saltan las líneas de consola —`debugPrint`, `writeln`—: un volcado de
  /// diagnóstico no es interfaz, y ahí las cajas de dibujo sí valen.
  List<String> recorrerInterfaz(bool Function(int) falla) {
    final malos = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      var n = 0;
      for (final l in f.readAsLinesSync()) {
        n++;
        if (l.contains('─') ||
            l.contains('debugPrint(') ||
            l.contains('writeln(') ||
            l.contains('print(')) {
          continue;
        }
        for (final c in _sinComentario(l).runes) {
          if (c < 128 || esLetraLatina(c)) continue;
          if (falla(c)) {
            malos.add('${f.path}:$n  U+${c.toRadixString(16).toUpperCase()} '
                '${String.fromCharCode(c)}');
          }
        }
      }
    }
    return malos;
  }

  group('7 · ni residuos ni glifos que no existen', () {
    test('CLAVE: ningún carácter roto ni invisible en la interfaz', () {
      // El keycap huérfano de `1️⃣` entraba por aquí, y por ningún otro sitio.
      expect(recorrerInterfaz(esResiduo), isEmpty,
          reason: 'un punto de código que no dibuja nada por sí solo');
    });

    test('CLAVE: y ningún símbolo fuera del repertorio', () {
      // El ⋮ entraba por aquí: completo, legal, y sin dibujo en la fuente.
      expect(
          recorrerInterfaz((c) =>
              !esResiduo(c) && !repertorio.runes.contains(c)),
          isEmpty,
          reason: 'míralo en pantalla en los dos temas, y luego añádelo '
              'al repertorio de arriba');
    });

    test('CONTRAPESO: el repertorio no está vacío ni se lo traga todo', () {
      // Sin esto, borrar la lista o meterle un rango entero dejaría las dos
      // pruebas de arriba en verde para siempre.
      expect(repertorio.runes.length, greaterThanOrEqualTo(10));
      expect(repertorio.runes.every((c) => !esResiduo(c)), isTrue,
          reason: 'nada roto puede estar permitido');
      // Y las flechas siguen dentro, que es la excepción declarada desde la
      // entrega 1: son tipografía, no iconografía.
      expect(repertorio.contains('→'), isTrue);
    });

    test('CONTRAPESO: el recorrido mira de verdad, no devuelve vacío siempre',
        () {
      // Si `recorrerInterfaz` estuviera roto —una ruta mala, un filtro que se
      // come todo— las dos pruebas CLAVE pasarían sin mirar nada.
      final letras = recorrerInterfaz((c) => c == 0x2192); // la flecha →
      expect(letras, isNotEmpty,
          reason: 'la interfaz tiene flechas: si no las ve, no ve nada');
    });
  });
}
