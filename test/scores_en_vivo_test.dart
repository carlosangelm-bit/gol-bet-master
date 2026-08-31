// ─────────────────────────────────────────────────────────────────────────────
// SCORES EN VIVO — la frontera de lectura, y corregir sin desconfiar
//
// «Esta sección lee datos de otras cuentas por primera vez desde el portal.
// Merece la misma sonda que te encontró los tres anteriores.»
//
// ── La determinación, y por qué NO hay reglas nuevas ────────────────────────
//
// Lo que las reglas de hoy conceden:
//
//   · liveRounds        → participantUids o ownerUid
//   · torneoResultados  → torneoOwnerUid (el organizador) o escritoPor
//
// De ahí sale la frontera: EN VIVO las rondas que el organizador montó —en un
// shotgun son todas—, y AL CERRAR las de otras cuentas. Ninguna regla nueva.
//
// Las dos formas de ampliarlo dan de más y se descartaron con el motivo
// delante:
//
//   1 · meter al organizador en `participantUids` le daría también UPDATE,
//       porque la regla es `allow read, update` juntas
//   2 · una regla por `torneoIds` necesitaría un `get()` cruzado por documento,
//       que en una regla de `list` no se puede acotar
//
// ── Lo que este fichero vigila ──────────────────────────────────────────────
//
// El grupo 1 lee `firestore.rules` COMO TEXTO. Es raro y es a propósito: las
// tres fugas históricas —sharedTorneos, players, userLookup— eran un `read`
// donde hacía falta un `get`, y ninguna prueba de Dart las podía ver. Esta sí,
// y sobre todo ve la regresión que de verdad va a pasar: que alguien amplíe
// liveRounds «para que el portal vea las rondas de todos».
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/ancho.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/models/correccion_de_score.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/round_result.dart';
import 'package:golf_bet_master/models/torneo.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/screens/organizador/scores_seccion.dart';

/// El bloque de la regla de [coleccion], sin comentarios.
String _regla(String coleccion) {
  final texto = File('firestore.rules').readAsStringSync();
  final i = texto.indexOf('match /$coleccion/');
  expect(i, greaterThan(-1), reason: 'no existe la regla de $coleccion');
  // Hasta el siguiente `match /` de primer nivel, que es donde acaba.
  final resto = texto.substring(i + 10);
  final j = resto.indexOf('\n    match /');
  final bloque = j == -1 ? resto : resto.substring(0, j);
  return bloque
      .split('\n')
      .map((l) {
        final c = l.indexOf('//');
        return c == -1 ? l : l.substring(0, c);
      })
      .join('\n');
}

Round _ronda({Map<String, Map<int, int>> scores = const {}}) {
  final ps = [
    Player(id: 'ana', name: 'Ana Robles'),
    Player(id: 'beto', name: 'Beto Lara'),
  ];
  return Round(
    id: 'r1',
    name: 'Grupo 3 · salida 8:40',
    course: CourseInfo(
        name: 'Los Encinos',
        holes: List.generate(
            18, (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1))),
    players: ps,
    roundPlayers:
        ps.map((p) => RoundPlayer(playerId: p.id, handicapEnRonda: 0)).toList(),
    betGroups: [
      BetGroup(
          id: 'g',
          name: 'G',
          format: PartidaFormat.oneVsOne,
          playerIds: ps.map((p) => p.id).toList(),
          modules: [
            BetModuleInstance.defaultFor(
                BetModuleType.skins, ps.map((p) => p.id).toList(),
                id: 'sk')
          ]),
    ],
    scores: {
      for (final e in scores.entries)
        e.key: {
          for (final h in e.value.entries)
            h.key: HoleScore(playerId: e.key, hole: h.key, grossScore: h.value),
        },
    },
    events: const {},
    oyeseRankings: const {},
    sliding: const [],
    createdAt: DateTime(2026, 8, 30),
    totalHoles: 18,
    isLive: true,
    ownerUid: 'org',
  );
}

Round _corregida() => conCorreccion(
      _ronda(scores: const {'ana': {7: 5}}),
      jugadorId: 'ana',
      hoyo: 7,
      nuevo: 4,
      porUid: 'org',
      porNombre: 'Carlos',
      cuando: DateTime(2026, 8, 30, 11, 5),
    );

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('1 · la frontera de lectura, leída de las reglas', () {
    test('CLAVE: liveRounds NO se lee por estar autenticado', () {
      // La regresión que va a intentarse: aflojar esto «para que el portal vea
      // las rondas de todos». Es la cuarta vez que este patrón aparece y las
      // tres anteriores costaron una sonda contra producción cada una.
      final r = _regla('liveRounds');
      expect(r, contains('participantUids'));
      expect(r, contains('ownerUid'));
      expect(r.contains('allow read: if request.auth != null;'), isFalse,
          reason: 'eso daría todas las rondas de todo el mundo');
      expect(r.contains('allow read: if true'), isFalse);
    });

    test('CLAVE: y la lectura va JUNTA con update — por eso no se amplía', () {
      // Es el motivo escrito de la determinación: no se puede dar lectura al
      // organizador sin darle escritura, porque la regla las concede juntas.
      // Si algún día se separan, esta prueba falla y la decisión se revisa.
      final r = _regla('liveRounds');
      expect(r, contains('allow read, update:'),
          reason: 'si se separan, se puede reconsiderar dar solo lectura');
    });

    test('CLAVE: torneoResultados solo para el organizador o el autor', () {
      // Es la fuente de «lo cerrado por otras cuentas», y la única del fichero
      // con `read` a propósito: la condición mira resource.data, así que
      // Firestore obliga a acotar la consulta.
      final r = _regla('torneoResultados');
      expect(r, contains('torneoOwnerUid'));
      expect(r, contains('escritoPor'));
      expect(r.contains('allow read: if request.auth != null;'), isFalse);
    });

    test('CONTRAPESO: y nadie más concede lectura libre', () {
      // El barrido. Un `allow read: if true` solo está permitido en la pantalla
      // proyectable, que es la única superficie sin sesión del sistema.
      final texto = File('firestore.rules').readAsStringSync();
      final libres = <String>[];
      var coleccion = '?';
      for (final l in texto.split('\n')) {
        final m = RegExp(r'match /(\w+)/').firstMatch(l);
        if (m != null) coleccion = m.group(1)!;
        final sin = l.contains('//') ? l.substring(0, l.indexOf('//')) : l;
        if (RegExp(r'allow (read|list)[^:]*:\s*if\s+true').hasMatch(sin)) {
          libres.add(coleccion);
        }
      }
      expect(libres, isEmpty,
          reason: 'la tele usa `allow get`, que no concede list');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('2 · corregir deja rastro, siempre', () {
    test('CLAVE: cambiar un score lo cambia Y lo anota', () {
      final r = _corregida();
      expect(r.scores['ana']![7]!.grossScore, 4);
      expect(r.correcciones, hasLength(1));
      final c = r.correcciones.single;
      expect(c.antes, 5);
      expect(c.despues, 4);
      expect(c.porNombre, 'Carlos');
      expect(c.hoyo, 7);
      // El nombre del JUGADOR se guarda: la corrección es un hecho pasado y
      // resolverlo hoy daría el nombre de hoy para lo de ayer.
      expect(c.jugadorNombre, 'Ana Robles');
    });

    test('CLAVE: rellenar un hueco también deja rastro, y lo dice distinto',
        () {
      final r = conCorreccion(_ronda(),
          jugadorId: 'beto',
          hoyo: 3,
          nuevo: 6,
          porUid: 'org',
          porNombre: 'Carlos',
          cuando: DateTime(2026, 8, 30));
      expect(r.scores['beto']![3]!.grossScore, 6);
      expect(r.correcciones.single.antes, isNull);
      expect(r.correcciones.single.frase, contains('se anotó 6'));
    });

    test('CLAVE: borrar es corregir, y no desaparece en silencio', () {
      // Un hoyo que se vacía sin decirlo es un score que se pierde.
      final r = conCorreccion(_ronda(scores: const {'ana': {7: 5}}),
          jugadorId: 'ana',
          hoyo: 7,
          nuevo: null,
          porUid: 'org',
          porNombre: 'Carlos',
          cuando: DateTime(2026, 8, 30));
      expect(r.scores['ana']![7]!.grossScore, isNull);
      expect(r.correcciones.single.frase, contains('se borró el 5'));
    });

    test('CLAVE: y lo que NO cambia no se anota', () {
      // Anotar correcciones que no cambiaron nada llena el registro de ruido y
      // hace dudar del que sí importa.
      final antes = _ronda(scores: const {'ana': {7: 5}});
      final despues = conCorreccion(antes,
          jugadorId: 'ana',
          hoyo: 7,
          nuevo: 5,
          porUid: 'org',
          porNombre: 'Carlos',
          cuando: DateTime(2026, 8, 30));
      expect(identical(antes, despues), isTrue);
      expect(despues.correcciones, isEmpty);
    });

    test('las correcciones se acumulan, no se sustituyen', () {
      var r = _corregida();
      r = conCorreccion(r,
          jugadorId: 'ana',
          hoyo: 7,
          nuevo: 6,
          porUid: 'org',
          porNombre: 'Carlos',
          cuando: DateTime(2026, 8, 30, 11, 20));
      expect(r.correcciones, hasLength(2));
      expect(r.correcciones.last.antes, 4, reason: 'parte de la anterior');
      expect(r.correcciones.first.antes, 5);
    });

    test('CONTRAPESO: y borrar conserva lo que no se estaba corrigiendo', () {
      // Los putts no son el score. Vaciar el hoyo entero sería corregir de más.
      final base = _ronda();
      final conPutts = base.copyWith(scores: {
        'ana': {
          7: HoleScore(playerId: 'ana', hole: 7, grossScore: 5, putts: 2),
        }
      });
      final r = conCorreccion(conPutts,
          jugadorId: 'ana',
          hoyo: 7,
          nuevo: null,
          porUid: 'org',
          porNombre: 'Carlos',
          cuando: DateTime(2026, 8, 30));
      expect(r.scores['ana']![7]!.putts, 2);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 3 · QUE EL RASTRO SOBREVIVA AL GUARDADO
  //
  // `guardarCorregida` escribe con `merge: false`: todo lo que no salga de
  // `roundToJson` se BORRA del documento en el siguiente guardado. Un registro
  // de quién cambió qué que desaparece al anotar el hoyo siguiente sería peor
  // que no tenerlo — diría que nadie tocó nada.
  //
  // Es la misma familia que costó cuatro campos caídos en esta sesión, y aquí
  // la comprobación tiene que existir ANTES de que el fallo aparezca.
  // ───────────────────────────────────────────────────────────────────────────
  group('3 · el rastro sobrevive al viaje por Firestore', () {
    test('CLAVE: ida y vuelta conserva las correcciones', () {
      final ida = _corregida();
      final vuelta = roundFromJson(roundToJson(ida));
      expect(vuelta.correcciones, hasLength(1));
      final c = vuelta.correcciones.single;
      expect(c.antes, 5);
      expect(c.despues, 4);
      expect(c.hoyo, 7);
      expect(c.porNombre, 'Carlos');
      expect(c.jugadorNombre, 'Ana Robles');
      expect(c.cuando, DateTime(2026, 8, 30, 11, 5));
      // Y el score corregido, claro.
      expect(vuelta.scores['ana']![7]!.grossScore, 4);
    });

    test('CLAVE: una ronda sin correcciones no gana la clave', () {
      // Un documento no engorda por una función nueva.
      expect(roundToJson(_ronda()).containsKey('correcciones'), isFalse);
      expect(roundFromJson(roundToJson(_ronda())).correcciones, isEmpty);
    });

    test('CONTRAPESO: una corrección ilegible no impide abrir la ronda', () {
      // El día del torneo, un registro a medias no puede dejar al organizador
      // sin la tarjeta.
      final j = roundToJson(_corregida());
      j['correcciones'] = ['esto no es un mapa', 42];
      expect(() => roundFromJson(j), returnsNormally);
      expect(roundFromJson(j).correcciones, isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('4 · la pantalla dice qué es en vivo y qué no', () {
    Future<void> montar(WidgetTester tester,
        {List<ResultadoPublicado> publicados = const []}) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LayoutBuilder(
            builder: (_, c) => ScoresSeccion(
              torneo: Torneo(id: 't1', nombre: 'Copa'),
              ancho: anchoDe(c.maxWidth),
              t: GolfTheme.classic,
              publicados: publicados,
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 200));
    }

    String texto(WidgetTester tester) => tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? '')
        .join(' · ');

    testWidgets('CLAVE: separa lo que es en vivo de lo que es al cerrar',
        (tester) async {
      // Es lo mismo que se decidió con el "Thru": mejor decir qué se ve que
      // prometer tiempo real y enseñar algo de hace dos horas.
      await montar(tester);
      final t = texto(tester);
      expect(t, contains('TUS GRUPOS · EN VIVO'));
      expect(t, contains('DE OTRAS CUENTAS · AL CERRAR'));
      expect(t, contains('cuando las '), reason: 'dice CUÁNDO se ve lo ajeno');
    });

    testWidgets('CLAVE: y lo ajeno lleva su FECHA, que es lo que lo separa',
        (tester) async {
      await montar(tester, publicados: [
        ResultadoPublicado(
          jugadorNombre: 'Diego Estrada',
          jugadorId: 'diego',
          resultado: RoundResult(
            roundId: 'r9',
            roundName: 'Grupo 9',
            courseName: 'Los Encinos',
            playedAt: DateTime(2026, 8, 29),
            holesPlayed: 18,
            playerIds: const ['diego'],
            playerNames: const {'diego': 'Diego Estrada'},
            balances: const {},
            pairBalances: const {},
            grossByPlayer: const {'diego': 78},
          ),
        ),
      ]);
      final t = texto(tester);
      expect(t, contains('Grupo 9'));
      expect(t, contains('Diego Estrada'));
      expect(t, contains('29/8'), reason: 'sin fecha se leería como un directo');
    });

    testWidgets('sin nada de fuera, lo dice en vez de dejar un hueco',
        (tester) async {
      await montar(tester);
      expect(texto(tester), contains('Nadie de fuera ha cerrado'));
    });
  });
}
