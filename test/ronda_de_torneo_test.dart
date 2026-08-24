// ─────────────────────────────────────────────────────────────────────────────
// LA RONDA QUE NACE DENTRO DEL TORNEO
//
// La corrección de dirección, probada. El torneo dejó de ser una vista sobre
// rondas que ya existen y pasó a ser el evento del que salen, y lo que eso
// significa en concreto es que RESPONDE preguntas de la ronda: el padrón, la
// ventaja, el campo y la marca.
//
// Lo que estos tests protegen, por orden de lo que más caro saldría:
//
//   1 · El handicap. Es el único sitio de todo esto donde el diseño podía colar
//       un número plausible y equivocado: la instantánea no lleva handicaps, así
//       que una ficha materializada nace en 0. Con "sin ventaja" no se pregunta
//       porque no interviene; con handicap o sliding SÍ.
//   2 · La marca. Una ronda del torneo que se juega y no cuenta es el peor de
//       los dos silencios: todo parece ir bien y la tabla no se mueve.
//   3 · Qué NO viaja en la instantánea. La plantilla lleva ids de jugador en sus
//       reglas por duelo, así que no entra, y el seguidor elige sus apuestas.
//   4 · El puente por nombre. Resolver el padrón contra las fichas que ya hay
//       tiene que normalizar IGUAL que el filtro de resultados publicados, o la
//       misma persona entra dos veces con la mitad de su historial cada una.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/punto_de_torneo.dart';
import 'package:golf_bet_master/models/round_result.dart';
import 'package:golf_bet_master/models/torneo.dart';
import 'package:golf_bet_master/models/torneo_publicado.dart';
import 'package:golf_bet_master/providers/betting_group_provider.dart';
import 'package:golf_bet_master/providers/handicap_provider.dart';
import 'package:golf_bet_master/providers/perfil_provider.dart';
import 'package:golf_bet_master/providers/player_provider.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/providers/torneo_provider.dart';
import 'package:golf_bet_master/providers/user_profile_provider.dart';
import 'package:golf_bet_master/services/player_service.dart';
import 'package:golf_bet_master/screens/setup/quick_start_screen.dart';
import 'package:golf_bet_master/providers/auth_provider.dart';
import 'package:golf_bet_master/screens/torneos/torneo_editor_screen.dart';
import 'package:golf_bet_master/screens/torneos/torneos_screen.dart';

const ana = 'pid_a', beto = 'pid_b', caro = 'pid_c', dani = 'pid_d';
const cuatro = [ana, beto, caro, dani];
const nombres = {
  ana: 'Luis Herrera',
  beto: 'Ana Ruiz',
  caro: 'Dani Sotó',
  dani: 'Rafa Gil'
};

Torneo _liga({
  VentajaDeTorneo? ventaja,
  CourseInfo? campo,
  String? plantillaId,
  List<String> participantes = cuatro,
  bool cerrado = false,
}) =>
    Torneo(
      id: 'cp',
      nombre: 'Copa de Primavera',
      fuente: FuenteDeRondas.marcadas,
      metodo: MetodoDePuntuacion.dinero,
      participantes: participantes,
      ventaja: ventaja,
      campo: campo,
      plantillaId: plantillaId,
      cerrado: cerrado,
    );

TorneoPublicado _publicar(Torneo t) {
  final tabla = tablaDe(t, const <RoundResult>[], nombres: nombres);
  return TorneoPublicado.desde(
    token: 'tok',
    ownerUid: 'uid_org',
    torneo: t,
    tabla: tabla,
    bote: boteDe(t, tabla),
    jornadas: botesPorJornada(t, tabla),
    cuando: DateTime(2026, 8, 24),
    nombres: nombres,
  );
}

final _campoPrueba = CourseInfo(name: 'Los Encinos', holes: const [
  CourseHole(hole: 1, par: 4, strokeIndex: 1),
  CourseHole(hole: 2, par: 3, strokeIndex: 2),
]);

void main() {
  group('1 · el padrón viaja, y por los dos caminos sale igual', () {
    test('desde MI torneo: los inscritos con el nombre del directorio', () {
      final p = PuntoDeTorneo.propio(_liga(), nombres: nombres);
      expect(p.padron, ['Luis Herrera', 'Ana Ruiz', 'Dani Sotó', 'Rafa Gil']);
      // El organizador SÍ tiene ficha de todos: son de su directorio.
      expect(p.sinFicha, isEmpty);
      expect(p.fichaDe['Luis Herrera'], ana);
      expect(p.utilizable, isTrue);
    });

    test('desde la instantánea: los mismos nombres, sin ninguna ficha', () {
      // Y con CERO rondas jugadas, que es justo cuando hace falta para crear la
      // primera. Verificado antes de construir nada sobre esto.
      final p = PuntoDeTorneo.seguido(_publicar(_liga()));
      expect(p.padron.toSet(),
          {'Luis Herrera', 'Ana Ruiz', 'Dani Sotó', 'Rafa Gil'});
      expect(p.sinFicha.length, 4);
      expect(p.utilizable, isTrue);
    });

    test('un inscrito sin nombre resoluble NO entra como guion', () {
      // Un id crudo o un '—' en una lista de jugadores es lo que ya nos dijo
      // "esto está a medias" más alto que cualquier otra cosa.
      final p = PuntoDeTorneo.propio(_liga(), nombres: const {ana: 'Luis'});
      expect(p.padron, ['Luis']);
      expect(p.padron, isNot(contains(sinNombre)));
    });

    test('sin participantes no es utilizable, y sin id del torneo tampoco', () {
      expect(
          PuntoDeTorneo.propio(_liga(participantes: const []), nombres: nombres)
              .utilizable,
          isFalse);
      // Instantánea vieja, publicada antes de que el id del torneo viajara: la
      // ronda no se podría marcar, así que no se ofrece crearla.
      const vieja = PuntoDeTorneo(
          torneoId: '', nombre: 'X', emoji: '🏆', padron: ['Luis']);
      expect(vieja.utilizable, isFalse);
    });
  });

  group('2 · el puente por nombre, que es el que evita la persona duplicada',
      () {
    test('resuelve contra las fichas que ya hay, sin acentos ni mayúsculas', () {
      final p = PuntoDeTorneo.seguido(_publicar(_liga()));
      // El seguidor ya tiene a dos de una ronda anterior, escritos a su manera.
      final con = p.conFichas({'luis herrera': 'mio_1', 'Dani Soto': 'mio_2'});
      expect(con.fichaDe['Luis Herrera'], 'mio_1');
      // 'Dani Sotó' con acento contra 'Dani Soto' sin él: si esto no cruzara,
      // la segunda ronda del torneo crearía a Dani otra vez y su historial se
      // partiría en dos sin que nadie lo viera.
      expect(con.fichaDe['Dani Sotó'], 'mio_2');
      expect(con.sinFicha.toSet(), {'Ana Ruiz', 'Rafa Gil'});
    });

    test('y normaliza IGUAL que el filtro de resultados publicados', () {
      // La garantía está repartida en dos sitios y ninguno es redundante: si uno
      // normalizara distinto, el nombre coincidiría para el ojo y no para el
      // código. Se prueba el mismo par por los dos caminos.
      final t = _liga();
      final cuenta = resultadosQueCuentan(
        t,
        [
          (
            jugadorNombre: 'dani soto',
            resultado: RoundResult(
              roundId: 'r1',
              roundName: 'Sábado',
              courseName: 'X',
              playedAt: DateTime(2026, 5, 1),
              holesPlayed: 18,
              playerIds: const [],
              playerNames: const {},
              balances: const {},
              pairBalances: const {},
              grossByPlayer: const {},
              netByPlayer: const {},
              stablefordByPlayer: const {},
            )
          )
        ],
        nombres: nombres,
      );
      expect(cuenta.length, 1, reason: 'el filtro cruza dani soto → Dani Sotó');
      final p = PuntoDeTorneo.seguido(_publicar(t))
          .conFichas({'dani soto': 'mio_2'});
      expect(p.fichaDe['Dani Sotó'], 'mio_2',
          reason: 'y el padrón tiene que cruzar el mismo par');
    });
  });

  group('3 · EL HANDICAP: el único sitio donde esto podía colar un número mal',
      () {
    test('sin ventaja NO se pregunta: no interviene en nada', () {
      final p = PuntoDeTorneo.propio(_liga(ventaja: VentajaDeTorneo.ninguna),
          nombres: nombres);
      expect(p.pideHandicap, isFalse);
      expect(VentajaDeTorneo.ninguna.usaHandicap, isFalse);
    });

    test('con handicap SÍ, y con sliding TAMBIÉN', () {
      // Sliding parte del handicap y se mueve desde ahí, así que un 0 falso
      // arrastra igual. Es el que más fácil se daría por bueno.
      for (final v in [VentajaDeTorneo.handicap, VentajaDeTorneo.sliding]) {
        expect(
            PuntoDeTorneo.propio(_liga(ventaja: v), nombres: nombres)
                .pideHandicap,
            isTrue,
            reason: v.name);
        expect(v.usaHandicap, isTrue, reason: v.name);
      }
    });

    test('sin ventaja DECIDIDA se pregunta: no saber no es no importar', () {
      final p = PuntoDeTorneo.propio(_liga(), nombres: nombres);
      expect(p.ventaja, isNull);
      expect(p.pideHandicap, isTrue);
    });
  });

  group('4 · qué viaja en la instantánea y qué no', () {
    test('la ventaja y el campo SÍ: son configuración, no personas', () {
      final c = _publicar(_liga(
          ventaja: VentajaDeTorneo.sliding, campo: _campoPrueba));
      expect(c.ventaja, VentajaDeTorneo.sliding);
      expect(c.campo?.name, 'Los Encinos');
      // Y sobreviven al viaje por Firestore.
      final ida = TorneoPublicado.fromJson('tok', c.toJson());
      expect(ida.ventaja, VentajaDeTorneo.sliding);
      expect(ida.campo?.holes.length, 2);
    });

    test('la PLANTILLA no: sus reglas por duelo llevan ids de jugador', () {
      final c = _publicar(_liga(plantillaId: 'bg_1'));
      final json = c.toJson().toString();
      expect(json.contains('bg_1'), isFalse,
          reason: 'publicar la plantilla expondría ids de jugador');
      // Y el seguidor lo sabe: hereda con quién, con qué ventaja y dónde, y
      // elige qué se apuesta.
      expect(PuntoDeTorneo.seguido(c).conPlantilla, isFalse);
    });

    test('el organizador sí la tiene, y entonces la ronda la hereda', () {
      final p =
          PuntoDeTorneo.propio(_liga(plantillaId: 'bg_1'), nombres: nombres);
      expect(p.conPlantilla, isTrue);
    });
  });

  group('5 · los tres campos nuevos del torneo, ida y vuelta', () {
    test('se guardan y se leen', () {
      final t = _liga(
          ventaja: VentajaDeTorneo.handicap,
          campo: _campoPrueba,
          plantillaId: 'bg_9');
      final ida = Torneo.fromJson(t.toJson());
      expect(ida.ventaja, VentajaDeTorneo.handicap);
      expect(ida.campo?.name, 'Los Encinos');
      expect(ida.plantillaId, 'bg_9');
    });

    test('un torneo guardado ANTES de que existieran se lee igual', () {
      // Aditivos: si no hay nada que decir no se escribe, así que Copa de
      // Primavera de la semana pasada abre sin cambiar de comportamiento.
      final viejo = _liga().toJson();
      expect(viejo.containsKey('ventaja'), isFalse);
      expect(viejo.containsKey('campo'), isFalse);
      expect(viejo.containsKey('plantillaId'), isFalse);
      final leido = Torneo.fromJson(viejo);
      expect(leido.ventaja, isNull);
      expect(leido.campo, isNull);
      expect(leido.plantillaId, isNull);
    });

    test('un campo malformado deja el torneo sin campo, no ilegible', () {
      // Misma familia que el "holes: 3" que tiró el buscador de campos.
      final j = _liga().toJson()..['campo'] = 3;
      expect(Torneo.fromJson(j).campo, isNull);
    });

    test('la plantilla NO mueve qué rondas cuentan', () {
      // Dos significados, dos campos. Si se hubieran fusionado, elegir una
      // plantilla habría añadido o quitado filas de la tabla en silencio.
      final t = _liga(plantillaId: 'bg_1');
      expect(t.bettingGroupId, isNull);
      final conFuente = t.copyWith(bettingGroupId: 'bg_2');
      expect(conFuente.plantillaId, 'bg_1');
      expect(conFuente.bettingGroupId, 'bg_2');
    });
  });

  group('6 · el editor: la sección que no existía', () {
    testWidgets('CÓMO SE JUEGA UNA RONDA está, con sus tres preguntas',
        (tester) async {
      final errores = await _montarEditor(tester, _liga());
      expect(errores, isEmpty);
      expect(find.text('2 · CÓMO SE JUEGA UNA RONDA'), findsOneWidget);
      expect(find.text('LAS APUESTAS'), findsOneWidget);
      expect(find.text('LA VENTAJA'), findsOneWidget);
      expect(find.text('EL CAMPO'), findsOneWidget);
    });

    testWidgets('elegir "sin ventaja" dice que el handicap deja de preguntarse',
        (tester) async {
      final errores = await _montarEditor(tester, _liga());
      expect(errores, isEmpty);
      await tester.tap(find.text('Sin ventaja'));
      await tester.pump();
      expect(_pantalla(tester), contains('el handicap no interviene'));
    });

    testWidgets('el campo arranca sin fijar: una liga rota de campo',
        (tester) async {
      final errores = await _montarEditor(tester, _liga());
      expect(errores, isEmpty);
      expect(find.text('Lo elige cada jornada'), findsOneWidget);
      expect(find.text('Quitar el campo fijo'), findsNothing);
    });

    testWidgets('con campo fijo se puede quitar', (tester) async {
      final errores =
          await _montarEditor(tester, _liga(campo: _campoPrueba));
      expect(errores, isEmpty);
      expect(find.text('Los Encinos'), findsOneWidget);
      expect(find.text('Quitar el campo fijo'), findsOneWidget);
    });
  });

  group('7 · el arranque desde el torneo', () {
    testWidgets('enseña lo que el torneo fija, y la marca entre ello',
        (tester) async {
      final errores = await _montarArranque(
          tester,
          PuntoDeTorneo.propio(
              _liga(ventaja: VentajaDeTorneo.ninguna, campo: _campoPrueba),
              nombres: nombres));
      expect(errores, isEmpty);
      final txt = _pantalla(tester);
      expect(txt, contains('LO QUE FIJA EL TORNEO'));
      expect(txt, contains('4 inscritos en el padrón'));
      expect(txt, contains('Ventaja: Sin ventaja'));
      expect(txt, contains('Campo: Los Encinos'));
      expect(txt, contains('La ronda cuenta para Copa de Primavera'));
    });

    testWidgets('con campo y ventaja fijados no queda NADA por decidir',
        (tester) async {
      final errores = await _montarArranque(
          tester,
          PuntoDeTorneo.propio(
              _liga(ventaja: VentajaDeTorneo.handicap, campo: _campoPrueba),
              nombres: nombres));
      expect(errores, isEmpty);
      expect(find.text('No falta nada por decidir.'), findsOneWidget);
      expect(find.text('FALTA DECIDIR'), findsNothing);
    });

    testWidgets('sin campo fijo, el campo se sigue preguntando', (tester) async {
      // Es la diferencia entre los dos modelos: una liga rota de campo, un
      // shotgun no. Un solo campo opcional cubre los dos sin bandera de modo.
      final errores = await _montarArranque(
          tester,
          PuntoDeTorneo.propio(_liga(ventaja: VentajaDeTorneo.ninguna),
              nombres: nombres));
      expect(errores, isEmpty);
      expect(find.text('FALTA DECIDIR'), findsOneWidget);
      expect(find.text('Campo'), findsOneWidget);
      // La ventaja NO, que la fija el torneo.
      expect(find.text('Ventaja'), findsNothing);
    });

    testWidgets('el padrón se ofrece, y arranca con nadie marcado de más',
        (tester) async {
      // Marcar a los veinte del padrón sería peor que no marcar a ninguno:
      // habría que desmarcar diecisiete para jugar un cuarteto.
      final errores = await _montarArranque(
          tester, PuntoDeTorneo.seguido(_publicar(_liga())));
      expect(errores, isEmpty);
      expect(find.text('DEL PADRÓN DEL TORNEO'), findsOneWidget);
      expect(find.text('+ Luis Herrera'), findsOneWidget);
      expect(find.text('+ Rafa Gil'), findsOneWidget);
      expect(_pantalla(tester), contains('0 jugando esta ronda'));
    });

    testWidgets('y NO se ofrece dos veces al que además está en mi directorio',
        (tester) async {
      // Salía como inscrito del torneo y otra vez como "del directorio". Elegir
      // entre dos chips idénticos no es una elección.
      final errores = await _montarArranque(
          tester, PuntoDeTorneo.seguido(_publicar(_liga())),
          conDirectorio: true);
      expect(errores, isEmpty);
      expect(find.text('+ Luis Herrera'), findsOneWidget);
    });

    testWidgets('CRITERIO handicap: con ventaja se avisa de que se preguntará',
        (tester) async {
      final errores = await _montarArranque(
          tester,
          PuntoDeTorneo.seguido(
              _publicar(_liga(ventaja: VentajaDeTorneo.handicap))));
      expect(errores, isEmpty);
      expect(_pantalla(tester),
          contains('se le pregunta el handicap al añadirlo'));
    });

    testWidgets('CRITERIO handicap: sin ventaja NO se avisa, porque no se pide',
        (tester) async {
      final errores = await _montarArranque(
          tester,
          PuntoDeTorneo.seguido(
              _publicar(_liga(ventaja: VentajaDeTorneo.ninguna))));
      expect(errores, isEmpty);
      expect(_pantalla(tester),
          isNot(contains('se le pregunta el handicap al añadirlo')));
    });

    testWidgets('CRITERIO handicap: sin ventaja, añadir NO abre el formulario',
        (tester) async {
      // El riesgo desaparece por CONSTRUCCIÓN: sin ventaja el handicap no
      // interviene en ningún cálculo, así que no hay número que preguntar y no
      // hay 0 que pueda mentir.
      final errores = await _montarArranque(
          tester,
          PuntoDeTorneo.seguido(
              _publicar(_liga(ventaja: VentajaDeTorneo.ninguna))));
      expect(errores, isEmpty);
      await tester.tap(find.text('+ Luis Herrera'));
      await tester.pump(const Duration(milliseconds: 300));
      // Nada de formulario, y ya está dentro de la ronda.
      expect(find.text('Handicap'), findsNothing);
      expect(_pantalla(tester), contains('1 jugando esta ronda'));
    });

    testWidgets('CRITERIO handicap: con ventaja, añadir SÍ lo pregunta',
        (tester) async {
      // Y aquí no se puede callar: una apuesta con ventaja calculada sobre un 0
      // falso da netos falsos sin avisar de nada.
      final errores = await _montarArranque(
          tester,
          PuntoDeTorneo.seguido(
              _publicar(_liga(ventaja: VentajaDeTorneo.handicap))));
      expect(errores, isEmpty);
      await tester.tap(find.text('+ Luis Herrera'));
      await tester.pumpAndSettle();
      // El formulario compartido —el MISMO del asistente, no una copia— con el
      // nombre ya puesto: lo único que queda por responder es el número.
      expect(find.text('Jugador'), findsOneWidget);
      expect(find.text('Guardar en mis compañeros'), findsOneWidget);
      // Y NO entra en la ronda hasta que se responda.
      expect(_pantalla(tester), contains('0 jugando esta ronda'));
    });

    testWidgets('sin plantilla, el botón lleva a elegir qué se juega',
        (tester) async {
      // Ofrecer "empezar" a secas arrancaría una ronda sin apuestas sin decirlo.
      final errores = await _montarArranque(
          tester,
          PuntoDeTorneo.seguido(_publicar(
              _liga(ventaja: VentajaDeTorneo.ninguna, campo: _campoPrueba))));
      expect(errores, isEmpty);
      expect(find.text('⛳ Elegir qué se juega y empezar'), findsOneWidget);
      expect(find.text('⛳ Empezar ronda'), findsNothing);
      // Con dos dentro ya se puede arrancar, y ahí es donde se dice que la ronda
      // queda marcada: antes de eso lo que toca decir es qué falta.
      await tester.tap(find.text('+ Luis Herrera'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('+ Ana Ruiz'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_pantalla(tester), contains('la ronda ya queda marcada'));
    });

    testWidgets('la marca va SIEMPRE, con plantilla y sin ella', (tester) async {
      // El silencio peor de los dos: la ronda se juega, todo parece ir bien y la
      // tabla no se mueve. Se comprueba en el objeto que la pantalla pasa.
      for (final p in [
        PuntoDeTorneo.propio(_liga(plantillaId: 'bg_1'), nombres: nombres),
        PuntoDeTorneo.seguido(_publicar(_liga())),
      ]) {
        expect(p.torneoId, 'cp');
      }
    });

    testWidgets('con plantilla, empieza la ronda de verdad', (tester) async {
      final errores = await _montarArranque(
          tester,
          PuntoDeTorneo.propio(
              _liga(
                  ventaja: VentajaDeTorneo.ninguna,
                  campo: _campoPrueba,
                  plantillaId: 'bg_1'),
              nombres: nombres),
          grupo: BettingGroup(
              id: 'bg_1',
              name: 'Los sábados',
              playerIds: const [ana, beto],
              updatedAt: DateTime(2026, 1, 1)));
      expect(errores, isEmpty);
      expect(find.text('⛳ Empezar ronda'), findsOneWidget);
      expect(find.text('Revisar todo antes de empezar'), findsOneWidget);
    });
  });

  _pantallaDelTorneo();
}

// ── Montaje ─────────────────────────────────────────────────────────────────

Future<List<String>> _montarEditor(WidgetTester tester, Torneo torneo) async {
  tester.view.physicalSize = const Size(390, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final errores = <String>[];
  final anterior = FlutterError.onError;
  FlutterError.onError = (d) => errores.add(d.exceptionAsString());

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => RoundProvider()),
      ChangeNotifierProvider(create: (_) => HandicapProvider()),
      ChangeNotifierProvider(create: (_) => UserProfileProvider()),
      ChangeNotifierProvider(create: (_) => BettingGroupProvider()),
      ChangeNotifierProvider<PlayerProvider>.value(
          value: PlayerProvider()
            ..sembrar([
              for (final e in nombres.entries)
                PlayerWithLink(player: Player(id: e.key, name: e.value)),
            ])),
      ChangeNotifierProvider<PerfilProvider>.value(
          value: PerfilProvider()..sembrar(const [])),
      ChangeNotifierProvider<TorneoProvider>.value(
          value: TorneoProvider()..sembrar([torneo])),
    ],
    child: MaterialApp(
      theme: GolfTheme.classic.toMaterial(),
      home: TorneoEditorScreen(existente: torneo),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
  FlutterError.onError = anterior;
  return errores;
}

/// [conDirectorio] siembra a los cuatro del padrón como fichas propias.
///
/// Por defecto NO: es la situación real de quien sigue un torneo —no tiene a la
/// gente del organizador— y es la que hace visible lo del handicap.
Future<List<String>> _montarArranque(
    WidgetTester tester, PuntoDeTorneo punto,
    {BettingGroup? grupo, bool conDirectorio = false}) async {
  tester.view.physicalSize = const Size(390, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final errores = <String>[];
  final anterior = FlutterError.onError;
  FlutterError.onError = (d) => errores.add(d.exceptionAsString());

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => RoundProvider()),
      ChangeNotifierProvider(create: (_) => HandicapProvider()),
      ChangeNotifierProvider(create: (_) => UserProfileProvider()),
      ChangeNotifierProvider<PlayerProvider>.value(
          value: PlayerProvider()
            ..sembrar([
              if (conDirectorio)
                for (final e in nombres.entries)
                  PlayerWithLink(player: Player(id: e.key, name: e.value)),
            ])),
    ],
    child: MaterialApp(
      theme: GolfTheme.classic.toMaterial(),
      home: QuickStartScreen(grupo: grupo, torneo: punto),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
  FlutterError.onError = anterior;
  return errores;
}

String _pantalla(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .join(' · ');

// ─────────────────────────────────────────────────────────────────────────────
// 8 · LA PANTALLA DEL TORNEO: jugar va primero
// ─────────────────────────────────────────────────────────────────────────────
Future<List<String>> _montarTabla(WidgetTester tester, Torneo torneo) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final errores = <String>[];
  final anterior = FlutterError.onError;
  FlutterError.onError = (d) => errores.add(d.exceptionAsString());

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => RoundProvider()),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => HandicapProvider()),
      ChangeNotifierProvider(create: (_) => UserProfileProvider()),
      ChangeNotifierProvider(create: (_) => BettingGroupProvider()),
      ChangeNotifierProvider<PlayerProvider>.value(
          value: PlayerProvider()
            ..sembrar([
              for (final e in nombres.entries)
                PlayerWithLink(player: Player(id: e.key, name: e.value)),
            ])),
      ChangeNotifierProvider<PerfilProvider>.value(
          value: PerfilProvider()..sembrar(const [])),
      ChangeNotifierProvider<TorneoProvider>.value(
          value: TorneoProvider()..sembrar([torneo])),
    ],
    child: MaterialApp(
      theme: GolfTheme.classic.toMaterial(),
      home: TorneoTablaScreen(torneo: torneo),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 200));
  FlutterError.onError = anterior;
  return errores;
}

void _pantallaDelTorneo() {
  group('8 · la pantalla del torneo: jugar va primero', () {
    testWidgets('ofrece crear una ronda del torneo', (tester) async {
      final errores = await _montarTabla(tester, _liga());
      expect(errores, isEmpty);
      expect(find.text('⛳ Jugar una ronda de Copa de Primavera'),
          findsOneWidget);
    });

    testWidgets('sin plantilla dice que las apuestas se elegirán',
        (tester) async {
      final errores = await _montarTabla(tester, _liga());
      expect(errores, isEmpty);
      expect(_pantalla(tester),
          contains('Fija una plantilla en el editor'));
    });

    testWidgets('sin participantes NO ofrece el atajo: dice qué falta',
        (tester) async {
      // Sin padrón esto no ahorraría nada, y un atajo que no ataja es peor que
      // no ofrecerlo.
      final errores =
          await _montarTabla(tester, _liga(participantes: const []));
      expect(errores, isEmpty);
      expect(find.textContaining('Jugar una ronda de'), findsNothing);
      expect(_pantalla(tester),
          contains('Define los participantes y este torneo podrá crear'));
    });

    testWidgets('un torneo CERRADO no ofrece jugar', (tester) async {
      // La tabla ya no va a cambiar: ofrecer jugar ahí prometería que cuenta.
      final errores = await _montarTabla(tester, _liga(cerrado: true));
      expect(errores, isEmpty);
      expect(find.textContaining('Jugar una ronda de'), findsNothing);
    });
  });
}
