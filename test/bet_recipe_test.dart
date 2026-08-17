// ─────────────────────────────────────────────────────────────────────────────
// bet_recipe_test.dart — el flujo rápido produce lo mismo que el manual
//
// El traductor convierte (qué se cuenta × si se parte × qué bola) en un
// BetModuleInstance. Si produjera algo distinto de lo que crea el flujo manual,
// dos usuarios que configuran la misma apuesta por caminos distintos jugarían
// apuestas distintas sin saberlo.
//
// La longitud de la ronda NO es un eje: es un dato del paso Campo. Pero cambia
// qué particiones existen, y esa dependencia es la que más tests lleva porque
// es la que se modeló mal la primera vez.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/bet_recipe.dart';

const pids = ['a', 'b', 'c', 'd'];
const lados = [
  BetSide(id: 'A', name: 'Equipo A', playerIds: ['a', 'b']),
  BetSide(id: 'B', name: 'Equipo B', playerIds: ['c', 'd']),
];

BetRecipeResult _r(BetCount c, BetDivision d,
        {TeamBall? bola, bool eq = false, int hoyos = 18}) =>
    BetRecipe.build(
      cuenta: c, division: d, bola: bola,
      participantIds: pids,
      holesInRound: hoyos,
      sides: eq ? lados : null,
      id: 'fijo',
    );

void main() {
  group('produce el mismo módulo que el flujo manual', () {
    void mismoQueManual(BetCount c, BetDivision d, BetModuleType esperado,
        {TeamBall? bola, bool eq = false, int hoyos = 18}) {
      final res = _r(c, d, bola: bola, eq: eq, hoyos: hoyos);
      expect(res.ok, isTrue,
          reason: '${c.label} · $d fue rechazado: ${res.rechazo}');
      expect(res.module!.type, esperado);
      final manual = BetModuleInstance.defaultFor(esperado, pids,
          id: 'fijo', sides: eq ? lados : null);
      expect(res.module!.configSignature, manual.configSignature,
          reason: '${c.label} · $d difiere del flujo manual');
    }

    test('Match · Front·Back·Total → Nassau', () {
      mismoQueManual(BetCount.puntos, BetDivision.frontBackTotal,
          BetModuleType.nassau);
    });

    test('Match · una sola apuesta en 9 hoyos → Nassau', () {
      // _nassauPair ya colapsa a un solo asiento cuando segmentsOf marca
      // singleNine: no hay nada que desactivar y no sobra ninguna config.
      mismoQueManual(BetCount.puntos, BetDivision.unaSolaApuesta,
          BetModuleType.nassau, hoyos: 9);
    });

    test('Skins → Skins', () {
      mismoQueManual(BetCount.skins, BetDivision.unaSolaApuesta,
          BetModuleType.skins);
    });

    test('Score total → Medal', () {
      mismoQueManual(BetCount.scoreTotal, BetDivision.unaSolaApuesta,
          BetModuleType.medal);
    });

    test('Putts → Putts', () {
      mismoQueManual(BetCount.putts, BetDivision.unaSolaApuesta,
          BetModuleType.putts);
    });

    test('Oyes → Oyeses', () {
      mismoQueManual(BetCount.oyes, BetDivision.unaSolaApuesta,
          BetModuleType.oyeses);
    });

    test('Unidades → Units', () {
      mismoQueManual(BetCount.unidades, BetDivision.unaSolaApuesta,
          BetModuleType.units);
    });

    test('Puntos con la mejor y la peor bola → Bola Baja / Bola Alta', () {
      mismoQueManual(BetCount.puntos, BetDivision.frontBackTotal,
          BetModuleType.nassauLowHigh,
          bola: TeamBall.mejorYPeor, eq: true);
    });

    test('la mejor bola NO cambia el tipo: sigue siendo Nassau', () {
      mismoQueManual(BetCount.puntos, BetDivision.frontBackTotal,
          BetModuleType.nassau, bola: TeamBall.mejor, eq: true);
    });
  });

  group('la longitud de la ronda no es un eje, pero manda', () {
    test('Front·Back·Total no existe en una ronda de 9 hoyos', () {
      final res = _r(BetCount.puntos, BetDivision.frontBackTotal, hoyos: 9);
      expect(res.ok, isFalse);
      expect(res.rechazo, contains('9 hoyos'));
    });

    test('Match a los 18 sin partir se rechaza: dejaría apuntes de \$0', () {
      // Sería un Nassau con Front y Back a cero, y _addNassauSegment no
      // comprueba si el valor es cero.
      final res = _r(BetCount.puntos, BetDivision.unaSolaApuesta, hoyos: 18);
      expect(res.ok, isFalse);
      expect(res.rechazo, contains('\$0'));
    });

    test('el mismo Match a los 9 sí se puede', () {
      // La misma combinación de ejes, distinta longitud de ronda. Si el
      // rechazo dependiera del eje y no del dato, este test fallaría.
      expect(_r(BetCount.puntos, BetDivision.unaSolaApuesta, hoyos: 9).ok,
          isTrue);
    });

    test('los conteos que no segmentan no dependen de la longitud', () {
      for (final c in [BetCount.skins, BetCount.scoreTotal,
                       BetCount.putts, BetCount.oyes, BetCount.unidades]) {
        for (final h in [9, 18]) {
          expect(_r(c, BetDivision.unaSolaApuesta, hoyos: h).ok, isTrue,
              reason: '${c.label} en $h hoyos');
        }
      }
    });
  });

  group('Bola Baja / Bola Alta sí sabe colapsar', () {
    test('una sola apuesta a los 18 deja solo el Total', () {
      // La asimetría con Nassau es del modelo: NassauLowHighConfig tiene
      // front9Enabled / back9Enabled / overallEnabled, y NassauConfig no.
      final res = _r(BetCount.puntos, BetDivision.unaSolaApuesta,
          bola: TeamBall.mejorYPeor, eq: true);
      expect(res.ok, isTrue, reason: res.rechazo);
      final cfg = res.module!.lowHigh;
      expect(cfg.front9Enabled, isFalse);
      expect(cfg.back9Enabled, isFalse);
      expect(cfg.overallEnabled, isTrue);
    });

    test('partido en tres conserva los tres segmentos', () {
      final res = _r(BetCount.puntos, BetDivision.frontBackTotal,
          bola: TeamBall.mejorYPeor, eq: true);
      expect(res.ok, isTrue);
      expect(res.module!.lowHigh.front9Enabled, isTrue);
      expect(res.module!.lowHigh.back9Enabled, isTrue);
    });
  });

  group('lo que no se puede expresar se rechaza CON motivo', () {
    test('solo Puntos se parte en Front·Back·Total', () {
      // El motor solo segmenta en nassau y bola baja/alta. Ofrecerlo en Skins
      // o Putts sería jugar una apuesta distinta de la pedida.
      for (final c in [BetCount.skins, BetCount.scoreTotal,
                       BetCount.putts, BetCount.unidades, BetCount.oyes]) {
        final res = _r(c, BetDivision.frontBackTotal);
        expect(res.ok, isFalse, reason: '${c.label} no debería partirse');
        expect(res.rechazo, isNotEmpty);
      }
    });

    test('los conteos sin motor de equipo se rechazan con lados', () {
      for (final c in [BetCount.scoreTotal, BetCount.putts,
                       BetCount.oyes, BetCount.unidades]) {
        final res = _r(c, BetDivision.unaSolaApuesta,
            bola: TeamBall.mejor, eq: true);
        expect(res.ok, isFalse, reason: '${c.label} no tiene motor de equipo');
        expect(res.rechazo, isNotNull);
      }
    });

    test('la bola baja/alta exige equipos', () {
      final res = _r(BetCount.puntos, BetDivision.frontBackTotal,
          bola: TeamBall.mejorYPeor);
      expect(res.ok, isFalse);
      expect(res.rechazo, contains('2 vs 2'));
    });

    test('un rechazo nunca trae módulo, y un módulo nunca trae rechazo', () {
      for (final c in BetCount.values) {
        for (final d in BetDivision.values) {
          for (final h in [9, 18]) {
            final res = _r(c, d, hoyos: h);
            expect(res.ok, res.rechazo == null, reason: '${c.label} · $d · $h');
          }
        }
      }
    });
  });

  group('el nombre se deriva de la bola, no se elige', () {
    test('un punto por hoyo es Match; dos son Puntos', () {
      expect(BetCount.puntos.labelCon(null), 'Match');
      expect(BetCount.puntos.labelCon(TeamBall.mejor), 'Match');
      expect(BetCount.puntos.labelCon(TeamBall.unaSola), 'Match');
      expect(BetCount.puntos.labelCon(TeamBall.mejorYPeor), 'Puntos');
    });

    test('la bola dice cuántos puntos reparte el hoyo', () {
      expect(TeamBall.mejorYPeor.puntosPorHoyo, 2);
      expect(TeamBall.mejor.puntosPorHoyo, 1);
      expect((null as TeamBall?).puntosPorHoyo, 1);
    });

    test('los demás conteos no cambian de nombre con la bola', () {
      for (final c in BetCount.values) {
        if (c == BetCount.puntos) continue;
        expect(c.labelCon(TeamBall.mejorYPeor), c.labelCon(null),
            reason: '${c.label} cambió de nombre con la bola');
      }
    });

    test('se usa el vocabulario del grupo, no el del modelo', () {
      expect(BetCount.oyes.label, 'Oyes');
      expect(BetCount.unidades.label, 'Unidades');
    });
  });

  group('el bote se ofrece donde el motor lo respeta', () {
    test('lo admiten los cuatro motores que leen formatMode', () {
      expect(BetCount.skins.admiteBote, isTrue);
      expect(BetCount.scoreTotal.admiteBote, isTrue);
      expect(BetCount.putts.admiteBote, isTrue);
      expect(BetCount.oyes.admiteBote, isTrue);
    });

    test('Unidades NO lo admite: _units no lee formatMode', () {
      expect(BetCount.unidades.admiteBote, isFalse);
      expect(BetCount.unidades.sinBote, isNotNull);
    });

    test('todo lo que niega el bote explica por qué', () {
      for (final c in BetCount.values) {
        expect(c.sinBote == null, c.admiteBote, reason: c.label);
      }
    });
  });

  group('lo que alimenta la UI', () {
    test('hoy solo Bola Baja / Bola Alta admite más de una división', () {
      // Barrido de TODO el espacio: 6 conteos × 3 bolas × 2 longitudes. Solo
      // una celda deja dos divisiones abiertas, y es la única config con
      // interruptores de segmento —NassauLowHighConfig—.
      //
      // Consecuencia para el flujo: el paso "¿se parte en varias apuestas?"
      // solo tiene sentido con bola baja y alta. En cualquier otro caso hay
      // una única respuesta posible y preguntarla sería ruido.
      final conVarias = <String>[];
      for (final h in [9, 18]) {
        for (final bola in [null, TeamBall.mejor, TeamBall.mejorYPeor]) {
          for (final c in BetCount.values) {
            if (BetRecipe.admiteParticion(c, bola: bola, holesInRound: h)) {
              conVarias.add('$h·${bola?.name ?? "-"}·${c.labelCon(bola)}');
            }
          }
        }
      }
      expect(conVarias, ['18·mejorYPeor·Puntos']);
    });

    test('Match a 18 solo puede ir partido en tres', () {
      // No es que no admita partición: es que la única división posible ES la
      // partida. Un match único a los 18 no se puede expresar.
      final d = BetRecipe.divisionesPara(BetCount.puntos);
      expect(d[BetDivision.frontBackTotal], isNull);
      expect(d[BetDivision.unaSolaApuesta], isNotNull);
      expect(BetRecipe.admiteParticion(BetCount.puntos), isFalse);
    });

    test('Match a 9 solo puede ir entero', () {
      final d = BetRecipe.divisionesPara(BetCount.puntos, holesInRound: 9);
      expect(d[BetDivision.unaSolaApuesta], isNull);
      expect(d[BetDivision.frontBackTotal], isNotNull);
    });

    test('cada conteo deja al menos una división disponible', () {
      // Un conteo sin ninguna sería inofrecible, y la UI lo mostraría vacío.
      for (final c in BetCount.values) {
        for (final h in [9, 18]) {
          final d = BetRecipe.divisionesPara(c, holesInRound: h);
          expect(d.values.any((m) => m == null), isTrue,
              reason: '${c.label} en $h hoyos no tiene ninguna división');
        }
      }
    });

    test('Oyes y Unidades son de grupo y lo explican', () {
      for (final c in BetCount.values) {
        expect(c.soloDeGrupo != null, c.esDeGrupo, reason: c.label);
      }
      expect(BetCount.oyes.esDeGrupo, isTrue);
      expect(BetCount.unidades.esDeGrupo, isTrue);
      expect(BetCount.skins.esDeGrupo, isFalse);
    });
  });
}
