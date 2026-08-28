// ─────────────────────────────────────────────────────────────────────────────
// PUBLICAR NO DEPENDE DE NINGUNA PANTALLA
//
// El fallo, con el dato de producción delante: Carlos cerró una ronda marcada
// para Liga por Score y torneoResultados quedó con CERO documentos, teniendo la
// marca puesta, el seguimiento completo y el nombre entre los inscritos. Todas
// las guardas pasaban. Lo que no pasaba era el código: finishRound() hace
// `_round = null`, eso quita la pestaña Score, la pantalla de captura se
// destruye, y al volver del await `context.mounted` era false.
//
// La pantalla que tenía que publicar la eliminaba la misma acción que disparaba
// la publicación.
//
// Lo que estos tests fijan:
//
//   1 · Publicar ocurre DENTRO de finishRound, sin ningún BuildContext. Un test
//       sin árbol de widgets es la prueba: si dependiera de la pantalla, aquí no
//       podría ni ejecutarse.
//   2 · Cada salida dice algo distinto. Cinco silencios iguales costaron tres
//       entregas de diagnóstico.
//   3 · Lo que falla se encola y se reintenta, y reintentar no duplica.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/torneo.dart';
import 'package:golf_bet_master/models/torneo_seguido.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/services/publicacion_torneo_service.dart';

final _curso = CourseInfo(name: 'C', holes: [
  for (int i = 1; i <= 18; i++) CourseHole(hole: i, par: 4, strokeIndex: i),
]);

Round _ronda({List<String> torneos = const []}) => Round(
      id: 'r1',
      name: 'Ronda de prueba',
      course: _curso,
      players: [
        Player(id: 'yo', name: 'CAV'),
        Player(id: 'otro', name: 'Pepe Pérez'),
      ],
      roundPlayers: [
        RoundPlayer(playerId: 'yo', handicapEnRonda: 10),
        RoundPlayer(playerId: 'otro', handicapEnRonda: 12),
      ],
      betGroups: const [],
      scores: {
        'yo': {1: HoleScore(playerId: 'yo', hole: 1, grossScore: 4, putts: 2)},
        'otro': {
          1: HoleScore(playerId: 'otro', hole: 1, grossScore: 5, putts: 2)
        },
      },
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2026, 8, 28),
      totalHoles: 18,
      torneoIds: torneos,
    );

TorneoSeguido _seguido({
  String torneoId = 'tor_a',
  String token = 'tok',
  String ownerUid = 'uid_org',
  String jugadorNombre = 'Carlos Angel',
}) =>
    TorneoSeguido(
      torneoId: torneoId,
      token: token,
      ownerUid: ownerUid,
      nombre: 'Liga por Score',
      emoji: '🏆',
      desde: DateTime(2026, 8, 24),
      jugadorNombre: jugadorNombre,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('1 · publicar vive dentro de cerrar, no dentro de una pantalla', () {
    test('finishRound publica sin árbol de widgets ni BuildContext', () async {
      // Si esto dependiera de la pantalla, este test no podría existir: no hay
      // pantalla que destruir porque no hay ninguna. Es la prueba estructural.
      final prov = RoundProvider();
      prov.startRound(_ronda(torneos: const ['tor_a', 'tor_b']));

      await prov.finishRound(seguidos: [_seguido()]);

      expect(prov.ultimosEnvios.length, 2,
          reason: 'una frase por torneo marcado, siempre');
      expect(prov.round, isNull, reason: 'y la ronda se cerró igual');
    });

    test('una ronda sin marca no dice nada, y esa ausencia significa una cosa',
        () async {
      // El silencio tiene que tener un solo significado: no estaba marcada.
      final prov = RoundProvider();
      prov.startRound(_ronda());
      await prov.finishRound(seguidos: [_seguido()]);
      expect(prov.ultimosEnvios, isEmpty);
    });

    test('limpiarEnvios permite que la pantalla no lo enseñe dos veces',
        () async {
      final prov = RoundProvider();
      prov.startRound(_ronda(torneos: const ['tor_a']));
      await prov.finishRound(seguidos: [_seguido()]);
      expect(prov.ultimosEnvios, isNotEmpty);
      prov.limpiarEnvios();
      expect(prov.ultimosEnvios, isEmpty);
    });
  });

  group('2 · cada salida dice algo distinto', () {
    test('sin marca: nada que enviar', () async {
      final r = await PublicacionTorneoService.publicar(
          round: _ronda(), misTorneos: const [], seguidos: const []);
      expect(r, isEmpty);
    });

    test('sin sesión lo dice, y no se lo traga', () async {
      // Sin AuthService.uid, que es el estado del harness.
      final r = await PublicacionTorneoService.publicar(
          round: _ronda(torneos: const ['tor_a']),
          misTorneos: const [],
          seguidos: [_seguido()]);
      expect(r.length, 1);
      expect(r.first.enviado, isFalse);
      expect(r.first.motivo, contains('sesión'));
    });

    test('las frases de las tres causas son distinguibles entre sí', () {
      final frases = {
        const EnvioAlTorneo('X', enviado: false, motivo: 'no sigues ese torneo')
            .frase,
        const EnvioAlTorneo('X',
                enviado: false, motivo: 'la referencia no trae el enlace')
            .frase,
        const EnvioAlTorneo('X',
                enviado: false, pendiente: true, motivo: 'PERMISSION_DENIED')
            .frase,
      };
      expect(frases.length, 3, reason: 'tres causas, tres frases');
    });

    test('enviado limpio y enviado con reserva NO se leen igual', () {
      expect(const EnvioAlTorneo('Liga', enviado: true).frase,
          'Resultado enviado a Liga.');
      // El matiz importa: si yo no juego en la ronda, el organizador no puede
      // acreditar mi nombre a ningún jugador y su tabla contará la ronda sin
      // darme nada.
      expect(
          const EnvioAlTorneo('Liga',
                  enviado: true, motivo: 'tú no juegas en esta ronda')
              .frase,
          contains('pero tú no juegas'));
    });

    test('lo que se encola lo dice, en vez de parecer que se perdió', () {
      final f = const EnvioAlTorneo('Liga',
              enviado: false, pendiente: true, motivo: 'sin red')
          .frase;
      expect(f, contains('Queda pendiente'));
      expect(f, contains('se reintenta'));
    });
  });

  group('3 · la cola: que se pueda repetir', () {
    test('arranca vacía y reintentar sin sesión no rompe nada', () async {
      expect(await PublicacionTorneoService.pendientes(), 0);
      expect(await PublicacionTorneoService.nombresPendientes(), isEmpty);
      expect(await PublicacionTorneoService.reintentarPendientes(), 0);
    });

    test('el id del documento es determinista: reintentar ACTUALIZA', () {
      // Es lo que hace que reintentar sea seguro por construcción y no por
      // cuidado. La regla de Firestore exige este id, así que dos intentos de
      // la misma ronda no pueden salir como dos filas.
      const a = ResultadoDeTorneo(
          torneoId: 'tor_a',
          roundId: 'r1',
          token: 'tok',
          torneoOwnerUid: 'uid_org',
          escritoPor: 'uid_yo',
          resultado: {});
      const b = ResultadoDeTorneo(
          torneoId: 'tor_a',
          roundId: 'r1',
          token: 'tok',
          torneoOwnerUid: 'uid_org',
          escritoPor: 'uid_yo',
          jugadorNombre: 'Carlos Angel',
          resultado: {'distinto': true});
      expect(a.docId, b.docId);
      expect(a.docId, 'tor_a_r1');
    });
  });

  group('4 · las guardas, con los valores que tenía la ronda real', () {
    test('el seguimiento de Liga por Score era utilizable', () {
      // Comprobado contra producción: token, ownerUid y jugadorNombre estaban,
      // y el nombre estaba entre los inscritos. Todas las guardas pasaban — por
      // eso el fallo no era el dato.
      expect(_seguido().utilizable, isTrue);
    });

    test('y cada campo que falte deja la referencia inutilizable', () {
      expect(_seguido(token: '').utilizable, isFalse);
      expect(_seguido(ownerUid: '').utilizable, isFalse);
      expect(_seguido(jugadorNombre: '').utilizable, isFalse);
    });

    test('sin sesión NADA se da por bueno, ni siquiera un torneo propio',
        () async {
      // Sin cuenta no se puede escribir en ningún sitio —tampoco en mi propia
      // colección— así que la falta de sesión manda sobre todo lo demás y se
      // dice una vez por torneo marcado. En el harness no hay auth, así que la
      // rama del torneo propio se fija por su frase, arriba.
      final r = await PublicacionTorneoService.publicar(
        round: _ronda(torneos: const ['mio']),
        misTorneos: [
          Torneo(id: 'mio', nombre: 'Liga Viernes', participantes: const [])
        ],
        seguidos: const [],
      );
      expect(r.length, 1);
      expect(r.first.enviado, isFalse);
      expect(r.first.motivo, contains('sesión'));
    });

    test('y la frase del torneo propio dice por qué no hace falta enviarlo', () {
      // Su resultado ya cae en mi colección. El silencio aquí era el que hacía
      // ambigua la ausencia de mensaje.
      final e = const EnvioAlTorneo('Liga Viernes',
          enviado: true, motivo: 'es tu torneo: ya cuenta en tu tabla');
      expect(e.frase, contains('es tu torneo'));
    });
  });
}
