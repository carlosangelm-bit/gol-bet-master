// Cubre la comparación de nombres del fallback de GolfCourseService.
//
// Contexto: golfcourseapi.com migró sus IDs de numéricos a alfanuméricos, así
// que los favoritos guardados con el ID viejo dan 404 y se recuperan buscando
// por nombre. Ese fallback tomaba `results.first` sin comparar nada, y la
// búsqueda de la API es muy laxa — comprobado en vivo: "Club de Golf" devuelve
// 25 resultados encabezados por "Tajin Club De Golf".
//
// Cargar el campo equivocado no es un fallo visible: el campo aporta el par y
// el stroke index de cada hoyo, o sea la base del cálculo de ventajas. La ronda
// entera saldría mal sin ninguna señal. De ahí que la regla sea coincidencia
// exacta (normalizada) o excepción.

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/services/golf_course_service.dart';

void main() {
  group('normalizeClubName', () {
    test('ignora mayúsculas', () {
      expect(
        GolfCourseService.normalizeClubName('CLUB DE GOLF MEXICO'),
        GolfCourseService.normalizeClubName('club de golf mexico'),
      );
    });

    test('ignora acentos — la API los escribe sin ellos', () {
      expect(
        GolfCourseService.normalizeClubName('Club de Golf México'),
        GolfCourseService.normalizeClubName('Club De Golf Mexico'),
      );
    });

    test('ignora puntuación y espacios de sobra', () {
      expect(
        GolfCourseService.normalizeClubName('  Club-de  Golf, Mexico.  '),
        GolfCourseService.normalizeClubName('Club de Golf Mexico'),
      );
    });

    test('la ñ se normaliza a n', () {
      expect(GolfCourseService.normalizeClubName('Peña Blanca'), 'pena blanca');
    });

    test('NO colapsa clubes distintos que comparten palabras', () {
      // El caso real que rompía: buscar "Club de Golf" traía "Tajin Club De
      // Golf" como primer resultado. Si estos normalizaran igual, el fallback
      // seguiría cargando el campo equivocado.
      expect(
        GolfCourseService.normalizeClubName('Club de Golf'),
        isNot(GolfCourseService.normalizeClubName('Tajin Club De Golf')),
      );
      expect(
        GolfCourseService.normalizeClubName('Club De Golf Mexico'),
        isNot(GolfCourseService.normalizeClubName('Club De Golf Papudo')),
      );
    });

    test('es idempotente', () {
      final once = GolfCourseService.normalizeClubName('Club de Golf México');
      expect(GolfCourseService.normalizeClubName(once), once);
    });

    test('tolera cadena vacía', () {
      expect(GolfCourseService.normalizeClubName(''), '');
      expect(GolfCourseService.normalizeClubName('   '), '');
    });
  });
}
