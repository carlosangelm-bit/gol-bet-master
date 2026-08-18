// ─────────────────────────────────────────────────────────────────────────────
// nomina_de_hoy_test.dart — "a veces falta uno y va otro"
//
// La lista de un grupo son los HABITUALES, no los de hoy. Y las dos operaciones
// no son simétricas:
//
//   quitar   PairBetRule es por pareja concreta, así que las reglas del que no
//            viene desaparecen solas y los demás quedan igual.
//   añadir   quien no estaba NO tiene regla con nadie: entraría sin jugar nada,
//            que no es lo que se espera de "va otro en su lugar".
//
// La forma que admite un invitado gratis ya existe en el modelo, en GamePreset:
// modulesJson SIN participantIds —la regla de todos— más pairAgreementsJson de
// excepciones. Un grupo no tiene esa separación, así que se DERIVA comparando
// las plantillas de todos los cruces.
//
// Y si no coinciden NO se adivina: elegir por mayoría le inventaría al invitado
// un acuerdo que nadie pactó.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';

const cam = 'cam', rafa = 'rafa', cav = 'cav', kawa = 'kawa';

BetModuleTemplate _nassau(double v) => BetModuleTemplate(
      type: BetModuleType.nassau,
      nassauConfig: NassauConfig.def
          .copyWith(frontValue: v, backValue: v, totalValue: v * 2),
    );

BetModuleTemplate _skins(double v) => BetModuleTemplate(
      type: BetModuleType.skins,
      skinsConfig: SkinsConfig.def.copyWith(valuePerSkin: v),
    );

PairBetRule _regla(String a, String b, List<BetModuleTemplate> m) =>
    PairBetRule(id: '$a-$b', playerAId: a, playerBId: b, modules: m);

/// Grupo uniforme: los tres cruces juegan el mismo Nassau.
BettingGroup _uniforme() => BettingGroup(
      id: 'g', name: 'Viernes', emoji: '🏌',
      playerIds: const [cam, rafa, cav],
      pairRules: [
        _regla(cam, rafa, [_nassau(50)]),
        _regla(cam, cav, [_nassau(50)]),
        _regla(rafa, cav, [_nassau(50)]),
      ],
      updatedAt: DateTime(2026, 1, 1),
    );

/// Grupo desigual: un cruce juega otra cosa.
BettingGroup _desigual() => BettingGroup(
      id: 'g', name: 'Viernes', emoji: '🏌',
      playerIds: const [cam, rafa, cav],
      pairRules: [
        _regla(cam, rafa, [_nassau(50)]),
        _regla(cam, cav, [_nassau(50)]),
        _regla(rafa, cav, [_skins(200)]),
      ],
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  group('el grupo guardado NO se modifica', () {
    // El punto que más fácil se rompe: reutilizar pairRules para la sesión de
    // hoy haría que jugar sin uno lo borrara del grupo para siempre.
    test('jugar sin uno no lo saca del grupo', () {
      final g = _uniforme();
      final antes = g.playerIds.length;
      final antesReglas = g.pairRules.length;

      g.rulesForToday(const [cam, rafa]); // hoy falta CAV

      expect(g.playerIds.length, antes);
      expect(g.pairRules.length, antesReglas);
      expect(g.playerIds, contains(cav));
    });

    test('añadir a alguien no lo mete en el grupo', () {
      final g = _uniforme();
      g.rulesForToday(const [cam, rafa, cav, kawa]);
      expect(g.playerIds, isNot(contains(kawa)));
      expect(g.pairRules.length, 3);
    });

    test('la lista de hoy es una COPIA, no la del grupo', () {
      final g = _uniforme();
      final hoy = g.rulesForToday(const [cam, rafa, cav]);
      expect(hoy, isNot(same(g.pairRules)));
    });
  });

  group('quitar es limpio', () {
    test('las reglas del que falta desaparecen', () {
      final hoy = _uniforme().rulesForToday(const [cam, rafa]);
      expect(hoy.length, 1);
      expect({hoy.single.playerAId, hoy.single.playerBId}, {cam, rafa});
    });

    test('y los demás quedan igual', () {
      final hoy = _uniforme().rulesForToday(const [cam, rafa]);
      expect(hoy.single.modules.single.type, BetModuleType.nassau);
      expect(hoy.single.modules.single.nassauConfig!.frontValue, 50);
    });

    test('tres presentes dan tres cruces; dos dan uno', () {
      expect(_uniforme().rulesForToday(const [cam, rafa, cav]).length, 3);
      expect(_uniforme().rulesForToday(const [cam, rafa]).length, 1);
    });
  });

  group('añadir: el patrón se DERIVA, no se adivina', () {
    test('un grupo uniforme tiene patrón', () {
      final p = _uniforme().patron;
      expect(p.uniforme, isTrue);
      expect(p.modules.single.type, BetModuleType.nassau);
      expect(p.motivo, isNull);
    });

    test('el invitado juega el patrón contra TODOS los presentes', () {
      // Es lo que se espera de "va otro": que juegue, no que entre de mirón.
      final hoy = _uniforme().rulesForToday(const [cam, rafa, cav, kawa]);
      expect(hoy.length, 6, reason: 'los 6 cruces de cuatro jugadores');
      final delInvitado =
          hoy.where((r) => r.playerAId == kawa || r.playerBId == kawa);
      expect(delInvitado.length, 3);
      for (final r in delInvitado) {
        expect(r.modules.single.nassauConfig!.frontValue, 50, reason: r.id);
      }
    });

    test('un grupo desigual NO tiene patrón, y lo explica', () {
      final p = _desigual().patron;
      expect(p.uniforme, isFalse);
      expect(p.modules, isEmpty);
      expect(p.motivo, contains('no juegan todos lo mismo'));
    });

    test('y entonces el invitado entra sin apuestas en vez de con una inventada', () {
      // Elegir por mayoría le daría el Nassau, que dos cruces juegan y uno no.
      // Eso es inventarle un acuerdo que nadie pactó.
      final hoy = _desigual().rulesForToday(const [cam, rafa, cav, kawa]);
      expect(hoy.any((r) => r.playerAId == kawa || r.playerBId == kawa),
          isFalse);
      // Los habituales siguen jugando lo suyo.
      expect(hoy.length, 3);
    });

    test('sustituir es quitar y añadir: el invitado hereda el patrón', () {
      // No hereda las reglas del ausente: quitar a uno y añadir a otro es
      // indistinguible de que el grupo crezca y encoja a la vez, así que no se
      // puede inferir a quién sustituye.
      final hoy = _uniforme().rulesForToday(const [cam, rafa, kawa]);
      expect(hoy.length, 3);
      expect(hoy.any((r) => r.playerAId == cav || r.playerBId == cav), isFalse);
      expect(hoy.where((r) => r.playerAId == kawa || r.playerBId == kawa).length,
          2);
    });
  });

  group('los módulos de hoy', () {
    test('salen de la lista de hoy, no de la del grupo', () {
      final mods = _uniforme().toBetModuleInstancesForToday(
        presentes: const [cam, rafa, kawa],
        betGroupId: 'bg', betGroupName: 'Viernes',
      );
      expect(mods.length, 3);
      final ids = mods.expand((m) => m.participantIds).toSet();
      expect(ids, {cam, rafa, kawa});
      expect(ids, isNot(contains(cav)));
    });

    test('cada módulo con su propio id', () {
      final mods = _uniforme().toBetModuleInstancesForToday(
        presentes: const [cam, rafa, cav],
        betGroupId: 'bg', betGroupName: 'Viernes',
      );
      expect(mods.map((m) => m.id).toSet().length, mods.length);
    });

    test('sin nadie presente no hay módulos', () {
      expect(
          _uniforme().toBetModuleInstancesForToday(
            presentes: const [], betGroupId: 'bg', betGroupName: 'V',
          ),
          isEmpty);
    });
  });
}
