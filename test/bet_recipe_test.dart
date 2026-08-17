// ─────────────────────────────────────────────────────────────────────────────
// bet_recipe_test.dart — el flujo rápido produce lo mismo que el manual
//
// El traductor convierte (qué se cuenta × qué bola × cuántos hoyos) en un
// BetModuleInstance. La partición NO entra: se deriva. De las 36 celdas solo
// una admite dos caminos, así que preguntarla sería un paso con una única
// respuesta en 35 de 36 casos.
//
// Dos clases de "no" que conviene no confundir:
//   · rechazo      → el usuario eligió algo imposible (Putts por equipos)
//   · explicación  → el sistema resolvió un eje y dice por qué
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/bet_recipe.dart';

const pids = ['a', 'b', 'c', 'd'];
const lados = [
  BetSide(id: 'A', name: 'Equipo A', playerIds: ['a', 'b']),
  BetSide(id: 'B', name: 'Equipo B', playerIds: ['c', 'd']),
];

BetRecipeResult _r(BetCount c,
        {TeamBall? bola, bool eq = false, int hoyos = 18,
         BetDivision? preferida}) =>
    BetRecipe.build(
      cuenta: c, bola: bola,
      participantIds: pids,
      holesInRound: hoyos,
      sides: eq ? lados : null,
      preferida: preferida,
      id: 'fijo',
    );

void main() {
  group('produce el mismo módulo que el flujo manual', () {
    void mismoQueManual(BetCount c, BetModuleType esperado,
        {TeamBall? bola, bool eq = false, int hoyos = 18}) {
      final res = _r(c, bola: bola, eq: eq, hoyos: hoyos);
      expect(res.ok, isTrue, reason: '${c.label} rechazado: ${res.rechazo}');
      expect(res.module!.type, esperado);
      final manual = BetModuleInstance.defaultFor(esperado, pids,
          id: 'fijo', sides: eq ? lados : null);
      expect(res.module!.configSignature, manual.configSignature,
          reason: '${c.label} difiere del flujo manual');
    }

    test('Match → Nassau', () => mismoQueManual(BetCount.puntos, BetModuleType.nassau));
    test('Match a 9 hoyos → Nassau', () =>
        mismoQueManual(BetCount.puntos, BetModuleType.nassau, hoyos: 9));
    test('Skins → Skins', () => mismoQueManual(BetCount.skins, BetModuleType.skins));
    test('Score total → Medal', () =>
        mismoQueManual(BetCount.scoreTotal, BetModuleType.medal));
    test('Putts → Putts', () => mismoQueManual(BetCount.putts, BetModuleType.putts));
    test('Oyes → Oyeses', () => mismoQueManual(BetCount.oyes, BetModuleType.oyeses));
    test('Unidades → Units', () =>
        mismoQueManual(BetCount.unidades, BetModuleType.units));

    test('Puntos con bola baja y alta → Bola Baja / Bola Alta', () {
      mismoQueManual(BetCount.puntos, BetModuleType.nassauLowHigh,
          bola: TeamBall.mejorYPeor, eq: true);
    });

    test('la mejor bola NO cambia el tipo: sigue siendo Nassau', () {
      mismoQueManual(BetCount.puntos, BetModuleType.nassau,
          bola: TeamBall.mejor, eq: true);
    });
  });

  group('la partición se deriva, no se pregunta', () {
    test('solo UNA de las 36 celdas ofrece elección', () {
      // Barrido completo. Si alguien añade flags de segmento a otra config,
      // este test lo detecta en vez de dejarlo pasar en silencio.
      final conEleccion = <String>[];
      for (final h in [9, 18]) {
        for (final bola in [null, TeamBall.mejor, TeamBall.mejorYPeor]) {
          for (final c in BetCount.values) {
            final d = BetRecipe.divisionDe(c, bola: bola, holesInRound: h);
            if (d.hayEleccion) {
              conEleccion.add('$h·${bola?.name ?? "-"}·${c.labelCon(bola)}');
            }
          }
        }
      }
      expect(conEleccion, ['18·mejorYPeor·Puntos']);
    });

    test('cuando no hay elección siempre hay explicación, y viceversa', () {
      // Una celda sin elección y sin explicación dejaría al usuario sin saber
      // por qué no puede elegir. Una con las dos cosas mostraría un motivo
      // junto a una opción habilitada.
      for (final h in [9, 18]) {
        for (final bola in [null, TeamBall.mejor, TeamBall.mejorYPeor]) {
          for (final c in BetCount.values) {
            final d = BetRecipe.divisionDe(c, bola: bola, holesInRound: h);
            expect(d.explicacion == null, d.hayEleccion,
                reason: '${c.labelCon(bola)} · $h hoyos · bola $bola');
            if (!d.hayEleccion) expect(d.explicacion, isNotEmpty);
          }
        }
      }
    });

    test('la elegida siempre está entre las disponibles', () {
      for (final h in [9, 18]) {
        for (final bola in [null, TeamBall.mejor, TeamBall.mejorYPeor]) {
          for (final c in BetCount.values) {
            final d = BetRecipe.divisionDe(c, bola: bola, holesInRound: h);
            expect(d.disponibles, isNotEmpty);
            expect(d.disponibles, contains(d.elegida), reason: c.label);
          }
        }
      }
    });

    test('Match a 18 solo partido; a 9 solo entero', () {
      final a18 = BetRecipe.divisionDe(BetCount.puntos);
      expect(a18.elegida, BetDivision.frontBackTotal);
      expect(a18.explicacion, contains('\$0'));

      final a9 = BetRecipe.divisionDe(BetCount.puntos, holesInRound: 9);
      expect(a9.elegida, BetDivision.unaSolaApuesta);
      expect(a9.explicacion, contains('9 hoyos'));
    });

    test('los conteos que no segmentan van enteros y explican por qué', () {
      for (final c in [BetCount.skins, BetCount.scoreTotal,
                       BetCount.putts, BetCount.oyes, BetCount.unidades]) {
        final d = BetRecipe.divisionDe(c);
        expect(d.elegida, BetDivision.unaSolaApuesta, reason: c.label);
        expect(d.hayEleccion, isFalse);
        expect(d.explicacion, isNotEmpty);
      }
    });
  });

  group('la preferencia solo cuenta donde hay elección', () {
    test('se honra en la única celda que la admite', () {
      final d = BetRecipe.divisionDe(BetCount.puntos,
          bola: TeamBall.mejorYPeor,
          preferida: BetDivision.unaSolaApuesta);
      expect(d.elegida, BetDivision.unaSolaApuesta);
    });

    test('una preferencia imposible NO sobrevive al cambio de contexto', () {
      // El usuario elige "entera" con bola baja y alta, y luego cambia a la
      // mejor bola. Si la preferencia sobreviviera, se quedaría pedida una
      // partición que ya no existe.
      final d = BetRecipe.divisionDe(BetCount.puntos,
          bola: TeamBall.mejor,
          preferida: BetDivision.unaSolaApuesta);
      expect(d.elegida, BetDivision.frontBackTotal);
      expect(d.disponibles, [BetDivision.frontBackTotal]);
    });

    test('tampoco sobrevive al cambio de longitud', () {
      final d = BetRecipe.divisionDe(BetCount.puntos,
          bola: TeamBall.mejorYPeor, holesInRound: 9,
          preferida: BetDivision.frontBackTotal);
      expect(d.elegida, BetDivision.unaSolaApuesta);
    });
  });

  group('Bola Baja / Bola Alta es la única que sabe colapsar', () {
    test('entera deja solo el Total', () {
      final res = _r(BetCount.puntos, bola: TeamBall.mejorYPeor, eq: true,
          preferida: BetDivision.unaSolaApuesta);
      expect(res.ok, isTrue, reason: res.rechazo);
      final cfg = res.module!.lowHigh;
      expect(cfg.front9Enabled, isFalse);
      expect(cfg.back9Enabled, isFalse);
      expect(cfg.overallEnabled, isTrue);
    });

    test('partida conserva los tres segmentos', () {
      final res = _r(BetCount.puntos, bola: TeamBall.mejorYPeor, eq: true,
          preferida: BetDivision.frontBackTotal);
      expect(res.module!.lowHigh.front9Enabled, isTrue);
      expect(res.module!.lowHigh.back9Enabled, isTrue);
    });
  });

  group('los rechazos quedan para lo que el usuario SÍ puede elegir', () {
    test('los conteos sin motor de equipo se rechazan con lados', () {
      for (final c in [BetCount.scoreTotal, BetCount.putts,
                       BetCount.oyes, BetCount.unidades]) {
        final res = _r(c, bola: TeamBall.mejor, eq: true);
        expect(res.ok, isFalse, reason: '${c.label} no tiene motor de equipo');
        expect(res.rechazo, isNotEmpty);
      }
    });

    test('la bola baja/alta exige equipos', () {
      final res = _r(BetCount.puntos, bola: TeamBall.mejorYPeor);
      expect(res.ok, isFalse);
      expect(res.rechazo, contains('2 vs 2'));
    });

    test('un rechazo nunca trae módulo, y un módulo nunca trae rechazo', () {
      for (final c in BetCount.values) {
        for (final h in [9, 18]) {
          for (final eq in [true, false]) {
            final res = _r(c, hoyos: h, eq: eq,
                bola: eq ? TeamBall.mejor : null);
            expect(res.ok, res.rechazo == null, reason: '${c.label}·$h·$eq');
          }
        }
      }
    });

    test('individual nunca se rechaza: todo conteo se juega uno contra uno', () {
      for (final c in BetCount.values) {
        for (final h in [9, 18]) {
          expect(_r(c, hoyos: h).ok, isTrue,
              reason: '${c.label} a $h hoyos en individual');
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
        expect(c.labelCon(TeamBall.mejorYPeor), c.labelCon(null), reason: c.label);
      }
    });

    test('se usa el vocabulario del grupo, no el del modelo', () {
      expect(BetCount.oyes.label, 'Oyes');
      expect(BetCount.unidades.label, 'Unidades');
    });
  });

  group('el bote se ofrece donde el motor lo respeta', () {
    test('lo admiten los cuatro motores que leen formatMode', () {
      for (final c in [BetCount.skins, BetCount.scoreTotal,
                       BetCount.putts, BetCount.oyes]) {
        expect(c.admiteBote, isTrue, reason: c.label);
      }
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

  group('Oyes y Unidades son de grupo', () {
    test('y lo explican', () {
      for (final c in BetCount.values) {
        expect(c.soloDeGrupo != null, c.esDeGrupo, reason: c.label);
      }
      expect(BetCount.oyes.esDeGrupo, isTrue);
      expect(BetCount.unidades.esDeGrupo, isTrue);
      expect(BetCount.skins.esDeGrupo, isFalse);
    });
  });
}
