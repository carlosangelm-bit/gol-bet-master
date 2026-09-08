// ─────────────────────────────────────────────────────────────────────────────
// DOS REGLAS: PRESIONES EN LAS APUESTAS PEDIDAS, Y EL AJUSTE AL B9
//
// ── 1 · Por defecto no trae presiones, pero se pueden pedir ─────────────────
//
// El carry y la apertura nacen SIN presiones automáticas —son apuestas que se
// piden enteras— y eso no cambia. Lo que faltaba es poder pedirle una.
//
// Y la apertura sigue la MISMA regla: lo que decide no es qué apuesta es, sino
// cómo nació, y las dos nacieron porque alguien las pidió.
//
// ── 2 · El ajuste al entrar en el B9, que NO es el sliding ──────────────────
//
//     «La diferencia de hoyos en la primera vuelta, al 50%. Si quedara una
//      diferencia de 2.5, el .5 se utiliza como desempate en caso de empate en
//      el hoyo donde corresponda la ventaja. La primera vuelta ya quedó como
//      quedó, solo se ajusta la ventaja en la segunda vuelta.»
//
// Es para dos que no se conocen: la primera vuelta les sirve para medirse.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/providers/round_provider.dart'
    show roundToJson, roundFromJson;

/// Stroke index = número de hoyo, así el hoyo 10 es el más difícil del B9.
final _curso = CourseInfo(name: 'P72', holes: [
  for (int i = 1; i <= 18; i++) CourseHole(hole: i, par: 4, strokeIndex: i),
]);

/// CAM vs CAV, sin ventaja pactada — los que no se conocen.
///
/// [ganaCam] los hoyos que CAM gana en bruto; [empatan] se dejan iguales.
Round _r({
  required List<int> ganaCam,
  List<int> ganaCav = const [],
  NassauConfig cfg = const NassauConfig(
      frontValue: 50, backValue: 50, totalValue: 100),
  int hasta = 18,
}) =>
    Round(
      id: 'r',
      name: 'Primera vez',
      course: _curso,
      isFinished: hasta == 18,
      players: [Player(id: 'cam', name: 'CAM'), Player(id: 'cav', name: 'CAV')],
      roundPlayers: [
        RoundPlayer(playerId: 'cam', handicapEnRonda: 0),
        RoundPlayer(playerId: 'cav', handicapEnRonda: 0),
      ],
      betGroups: [
        BetGroup(
            id: 'g',
            name: 'G',
            format: PartidaFormat.oneVsOne,
            playerIds: const ['cam', 'cav'],
            modules: [
              BetModuleInstance(
                  id: 'n',
                  type: BetModuleType.nassau,
                  name: 'Nassau',
                  participantIds: const ['cam', 'cav'],
                  nassauConfig: cfg),
            ])
      ],
      scores: {
        for (final p in ['cam', 'cav'])
          p: {
            for (int h = 1; h <= hasta; h++)
              h: HoleScore(
                  playerId: p,
                  hole: h,
                  grossScore: (ganaCam.contains(h) && p == 'cav') ||
                          (ganaCav.contains(h) && p == 'cam')
                      ? 5
                      : 4,
                  putts: 2)
          }
      },
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2026, 9, 7),
      totalHoles: 18,
    );

BetModuleInstance _mod(Round r) => r.betGroups.first.modules.first;

List<LedgerEntry> _asientos(Round r) {
  LedgerEngine.invalidateCache();
  return LedgerEngine.entriesOf(r);
}

double _monto(Round r, String motivo) => _asientos(r)
    .where((e) => e.reason.contains(motivo))
    .fold(0.0, (s, e) => s + (e.toPlayerId == 'cam' ? e.amount : -e.amount));

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  group('el ajuste en la rama CON PRESIONES', () {
    // Hueco real: todas las demás pruebas del ajuste van por `_nassauPair`, y el
    // parámetro que lleva los deltas del B9 vive en `_nassauPressPair`. Sin este
    // grupo, liquidar el F9 con los deltas del B9 no lo cazaba nadie.
    const conPresiones = NassauConfig(
        frontValue: 50,
        backValue: 50,
        totalValue: 100,
        ajusteEnB9: true,
        pressEnabled: true,
        autoPressTrigger: 2,
        frontPressValue: 25,
        backPressValue: 25);

    Round real({bool ajuste = true}) => _r(
        ganaCam: const [1, 2, 3, 4, 5],
        ganaCav: const [13, 14, 15],
        cfg: ajuste
            ? conPresiones
            : conPresiones.copyWith(ajusteEnB9: false));

    test('CLAVE: el F9 y su presión liquidan con la ventaja ORIGINAL', () {
      // Si el F9 se liquidara con los deltas del B9, su marcador se iría a cero
      // —ese mapa solo tiene los hoyos de la otra vuelta— y no pagaría nadie.
      final e = _asientos(real());
      expect(e.firstWhere((x) => x.reason == 'Nassau Front 9').toPlayerId, 'cam');
      expect(
          e
              .firstWhere((x) => x.reason.contains('Press H3–H9'))
              .toPlayerId,
          'cam');
    });

    test('CLAVE: el B9 y su presión van AJUSTADOS, y el motivo lo dice', () {
      final e = _asientos(real());
      final b9 = e.firstWhere((x) => x.reason.startsWith('Nassau Back 9'));
      expect(b9.reason, contains('(ajustado)'));
      expect(b9.toPlayerId, 'cav');
      // La presión del B9 hereda la ventaja de su segmento: nace y se liquida
      // sobre el marcador ajustado.
      final p = e.firstWhere((x) => x.reason.contains('Press H12'));
      expect(p.reason, contains('ajustado'));
      expect(p.toPlayerId, 'cav');
    });

    test('CLAVE: el TOTAL sigue con la original', () {
      expect(_asientos(real())
              .firstWhere((x) => x.reason == 'Nassau Total 18')
              .toPlayerId,
          'cam');
    });

    test('CONTRAPESO: sin ajuste, el B9 y su presión cambian de dueño', () {
      // Es lo que prueba que el ajuste está haciendo algo en esta rama.
      final e = _asientos(real(ajuste: false));
      expect(e.firstWhere((x) => x.reason.startsWith('Nassau Back 9')).toPlayerId,
          'cav',
          reason: 'CAV gana tres hoyos en bruto');
      expect(e.any((x) => x.reason.contains('(ajustado)')), isFalse);
      // Y el B9 sin ajuste va −3, no −6: la presión nace en otro hoyo.
      final presiones = e
          .where((x) => x.reason.contains('Press H') &&
              x.reason.contains('Back 9'))
          .map((x) => x.reason)
          .toList();
      final conAjusteP = _asientos(real())
          .where((x) => x.reason.contains('Press H') &&
              x.reason.contains('Back 9'))
          .map((x) => x.reason)
          .toList();
      expect(presiones, isNot(conAjusteP));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIO 1 · presión sobre el carry: se pide, no salta', () {
    NassauConfig conCarry({Map<String, Map<String, List<int>>> presiones = const {}}) =>
        NassauConfig(
            frontValue: 50,
            backValue: 50,
            totalValue: 100,
            carryEnabled: true,
            carryPedidoByPair: const {'cam|cav': 'cav'},
            presionesPedidasByPair: presiones);

    test('CLAVE: el carry NO trae presiones por sí solo', () {
      // CAM gana el hoyo 1 —para que haya perdedor y el carry se pueda pedir—
      // y luego arrasa el B9: cuatro abajo y ninguna presión sobre el carry.
      final r = _r(ganaCam: const [1, 10, 11, 12, 13], cfg: conCarry());
      expect(_asientos(r).any((e) => e.reason.contains('Presión pedida')),
          isFalse);
      expect(_asientos(r).any((e) => e.reason.startsWith('Carry')), isTrue);
    });

    test('CLAVE: pedida en el hoyo 14, existe y cubre del 14 al 18', () {
      final r = _r(
          ganaCam: const [1, 10, 11, 12, 13],
          cfg: conCarry(presiones: const {
            'cam|cav': {'carry': [14]}
          }));
      final p = BetEngine.presionesPedidasSobre(
          r, 'cam', 'cav', _mod(r), BetEngine.segmentsOf(r), 'carry');
      expect(p, hasLength(1));
      expect(p.first.hoyo, 14);
      expect(p.first.jugados, 5, reason: 'del 14 al 18');
    });

    test('CLAVE: se liquida con su propio asiento y su propio importe', () {
      // CAV gana el 14 y el 15: la presión pedida es suya.
      final r = _r(
          ganaCam: const [1, 10, 11, 12, 13],
          ganaCav: const [14, 15],
          cfg: conCarry(presiones: const {
            'cam|cav': {'carry': [14]}
          }).copyWith(frontPressValue: 25, backPressValue: 25));
      final e = _asientos(r)
          .firstWhere((x) => x.reason.contains('Presión pedida H14'));
      expect(e.reason, contains('Carry'), reason: 'de qué apuesta es');
      expect(e.amount, 25);
      expect(e.toPlayerId, 'cav');
    });

    test('CLAVE: y la APERTURA sigue la misma regla', () {
      // «Determina si la apertura sigue la misma regla.» Sí: lo que decide es
      // cómo nació la apuesta, no cuál es.
      // CAM gana el 16, que cae dentro de la presión: sin dueño no hay asiento.
      final r = _r(
          ganaCam: const [1, 10, 11, 12, 13, 16],
          cfg: const NassauConfig(
              frontValue: 50,
              backValue: 50,
              totalValue: 100,
              aperturaB9ByPair: {'cam|cav': true},
              presionesPedidasByPair: {
                'cam|cav': {'apertura': [15]}
              }));
      final e = _asientos(r)
          .firstWhere((x) => x.reason.contains('Presión pedida H15'));
      expect(e.reason, contains('Apertura'));
    });

    test('CONTRAPESO: sin la apuesta madre, su presión no existe', () {
      // Pedir presión sobre un carry que nadie pidió sería una apuesta sobre
      // nada.
      final r = _r(
          ganaCam: const [1, 10, 11],
          cfg: const NassauConfig(
              frontValue: 50,
              backValue: 50,
              totalValue: 100,
              presionesPedidasByPair: {
                'cam|cav': {'carry': [14]}
              }));
      expect(_asientos(r).any((e) => e.reason.contains('Presión pedida')),
          isFalse);
    });

    test('CLAVE: la presión del carry HEREDA su golpe extra', () {
      // La madre del carry lleva un golpe más para quien lo pidió, así que su
      // presión también. Se ve en el marcador: sobre los mismos hoyos, la
      // presión de la APERTURA y la del CARRY no dan lo mismo.
      //
      // La presión arranca en el 10 A PROPÓSITO: los golpes se reparten por
      // stroke index sobre los NUEVE, así que una presión que empiece en el 14
      // puede no contener ninguno y entonces heredar la ventaja no cambia nada.
      const hoyos = {
        'cam|cav': {'carry': [10], 'apertura': [10]}
      };
      final r = _r(
          ganaCam: const [1, 10, 11, 12, 13, 14],
          cfg: NassauConfig(
              frontValue: 50,
              backValue: 50,
              totalValue: 100,
              carryEnabled: true,
              carryPedidoByPair: const {'cam|cav': 'cav'},
              aperturaB9ByPair: const {'cam|cav': true},
              presionesPedidasByPair: hoyos));
      final seg = BetEngine.segmentsOf(r);
      final delCarry = BetEngine.presionesPedidasSobre(
          r, 'cam', 'cav', _mod(r), seg, 'carry');
      final deApertura = BetEngine.presionesPedidasSobre(
          r, 'cam', 'cav', _mod(r), seg, 'apertura');
      expect(delCarry.first.margen, lessThan(deApertura.first.margen),
          reason: 'el golpe extra de CAV se nota en la del carry');
    });

    test('CLAVE: y entran en el inventario de la tarjeta', () {
      final r = _r(
          ganaCam: const [1, 10, 11, 12, 13],
          cfg: conCarry(presiones: const {
            'cam|cav': {'carry': [14]}
          }));
      final inv = BetEngine.apuestasVivasDelNassau(r, 'cam', 'cav', _mod(r));
      final p = inv.where((a) => a.nota?.contains('presión pedida') == true);
      expect(p, hasLength(1));
      expect(p.first.nota, contains('Carry'));
    });

    test('ida y vuelta a JSON conserva los hoyos pedidos', () {
      final r = _r(
          ganaCam: const [1],
          cfg: conCarry(presiones: const {
            'cam|cav': {'carry': [14, 16]}
          }));
      final back = roundFromJson(roundToJson(r));
      expect(
          back.betGroups.first.modules.first.nassau
              .presionesPedidasDe('cam', 'cav', 'carry'),
          [14, 16]);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIO 2 · la ventaja del B9 sale del F9 al 50%', () {
    const conAjuste = NassauConfig(
        frontValue: 50, backValue: 50, totalValue: 100, ajusteEnB9: true);

    test('CLAVE: F9 por 5 → el otro recibe 2.5 en el B9', () {
      // El caso del enunciado, y el que pide el criterio 5: diferencia IMPAR.
      final r = _r(ganaCam: const [1, 2, 3, 4, 5], cfg: conAjuste);
      final a = BetEngine.ajusteDelB9(r, 'cam', 'cav', _mod(r))!;
      expect(a.margenF9, 5);
      expect(a.ventaja, -2.5, reason: 'CAM gana por 5, así que DA 2.5');
      // Y leído desde CAV es +2.5: recibe.
      expect(BetEngine.ajusteDelB9(r, 'cav', 'cam', _mod(r))!.ventaja, 2.5);
    });

    test('CLAVE: diferencia PAR → sin medio golpe', () {
      final r = _r(ganaCam: const [1, 2, 3, 4], cfg: conAjuste);
      final a = BetEngine.ajusteDelB9(r, 'cam', 'cav', _mod(r))!;
      expect(a.ventaja, -2.0);
      expect(a.hoyoDelMedio, isNull);
    });

    test('CLAVE: SUSTITUYE la ventaja del B9, no se suma', () {
      // Es una medición de esta ronda, no una corrección de un acuerdo.
      final r = _r(ganaCam: const [1, 2, 3, 4, 5], cfg: conAjuste);
      expect(BetEngine.ventajaDelSegundoNueve(r, 'cam', 'cav', _mod(r)), -2.5);
    });

    test('CLAVE: con el F9 a medias no hay ajuste que anunciar', () {
      // Hasta que termine, la diferencia va a cambiar. Anunciar una a medias
      // sería anunciar un número que se mueve.
      final r = _r(ganaCam: const [1, 2, 3], hasta: 5, cfg: conAjuste);
      expect(BetEngine.ajusteDelB9(r, 'cam', 'cav', _mod(r)), isNull);
    });

    test('CONTRAPESO: apagado, la ventaja del B9 es la de siempre', () {
      // Si esto cambiara, el ajuste habría reescrito el comportamiento de todo
      // el mundo en vez de añadir una opción.
      final r = _r(ganaCam: const [1, 2, 3, 4, 5]);
      expect(BetEngine.ajusteDelB9(r, 'cam', 'cav', _mod(r)), isNull);
      expect(BetEngine.ventajaDelSegundoNueve(r, 'cam', 'cav', _mod(r)), 0.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIO 3 · el medio golpe hace algo definido', () {
    const conAjuste = NassauConfig(
        frontValue: 50, backValue: 50, totalValue: 100, ajusteEnB9: true);

    test('CLAVE: cae en el SIGUIENTE hoyo por stroke index', () {
      // F9 por 5 → 2 enteros en los hoyos 10 y 11 —los más difíciles del B9— y
      // el medio en el 12, que es el que habría recibido el tercero.
      final r = _r(ganaCam: const [1, 2, 3, 4, 5], cfg: conAjuste);
      final a = BetEngine.ajusteDelB9(r, 'cam', 'cav', _mod(r))!;
      expect(a.hoyoDelMedio, 12);
    });

    test('CLAVE: y solo ROMPE EMPATES — no da un golpe', () {
      // En el hoyo 12 los dos hacen 4. Sin el medio golpe es empate; con él lo
      // gana CAV, que es quien recibe.
      final r = _r(ganaCam: const [1, 2, 3, 4, 5], cfg: conAjuste);
      final seg = BetEngine.segmentsOf(r);
      final conMedio = BetEngine.deltasConVentajaDeNueve(
          r, 'cam', 'cav', _mod(r),
          hoyosDelNueve: seg.secondNine, ventaja: -2.5);
      final sinMedio = BetEngine.deltasConVentajaDeNueve(
          r, 'cam', 'cav', _mod(r),
          hoyosDelNueve: seg.secondNine, ventaja: -2.0);
      expect(conMedio[12], -1, reason: 'el empate del 12 se lo lleva CAV');
      expect(sinMedio[12], 0);
      // Y en los hoyos con golpe entero no cambia nada.
      expect(conMedio[10], sinMedio[10]);
    });

    test('CLAVE: en un hoyo que NO está empatado, el medio no hace nada', () {
      // CAM gana el 12 en bruto: el medio golpe no lo convierte en empate.
      final r = _r(ganaCam: const [1, 2, 3, 4, 5, 12], cfg: conAjuste);
      final seg = BetEngine.segmentsOf(r);
      final d = BetEngine.deltasConVentajaDeNueve(r, 'cam', 'cav', _mod(r),
          hoyosDelNueve: seg.secondNine, ventaja: -2.5);
      expect(d[12], 1, reason: 'lo gana CAM, medio golpe o no');
    });

    test('CLAVE: y la pantalla lo EXPLICA', () {
      // «Medio golpe es lo que nadie sabe explicar en el tee.»
      final codigo = File('lib/screens/scorecard/scorecard_screen.dart')
          .readAsStringSync();
      expect(codigo, contains('MEDIO GOLPE en el H'));
      expect(codigo, contains('rompe el empate'));
      // Y dice en qué hoyo cae, que es la mitad de la explicación.
      expect(codigo, contains('aj.hoyoDelMedio'));
      // El editor explica la regla al pactarla.
      final editor =
          File('lib/widgets/bet_module_edit_sheet.dart').readAsStringSync();
      expect(editor, contains('MEDIO GOLPE'));
      expect(editor, contains('sirve de desempate'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIO 4 · el F9 liquida con la ventaja original', () {
    const conAjuste = NassauConfig(
        frontValue: 50, backValue: 50, totalValue: 100, ajusteEnB9: true);

    test('CLAVE: el F9 no se recalcula — «ya quedó como quedó»', () {
      // CAM gana los cinco primeros: el F9 es suyo, con o sin ajuste.
      final r = _r(ganaCam: const [1, 2, 3, 4, 5], cfg: conAjuste);
      expect(_monto(r, 'Front 9'), 50);
    });

    test('CLAVE: y el TOTAL DE 18 tampoco', () {
      // Es UNA apuesta sobre los dieciocho: cambiarle la ventaja a mitad
      // dejaría su primer nueve con una regla y el segundo con otra. Mismo
      // criterio que el carry natural.
      //
      // CAM gana 5 del F9; CAV gana 3 del B9 en bruto. Con la ventaja ORIGINAL
      // —cero— el total va +2 para CAM.
      final r = _r(
          ganaCam: const [1, 2, 3, 4, 5],
          ganaCav: const [10, 11, 12],
          cfg: conAjuste);
      expect(_monto(r, 'Total 18'), 100, reason: 'CAM +2 en bruto sobre 18');
    });

    test('CLAVE: y el caso que lo DEMUESTRA — el total cambiaría de dueño', () {
      // El total es match play: solo importa quién gana, así que probarlo con
      // un caso donde el signo no cambia no prueba nada. Este cambia:
      //
      //   F9: CAM +5. B9 en bruto: CAV gana 13, 14 y 15 → −3.
      //   total con la ventaja ORIGINAL  →  5 − 3 = +2  → lo gana CAM
      //   total si se ajustara           →  5 − 6 = −1  → lo ganaría CAV
      //
      // (Con el ajuste, CAV gana además el 10 y el 11 por golpe entero y el 12
      // por el medio: el B9 se va a −6.)
      final r = _r(
          ganaCam: const [1, 2, 3, 4, 5],
          ganaCav: const [13, 14, 15],
          cfg: conAjuste);
      expect(_monto(r, 'Total 18'), 100,
          reason: 'el total se paga con la ventaja ORIGINAL: lo gana CAM');
      expect(_monto(r, 'Back 9'), -50, reason: 'y el B9 ajustado lo gana CAV');
      // Y la prueba de que el B9 ajustado va a −6 y no a −3.
      final seg = BetEngine.segmentsOf(r);
      final d = BetEngine.deltasConVentajaDeNueve(r, 'cam', 'cav', _mod(r),
          hoyosDelNueve: seg.secondNine, ventaja: -2.5);
      expect(seg.secondNine.fold<int>(0, (a, h) => a + (d[h] ?? 0)), -6);
    });

    test('CLAVE: pero el B9 SÍ, y con el medio golpe', () {
      // CAV gana 3 hoyos del B9 en bruto (10, 11, 12) y recibe 2.5. Los dos
      // enteros caen en el 10 y el 11 —que ya gana— y el medio en el 12, que
      // también gana. Así que el B9 es de CAV por 3.
      final r = _r(
          ganaCam: const [1, 2, 3, 4, 5],
          ganaCav: const [10, 11, 12],
          cfg: conAjuste);
      expect(_monto(r, 'Back 9'), -50, reason: 'lo gana CAV');
      expect(_asientos(r).any((e) => e.reason.contains('ajustado')), isTrue,
          reason: 'el motivo dice que ese nueve va ajustado');
    });

    test('CONTRAPESO: sin ajuste, ese mismo B9 lo gana igual CAV pero por 3', () {
      // El contrapeso que importa: con la ventaja original el resultado del B9
      // aquí coincide, así que la prueba que lo distingue es la de abajo.
      final r = _r(
          ganaCam: const [1, 2, 3, 4, 5], ganaCav: const [10, 11, 12]);
      expect(_monto(r, 'Back 9'), -50);
    });

    test('CLAVE: el caso donde el ajuste CAMBIA quién gana el B9', () {
      // CAM gana el F9 por 5 → CAV recibe 2.5 en el B9. En el B9 CAM gana dos
      // hoyos en bruto (13 y 14) y el resto se empata.
      //
      //   sin ajuste → CAM gana el B9 por 2
      //   con ajuste → CAV tiene golpe en el 10 y el 11 (los gana) y medio en
      //                el 12 (empate → suyo): 3 a 2 para CAV.
      final sin = _r(ganaCam: const [1, 2, 3, 4, 5, 13, 14]);
      final con = _r(ganaCam: const [1, 2, 3, 4, 5, 13, 14], cfg: conAjuste);
      expect(_monto(sin, 'Back 9'), 50, reason: 'sin ajuste lo gana CAM');
      expect(_monto(con, 'Back 9'), -50, reason: 'con ajuste lo gana CAV');
    });
  });
}
