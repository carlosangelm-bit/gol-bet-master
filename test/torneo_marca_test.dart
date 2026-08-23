// ─────────────────────────────────────────────────────────────────────────────
// LA MARCA DE TORNEO — cuenta la ronda que se marcó, no la que caiga en un rango
//
// La fuente por fechas arrastraba todo lo jugado entre dos días: rondas de otros
// grupos, rondas de prueba, rondas que nadie inscribió. Con marca explícita, un
// torneo cuenta lo que se dijo que contaba al configurar la ronda.
//
// Lo que se prueba aquí, y por qué cada cosa:
//
//   1 · la marca sobrevive el viaje Round → RoundResult → torneo. Es el camino
//       completo; si se rompe en medio, el torneo se queda a cero en silencio
//   2 · la fuente por fechas está retirada pero NO derogada: un torneo guardado
//       con ella sigue contando igual. Es el patrón de Match+Press
//   3 · qué enlaces se republican al cerrar, con las tres condiciones sueltas
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/round_result.dart';
import 'package:golf_bet_master/models/torneo.dart';
import 'package:golf_bet_master/providers/round_provider.dart';

const ana = 'pid_7f3a91', beto = 'pid_2c5e08';

CourseInfo _course() => CourseInfo(
    name: 'Los Encinos',
    holes: List.generate(
        18, (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)));

Round _round({List<String> torneoIds = const [], String id = 'r1', int dia = 5}) {
  final ps = [ana, beto]
      .map((i) => Player(id: i, name: i.toUpperCase()))
      .toList();
  return Round(
    id: id,
    name: 'Sábado',
    course: _course(),
    players: ps,
    roundPlayers:
        ps.map((p) => RoundPlayer(playerId: p.id, handicapEnRonda: 0)).toList(),
    betGroups: [
      BetGroup(
          id: 'grp',
          name: 'G',
          format: PartidaFormat.oneVsOne,
          playerIds: [ana, beto],
          modules: [
            BetModuleInstance.defaultFor(BetModuleType.skins, [ana, beto],
                id: 'sk')
          ]),
    ],
    scores: {
      for (final p in [ana, beto])
        p: {
          for (var h = 1; h <= 18; h++)
            h: HoleScore(playerId: p, hole: h, grossScore: p == ana ? 4 : 5),
        },
    },
    events: const {},
    oyeseRankings: const {},
    sliding: const [],
    createdAt: DateTime(2026, 3, dia),
    totalHoles: 18,
    isFinished: true,
    torneoIds: torneoIds,
  );
}

Torneo _t({
  String id = 'tor_1',
  FuenteDeRondas fuente = FuenteDeRondas.marcadas,
  String? token,
  bool cerrado = false,
  List<String> participantes = const [ana, beto],
  DateTime? desde,
  DateTime? hasta,
}) =>
    Torneo(
      id: id,
      nombre: 'Copa',
      fuente: fuente,
      metodo: MetodoDePuntuacion.dinero,
      acumulacion: Acumulacion.sumaSimple,
      participantes: participantes,
      tokenCompartido: token,
      cerrado: cerrado,
      desde: desde,
      hasta: hasta,
    );

void main() {
  group('1 · la marca llega desde la configuración hasta la tabla', () {
    test('el default es marcadas: un torneo nuevo no arrastra por fechas', () {
      expect(_t().fuente, FuenteDeRondas.marcadas);
      // Y sin marca no cuenta nada, aunque haya rondas jugadas.
      final sinMarca = RoundResult.fromRound(_round());
      expect(rondasDelTorneo(_t(), [sinMarca]), isEmpty);
    });

    test('la marca sobrevive Round → RoundResult → rondasDelTorneo', () {
      final marcada = RoundResult.fromRound(_round(torneoIds: const ['tor_1']));
      expect(marcada.torneoIds, ['tor_1']);
      expect(rondasDelTorneo(_t(), [marcada]).map((r) => r.roundId), ['r1']);
    });

    test('cuenta para un torneo y no para el otro', () {
      final r = RoundResult.fromRound(_round(torneoIds: const ['tor_1']));
      expect(rondasDelTorneo(_t(id: 'tor_1'), [r]), hasLength(1));
      expect(rondasDelTorneo(_t(id: 'tor_2'), [r]), isEmpty);
    });

    test('una ronda puede contar para dos torneos a la vez', () {
      // La liga de la temporada y la copa del sábado son el mismo golf.
      final r = RoundResult.fromRound(
          _round(torneoIds: const ['tor_1', 'tor_2']));
      expect(rondasDelTorneo(_t(id: 'tor_1'), [r]), hasLength(1));
      expect(rondasDelTorneo(_t(id: 'tor_2'), [r]), hasLength(1));
    });

    test('la marca viaja en el JSON de la ronda, y solo si hay algo', () {
      final con = roundToJson(_round(torneoIds: const ['tor_1']));
      expect(con['torneoIds'], ['tor_1']);
      expect(roundFromJson(con).torneoIds, ['tor_1']);
      // Sin marca no se escribe el campo: una ronda normal no engorda.
      expect(roundToJson(_round()).containsKey('torneoIds'), isFalse);
      expect(roundFromJson(roundToJson(_round())).torneoIds, isEmpty);
    });

    test('la marca viaja en el JSON del RoundResult', () {
      final res = RoundResult.fromRound(_round(torneoIds: const ['tor_1']));
      final ida = RoundResult.fromJson(res.toJson());
      expect(ida.torneoIds, ['tor_1']);
      // Y un resultado viejo, escrito antes de que el campo existiera, se lee
      // sin marcas en vez de reventar.
      final viejo = Map<String, dynamic>.from(res.toJson())
        ..remove('torneoIds');
      expect(RoundResult.fromJson(viejo).torneoIds, isEmpty);
    });

    test('las fechas no filtran la fuente por marcas', () {
      // Se marcó, así que cuenta: da igual que caiga fuera del rango que el
      // torneo tuviera puesto de antes.
      final r = RoundResult.fromRound(
          _round(torneoIds: const ['tor_1'], dia: 5));
      final t = _t(desde: DateTime(2026, 6, 1), hasta: DateTime(2026, 6, 30));
      expect(rondasDelTorneo(t, [r]), hasLength(1));
    });
  });

  group('2 · la fuente por fechas: retirada, no derogada', () {
    test('no se ofrece, pero sigue en el enum', () {
      expect(fuentesOfrecibles, isNot(contains(FuenteDeRondas.rango)));
      expect(FuenteDeRondas.values, contains(FuenteDeRondas.rango));
      expect(FuenteDeRondas.rango.seOfrece, isFalse);
      for (final f in fuentesOfrecibles) {
        expect(f.seOfrece, isTrue);
        expect(f.motivoRetirada, isNull);
      }
    });

    test('la retirada explica qué hacer en su lugar', () {
      final motivo = FuenteDeRondas.rango.motivoRetirada;
      expect(motivo, isNotNull);
      // Nombra las dos salidas. Un aviso que solo dice "ya no vale" deja al
      // dueño del torneo sin saber a qué cambiar.
      expect(motivo, contains('Marcadas'));
      expect(motivo, contains('mano'));
    });

    test('un torneo guardado con fechas sigue contando por fechas', () {
      // Es el caso de la Copa CGM 2026, que ya existe con este ajuste. Retirar
      // la opción no puede vaciarle la tabla.
      // fromRound no adivina la fecha: se le pasa la de la ronda.
      final r = RoundResult.fromRound(_round(dia: 5),
          playedAt: DateTime(2026, 3, 5)); // sin marca ninguna
      final viejo = _t(
          fuente: FuenteDeRondas.rango,
          desde: DateTime(2026, 3, 1),
          hasta: DateTime(2026, 3, 31));
      expect(rondasDelTorneo(viejo, [r]), hasLength(1));
    });

    test('el aviso de arrastre solo sale donde puede arrastrar', () {
      // Con marcas no hay arrastre posible: cuenta lo que se marcó. Dejar el
      // aviso ahí sería ruido permanente.
      // El aviso pide gente de sobra y sin inscribir, que es cuando el rango
      // ha arrastrado lo que no era. Los resultados van a mano: hacen falta
      // doce jugadores y la ronda de este archivo solo tiene dos.
      final gente = [for (var i = 0; i < 12; i++) 'pid_x$i'];
      final rs = [
        for (var i = 1; i <= 30; i++)
          RoundResult(
            roundId: 'r$i',
            roundName: 'R$i',
            courseName: 'Los Encinos',
            playedAt: DateTime(2026, 3, 1 + i % 28),
            holesPlayed: 18,
            playerIds: gente,
            playerNames: {for (final g in gente) g: g},
            balances: {for (final g in gente) g: 10},
            pairBalances: const {},
            grossByPlayer: const {},
            netByPlayer: const {},
            stablefordByPlayer: const {},
            bettingGroupIds: const [],
            torneoIds: const ['tor_1'],
          ),
      ];
      final conMarcas = _t(participantes: const []);
      expect(avisoDeArrastre(conMarcas, tablaDe(conMarcas, rs)), isNull);
      final porFechas =
          _t(fuente: FuenteDeRondas.rango, participantes: const []);
      expect(avisoDeArrastre(porFechas, tablaDe(porFechas, rs)), isNotNull);
    });
  });

  group('3 · qué torneos se ofrecen al configurar la ronda', () {
    test('los abiertos que miran la marca, y nada más', () {
      final lista = [
        _t(id: 'tor_1'),
        _t(id: 'tor_2', cerrado: true),
        _t(id: 'tor_3', fuente: FuenteDeRondas.rango),
        _t(id: 'tor_4', fuente: FuenteDeRondas.manual),
        _t(id: 'tor_5'),
      ];
      expect(torneosMarcables(lista).map((t) => t.id), ['tor_1', 'tor_5']);
    });

    test('sin torneos marcables la lista sale vacía, y el bloque no aparece',
        () {
      expect(torneosMarcables(const []), isEmpty);
      expect(torneosMarcables([_t(cerrado: true)]), isEmpty);
    });
  });

  group('4 · qué enlaces se refrescan al cerrar la ronda', () {
    final publicado = _t(token: 'tok_abc');

    test('el torneo marcado y compartido se republica', () {
      final r = _round(torneoIds: const ['tor_1']);
      expect(torneosARepublicar(r, [publicado]).map((t) => t.id), ['tor_1']);
    });

    test('sin marca no se toca nada: la tabla no cambió', () {
      expect(torneosARepublicar(_round(), [publicado]), isEmpty);
    });

    test('sin enlace no se crea uno: publicar es una decisión', () {
      final r = _round(torneoIds: const ['tor_1']);
      expect(torneosARepublicar(r, [_t()]), isEmpty);
    });

    test('un torneo cerrado no se vuelve a publicar', () {
      final r = _round(torneoIds: const ['tor_1']);
      expect(torneosARepublicar(r, [_t(token: 'tok_abc', cerrado: true)]),
          isEmpty);
    });

    test('si la fuente no mira la marca, cerrar no mueve la tabla', () {
      final r = _round(torneoIds: const ['tor_1']);
      final porFechas = _t(token: 'tok_abc', fuente: FuenteDeRondas.rango);
      expect(torneosARepublicar(r, [porFechas]), isEmpty);
    });

    test('se republican los dos torneos de una ronda doble', () {
      final r = _round(torneoIds: const ['tor_1', 'tor_2']);
      final lista = [
        _t(id: 'tor_1', token: 'tok_1'),
        _t(id: 'tor_2', token: 'tok_2'),
        _t(id: 'tor_3', token: 'tok_3'), // no marcado
      ];
      expect(torneosARepublicar(r, lista).map((t) => t.id),
          ['tor_1', 'tor_2']);
    });
  });
}
