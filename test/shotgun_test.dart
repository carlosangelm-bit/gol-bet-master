// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';
// SHOTGUN — el reparto, las salidas, y lo que se dice cuando no cuadra
//
// «Crear veintidós rondas de una vez es lo que hace posible un torneo de 88
// personas con esta app.» Ese es el criterio que decide si el módulo sirve, y
// casi todo lo de aquí protege lo que tiene que ser cierto ANTES de darle al
// botón: que nadie se quede sin grupo, que ningún grupo se quede sin salida sin
// avisar, y que un campo a medio cargar no produzca veintidós salidas
// inventadas.
//
// El reparto de 150 personas es aritmética con casos raros. Cinco jugadores no
// se parten en grupos de tres o cuatro DE NINGUNA FORMA, y eso es lo que
// aparece el día del torneo si nadie lo probó antes.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:golf_bet_master/core/ancho.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/models/torneo.dart';
import 'package:golf_bet_master/providers/organizador_provider.dart';
import 'package:golf_bet_master/providers/player_provider.dart';
import 'package:golf_bet_master/providers/torneo_provider.dart';
import 'package:golf_bet_master/providers/user_profile_provider.dart';
import 'package:golf_bet_master/widgets/course_picker_sheet.dart';
import 'package:golf_bet_master/services/player_service.dart';
import 'package:golf_bet_master/screens/organizador/salidas_seccion.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/shotgun.dart';

/// Un campo de 18 con [par3] hoyos de par 3, en los hoyos que se digan.
CourseInfo _campo({Set<int> par3 = const {3, 7, 12, 16}}) => CourseInfo(
      name: 'Los Encinos',
      holes: List.generate(
          18,
          (i) => CourseHole(
              hole: i + 1,
              par: par3.contains(i + 1) ? 3 : 4,
              strokeIndex: i + 1)),
    );

List<String> _padron(int n) => [for (var i = 1; i <= n; i++) 'j$i'];

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('1 · las salidas: 18 hoyos y cuatro par 3 dan 22', () {
    test('CLAVE: los par 3 llevan A y B; los demás, ni letra', () {
      final s = salidasDe(_campo());
      expect(s.length, 22, reason: '18 + 4 letras B');

      // Y la letra donde toca: un hoyo con una sola salida NO es "1A". Decir
      // 1A invita a buscar el 1B, que no existe.
      expect(s.where((x) => x.hoyo == 1).single.letra, isNull);
      expect(s.where((x) => x.hoyo == 3).map((x) => x.letra), ['A', 'B']);
      expect(s.where((x) => x.hoyo == 16).map((x) => x.letra), ['A', 'B']);
    });

    test('CLAVE: y se cantan en orden, con la A antes de la B', () {
      final s = salidasDe(_campo());
      for (var i = 1; i < s.length; i++) {
        final orden = s[i - 1].hoyo != s[i].hoyo
            ? s[i - 1].hoyo < s[i].hoyo
            : (s[i - 1].letra ?? '').compareTo(s[i].letra ?? '') < 0;
        expect(orden, isTrue, reason: '${s[i - 1].etiqueta} → ${s[i].etiqueta}');
      }
    });

    test('la etiqueta es lo que se dice en voz alta', () {
      expect(const PuntoDeSalida(7).etiqueta, 'Hoyo 7');
      expect(const PuntoDeSalida(7, 'B').etiqueta, 'Hoyo 7B');
    });

    test('sin la opción de dos salidas, 18 y ninguna letra', () {
      // Con 40 jugadores sobran salidas, y meter dos grupos en un tee sin hacer
      // falta solo hace esperar.
      final s = salidasDe(_campo(), dosEnPar3: false);
      expect(s.length, 18);
      expect(s.every((x) => x.letra == null), isTrue);
    });

    test('CLAVE: y los par 3 se pueden marcar A MANO', () {
      // El dato del campo manda, pero el organizador que está mirando el tee
      // manda más. Un campo con los pares mal cargados es lo normal.
      final sinPar3 = _campo(par3: const {});
      expect(salidasDe(sinPar3).length, 18);
      expect(salidasDe(sinPar3, par3AMano: const {4, 9}).length, 20);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('2 · el reparto: nadie se queda corto', () {
    test('CLAVE: 150 en grupos de 4 son 38, y ninguno de dos', () {
      // Cortar la lista de cuatro en cuatro daría 37 grupos de 4 y uno de DOS
      // —y ese es el que va a esperar a los otros 37 en un shotgun—.
      final p = planDeShotgun(
          padron: _padron(150), campo: _campo(), tamano: 4);
      expect(p.grupos.length, 38);
      final tamanos = p.grupos.map((g) => g.jugadores.length).toList();
      expect(tamanos.where((x) => x == 4).length, 36);
      expect(tamanos.where((x) => x == 3).length, 2);
      expect(tamanos.every((x) => x >= 3), isTrue);
    });

    test('CLAVE: y no se pierde ni se duplica nadie', () {
      // Es la comprobación que un reparto tiene que pasar siempre: la unión de
      // los grupos es el padrón, exactamente.
      for (final n in [1, 2, 3, 4, 5, 7, 12, 63, 88, 150]) {
        final p = planDeShotgun(
            padron: _padron(n), campo: _campo(), tamano: 4);
        final todos = p.grupos.expand((g) => g.jugadores).toList();
        expect(todos.length, n, reason: 'con $n');
        expect(todos.toSet().length, n, reason: 'duplicados con $n');
        expect(todos.toSet(), _padron(n).toSet(), reason: 'con $n');
      }
    });

    test('la diferencia entre el grupo mayor y el menor nunca pasa de uno', () {
      for (final n in [7, 13, 26, 63, 88, 150]) {
        for (final tam in [3, 4]) {
          final p = planDeShotgun(
              padron: _padron(n), campo: _campo(), tamano: tam);
          final t = p.grupos.map((g) => g.jugadores.length).toList();
          expect(t.reduce((a, b) => a > b ? a : b) -
                  t.reduce((a, b) => a < b ? a : b),
              lessThanOrEqualTo(1),
              reason: '$n en grupos de $tam');
        }
      }
    });

    test('CLAVE: cinco jugadores NO se parten en 3 o 4, y se dice', () {
      // El caso raro. 5 = 4+1 o 3+2, y ninguno vale. Callarlo dejaría un grupo
      // de dos sin que nadie lo hubiera decidido.
      final p = planDeShotgun(padron: _padron(5), campo: _campo(), tamano: 4);
      expect(p.aviso, isNotNull);
      expect(p.aviso, contains('no se reparten en grupos de 3 o 4'));
      // Y sigue siendo utilizable: la decisión es del organizador, no de esto.
      expect(p.utilizable, isTrue);
    });

    test('cada grupo lleva SU salida, en orden', () {
      final p = planDeShotgun(padron: _padron(12), campo: _campo(), tamano: 4);
      expect(p.grupos.length, 3);
      expect(p.grupos[0].salida, const PuntoDeSalida(1));
      expect(p.grupos[1].salida, const PuntoDeSalida(2));
      expect(p.grupos[2].salida, const PuntoDeSalida(3, 'A'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 3 · CUANDO NO CUADRA, CON EL NÚMERO
  //
  // «Que lo diga con el número, no que reparta como se pueda.»
  // ───────────────────────────────────────────────────────────────────────────
  group('3 · lo que se dice cuando no cuadra', () {
    test('CLAVE: 24 grupos en 22 salidas — no caben 2, y lo dice', () {
      // 93 jugadores en grupos de 4 son 24 grupos.
      final p = planDeShotgun(padron: _padron(93), campo: _campo(), tamano: 4);
      expect(p.grupos.length, 24);
      expect(p.impedimento, isNotNull);
      expect(p.impedimento, contains('24 grupos'));
      expect(p.impedimento, contains('22 salidas'));
      expect(p.impedimento, contains('no caben 2'));
      // Y no se puede crear: repartir "como se pueda" es lo que no se hace.
      expect(p.utilizable, isFalse);
    });

    test('CLAVE: 20 grupos en 22 salidas — sobran 2, y eso NO impide', () {
      final p = planDeShotgun(padron: _padron(78), campo: _campo(), tamano: 4);
      expect(p.grupos.length, 20);
      expect(p.impedimento, isNull, reason: 'sobrar salidas no es un error');
      expect(p.aviso, contains('sobran 2'));
      expect(p.utilizable, isTrue);
    });

    test('CLAVE: sin campo, se dice — no se suponen 18 hoyos', () {
      // Suponer 18 con cuatro par 3 daría 22 salidas inventadas, y el
      // organizador se enteraría en el tee.
      final p = planDeShotgun(padron: _padron(80), campo: null);
      // Y NO se manda a otra pantalla: el selector está arriba, en la misma
      // sección. El mensaje decía "elige el campo y vuelve" cuando no había
      // dónde elegirlo.
      expect(p.impedimento, contains('arriba'));
      expect(p.impedimento, isNot(contains('vuelve')));
      expect(p.salidas, isEmpty);
      expect(p.utilizable, isFalse);
    });

    test('CLAVE: un campo SIN HOYOS se dice con su nombre', () {
      // Criterio 5. Un campo a medio cargar no es un campo estándar.
      final p = planDeShotgun(
          padron: _padron(80),
          campo: const CourseInfo(name: 'Bosques', holes: []));
      expect(p.impedimento, contains('Bosques'));
      // Y NO ofrece marcar par 3 a mano: sin ningún hoyo no se sabe cuántos
      // habría que marcar. Ofrecer una salida que no existe es el fallo que
      // este mensaje tenía.
      expect(p.impedimento, isNot(contains('par 3 a mano')));
      expect(p.impedimento, contains('Elige otro campo'));
      expect(p.utilizable, isFalse);
    });

    test('sin nadie inscrito, se dice de dónde salen los grupos', () {
      final p = planDeShotgun(padron: const [], campo: _campo());
      expect(p.impedimento, contains('padrón'));
      expect(p.salidas.length, 22, reason: 'las salidas sí se saben');
    });

    test('CONTRAPESO: y el caso que cuadra JUSTO no avisa de nada', () {
      // 22 grupos en 22 salidas. Sin esto, un aviso siempre presente pasaría
      // los tests de arriba y no significaría nada.
      final p = planDeShotgun(padron: _padron(88), campo: _campo(), tamano: 4);
      expect(p.grupos.length, 22);
      expect(p.impedimento, isNull);
      expect(p.aviso, isNull);
      expect(p.utilizable, isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('4 · mover a alguien de grupo', () {
    test('CLAVE: se va de donde estaba y llega al destino', () {
      final p = planDeShotgun(padron: _padron(12), campo: _campo(), tamano: 4);
      final movidos = moviendo(p.grupos, 'j1', 2);
      expect(movidos[0].jugadores, isNot(contains('j1')));
      expect(movidos[2].jugadores, contains('j1'));
      // Y no aparece dos veces, que es el fallo de mover mal.
      expect(movidos.expand((g) => g.jugadores).where((x) => x == 'j1').length,
          1);
    });

    test('CLAVE: la SALIDA no se mueve con el jugador', () {
      // La salida es del grupo. Cambiar de grupo es cambiar de salida, y eso
      // es lo que se está pidiendo.
      final p = planDeShotgun(padron: _padron(12), campo: _campo(), tamano: 4);
      final movidos = moviendo(p.grupos, 'j1', 2);
      for (var i = 0; i < movidos.length; i++) {
        expect(movidos[i].salida, p.grupos[i].salida, reason: 'grupo $i');
      }
    });

    test('CONTRAPESO: mover al grupo donde ya está no cambia nada', () {
      final p = planDeShotgun(padron: _padron(12), campo: _campo(), tamano: 4);
      expect(identical(moviendo(p.grupos, 'j1', 0), p.grupos), isTrue);
      // Y un destino imposible tampoco: en el tee no se lanza.
      expect(identical(moviendo(p.grupos, 'j1', 99), p.grupos), isTrue);
      expect(identical(moviendo(p.grupos, 'j1', -1), p.grupos), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('5 · las rondas que se crean', () {
    Map<String, Player> _porId(int n) => {
          for (var i = 1; i <= n; i++)
            'j$i': Player(id: 'j$i', name: 'Jugador $i'),
        };

    test('CLAVE: una por grupo, y se llaman por su SALIDA', () {
      // "Hoyo 7B" y no "Grupo 14": el organizador canta salidas y el jugador
      // busca su hoyo. Y en Scores en vivo, 22 "Grupo N" no dicen dónde está
      // ninguno.
      final p = planDeShotgun(padron: _padron(88), campo: _campo(), tamano: 4);
      final rondas = rondasDelPlan(
          plan: p,
          torneoId: 't1',
          campo: _campo(),
          porId: _porId(88),
          cuando: DateTime(2026, 8, 30));
      expect(rondas.length, 22);
      expect(rondas.first.name, 'Hoyo 1');
      expect(rondas.map((r) => r.name), contains('Hoyo 3B'));
    });

    test('CLAVE: llevan la marca del torneo — sin ella son rondas sueltas', () {
      // Es lo que hace que aparezcan solas en la tabla y en el portal.
      final p = planDeShotgun(padron: _padron(12), campo: _campo());
      final rondas = rondasDelPlan(
          plan: p,
          torneoId: 't1',
          campo: _campo(),
          porId: _porId(12),
          cuando: DateTime(2026, 8, 30));
      expect(rondas.every((r) => r.torneoIds.contains('t1')), isTrue);
    });

    test('CLAVE: el id es DETERMINISTA — volver a crear no duplica', () {
      // Un botón lento produce dobles pulsaciones solo. Con ids deterministas,
      // la segunda actualiza en vez de crear otros veintidós grupos.
      final p = planDeShotgun(padron: _padron(88), campo: _campo());
      List<String> ids() => rondasDelPlan(
            plan: p,
            torneoId: 't1',
            campo: _campo(),
            porId: _porId(88),
            cuando: DateTime(2026, 8, 30),
          ).map((r) => r.id).toList();
      expect(ids(), equals(ids()));
      expect(ids().toSet().length, ids().length, reason: 'ids repetidos');
      expect(ids().first, 't1_s1');
      expect(ids(), contains('t1_s3B'));
    });

    test('CLAVE: los jugadores son los del grupo, con su nombre', () {
      final p = planDeShotgun(padron: _padron(12), campo: _campo());
      final rondas = rondasDelPlan(
          plan: p,
          torneoId: 't1',
          campo: _campo(),
          porId: _porId(12),
          cuando: DateTime(2026, 8, 30));
      expect(rondas.first.players.map((x) => x.name),
          ['Jugador 1', 'Jugador 2', 'Jugador 3', 'Jugador 4']);
      // Y el organizador captura: en un shotgun de 88 no todos traen la app.
      expect(rondas.first.scoringMode, 'admin');
    });

    test('el handicap entra si se pasa, y no si no', () {
      final p = planDeShotgun(padron: _padron(4), campo: _campo());
      final sin = rondasDelPlan(
          plan: p,
          torneoId: 't1',
          campo: _campo(),
          porId: _porId(4),
          cuando: DateTime(2026, 8, 30));
      expect(sin.first.roundPlayers.every((rp) => rp.handicapEnRonda == 0),
          isTrue);
      final con = rondasDelPlan(
          plan: p,
          torneoId: 't1',
          campo: _campo(),
          porId: _porId(4),
          cuando: DateTime(2026, 8, 30),
          handicaps: const {'j1': 12.5});
      expect(con.first.roundPlayers.first.handicapEnRonda, 12.5);
    });

    test('CONTRAPESO: un grupo SIN salida no produce ronda', () {
      // No se crea una ronda cuyo nombre no puede decir de dónde sale. El plan
      // ya lo impide con su motivo; esto es el cinturón.
      final p = planDeShotgun(padron: _padron(93), campo: _campo(), tamano: 4);
      expect(p.grupos.where((g) => g.salida == null).length, 2);
      final rondas = rondasDelPlan(
          plan: p,
          torneoId: 't1',
          campo: _campo(),
          porId: _porId(93),
          cuando: DateTime(2026, 8, 30));
      expect(rondas.length, 22, reason: 'las 22 que sí tienen salida');
    });

    test('CONTRAPESO: y las apuestas van vacías a propósito', () {
      // Rellenarlas aquí sería decidir por 88 personas a la vez.
      final p = planDeShotgun(padron: _padron(12), campo: _campo());
      final rondas = rondasDelPlan(
          plan: p,
          torneoId: 't1',
          campo: _campo(),
          porId: _porId(12),
          cuando: DateTime(2026, 8, 30));
      expect(rondas.every((r) => r.betGroups.isEmpty), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 6 · Y QUE SE VEA EN LA PANTALLA
  //
  // Los grupos de arriba prueban el cálculo. Estos prueban que llega a los ojos
  // del organizador: un impedimento correcto que la pantalla no pinta es un
  // impedimento que no existe.
  // ───────────────────────────────────────────────────────────────────────────
  group('6 · la pantalla dice lo que el plan calcula', () {
    Torneo torneo({int inscritos = 88, CourseInfo? campo}) => Torneo(
          id: 't1',
          nombre: 'Copa',
          participantes: _padron(inscritos),
          campo: campo ?? _campo(),
        );

    testWidgets('CLAVE: 22 grupos en 22 salidas, y el botón dice cuántas',
        (tester) async {
      // El criterio que decide si el módulo sirve: UNA acción, y que diga qué
      // va a hacer antes de hacerlo.
      await montarSeccion(tester, torneo());
      final txt = textoDe(tester);
      expect(txt, contains('Crear 22 rondas'));
      expect(txt, contains('22 salidas'));
      // Y las salidas como título de cada grupo, no "Grupo 14".
      expect(txt, contains('Hoyo 3A'));
      expect(txt, contains('Hoyo 3B'));
    });

    testWidgets('CLAVE: cuando no caben, la pantalla lo dice con el número',
        (tester) async {
      await montarSeccion(tester, torneo(inscritos: 93));
      final txt = textoDe(tester);
      expect(txt, contains('24 grupos'));
      expect(txt, contains('no caben 2'));
      // Y el botón NO se puede pulsar: repartir como se pueda es lo que no se
      // hace.
      final boton = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(boton.onPressed, isNull);
    });

    testWidgets('CLAVE: un campo sin hoyos se dice, y con su nombre',
        (tester) async {
      await montarSeccion(tester,
          torneo(campo: const CourseInfo(name: 'Bosques', holes: [])));
      final txt = textoDe(tester);
      expect(txt, contains('Bosques'));
      expect(txt, contains('par 3'));
      final boton = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(boton.onPressed, isNull);
    });

    testWidgets('CONTRAPESO: y con todo en orden el botón SÍ se puede pulsar',
        (tester) async {
      // Sin esto, un botón siempre apagado pasaría los dos tests de arriba.
      await montarSeccion(tester, torneo(inscritos: 78));
      final boton = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(boton.onPressed, isNotNull);
      expect(textoDe(tester), contains('sobran 2'),
          reason: 'sobrar salidas se avisa pero no impide');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 7 · EL CAMPO SE ELIGE DONDE EL AVISO LO PIDE
  //
  // «No hay dónde cargar el campo. El aviso dice "elige el campo y vuelve" — y
  // no hay dónde elegirlo.»
  //
  // Había dos posibilidades muy distintas y ninguna era la buena:
  //
  //   A · la opción del editor no hace nada    → NO: abre el selector y guarda
  //   B · lo guarda y no llega aquí            → NO: la cadena está entera
  //
  // Era lo otro: el aviso mandaba a un sitio que no nombraba, y ese sitio está
  // en OTRA superficie. Los dos primeros tests de aquí abajo son la prueba de
  // que A y B no eran — si algún día una de las dos SE VUELVE verdad, fallan.
  // ───────────────────────────────────────────────────────────────────────────
  group('7 · el campo del torneo: la cadena y el selector', () {
    test('CLAVE: fijar el campo sobrevive a copyWith y a Firestore', () {
      // Descarta A y B de una vez: si `copyWith` o el viaje perdieran el campo,
      // el editor haría su trabajo y la sección seguiría sin verlo.
      final campo = _campo();
      final t = Torneo(id: 't1', nombre: 'Copa').copyWith(campo: campo);
      expect(t.campo?.name, 'Los Encinos');
      expect(t.campo?.holes.length, 18);

      final vuelta = Torneo.fromJson(t.toJson());
      expect(vuelta.campo?.name, 'Los Encinos');
      expect(vuelta.campo?.holes.where((h) => h.isPar3).length, 4,
          reason: 'los PARES tienen que viajar, no solo el nombre');
    });

    test('CLAVE: y quitarlo también llega', () {
      final t = Torneo(id: 't1', nombre: 'Copa', campo: _campo())
          .copyWith(limpiarCampo: true);
      expect(t.campo, isNull);
      expect(Torneo.fromJson(t.toJson()).campo, isNull);
    });

    testWidgets('CLAVE: la sección enseña el campo con sus DOS números',
        (tester) async {
      // El nombre solo no basta: un campo mal cargado —18 hoyos y ningún par—
      // se ve idéntico a uno bueno hasta llegar al reparto.
      await montarSeccion(tester,
          Torneo(id: 't1', nombre: 'Copa',
              participantes: _padron(88), campo: _campo()));
      final txt = textoDe(tester);
      expect(txt, contains('EL CAMPO'));
      expect(txt, contains('Los Encinos'));
      expect(txt, contains('18 hoyos'));
      expect(txt, contains('4 par 3'));
    });

    testWidgets('CLAVE: sin campo, el botón de elegirlo está AQUÍ',
        (tester) async {
      // El criterio 1. Antes el aviso mandaba a otra pantalla sin nombrarla.
      await montarSeccion(tester,
          Torneo(id: 't1', nombre: 'Copa', participantes: _padron(88)));
      final txt = textoDe(tester);
      expect(txt, contains('Sin campo todavía'));
      expect(txt, contains('Tócalo para elegirlo'));
      // Y el aviso ya no manda a ningún sitio que no esté a la vista.
      expect(txt, contains('arriba'));
      expect(txt, isNot(contains('y vuelve')));
    });

    testWidgets('y tocarlo abre el MISMO selector de siempre', (tester) async {
      // Uno propio aquí habría dado dos formas de elegir campo y dos
      // resultados para el mismo club.
      await montarSeccion(tester,
          Torneo(id: 't1', nombre: 'Copa', participantes: _padron(88)));
      await tester.tap(find.text('Sin campo todavía'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(CoursePickerSheet), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('8 · los par 3 a mano, en los dos sentidos', () {
    test('CLAVE: la lista SUSTITUYE al campo, no se le suma', () {
      // Sumarse solo permitiría añadir. Y hace falta quitar: un campo mal
      // cargado puede traer un par 3 donde hay un par 4, y ahí la app pondría
      // dos grupos en un tee donde no caben.
      final campo = _campo(par3: const {3, 7, 12, 16});
      expect(salidasDe(campo).length, 22);
      // Dictando SOLO dos, quedan dos: los otros dos del campo se quitan.
      expect(salidasDe(campo, par3AMano: const {3, 7}).length, 20);
      // Y dictando ninguno de los del campo, ninguno cuenta.
      expect(salidasDe(campo, par3AMano: const {5}).length, 19);
    });

    test('CLAVE: vacío manda el campo — que es el caso normal', () {
      // El contrapeso del test de arriba: si la lista vacía sustituyera, un
      // campo con cuatro par 3 daría 18 salidas y nadie habría pedido eso.
      expect(salidasDe(_campo()).length, 22);
    });

    test('un campo sin ningún par 3 da 18, y con dictado los que se digan', () {
      final pelado = _campo(par3: const {});
      expect(salidasDe(pelado).length, 18);
      expect(salidasDe(pelado, par3AMano: const {4, 9, 14, 17}).length, 22);
    });

    testWidgets('CLAVE: y la pantalla lo ofrece cuando puede hacer falta',
        (tester) async {
      // El caso que produce 18 salidas en silencio: el campo no trae pares.
      await montarSeccion(tester,
          Torneo(id: 't1', nombre: 'Copa',
              participantes: _padron(60), campo: _campo(par3: const {})));
      final txt = textoDe(tester);
      expect(txt, contains('no trae ningún par 3'));
      expect(txt, contains('18 salidas'), reason: 'y dice cuántas hay ahora');
    });

    testWidgets('con los pares bien, dice cuáles son en vez de callarse',
        (tester) async {
      await montarSeccion(tester,
          Torneo(id: 't1', nombre: 'Copa',
              participantes: _padron(60), campo: _campo()));
      expect(textoDe(tester), contains('Par 3 según el campo: 3, 7, 12, 16'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 9 · QUE LA SECCIÓN SE ENTERE SIN RECARGAR
  //
  // «Si recargo la página, sí se muestra actualizado. Pero la sección sigue
  // diciendo "Sin campo todavía" hasta que se recarga. El organizador elige el
  // campo, ve el mismo aviso rojo, y concluye que falló.»
  //
  // Dos causas, y las dos son la familia de siempre —el dato llega y la
  // superficie no se entera—:
  //
  //   1 · `CoursePickerSheet._pickTee` hace su PROPIO Navigator.pop antes de
  //       llamar al callback. Popear otra vez desde el callback se lleva la
  //       ruta de debajo, que es el portal entero.
  //   2 · el campo venía en `widget.torneo`: una copia que solo se renueva si
  //       el PADRE reconstruye.
  //
  // Este test cubre la segunda, que es la estructural: guarda por el provider y
  // exige que la sección lo enseñe SIN volver a montarla.
  // ───────────────────────────────────────────────────────────────────────────
  group('9 · el campo elegido se ve sin recargar', () {
    testWidgets('CLAVE: guardar el campo actualiza la sección en el sitio',
        (tester) async {
      final t = Torneo(
          id: 't1', nombre: 'Copa', participantes: _padron(88));
      final prov = TorneoProvider()..sembrar([t]);

      tester.view.physicalSize = const Size(1440, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(
              create: (_) => PlayerProvider()
                ..sembrar([
                  for (var i = 1; i <= 150; i++)
                    PlayerWithLink(
                        player: Player(id: 'j$i', name: 'Jugador $i')),
                ])),
          ChangeNotifierProvider<TorneoProvider>.value(value: prov),
          ChangeNotifierProvider(create: (_) => UserProfileProvider()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: LayoutBuilder(
              // El torneo del ARGUMENTO se queda sin campo a propósito: es la
              // copia vieja. Si la sección lo leyera de aquí, este test
              // fallaría — y era exactamente el fallo.
              builder: (_, c) => SalidasSeccion(
                  torneo: t,
                  ancho: anchoDe(c.maxWidth),
                  t: GolfTheme.classic),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 200));
      expect(textoDe(tester), contains('Sin campo todavía'));

      // Lo que hace elegir un campo, sin pasar por la hoja.
      prov.sembrar([t.copyWith(campo: _campo())]);
      await tester.pump();

      final txt = textoDe(tester);
      expect(txt, contains('Los Encinos'), reason: 'sin recargar nada');
      expect(txt, isNot(contains('Sin campo todavía')));
      // Y todo lo de abajo se rellena: las salidas salen de sus hoyos.
      expect(txt, contains('22 salidas'));
      expect(txt, contains('Crear 22 rondas'));
    });

    testWidgets('CONTRAPESO: y sin campo sigue diciéndolo', (tester) async {
      // Sin esto, una sección que enseñara siempre un campo pasaría el test de
      // arriba.
      await montarSeccion(tester,
          Torneo(id: 't1', nombre: 'Copa', participantes: _padron(88)));
      expect(textoDe(tester), contains('Sin campo todavía'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('10 · la regla que faltaba: courseCorrections', () {
    String reglaDe(String coleccion) {
      final texto = File('firestore.rules').readAsStringSync();
      final i = texto.indexOf('match /$coleccion/');
      expect(i, greaterThan(-1), reason: 'no existe la regla de $coleccion');
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

    test('CLAVE: existe — no tenerla era el permission-denied', () {
      // No era una regla estricta: era que NO HABÍA NINGUNA, así que el deny
      // por defecto mandaba y el servicio llevaba desde el primer día pidiendo
      // un documento que nadie le podía dar.
      final r = reglaDe('courseCorrections');
      expect(r, contains('allow get:'));
    });

    test('CLAVE: GET y no READ — el servicio nunca lista', () {
      // Cuarta vez que esta distinción aparece en el fichero. `read` habría
      // concedido de paso el listado de todos los campos corregidos, que
      // ningún código pide.
      final r = reglaDe('courseCorrections');
      expect(r.contains('allow read'), isFalse);
      expect(r, contains('allow list: if false'));
    });

    test('CLAVE: y nadie escribe — las correcciones se curan a mano', () {
      // Un write abierto dejaría que cualquiera con cuenta cambiara los pares
      // de un campo para TODOS: eso mueve handicaps y clasificaciones ajenas.
      final r = reglaDe('courseCorrections');
      expect(r, contains('allow write: if false'));
    });

    test('CONTRAPESO: y el servicio de verdad no lista ni escribe', () {
      // La regla dice "solo get". Esto comprueba que el código no pide más —
      // si mañana alguien añade un `.where(...)`, la regla lo rechazará en
      // producción y no en la revisión, que es demasiado tarde.
      final codigo =
          File('lib/services/course_corrections_service.dart').readAsStringSync();
      for (final prohibido in ['.where(', '.set(', '.update(', '.add(']) {
        expect(codigo.contains('_corrections$prohibido'), isFalse,
            reason: prohibido);
      }
      expect(codigo, contains('_corrections.doc('));
    });
  });
}

/// Monta la sección con el torneo dado. Compartido por los grupos 6, 7 y 8.
Future<void> montarSeccion(WidgetTester tester, Torneo t) async {
  // Una ventana muy alta a propósito: un ListView no construye lo que no se ve,
  // y el botón vive debajo de veinticuatro grupos.
  tester.view.physicalSize = const Size(1440, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(
          create: (_) => PlayerProvider()
            ..sembrar([
              for (var i = 1; i <= 150; i++)
                PlayerWithLink(player: Player(id: 'j$i', name: 'Jugador $i')),
            ])),
      ChangeNotifierProvider(create: (_) => TorneoProvider()..sembrar([t])),
      // La marca de organizador: el logo de Inicio la consulta. En false,
      // que es una cuenta normal — es lo que estos tests miran.
      ChangeNotifierProvider<OrganizadorProvider>(
          create: (_) => OrganizadorProvider()..sembrar(false)),
      // El selector de campo enseña los favoritos del perfil, así que necesita
      // su provider. Montar con menos escondería que la hoja no abre.
      ChangeNotifierProvider(create: (_) => UserProfileProvider()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: LayoutBuilder(
          builder: (_, c) => SalidasSeccion(
              torneo: t, ancho: anchoDe(c.maxWidth), t: GolfTheme.classic),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 200));
}

String textoDe(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .join(' · ');
