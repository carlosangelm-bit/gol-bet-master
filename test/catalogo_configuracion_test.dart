// ─────────────────────────────────────────────────────────────────────────────
// UNA CONFIGURACIÓN, UNA FORMA DE DECIRLA
//
// El criterio de Carlos, después de cuatro fallos que resultaron ser el mismo:
// "lo importante sería que toda la UI se base en la misma configuración de
// apuesta". Una superficie que muestra un dato tiene que mostrar EL DATO.
//
// El barrido por estructura —no por texto— encontró el formato descrito en
// CUATRO superficies con TRES pares de literales distintos, y la explicación
// larga copiada palabra por palabra en dos sitios:
//
//   bets_screen        'Todos vs todos' / '1 Pot'        ← t minúscula
//   setup_screen       'Todos vs Todos' / '1 Pot'
//   game_presets       'Todos vs Todos' / '1 Pot'
//   bet_module_edit    ['1 Pot', 'Todos vs Todos']
//
// Cada copia es una oportunidad de que una cambie y las otras no. Ya pasó: el
// chip que decía "Todos vs Todos" mientras se construía onePot.
//
// ── Por qué este test lee el código fuente ────────────────────────────────────
//
// Porque la propiedad que hay que proteger no es un valor: es que NO EXISTA una
// segunda copia. Un test de widget comprueba que una pantalla dice lo correcto
// hoy; este comprueba que mañana no se pueda escribir la frase suelta en otra.
// Es el mismo barrido que ya funcionó con betTypeSections y aplicaEnFormato,
// hecho ejecutable.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';

/// Todo el código de interfaz: pantallas y widgets.
List<File> _superficies() {
  final out = <File>[];
  for (final dir in ['lib/screens', 'lib/widgets']) {
    final d = Directory(dir);
    if (!d.existsSync()) continue;
    for (final f in d.listSync(recursive: true)) {
      if (f is File && f.path.endsWith('.dart')) out.add(f);
    }
  }
  return out;
}

void main() {
  group('1 · el catálogo dice las cosas una vez', () {
    test('cada modo tiene etiqueta, explicación y resumen, y son distintos', () {
      final labels = BetFormatMode.values.map((m) => m.label).toSet();
      expect(labels.length, BetFormatMode.values.length);
      for (final m in BetFormatMode.values) {
        expect(m.label, isNotEmpty);
        expect(m.explicacion, isNotEmpty);
        expect(m.resumen, isNotEmpty);
        // La explicación empieza nombrando el modo: es lo que la hace legible
        // suelta, debajo de un selector.
        expect(m.explicacion, startsWith(m.label));
      }
    });

    test('cada alcance tiene insignia y consecuencia, y son distintas', () {
      final ins = BetScopeKind.values.map((k) => k.insignia).toSet();
      expect(ins.length, BetScopeKind.values.length);
      for (final k in BetScopeKind.values) {
        expect(k.consecuencia, isNotEmpty, reason: k.name);
      }
    });

    test('la consecuencia del alcance abierto habla de DINERO, no de comodidad',
        () {
      // Era "quien se sume después entra automáticamente" — verdad, y no lo que
      // importa. Lo que importa es que multiplica la apuesta por pareja, que es
      // lo que le pasó a los dos Nassau de la ronda del 28.
      expect(BetScopeKind.everyone.consecuencia, contains('liquida'));
      expect(BetScopeKind.pair.consecuencia, contains('liquida'));
    });
  });

  group('1b · y las dice en el mismo idioma', () {
    test('ninguna etiqueta mezcla inglés con español', () {
      // El catálogo nació con "1 Pot" junto a "Todos vs Todos", y las dos
      // insignias salían en la misma pantalla de Apuestas.
      //
      // El test que lee el código fuente NO podía cazarlo: comprueba que no haya
      // una segunda COPIA, y no la había. Un catálogo centraliza DÓNDE vive la
      // palabra, no si la palabra es buena. Esto cubre lo otro.
      const enIngles = ['Pot', 'All vs', 'Head to head', 'Skins pot'];
      for (final m in BetFormatMode.values) {
        for (final p in enIngles) {
          expect(m.label.contains(p), isFalse,
              reason: '${m.name}: "${m.label}" mezcla idiomas');
        }
      }
    });
  });

  group('2 · ninguna superficie escribe su propia versión', () {
    test('las etiquetas de formato solo viven en el catálogo', () {
      final prohibidos = [
        "'Todos vs todos'",
        "'Todos vs Todos'",
        "'1 Pot'",
      ];
      final culpables = <String>[];
      for (final f in _superficies()) {
        final src = f.readAsStringSync();
        for (final p in prohibidos) {
          if (src.contains(p)) culpables.add('${f.path}: $p');
        }
      }
      expect(culpables, isEmpty,
          reason: 'usa BetFormatMode.label en vez del literal:\n'
              '${culpables.join("\n")}');
    });

    test('y las insignias de alcance tampoco', () {
      final prohibidos = ["'TODA LA PARTIDA'", "'USTEDES DOS'"];
      final culpables = <String>[];
      for (final f in _superficies()) {
        final src = f.readAsStringSync();
        for (final p in prohibidos) {
          if (src.contains(p)) culpables.add('${f.path}: $p');
        }
      }
      expect(culpables, isEmpty,
          reason: 'usa BetScopeKind.insignia en vez del literal:\n'
              '${culpables.join("\n")}');
    });

    test('la explicación larga no está copiada en ninguna pantalla', () {
      // Estaba dos veces, palabra por palabra, en el asistente y en Plantillas.
      final trozo = 'un solo ganador por hoyo/segmento';
      final culpables = [
        for (final f in _superficies())
          if (f.readAsStringSync().contains(trozo)) f.path
      ];
      expect(culpables, isEmpty,
          reason: 'usa BetFormatMode.explicacion:\n${culpables.join("\n")}');
    });

    test('el contrapeso: el catálogo SÍ las tiene', () {
      // Sin esto, borrar las frases de todas partes pasaría los tests de arriba.
      //
      // Se comprueba contra el ENUM y no grepeando el archivo: la primera
      // versión buscaba "'1 Pot'" como texto en models.dart y siguió pasando
      // cuando ese literal ya solo estaba dentro de un comentario. Un
      // contrapeso que se satisface con un comentario no es un contrapeso.
      for (final m in BetFormatMode.values) {
        expect(m.label.trim(), isNotEmpty);
        expect(m.explicacion.length, greaterThan(m.label.length));
      }
      for (final k in BetScopeKind.values) {
        expect(k.insignia.trim(), isNotEmpty);
      }
    });
  });
}
