// ─────────────────────────────────────────────────────────────────────────────
// WOLF — cada hoyo uno elige compañero, o va solo por el doble
//
// El insight que define el diseño: nadie necesita ver en la app quién es el Wolf
// durante el hoyo. Eso se sabe en el tee. Así que el Wolf se DERIVA y lo único
// que se pide es una cosa por hoyo.
//
// Los tests que protegen algo de verdad:
//
//   · El Wolf sale del orden de salida y NO se pregunta. Si esto se rompiera,
//     el formato entero mide el enfrentamiento equivocado y los números siguen
//     pareciendo razonables.
//   · Un hoyo sin WolfCall NO liquida y se dice. No se inventa un compañero.
//   · El multiplicador premia SOLO al Lone Wolf que gana. El que pierde paga
//     sencillo, que es lo estándar.
//   · Con distinto de 4 jugadores el formato no se ofrece, y el motivo se puede
//     leer. Es lo que distingue una opción atenuada de un error.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/bet_recipe.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/wolf_engine.dart';
import 'package:golf_bet_master/engines/settlement_notes.dart';
import 'package:golf_bet_master/providers/round_provider.dart'
    show roundToJson, roundFromJson;

// El orden de salida es el orden de esta lista.
const w = 'w', x = 'x', y = 'y', z = 'z';
const orden = [w, x, y, z];

CourseInfo _course([int hoyos = 18]) => CourseInfo(
    name: 'T',
    holes: List.generate(
        hoyos, (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)));

/// Ronda de Wolf.
///
/// [bruto] es hoyo → {jugador: golpes}; los ausentes hacen 4. Sin handicap, así
/// que neto = bruto.
Round _round({
  Map<int, Map<String, int>> bruto = const {},
  Map<int, String?> llamadas = const {},
  Set<int> sinLlamada = const {},
  Set<int> sinScore = const {},
  WolfConfig cfg = WolfConfig.def,
  int hoyos = 18,
  List<String> participantes = orden,
}) {
  // Por defecto todos los hoyos con llamada al primer candidato posible, para
  // que los tests que no hablan de la llamada no se llenen de ruido.
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
          playerIds: participantes,
          modules: [
            BetModuleInstance.defaultFor(BetModuleType.wolf, participantes,
                    id: 'wf')
                .copyWith(wolfConfig: cfg),
          ]),
    ],
    scores: {
      for (final pid in orden)
        pid: {
          for (var h = 1; h <= hoyos; h++)
            if (!sinScore.contains(h))
              h: HoleScore(
                  playerId: pid, hole: h, grossScore: bruto[h]?[pid] ?? 4),
        },
    },
    events: const {}, oyeseRankings: const {}, sliding: const [],
    wolfCalls: calls,
    createdAt: DateTime(2026, 1, 1), totalHoles: hoyos,
  );
}

WolfHoyo _hoyo(Round r, int h) =>
    WolfEngine.recorrido(r, orden, r.betGroups.first.modules.first.wolf)
        .firstWhere((x) => x.hoyo == h);

void main() {
  group('1 · el Wolf se DERIVA del orden de salida', () {
    test('hoyo N → (N-1) mod 4', () {
      expect(WolfEngine.wolfDelHoyo(orden, 1), w);
      expect(WolfEngine.wolfDelHoyo(orden, 2), x);
      expect(WolfEngine.wolfDelHoyo(orden, 3), y);
      expect(WolfEngine.wolfDelHoyo(orden, 4), z);
      expect(WolfEngine.wolfDelHoyo(orden, 5), w, reason: 'vuelve a empezar');
    });

    test('los hoyos 17 y 18 siguen la MISMA rotación', () {
      // Decisión explícita: algunos grupos hacen que sea Wolf el que va
      // perdiendo, y sin dato no se supone. Si algún día cambia, este test es
      // el que hay que tocar — y eso es lo que se quiere, que se note.
      expect(WolfEngine.wolfDelHoyo(orden, 17), w);
      expect(WolfEngine.wolfDelHoyo(orden, 18), x);
    });

    test('cada uno es Wolf el mismo número de veces en 18 hoyos', () {
      // Con 18 hoyos y 4 jugadores no sale parejo —dos llevan 5 y dos 4— y eso
      // es correcto: lo que se comprueba es que nadie se queda fuera.
      final cuenta = <String, int>{};
      for (var h = 1; h <= 18; h++) {
        final wf = WolfEngine.wolfDelHoyo(orden, h);
        cuenta[wf] = (cuenta[wf] ?? 0) + 1;
      }
      expect(cuenta.keys.toSet(), orden.toSet());
      expect(cuenta.values.reduce((a, b) => a + b), 18);
    });
  });

  group('2 · el enfrentamiento del hoyo', () {
    test('la pareja del Wolf contra los otros dos, mejor bola neta', () {
      // H1: Wolf es w, juega con y. La pareja hace 3 (por y) contra 4.
      final r = _round(
          hoyos: 1,
          llamadas: {1: y},
          bruto: {
            1: {w: 5, y: 3, x: 4, z: 4}
          });
      final h = _hoyo(r, 1);
      expect(h.wolf, w);
      expect(h.companero, y);
      expect(h.ganadores, [w, y]);
      expect(h.perdedores, [x, z]);
    });

    test('cada perdedor paga a cada ganador', () {
      final r = _round(
          hoyos: 1,
          llamadas: {1: y},
          bruto: {
            1: {w: 5, y: 3, x: 4, z: 4}
          },
          cfg: const WolfConfig(value: 50));
      final e = BetEngine.computeAll(r);
      expect(e, hasLength(4), reason: '2 perdedores × 2 ganadores');
      expect(e.every((x) => x.amount == 50), isTrue);
      // Los asientos nombran PERSONAS, que es lo que el ajuste de ventajas sabe
      // leer. Un asiento contra un lado no se podría interpretar.
      expect(e.map((x) => x.toPlayerId).toSet(), {w, y});
      expect(e.map((x) => x.fromPlayerId).toSet(), {x, z});
    });

    test('empate en el hoyo: nadie paga', () {
      final r = _round(hoyos: 1, llamadas: {1: y});
      expect(_hoyo(r, 1).sinLiquidar, WolfSinLiquidar.empatado);
      expect(BetEngine.computeAll(r), isEmpty);
    });
  });

  group('3 · Lone Wolf', () {
    test('gana solo: cobra el multiplicador a cada uno de los tres', () {
      final r = _round(
          hoyos: 1,
          llamadas: {1: null}, // solo
          bruto: {
            1: {w: 3}
          },
          cfg: const WolfConfig(value: 50, loneMultiplier: 2));
      final e = BetEngine.computeAll(r);
      expect(e, hasLength(3));
      expect(e.every((x) => x.toPlayerId == w), isTrue);
      expect(e.every((x) => x.amount == 100), isTrue);
    });

    test('el multiplicador es configurable, por defecto 2', () {
      expect(WolfConfig.def.loneMultiplier, 2);
      final r = _round(
          hoyos: 1, llamadas: {1: null},
          bruto: {1: {w: 3}},
          cfg: const WolfConfig(value: 50, loneMultiplier: 4));
      expect(BetEngine.computeAll(r).first.amount, 200);
    });

    test('pierde solo: paga SENCILLO a cada rival, sin multiplicador', () {
      // Es lo estándar y por eso no es configurable. Si el multiplicador se
      // aplicara también a la derrota, aquí saldrían 100 en vez de 50.
      final r = _round(
          hoyos: 1, llamadas: {1: null},
          bruto: {1: {w: 6}},
          cfg: const WolfConfig(value: 50, loneMultiplier: 2));
      final e = BetEngine.computeAll(r);
      expect(e, hasLength(3));
      expect(e.every((x) => x.fromPlayerId == w), isTrue);
      expect(e.every((x) => x.amount == 50), isTrue,
          reason: 'la derrota del Lone Wolf no lleva multiplicador');
    });

    test('y se cuenta en las notas: los solos son la sal del formato', () {
      final r = _round(
          hoyos: 1, llamadas: {1: null}, bruto: {1: {w: 3}});
      expect(notasDeLiquidacion(r).map((n) => n.texto).join(),
          contains('en solitario'));
    });
  });

  group('4 · un hoyo sin WolfCall no liquida, y se DICE', () {
    test('no se inventa compañero', () {
      final r = _round(hoyos: 2, llamadas: {1: y}, sinLlamada: {2},
          bruto: {2: {w: 3}});
      expect(_hoyo(r, 2).sinLiquidar, WolfSinLiquidar.sinEleccion);
      expect(_hoyo(r, 2).companero, isNull);
    });

    test('el hoyo no mueve dinero aunque haya un ganador claro', () {
      final r = _round(hoyos: 1, sinLlamada: {1}, bruto: {1: {w: 3}});
      expect(BetEngine.computeAll(r), isEmpty);
    });

    test('y la nota nombra los hoyos y pide la acción', () {
      final r = _round(hoyos: 3, llamadas: {1: y}, sinLlamada: {2, 3});
      final notas = notasDeLiquidacion(r)
          .where((n) => n.texto.contains('Sin compañero'))
          .toList();
      expect(notas, hasLength(1), reason: 'UNA línea, no una por hoyo');
      expect(notas.single.texto, contains('H2, H3'));
      expect(notas.single.tono, TonoNota.faltaDato,
          reason: 'falta una decisión del usuario, no es solo informativo');
    });

    test('con muchos hoyos la nota resume en vez de listar dieciocho', () {
      final r = _round(sinLlamada: {for (var h = 1; h <= 18; h++) h});
      final texto = notasDeLiquidacion(r)
          .firstWhere((n) => n.texto.contains('Sin compañero'))
          .texto;
      expect(texto, contains('18 hoyos'));
      expect(texto, isNot(contains('H2, H3, H4')));
    });

    test('un compañero que no juega se trata como sin elegir', () {
      // Un lado inválido liquidaría un enfrentamiento que no existió.
      final r = _round(hoyos: 1, llamadas: {1: 'fantasma'},
          bruto: {1: {w: 3}});
      expect(_hoyo(r, 1).sinLiquidar, WolfSinLiquidar.sinEleccion);
    });

    test('el Wolf eligiéndose a sí mismo, también', () {
      final r = _round(hoyos: 1, llamadas: {1: w}, bruto: {1: {w: 3}});
      expect(_hoyo(r, 1).sinLiquidar, WolfSinLiquidar.sinEleccion);
    });
  });

  group('5 · solo con 4 jugadores', () {
    test('con 3 no se ofrece, y el motivo se puede leer', () {
      final res = BetRecipe.build(
          cuenta: BetCount.wolf, participantIds: const [w, x, y]);
      expect(res.ok, isFalse);
      expect(res.rechazo, contains('exactamente con 4'));
    });

    test('con 5 tampoco', () {
      final res = BetRecipe.build(
          cuenta: BetCount.wolf,
          participantIds: const [w, x, y, z, 'e']);
      expect(res.ok, isFalse);
    });

    test('con 4 sí', () {
      // El contrapeso: sin este, la puerta podría estar cerrada siempre.
      final res =
          BetRecipe.build(cuenta: BetCount.wolf, participantIds: orden);
      expect(res.ok, isTrue);
      expect(res.module!.type, BetModuleType.wolf);
    });

    test('la regla vive en la tabla, no en un if suelto', () {
      expect(BetModuleType.wolf.rules.jugadoresExactos, 4);
      expect(BetModuleType.wolf.rules.sinEseNumero, isNotNull);
    });

    test('una ronda guardada que se queda en 3 lo dice en vez de callarse', () {
      final r = _round(participantes: const [w, x, y]);
      final notas = notasDeLiquidacion(r);
      expect(notas, hasLength(1));
      expect(notas.single.texto, contains('exactamente con 4'));
      expect(BetEngine.computeAll(r), isEmpty);
    });
  });

  group('6 · hoyos sin score', () {
    test('no liquidan y se distinguen de los que no tienen llamada', () {
      // Son dos problemas distintos: uno se resuelve anotando y el otro
      // eligiendo. Mezclarlos en un aviso mandaría a hacer lo que no toca.
      final r = _round(hoyos: 2, llamadas: {1: y, 2: y}, sinScore: {2});
      expect(_hoyo(r, 2).sinLiquidar, WolfSinLiquidar.sinScore);
      final textos = notasDeLiquidacion(r).map((n) => n.texto).toList();
      expect(textos.any((x) => x.contains('Faltan scores')), isTrue);
      expect(textos.any((x) => x.contains('Sin compañero')), isFalse);
    });
  });

  group('7 · el dato sobrevive al viaje', () {
    test('la llamada de cada hoyo se serializa y se recupera', () {
      final r = _round(hoyos: 3, llamadas: {1: y, 2: null, 3: x});
      final vuelta = roundFromJson(
          Map<String, dynamic>.from(roundToJson(r)));
      expect(vuelta.getWolfCall(1)!.partnerId, y);
      expect(vuelta.getWolfCall(2)!.solo, isTrue,
          reason: 'Lone Wolf: en el mapa con partnerId nulo');
      expect(vuelta.getWolfCall(3)!.partnerId, x);
    });

    test('un hoyo sin llamada sigue sin llamada, no aparece como solo', () {
      // La distinción del modelo: ausente ≠ solo. Si la deserialización
      // rellenara los huecos, esos hoyos empezarían a liquidar solos.
      final r = _round(hoyos: 2, llamadas: {1: y}, sinLlamada: {2});
      final vuelta = roundFromJson(
          Map<String, dynamic>.from(roundToJson(r)));
      expect(vuelta.getWolfCall(2), isNull);
    });

    test('una ronda sin Wolf no gana una clave vacía en el JSON', () {
      final r = _round(hoyos: 1, sinLlamada: {1});
      expect(roundToJson(r).containsKey('wolfCalls'), isFalse);
    });

    test('el multiplicador se conserva', () {
      final m = BetModuleInstance.defaultFor(BetModuleType.wolf, orden, id: 'w')
          .copyWith(wolfConfig: const WolfConfig(value: 80, loneMultiplier: 3));
      final v = BetModuleInstance.fromJson(
          Map<String, dynamic>.from(m.toJson()));
      expect(v.wolf.value, 80);
      expect(v.wolf.loneMultiplier, 3);
    });
  });
}
