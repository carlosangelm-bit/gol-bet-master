// ─────────────────────────────────────────────────────────────────────────────
// home_catalog_test.dart — el catálogo de Inicio no puede derivar del enum
//
// "APUESTAS DISPONIBLES" era una lista de texto plano que NO mencionaba
// BetModuleType ni una vez. Derivó en las dos direcciones a la vez: siguió
// anunciando Match + Press meses después de retirarlo, y nunca llegó a
// mencionar Bola Baja / Bola Alta.
//
// Ese fallo no lo encuentra un grep del enum, justamente porque la lista no lo
// usaba. Lo encuentra alguien abriendo la app. Este test lo encuentra antes.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/screens/home/home_screen.dart';

void main() {
  group('el catálogo cubre exactamente lo ofrecible', () {
    test('hay una ficha por cada tipo que se puede crear', () {
      final conFicha = betCatalogTypes.toSet();
      for (final t in creatableBetTypes) {
        expect(conFicha, contains(t),
            reason: '${t.label} se puede crear pero no se explica en Inicio');
      }
    });

    test('no se anuncia nada que no exista', () {
      // Una ficha bajo el título "APUESTAS DISPONIBLES" es una promesa: el
      // usuario lo ve, lo quiere y tiene que encontrarlo.
      //
      // Hubo un filtro `isCreatable` para esconder Match + Press dejando su
      // ficha escrita. Se fue con el tipo, así que ahora la promesa se comprueba
      // contra el catálogo entero.
      for (final t in betCatalogTypes) {
        expect(BetModuleType.values, contains(t),
            reason: '${t.label} se anuncia y no existe');
      }
    });

    test('ninguna ficha repetida', () {
      expect(betCatalogTypes.toSet().length, betCatalogTypes.length);
    });
  });

  group('vocabulario del grupo', () {
    test('Oyes y Unidades, no "Oyeses" ni "Units"', () {
      // Un nombre que hay que traducir mentalmente ya cuesta un paso.
      expect(BetModuleType.oyeses.label, 'Oyes');
      expect(BetModuleType.units.label, 'Unidades');
    });

    test('el nombre de la ficha sale del enum, no de una copia', () {
      // Dos sitios con el mismo nombre a mano son dos sitios que se pueden
      // contradecir.
      for (final t in betCatalogTypes) {
        expect(betCatalogNameOf(t), t.label, reason: '$t');
      }
    });
  });
}
