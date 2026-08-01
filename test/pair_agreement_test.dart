// Cubre PairAgreementEngine y el modelo PairAgreement.
//
// El escenario que motivó la función, en palabras del usuario: "puede ser que
// Oscar juegue una apuesta diferente conmigo que con Rafa". O sea que el acuerdo
// pertenece a la PAREJA, no a la persona — y eso es justo lo que se prueba aquí.
//
// Segundo requisito, que llegó después: los mismos jugadores pueden apostar
// distinto en el juego de los martes que en el de los viernes. Por eso el
// acuerdo vive dentro de un GamePreset y no en una colección global — ver el
// grupo "contexto: martes vs viernes" al final.
//
// Es lógica pura, sin Firestore: el engine no toca red.

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/pair_agreement_engine.dart';
import 'package:golf_bet_master/services/firestore_service.dart' show GamePreset;

// ── Helpers ───────────────────────────────────────────────────────────────────

BetModuleInstance _skins(double value, {String id = 'm'}) => BetModuleInstance(
      id: id,
      type: BetModuleType.skins,
      name: 'Skins',
      participantIds: const [],
      skinsConfig: SkinsConfig(valuePerSkin: value),
    );

BetModuleInstance _medal(double value, {String id = 'm'}) => BetModuleInstance(
      id: id,
      type: BetModuleType.medal,
      name: 'Medal',
      participantIds: const [],
      medalConfig: MedalConfig(value: value),
    );

PairAgreement _agreement(String p1, String p2, List<BetModuleInstance> t) =>
    PairAgreement.forPair(
      playerAId: p1,
      playerBId: p2,
      templates: t,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

/// Generador de ids determinista, para que los tests no dependan de Uuid.
String Function() _ids() {
  var n = 0;
  return () => 'gen${n++}';
}

void main() {
  // Los tres jugadores del ejemplo real. Los ids se eligen para que el orden
  // lexicográfico NO coincida con el orden de escritura, y así se verifique que
  // la clave canónica hace su trabajo.
  const yo = 'zz-yo';
  const rafa = 'aa-rafa';
  const oscar = 'mm-oscar';

  group('pairKey canónica', () {
    test('es simétrica: el orden de los argumentos no importa', () {
      expect(
        BetModuleInstance.pairKey(oscar, rafa),
        BetModuleInstance.pairKey(rafa, oscar),
      );
    });

    test('pairKeysAmong genera n(n-1)/2 parejas sin repetir', () {
      final keys = PairAgreementEngine.pairKeysAmong([yo, rafa, oscar]);
      expect(keys.length, 3);
      expect(keys.toSet().length, 3);
    });

    test('ignora ids vacíos y duplicados', () {
      final keys = PairAgreementEngine.pairKeysAmong([yo, '', rafa, yo]);
      expect(keys.length, 1);
      expect(keys.first, BetModuleInstance.pairKey(yo, rafa));
    });

    test('con menos de 2 jugadores no hay parejas', () {
      expect(PairAgreementEngine.pairKeysAmong([yo]), isEmpty);
      expect(PairAgreementEngine.pairKeysAmong([]), isEmpty);
    });
  });

  group('instantiate — el caso que motivó todo', () {
    test('Oscar juega distinto conmigo que con Rafa, y ambos se respetan', () {
      final agreements = {
        BetModuleInstance.pairKey(yo, oscar):
            _agreement(yo, oscar, [_medal(100)]),
        BetModuleInstance.pairKey(rafa, oscar):
            _agreement(rafa, oscar, [_skins(20)]),
      };

      final mods = PairAgreementEngine.instantiate(
        playerIds: [yo, rafa, oscar],
        agreements: agreements,
        newId: _ids(),
      );

      expect(mods.length, 2);

      final mine = mods.firstWhere((m) => m.containsPair(yo, oscar));
      final theirs = mods.firstWhere((m) => m.containsPair(rafa, oscar));

      // Mismo jugador (Oscar), dos acuerdos distintos.
      expect(mine.type, BetModuleType.medal);
      expect(mine.medal.value, 100);
      expect(theirs.type, BetModuleType.skins);
      expect(theirs.skins.valuePerSkin, 20);
    });

    test('cada módulo queda con alcance de duelo y sus dos participantes', () {
      final mods = PairAgreementEngine.instantiate(
        playerIds: [yo, rafa],
        agreements: {
          BetModuleInstance.pairKey(yo, rafa): _agreement(yo, rafa, [_skins(50)])
        },
        newId: _ids(),
      );

      expect(mods.single.participantIds.toSet(), {yo, rafa});
      expect(mods.single.scope?.kind, BetScopeKind.pair);
    });

    test('ids únicos por módulo — si se repitieran se pisarían en la ronda', () {
      final mods = PairAgreementEngine.instantiate(
        playerIds: [yo, rafa],
        agreements: {
          BetModuleInstance.pairKey(yo, rafa):
              _agreement(yo, rafa, [_skins(50), _medal(30)])
        },
        newId: _ids(),
      );
      expect(mods.map((m) => m.id).toSet().length, mods.length);
    });

    test('una pareja presente sin acuerdo no genera nada', () {
      final mods = PairAgreementEngine.instantiate(
        playerIds: [yo, rafa, oscar],
        agreements: {
          BetModuleInstance.pairKey(yo, rafa): _agreement(yo, rafa, [_skins(50)])
        },
        newId: _ids(),
      );
      // Solo la pareja con acuerdo; yo↔oscar y rafa↔oscar quedan libres.
      expect(mods.length, 1);
      expect(mods.single.containsPair(yo, rafa), isTrue);
    });

    test('un acuerdo de jugadores ausentes se ignora', () {
      final mods = PairAgreementEngine.instantiate(
        playerIds: [yo, rafa],
        agreements: {
          BetModuleInstance.pairKey(oscar, 'willy'):
              _agreement(oscar, 'willy', [_skins(20)])
        },
        newId: _ids(),
      );
      expect(mods, isEmpty);
    });

    test('acuerdo vacío no genera módulos', () {
      final mods = PairAgreementEngine.instantiate(
        playerIds: [yo, rafa],
        agreements: {
          BetModuleInstance.pairKey(yo, rafa): _agreement(yo, rafa, [])
        },
        newId: _ids(),
      );
      expect(mods, isEmpty);
    });
  });

  group('pairsWithoutAgreement', () {
    test('señala solo las parejas que hay que configurar a mano', () {
      final pending = PairAgreementEngine.pairsWithoutAgreement(
        playerIds: [yo, rafa, oscar],
        agreements: {
          BetModuleInstance.pairKey(yo, rafa): _agreement(yo, rafa, [_skins(50)])
        },
      );
      expect(pending.length, 2);
      expect(pending, isNot(contains(BetModuleInstance.pairKey(yo, rafa))));
    });
  });

  group('groupByPair', () {
    test('agrupa duelos por pareja', () {
      final mods = [
        _skins(50, id: 'a').copyForPair('a', yo, rafa),
        _medal(30, id: 'b').copyForPair('b', yo, rafa),
        _skins(20, id: 'c').copyForPair('c', yo, oscar),
      ];
      final grouped = PairAgreementEngine.groupByPair(mods);
      expect(grouped.length, 2);
      expect(grouped[BetModuleInstance.pairKey(yo, rafa)]!.length, 2);
      expect(grouped[BetModuleInstance.pairKey(yo, oscar)]!.length, 1);
    });

    test('excluye apuestas de grupo — no son el acuerdo de ninguna pareja', () {
      // Un skins de 3 jugadores no puede guardarse como acuerdo de pareja: al
      // reinstanciarlo se convertiría en 3 duelos y se cobraría de más.
      final grupal = BetModuleInstance(
        id: 'g',
        type: BetModuleType.skins,
        name: 'Skins',
        participantIds: const [yo, rafa, oscar],
        skinsConfig: const SkinsConfig(valuePerSkin: 20),
      );
      expect(PairAgreementEngine.groupByPair([grupal]), isEmpty);
    });
  });

  group('diff — estado de cada pareja', () {
    test('asAlways cuando la ronda coincide con el acuerdo', () {
      final saved = _skins(50);
      final diffs = PairAgreementEngine.diff(
        playerIds: [yo, rafa],
        modules: [saved.copyForPair('x', yo, rafa)],
        agreements: {
          BetModuleInstance.pairKey(yo, rafa): _agreement(yo, rafa, [saved])
        },
      );
      expect(diffs.single.status, PairStatus.asAlways);
      expect(diffs.single.worthSaving, isFalse);
    });

    test('changed cuando cambia el importe', () {
      final diffs = PairAgreementEngine.diff(
        playerIds: [yo, rafa],
        modules: [_skins(80).copyForPair('x', yo, rafa)],
        agreements: {
          BetModuleInstance.pairKey(yo, rafa): _agreement(yo, rafa, [_skins(50)])
        },
      );
      expect(diffs.single.status, PairStatus.changed);
      expect(diffs.single.worthSaving, isTrue);
    });

    test('changed cuando se añade una apuesta', () {
      final diffs = PairAgreementEngine.diff(
        playerIds: [yo, rafa],
        modules: [
          _skins(50).copyForPair('x', yo, rafa),
          _medal(30).copyForPair('y', yo, rafa),
        ],
        agreements: {
          BetModuleInstance.pairKey(yo, rafa): _agreement(yo, rafa, [_skins(50)])
        },
      );
      expect(diffs.single.status, PairStatus.changed);
    });

    test('unsaved cuando juegan pero no hay acuerdo guardado', () {
      final diffs = PairAgreementEngine.diff(
        playerIds: [yo, rafa],
        modules: [_skins(50).copyForPair('x', yo, rafa)],
        agreements: const {},
      );
      expect(diffs.single.status, PairStatus.unsaved);
      expect(diffs.single.worthSaving, isTrue);
    });

    test('notPlaying cuando hay acuerdo y hoy no apuestan', () {
      final diffs = PairAgreementEngine.diff(
        playerIds: [yo, rafa],
        modules: const [],
        agreements: {
          BetModuleInstance.pairKey(yo, rafa): _agreement(yo, rafa, [_skins(50)])
        },
      );
      expect(diffs.single.status, PairStatus.notPlaying);
      // No se ofrece guardar: borraría el acuerdo por no jugarlo un día.
      expect(diffs.single.worthSaving, isFalse);
    });

    test('el orden de las apuestas no cuenta como cambio', () {
      final diffs = PairAgreementEngine.diff(
        playerIds: [yo, rafa],
        modules: [
          _medal(30).copyForPair('y', yo, rafa),
          _skins(50).copyForPair('x', yo, rafa),
        ],
        agreements: {
          BetModuleInstance.pairKey(yo, rafa):
              _agreement(yo, rafa, [_skins(50), _medal(30)])
        },
      );
      expect(diffs.single.status, PairStatus.asAlways);
    });

    test('una pareja sin acuerdo y sin apuestas no aparece', () {
      final diffs = PairAgreementEngine.diff(
        playerIds: [yo, rafa, oscar],
        modules: [_skins(50).copyForPair('x', yo, rafa)],
        agreements: const {},
      );
      expect(diffs.length, 1);
      expect(diffs.single.pairKey, BetModuleInstance.pairKey(yo, rafa));
    });
  });

  group('PairAgreement — modelo', () {
    test('los ids quedan ordenados sin importar cómo se pasen', () {
      // oscar='mm-oscar' y rafa='aa-rafa' → rafa es el menor.
      final a = _agreement(oscar, rafa, [_skins(20)]);
      final b = _agreement(rafa, oscar, [_skins(20)]);
      expect(a.p1Id, rafa);
      expect(a.p2Id, oscar);
      expect(a.pairKey, b.pairKey);
    });

    test('isBetween reconoce el par en cualquier orden', () {
      final a = _agreement(yo, rafa, [_skins(20)]);
      expect(a.isBetween(yo, rafa), isTrue);
      expect(a.isBetween(rafa, yo), isTrue);
      expect(a.isBetween(yo, oscar), isFalse);
    });

    test('roundtrip Firestore conserva par y plantillas', () {
      final original = _agreement(yo, rafa, [_skins(50), _medal(30)]);
      final back =
          PairAgreement.fromFirestore(original.toFirestore(), original.pairKey)!;
      expect(back.pairKey, original.pairKey);
      expect(back.p1Id, original.p1Id);
      expect(back.p2Id, original.p2Id);
      expect(
        back.templates.map((t) => t.configSignature).toSet(),
        original.templates.map((t) => t.configSignature).toSet(),
      );
    });

    test('un doc sin los dos ids se descarta — no se puede aplicar a nada', () {
      expect(PairAgreement.fromFirestore({'templates': []}, 'k'), isNull);
      expect(PairAgreement.fromFirestore({'p1Id': yo}, 'k'), isNull);
      expect(
        PairAgreement.fromFirestore({'p1Id': yo, 'p2Id': yo}, 'k'),
        isNull,
      );
    });

    test('una plantilla ilegible se descarta sin perder el resto', () {
      final data = _agreement(yo, rafa, [_skins(50)]).toFirestore();
      // Firestore puede devolver cualquier cosa dentro de la lista; se simula
      // una entrada que no es un mapa junto a una válida.
      data['templates'] = <dynamic>[
        ...(data['templates'] as List),
        'esto no es un mapa',
      ];
      final back = PairAgreement.fromFirestore(data, 'k')!;
      expect(back.templates.length, 1);
      expect(back.templates.single.type, BetModuleType.skins);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // El acuerdo pertenece a un JUEGO, no solo a la pareja.
  // ══════════════════════════════════════════════════════════════════════════
  group('contexto: martes vs viernes', () {
    // Dos juegos con LOS MISMOS jugadores y apuestas distintas entre ellos.
    // Si el acuerdo viviera en una colección global por pareja, uno pisaría al
    // otro y no habría forma de tener ambos.
    GamePreset preset(String name, List<PairAgreement> agreements) => GamePreset(
          id: name,
          name: name,
          emoji: '⛳️',
          description: '',
          modulesJson: const [],
          pairAgreementsJson: agreements.map((a) => a.toFirestore()).toList(),
          updatedAt: DateTime(2026, 1, 1),
        );

    test('la misma pareja apuesta distinto en cada juego', () {
      final martes = preset('Martes', [_agreement(yo, oscar, [_skins(20)])]);
      final viernes = preset('Viernes', [_agreement(yo, oscar, [_medal(200)])]);

      final mMods = martes.toPairModules([yo, oscar], _ids());
      final vMods = viernes.toPairModules([yo, oscar], _ids());

      expect(mMods.single.type, BetModuleType.skins);
      expect(mMods.single.skins.valuePerSkin, 20);
      expect(vMods.single.type, BetModuleType.medal);
      expect(vMods.single.medal.value, 200);
    });

    test('cada juego resuelve varias parejas de forma independiente', () {
      // Martes: yo↔Oscar skins, Rafa↔Oscar medal.
      // Viernes: solo yo↔Rafa. Oscar no tiene acuerdo con nadie ese día.
      final martes = preset('Martes', [
        _agreement(yo, oscar, [_skins(20)]),
        _agreement(rafa, oscar, [_medal(50)]),
      ]);
      final viernes = preset('Viernes', [_agreement(yo, rafa, [_skins(100)])]);

      final mMods = martes.toPairModules([yo, rafa, oscar], _ids());
      final vMods = viernes.toPairModules([yo, rafa, oscar], _ids());

      expect(mMods.length, 2);
      expect(vMods.length, 1);
      expect(vMods.single.containsPair(yo, rafa), isTrue);
    });

    test('reglas de grupo y excepciones por pareja conviven', () {
      // modulesJson = lo que juega todo el grupo; los acuerdos son aparte.
      final grupal = _skins(20);
      final juego = GamePreset(
        id: 'g',
        name: 'Martes',
        emoji: '⛳️',
        description: '',
        modulesJson: [grupal.toJson()],
        pairAgreementsJson: [_agreement(yo, oscar, [_medal(200)]).toFirestore()],
        updatedAt: DateTime(2026, 1, 1),
      );

      final reglas = juego.toModules([yo, rafa, oscar]);
      final excepciones = juego.toPairModules([yo, rafa, oscar], _ids());

      // La regla cubre a los tres; la excepción solo al duelo.
      expect(reglas.single.participantIds.length, 3);
      expect(excepciones.single.participantIds.toSet(), {yo, oscar});
    });

    test('un preset viejo sin acuerdos se comporta como antes', () {
      // Retrocompatibilidad: los presets guardados antes de esta versión no
      // tienen el campo, y deben seguir aplicando solo sus reglas de grupo.
      final viejo = GamePreset(
        id: 'v',
        name: 'Antiguo',
        emoji: '⛳️',
        description: '',
        modulesJson: [_skins(20).toJson()],
        updatedAt: DateTime(2026, 1, 1),
      );
      expect(viejo.pairAgreementsJson, isEmpty);
      expect(viejo.pairAgreements, isEmpty);
      expect(viejo.toPairModules([yo, rafa], _ids()), isEmpty);
      expect(viejo.toModules([yo, rafa]).length, 1);
    });

    test('pairAgreements indexa por clave canónica y descarta lo ilegible', () {
      final juego = GamePreset(
        id: 'g',
        name: 'Martes',
        emoji: '⛳️',
        description: '',
        modulesJson: const [],
        pairAgreementsJson: [
          _agreement(yo, oscar, [_skins(20)]).toFirestore(),
          {'p1Id': yo}, // sin el segundo id → inaplicable, se descarta
          {'p1Id': rafa, 'p2Id': rafa, 'templates': []}, // par degenerado
        ],
        updatedAt: DateTime(2026, 1, 1),
      );
      expect(juego.pairAgreements.length, 1);
      expect(
        juego.pairAgreements.keys.single,
        BetModuleInstance.pairKey(yo, oscar),
      );
    });
  });
}
