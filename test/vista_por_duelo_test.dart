// ─────────────────────────────────────────────────────────────────────────────
// EL PASO 6, LEÍDO DESDE EL DUELO
//
//     «Sigue siendo un problema configurar diferentes apuestas entre diferentes
//      jugadores. El armado está hecho para que todos jueguen lo mismo, cuando
//      ese no es el caso.»
//
// El paso se lee por APUESTA: quién entra en Skins, y qué cruces de Skins
// quedan fuera. La otra lectura —qué juega CAM contra KAWA— es la transposición
// de los mismos dos mapas:
//
//     CAM vs KAWA    Nassau · Skins
//     CAM vs Jose    Nassau
//     KAWA vs Jose   Nassau · Skins
//     Oyes           de la partida — no se pacta por duelo
//
// Sin modelo nuevo. Y por eso la respuesta vive en UNA función que las dos
// vistas consultan: dos vistas del mismo dato que lo calculan por su cuenta
// acaban discrepando, y llevamos la sesión entera desmontando ese patrón.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/screens/setup/setup_screen.dart';
import 'package:golf_bet_master/models/bet_recipe.dart';

const _cam = 'cam', _kawa = 'kawa', _jose = 'jose';

/// Lo elegido: dos de duelo y una de la partida.
const _conteos = [BetCount.puntos, BetCount.skins, BetCount.oyes];

/// Todos juegan todo, salvo lo que se diga.
List<EstadoDelCruce> _estados(
  String a,
  String b, {
  Map<BetCount, List<String>> quienJuega = const {},
  Map<BetCount, Set<String>> fuera = const {},
}) =>
    apuestasDelCruce(a, b,
        conteos: _conteos,
        participantesDe: (c) =>
            quienJuega[c] ?? const [_cam, _kawa, _jose],
        crucesFuera: (c) => fuera[c] ?? const {});

Set<BetCount> _juega(List<EstadoDelCruce> e) =>
    e.where((x) => x.juega).map((x) => x.cuenta).toSet();

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  group('1 · la transposición', () {
    test('CLAVE (criterio 1): qué juega cada par, desde los mismos dos mapas',
        () {
      // Skins apagado solo entre CAM y Jose.
      final fuera = {
        BetCount.skins: {BetRecipe.cruceKey(_cam, _jose)}
      };
      expect(_juega(_estados(_cam, _kawa, fuera: fuera)),
          {BetCount.puntos, BetCount.skins});
      expect(_juega(_estados(_cam, _jose, fuera: fuera)), {BetCount.puntos});
      expect(_juega(_estados(_kawa, _jose, fuera: fuera)),
          {BetCount.puntos, BetCount.skins});
    });

    test('CLAVE (criterio 3): las de la partida no salen como pactables', () {
      // Oyes es de la partida, así que no aparece entre los chips de un duelo.
      expect(_estados(_cam, _kawa).map((e) => e.cuenta),
          isNot(contains(BetCount.oyes)));
      // Y se enumeran de la marca del catálogo, no de una lista a mano.
      expect(apuestasDeLaPartida(_conteos), [BetCount.oyes]);
      expect(BetCount.oyes.esDeGrupo, isTrue);
      expect(BetCount.skins.esDeGrupo, isFalse);
    });

    test('CLAVE: quien no está en la apuesta se DICE, y no se deja tocar', () {
      // Jose fuera de Skins del todo. Encenderlo desde el duelo lo metería
      // contra todos, que es otra decisión: se explica y se manda al otro lado.
      final e = _estados(_cam, _jose, quienJuega: {
        BetCount.skins: const [_cam, _kawa]
      }).firstWhere((x) => x.cuenta == BetCount.skins);
      expect(e.juega, isFalse);
      expect(e.editable, isFalse);
      expect(e.fueraDeLaApuesta, [_jose]);
      // Y entre los dos que sí están, se puede tocar.
      final f = _estados(_cam, _kawa, quienJuega: {
        BetCount.skins: const [_cam, _kawa]
      }).firstWhere((x) => x.cuenta == BetCount.skins);
      expect(f.editable, isTrue);
      expect(f.juega, isTrue);
    });
  });

  _enPantalla();
  _lasDosALaVez();
  _oyesNoTieneCruces();
  _todasLasApuestas();

  // ═══════════════════════════════════════════════════════════════════════════
  group('2 · las dos lecturas no pueden discrepar', () {
    test('CLAVE (criterio 2): apagar desde un lado se ve desde el otro', () {
      // La vista por apuesta escribe `_crucesFuera[skins]`; la del duelo lee de
      // esta misma función. No hay dos caminos.
      final fuera = <BetCount, Set<String>>{BetCount.skins: {}};
      expect(_juega(_estados(_cam, _kawa, fuera: fuera)),
          contains(BetCount.skins));

      fuera[BetCount.skins] = {BetRecipe.cruceKey(_cam, _kawa)};
      expect(_juega(_estados(_cam, _kawa, fuera: fuera)),
          isNot(contains(BetCount.skins)));
      // Y solo ese cruce: apagarlo aquí no toca a los demás.
      expect(_juega(_estados(_kawa, _jose, fuera: fuera)),
          contains(BetCount.skins));
    });

    test('CONTRAPESO: la clave del cruce es simétrica', () {
      // Si no lo fuera, apagar «CAM vs KAWA» dejaría vivo «KAWA vs CAM» y las
      // dos vistas dirían cosas distintas de la misma pareja.
      final fuera = {
        BetCount.skins: {BetRecipe.cruceKey(_kawa, _cam)}
      };
      expect(_juega(_estados(_cam, _kawa, fuera: fuera)),
          isNot(contains(BetCount.skins)));
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 3 · EN PANTALLA, CON TRES JUGADORES Y APUESTAS DISTINTAS POR PAR
// ─────────────────────────────────────────────────────────────────────────────
void _enPantalla() {
  testWidgets('CLAVE (criterio 5): se lee por duelo, y tocar un chip apaga esa '
      'apuesta en ese cruce', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // El estado real del paso: el mapa de cruces fuera, y nada más.
    final fuera = <BetCount, Set<String>>{};

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (ctx, setSt) {
          return SingleChildScrollView(
            child: PanelPorDuelo(
              players: [
                Player(id: _cam, name: 'CAM'),
                Player(id: _kawa, name: 'KAWA'),
                Player(id: _jose, name: 'Jose'),
              ],
              conteos: _conteos,
              bola: null,
              participantesDe: (c) => const [_cam, _kawa, _jose],
              crucesFuera: (c) => fuera[c] ?? const {},
              onAlternar: (cuenta, a, b) => setSt(() {
                final set = Set<String>.of(fuera[cuenta] ?? const {});
                final k = BetRecipe.cruceKey(a, b);
                if (!set.remove(k)) set.add(k);
                fuera[cuenta] = set;
              }),
              t: GolfTheme.dark,
            ),
          );
        }),
      ),
    ));
    await tester.pumpAndSettle();

    String texto() => tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? '')
        .join('  ‖  ');

    // Los tres cruces, cada uno con lo suyo.
    expect(texto(), contains('CAM vs KAWA'));
    expect(texto(), contains('CAM vs Jose'));
    expect(texto(), contains('KAWA vs Jose'));
    expect('2 apuestas entre ellos'.allMatches(texto()).length, 3);

    // Y la de la partida, aparte y sin chip.
    expect(texto(), contains('De la partida — no se pacta por duelo'));

    // ── Se apaga Skins SOLO entre CAM y Jose ─────────────────────────────
    //
    // El chip vive dentro de la ficha de ese cruce, así que se busca ahí: hay
    // un «Skins» por cruce y tocar el primero apagaría el que no es.
    final fichaCamJose = find.ancestor(
        of: find.text('CAM vs Jose'), matching: find.byType(Container));
    await tester.tap(find.descendant(
        of: fichaCamJose.first, matching: find.text(BetCount.skins.label)));
    await tester.pumpAndSettle();

    // El estado, que es lo que la ronda se lleva.
    expect(fuera[BetCount.skins], {BetRecipe.cruceKey(_cam, _jose)});
    // Y en pantalla: ese cruce baja a una, los otros dos siguen con dos.
    expect('2 apuestas entre ellos'.allMatches(texto()).length, 2);
    expect(texto(), contains('1 apuesta entre ellos'));
  });

  testWidgets('CONTRAPESO: quien no está en la apuesta lo dice y no se puede '
      'tocar', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var toques = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PanelPorDuelo(
            players: [
              Player(id: _cam, name: 'CAM'),
              Player(id: _jose, name: 'Jose'),
            ],
            conteos: _conteos,
            bola: null,
            // Jose no juega Skins en absoluto.
            participantesDe: (c) =>
                c == BetCount.skins ? const [_cam] : const [_cam, _jose],
            crucesFuera: (c) => const {},
            onAlternar: (_, __, ___) => toques++,
            t: GolfTheme.dark,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final texto = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? '')
        .join('  ‖  ');
    expect(texto, contains('Jose no está en esa apuesta'));
    expect(texto, contains('Se añade desde «Por apuesta»'));

    await tester.tap(find.text(BetCount.skins.label));
    await tester.pumpAndSettle();
    expect(toques, 0, reason: 'un chip muerto no escribe nada');
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 4 · LAS DOS VISTAS, MONTADAS A LA VEZ
//
// «Las dos lecturas no pueden discrepar» era una afirmación sin forma de
// contradecirla mientras la vista por apuesta viviera dentro del State. Un
// contrapeso —devolver el interruptor a su cuenta propia— pasó en verde por
// eso. Montadas las dos sobre el MISMO mapa, ya no.
// ─────────────────────────────────────────────────────────────────────────────
void _lasDosALaVez() {
  testWidgets('CLAVE (criterio 2): tocar en una se ve en la otra', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final fuera = <BetCount, Set<String>>{};
    final jugadores = [
      Player(id: _cam, name: 'CAM'),
      Player(id: _kawa, name: 'KAWA'),
      Player(id: _jose, name: 'Jose'),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (ctx, setSt) {
          void alternar(BetCount c, String a, String b) => setSt(() {
                final set = Set<String>.of(fuera[c] ?? const {});
                final k = BetRecipe.cruceKey(a, b);
                if (!set.remove(k)) set.add(k);
                fuera[c] = set;
              });
          return SingleChildScrollView(
            child: Column(children: [
              // Arriba la vista POR APUESTA, solo la de Skins.
              CrucesDeLaApuesta(
                cuenta: BetCount.skins,
                cruces: BetRecipe.crucesDe(
                    jugadores.map((p) => p.id).toList()),
                nombreDe: (id) =>
                    jugadores.firstWhere((p) => p.id == id).name,
                participantesDe: (c) => const [_cam, _kawa, _jose],
                crucesFuera: (c) => fuera[c] ?? const {},
                onAlternar: alternar,
                t: GolfTheme.dark,
              ),
              // Abajo la vista POR DUELO, sobre el mismo mapa.
              PanelPorDuelo(
                players: jugadores,
                conteos: _conteos,
                bola: null,
                participantesDe: (c) => const [_cam, _kawa, _jose],
                crucesFuera: (c) => fuera[c] ?? const {},
                onAlternar: alternar,
                t: GolfTheme.dark,
              ),
            ]),
          );
        }),
      ),
    ));
    await tester.pumpAndSettle();

    // Cuántos interruptores de la vista por apuesta están encendidos.
    int encendidos() => tester
        .widgetList<Switch>(find.byType(Switch))
        .where((s) => s.value)
        .length;
    String texto() => tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? '')
        .join('  ‖  ');

    expect(encendidos(), 3);
    expect('2 apuestas entre ellos'.allMatches(texto()).length, 3);

    // ── Se apaga desde la vista POR DUELO ────────────────────────────────
    final fichaCamJose = find.ancestor(
        of: find.text('CAM vs Jose'), matching: find.byType(Container));
    await tester.tap(find.descendant(
        of: fichaCamJose.first, matching: find.text(BetCount.skins.label)));
    await tester.pumpAndSettle();

    expect(encendidos(), 2, reason: 'el interruptor de arriba lo refleja');
    expect(texto(), contains('1 apuesta entre ellos'));

    // ── Y se vuelve a encender desde la vista POR APUESTA ────────────────
    final apagado = tester
        .widgetList<Switch>(find.byType(Switch))
        .toList()
        .indexWhere((s) => !s.value);
    await tester.tap(find.byType(Switch).at(apagado));
    await tester.pumpAndSettle();

    expect(encendidos(), 3);
    expect('2 apuestas entre ellos'.allMatches(texto()).length, 3,
        reason: 'los chips de abajo lo reflejan');
    expect(fuera[BetCount.skins], isEmpty);
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 5 · `Bad state: No element` EN EL PASO 6
//
//     Oyes
//       CAM   CAV   AAM
//       3 de 3 jugadores · 3 enfrentamientos
//       ¿ALGÚN CRUCE NO LA JUEGA?
//       ⚠ Error de la aplicación · Bad state: No element
//
// Lo metí yo en `ac5255b`. Al extraer la lista de cruces a un widget público
// —para poder montar las dos vistas a la vez— el interruptor pasó a leer
// `apuestasDelCruce(...).single`. Y esa función FILTRA las apuestas de la
// partida, así que para Oyes devuelve una lista vacía y `.single` revienta.
//
// La guarda del commit anterior comprobaba que las dos vistas coincidieran, y
// coincidían: la vista por duelo no pinta Oyes, así que nunca llamó a la
// función con una apuesta de grupo. Faltaba el caso, no la guarda.
//
// Y el fallo de fondo es el criterio 2: una apuesta de la partida no tiene
// cruces que apagar, así que ese bloque no debería dibujarse para ella.
// ─────────────────────────────────────────────────────────────────────────────
void _oyesNoTieneCruces() {
  test('CLAVE: preguntar por una apuesta de la partida no revienta', () {
    // La llamada que hacía el interruptor. `.single` sobre esto era el error.
    final r = apuestasDelCruce(_cam, _kawa,
        conteos: const [BetCount.oyes],
        participantesDe: (_) => const [_cam, _kawa, _jose],
        crucesFuera: (_) => const {});
    expect(r, isEmpty, reason: 'Oyes no se pacta por duelo: no tiene cruces');
  });

  testWidgets('CLAVE (criterios 1 y 2): la lista de cruces no se ofrece para '
      'una apuesta de la partida', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final jugadores = [
      Player(id: _cam, name: 'CAM'),
      Player(id: _kawa, name: 'CAV'),
      Player(id: _jose, name: 'AAM'),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CrucesDeLaApuesta(
          cuenta: BetCount.oyes,
          cruces: BetRecipe.crucesDe(jugadores.map((p) => p.id).toList()),
          nombreDe: (id) => jugadores.firstWhere((p) => p.id == id).name,
          participantesDe: (_) => const [_cam, _kawa, _jose],
          crucesFuera: (_) => const {},
          onAlternar: (_, __, ___) {},
          t: GolfTheme.dark,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Ni excepción ni bloque: no hay nada que preguntar.
    expect(tester.takeException(), isNull);
    final texto = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? '')
        .join('  ‖  ');
    expect(texto, isNot(contains('¿ALGÚN CRUCE NO LA JUEGA?')));
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('CONTRAPESO: una apuesta de duelo SÍ la ofrece', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final jugadores = [
      Player(id: _cam, name: 'CAM'),
      Player(id: _kawa, name: 'CAV'),
      Player(id: _jose, name: 'AAM'),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CrucesDeLaApuesta(
          cuenta: BetCount.skins,
          cruces: BetRecipe.crucesDe(jugadores.map((p) => p.id).toList()),
          nombreDe: (id) => jugadores.firstWhere((p) => p.id == id).name,
          participantesDe: (_) => const [_cam, _kawa, _jose],
          crucesFuera: (_) => const {},
          onAlternar: (_, __, ___) {},
          t: GolfTheme.dark,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('¿ALGÚN CRUCE NO LA JUEGA?'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(3));
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 6 · LA PRUEBA QUE LO HABRÍA CAZADO
//
// El fallo no fue de lógica: fue un caso que ninguna prueba visitaba. Oyes era
// la única apuesta de la partida entre las que yo montaba, y no la montaba.
//
// Así que la guarda recorre el CATÁLOGO ENTERO. Un tipo nuevo entra solo, y si
// resulta que revienta esta pantalla se sabe aquí y no en el campo.
// ─────────────────────────────────────────────────────────────────────────────
void _todasLasApuestas() {
  final jugadores = [
    Player(id: _cam, name: 'CAM'),
    Player(id: _kawa, name: 'CAV'),
    Player(id: _jose, name: 'AAM'),
  ];

  testWidgets('CLAVE (criterio 1): ninguna apuesta del catálogo revienta la '
      'lista de cruces', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final c in BetCount.values) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CrucesDeLaApuesta(
            cuenta: c,
            cruces: BetRecipe.crucesDe(jugadores.map((p) => p.id).toList()),
            nombreDe: (id) => jugadores.firstWhere((p) => p.id == id).name,
            participantesDe: (_) => const [_cam, _kawa, _jose],
            crucesFuera: (_) => const {},
            onAlternar: (_, __, ___) {},
            t: GolfTheme.dark,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: c.name);

      // Y el criterio 2, del catálogo: las de la partida no ofrecen cruces.
      expect(find.text('¿ALGÚN CRUCE NO LA JUEGA?'),
          c.esDeGrupo ? findsNothing : findsOneWidget,
          reason: c.name);
    }
  });

  testWidgets('CLAVE: y la vista por duelo con TODAS a la vez tampoco',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PanelPorDuelo(
            players: jugadores,
            conteos: BetCount.values,
            bola: null,
            participantesDe: (_) => const [_cam, _kawa, _jose],
            crucesFuera: (_) => const {},
            onAlternar: (_, __, ___) {},
            t: GolfTheme.dark,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final texto = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? '')
        .join('  ‖  ');
    // Las seis de la partida, juntas y fuera de los chips.
    expect(texto, contains('De la partida — no se pacta por duelo'));
    for (final c in BetCount.values.where((c) => c.esDeGrupo)) {
      expect(texto, contains(c.label), reason: c.name);
    }
  });
}
