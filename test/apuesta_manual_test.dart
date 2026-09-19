// ─────────────────────────────────────────────────────────────────────────────
// APUESTAS MANUALES
//
//     «Crear una apuesta con el mecanismo que ya tienes —bote o todos vs todos,
//      monto, quiénes juegan—. Estoy pensando en grupos que apuestan cosas
//      raras que no vamos a meter a la app, como fairways, green en regulation.»
//
// Un TIPO del catálogo, no un motor paralelo: el nombre es un dato de la
// instancia, así que «Fairways» y «Green en regulación» son dos apuestas del
// mismo tipo. Añadirlo al enum hizo que el analizador señalara los VEINTE
// switch exhaustivos que tenían algo que decir — que es justo para lo que
// están, y lo que un motor aparte no habría pedido.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/providers/round_provider.dart'
    show roundToJson, roundFromJson;

final _curso = CourseInfo(name: 'P72', holes: [
  for (int i = 1; i <= 18; i++) CourseHole(hole: i, par: 4, strokeIndex: i),
]);

const _cinco = ['cam', 'kawa', 'jose', 'aam', 'rich'];

BetModuleInstance _manual(
        {required String id,
        required String nombre,
        required ModoManual modo,
        double valor = 50}) =>
    BetModuleInstance(
      id: id,
      type: BetModuleType.manual,
      name: nombre,
      participantIds: _cinco,
      formatMode: BetFormatMode.allVsAll,
      manualConfig:
          ManualConfig(nombre: nombre, modo: modo, value: valor),
    );

Round _ronda({
  required List<BetModuleInstance> modulos,
  Map<String, Map<int, List<String>>> marcas = const {},
}) =>
    Round(
      id: 'r',
      name: 'Hoy',
      course: _curso,
      isFinished: false,
      players: [for (final p in _cinco) Player(id: p, name: p.toUpperCase())],
      roundPlayers: [
        for (final p in _cinco) RoundPlayer(playerId: p, handicapEnRonda: 0),
      ],
      betGroups: [
        BetGroup(
            id: 'g',
            name: 'G',
            format: PartidaFormat.oneVsOne,
            playerIds: _cinco,
            modules: modulos)
      ],
      scores: {
        for (final p in _cinco)
          p: {
            for (int h = 1; h <= 18; h++)
              h: HoleScore(playerId: p, hole: h, grossScore: 4, putts: 2)
          }
      },
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      manuales: marcas,
      createdAt: DateTime(2026, 9, 20),
      totalHoles: 18,
    );

List<LedgerEntry> _asientos(Round r) {
  LedgerEngine.invalidateCache();
  return LedgerEngine.entriesOf(r);
}

/// Lo que CAM cobra (o paga) en total.
double _deCam(Round r) => _asientos(r).fold(
    0.0,
    (s, e) => s +
        (e.toPlayerId == 'cam'
            ? e.amount
            : e.fromPlayerId == 'cam'
                ? -e.amount
                : 0));

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  group('1 · sí/no: gana quien más tenga', () {
    // CAM pega 3 fairways, KAWA 1, los demás ninguno.
    final marcas = {
      'fw': {
        1: ['cam', 'kawa'],
        2: ['cam'],
        3: ['cam'],
      }
    };
    final r = _ronda(
        modulos: [
          _manual(id: 'fw', nombre: 'Fairways', modo: ModoManual.siNo)
        ],
        marcas: marcas);

    test('CLAVE (criterio 1): la apuesta lleva el nombre del grupo', () {
      final e = _asientos(r);
      expect(e, isNotEmpty);
      expect(e.every((x) => x.reason.startsWith('Fairways')), isTrue);
      expect(e.first.betType, BetModuleType.manual);
    });

    test('CLAVE (criterio 5): liquida por diferencia, como Putts', () {
      // CAM 3 · KAWA 1 · los otros tres 0 → CAM gana los cuatro duelos.
      expect(_deCam(r), 4 * 50);
      // Y KAWA gana los tres suyos contra los que tienen cero.
      final kawa = _asientos(r).fold<double>(
          0,
          (s, e) => s +
              (e.toPlayerId == 'kawa'
                  ? e.amount
                  : e.fromPlayerId == 'kawa'
                      ? -e.amount
                      : 0));
      expect(kawa, 3 * 50 - 50);
    });

    test('CONTRAPESO: un empate no mueve dinero', () {
      // Los cinco a cero: no es un cálculo fallido, es que quedaron igual.
      expect(_asientos(_ronda(modulos: [
        _manual(id: 'fw', nombre: 'Fairways', modo: ModoManual.siNo)
      ])), isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('2 · sí/no invertido: el mismo motor con el signo cambiado', () {
    test('CLAVE (criterio 3): gana quien MENOS tenga', () {
      final marcas = {
        'pen': {
          1: ['cam', 'kawa'],
          2: ['cam'],
          3: ['cam'],
        }
      };
      final normal = _ronda(
          modulos: [
            _manual(id: 'pen', nombre: 'Penaltis', modo: ModoManual.siNo)
          ],
          marcas: marcas);
      final invertido = _ronda(
          modulos: [
            _manual(
                id: 'pen',
                nombre: 'Penaltis',
                modo: ModoManual.siNoInvertido)
          ],
          marcas: marcas);

      // Exactamente el mismo dinero, del otro lado.
      expect(_deCam(normal), 200);
      expect(_deCam(invertido), -200);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('3 · ranking: paga por diferencia de posición, como Oyes', () {
    test('CLAVE (criterio 4): en un hoyo de tres, el 1º cobra dos veces', () {
      final r = _ronda(
          modulos: [
            _manual(id: 'drive', nombre: 'Drive más largo', modo: ModoManual.ranking)
          ],
          marcas: {
            'drive': {
              7: ['cam', 'kawa', 'jose'],
            }
          });
      final e = _asientos(r);
      expect(e, hasLength(3), reason: '1º-2º, 1º-3º y 2º-3º');
      expect(_deCam(r), 100, reason: 'cobra de KAWA y de JOSE');
      // Y el motivo dice el hoyo y las posiciones, como «Oyés H3 (1° vs 2°)».
      expect(e.map((x) => x.reason),
          contains('Drive más largo H7 (1° vs 2°)'));
    });

    test('CONTRAPESO: quien no está marcado en ese hoyo no entra', () {
      // Contarlo como último sería inventarle una posición que nadie puso.
      final r = _ronda(
          modulos: [
            _manual(id: 'drive', nombre: 'Drive', modo: ModoManual.ranking)
          ],
          marcas: {
            'drive': {
              7: ['cam', 'kawa'],
            }
          });
      expect(_asientos(r), hasLength(1));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('4 · dos manuales a la vez, que es el caso real', () {
    test('CLAVE: fairways y green en regulación no se mezclan', () {
      // La clave de las marcas es el id del MÓDULO, no el tipo: si fuera el
      // tipo, las dos apuestas compartirían marcas y cobrarían lo mismo.
      final r = _ronda(modulos: [
        _manual(id: 'fw', nombre: 'Fairways', modo: ModoManual.siNo),
        _manual(id: 'gir', nombre: 'Green en regulación', modo: ModoManual.siNo),
      ], marcas: {
        'fw': {
          1: ['cam']
        },
        'gir': {
          1: ['kawa']
        },
      });
      final motivos = _asientos(r).map((e) => e.reason).toSet();
      expect(motivos.any((m) => m.startsWith('Fairways')), isTrue);
      expect(motivos.any((m) => m.startsWith('Green en regulación')), isTrue);
      // CAM gana los cuatro de fairways y pierde uno de GIR.
      expect(_deCam(r), 4 * 50 - 50);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('5 · sobrevive al guardado', () {
    test('CLAVE: la config y las marcas van y vuelven', () {
      final r = _ronda(
          modulos: [
            _manual(
                id: 'fw',
                nombre: 'Fairways',
                modo: ModoManual.siNoInvertido,
                valor: 25)
          ],
          marcas: {
            'fw': {
              1: ['cam', 'kawa'],
              9: ['jose'],
            }
          });
      final vuelta = roundFromJson(roundToJson(r));
      final cfg = vuelta.betGroups.first.modules.first.manual;
      expect(cfg.nombre, 'Fairways');
      expect(cfg.modo, ModoManual.siNoInvertido);
      expect(cfg.value, 25);
      expect(vuelta.marcadosEn('fw', 1), ['cam', 'kawa']);
      expect(vuelta.marcadosEn('fw', 9), ['jose']);
      // Y el dinero es el mismo después de ir y volver.
      expect(_deCam(vuelta), _deCam(r));
    });

    test('CONTRAPESO: una ronda sin manuales no escribe el campo', () {
      final j = roundToJson(_ronda(modulos: const []));
      expect(j.containsKey('manuales'), isFalse);
    });
  });
}
