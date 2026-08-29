// ─────────────────────────────────────────────────────────────────────────────
// UN HOYO SIN CAPTURAR QUE SE LEÍA COMO CAPTURADO
//
// El reporte: con el F9 "completo y empatado", ni CARRY ni APERTURA 2ª VUELTA
// salían, y la cabecera decía 8/18.
//
// No había score perdido. La captura enseñaba el PAR en gris como pista de por
// dónde empiezan el − y el +, y al lado el chip del acumulado decía "E" —el
// jugador iba a la par en los hoyos que sí tenía—. Las dos cosas juntas se leen
// como "hoyo hecho en par". El hoyo 4 de Luis nunca se capturó.
//
// Así que el fallo era doble, y ninguno era el que parecía:
//
//   · La captura enseñaba un número donde no había dato. Ahora enseña un guion.
//   · Los dos bloques desaparecían sin decir por qué. Ahora se dice qué falta,
//     con los hoyos.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/screens/scorecard/scorecard_screen.dart';

final _curso = CourseInfo(name: 'P72', holes: [
  for (int i = 1; i <= 18; i++) CourseHole(hole: i, par: 4, strokeIndex: i),
]);

/// Ronda con [hasta] hoyos capturados, saltándose [sinCapturar] para 'B'.
Round _r({int hasta = 10, List<int> sinCapturar = const []}) => Round(
      id: 'r',
      name: 'R',
      course: _curso,
      players: [Player(id: 'A', name: 'A'), Player(id: 'B', name: 'B')],
      roundPlayers: [
        RoundPlayer(playerId: 'A', handicapEnRonda: 0),
        RoundPlayer(playerId: 'B', handicapEnRonda: 0),
      ],
      betGroups: const [],
      scores: {
        for (final p in ['A', 'B'])
          p: {
            for (int h = 1; h <= hasta; h++)
              if (!(p == 'B' && sinCapturar.contains(h)))
                h: HoleScore(playerId: p, hole: h, grossScore: 4, putts: 2)
          }
      },
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2026, 8, 29),
      totalHoles: 18,
    );

void main() {
  group('qué hoyos faltan del primer nueve', () {
    test('con el F9 completo no falta ninguno', () {
      expect(hoyosQueFaltanDelPrimerNueve(_r(), 'A', 'B'), isEmpty);
    });

    test('el hoyo que le falta a UNO de los dos cuenta como que falta', () {
      // Es la situación exacta del reporte: A lo tiene, B no.
      final r = _r(sinCapturar: const [4]);
      expect(hoyosQueFaltanDelPrimerNueve(r, 'A', 'B'), [4]);
    });

    test('y los nombra todos, para no tener que buscarlos', () {
      final r = _r(sinCapturar: const [2, 4, 7]);
      expect(hoyosQueFaltanDelPrimerNueve(r, 'A', 'B'), [2, 4, 7]);
    });

    test('a mitad del F9 faltan los que aún no se juegan', () {
      // El aviso no se enseña aquí —solo tiene sentido en la 2ª vuelta— pero la
      // cuenta es la misma y conviene que sea honesta.
      final r = _r(hasta: 5);
      expect(hoyosQueFaltanDelPrimerNueve(r, 'A', 'B'), [6, 7, 8, 9]);
    });
  });

  group('el placeholder de la captura', () {
    test('un hoyo sin score NO tiene score, por mucho que se pinte el par', () {
      // La prueba de que no había dato perdido: el modelo siempre lo supo.
      final r = _r(sinCapturar: const [4]);
      expect(r.getScore('B', 4).hasScore, isFalse);
      expect(r.getScore('A', 4).hasScore, isTrue);
    });

    test('y el acumulado ignora el hoyo sin capturar, que es lo correcto', () {
      // Por eso el chip decía "E": B iba a la par en los ocho que sí tenía. El
      // chip no mentía; mentía leerlo como el score del hoyo.
      final r = _r(sinCapturar: const [4]);
      var golpes = 0, hoyos = 0;
      for (int h = 1; h <= 9; h++) {
        final s = r.getScore('B', h);
        if (!s.hasScore) continue;
        golpes += s.grossScore!;
        hoyos++;
      }
      expect(hoyos, 8, reason: '8 de 9, que es lo que decía la cabecera');
      expect(golpes, 32);
    });
  });
}
