// ─────────────────────────────────────────────────────────────────────────────
// LA TARJETA DEL NASSAU ENSEÑABA CUATRO DE CINCO
//
// «Se muestra en el resultado, pero la tarjeta del duelo muestra lo mismo que te
//  mandé inicialmente.»
//
// El desglose listaba cinco apuestas y la tarjeta cuatro recuadros: faltaban el
// carry pedido y la apertura de 2ª vuelta.
//
// ── Y no era una cuenta mal hecha ───────────────────────────────────────────
//
// Los importes los leía del motor. Lo que tenía escrito a mano era el
// INVENTARIO —«tres segmentos y las presiones»— así que una apuesta nueva no
// aparecía por no estar en la lista. Es la misma familia que la cuenta paralela
// del desglose, un piso más arriba: allí se recalculaba el dinero, aquí se
// decidía qué existe.
//
// ── Y por qué no vale probarlo contra el ledger ─────────────────────────────
//
// El ledger solo emite asiento cuando hay ganador, y un segmento empatado tiene
// que verse igual —«F9 AS $50»—. Así que se enumera aparte, y esta prueba ATA
// las dos listas: todo lo que el ledger cobra tiene que tener su recuadro.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/screens/scorecard/scorecard_screen.dart';
import 'package:provider/provider.dart';

final _curso = CourseInfo(name: 'P72', holes: [
  for (int i = 1; i <= 18; i++) CourseHole(hole: i, par: 4, strokeIndex: i),
]);

/// Lo pedido el 7 de septiembre: el carry y la apertura.
const _lasDos = NassauConfig(
  frontValue: 50,
  backValue: 50,
  totalValue: 100,
  carryEnabled: true,
  pressEnabled: true,
  autoPressTrigger: 2,
  carryPedidoByPair: {'cam|cav': 'cav'},
  aperturaB9ByPair: {'cam|cav': true},
);

/// La ronda del 7 Sep: F9 empatado, CAM gana cuatro del B9.
Round _r({NassauConfig cfg = _lasDos, List<int> ganaCam = const [10, 11, 12, 13]}) =>
    Round(
      id: 'r',
      name: '7 Sep',
      course: _curso,
      isFinished: false,
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
            for (int h = 1; h <= 18; h++)
              h: HoleScore(
                  playerId: p,
                  hole: h,
                  grossScore: ganaCam.contains(h) && p == 'cav' ? 5 : 4,
                  putts: 2)
          }
      },
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2026, 9, 7),
      totalHoles: 18,
    );

List<ApuestaVivaDelNassau> _inventario(Round r) => BetEngine
    .apuestasVivasDelNassau(r, 'cam', 'cav', r.betGroups.first.modules.first);

List<String> _motivos(Round r) {
  LedgerEngine.invalidateCache();
  return LedgerEngine.entriesOf(r).map((e) => e.reason).toList();
}

Future<int> _recuadros(WidgetTester tester, Round r) async {
  await tester.pumpWidget(ChangeNotifierProvider<RoundProvider>.value(
    value: RoundProvider()..startRound(r),
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: NassauLivePanel(
              round: r,
              p1: r.players[0],
              p2: r.players[1],
              mod: r.betGroups.first.modules.first,
              t: GolfTheme.dark),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return tester.widgetList(find.byType(NassauSegment)).length;
}

String _texto(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .join('  ‖  ');

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIO 1 · la tarjeta enseña las cinco', () {
    test('CLAVE: el inventario son SEIS, y el desglose lista cinco', () {
      // Seis recuadros y cinco asientos, y las dos cifras son correctas: el F9
      // quedó EMPATADO, así que tiene recuadro —«F9 AS \$50»— y no tiene
      // asiento. Es la razón exacta por la que este inventario no puede salir
      // del ledger.
      final inv = _inventario(_r());
      expect(inv.map((a) => a.etiqueta).toList(),
          ['F9', 'B9', '18', 'H12', 'Apertura', 'Carry']);
      expect(_motivos(_r()), hasLength(5));
      expect(inv.where((a) => a.empatada).map((a) => a.etiqueta), ['F9']);
    });

    test('CLAVE: y las dos PEDIDAS están, con su clase', () {
      final pedidas = _inventario(_r())
          .where((a) => a.clase == ClaseDeApuesta.pedida)
          .toList();
      expect(pedidas.map((a) => a.etiqueta), containsAll(['Apertura', 'Carry']));
    });

    test('CLAVE: TODO lo que el ledger cobra tiene su recuadro', () {
      // La guarda que faltaba. Si mañana aparece una apuesta nueva en el motor
      // y no en el inventario, el desglose la cobrará y la tarjeta no la
      // enseñará — que es exactamente lo que pasó.
      final r = _r();
      final inv = _inventario(r);
      const deLedgerARecuadro = {
        'Nassau Front 9': 'F9',
        'Nassau Back 9': 'B9',
        'Nassau Total 18': '18',
        'Apertura 2ª vuelta': 'Apertura',
        'Carry · un golpe más': 'Carry',
      };
      for (final motivo in _motivos(r)) {
        final esperado = motivo.startsWith('Press')
            ? RegExp(r'H\d+').firstMatch(motivo)!.group(0)!
            : deLedgerARecuadro.entries
                .firstWhere((e) => motivo.startsWith(e.key),
                    orElse: () => throw StateError('motivo sin mapear: $motivo'))
                .value;
        expect(inv.map((a) => a.etiqueta), contains(esperado),
            reason: 'el ledger cobra «$motivo» y no hay recuadro');
      }
    });

    test('CLAVE: y el inventario no inventa nada que el ledger no conozca', () {
      // Al revés: un recuadro de una apuesta que nadie liquida sería una
      // promesa falsa. Se comprueba sobre las NO empatadas, porque un empate no
      // produce asiento y sí tiene que verse.
      const comoLoLlamaElLedger = {
        'F9': 'Front 9',
        'B9': 'Back 9',
        '18': 'Total 18',
        'Apertura': 'Apertura',
        'Carry': 'Carry',
      };
      final r = _r();
      final motivos = _motivos(r).join(' ‖ ');
      for (final a in _inventario(r).where((x) => !x.empatada)) {
        final buscar = comoLoLlamaElLedger[a.etiqueta] ?? a.etiqueta;
        expect(motivos, contains(buscar),
            reason: 'hay recuadro de ${a.etiqueta} y el ledger no lo cobra');
      }
    });

    test('CONTRAPESO: sin pedir ninguna, son tres segmentos y la presión', () {
      final r = _r(
          cfg: const NassauConfig(
              frontValue: 50,
              backValue: 50,
              totalValue: 100,
              carryEnabled: true,
              pressEnabled: true,
              autoPressTrigger: 2));
      expect(_inventario(r).map((a) => a.etiqueta).toList(),
          ['F9', 'B9', '18', 'H12']);
      expect(
          _inventario(r).any((a) => a.clase == ClaseDeApuesta.pedida), isFalse);
    });

    testWidgets('CLAVE: EN PANTALLA salen los seis', (tester) async {
      // `NassauSegment` pinta los segmentos y las pedidas —CINCO—; la presión
      // la pinta su propio chip, y se comprueba por su título y su hoyo.
      expect(await _recuadros(tester, _r()), 5);
      final txt = _texto(tester);
      expect(txt, contains('PRESIONES  B9'));
      expect(txt, contains('H12'));
    });

    testWidgets('CONTRAPESO: sin pedirlas, tres', (tester) async {
      final r = _r(
          cfg: const NassauConfig(
              frontValue: 50,
              backValue: 50,
              totalValue: 100,
              carryEnabled: true,
              pressEnabled: true,
              autoPressTrigger: 2));
      expect(await _recuadros(tester, r), 3);
    });

    testWidgets('CLAVE: y cada pedida DICE qué la distingue', (tester) async {
      // Comparten hoyos e importe con el B9. Dos recuadros iguales con
      // marcadores distintos y sin explicación se leen como un fallo.
      await _recuadros(tester, _r());
      final txt = _texto(tester);
      expect(txt, contains('PEDIDAS'));
      expect(txt, contains('Carry · un golpe más de ventaja'));
      expect(txt, contains('Apertura · la 2ª vuelta otra vez, desde cero'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIO 2 · qué entra en la línea, y por qué', () {
    // La regla: la línea es UN marcador leído desde varios hoyos de salida. De
    // ahí sale que los números sean comparables y que la longitud cuente
    // presiones.
    test('CLAVE: ni el carry ni la apertura entran', () {
      final r = _r();
      final l = BetEngine.lineasDelDuelo(
          r, 'cam', 'cav', r.betGroups.first.modules.first);
      final b9 = l.firstWhere((x) => x.etiqueta == 'B9');
      expect(b9.presiones, 1, reason: 'la longitud sigue contando presiones');
      expect(b9.numeros, hasLength(2), reason: 'el segmento y su presión');
    });

    test('CLAVE: la APERTURA sería una copia del primer número', () {
      // Mismo nueve, mismos golpes, mismo marcador. Añadirla no diría nada.
      final r = _r();
      final inv = _inventario(r);
      final b9 = inv.firstWhere((a) => a.etiqueta == 'B9');
      final ap = inv.firstWhere((a) => a.etiqueta == 'Apertura');
      expect(ap.margen, b9.margen);
    });

    test('CLAVE: y el CARRY se mide con OTRA ventaja — medido', () {
      // La demostración concreta: los MISMOS nueve hoyos dan +4 en el B9 y +3
      // en la apuesta del carry, porque CAV lleva un golpe más ahí. Puestos en
      // la misma línea —«+4 +2 +3»— el tres invitaría a compararse con los
      // otros dos, y no está en su escala.
      final inv = _inventario(_r());
      final b9 = inv.firstWhere((a) => a.etiqueta == 'B9');
      final carry = inv.firstWhere((a) => a.etiqueta == 'Carry');
      expect(b9.margen, 4);
      expect(carry.margen, 3);
      expect(carry.nota, contains('golpe más'));
    });

    testWidgets('CLAVE: la cabecera SÍ dice que hay pedidas', (tester) async {
      // La línea sigue siendo la cadena; lo que no puede es callar que existen.
      final r = _r();
      await tester.pumpWidget(ChangeNotifierProvider<RoundProvider>.value(
        value: RoundProvider()..startRound(r),
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MatchStatusCard(
                round: r,
                p1: r.players[0],
                p2: r.players[1],
                t: GolfTheme.dark,
                skinsModules: const [],
                nassauModules: r.betGroups.first.modules,
                oyesModules: const [],
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final txt = _texto(tester);
      expect(txt, contains('2 pedidas más'));
      expect(txt, contains('Presiones desde H12'));
    });
  });
}
