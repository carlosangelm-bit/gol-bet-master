// Carry por pareja en Nassau — portado de MatchAutoPressConfig.
//
// En un grupo de cuatro, A puede pedir carry contra B y no contra C. El
// booleano carryApplied es de módulo entero y no puede expresarlo.
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';

void main() {
  const a = 'a', b = 'b', c = 'c';

  test('la clave del par es simétrica', () {
    expect(NassauConfig.carryPairKey(a, b), NassauConfig.carryPairKey(b, a));
  });

  test('usa el MISMO formato que MatchAutoPressConfig', () {
    // Si difirieran, migrar un módulo de un tipo al otro exigiría traducir
    // cada clave — y una traducción fallida no da error: el carry dejaría de
    // aplicarse en silencio.
    expect(NassauConfig.carryPairKey(a, b), MatchAutoPressConfig.pairKey(a, b));
  });

  test('el carry aplica solo a la pareja que lo pidió', () {
    final cfg = const NassauConfig().copyWith(
      carryByPair: {NassauConfig.carryPairKey(a, b): 2.0},
    );
    expect(cfg.carryAppliedForPair(a, b), isTrue);
    expect(cfg.carryFactorForPair(a, b), 2.0);

    expect(cfg.carryAppliedForPair(a, c), isFalse);
    expect(cfg.carryFactorForPair(a, c), 1.0);
  });

  test('cada pareja puede tener su propio factor', () {
    final cfg = const NassauConfig().copyWith(carryByPair: {
      NassauConfig.carryPairKey(a, b): 2.0,
      NassauConfig.carryPairKey(a, c): 3.0,
    });
    expect(cfg.carryFactorForPair(a, b), 2.0);
    expect(cfg.carryFactorForPair(a, c), 3.0);
  });

  group('retrocompatibilidad', () {
    test('sin mapa, el booleano legacy sigue mandando', () {
      const cfg = NassauConfig(carryApplied: true, carryFactor: 2.0);
      expect(cfg.carryAppliedForPair(a, b), isTrue);
      expect(cfg.carryFactorForPair(a, b), 2.0);
    });

    test('con mapa, el legacy deja de aplicarse', () {
      // Si ambos mandaran, una ronda migrada cobraría carry a parejas que
      // nunca lo pidieron.
      final cfg = const NassauConfig(carryApplied: true, carryFactor: 2.0)
          .copyWith(carryByPair: {NassauConfig.carryPairKey(a, b): 2.0});
      expect(cfg.carryAppliedForPair(a, c), isFalse);
      expect(cfg.carryFactorForPair(a, c), 1.0);
    });

    test('roundtrip JSON conserva el mapa', () {
      final cfg = const NassauConfig().copyWith(
        carryByPair: {NassauConfig.carryPairKey(a, b): 2.5},
      );
      final back = NassauConfig.fromJson(cfg.toJson());
      expect(back.carryFactorForPair(a, b), 2.5);
    });

    test('un JSON sin la clave carga con mapa vacío', () {
      final back = NassauConfig.fromJson(const NassauConfig().toJson());
      expect(back.carryByPair, isEmpty);
    });
  });
}
