// ─────────────────────────────────────────────────────────────────────────────
// NINGÚN BOTÓN ENSEÑA SU PROPIO CÓDIGO
//
// El botón de avanzar de hoyo decía, literalmente y en verde a dos líneas:
//
//     ${startingNine == StartingNine.back ? "Front 9 →" : "Back 9 →"}
//
// El `$` estaba ESCAPADO, así que la interpolación no interpolaba.
//
// ── El barrido encontró dos más, y las tres tienen la misma forma ───────────
//
// Las tres eran la SEGUNDA RAMA de un ternario cuya primera rama estaba bien:
//
//     avisos.length == 1
//         ? 'Una ventaja pactada no aplica...'     ← bien
//         : '\${avisos.length} ventajas...'        ← escapado
//
// O sea que no se escribieron mal: se copiaron mal, y nadie las vio pintadas
// porque son la rama que sale solo cuando hay más de uno.
//
// Por eso esto es una prueba y no un arreglo: la forma se repite.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Cadenas de Dart de una línea, con comilla simple o doble, sin las `r'...'`.
final _cadena = RegExp(r"""(?<!r)(['"])((?:\\.|(?!\1)[^\\\n])*)\1""");

/// Un `$` escapado que abre llave: la interpolación no interpola.
final _dolarEscapado = RegExp(r'\\\$\s*\{');

/// Una llave suelta sin `$` delante: alguien se comió el dólar.
final _llaveSuelta = RegExp(r'(?<![$\\])\{');

/// Prosa donde una llave es deliberada: describe la FORMA de algo, no lo
/// interpola. Se listan una por una para que añadir una excepción sea una
/// decisión y no un descuido.
const _deliberadas = {
  '/organizador/{id del torneo}',
};

void main() {
  test('CLAVE: ninguna cadena de la app enseña código', () {
    final hallazgos = <String>[];
    var revisados = 0;
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      revisados++;
      final lineas = f.readAsStringSync().split('\n');
      for (var i = 0; i < lineas.length; i++) {
        final l = lineas[i];
        if (l.trimLeft().startsWith('//')) continue;
        final sinComentario = l.split('//').first;
        for (final m in _cadena.allMatches(sinComentario)) {
          final cuerpo = m.group(2)!;
          if (_deliberadas.any(cuerpo.contains)) continue;
          if (_dolarEscapado.hasMatch(cuerpo)) {
            hallazgos.add('${f.path}:${i + 1}  dólar escapado → ${l.trim()}');
          } else if (_llaveSuelta.hasMatch(cuerpo) && !cuerpo.contains(r'$')) {
            hallazgos.add('${f.path}:${i + 1}  llave sin dólar → ${l.trim()}');
          }
        }
      }
    }
    expect(hallazgos, isEmpty,
        reason: 'esto sale pintado en la pantalla:\n${hallazgos.join('\n')}');

    // ── Y que de verdad haya mirado la app entera ─────────────────────────
    //
    // Un barrido solo falla cuando encuentra algo, así que ESTRECHARLO no lo
    // rompe: pasaría igual mirando un solo fichero. Se fija el suelo para que
    // reducir el alcance sea una prueba en rojo y no un cambio invisible.
    expect(revisados, greaterThan(80),
        reason: 'el barrido dejó de mirar la app entera');
  });

  test('CONTRAPESO: el barrido reconoce el fallo que lo motivó', () {
    // Si el detector dejara de detectar, la prueba de arriba pasaría siempre y
    // no protegería nada.
    const roto = r"""  final x = '\${algo.length} cosas';""";
    final cuerpo = _cadena.firstMatch(roto.split('//').first)!.group(2)!;
    expect(_dolarEscapado.hasMatch(cuerpo), isTrue);

    // Y no confunde un símbolo de moneda, que es legítimo y abunda.
    const dinero = r"""  final y = 'Vale \$${v.toStringAsFixed(0)} por duelo';""";
    final cuerpoDinero =
        _cadena.firstMatch(dinero.split('//').first)!.group(2)!;
    expect(_dolarEscapado.hasMatch(cuerpoDinero), isFalse);
  });
}
