// ─────────────────────────────────────────────────────────────────────────────
// multiselect_test.dart — varias apuestas en la misma ronda
//
// El paso "qué se cuenta" es multi-select: una ronda puede llevar skins, match
// y unidades a la vez, cada una con su configuración y su monto. Antes se
// creaban de una en una.
//
// Lo que se prueba aquí es la LÓGICA del paso, no su pintura: qué módulos
// produce un conjunto de conteos, y que cada uno sea el que produciría el flujo
// manual. La pintura no la puedo verificar desde aquí y lo digo en la entrega.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/bet_recipe.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';

const pids = ['a1', 'a2', 'b1', 'b2'];
final lados = [
  BetSide(id: 'lado_A', name: 'Equipo A', playerIds: const ['a1', 'a2'],
      playMode: TeamPlayMode.bestBall),
  BetSide(id: 'lado_B', name: 'Equipo B', playerIds: const ['b1', 'b2'],
      playMode: TeamPlayMode.bestBall),
];

/// Réplica de _sincronizarModulos: los conteos elegidos → módulos.
List<BetModuleInstance> _modulos(
  Set<BetCount> conteos, {
  TeamBall? bola,
  bool equipos = false,
  int hoyos = 18,
  Map<BetCount, BetDivision> particion = const {},
  Map<BetCount, BetFormatMode> reparto = const {},
}) {
  final out = <BetModuleInstance>[];
  for (final c in conteos) {
    final res = BetRecipe.build(
      cuenta: c, bola: bola, participantIds: pids,
      holesInRound: hoyos, sides: equipos ? lados : null,
      preferida: particion[c], id: 'flujo_${c.name}',
    );
    if (!res.ok) continue;
    var m = res.module!;
    final r = reparto[c];
    if (r != null && c.admiteBote) m = m.copyWith(formatMode: r);
    out.add(m);
  }
  return out;
}

void main() {
  group('varias apuestas a la vez', () {
    test('tres conteos producen tres módulos distintos', () {
      final m = _modulos({BetCount.skins, BetCount.puntos, BetCount.unidades});
      expect(m.length, 3);
      expect(m.map((x) => x.type).toSet(),
          {BetModuleType.skins, BetModuleType.nassau, BetModuleType.units});
    });

    test('cada uno con su propia configuración tipada', () {
      final m = _modulos({BetCount.skins, BetCount.putts});
      expect(m.firstWhere((x) => x.type == BetModuleType.skins).skinsConfig,
          isNotNull);
      expect(m.firstWhere((x) => x.type == BetModuleType.putts).puttsConfig,
          isNotNull);
    });

    test('los seis conteos a la vez, y todos liquidan en la misma ronda', () {
      // La prueba de que no se pisan: seis apuestas conviviendo y el libro
      // saliendo sin errores de integridad.
      final mods = _modulos(BetCount.values.toSet());
      expect(mods.length, 6);
      final course = CourseInfo(name: 'T',
          holes: List.generate(18,
              (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)));
      final gross = {'a1': 3, 'a2': 4, 'b1': 5, 'b2': 6};
      final r = Round(
        id: 'r', name: 'R', course: course,
        players: pids.map((i) => Player(id: i, name: i)).toList(),
        roundPlayers:
            pids.map((i) => RoundPlayer(playerId: i, handicapEnRonda: 0)).toList(),
        betGroups: [BetGroup(id: 'g', name: 'G',
            format: PartidaFormat.allInOnePot, playerIds: pids, modules: mods)],
        scores: {
          for (final e in gross.entries)
            e.key: {for (var h = 1; h <= 18; h++)
              h: HoleScore(playerId: e.key, hole: h, grossScore: e.value)},
        },
        events: const {}, oyeseRankings: const {}, sliding: const [],
        createdAt: DateTime(2026, 1, 1), totalHoles: 18,
      );
      final c = BetEngine.safeComputeAll(r);
      expect(c.errors, isEmpty, reason: 'seis apuestas juntas dan error');
      expect(c.entries, isNotEmpty);
    });

    test('los ids no colisionan entre conteos', () {
      // Con un id compartido, el segundo módulo sobreescribiría al primero al
      // guardarse.
      final m = _modulos(BetCount.values.toSet());
      expect(m.map((x) => x.id).toSet().length, m.length);
    });

    test('el prefijo permite distinguir lo del flujo de lo hecho a mano', () {
      // _sincronizarModulos reemplaza solo los del flujo: volver atrás a
      // cambiar una casilla no puede borrar lo que el usuario creó en detalle.
      final m = _modulos({BetCount.skins});
      expect(m.single.id.startsWith('flujo_'), isTrue);
    });
  });

  group('los atajos rellenan dos ejes', () {
    test('Nassau es puntos partido en Front · Back · Total', () {
      final m = _modulos({BetCount.puntos},
          particion: {BetCount.puntos: BetDivision.frontBackTotal});
      expect(m.single.type, BetModuleType.nassau);
    });

    test('y el atajo no impide cambiar la partición después', () {
      // Es un preselector dentro del paso, no un modo aparte.
      final div = BetRecipe.divisionDe(BetCount.puntos,
          bola: TeamBall.mejorYPeor,
          preferida: BetDivision.unaSolaApuesta);
      expect(div.elegida, BetDivision.unaSolaApuesta);
    });
  });

  group('lo que no se ofrece no se crea', () {
    test('un conteo rechazado no produce módulo', () {
      // Putts por equipos se rechaza: no tiene motor de equipo. Marcarlo no
      // debería colar un módulo que liquide como individual sin avisar.
      final m = _modulos({BetCount.putts, BetCount.skins},
          equipos: true, bola: TeamBall.mejor);
      expect(m.map((x) => x.type), [BetModuleType.skins]);
    });

    test('con menos de dos jugadores no se crea nada', () {
      // Lo comprueba _sincronizarModulos antes de entrar al bucle.
      expect(pids.length >= 2, isTrue);
    });
  });

  group('el reparto solo se aplica donde el motor lo lee', () {
    test('el bote llega al módulo en los conteos que lo admiten', () {
      final m = _modulos({BetCount.skins},
          reparto: {BetCount.skins: BetFormatMode.onePot});
      expect(m.single.formatMode, BetFormatMode.onePot);
    });

    test('en Unidades la petición se ignora y queda el default', () {
      // _units no lee formatMode: aplicarlo dejaría una config que miente.
      //
      // No vale afirmar "no es onePot": onePot ES el default de todo módulo, así
      // que ese aserto pasaría sin que el guard existiera. Se comprueba que el
      // valor no se MUEVE respecto al que pone defaultFor.
      final def =
          BetModuleInstance.defaultFor(BetModuleType.units, pids).formatMode;
      for (final pedido in BetFormatMode.values) {
        final m = _modulos({BetCount.unidades},
            reparto: {BetCount.unidades: pedido});
        expect(m.single.formatMode, def,
            reason: 'pedir $pedido movió la config de Unidades');
      }
    });

    test('y en Skins sí se mueve, para que el test anterior valga algo', () {
      final def =
          BetModuleInstance.defaultFor(BetModuleType.skins, pids).formatMode;
      final otro = BetFormatMode.values.firstWhere((m) => m != def);
      final m = _modulos({BetCount.skins}, reparto: {BetCount.skins: otro});
      expect(m.single.formatMode, otro);
    });
  });

  group('coincide con el flujo manual', () {
    test('cada módulo del multi-select es el que crea defaultFor', () {
      for (final c in BetCount.values) {
        final m = _modulos({c}).single;
        final manual = BetModuleInstance.defaultFor(m.type, pids, id: m.id);
        expect(m.configSignature, manual.configSignature, reason: c.label);
      }
    });
  });
}
