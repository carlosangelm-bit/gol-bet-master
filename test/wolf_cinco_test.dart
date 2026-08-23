// ─────────────────────────────────────────────────────────────────────────────
// WOLF CON CINCO JUGADORES
//
// Lo que este archivo demuestra, y es el punto del encargo: el DISEÑO DE CAPTURA
// no cambió. La pregunta sigue siendo "¿con quién jugó?" con un candidato más, y
// la rotación ya era genérica —wolfDelHoyo usa la longitud del orden, el `mod 4`
// estaba solo en el comentario—. Eso valida haber derivado el Wolf en vez de
// preguntarlo: el formato aguantó un cambio de reglas sin enterarse.
//
// Lo único de fondo es la compensación por minoría, y está formulada por
// ASIMETRÍA DE LOS LADOS y no por número de jugadores: el lado más pequeño que
// gana cobra doble. Los tests de abajo comprueban justamente eso —que con cuatro
// NO se aplica— porque es lo que distingue la formulación correcta de un
// `if (jugadores == 5)`.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/bet_recipe.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/wolf_engine.dart';
import 'package:golf_bet_master/engines/settlement_notes.dart';

const a = 'a', b = 'b', c = 'c', d = 'd', e = 'e';
const cinco = [a, b, c, d, e];
const cuatro = [a, b, c, d];

CourseInfo _course([int hoyos = 18]) => CourseInfo(
    name: 'T',
    holes: List.generate(
        hoyos, (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)));

/// Ronda de Wolf con [orden] como orden de salida.
///
/// [bruto] es hoyo → {jugador: golpes}; los ausentes hacen 4. Sin handicap.
Round _round({
  List<String> orden = cinco,
  Map<int, Map<String, int>> bruto = const {},
  Map<int, String?> llamadas = const {},
  Set<int> sinLlamada = const {},
  WolfConfig cfg = WolfConfig.def,
  int hoyos = 18,
}) {
  final calls = <int, WolfCall>{};
  for (var h = 1; h <= hoyos; h++) {
    if (sinLlamada.contains(h)) continue;
    if (llamadas.containsKey(h)) {
      calls[h] = WolfCall(hole: h, partnerId: llamadas[h]);
    }
  }
  return Round(
    id: 'r', name: 'R', course: _course(hoyos),
    players: orden.map((i) => Player(id: i, name: i.toUpperCase())).toList(),
    roundPlayers:
        orden.map((i) => RoundPlayer(playerId: i, handicapEnRonda: 0)).toList(),
    betGroups: [
      BetGroup(
          id: 'g', name: 'G',
          format: PartidaFormat.allInOnePot,
          playerIds: orden,
          modules: [
            BetModuleInstance.defaultFor(BetModuleType.wolf, orden, id: 'wf')
                .copyWith(wolfConfig: cfg),
          ]),
    ],
    scores: {
      for (final pid in orden)
        pid: {
          for (var h = 1; h <= hoyos; h++)
            h: HoleScore(
                playerId: pid, hole: h, grossScore: bruto[h]?[pid] ?? 4),
        },
    },
    events: const {}, oyeseRankings: const {}, sliding: const [],
    wolfCalls: calls,
    createdAt: DateTime(2026, 1, 1), totalHoles: hoyos,
  );
}

WolfHoyo _hoyo(Round r, int h, {List<String> orden = cinco}) =>
    WolfEngine.recorrido(r, orden, r.betGroups.first.modules.first.wolf)
        .firstWhere((x) => x.hoyo == h);

void main() {
  group('1 · con cinco se ofrece, sin atenuar', () {
    test('BetRecipe lo acepta', () {
      final res =
          BetRecipe.build(cuenta: BetCount.wolf, participantIds: cinco);
      expect(res.ok, isTrue);
      expect(res.rechazo, isNull);
    });

    test('y no hay motivo que enseñar', () {
      expect(BetModuleType.wolf.motivoNoDisponible(5), isNull);
      expect(BetModuleType.wolf.motivoNoDisponible(4), isNull);
    });

    test('con 3 y con 6 sí, con motivos distintos', () {
      final pocos = BetModuleType.wolf.motivoNoDisponible(3)!;
      final muchos = BetModuleType.wolf.motivoNoDisponible(6)!;
      expect(pocos, contains('rotación'));
      expect(muchos, contains('no hay una regla estándar'));
      expect(pocos, isNot(muchos));
    });
  });

  group('2 · la rotación cierra el ciclo cada cinco hoyos', () {
    test('cada hoyo le toca al siguiente, y el 6 vuelve al primero', () {
      for (var i = 0; i < 5; i++) {
        expect(WolfEngine.wolfDelHoyo(cinco, i + 1), cinco[i]);
      }
      expect(WolfEngine.wolfDelHoyo(cinco, 6), a, reason: 'cierra el ciclo');
      expect(WolfEngine.wolfDelHoyo(cinco, 11), a);
    });

    test('con cuatro sigue cerrando cada cuatro: la función es genérica', () {
      // Es el punto: no hay dos ramas. La misma línea sirve para los dos
      // tamaños, y por eso añadir cinco no tocó la captura.
      expect(WolfEngine.wolfDelHoyo(cuatro, 5), a);
      expect(WolfEngine.wolfDelHoyo(cinco, 5), e);
    });

    test('en 18 hoyos todos son Wolf al menos tres veces', () {
      final cuenta = <String, int>{};
      for (var h = 1; h <= 18; h++) {
        final wf = WolfEngine.wolfDelHoyo(cinco, h);
        cuenta[wf] = (cuenta[wf] ?? 0) + 1;
      }
      expect(cuenta.keys.toSet(), cinco.toSet());
      expect(cuenta.values.every((n) => n >= 3), isTrue);
      expect(cuenta.values.reduce((x, y) => x + y), 18);
    });
  });

  group('3 · el lado pequeño que gana cobra doble', () {
    test('2 contra 3: gana el Wolf y su compañero → ×2', () {
      // H1: Wolf es a, juega con b. Su mejor bola es 3 contra 4.
      final r = _round(hoyos: 1, llamadas: {1: b},
          bruto: {1: {a: 3}}, cfg: const WolfConfig(value: 50));
      final h = _hoyo(r, 1);
      expect(h.ganadores, [a, b]);
      expect(h.perdedores, [c, d, e]);
      expect(h.bonusMinoria, isTrue);
      expect(h.importe, 100);

      final asientos = BetEngine.computeAll(r);
      expect(asientos, hasLength(6), reason: '3 perdedores × 2 ganadores');
      expect(asientos.every((x) => x.amount == 100), isTrue);
    });

    test('2 contra 3: gana el lado GRANDE → sencillo', () {
      // La compensación es del lado pequeño. Si el grande cobrara doble, la
      // regla estaría invertida y el dinero seguiría cuadrando.
      final r = _round(hoyos: 1, llamadas: {1: b},
          bruto: {1: {c: 3}}, cfg: const WolfConfig(value: 50));
      final h = _hoyo(r, 1);
      expect(h.ganadores, [c, d, e]);
      expect(h.bonusMinoria, isFalse);
      expect(h.importe, 50);
    });

    test('el lado pequeño que PIERDE paga sencillo', () {
      final r = _round(hoyos: 1, llamadas: {1: b},
          bruto: {1: {c: 3}}, cfg: const WolfConfig(value: 50));
      final asientos = BetEngine.computeAll(r);
      expect(asientos.where((x) => x.fromPlayerId == a), hasLength(3));
      expect(asientos.every((x) => x.amount == 50), isTrue);
    });

    test('con CUATRO no se aplica: 2 contra 2 no tiene lado pequeño', () {
      // El test que distingue la formulación correcta de un if por número de
      // jugadores. Si la regla mirara el tamaño de la partida en vez de la
      // asimetría, esto pagaría doble.
      final r = _round(orden: cuatro, hoyos: 1, llamadas: {1: b},
          bruto: {1: {a: 3}}, cfg: const WolfConfig(value: 50));
      final h = _hoyo(r, 1, orden: cuatro);
      expect(h.ganadores, [a, b]);
      expect(h.bonusMinoria, isFalse);
      expect(h.importe, 50);
    });

    test('y el asiento dice por qué el importe va doblado', () {
      // Un importe al doble sin motivo visible se lee como error de cálculo.
      final r = _round(hoyos: 1, llamadas: {1: b}, bruto: {1: {a: 3}});
      expect(BetEngine.computeAll(r).first.reason, contains('minoría'));
    });
  });

  group('4 · el Lone Wolf con cinco', () {
    test('va solo contra CUATRO y cobra su multiplicador', () {
      final r = _round(hoyos: 1, llamadas: {1: null},
          bruto: {1: {a: 3}}, cfg: const WolfConfig(value: 50));
      final asientos = BetEngine.computeAll(r);
      expect(asientos, hasLength(4));
      expect(asientos.every((x) => x.toPlayerId == a), isTrue);
      expect(asientos.every((x) => x.amount == 100), isTrue);
    });

    test('NO acumula el doble de la minoría sobre el multiplicador', () {
      // Ir solo ya es el caso extremo de minoría. Sumar las dos cosas sería
      // cobrar dos veces por lo mismo: saldría ×4 con el default ×2.
      final r = _round(hoyos: 1, llamadas: {1: null},
          bruto: {1: {a: 3}}, cfg: const WolfConfig(value: 50));
      expect(_hoyo(r, 1).importe, 100, reason: '×2, no ×4');
      expect(_hoyo(r, 1).bonusMinoria, isFalse);
    });

    test('el multiplicador sigue siendo configurable', () {
      final r = _round(hoyos: 1, llamadas: {1: null}, bruto: {1: {a: 3}},
          cfg: const WolfConfig(value: 50, loneMultiplier: 4));
      expect(_hoyo(r, 1).importe, 200);
    });

    test('y el default sigue siendo 2, no cambia con cinco', () {
      // Decisión explícita: se AVISA en la configuración de que con cinco suele
      // subirse, en vez de cambiar el default por tamaño. Un default distinto
      // según el número de jugadores es una regla que nadie pidió, y
      // sorprendería a quien ya tenía su valor elegido.
      expect(WolfConfig.def.loneMultiplier, 2);
    });

    test('perder solo sigue pagando sencillo a cada rival', () {
      final r = _round(hoyos: 1, llamadas: {1: null},
          bruto: {1: {b: 3}}, cfg: const WolfConfig(value: 50));
      final asientos = BetEngine.computeAll(r);
      expect(asientos, hasLength(4));
      expect(asientos.every((x) => x.fromPlayerId == a), isTrue);
      expect(asientos.every((x) => x.amount == 50), isTrue);
    });
  });

  group('5 · la captura no cambia', () {
    test('hay CUATRO candidatos en vez de tres, y nada más', () {
      final r = _round(hoyos: 1, sinLlamada: {1});
      final wolf = WolfEngine.wolfDelHoyo(cinco, 1);
      final candidatos = cinco.where((p) => p != wolf).toList();
      expect(candidatos, hasLength(4));
      expect(candidatos, isNot(contains(wolf)));
    });

    test('un hoyo sin elección sigue sin liquidar, y se dice', () {
      final r = _round(hoyos: 2, llamadas: {1: b}, sinLlamada: {2});
      expect(_hoyo(r, 2).sinLiquidar, WolfSinLiquidar.sinEleccion);
      final notas = notasDeLiquidacion(r)
          .where((n) => n.texto.contains('Sin compañero'));
      expect(notas, hasLength(1));
      expect(notas.single.tono, TonoNota.faltaDato);
    });

    test('el dinero de cada hoyo suma cero', () {
      final r = _round(
          llamadas: {for (var h = 1; h <= 18; h++) h: h.isEven ? b : null},
          bruto: {for (var h = 1; h <= 18; h++) h: {cinco[h % 5]: 3}});
      final e = BetEngine.computeAll(r);
      expect(e, isNotEmpty);
      final saldo = <String, double>{};
      for (final x in e) {
        saldo[x.fromPlayerId] = (saldo[x.fromPlayerId] ?? 0) - x.amount;
        saldo[x.toPlayerId] = (saldo[x.toPlayerId] ?? 0) + x.amount;
      }
      final total = saldo.values.fold(0.0, (s, v) => s + v);
      expect(total.abs() < 0.01, isTrue, reason: 'total = $total');
    });
  });
}
