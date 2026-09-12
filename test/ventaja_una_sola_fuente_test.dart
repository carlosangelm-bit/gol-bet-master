// ─────────────────────────────────────────────────────────────────────────────
// LA VENTAJA ENTRE DOS JUGADORES — una sola fuente
//
// «Al crear la ronda aparece uno, pero ya iniciada la ronda, en la pestaña de
//  Inicio, aparece otro.»
//
// ── El barrido, por estructura ──────────────────────────────────────────────
//
// No se buscó la palabra «sliding»: se buscaron los PASOS de la cadena —leer
// `pairSliding`, leer `manualHandicaps`, restar handicaps— porque la sexta
// cuenta del Nassau se escapó por llamarse de otra manera.
//
// Salieron NUEVE sitios resolviendo la misma pregunta:
//
//   1 · Round.ventajaDe                    ← la única que queda
//   2 · BetEngine._strokesP1ReceivesFromP2   copia completa
//   3 · GameEngine.matchPlayStatus           copia completa, en línea
//   4 · Inicio, lista de ventajas            SE SALTABA pairSliding
//   5 · Inicio, hoja de edición              solo la resta de handicaps
//   6 · bets_screen                          copia FIEL, con su comentario
//   7 · Asistente, panel de sliding          su estado local
//   8 · Asistente, matriz de handicap        SE SALTABA el acumulado
//   9 · sliding_adjustment_engine            el legacy a mano
//
// ── Y la fuente vive en el MODELO, no en el motor ──────────────────────────
//
// `models` no importa los motores. Un resolvedor en `BetEngine` no lo pueden
// llamar ni el modelo ni las pantallas que no dependen del motor — y esa era la
// razón de que cada una escribiera la suya. Poner la cuenta donde vive el dato
// es lo que quita la excusa.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/game_engine.dart';
import 'package:golf_bet_master/models/models.dart';

final _curso = CourseInfo(name: 'P72', holes: [
  for (int i = 1; i <= 18; i++) CourseHole(hole: i, par: 4, strokeIndex: i),
]);

/// CAM (hcp 5) vs CAV (hcp 12). Sin acuerdo, CAV recibe 7.
Round _r({
  Map<String, double> pairSliding = const {},
  Map<String, Map<String, double>> manual = const {},
  double hcpCam = 5,
  double hcpCav = 12,
}) =>
    Round(
      id: 'r',
      name: 'R',
      course: _curso,
      isFinished: false,
      players: [Player(id: 'cam', name: 'CAM'), Player(id: 'cav', name: 'CAV')],
      roundPlayers: [
        RoundPlayer(
            playerId: 'cam',
            handicapEnRonda: hcpCam,
            manualHandicaps: manual['cam'] ?? const {}),
        RoundPlayer(
            playerId: 'cav',
            handicapEnRonda: hcpCav,
            manualHandicaps: manual['cav'] ?? const {}),
      ],
      betGroups: const [],
      scores: {
        for (final p in ['cam', 'cav'])
          p: {
            for (int h = 1; h <= 18; h++)
              h: HoleScore(playerId: p, hole: h, grossScore: 4, putts: 2)
          }
      },
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2026, 9, 12),
      totalHoles: 18,
      pairSliding: pairSliding,
    );

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIO 2 · la cadena, en un solo sitio', () {
    test('CLAVE: 1 · el ACUERDO de la ronda manda sobre todo', () {
      // Es lo que el asistente escribe al editar el sliding.
      final r = _r(pairSliding: {'cam|cav': -3.0});
      expect(r.ventajaDe('cam', 'cav'), -3.0);
      expect(r.ventajaDe('cav', 'cam'), 3.0, reason: 'el signo se invierte');
    });

    test('CLAVE: 2 · el formato viejo, si no hay acuerdo nuevo', () {
      final r = _r(manual: {
        'cam': {'cav': -4.0},
        'cav': {'cam': 4.0}
      });
      expect(r.ventajaDe('cam', 'cav'), -4.0);
    });

    test('CLAVE: 3 · y solo entonces, la diferencia de handicaps', () {
      expect(_r().ventajaDe('cav', 'cam'), 7.0);
    });

    test('CLAVE: un acuerdo de CERO es un acuerdo, no una ausencia', () {
      // «Jugar a la par» es un pacto. Si cayera al paso 3, CAV recibiría 7.
      final r = _r(pairSliding: {'cam|cav': 0.0});
      expect(r.ventajaDe('cav', 'cam'), 0.0);
      expect(r.hayAcuerdoDeVentaja('cam', 'cav'), isTrue);
      expect(_r().hayAcuerdoDeVentaja('cam', 'cav'), isFalse,
          reason: 'sin acuerdo, aunque la resta diera 0');
    });

    test('CLAVE: el legacy contradictorio LANZA al liquidar, y no al pintar',
        () {
      // Mejor fallar que cobrar mal. Pero una pantalla no puede reventar por
      // unos datos rotos: enseña la perspectiva de quien pregunta.
      final r = _r(manual: {
        'cam': {'cav': -4.0},
        'cav': {'cam': 9.0}
      });
      expect(() => r.ventajaDe('cam', 'cav', estricto: true), throwsStateError);
      expect(r.ventajaDe('cam', 'cav'), -4.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIO 3 · todas las superficies dan la MISMA cifra', () {
    // El caso del síntoma: un acuerdo pactado en el asistente, que vive en
    // `pairSliding` y NO en el legacy.
    final r = _r(pairSliding: {'cam|cav': -3.0});

    test('CLAVE: el motor de apuestas', () {
      expect(BetEngine.strokesP1ReceivesFromP2(r, 'cam', 'cav'), -3.0);
    });

    test('CLAVE: la tarjeta de puntuación', () {
      expect(r.strokesVs('cav', 'cam'), (3, 0));
      expect(r.strokesVs('cam', 'cav'), (0, 3));
    });

    test('CLAVE: y el match play, que tenía la cadena escrita en línea', () {
      // CAV recibe 3 golpes en los hoyos 1, 2 y 3 (los de menor stroke index),
      // así que con todos empatados en bruto gana esos tres.
      expect(GameEngine.matchPlayStatus(r, 'cav', 'cam', true), 3);
      expect(GameEngine.matchPlayStatus(r, 'cav', 'cam', false), 0,
          reason: 'en bruto no hay ventaja que aplicar');
    });

    test('CONTRAPESO: sin acuerdo, las tres siguen coincidiendo', () {
      final sin = _r();
      expect(BetEngine.strokesP1ReceivesFromP2(sin, 'cav', 'cam'), 7.0);
      expect(sin.strokesVs('cav', 'cam'), (7, 0));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIO 4 · la guarda, para que no nazca la décima', () {
    /// Cada patrón es UN PASO de la cadena hecho a mano.
    final pasos = {
      'lee pairSliding': RegExp(r'(?<!_)pairSliding\s*\['),
      'lee manualHandicaps': RegExp(r'manualHandicaps\s*\[|manualHandicaps\.containsKey'),
      // El TERCER paso también cuenta. Sin esto, Inicio podía volver a enseñar
      // la resta de handicaps sin que nadie lo notara — que es el fallo
      // original. Se permite cuando el resultado se llama `auto…`: ahí no es la
      // ventaja, es la REFERENCIA que se enseña al lado cuando no hay acuerdo.
      'resta handicaps a mano': RegExp(
          r'(getHandicap|playingHcp|_playingHcp|_hcpDe)\([^)]*\)\s*-\s*'
          r'(?:\w+\.)?(getHandicap|playingHcp|_playingHcp|_hcpDe)\('),
    };

    /// Quién puede tocar los pasos, y por qué. Añadir uno tiene que ser una
    /// decisión, no un descuido.
    const permitidos = {
      // La fuente.
      'lib/models/models.dart',
      // Migra el formato viejo al canónico: tiene que leer el viejo.
      'lib/providers/round_provider.dart',
      // ESCRIBE el acuerdo —no lo resuelve— y lo hace antes de que la ronda
      // exista, así que no puede preguntarle a `Round`.
      'lib/screens/setup/setup_screen.dart',
      // Vuelca el estado para depurar.
      'lib/engines/round_debug.dart',
    };

    test('CLAVE: nadie más resuelve la cadena por su cuenta', () {
      final intrusos = <String>[];
      for (final f
          in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        if (permitidos.contains(f.path)) continue;
        final lineas = f.readAsStringSync().split('\n');
        for (var i = 0; i < lineas.length; i++) {
          final l = lineas[i];
          if (l.trimLeft().startsWith('//')) continue;
          final codigo = l.split('//').first;
          // La REFERENCIA se llama `auto…` por convención en las dos pantallas
          // que la enseñan: es lo que valdría la ventaja si no hubiera acuerdo,
          // y se pinta al lado del valor. No es una resolución.
          if (RegExp(r'\bauto\w*\s*=').hasMatch(codigo)) continue;
          pasos.forEach((nombre, rx) {
            if (rx.hasMatch(codigo)) {
              intrusos.add('${f.path}:${i + 1}  [$nombre]  ${l.trim()}');
            }
          });
        }
      }
      expect(intrusos, isEmpty,
          reason: 'esto es una décima cuenta de la ventaja:\n'
              '${intrusos.join('\n')}\n\n'
              'Usa Round.ventajaDe. Si de verdad hace falta otra cosa, '
              'añádelo a `permitidos` con su motivo escrito.');
    });

    test('CONTRAPESO: la guarda reconoce un paso hecho a mano', () {
      // Si dejara de reconocerlo, pasaría siempre y no protegería nada.
      expect(pasos['lee pairSliding']!.hasMatch('  final x = round.pairSliding[k];'),
          isTrue);
      expect(
          pasos['lee manualHandicaps']!
              .hasMatch('  final y = rp.manualHandicaps[otro];'),
          isTrue);
      // Y no confunde una escritura del propio estado del asistente.
      expect(pasos['lee pairSliding']!.hasMatch('  _pairSliding[key] = v;'),
          isFalse);
    });

    test('CLAVE: la fuente está en el MODELO, que es quien no tiene ciclos', () {
      // Si volviera al motor, las pantallas que no lo importan tendrían que
      // copiarla otra vez — que es exactamente cómo nacieron las nueve.
      final modelo = File('lib/models/models.dart').readAsStringSync();
      expect(modelo, contains('double ventajaDe('));
      final motor = File('lib/engines/bet_engine.dart').readAsStringSync();
      expect(motor, contains('round.ventajaDe(p1Id, p2Id, estricto: true)'));
    });
  });
}
