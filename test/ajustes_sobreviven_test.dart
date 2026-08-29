// ─────────────────────────────────────────────────────────────────────────────
// EDITAR EN UN SITIO NO PUEDE DESHACERSE EN OTRO
//
// El criterio de Carlos aplicado al asistente. _sincronizarModulos reconstruye
// los módulos del flujo desde la receta cada vez que se sale de Cuenta,
// Participantes o Montos — así que lo ajustado en Detalle se perdía.
//
// REPRODUCIDO recorriendo el asistente de verdad antes de tocar nada:
//
//   Medal a 9 hoyos → atrás hasta Cuenta → adelante  →  vuelve a 18
//
// Y con el arreglo, el mismo recorrido deja 9. Esa comprobación se hizo con un
// recorrido de un solo uso; lo que queda fijado aquí es la REGLA, que es lo que
// se puede probar sin montar nueve pasos de interfaz.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/bet_recipe.dart';

BetModuleInstance _medal({int holes = 18, double valor = 100}) =>
    BetModuleInstance(
      id: 'flujo_scoreTotal',
      type: BetModuleType.medal,
      name: 'Medal',
      participantIds: const ['a', 'b'],
      medalConfig: MedalConfig(value: valor, holes: holes),
    );

void main() {
  group('lo ajustado sobrevive a la reconstrucción', () {
    test('los hoyos elegidos en Detalle ganan a los de la receta', () {
      final receta = _medal(); // 18, como sale de BetRecipe.build
      final ajustado = _medal(holes: 9);
      final salida = BetRecipe.conservandoAjustes(ajustado, receta);
      expect(salida.medal.holes, 9);
    });

    test('y también el importe y el modo', () {
      final receta = _medal();
      final ajustado = _medal(holes: 9, valor: 250);
      final salida = BetRecipe.conservandoAjustes(ajustado, receta);
      expect(salida.medal.value, 250);
      expect(salida.medal.holes, 9);
    });

    test('la receta sigue mandando en la FORMA: id, tipo y participantes', () {
      // Lo que se trasplanta es la configuración, no la identidad. Si esto se
      // llevara el id o los participantes, cambiar de jugadores en el asistente
      // dejaría de tener efecto.
      final receta = _medal().copyWith(participantIds: const ['a', 'b', 'c']);
      final ajustado = _medal(holes: 9);
      final salida = BetRecipe.conservandoAjustes(ajustado, receta);
      expect(salida.participantIds, ['a', 'b', 'c']);
      expect(salida.id, receta.id);
      expect(salida.type, receta.type);
    });

    test('con tipos distintos NO se trasplanta nada', () {
      // Cambiar la bola de equipo puede cambiar el tipo de la misma cuenta, y
      // meterle la config de otro formato sería peor que perderla.
      final receta = BetModuleInstance(
        id: 'flujo_scoreTotal',
        type: BetModuleType.putts,
        name: 'Putts',
        participantIds: const ['a', 'b'],
        puttsConfig: const PuttsConfig(value: 50, puttsMode: PuttsMode.total),
      );
      final salida = BetRecipe.conservandoAjustes(_medal(holes: 9), receta);
      expect(salida.type, BetModuleType.putts);
      expect(salida.putts.value, 50);
      expect(identical(salida, receta), isTrue,
          reason: 'sin tipo común, se devuelve la receta tal cual');
    });

    test('el contrapeso: sin ajuste previo la receta queda intacta', () {
      final receta = _medal();
      final salida = BetRecipe.conservandoAjustes(_medal(), receta);
      expect(salida.medal.holes, 18);
      expect(salida.medal.value, 100);
    });
  });
}
