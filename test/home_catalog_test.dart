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

    test('no se anuncia nada retirado', () {
      // Un tipo retirado bajo el título "APUESTAS DISPONIBLES" es una promesa
      // que la app no cumple: el usuario lo ve, lo quiere y no lo encuentra.
      for (final t in betCatalogTypes) {
        expect(t.isCreatable, isTrue,
            reason: '${t.label} está retirado y sigue anunciándose');
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
