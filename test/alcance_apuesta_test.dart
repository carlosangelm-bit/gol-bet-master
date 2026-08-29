// ─────────────────────────────────────────────────────────────────────────────
// EL ALCANCE DE UNA APUESTA SE DECIDE EN TRES CAMPOS
//
// La pregunta de Carlos: "las establezco para todos, y luego la configuración me
// pregunta otra vez si es entre todos o solo entre Dylan y yo. ¿Qué pasa si le
// pongo al duelo que es Medal entre todos?"
//
// La respuesta, MEDIDA sobre la ronda del 28 de agosto y no leída:
//
//   · No se crea un módulo paralelo. La hoja del duelo guarda sobre el MISMO
//     módulo, así que SOBREESCRIBE la apuesta de la partida.
//   · Acotar un pote de cuatro a un par deja a los otros dos en CERO. El dinero
//     de KAWA pasa de +300 a 0 porque otros dos acotaron la apuesta.
//   · `scope` manda sobre `participantIds`; sin `scope` —rondas viejas— mandan
//     los participantIds. La misma lista significa cosas distintas según exista
//     el campo o no.
//   · `formatMode` no decide QUIÉN juega, solo cómo se reparte entre los que hay.
//
// Y la conexión con las ventajas: un pote con handicap y más de dos jugadores
// necesita un número por jugador, así que mide a todos contra un ancla. Los
// pactos que no tocan al ancla no existen para ese dinero — y eso ahora se dice.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';

final _curso = CourseInfo(name: 'P72', holes: [
  for (int i = 1; i <= 18; i++) CourseHole(hole: i, par: 4, strokeIndex: i),
]);

const _hcp = {'CAM': 13.0, 'AAM': 17.0, 'KAWA': 16.0, 'Dylan': 0.0};
const _gross = {'CAM': 89, 'AAM': 95, 'KAWA': 85, 'Dylan': 97};

Map<int, HoleScore> _sc(String pid, int total) {
  final out = <int, HoleScore>{};
  var falta = total;
  for (int h = 1; h <= 18; h++) {
    final g = (falta / (19 - h)).round();
    out[h] = HoleScore(playerId: pid, hole: h, grossScore: g, putts: 2);
    falta -= g;
  }
  return out;
}

/// Los SEIS pactos de la ronda real. Los tres que no tocan a CAM contradicen a
/// los tres que sí, y por eso ningún ancla puede reproducirlos todos.
const _pactos = {
  'AAM|CAM': 7.0, // AAM recibe 7 de CAM
  'CAM|KAWA': -4.0, // KAWA recibe 4 de CAM
  'CAM|Dylan': -6.0, // Dylan recibe 6 de CAM
  'AAM|KAWA': 4.0, // AAM recibe 4 de KAWA   → implícito 3
  'AAM|Dylan': -5.0, // Dylan recibe 5 de AAM  → implícito al revés
  'Dylan|KAWA': 6.0, // Dylan recibe 6 de KAWA → implícito 2
};

Round _ronda(BetModuleInstance mod, {Map<String, double>? pactos}) => Round(
      id: 'r',
      name: 'R',
      course: _curso,
      isFinished: true,
      players: [
        for (final p in _hcp.keys) Player(id: p, name: p, handicapBase: _hcp[p]!)
      ],
      roundPlayers: [
        for (final p in _hcp.keys)
          RoundPlayer(playerId: p, handicapEnRonda: _hcp[p]!)
      ],
      betGroups: [
        BetGroup(
            id: 'g',
            name: 'G',
            format: PartidaFormat.allInOnePot,
            playerIds: _hcp.keys.toList(),
            modules: [mod])
      ],
      scores: {for (final p in _hcp.keys) p: _sc(p, _gross[p]!)},
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2026, 8, 28),
      totalHoles: 18,
      startingNine: StartingNine.back,
      pairSliding: pactos ?? _pactos,
    );

BetModuleInstance _medal(
        {BetScope? scope,
        BetFormatMode modo = BetFormatMode.onePot,
        List<String> pids = const []}) =>
    BetModuleInstance(
      id: 'm',
      type: BetModuleType.medal,
      name: 'Medal',
      participantIds: pids,
      formatMode: modo,
      scope: scope,
      medalConfig: MedalConfig(value: 100, mode: GrossNetMode.net),
    );

Map<String, double> _balances(Round r) {
  LedgerEngine.invalidateCache();
  return LedgerEngine.playerBalances(r);
}

void main() {
  group('1 · qué pasa si los dos alcances se contradicen', () {
    test('el pote de cuatro: KAWA cobra a los tres', () {
      final b = _balances(_ronda(_medal(scope: const BetScope.everyone())));
      expect(b, {'CAM': -100.0, 'AAM': -100.0, 'KAWA': 300.0, 'Dylan': -100.0});
    });

    test('acotarlo a un par desde el duelo DEJA A LOS OTROS DOS EN CERO', () {
      // Esta es la respuesta a la pregunta: no se ignora, no se duplica —
      // sustituye. Y la sustitución se la comen dos que no estaban en la
      // conversación.
      final b = _balances(_ronda(_medal(scope: BetScope.pair('CAM', 'Dylan'))));
      expect(b['AAM'], 0.0, reason: 'AAM ya no juega el Medal');
      expect(b['KAWA'], 0.0, reason: 'y KAWA pierde sus 300');
      expect(b['CAM'], 100.0);
      expect(b['Dylan'], -100.0);
    });

    test('no se crea un módulo paralelo: sigue habiendo UNO', () {
      // Coincide con la auditoría: la ronda real tiene un solo Medal.
      final r = _ronda(_medal(scope: BetScope.pair('CAM', 'Dylan')));
      expect(r.betGroups.single.modules.length, 1);
    });
  });

  group('2 · la precedencia entre los tres campos', () {
    test('scope MANDA sobre participantIds', () {
      final r = _ronda(_medal(
          scope: const BetScope.everyone(), pids: const ['CAM', 'Dylan']));
      final g = r.betGroups.single;
      expect(r.participantesDe(g.modules.single, g.playerIds).length, 4);
    });

    test('sin scope —rondas viejas— mandan los participantIds', () {
      // La MISMA lista de dos significa lo contrario según exista scope o no.
      // Está documentado en participantesDe porque leyendo una ronda antigua no
      // hay forma de adivinarlo.
      final r = _ronda(_medal(pids: const ['CAM', 'Dylan']));
      final g = r.betGroups.single;
      expect(r.participantesDe(g.modules.single, g.playerIds),
          ['CAM', 'Dylan']);
    });

    test('formatMode no decide QUIÉN juega, solo cómo se reparte', () {
      final pote = _balances(_ronda(_medal(scope: const BetScope.everyone())));
      final todos = _balances(_ronda(_medal(
          scope: const BetScope.everyone(), modo: BetFormatMode.allVsAll)));
      // Los mismos cuatro en los dos casos...
      expect(pote.keys.toSet(), todos.keys.toSet());
      // ...y con ESTOS datos, además, el mismo reparto — porque KAWA le gana a
      // los tres en todos los duelos, así que cobrar el pote y ganar tres duelos
      // dan lo mismo. Es coincidencia de la ronda, no una regla, y conviene que
      // el test lo diga en vez de parecer que el modo da igual.
      expect(pote, todos);
    });

    test('y con otros pactos el modo SÍ cambia el dinero', () {
      // El contrapeso del de arriba: solo los tres pactos con CAM, y entonces
      // los dos modos reparten distinto. Si no, "dan lo mismo" se leería como
      // que formatMode no hace nada.
      const soloConCam = {
        'AAM|CAM': 7.0,
        'CAM|KAWA': -4.0,
        'CAM|Dylan': -6.0,
      };
      final pote = _balances(_ronda(_medal(scope: const BetScope.everyone()),
          pactos: soloConCam));
      final todos = _balances(
          _ronda(
              _medal(
                  scope: const BetScope.everyone(),
                  modo: BetFormatMode.allVsAll),
              pactos: soloConCam));
      expect(pote, isNot(equals(todos)));
      expect(pote['Dylan'], -100.0);
      expect(todos['Dylan'], -300.0);
    });

    test('con dos participantes, pote y todos-contra-todos dan lo mismo', () {
      final a = _balances(_ronda(_medal(scope: BetScope.pair('CAM', 'Dylan'))));
      final b = _balances(_ronda(_medal(
          scope: BetScope.pair('CAM', 'Dylan'),
          modo: BetFormatMode.allVsAll)));
      expect(a, b);
    });
  });

  group('3 · los pactos que el pote no puede honrar se dicen', () {
    test('los tres que no tocan al ancla salen como aviso, con dirección', () {
      final r = _ronda(_medal(scope: const BetScope.everyone()));
      LedgerEngine.invalidateCache();
      final avisos = LedgerEngine.integrityErrors(r);
      expect(avisos.length, 3, reason: 'AAM–KAWA, AAM–Dylan y KAWA–Dylan');
      expect(avisos.join(' '), contains('se mide contra CAM'));
      // La dirección importa: en AAM–Dylan el pacto y el implícito van al revés,
      // y decir solo la cifra lo escondería.
      expect(avisos.join(' '), contains('AAM recibe 1 de Dylan'));
      expect(avisos.join(' '), contains('Dylan recibe 5 de AAM'));
    });

    test('con pactos coherentes NO hay aviso', () {
      // El contrapeso. Con ventajas del directorio salen de diferencias, que son
      // transitivas, y el ancla las reproduce todas.
      final coherentes = {
        'AAM|CAM': 7.0,
        'CAM|KAWA': -4.0,
        'CAM|Dylan': -6.0,
        'AAM|KAWA': 3.0, // 7 − 4
        'AAM|Dylan': 1.0, // 7 − 6
        'Dylan|KAWA': 2.0, // 6 − 4
      };
      final r = _ronda(_medal(scope: const BetScope.everyone()),
          pactos: coherentes);
      LedgerEngine.invalidateCache();
      expect(LedgerEngine.integrityErrors(r), isEmpty);
    });

    test('y un duelo de dos tampoco avisa: ahí no hay ancla', () {
      final r = _ronda(_medal(scope: BetScope.pair('CAM', 'Dylan')));
      LedgerEngine.invalidateCache();
      expect(LedgerEngine.integrityErrors(r), isEmpty);
    });

    test('Nassau en pote NO avisa: reparte par a par y sí honra los pactos', () {
      // Verificado con los asientos de la ronda real: Nassau produce entradas
      // para los seis pares aunque el módulo diga pote. Avisar ahí sería una
      // falsa alarma, y una falsa alarma en un canal de integridad lo apaga.
      final r = _ronda(BetModuleInstance(
        id: 'n',
        type: BetModuleType.nassau,
        name: 'Nassau',
        participantIds: const [],
        formatMode: BetFormatMode.onePot,
        scope: const BetScope.everyone(),
        nassauConfig: const NassauConfig(
            frontValue: 50, backValue: 50, totalValue: 100),
      ));
      LedgerEngine.invalidateCache();
      expect(BetEngine.pactosQueElPoteIgnora(r), isEmpty);
    });
  });
}
