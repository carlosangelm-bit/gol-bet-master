// ─────────────────────────────────────────────────────────────────────────────
// MODO INDIVIDUAL Y MODO GRUPAL
//
//     «Juego con personas mayores… es de mucha utilidad que puedan acceder a su
//      cuenta a ver los resultados mientras alguien más configura las apuestas
//      e introduce los scores. El error es que a veces no tengo la información
//      de algún duelo individual.»
//
// Con cinco jugadores hay diez cruces y de varios no se sabe qué pactaron. En
// individual son cuatro: los de quien crea la ronda.
//
// Y NO es el enlace en vivo. El enlace decide si los demás pueden ENTRAR; esto
// decide qué apuestas EXISTEN. Van juntos en una sola dirección: en individual
// el enlace no se ofrece, porque no hay nada que nadie venga a corregir.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/models/bet_recipe.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/screens/setup/setup_flow.dart';
import 'package:golf_bet_master/screens/setup/setup_screen.dart';

const _yo = 'cam';
const _cinco = [_yo, 'kawa', 'jose', 'aam', 'rich'];

Set<String> _fuera(ModoDeRonda modo, {Set<String> aMano = const {}}) =>
    crucesFueraDeLaRonda(
        participantIds: _cinco, apagadosAMano: aMano, modo: modo, yo: _yo);

List<(String, String)> _vivos(ModoDeRonda modo) {
  final fuera = _fuera(modo);
  return BetRecipe.crucesDe(_cinco)
      .where((c) => !fuera.contains(BetRecipe.cruceKey(c.$1, c.$2)))
      .toList();
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  group('1 · qué cruces existen', () {
    test('CLAVE (criterio 4): en grupal, los diez — todo como hoy', () {
      expect(BetRecipe.crucesDe(_cinco), hasLength(10));
      expect(_fuera(ModoDeRonda.grupal), isEmpty);
      expect(_vivos(ModoDeRonda.grupal), hasLength(10));
    });

    test('CLAVE (criterio 2): en individual, los cuatro míos', () {
      final vivos = _vivos(ModoDeRonda.individual);
      expect(vivos, hasLength(4));
      expect(vivos.every((c) => c.$1 == _yo || c.$2 == _yo), isTrue);
    });

    test('CLAVE: y se suma a lo apagado a mano, no lo sustituye', () {
      // Quitar un duelo propio en el paso 6 sigue funcionando dentro del modo.
      final k = BetRecipe.cruceKey(_yo, 'kawa');
      final fuera = _fuera(ModoDeRonda.individual, aMano: {k});
      expect(fuera, contains(k));
      expect(fuera, hasLength(7), reason: 'los 6 ajenos más el mío apagado');
    });

    test('CONTRAPESO: sin saber quién soy, no se apaga nada', () {
      // Preferible a adivinar: dejar los diez es lo de hoy, y equivocarse de
      // jugador dejaría a quien crea la ronda sin ninguna apuesta.
      expect(
          crucesFueraDeLaRonda(
              participantIds: _cinco,
              apagadosAMano: const {},
              modo: ModoDeRonda.individual,
              yo: null),
          isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('1b · y los MÓDULOS que se crean, que es lo que cobra', () {
    List<BetModuleInstance> modulos(ModoDeRonda modo) {
      final base = BetRecipe.build(
          cuenta: BetCount.puntos,
          participantIds: _cinco,
          holesInRound: 18,
          id: 'flujo_puntos');
      // Se le pasa el MODO, no un conjunto ya calculado: es el camino que
      // recorre el asistente. Precalcularlo aquí sería reproducir el cableado
      // en vez de ejercitarlo, y un contrapeso ya pasó en verde por eso.
      return BetRecipe.conCrucesFuera(base.module!,
          participantIds: _cinco, modo: modo, yo: _yo);
    }

    test('CLAVE (criterio 2): en individual, cuatro módulos y todos míos', () {
      // Enseñar cuatro duelos y crear diez sería el fallo de siempre: la
      // pantalla dice una cosa y la ronda cobra otra.
      final m = modulos(ModoDeRonda.individual);
      expect(m, hasLength(4));
      for (final x in m) {
        expect(x.participantIds, contains(_yo), reason: x.id);
        expect(x.participantIds, hasLength(2));
      }
    });

    test('CONTRAPESO (criterio 4): en grupal, UN módulo con los cinco', () {
      // Sin exclusiones no se parte: es la ronda de siempre, y partirla en diez
      // cambiaría cómo se lee sin cambiar lo que paga.
      final m = modulos(ModoDeRonda.grupal);
      expect(m, hasLength(1));
      expect(m.single.participantIds, _cinco);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('2 · el paso existe, y solo donde significa algo', () {
    List<SetupStep> pasos({required int jugadores, bool equipos = false}) =>
        setupSteps(
            porEquipos: equipos,
            jugadores: jugadores,
            apuestasElegidas: 2,
            conCuenta: true,
            conParticipantes: true);

    test('CLAVE (criterio 1): con tres o más, se elige', () {
      expect(pasos(jugadores: 5), contains(SetupStep.modo));
      expect(pasos(jugadores: 3), contains(SetupStep.modo));
    });

    test('CLAVE: y va ANTES de elegir qué se juega', () {
      final p = pasos(jugadores: 5);
      expect(p.indexOf(SetupStep.modo), lessThan(p.indexOf(SetupStep.cuenta)),
          reason: 'cambia cuántas apuestas hay que configurar');
    });

    test('CONTRAPESO: con dos no se pregunta — los dos modos dan lo mismo', () {
      expect(pasos(jugadores: 2), isNot(contains(SetupStep.modo)));
    });

    test('CONTRAPESO: y con equipos tampoco — la apuesta es lado contra lado',
        () {
      expect(pasos(jugadores: 4, equipos: true),
          isNot(contains(SetupStep.modo)));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('3 · en pantalla, los dos modos con cinco jugadores', () {
    Future<String> montar(WidgetTester tester, ModoDeRonda modo) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PanelPorDuelo(
              players: [
                for (final p in _cinco) Player(id: p, name: p.toUpperCase()),
              ],
              conteos: const [BetCount.puntos, BetCount.skins],
              bola: null,
              participantesDe: (_) => _cinco,
              crucesFuera: (c) => _fuera(modo),
              onAlternar: (_, __, ___) {},
              modo: modo,
              yo: _yo,
              t: GolfTheme.dark,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .join('  ‖  ');
    }

    testWidgets('CLAVE (criterio 5): en individual, cuatro con apuestas y seis '
        'sin ellas — y se dice por qué', (tester) async {
      final texto = await montar(tester, ModoDeRonda.individual);
      expect('2 apuestas entre ellos'.allMatches(texto).length, 4);
      expect('No juegan nada entre ellos'.allMatches(texto).length, 6);
      // El criterio 2 de la determinación: que nadie busque un duelo que no
      // existe.
      expect(texto, contains('Esta ronda es individual: solo se crean tus '
          'duelos'));
      expect(texto, contains('se anotan sus scores'));
    });

    testWidgets('CLAVE: y un cruce ajeno no se puede encender desde aquí',
        (tester) async {
      // El modo se elige al crear la ronda; encenderlo desde el paso 6 lo
      // dejaría encendido en la pantalla y apagado en los módulos, porque
      // `conCrucesFuera` vuelve a aplicar el modo. Un chip que no hace nada.
      var toques = 0;
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PanelPorDuelo(
              players: [
                for (final p in _cinco) Player(id: p, name: p.toUpperCase()),
              ],
              conteos: const [BetCount.puntos],
              bola: null,
              participantesDe: (_) => _cinco,
              crucesFuera: (c) => _fuera(ModoDeRonda.individual),
              onAlternar: (_, __, ___) => toques++,
              modo: ModoDeRonda.individual,
              yo: _yo,
              t: GolfTheme.dark,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // KAWA vs JOSE: ninguno soy yo.
      final ficha = find.ancestor(
          of: find.text('KAWA vs JOSE'), matching: find.byType(Container));
      await tester.tap(find.descendant(
          of: ficha.first, matching: find.text(BetCount.puntos.label)));
      await tester.pumpAndSettle();
      expect(toques, 0);

      // Y uno MÍO sí se toca: el modo no congela la ronda entera.
      final mia = find.ancestor(
          of: find.text('CAM vs KAWA'), matching: find.byType(Container));
      await tester.tap(find.descendant(
          of: mia.first, matching: find.text(BetCount.puntos.label)));
      await tester.pumpAndSettle();
      expect(toques, 1);
    });

    testWidgets('CONTRAPESO (criterio 4): en grupal, los diez con sus apuestas',
        (tester) async {
      final texto = await montar(tester, ModoDeRonda.grupal);
      expect('2 apuestas entre ellos'.allMatches(texto).length, 10);
      expect(texto, isNot(contains('Esta ronda es individual')));
    });
  });
}
