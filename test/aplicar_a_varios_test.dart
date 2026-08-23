// ─────────────────────────────────────────────────────────────────────────────
// APLICAR A VARIOS: UNA APUESTA SUELTA
//
// El reporte era "solo aparecen Skins y Nassau", y no era una lista literal:
// la hoja mostraba CONFIGURACIONES GUARDADAS y Carlos tenía dos. El control
// funcionaba, pero su nombre prometía otra cosa.
//
// Lo que este archivo fija es lo que descubrí al determinar el alcance, porque
// cambia el encargo: **de los diez tipos creables, solo CUATRO se pactan por
// duelo**. Un grupo de apuesta es por dentro una lista de duelos
// —BettingGroup.pairRules— y toBetModuleInstancesForToday crea cada módulo con
// exactamente dos participantes. Así que Snake, Rabbit, Wolf, Oyes y Unidades no
// caben ahí de ninguna manera: son apuestas de la partida entera.
//
// Los tests que protegen algo:
//
//   · Cuáles se pactan por duelo, DERIVADO de la tabla y no de una lista.
//   · Que el motivo de los atenuados diga dónde SÍ funcionan.
//   · Que un duelo con la apuesta ya puesta no se pise: ahí vive un monto
//     pactado entre dos personas, que es el dato que este editor guarda.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/bet_recipe.dart';

void main() {
  group('1 · qué se pacta por duelo, y qué no', () {
    test('Skins, Nassau, Medal, Putts y Stableford', () {
      // La lista es EXPLÍCITA a propósito, y ya hizo su trabajo: al añadir
      // Stableford cayó, y la respuesta había cambiado de verdad —comparar
      // puntos entre dos personas es un duelo perfectamente válido—. Una lista
      // derivada de la propia implementación no habría dicho nada.
      final porDuelo =
          creatableBetTypes.where((t) => t.sePactaPorDuelo).toSet();
      expect(porDuelo, {
        BetModuleType.skins,
        BetModuleType.nassau,
        BetModuleType.medal,
        BetModuleType.putts,
        BetModuleType.stableford,
      });
    });

    test('ninguno de los tres formatos nuevos', () {
      // El hallazgo que cambia el encargo: Carlos pidió poder añadir Wolf y
      // Snake a todos los duelos, y ninguno de los dos existe como duelo.
      for (final t in [
        BetModuleType.snake,
        BetModuleType.rabbit,
        BetModuleType.wolf,
      ]) {
        expect(t.sePactaPorDuelo, isFalse, reason: t.label);
      }
    });

    test('todo tipo que no se pacta por duelo dice POR QUÉ', () {
      for (final t in creatableBetTypes) {
        if (t.sePactaPorDuelo) continue;
        expect(t.motivoSinDuelo, isNotNull, reason: t.label);
        expect(t.motivoSinDuelo!.trim(), isNotEmpty, reason: t.label);
      }
    });

    test('y los de partida dicen DÓNDE sí se ponen', () {
      // Es lo que separa una opción atenuada útil de un callejón sin salida.
      for (final t in creatableBetTypes) {
        if (!t.rules.deLaPartida) continue;
        final m = t.motivoSinDuelo!.toLowerCase();
        expect(m.contains('partida') || m.contains('ronda'), isTrue,
            reason: '${t.label} no dice dónde ponerla: ${t.motivoSinDuelo}');
      }
    });

    test('Bola Baja / Bola Alta queda fuera por los equipos, no por la partida',
        () {
      // Motivos distintos para casos distintos: es 2 vs 2, no una apuesta de
      // toda la partida. Si los dos dieran el mismo texto, el usuario no sabría
      // que uno se resuelve con equipos y el otro no se resuelve aquí.
      expect(BetModuleType.nassauLowHigh.rules.deLaPartida, isFalse);
      expect(BetModuleType.nassauLowHigh.motivoSinDuelo, contains('2 vs 2'));
    });
  });

  group('2 · la fuente es única', () {
    test('BetCount.esDeGrupo se DERIVA de la tabla', () {
      // Era una lista de dos escrita a mano —Oyes y Unidades— y con los tres
      // formatos nuevos habría quedado corta sin que nada fallara.
      for (final c in BetCount.values) {
        expect(c.esDeGrupo, !c.tipoCon(null).sePactaPorDuelo, reason: c.name);
      }
    });

    test('los conteos de los formatos nuevos son de grupo', () {
      for (final c in [BetCount.snake, BetCount.rabbit, BetCount.wolf]) {
        expect(c.esDeGrupo, isTrue, reason: c.name);
        expect(c.soloDeGrupo, isNotNull, reason: c.name);
      }
    });

    test('y los cuatro de duelo no lo son', () {
      for (final c in [BetCount.skins, BetCount.puntos, BetCount.scoreTotal,
        BetCount.putts]) {
        expect(c.esDeGrupo, isFalse, reason: c.name);
      }
    });
  });

  group('3 · el importe se aplica sin duplicar constructores de campos', () {
    test('Skins, Medal y Putts aceptan un importe único', () {
      for (final t in [BetModuleType.skins, BetModuleType.medal,
        BetModuleType.putts]) {
        final base = BetModuleInstance.defaultFor(t, const ['a', 'b'], id: 'x');
        final conMonto = base.withBaseValue(250);
        expect(conMonto, isNotNull, reason: t.label);
        expect(conMonto!.value, 250, reason: t.label);
      }
    });

    test('Nassau NO: tiene tres importes y uno solo no lo describe', () {
      // Y es la misma razón por la que su regla no admite monto por pareja: una
      // respuesta, no dos.
      final base = BetModuleInstance
          .defaultFor(BetModuleType.nassau, const ['a', 'b'], id: 'x');
      expect(base.withBaseValue(250), isNull);
      expect(BetModuleType.nassau.rules.sinMontoPorPareja, isNotNull);
    });

    test('el importe sobrevive el viaje a plantilla', () {
      // Es el camino real: instancia con monto → plantilla → se guarda en la
      // regla del duelo.
      final base = BetModuleInstance
          .defaultFor(BetModuleType.putts, const ['a', 'b'], id: 'x')
          .withBaseValue(300)!;
      final tpl = BetModuleTemplate.fromInstance(base);
      expect(tpl.type, BetModuleType.putts);
      expect(tpl.putts.value, 300);
    });
  });

  group('4 · añadir no pisa lo que ya hay', () {
    /// Réplica de _applyTipoToRules: añade el tipo saltando los que ya lo
    /// tienen, y devuelve (añadidos, saltados).
    (List<PairBetRule>, int, int) aplica(
        List<PairBetRule> reglas, BetModuleType tipo, double monto) {
      var base = BetModuleInstance.defaultFor(tipo, const ['a', 'b'], id: 'tmp');
      base = base.withBaseValue(monto) ?? base;
      final plantilla = BetModuleTemplate.fromInstance(base);
      final salida = <PairBetRule>[];
      var anadidos = 0, saltados = 0;
      for (final r in reglas) {
        if (r.modules.any((m) => m.type == tipo)) {
          saltados++;
          salida.add(r);
          continue;
        }
        anadidos++;
        salida.add(r.copyWith(modules: [...r.modules, plantilla]));
      }
      return (salida, anadidos, saltados);
    }

    PairBetRule regla(String id, List<BetModuleTemplate> mods) =>
        PairBetRule(id: id, playerAId: 'a$id', playerBId: 'b$id', modules: mods);

    test('un duelo con Putts a un monto pactado NO se sobrescribe', () {
      // El caso que importa. Reemplazar en silencio borraría el acuerdo entre
      // esas dos personas, que es justo lo que este editor existe para guardar.
      final pactado = BetModuleTemplate.fromInstance(BetModuleInstance
          .defaultFor(BetModuleType.putts, const ['a', 'b'], id: 'x')
          .withBaseValue(999)!);
      final (out, anadidos, saltados) = aplica(
          [regla('1', [pactado]), regla('2', const [])],
          BetModuleType.putts,
          50);
      expect(anadidos, 1);
      expect(saltados, 1);
      expect(out[0].modules.single.putts.value, 999,
          reason: 'el monto pactado sigue ahí');
      expect(out[1].modules.single.putts.value, 50);
    });

    test('se puede decir cuántos de cuántos', () {
      // "Añadida a 12 de 15" es un resultado; "aplicado" a secas deja al
      // usuario sin saber si funcionó.
      final conPutts = BetModuleTemplate.defaultFor(BetModuleType.putts);
      final reglas = [
        for (var i = 0; i < 15; i++)
          regla('$i', i < 3 ? [conPutts] : const []),
      ];
      final (_, anadidos, saltados) =
          aplica(reglas, BetModuleType.putts, 50);
      expect((anadidos, saltados), (12, 3));
    });

    test('añadir un tipo distinto no toca los que ya había', () {
      final conPutts = BetModuleTemplate.defaultFor(BetModuleType.putts);
      final (out, anadidos, saltados) =
          aplica([regla('1', [conPutts])], BetModuleType.skins, 100);
      expect((anadidos, saltados), (1, 0));
      expect(out.single.modules.map((m) => m.type).toSet(),
          {BetModuleType.putts, BetModuleType.skins});
    });
  });
}
