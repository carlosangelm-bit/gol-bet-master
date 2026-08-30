// ─────────────────────────────────────────────────────────────────────────────
// UNA RONDA DE NUEVE HOYOS ES UN CASO NORMAL
//
// Media mañana, nueve hoyos, y a casa. Y la app la trataba como una de dieciocho
// a medias: una ronda de nueve TERMINADA salía en resultados como "9 de 18
// hoyos con score" y EN ROJO, listando como incompletos los hoyos del 10 al 18
// —que no se juegan nunca—.
//
// ── Lo que resultó estar bien, y conviene decirlo ───────────────────────────
//
// Los motores. Nassau ya liquidaba UNA sola apuesta con nueve hoyos, y Medal ya
// contaba solo los hoyos con score. Nunca liquidaron de más.
//
// Lo que estaba mal era QUIEN CONTABA: tenía a mano `round.course.holes`, que
// son los del CAMPO, y el campo tiene dieciocho siempre.
//
// Y el daño no es el número: es que el rojo de las alarmas se gastó en algo que
// no pasaba. Es el mismo criterio que separó los avisos informativos de
// integrityErrors.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';
import 'package:golf_bet_master/models/models.dart';

final _curso = CourseInfo(name: 'P72', holes: [
  for (var i = 1; i <= 18; i++) CourseHole(hole: i, par: 4, strokeIndex: i),
]);

/// Una ronda de [totalHoles] hoyos con los dos jugadores anotando TODOS los que
/// se juegan. O sea: completa.
Round _ronda({
  int totalHoles = 9,
  StartingNine inicio = StartingNine.front,
  List<int> ganaA = const [1, 2],
  List<BetModuleInstance> modulos = const [],
}) {
  final orden = inicio == StartingNine.back
      ? [...List.generate(9, (i) => i + 10), ...List.generate(9, (i) => i + 1)]
      : List.generate(18, (i) => i + 1);
  final jugados = orden.take(totalHoles).toSet();

  int golpe(String p, int h) {
    if (ganaA.contains(h)) return p == 'A' ? 4 : 5;
    return 4;
  }

  return Round(
    id: 'r',
    name: 'Nueve de la mañana',
    course: _curso,
    isFinished: true,
    players: [Player(id: 'A', name: 'A'), Player(id: 'B', name: 'B')],
    roundPlayers: [
      RoundPlayer(playerId: 'A', handicapEnRonda: 0),
      RoundPlayer(playerId: 'B', handicapEnRonda: 0),
    ],
    betGroups: modulos.isEmpty
        ? const []
        : [
            BetGroup(
                id: 'g',
                name: 'G',
                format: PartidaFormat.allInOnePot,
                playerIds: const ['A', 'B'],
                modules: modulos)
          ],
    scores: {
      for (final p in ['A', 'B'])
        p: {
          for (final h in jugados)
            h: HoleScore(playerId: p, hole: h, grossScore: golpe(p, h), putts: 2)
        }
    },
    events: const {},
    oyeseRankings: const {},
    sliding: const [],
    createdAt: DateTime(2026, 8, 30),
    totalHoles: totalHoles,
    startingNine: inicio,
  );
}

BetModuleInstance _nassau() => const BetModuleInstance(
      id: 'n',
      type: BetModuleType.nassau,
      name: 'Nassau',
      participantIds: ['A', 'B'],
      nassauConfig:
          NassauConfig(frontValue: 50, backValue: 50, totalValue: 100),
    );

List<LedgerEntry> _asientos(Round r) {
  LedgerEngine.invalidateCache();
  return LedgerEngine.entriesOf(r);
}

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('1 · los hoyos que la ronda JUEGA', () {
    test('CLAVE: nueve, no dieciocho', () {
      // Es la cuenta que estaba mal. `round.course.holes` son los del campo.
      final s = BetEngine.segmentsOf(_ronda());
      expect(s.singleNine, isTrue);
      expect(s.hoyosEnJuego, hasLength(9));
      expect(s.hoyosEnJuego, List.generate(9, (i) => i + 1));
    });

    test('CLAVE: y los que no se juegan NO están', () {
      // De aquí salía "Hoyos incompletos: 10, 11, 12…".
      final s = BetEngine.segmentsOf(_ronda());
      for (final h in [10, 11, 12, 13, 14, 15, 16, 17, 18]) {
        expect(s.hoyosEnJuego.contains(h), isFalse, reason: 'hoyo $h');
      }
    });

    test('saliendo por el 10, los nueve son del 10 al 18', () {
      final s = BetEngine.segmentsOf(_ronda(inicio: StartingNine.back));
      expect(s.hoyosEnJuego, List.generate(9, (i) => i + 10));
    });

    test('CONTRAPESO: en una ronda de 18 siguen siendo los dieciocho', () {
      // Sin esto, un `hoyosEnJuego => firstNine` fijo pasaría todo lo de arriba
      // y las rondas completas dejarían de contar la vuelta.
      final s = BetEngine.segmentsOf(_ronda(totalHoles: 18));
      expect(s.singleNine, isFalse);
      expect(s.hoyosEnJuego, hasLength(18));
    });

    test('y playOrder sigue siendo los DIECIOCHO del campo', () {
      // Son dos preguntas distintas y las dos hacen falta: el orden de juego
      // del campo, y los hoyos de esta ronda.
      expect(BetEngine.segmentsOf(_ronda()).playOrder, hasLength(18));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('2 · una ronda de nueve terminada está COMPLETA', () {
    /// La cuenta que hace la pantalla de resultados, con los hoyos de la ronda.
    (int completos, int total, List<int> huecos) cobertura(Round r) {
      final holes = BetEngine.segmentsOf(r).hoyosEnJuego;
      final pids = ['A', 'B'];
      final completos = holes
          .where((h) => pids.every((p) => r.getScore(p, h).hasScore))
          .length;
      final huecos = holes
          .where((h) => !pids.every((p) => r.getScore(p, h).hasScore))
          .toList();
      return (completos, holes.length, huecos);
    }

    test('CLAVE: nueve de nueve, y sin huecos', () {
      // Es el reporte, al revés: decía "9 de 18" y listaba nueve huecos.
      final (c, t, huecos) = cobertura(_ronda());
      expect(c, 9);
      expect(t, 9);
      expect(huecos, isEmpty, reason: 'no falta ni un hoyo');
    });

    test('CONTRAPESO: y si de verdad falta uno, se sigue viendo', () {
      // Sin esto, contar solo los hoyos con score daría siempre "completa" y
      // el aviso no serviría para nada.
      final r = _ronda();
      final sinUno = {
        for (final e in r.scores.entries)
          e.key: {
            for (final h in e.value.entries)
              if (!(e.key == 'B' && h.key == 5)) h.key: h.value
          }
      };
      final parcial = Round(
        id: r.id, name: r.name, course: r.course, isFinished: true,
        players: r.players, roundPlayers: r.roundPlayers,
        betGroups: r.betGroups, scores: sinUno, events: const {},
        oyeseRankings: const {}, sliding: const [],
        createdAt: r.createdAt, totalHoles: 9,
      );
      final (c, t, huecos) = cobertura(parcial);
      expect(c, 8);
      expect(t, 9);
      expect(huecos, [5]);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('3 · el Nassau en nueve hoyos', () {
    test('CLAVE: UNA apuesta, no tres', () {
      // El motor ya lo hacía. Lo que faltaba era decirlo.
      final asientos = _asientos(_ronda(modulos: [_nassau()]))
          .where((e) => e.betType == BetModuleType.nassau)
          .toList();
      expect(asientos, hasLength(1));
      expect(asientos.first.reason, contains('9 hoyos'));
      expect(asientos.first.amount, 50);
    });

    test('CONTRAPESO: y con dieciocho siguen siendo tres', () {
      // Con un ganador en CADA vuelta: si solo gana la ida, la vuelta empata y
      // no paga — que es correcto, y haría que esta prueba contara dos.
      final razones = _asientos(_ronda(
              totalHoles: 18,
              ganaA: const [1, 2, 10, 11],
              modulos: [_nassau()]))
          .where((e) => e.betType == BetModuleType.nassau)
          .map((e) => e.reason)
          .toList();
      expect(razones, hasLength(3));
      expect(razones.any((r) => r.contains('Total 18')), isTrue);
    });

    test('CLAVE: y el catálogo LO DICE', () {
      // Quien pacta un Nassau espera tres apuestas. Que el motor haga lo
      // correcto no sirve si la pantalla promete otra cosa.
      expect(BetModuleType.nassau.enNueveHoyos, isNotNull);
      expect(BetModuleType.nassau.enNueveHoyos, contains('Una sola apuesta'));
      expect(BetModuleType.nassau.description, contains('9 hoyos'));
    });

    test('y los formatos que no cambian dicen que no cambian', () {
      // Null es una respuesta: "se juega igual". Rellenarlos todos con una
      // frase habría dado ruido en vez de información.
      expect(BetModuleType.skins.enNueveHoyos, isNull);
      expect(BetModuleType.medal.enNueveHoyos, isNull);
    });

    test('CONTRAPESO: no todos los formatos dicen lo mismo', () {
      // Sin esto, una frase única para todos pasaría la prueba de arriba.
      final frases = BetModuleType.values
          .map((t) => t.enNueveHoyos)
          .whereType<String>()
          .toSet();
      expect(frases.length, greaterThan(1));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 4 · CAMBIAR LA DURACIÓN DESPUÉS
  //
  // La pregunta era si hay que reajustar las apuestas al pasar de 18 a 9. La
  // respuesta es que no hay nada que reajustar, y es por diseño: los segmentos
  // se DERIVAN de la ronda en cada cálculo, no se guardan en el módulo.
  //
  // Es la misma regla que rige las tablas de torneo y la serie del handicap: lo
  // guardado se queda viejo en silencio.
  // ───────────────────────────────────────────────────────────────────────────
  group('4 · la duración se lee al calcular, no se guarda', () {
    test('CLAVE: el MISMO módulo liquida distinto según la ronda', () {
      final mod = _nassau();
      final nueve = _asientos(_ronda(totalHoles: 9, modulos: [mod]))
          .where((e) => e.betType == BetModuleType.nassau);
      final dieciocho = _asientos(_ronda(
              totalHoles: 18,
              ganaA: const [1, 2, 10, 11],
              modulos: [mod]))
          .where((e) => e.betType == BetModuleType.nassau);
      expect(nueve, hasLength(1));
      expect(dieciocho, hasLength(3));
    });

    test('y el módulo no guarda ninguna duración que se pueda quedar vieja', () {
      // Si la guardara, cambiar la ronda de 18 a 9 dejaría el módulo diciendo
      // 18 para siempre, y haría falta un `_sincronizarModulos` con su
      // precedencia. No hace falta porque no hay nada que sincronizar.
      final json = _nassau().toJson().toString();
      for (final sospechoso in ['totalHoles', 'holes', 'duracion']) {
        expect(json.contains(sospechoso), isFalse, reason: sospechoso);
      }
    });
  });
}
