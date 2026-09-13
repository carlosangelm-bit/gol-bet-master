// ─────────────────────────────────────────────────────────────────────────────
// LO CONFIGURADO EN EL DUELO ES LO QUE SE COBRA
//
// «¿Podemos revisar que tengamos certeza de que lo que aparece configurado en
//  los duelos sea lo que se refleje en la apuesta?»
//
// Van dos veces que un importe no llega: los oyeses, que mostraban el de otro
// duelo, y las unidades, que al anotar decían $25 donde la apuesta decía $100.
//
// ── El fondo: seis listas para un hecho ─────────────────────────────────────
//
// «Este tipo tiene importe, vive aquí, y admite uno por duelo» estaba escrito
// SEIS VECES a mano —la tabla de reglas, `supportsPlayerOverride`,
// `overrideForPair`, `pairOverrideKey`, `baseValue`, `withBaseValue`— y todas
// menos dos derivaron solas. Por ahí se colaron TRES tipos que ofrecían importe
// por duelo y no lo aplicaban: medal, putts y stableford.
//
// ── Esta prueba recorre el ENUM, no una lista ───────────────────────────────
//
// Con doce tipos, una prueba por tipo escrita a mano envejece mal — y ya fue una
// lista escrita a mano la que dejó seis apuestas fuera del desglose. Añadir un
// tipo al catálogo hace que estas pruebas lo cubran solas.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';
import 'package:golf_bet_master/models/models.dart';

final _curso = CourseInfo(
    name: 'P72',
    holes: List.generate(
        18,
        (i) => CourseHole(
            hole: i + 1,
            par: const {3, 7, 12, 16}.contains(i + 1) ? 3 : 4,
            strokeIndex: i + 1)));

const _tres = ['ana', 'beto', 'caro'];

/// Una ronda con un módulo de [tipo] entre los tres, y una excepción de importe
/// para la pareja ana↔beto.
///
/// Los scores se reparten para que TODOS los tipos produzcan asiento: ana hace
/// birdies, beto pares y caro bogeys, con putts distintos.
Round _r(BetModuleType tipo,
    {Map<String, Map<String, dynamic>>? porDuelo, double base = 100}) {
  var mod = BetModuleInstance.defaultFor(tipo, _tres, id: 'm');
  mod = (mod.withBaseValue(base) ?? mod).copyWith(
      pairConfigOverrides: porDuelo,
      // TODOS VS TODOS: es donde el importe por duelo existe. En un pote no,
      // y eso está decidido y probado aparte — «el pozo es único».
      formatMode: BetFormatMode.allVsAll);
  return Round(
    id: 'r',
    name: 'R',
    course: _curso,
    isFinished: true,
    players: [for (final p in _tres) Player(id: p, name: p)],
    roundPlayers: [
      for (final p in _tres) RoundPlayer(playerId: p, handicapEnRonda: 0)
    ],
    betGroups: [
      BetGroup(
          id: 'g',
          name: 'G',
          format: PartidaFormat.oneVsOne,
          playerIds: _tres,
          modules: [mod])
    ],
    scores: {
      for (final (i, p) in _tres.indexed)
        p: {
          for (final ch in _curso.holes)
            ch.hole: HoleScore(
                playerId: p,
                hole: ch.hole,
                grossScore: ch.par + i - 1,
                putts: 1 + i)
        }
    },
    events: const {},
    oyeseRankings: const {},
    sliding: const [],
    createdAt: DateTime(2026, 9, 13),
    totalHoles: 18,
  );
}

List<LedgerEntry> _entre(Round r, String a, String b) {
  LedgerEngine.invalidateCache();
  return LedgerEngine.entriesOf(r)
      .where((e) =>
          (e.fromPlayerId == a && e.toPlayerId == b) ||
          (e.fromPlayerId == b && e.toPlayerId == a))
      .toList();
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIO 1 · cada tipo dice dónde vive su importe', () {
    test('CLAVE: la tabla cubre el catálogo ENTERO, sin comodín', () {
      // El switch de `importeDelTipo` no tiene `_`, así que añadir un tipo no
      // compila hasta declararlo. Esto lo comprueba desde fuera.
      for (final t in BetModuleType.values) {
        expect(() => BetModuleInstance.importeDelTipo(t), returnsNormally,
            reason: '$t no declara dónde vive su importe');
      }
    });

    test('CLAVE: el importe base va y vuelve — para todos los que lo tienen',
        () {
      // `withBaseValue` escribía en un sitio y `baseValue` leía de otro en
      // Stableford: el viaje se perdía, y dos pantallas enseñaban cifras
      // distintas del mismo dato.
      for (final t in BetModuleType.values) {
        final mod = BetModuleInstance.defaultFor(t, _tres, id: 'm');
        final conValor = mod.withBaseValue(77);
        if (conValor == null) continue; // lleva varios importes: no aplica
        expect(conValor.baseValue, 77,
            reason: '${t.name}: se escribe en un sitio y se lee de otro');
      }
    });

    test('CLAVE: `value` y `baseValue` dicen lo mismo en los doce', () {
      // `value` es una SÉPTIMA lista: el importe de titular, con su propio
      // switch por tipo, que es lo que pintan los chips. Hoy coincide con
      // `baseValue` en todos — pero coincidir no es estar atado, y así es
      // exactamente como nacen las divergencias que esta auditoría persigue.
      for (final t in BetModuleType.values) {
        final mod = BetModuleInstance.defaultFor(t, _tres, id: 'm');
        expect(mod.value, mod.baseValue,
            reason: '${t.name}: el titular y el base se separaron');
        // Y también después de fijarlo, que es cuando se notaría.
        final conValor = mod.withBaseValue(42);
        if (conValor == null) continue;
        expect(conValor.value, conValor.baseValue, reason: '${t.name} tras fijar');
      }
    });

    test('CONTRAPESO: los que llevan VARIOS importes no fingen tener uno', () {
      // Nassau tiene front, back, total y presiones: escribir «el importe»
      // dejaría los otros sin tocar.
      for (final t in [BetModuleType.nassau, BetModuleType.nassauLowHigh]) {
        expect(BetModuleInstance.defaultFor(t, _tres, id: 'm').withBaseValue(77),
            isNull);
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIO 2 · lo que se ofrece es lo que se aplica', () {
    test('CLAVE: quien ANUNCIA importe por duelo tiene con qué guardarlo', () {
      // Stableford lo anunciaba y `overrideForPair` le devolvía null: se
      // configuraba, se guardaba y nada lo aplicaba.
      for (final t in BetModuleType.values) {
        final mod = BetModuleInstance.defaultFor(t, _tres, id: 'm');
        expect(t.rules.perPairAmount, mod.pairOverrideKey != null,
            reason: '${t.name}: lo anuncia y no tiene clave donde guardarlo');
        // Y un módulo en POTE no lo admite, aunque su tipo sí: ofrecer una
        // excepción que el pozo nunca aplicaría es el mismo defecto.
        expect(
            mod.copyWith(formatMode: BetFormatMode.onePot)
                .supportsPlayerOverride,
            isFalse,
            reason: '${t.name}: un pote no lleva importes por duelo');
      }
    });

    test('CLAVE: y el MOTOR lo cobra — los tres que no lo hacían', () {
      // La comprobación de fondo, y la que ninguna de las anteriores hacía:
      // se configura un importe para UN duelo y se mira lo que el ledger cobra.
      for (final t in BetModuleType.values) {
        final mod = BetModuleInstance.defaultFor(t, _tres, id: 'm')
            .copyWith(formatMode: BetFormatMode.allVsAll);
        final clave = mod.pairOverrideKey;
        if (clave == null) continue;

        final r = _r(t,
            base: 100,
            porDuelo: {
              BetModuleInstance.pairKey('ana', 'beto'): {clave: 25.0}
            });
        final entreLosDos = _entre(r, 'ana', 'beto');
        if (entreLosDos.isEmpty) continue; // ese tipo no cruzó a esta pareja

        expect(entreLosDos.map((e) => e.amount).toSet(), {25.0},
            reason: '${t.name}: la pareja pactó 25 y el ledger cobra otra cosa');
      }
    });

    test('CLAVE: CRITERIO 3 · dos duelos con importes distintos no se mezclan',
        () {
      // El escenario que nunca se había probado. ana↔beto a 25, y ana↔caro
      // se queda con los 100 de la apuesta.
      for (final t in BetModuleType.values) {
        final mod = BetModuleInstance.defaultFor(t, _tres, id: 'm')
            .copyWith(formatMode: BetFormatMode.allVsAll);
        final clave = mod.pairOverrideKey;
        if (clave == null) continue;

        final r = _r(t,
            base: 100,
            porDuelo: {
              BetModuleInstance.pairKey('ana', 'beto'): {clave: 25.0}
            });
        final conBeto = _entre(r, 'ana', 'beto').map((e) => e.amount).toSet();
        final conCaro = _entre(r, 'ana', 'caro').map((e) => e.amount).toSet();
        if (conBeto.isEmpty || conCaro.isEmpty) continue;

        expect(conBeto, {25.0}, reason: '${t.name}: el duelo pactado');
        expect(conCaro, {100.0},
            reason: '${t.name}: el otro duelo se contaminó');
      }
    });

    test('CONTRAPESO: sin excepción, los dos duelos cobran el base', () {
      // Si no, la prueba de arriba no probaría que la excepción es lo que
      // separa a los dos.
      for (final t in BetModuleType.values) {
        final mod = BetModuleInstance.defaultFor(t, _tres, id: 'm')
            .copyWith(formatMode: BetFormatMode.allVsAll);
        if (mod.pairOverrideKey == null) continue;
        final r = _r(t, base: 100);
        for (final otro in ['beto', 'caro']) {
          final e = _entre(r, 'ana', otro).map((x) => x.amount).toSet();
          if (e.isEmpty) continue;
          expect(e, {100.0}, reason: '${t.name} vs $otro');
        }
      }
    });
  });
}
