// ─────────────────────────────────────────────────────────────────────────────
// bet_recipe_test.dart — el flujo rápido produce lo mismo que el manual
//
// El traductor convierte (qué se cuenta × cómo se divide × qué bola) en un
// BetModuleInstance. Si produjera algo distinto de lo que crea el flujo manual,
// dos usuarios que configuran la misma apuesta por caminos distintos jugarían
// apuestas distintas sin saberlo.
//
// La comparación es por configSignature, que resume tipo + config tipada e
// ignora ids y participantes: exactamente "qué se juega".
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/bet_recipe.dart';

const pids = ['a', 'b', 'c', 'd'];
const lados = [
  BetSide(id: 'A', name: 'Equipo A', playerIds: ['a', 'b']),
  BetSide(id: 'B', name: 'Equipo B', playerIds: ['c', 'd']),
];

BetRecipeResult _r(BetCount c, BetDivision d, {TeamBall? bola, bool eq = false}) =>
    BetRecipe.build(
      cuenta: c, division: d, bola: bola,
      participantIds: pids,
      sides: eq ? lados : null,
      id: 'fijo',
    );

void main() {
  group('produce el mismo módulo que el flujo manual', () {
    // El flujo manual crea con defaultFor. Si el traductor diverge, dos
    // caminos a la misma apuesta darían configuraciones distintas.
    void mismoQueManual(BetCount c, BetDivision d, BetModuleType esperado,
        {TeamBall? bola, bool eq = false}) {
      final res = _r(c, d, bola: bola, eq: eq);
      expect(res.ok, isTrue, reason: '${c.label} · $d fue rechazado: ${res.rechazo}');
      expect(res.module!.type, esperado);
      final manual = BetModuleInstance.defaultFor(esperado, pids,
          id: 'fijo', sides: eq ? lados : null);
      expect(res.module!.configSignature, manual.configSignature,
          reason: '${c.label} · $d difiere del flujo manual');
    }

    test('Puntos · Front·Back·Total → Nassau', () {
      mismoQueManual(BetCount.puntos, BetDivision.frontBackTotal,
          BetModuleType.nassau);
    });

    test('Puntos · una vuelta → Nassau', () {
      mismoQueManual(BetCount.puntos, BetDivision.soloNueve,
          BetModuleType.nassau);
    });

    test('Skins · toda la ronda → Skins', () {
      mismoQueManual(BetCount.skins, BetDivision.todaLaRonda,
          BetModuleType.skins);
    });

    test('Score total → Medal', () {
      mismoQueManual(BetCount.scoreTotal, BetDivision.todaLaRonda,
          BetModuleType.medal);
    });

    test('Putts → Putts', () {
      mismoQueManual(BetCount.putts, BetDivision.todaLaRonda,
          BetModuleType.putts);
    });

    test('Cercanía → Oyeses', () {
      mismoQueManual(BetCount.cercania, BetDivision.todaLaRonda,
          BetModuleType.oyeses);
    });

    test('Logros → Units', () {
      mismoQueManual(BetCount.logros, BetDivision.todaLaRonda,
          BetModuleType.units);
    });

    test('Puntos con la mejor y la peor bola → Bola Baja / Bola Alta', () {
      // El único conteo cuyo tipo depende de la bola.
      mismoQueManual(BetCount.puntos, BetDivision.frontBackTotal,
          BetModuleType.nassauLowHigh,
          bola: TeamBall.mejorYPeor, eq: true);
    });

    test('la mejor bola NO cambia el tipo: sigue siendo Nassau', () {
      mismoQueManual(BetCount.puntos, BetDivision.frontBackTotal,
          BetModuleType.nassau,
          bola: TeamBall.mejor, eq: true);
    });
  });

  group('lo que no se puede expresar se rechaza CON motivo', () {
    test('Puntos por toda la ronda: dejaría apuntes de \$0', () {
      // Sería un Nassau con Front y Back a cero, y _addNassauSegment no
      // comprueba si el valor es cero: emitiría dos asientos vacíos por
      // pareja. Arreglarlo es tocar el cálculo, así que no se ofrece.
      final res = _r(BetCount.puntos, BetDivision.todaLaRonda);
      expect(res.ok, isFalse);
      expect(res.rechazo, contains('\$0'));
    });

    test('solo Puntos liquida por Front·Back·Total', () {
      // El mockup ofrece esa división para Skins, Score total, Putts y Logros,
      // pero el motor no la liquida: solo nassau y bola baja/alta segmentan.
      for (final c in [BetCount.skins, BetCount.scoreTotal,
                       BetCount.putts, BetCount.logros, BetCount.cercania]) {
        final res = _r(c, BetDivision.frontBackTotal);
        expect(res.ok, isFalse, reason: '${c.label} no debería segmentar');
        expect(res.rechazo, isNotNull);
        expect(res.rechazo, isNotEmpty);
      }
    });

    test('los conteos sin motor de equipo se rechazan con lados', () {
      for (final c in [BetCount.scoreTotal, BetCount.putts,
                       BetCount.cercania, BetCount.logros]) {
        final res = _r(c, BetDivision.todaLaRonda, bola: TeamBall.mejor, eq: true);
        expect(res.ok, isFalse, reason: '${c.label} no tiene motor de equipo');
        expect(res.rechazo, isNotNull);
      }
    });

    test('la bola baja/alta exige equipos', () {
      final res = _r(BetCount.puntos, BetDivision.frontBackTotal,
          bola: TeamBall.mejorYPeor); // sin lados
      expect(res.ok, isFalse);
      expect(res.rechazo, contains('2 vs 2'));
    });

    test('un rechazo nunca trae módulo, y un módulo nunca trae rechazo', () {
      for (final c in BetCount.values) {
        for (final d in BetDivision.values) {
          final res = _r(c, d);
          expect(res.ok, res.rechazo == null, reason: '${c.label} · $d');
        }
      }
    });
  });

  group('el bote se ofrece donde el motor lo respeta', () {
    test('lo admiten los cuatro motores que leen formatMode', () {
      // Verificado en bet_engine: lo consumen _skins, _medal, _putts y
      // _oyeses. Ofrecerlo en otro sitio sería un control que no hace nada.
      expect(BetCount.skins.admiteBote, isTrue);
      expect(BetCount.scoreTotal.admiteBote, isTrue);
      expect(BetCount.putts.admiteBote, isTrue);
      expect(BetCount.cercania.admiteBote, isTrue);
    });

    test('Logros NO lo admite: _units no lee formatMode', () {
      expect(BetCount.logros.admiteBote, isFalse);
      expect(BetCount.logros.sinBote, isNotNull);
    });

    test('todo lo que niega el bote explica por qué', () {
      for (final c in BetCount.values) {
        if (c.admiteBote) {
          expect(c.sinBote, isNull, reason: '${c.label} admite bote y trae motivo');
        } else {
          expect(c.sinBote, isNotNull, reason: '${c.label} niega bote sin motivo');
        }
      }
    });
  });

  group('divisionesPara alimenta la UI', () {
    test('Puntos ofrece dos de tres, y explica la que no', () {
      final d = BetRecipe.divisionesPara(BetCount.puntos);
      expect(d[BetDivision.frontBackTotal], isNull);
      expect(d[BetDivision.soloNueve], isNull);
      expect(d[BetDivision.todaLaRonda], isNotNull);
    });

    test('Skins ofrece toda la ronda y una vuelta, no segmentos', () {
      final d = BetRecipe.divisionesPara(BetCount.skins);
      expect(d[BetDivision.todaLaRonda], isNull);
      expect(d[BetDivision.frontBackTotal], isNotNull);
    });

    test('cada conteo deja al menos una división disponible', () {
      // Un conteo sin ninguna sería inofrecible, y la UI lo mostraría vacío.
      for (final c in BetCount.values) {
        final d = BetRecipe.divisionesPara(c);
        expect(d.values.any((motivo) => motivo == null), isTrue,
            reason: '${c.label} no tiene ninguna división posible');
      }
    });
  });
}
