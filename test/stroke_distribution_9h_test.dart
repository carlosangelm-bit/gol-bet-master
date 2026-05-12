// ignore_for_file: avoid_print
// Tests para validar distribución de ventajas en campo 9 hoyos
// Escenario: RAFA recibe 10 de CAM (pairSliding=-10), campo 1-9, startingNine=back.
// La B9 (vuelta de inicio) recibe ceil(10/2)=5 strokes.
// Los 5 strokes deben ir a los 5 hoyos con menor SI.
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/game_engine.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';

// Campo 1-9 con SI estándar (SI correcto)
final _course1to9_stdSI = CourseInfo(
  name: 'Campo 1-9 SI estándar',
  holes: [
    CourseHole(hole: 1, par: 4, strokeIndex: 5),
    CourseHole(hole: 2, par: 5, strokeIndex: 11),
    CourseHole(hole: 3, par: 3, strokeIndex: 15),
    CourseHole(hole: 4, par: 4, strokeIndex: 1),
    CourseHole(hole: 5, par: 4, strokeIndex: 9),
    CourseHole(hole: 6, par: 3, strokeIndex: 17),
    CourseHole(hole: 7, par: 4, strokeIndex: 3),
    CourseHole(hole: 8, par: 5, strokeIndex: 13),
    CourseHole(hole: 9, par: 4, strokeIndex: 7),
  ],
);

// Campo 1-9 con SI = número hoyo (simula campo mal configurado)
final _course1to9_numSI = CourseInfo(
  name: 'Campo 1-9 SI=número',
  holes: [
    CourseHole(hole: 1, par: 4, strokeIndex: 1),
    CourseHole(hole: 2, par: 5, strokeIndex: 2),
    CourseHole(hole: 3, par: 3, strokeIndex: 3),
    CourseHole(hole: 4, par: 4, strokeIndex: 4),
    CourseHole(hole: 5, par: 4, strokeIndex: 5),
    CourseHole(hole: 6, par: 3, strokeIndex: 6),
    CourseHole(hole: 7, par: 4, strokeIndex: 7),
    CourseHole(hole: 8, par: 5, strokeIndex: 8),
    CourseHole(hole: 9, par: 4, strokeIndex: 9),
  ],
);

void main() {
  // ─── Test 1: campo 1-9 back-start con SI estándar ───────────────────────
  test('T1: campo 1-9 back-start, diff18=10 → 5 strokes en B9 por orden SI', () {
    print('\n=== T1: campo 1-9, startingNine=back, SI estándar, diff18=10 ===');

    final allHoles = _course1to9_stdSI.holes;
    final (courseF9, courseB9) =
        BetEngine.courseHolesF9B9Public(allHoles, StartingNine.back);

    print('courseF9 count: ${courseF9.length} (debe ser 0)');
    print('courseB9 count: ${courseB9.length} (debe ser 9)');
    expect(courseF9.length, 0, reason: 'F9 vacío para campo 1-9 back');
    expect(courseB9.length, 9, reason: 'B9 tiene los 9 hoyos');

    int totalStrokes = 0;
    final List<String> holesWithStroke = [];
    for (final ch in allHoles) {
      final courseHolesForHole =
          courseF9.any((h) => h.hole == ch.hole) ? courseF9 : courseB9;
      final s = GameEngine.strokesReceivedFromOfficial18Sliding(
        diff18: 10,
        ch: ch,
        courseHolesInSameNine: courseHolesForHole,
        startingNine: StartingNine.back,
        isNineHolesStartingNine: courseF9.any((h) => h.hole == ch.hole)
            ? (StartingNine.back == StartingNine.front)
            : (StartingNine.back == StartingNine.back),
      );
      if (s > 0) holesWithStroke.add('H${ch.hole}(SI${ch.strokeIndex})');
      print('  H${ch.hole} (SI${ch.strokeIndex}): $s stroke');
      totalStrokes += s;
    }
    print('Total strokes: $totalStrokes, hoyos con stroke: $holesWithStroke');
    expect(totalStrokes, 5, reason: 'Total debe ser 5 (share de B9=ceil(10/2)=5)');

    // Los 5 hoyos con stroke deben ser los de menor SI: H4(SI1), H7(SI3), H1(SI5), H9(SI7), H5(SI9)
    final expected = {1, 4, 5, 7, 9};
    final actual = allHoles
        .where((ch) {
          final courseHolesForHole =
              courseF9.any((h) => h.hole == ch.hole) ? courseF9 : courseB9;
          return GameEngine.strokesReceivedFromOfficial18Sliding(
                diff18: 10,
                ch: ch,
                courseHolesInSameNine: courseHolesForHole,
                startingNine: StartingNine.back,
                isNineHolesStartingNine: courseF9.any((h) => h.hole == ch.hole)
                    ? (StartingNine.back == StartingNine.front)
                    : (StartingNine.back == StartingNine.back),
              ) >
              0;
        })
        .map((ch) => ch.hole)
        .toSet();
    print('Hoyos con stroke (actual): $actual');
    print('Hoyos con stroke (esperado): $expected');
    expect(actual, expected,
        reason: 'Strokes deben ir a H1,H4,H5,H7,H9 (los de menor SI)');
  });

  // ─── Test 2: campo 1-9 back-start con SI=número (campo problemático) ────
  test('T2: campo 1-9 back-start, SI=número, diff18=10 → 5 strokes en H1-H5', () {
    print('\n=== T2: campo 1-9, startingNine=back, SI=número, diff18=10 ===');
    print('(Si SI=número, los strokes van a H1-H5, no por dificultad real)');

    final allHoles = _course1to9_numSI.holes;
    final (courseF9, courseB9) =
        BetEngine.courseHolesF9B9Public(allHoles, StartingNine.back);

    int totalStrokes = 0;
    for (final ch in allHoles) {
      final courseHolesForHole =
          courseF9.any((h) => h.hole == ch.hole) ? courseF9 : courseB9;
      final s = GameEngine.strokesReceivedFromOfficial18Sliding(
        diff18: 10,
        ch: ch,
        courseHolesInSameNine: courseHolesForHole,
        startingNine: StartingNine.back,
        isNineHolesStartingNine: courseF9.any((h) => h.hole == ch.hole)
            ? (StartingNine.back == StartingNine.front)
            : (StartingNine.back == StartingNine.back),
      );
      print('  H${ch.hole} (SI${ch.strokeIndex}): $s stroke');
      totalStrokes += s;
    }
    print('Total strokes: $totalStrokes (debe ser 5)');
    expect(totalStrokes, 5, reason: 'Total sigue siendo 5 incluso con SI=número');
    // Con SI=número los strokes van a H1-H5 (SI 1-5)
    final actual = allHoles
        .where((ch) {
          final courseHolesForHole =
              courseF9.any((h) => h.hole == ch.hole) ? courseF9 : courseB9;
          return GameEngine.strokesReceivedFromOfficial18Sliding(
                diff18: 10,
                ch: ch,
                courseHolesInSameNine: courseHolesForHole,
                startingNine: StartingNine.back,
                isNineHolesStartingNine: courseF9.any((h) => h.hole == ch.hole)
                    ? (StartingNine.back == StartingNine.front)
                    : (StartingNine.back == StartingNine.back),
              ) >
              0;
        })
        .map((ch) => ch.hole)
        .toSet();
    print('Hoyos con stroke: $actual (con SI=número van a H1-H5)');
    expect(actual, {1, 2, 3, 4, 5}, reason: 'Con SI=número van a los primeros 5 hoyos');
  });

  // ─── Test 3: campo 18H estándar, startingNine=back, diff18=10 ────────────
  test('T3: campo 18H, startingNine=back, diff18=10 → 5 en B9 y 5 en F9', () {
    print('\n=== T3: campo 18H estándar, startingNine=back, diff18=10 ===');
    final allHoles = CourseInfo.standard.holes;
    final (courseF9, courseB9) =
        BetEngine.courseHolesF9B9Public(allHoles, StartingNine.back);
    print('courseF9 count: ${courseF9.length}, courseB9 count: ${courseB9.length}');
    expect(courseF9.length, 9);
    expect(courseB9.length, 9);

    int totalStrokes = 0;
    for (final ch in allHoles) {
      final courseHolesForHole =
          courseF9.any((h) => h.hole == ch.hole) ? courseF9 : courseB9;
      final s = GameEngine.strokesReceivedFromOfficial18Sliding(
        diff18: 10,
        ch: ch,
        courseHolesInSameNine: courseHolesForHole,
        startingNine: StartingNine.back,
        isNineHolesStartingNine: courseF9.any((h) => h.hole == ch.hole)
            ? (StartingNine.back == StartingNine.front)
            : (StartingNine.back == StartingNine.back),
      );
      if (s > 0) print('  H${ch.hole} (SI${ch.strokeIndex}): $s stroke');
      totalStrokes += s;
    }
    print('Total: $totalStrokes (debe ser 10)');
    expect(totalStrokes, 10);

    // B9 (startingNine): recibe ceil(10/2)=5 strokes → H11(SI2),H14(SI4),H10(SI6),H13(SI8),H16(SI10)
    final b9Strokes = courseB9.map((ch) {
      final s = GameEngine.strokesReceivedFromOfficial18Sliding(
        diff18: 10,
        ch: ch,
        courseHolesInSameNine: courseB9,
        startingNine: StartingNine.back,
        isNineHolesStartingNine: StartingNine.back == StartingNine.back, // B9 es la startingNine
      );
      return (ch.hole, s);
    }).where((p) => p.$2 > 0).map((p) => p.$1).toSet();
    print('B9 hoyos con stroke: $b9Strokes');
    expect(b9Strokes.length, 5, reason: 'B9 recibe ceil(10/2)=5 strokes');

    // F9 (secondary nine): recibe floor(10/2)=5 strokes → igual que ceil para diff par
    final f9Strokes = courseF9.map((ch) {
      final s = GameEngine.strokesReceivedFromOfficial18Sliding(
        diff18: 10,
        ch: ch,
        courseHolesInSameNine: courseF9,
        startingNine: StartingNine.back,
        isNineHolesStartingNine: StartingNine.back == StartingNine.front, // F9 NO es la startingNine
      );
      return (ch.hole, s);
    }).where((p) => p.$2 > 0).map((p) => p.$1).toSet();
    print('F9 hoyos con stroke: $f9Strokes');
    expect(f9Strokes.length, 5, reason: 'F9 recibe floor(10/2)=5 strokes');
  });

  // ─── Test 4: campo 1-9 back-start, diff18=9 (impar) ─────────────────────
  test('T4: campo 1-9 back-start, diff18=9 → 5 strokes en B9 (ceil=5 > floor=4)', () {
    print('\n=== T4: campo 1-9, startingNine=back, SI estándar, diff18=9 ===');
    final allHoles = _course1to9_stdSI.holes;
    final (courseF9, courseB9) =
        BetEngine.courseHolesF9B9Public(allHoles, StartingNine.back);

    int totalStrokes = 0;
    for (final ch in allHoles) {
      final courseHolesForHole =
          courseF9.any((h) => h.hole == ch.hole) ? courseF9 : courseB9;
      final s = GameEngine.strokesReceivedFromOfficial18Sliding(
        diff18: 9,
        ch: ch,
        courseHolesInSameNine: courseHolesForHole,
        startingNine: StartingNine.back,
        isNineHolesStartingNine: courseF9.any((h) => h.hole == ch.hole)
            ? (StartingNine.back == StartingNine.front)
            : (StartingNine.back == StartingNine.back),
      );
      if (s > 0) print('  H${ch.hole} (SI${ch.strokeIndex}): $s stroke');
      totalStrokes += s;
    }
    print('Total: $totalStrokes (debe ser 5 = ceil(9/2))');
    expect(totalStrokes, 5,
        reason: 'B9 (startingNine) recibe ceil(9/2)=5 strokes');
  });
}
