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

      final mMods = martes.apply([yo, oscar], _ids()).modules;
      final vMods = viernes.apply([yo, oscar], _ids()).modules;

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

      final mMods = martes.apply([yo, rafa, oscar], _ids()).modules;
      final vMods = viernes.apply([yo, rafa, oscar], _ids()).modules;

      expect(mMods.length, 2);
      expect(vMods.length, 1);
      expect(vMods.single.containsPair(yo, rafa), isTrue);
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
      expect(viejo.toModules([yo, rafa]).length, 1);

      final app = viejo.apply([yo, rafa], _ids());
      expect(app.modules.length, 1);
      expect(app.modules.single.participantIds.length, 2);
      expect(app.hasConflicts, isFalse);
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

  // ══════════════════════════════════════════════════════════════════════════
  // Reconciliar regla + excepción. Aquí es donde un fallo cobra dinero de más.
  // ══════════════════════════════════════════════════════════════════════════
  group('resolve — reglas contra excepciones', () {
    PresetApplication run({
      required List<BetModuleInstance> reglas,
      required List<PairAgreement> acuerdos,
      List<String> players = const [yo, rafa, oscar],
    }) =>
        PairAgreementEngine.resolve(
          groupRules: reglas,
          agreements: {for (final a in acuerdos) a.pairKey: a},
          playerIds: players,
          newId: _ids(),
        );

    test('excepción de otro tipo se añade como duelo propio', () {
      // Todos juegan skins; además yo↔Oscar juegan medal. Sin colisión.
      final app = run(reglas: [_skins(20)], acuerdos: [
        _agreement(yo, oscar, [_medal(200)])
      ]);
      expect(app.hasConflicts, isFalse);
      expect(app.modules.length, 2);
      final duelo = app.modules.firstWhere((m) => m.type == BetModuleType.medal);
      expect(duelo.participantIds.toSet(), {yo, oscar});
      expect(duelo.scope?.kind, BetScopeKind.pair);
    });

    test('CLAVE: excepción del mismo tipo NO duplica la apuesta', () {
      // Todos skins $20, pero yo↔Oscar a $50. Si se emitieran los dos módulos,
      // esa pareja tendría DOS skins y se le cobraría doble.
      final app = run(reglas: [_skins(20)], acuerdos: [
        _agreement(yo, oscar, [_skins(50)])
      ]);

      expect(app.hasConflicts, isFalse);
      // Un solo módulo de skins, no dos.
      expect(app.modules.where((m) => m.type == BetModuleType.skins).length, 1);

      final regla = app.modules.single;
      // El importe distinto viaja como override de esa pareja.
      expect(regla.overrideForPair(yo, oscar), 50);
      // Y las demás parejas siguen con el valor base.
      expect(regla.overrideForPair(yo, rafa), isNull);
      expect(regla.effectiveValueForDuel(yo, rafa).$1, 20);
      expect(regla.effectiveValueForDuel(yo, oscar).$1, 50);
    });

    test('acuerdo idéntico a la regla no añade nada', () {
      final app = run(reglas: [_skins(20)], acuerdos: [
        _agreement(yo, oscar, [_skins(20)])
      ]);
      expect(app.modules.length, 1);
      expect(app.modules.single.pairConfigOverrides ?? {}, isEmpty);
      expect(app.hasConflicts, isFalse);
    });

    test('varias parejas con importes distintos, todas como override', () {
      final app = run(reglas: [_skins(20)], acuerdos: [
        _agreement(yo, oscar, [_skins(50)]),
        _agreement(yo, rafa, [_skins(80)]),
      ]);
      expect(app.modules.length, 1);
      expect(app.modules.single.overrideForPair(yo, oscar), 50);
      expect(app.modules.single.overrideForPair(yo, rafa), 80);
      expect(app.hasConflicts, isFalse);
    });

    test('CONFLICTO: Nassau no admite importe por duelo', () {
      // Nassau tiene front/back/total: un override solo lleva un monto, así
      // que no puede representar "este duelo juega Nassau distinto".
      final nassau = BetModuleInstance(
        id: 'n',
        type: BetModuleType.nassau,
        name: 'Nassau',
        participantIds: const [],
        nassauConfig: const NassauConfig(
            frontValue: 50, backValue: 50, totalValue: 100),
      );
      final otro = BetModuleInstance(
        id: 'n2',
        type: BetModuleType.nassau,
        name: 'Nassau',
        participantIds: const [],
        nassauConfig: const NassauConfig(
            frontValue: 100, backValue: 100, totalValue: 200),
      );

      final app = run(reglas: [nassau], acuerdos: [_agreement(yo, oscar, [otro])]);

      expect(app.conflicts.length, 1);
      expect(app.conflicts.single.type, BetModuleType.nassau);
      expect(app.conflicts.single.pairKey, BetModuleInstance.pairKey(yo, oscar));
      // La regla se aplica sin la excepción: nunca se cobra de más en silencio.
      expect(app.modules.length, 1);
      expect(app.modules.single.pairConfigOverrides ?? {}, isEmpty);
    });

    test('CONFLICTO: difiere en algo más que el importe', () {
      // Mismo tipo y mismo monto, pero gross contra net. Un override solo puede
      // cambiar el monto, así que esto no es representable.
      // mode viene en net por defecto, así que el gross hay que ponerlo
      // explícito para que las dos configuraciones difieran de verdad.
      final reglaGross = BetModuleInstance(
        id: 'a',
        type: BetModuleType.skins,
        name: 'Skins',
        participantIds: const [],
        skinsConfig:
            const SkinsConfig(valuePerSkin: 20, mode: GrossNetMode.gross),
      );
      final acuerdoNet = BetModuleInstance(
        id: 'b',
        type: BetModuleType.skins,
        name: 'Skins',
        participantIds: const [],
        skinsConfig:
            const SkinsConfig(valuePerSkin: 20, mode: GrossNetMode.net),
      );

      final app = run(
          reglas: [reglaGross], acuerdos: [_agreement(yo, oscar, [acuerdoNet])]);

      expect(app.conflicts.length, 1);
      expect(app.conflicts.single.reason, contains('más que el importe'));
      expect(app.modules.single.pairConfigOverrides ?? {}, isEmpty);
    });

    test('las reglas cubren a todos los jugadores presentes', () {
      final app = run(reglas: [_skins(20)], acuerdos: const []);
      expect(app.modules.single.participantIds.toSet(), {yo, rafa, oscar});
    });

    test('acuerdos de parejas ausentes se ignoran', () {
      final app = run(
        reglas: [_skins(20)],
        acuerdos: [_agreement(oscar, 'willy', [_medal(30)])],
        players: [yo, rafa],
      );
      expect(app.modules.length, 1);
      expect(app.hasConflicts, isFalse);
    });

    test('override no pisa los que la regla ya traía', () {
      final conOverride = _skins(20).copyWith(pairConfigOverrides: {
        BetModuleInstance.pairKey(yo, rafa): {'value': 99}
      });
      final app = run(reglas: [conOverride], acuerdos: [
        _agreement(yo, oscar, [_skins(50)])
      ]);
      expect(app.modules.single.overrideForPair(yo, rafa), 99);
      expect(app.modules.single.overrideForPair(yo, oscar), 50);
    });

    test('units usa allEvents como clave de override', () {
      final base = BetModuleInstance(
        id: 'u',
        type: BetModuleType.units,
        name: 'Unidades',
        participantIds: const [],
        unitsConfig: const UnitsConfig().withAllEventsValue(20),
      );
      final caro = BetModuleInstance(
        id: 'u2',
        type: BetModuleType.units,
        name: 'Unidades',
        participantIds: const [],
        unitsConfig: const UnitsConfig().withAllEventsValue(30),
      );

      final app = run(reglas: [base], acuerdos: [_agreement(yo, oscar, [caro])]);
      expect(app.hasConflicts, isFalse);
      expect(app.modules.single.overrideForPair(yo, oscar), 30);
      expect(
        app.modules.single.pairConfigOverrides![
            BetModuleInstance.pairKey(yo, oscar)]!['allEvents'],
        30,
      );
    });

    test('ids únicos entre reglas y duelos añadidos', () {
      final app = run(reglas: [_skins(20)], acuerdos: [
        _agreement(yo, oscar, [_medal(200)]),
        _agreement(yo, rafa, [_medal(100)]),
      ]);
      expect(app.modules.map((m) => m.id).toSet().length, app.modules.length);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Captura: de una ronda configurada a un juego reutilizable.
  // ══════════════════════════════════════════════════════════════════════════
  group('capture', () {
    test('un módulo que cubre a todos es regla de grupo', () {
      final cap = PairAgreementEngine.capture(
        modules: [
          _skins(20).copyWith(participantIds: [yo, rafa, oscar]),
        ],
        playerIds: [yo, rafa, oscar],
      );
      expect(cap.groupRules.length, 1);
      expect(cap.pairAgreements, isEmpty);
      expect(cap.isComplete, isTrue);
      // Normalizado a plantilla: sin participantes ni alcance.
      expect(cap.groupRules.single.participantIds, isEmpty);
    });

    test('un duelo es acuerdo de esa pareja', () {
      final cap = PairAgreementEngine.capture(
        modules: [_medal(200).copyForPair('x', yo, oscar)],
        playerIds: [yo, rafa, oscar],
      );
      expect(cap.groupRules, isEmpty);
      expect(cap.pairAgreements.length, 1);
      expect(cap.pairAgreements.single.isBetween(yo, oscar), isTrue);
      expect(cap.pairAgreements.single.templates.single.medal.value, 200);
    });

    test('los overrides de una regla salen como acuerdos de pareja', () {
      // Todos skins $20 pero yo↔Oscar a $50: al capturar, el $50 debe quedar
      // como acuerdo de la pareja y NO dentro de la regla, para que haya una
      // sola fuente de verdad.
      final regla = _skins(20).copyWith(
        participantIds: [yo, rafa, oscar],
        pairConfigOverrides: {
          BetModuleInstance.pairKey(yo, oscar): {'value': 50}
        },
      );
      final cap = PairAgreementEngine.capture(
        modules: [regla],
        playerIds: [yo, rafa, oscar],
      );

      expect(cap.groupRules.single.pairConfigOverrides, isNull);
      expect(cap.pairAgreements.length, 1);
      final a = cap.pairAgreements.single;
      expect(a.isBetween(yo, oscar), isTrue);
      expect(a.templates.single.skins.valuePerSkin, 50);
    });

    test('apuestas por equipos no se capturan', () {
      final equipos = _skins(20).copyWith(
        participantIds: [yo, rafa, oscar],
        sides: const [
          BetSide(id: 'a', name: 'A', playerIds: [yo, rafa]),
          BetSide(id: 'b', name: 'B', playerIds: [oscar, 'ww-willy']),
        ],
      );
      final cap = PairAgreementEngine.capture(
        modules: [equipos],
        playerIds: [yo, rafa, oscar, 'willy'],
      );
      expect(cap.groupRules, isEmpty);
      expect(cap.pairAgreements, isEmpty);
      expect(cap.notCaptured.length, 1);
      expect(cap.isComplete, isFalse);
    });

    test('un subconjunto intermedio no se captura', () {
      // 3 de 4: ni regla de grupo ni pareja.
      final cap = PairAgreementEngine.capture(
        modules: [_skins(20).copyWith(participantIds: [yo, rafa, oscar])],
        playerIds: [yo, rafa, oscar, 'willy'],
      );
      expect(cap.groupRules, isEmpty);
      expect(cap.notCaptured.length, 1);
    });

    test('varios duelos de la misma pareja se agrupan en un acuerdo', () {
      final cap = PairAgreementEngine.capture(
        modules: [
          _medal(200).copyForPair('x', yo, oscar),
          _skins(30).copyForPair('y', oscar, yo), // orden invertido a propósito
        ],
        playerIds: [yo, oscar],
      );
      expect(cap.pairAgreements.length, 1);
      expect(cap.pairAgreements.single.templates.length, 2);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // La propiedad que de verdad importa: capturar y volver a aplicar reproduce
  // la misma configuración. Si esto falla, guardar un juego lo corrompe.
  // ══════════════════════════════════════════════════════════════════════════
  group('viaje redondo capture → resolve', () {
    /// Firma comparable de una configuración: qué se juega y quién lo juega,
    /// ignorando ids generados.
    ///
    /// Los números se normalizan a double: el JSON de origen puede traer un int
    /// (50) donde el motor escribe un double (50.0), y overrideForPair los lee
    /// con .toDouble(), así que son el mismo valor.
    Set<String> shape(List<BetModuleInstance> mods, List<String> players) =>
        mods.map((m) {
          final pids = m.effectivePids(players).toList()..sort();
          final ovs = (m.pairConfigOverrides ?? {}).entries.map((e) {
            final sorted = e.value.keys.toList()..sort();
            final vals = sorted.map((k) {
              final v = e.value[k];
              return '$k:${v is num ? v.toDouble() : v}';
            });
            return '${e.key}=${vals.join(",")}';
          }).toList()
            ..sort();
          return '${m.configSignature}|pids:${pids.join(",")}|ov:${ovs.join(";")}';
        }).toSet();

    test('regla sola', () {
      const players = [yo, rafa, oscar];
      final original = [_skins(20).copyWith(participantIds: players)];

      final cap =
          PairAgreementEngine.capture(modules: original, playerIds: players);
      final back = PairAgreementEngine.resolve(
        groupRules: cap.groupRules,
        agreements: {for (final a in cap.pairAgreements) a.pairKey: a},
        playerIds: players,
        newId: _ids(),
      );

      expect(back.hasConflicts, isFalse);
      expect(shape(back.modules, players), shape(original, players));
    });

    test('regla con override por pareja', () {
      const players = [yo, rafa, oscar];
      final original = [
        _skins(20).copyWith(
          participantIds: players,
          pairConfigOverrides: {
            BetModuleInstance.pairKey(yo, oscar): {'value': 50}
          },
        )
      ];

      final cap =
          PairAgreementEngine.capture(modules: original, playerIds: players);
      final back = PairAgreementEngine.resolve(
        groupRules: cap.groupRules,
        agreements: {for (final a in cap.pairAgreements) a.pairKey: a},
        playerIds: players,
        newId: _ids(),
      );

      expect(back.hasConflicts, isFalse);
      expect(shape(back.modules, players), shape(original, players));
      // El override sobrevivió el viaje completo.
      expect(back.modules.single.effectiveValueForDuel(yo, oscar).$1, 50);
      expect(back.modules.single.effectiveValueForDuel(yo, rafa).$1, 20);
    });

    test('regla de grupo más duelo suelto de otro tipo', () {
      const players = [yo, rafa, oscar];
      final original = [
        _skins(20).copyWith(participantIds: players),
        _medal(200).copyForPair('m', yo, oscar),
      ];

      final cap =
          PairAgreementEngine.capture(modules: original, playerIds: players);
      final back = PairAgreementEngine.resolve(
        groupRules: cap.groupRules,
        agreements: {for (final a in cap.pairAgreements) a.pairKey: a},
        playerIds: players,
        newId: _ids(),
      );

      expect(back.hasConflicts, isFalse);
      expect(shape(back.modules, players), shape(original, players));
    });

    test('el caso completo del usuario', () {
      // Todos skins $20; yo↔Oscar además medal $200; yo↔Willy unidades a otro
      // valor mientras el grupo las juega a $20.
      const willy = 'ww-willy';
      const players = [yo, rafa, oscar, willy];
      final units = BetModuleInstance(
        id: 'u',
        type: BetModuleType.units,
        name: 'Unidades',
        participantIds: players,
        unitsConfig: const UnitsConfig().withAllEventsValue(20),
      ).copyWith(pairConfigOverrides: {
        BetModuleInstance.pairKey(yo, willy): {'allEvents': 30}
      });

      final original = [
        _skins(20).copyWith(participantIds: players),
        units,
        _medal(200).copyForPair('m', yo, oscar),
      ];

      final cap =
          PairAgreementEngine.capture(modules: original, playerIds: players);
      expect(cap.isComplete, isTrue);

      final back = PairAgreementEngine.resolve(
        groupRules: cap.groupRules,
        agreements: {for (final a in cap.pairAgreements) a.pairKey: a},
        playerIds: players,
        newId: _ids(),
      );

      expect(back.hasConflicts, isFalse);
      expect(shape(back.modules, players), shape(original, players));

      final u = back.modules.firstWhere((m) => m.type == BetModuleType.units);
      expect(u.effectiveValueForDuel(yo, willy).$1, 30);
      expect(u.effectiveValueForDuel(rafa, oscar).$1, 20);
    });

    test('vía GamePreset.fromCapture y apply', () {
      const players = [yo, rafa, oscar];
      final original = [
        _skins(20).copyWith(
          participantIds: players,
          pairConfigOverrides: {
            BetModuleInstance.pairKey(yo, oscar): {'value': 50}
          },
        ),
        _medal(200).copyForPair('m', rafa, oscar),
      ];

      final juego = GamePreset.fromCapture(
        id: 'martes',
        name: 'Martes',
        emoji: '🌮',
        capture: PairAgreementEngine.capture(
            modules: original, playerIds: players),
        playerIds: players,
      );

      expect(juego.playerIds, players);

      final back = juego.apply(players, _ids());
      expect(back.hasConflicts, isFalse);
      expect(shape(back.modules, players), shape(original, players));
    });
  });

  group('withBaseValue', () {
    test('fija el importe de los tipos que admiten override', () {
      expect(_skins(20).withBaseValue(50)!.skins.valuePerSkin, 50);
      expect(_medal(20).withBaseValue(50)!.medal.value, 50);
    });

    test('devuelve null para Nassau — tiene varios importes', () {
      final nassau = BetModuleInstance(
        id: 'n',
        type: BetModuleType.nassau,
        name: 'Nassau',
        participantIds: const [],
        nassauConfig: const NassauConfig(
            frontValue: 50, backValue: 50, totalValue: 100),
      );
      expect(nassau.withBaseValue(80), isNull);
      expect(nassau.pairOverrideKey, isNull);
    });

    test('no altera nada más que el importe', () {
      final original = _skins(20);
      final cambiado = original.withBaseValue(50)!;
      // Con el importe igualado otra vez, las firmas coinciden: la única
      // diferencia era el monto. Es la comprobación que usa resolve().
      expect(
        cambiado.withBaseValue(20)!.configSignature,
        original.configSignature,
      );
    });
  });
}
