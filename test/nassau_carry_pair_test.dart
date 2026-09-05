// ─────────────────────────────────────────────────────────────────────────────
// EL CARRY PEDIDO, POR PAREJA
//
// En un grupo de cuatro, A puede pedir carry contra B y no contra C.
//
// ── Lo que cambió: el valor del mapa ────────────────────────────────────────
//
// Era `carryByPair: Map<String, double>` —pareja → multiplicador— y ahora es
// `carryPedidoByPair: Map<String, String>` —pareja → **quién lo pidió**—.
//
// No es un cambio de tipo, es un cambio de concepto. El carry no multiplica
// nada: el que va perdiendo compra una SEGUNDA apuesta sobre los mismos nueve
// hoyos, del mismo importe, en la que recibe un golpe más. Y ese golpe es de una
// persona, así que con la clave del par sola no se sabría de quién.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';

void main() {
  const a = 'a', b = 'b', c = 'c';

  test('la clave del par es simétrica', () {
    expect(NassauConfig.carryPairKey(a, b), NassauConfig.carryPairKey(b, a));
  });

  test('usa el MISMO formato que MatchAutoPressConfig', () {
    // Si difirieran, migrar un módulo de un tipo al otro exigiría traducir cada
    // clave — y una traducción fallida no da error: la apuesta dejaría de
    // aparecer en silencio.
    expect(NassauConfig.carryPairKey(a, b), MatchAutoPressConfig.pairKey(a, b));
  });

  test('CLAVE: el carry aplica solo a la pareja que lo pidió', () {
    final cfg = const NassauConfig()
        .copyWith(carryPedidoByPair: {NassauConfig.carryPairKey(a, b): a});
    expect(cfg.carryPedidoPor(a, b), a);
    expect(cfg.carryPedidoPor(a, c), isNull);
  });

  test('CLAVE: guarda QUIÉN lo pidió, no cuánto multiplica', () {
    // Es la diferencia entera entre lo viejo y lo nuevo: el golpe extra es de
    // una persona. Con un factor no habría forma de saber a quién dárselo.
    final cfg = const NassauConfig().copyWith(carryPedidoByPair: {
      NassauConfig.carryPairKey(a, b): b,
    });
    expect(cfg.carryPedidoPor(a, b), b, reason: 'lo pidió B, no A');
    // Y se lee igual desde los dos lados: la clave es del par.
    expect(cfg.carryPedidoPor(b, a), b);
  });

  test('cada pareja tiene su propio solicitante', () {
    final cfg = const NassauConfig().copyWith(carryPedidoByPair: {
      NassauConfig.carryPairKey(a, b): a,
      NassauConfig.carryPairKey(a, c): c,
    });
    expect(cfg.carryPedidoPor(a, b), a);
    expect(cfg.carryPedidoPor(a, c), c);
  });

  group('el multiplicador se RETIRÓ', () {
    test('CONTRAPESO: NassauConfig ya no lo guarda ni lo escribe', () {
      // Si volviera, volvería el fallo: el total de 18 duplicado. La prueba se
      // hace sobre el JSON porque es lo que llega a Firestore y a la próxima
      // versión del modelo.
      final j = const NassauConfig(carryEnabled: true).toJson();
      expect(j.containsKey('carryFactor'), isFalse);
      expect(j.containsKey('carryApplied'), isFalse);
      expect(j.containsKey('carryByPair'), isFalse);
    });

    test('CONTRAPESO: MatchAutoPressConfig tampoco', () {
      // Allí el carry multiplicaba el match ENTERO y todas sus presiones. Se
      // retiró sin sustituto: Match + Press es una apuesta sobre los dieciocho,
      // sin primer y segundo nueve, y la apuesta paralela que nace de ir por
      // detrás ya existe con su nombre — es la presión.
      final j = const MatchAutoPressConfig().toJson();
      expect(j.containsKey('carryFactor'), isFalse);
      expect(j.containsKey('carryApplied'), isFalse);
      expect(j.containsKey('carryByPair'), isFalse);
    });
  });

  group('ida y vuelta a JSON', () {
    test('CLAVE: conserva quién lo pidió', () {
      final cfg = const NassauConfig()
          .copyWith(carryPedidoByPair: {NassauConfig.carryPairKey(a, b): a});
      final back = NassauConfig.fromJson(cfg.toJson());
      expect(back.carryPedidoPor(a, b), a);
    });

    test('un JSON sin la clave carga con mapa vacío', () {
      final back = NassauConfig.fromJson(const NassauConfig().toJson());
      expect(back.carryPedidoByPair, isEmpty);
    });

    test('CLAVE: una ronda guardada con el multiplicador PIERDE el carry', () {
      // Sin migración, a propósito. Un `carryApplied: true` viejo no se lee, y
      // la pareja tiene que volver a pedirlo — dos toques. Construir un puente
      // para datos que van a desaparecer costaría más que volver a pedirlo, y
      // el puente traduciría un multiplicador a una ventaja, que no es lo
      // mismo: se inventaría un golpe que nadie pactó.
      final vieja = {
        'frontValue': 50.0,
        'backValue': 50.0,
        'totalValue': 100.0,
        'carryEnabled': true,
        'carryApplied': true,
        'carryFactor': 2.0,
        'carryByPair': {'a|b': 2.0},
      };
      final back = NassauConfig.fromJson(vieja);
      expect(back.carryEnabled, isTrue, reason: 'el grupo sigue jugando carry');
      expect(back.carryPedidoByPair, isEmpty, reason: 'pero hay que re-pedirlo');
    });
  });
}
