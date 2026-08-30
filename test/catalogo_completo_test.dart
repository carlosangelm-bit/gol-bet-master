// ─────────────────────────────────────────────────────────────────────────────
// TODO TIPO TIENE SU FICHA COMPLETA
//
// Al añadir un formato al enum, el analizador cazó los dieciséis switch
// exhaustivos del proyecto —y no cazó tres mapas const indexados con [this]!:
// label, icon y description—. Un mapa incompleto compila y revienta al pintar
// la etiqueta, que es la clase de fallo que solo aparece usando la app.
//
// Los tres pasaron a switch, así que ahora el compilador los cubre. Este test
// existe por lo que el compilador NO puede cubrir: cualquier otro sitio que
// resuelva por tipo con una estructura de datos en vez de un switch.
//
// Recorre los valores del enum, no una lista escrita a mano. Una lista
// duplicada aquí no cazaría un tipo nuevo, que es exactamente el fallo del
// catálogo de Inicio.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';

void main() {
  group('la ficha de cada tipo', () {
    for (final t in BetModuleType.values) {
      test('${t.name} tiene etiqueta, icono y descripción', () {
        expect(() => t.label, returnsNormally);
        expect(t.label.trim(), isNotEmpty);
        // Icono, no emoji: un emoji no hereda el color del tema, cambia de
        // dibujo según el aparato, y a color junto a texto gris es el pico
        // visual de la pantalla sin merecerlo.
        expect(() => t.icono, returnsNormally);
        expect(() => t.description, returnsNormally);
        expect(t.description.trim(), isNotEmpty);
      });

      test('${t.name} tiene reglas de compatibilidad', () {
        expect(() => t.rules, returnsNormally);
        // Un tipo que no admite equipos DEBE decir por qué: la opción atenuada
        // sin motivo enseña que algo está prohibido y esconde el modelo.
        final r = t.rules;
        if (!r.teams && !r.requiresTeams) {
          expect(r.sinEquipos, isNotNull,
              reason: '${t.name} no admite equipos y no dice por qué');
        }
        if (!r.segments) {
          expect(r.sinSegmentos, isNotNull,
              reason: '${t.name} no liquida por segmentos y no dice por qué');
        }
      });
    }

    test('y un módulo por defecto se puede construir de cada uno', () {
      // defaultFor resuelve la config tipada. Un tipo sin su rama devolvería
      // una config nula y el módulo liquidaría con valores de otro formato.
      for (final t in BetModuleType.values) {
        final m = BetModuleInstance.defaultFor(t, const ['a', 'b'], id: t.name);
        expect(m.type, t);
        expect(() => m.summaryLabel, returnsNormally,
            reason: '${t.name}: summaryLabel');
        expect(() => m.configSignature, returnsNormally,
            reason: '${t.name}: configSignature');
      }
    });
  });
}
