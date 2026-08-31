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
import 'package:golf_bet_master/models/torneo_seguido.dart';
import 'package:golf_bet_master/providers/betting_group_provider.dart';
import 'package:golf_bet_master/providers/handicap_provider.dart';
import 'package:golf_bet_master/providers/perfil_provider.dart';
import 'package:golf_bet_master/providers/player_provider.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/providers/torneo_provider.dart';
import 'package:golf_bet_master/providers/user_profile_provider.dart';
import 'package:golf_bet_master/services/player_service.dart';
import 'package:golf_bet_master/services/user_profile_service.dart';
import 'package:golf_bet_master/screens/setup/quick_start_screen.dart';
import 'package:golf_bet_master/screens/setup/setup_flow.dart';
import 'package:golf_bet_master/screens/setup/setup_screen.dart';
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
          ResultadoPublicado(
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
      expect(find.text('Elegir qué se juega y empezar'), findsOneWidget);
      expect(find.text('Empezar ronda'), findsNothing);
      // Con dos dentro ya se puede arrancar, y ahí es donde se dice que la ronda
      // queda marcada: antes de eso lo que toca decir es qué falta.
      await tester.tap(find.text('+ Luis Herrera'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('+ Ana Ruiz'));
      await tester.pump(const Duration(milliseconds: 300));
      // Y se dice POR QUÉ hace falta el paso: este torneo puntúa por dinero, así
      // que la medida sale de lo apostado.
      expect(_pantalla(tester), contains('la medida sale de lo apostado'));
      expect(_pantalla(tester), contains('incluida la marca del torneo'));
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
      expect(find.text('Empezar ronda'), findsOneWidget);
      expect(find.text('Revisar todo antes de empezar'), findsOneWidget);
    });
  });

  _pantallaDelTorneo();
  _quienSoy();
  _laRondaLlegaALaTabla();
  _elUltimoSalto();
  _laNominaLlegaALaRonda();
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
    {BettingGroup? grupo,
    bool conDirectorio = false,
    String? miFicha,
    String miNombre = 'CAV',
    double miHcp = 12}) async {
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
      ChangeNotifierProvider<UserProfileProvider>.value(
          value: UserProfileProvider()
            ..sembrar(UserProfile(
                uid: 'uid_yo',
                displayName: miNombre,
                email: 'yo@x.com',
                myPlayerId: miFicha))),
      ChangeNotifierProvider<PlayerProvider>.value(
          value: PlayerProvider()
            ..sembrar([
              if (conDirectorio)
                for (final e in nombres.entries)
                  PlayerWithLink(player: Player(id: e.key, name: e.value)),
              // MI ficha, con el apodo con el que me llamo en mi app. El nombre
              // NO coincide con el del padrón a propósito: es el caso real.
              if (miFicha != null)
                PlayerWithLink(
                    player: Player(
                        id: miFicha, name: miNombre, handicapBase: miHcp)),
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
      expect(find.text('Jugar una ronda de Copa de Primavera'),
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

// ─────────────────────────────────────────────────────────────────────────────
// 9 · EL ARRANQUE SABE QUIÉN SOY
//
// El dato existía —es lo que hace que el enlace diga "Carlos Angel · No soy yo"—
// y no llegaba. Y la consecuencia no es cosmética: si no caigo en añadirme, juego
// una ronda del torneo en la que no estoy.
// ─────────────────────────────────────────────────────────────────────────────
void _quienSoy() {
  group('9 · el arranque sabe quién soy', () {
    testWidgets('CRITERIO 1: vengo marcado, y NO se me ofrece añadirme',
        (tester) async {
      final errores = await _montarArranque(
          tester,
          PuntoDeTorneo.seguido(
              _publicar(_liga(ventaja: VentajaDeTorneo.ninguna)),
              yoSoy: 'Luis Herrera'),
          miFicha: 'mi_ficha');
      expect(errores, isEmpty);
      // Marcado, con su etiqueta, y con MI nombre —no el del padrón—.
      expect(find.text('CAV'), findsOneWidget);
      expect(find.text('tú'), findsOneWidget);
      // Y fuera del padrón: no soy un tercero.
      expect(find.text('+ Luis Herrera'), findsNothing);
      expect(find.text('+ CAV'), findsNothing);
    });

    testWidgets('CRITERIO 2: el contador me incluye', (tester) async {
      final errores = await _montarArranque(
          tester,
          PuntoDeTorneo.seguido(
              _publicar(_liga(ventaja: VentajaDeTorneo.ninguna)),
              yoSoy: 'Luis Herrera'),
          miFicha: 'mi_ficha');
      expect(errores, isEmpty);
      expect(_pantalla(tester), contains('1 jugando esta ronda'));
    });

    testWidgets('la reclamación manda sobre el nombre de mi ficha',
        (tester) async {
      // Mi ficha se llama "CAV" y el padrón dice "Luis Herrera". Emparejar solo
      // por nombre me habría dejado fuera de mi propio torneo.
      final p = PuntoDeTorneo.seguido(_publicar(_liga()), yoSoy: 'Luis Herrera')
          .conFichas({'CAV': 'mi_ficha'})
          .conMiFicha('mi_ficha');
      expect(p.miFicha, 'mi_ficha');
      expect(p.comoLoLlamo('Luis Herrera', {'mi_ficha': 'CAV'}), 'CAV');
    });

    testWidgets('CRITERIO 3: nadie más viene marcado por estar en mi lista',
        (tester) async {
      // Los cuatro del padrón están en mi directorio con esos mismos nombres, y
      // aun así solo entro yo: quién juega hoy no lo decide mi lista de
      // compañeros.
      final errores = await _montarArranque(
          tester,
          PuntoDeTorneo.seguido(
              _publicar(_liga(ventaja: VentajaDeTorneo.ninguna)),
              yoSoy: 'Luis Herrera'),
          miFicha: 'mi_ficha',
          conDirectorio: true);
      expect(errores, isEmpty);
      expect(_pantalla(tester), contains('1 jugando esta ronda'));
      // Y los demás se ofrecen, no se imponen.
      expect(find.text('+ Ana Ruiz'), findsOneWidget);
      expect(find.text('+ Rafa Gil'), findsOneWidget);
    });

    testWidgets('con plantilla SÍ vienen marcados, y se dice que es del torneo',
        (tester) async {
      // La diferencia entre los dos modelos: en liga eliges, en shotgun viene
      // dado. Y "dado" tiene que estar escrito, no adivinarse.
      final errores = await _montarArranque(
          tester,
          PuntoDeTorneo.propio(
              _liga(ventaja: VentajaDeTorneo.ninguna, plantillaId: 'bg_1'),
              nombres: nombres,
              yoSoy: 'Luis Herrera'),
          grupo: BettingGroup(
              id: 'bg_1',
              name: 'Los sábados',
              playerIds: const [beto, caro],
              updatedAt: DateTime(2026, 1, 1)),
          miFicha: 'mi_ficha',
          conDirectorio: true);
      expect(errores, isEmpty);
      expect(find.text('del torneo'), findsNWidgets(2));
      expect(_pantalla(tester), contains('3 jugando esta ronda'));
    });

    testWidgets('si no me pueden resolver, se dice lo que pasa si no me pongo',
        (tester) async {
      // Sin jugador propio en la cuenta. No se materializa en silencio: hace
      // falta el handicap y, sobre todo, hace falta que se vea.
      final errores = await _montarArranque(
          tester,
          PuntoDeTorneo.seguido(
              _publicar(_liga(ventaja: VentajaDeTorneo.ninguna)),
              yoSoy: 'Luis Herrera'));
      expect(errores, isEmpty);
      expect(find.text('+ Ponerme en la ronda (Luis Herrera)'), findsOneWidget);
      expect(_pantalla(tester),
          contains('contaría para el torneo sin contar para nadie'));
      expect(_pantalla(tester), contains('0 jugando esta ronda'));
    });

    testWidgets('CRITERIO 4: un solo vocabulario de nombres', (tester) async {
      // El padrón dice "Ana Ruiz" y yo la tengo como "ANITA". Sale ANITA, que es
      // como va a salir en la captura y en el historial.
      final p = PuntoDeTorneo.seguido(_publicar(_liga()))
          .conFichas({'ANITA': 'x'});
      // Sin ficha, el del padrón; con ficha, el mío. Una sola regla.
      expect(p.comoLoLlamo('Ana Ruiz', const {}), 'Ana Ruiz');
      expect(
          p.conMiFicha('x').comoLoLlamo('Ana Ruiz', const {'x': 'ANITA'}),
          'Ana Ruiz',
          reason: 'ANITA no cruza con Ana Ruiz por nombre, así que no es ella');
      final q = PuntoDeTorneo.seguido(_publicar(_liga()))
          .conFichas({'ana ruiz': 'y'});
      expect(q.comoLoLlamo('Ana Ruiz', const {'y': 'ANITA'}), 'ANITA');
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 10 · Y LA RONDA LLEGA A LA TABLA
//
// El fallo que salió de mirar el punto 1: el resultado publicado llegaba, la
// ronda se contaba, y NADIE tenía nada. Los ids de la ronda son del directorio
// de su autor y los inscritos del directorio del organizador, así que la tabla
// sumaba sobre ids que no reconocía.
//
// Ningún test lo cazó porque todos modelaban al seguidor con los ids DEL
// ORGANIZADOR: confirmaban la suposición en vez de probarla.
// ─────────────────────────────────────────────────────────────────────────────
void _laRondaLlegaALaTabla() {
  const org = {
    'org_carlos': 'Carlos Angel',
    'org_pepe': 'Pepe Perez',
    'org_luis': 'Luis Herrera'
  };
  Torneo torneoOrg() => Torneo(
      id: 'cp',
      nombre: 'Copa',
      fuente: FuenteDeRondas.marcadas,
      metodo: MetodoDePuntuacion.dinero,
      participantes: org.keys.toList());

  RoundResult delSeguidor() => RoundResult(
        roundId: 'r1',
        roundName: 'Sábado 1',
        courseName: 'Los Encinos',
        playedAt: DateTime(2026, 5, 2),
        holesPlayed: 18,
        // SUS ids, y con el apodo que él usa para sí mismo.
        playerIds: const ['mio_yo', 'mio_pepe'],
        playerNames: const {'mio_yo': 'CAV', 'mio_pepe': 'Pepe Perez'},
        balances: const {'mio_yo': 300, 'mio_pepe': -300},
        pairBalances: const {'mio_pepe|mio_yo': -300},
        grossByPlayer: const {'mio_yo': 82, 'mio_pepe': 90},
        netByPlayer: const {'mio_yo': 70, 'mio_pepe': 86},
        stablefordByPlayer: const {},
        torneoIds: const ['cp'],
      );

  group('10 · el resultado del seguidor acredita a quien jugó', () {
    test('antes de esto la tabla contaba la ronda y no le daba nada a nadie',
        () {
      // El contraejemplo, con el mismo dato y sin traducir: es lo que había.
      final t = torneoOrg();
      final tabla = tablaDe(t, [delSeguidor()], nombres: org);
      expect(tabla.rondas, 1, reason: 'la ronda SÍ se contaba');
      for (final f in [...tabla.filas, ...tabla.bajoMinimo]) {
        expect(f.jugadas, 0, reason: '${f.nombre} salía a cero');
      }
    });

    test('con el id del autor, el dinero llega a su inscrito', () {
      final t = torneoOrg();
      final cuentan = resultadosQueCuentan(
          t,
          [
            ResultadoPublicado(
                jugadorNombre: 'Carlos Angel',
                jugadorId: 'mio_yo',
                resultado: delSeguidor())
          ],
          nombres: org);
      expect(cuentan.length, 1);
      final tabla = tablaDe(t, cuentan, nombres: org);
      final filas = {
        for (final f in [...tabla.filas, ...tabla.bajoMinimo]) f.nombre: f
      };
      expect(filas['Carlos Angel']!.total, 300);
      expect(filas['Carlos Angel']!.jugadas, 1);
      // Y Pepe, que cruzó por nombre: una sola ronda publicada acredita a todos
      // los inscritos que jugaron en ella.
      expect(filas['Pepe Perez']!.total, -300);
      // Luis no jugó.
      expect(filas['Luis Herrera']!.jugadas, 0);
    });

    test('sin id del autor —lo publicado antes— cruza lo que puede', () {
      // Pepe se llama igual en las dos partes, así que él sí. Carlos, que se
      // apunta como CAV, no: es exactamente lo que el id resuelve.
      final t = torneoOrg();
      final cuentan = resultadosQueCuentan(
          t,
          [
            ResultadoPublicado(
                jugadorNombre: 'Carlos Angel', resultado: delSeguidor())
          ],
          nombres: org);
      final tabla = tablaDe(t, cuentan, nombres: org);
      final filas = {
        for (final f in [...tabla.filas, ...tabla.bajoMinimo]) f.nombre: f
      };
      expect(filas['Pepe Perez']!.total, -300);
      expect(filas['Carlos Angel']!.jugadas, 0);
    });

    test('dos jugadores no pueden acabar en el mismo inscrito', () {
      // Si mi compañero se llama literalmente igual que el inscrito que YO
      // reclamé, fundir los dos sumaría el dinero de uno al otro. El autor gana
      // el sitio y el otro se queda con el suyo.
      final r = RoundResult(
        roundId: 'r2',
        roundName: 'S',
        courseName: 'X',
        playedAt: DateTime(2026, 5, 3),
        holesPlayed: 18,
        playerIds: const ['mio_yo', 'otro'],
        playerNames: const {'mio_yo': 'CAV', 'otro': 'Carlos Angel'},
        balances: const {'mio_yo': 100, 'otro': -100},
        pairBalances: const {},
        grossByPlayer: const {},
        netByPlayer: const {},
        stablefordByPlayer: const {},
        torneoIds: const ['cp'],
      );
      final salida = conIdsDelTorneo(r,
          participantePorNombre: {
            for (final e in org.entries) nombreComparable(e.value): e.key
          },
          jugadorNombre: 'Carlos Angel',
          jugadorId: 'mio_yo');
      expect(salida.playerIds, ['org_carlos', 'otro']);
      expect(salida.balances['org_carlos'], 100);
      expect(salida.balances['otro'], -100);
    });

    test('el duelo no cambia de signo al traducir los ids', () {
      // La clave del par guarda la vista del id MENOR. Traducir sin recalcularla
      // habría invertido quién le ganó a quién sin que nada avisara.
      final r = delSeguidor();
      expect(r.netoEntre('mio_yo', 'mio_pepe'), 300);
      final salida = conIdsDelTorneo(r,
          participantePorNombre: {
            for (final e in org.entries) nombreComparable(e.value): e.key
          },
          jugadorNombre: 'Carlos Angel',
          jugadorId: 'mio_yo');
      expect(salida.netoEntre('org_carlos', 'org_pepe'), 300);
    });

    test('el id del autor viaja en el documento, no en la instantánea', () {
      final d = ResultadoDeTorneo(
        torneoId: 'cp',
        roundId: 'r1',
        token: 'tok',
        torneoOwnerUid: 'uid_org',
        escritoPor: 'uid_yo',
        jugadorNombre: 'Carlos Angel',
        jugadorId: 'mio_yo',
        resultado: const {'roundId': 'r1'},
      );
      expect(d.toJson()['jugadorId'], 'mio_yo');
      expect(ResultadoDeTorneo.fromJson(d.toJson()).jugadorId, 'mio_yo');
      // Y la instantánea pública sigue sin ids de jugador.
      expect(_publicar(_liga()).toJson().toString().contains('pid_'), isFalse);
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 11 · EL ÚLTIMO SALTO
//
// Donde se ha roto tres veces: la pantalla compone bien y el último salto va a
// otro sitio. Aquí eran dos cosas — yo como casilla que había que marcar, y el
// botón cayendo en "paso 1 de 8 · Campo" a preguntar lo que el torneo ya fijó.
// ─────────────────────────────────────────────────────────────────────────────
void _elUltimoSalto() {
  group('11 · el último salto', () {
    testWidgets('CRITERIO 1: mi fila es un hecho, no una casilla',
        (tester) async {
      final errores = await _montarArranque(
          tester,
          PuntoDeTorneo.seguido(
              _publicar(_liga(ventaja: VentajaDeTorneo.ninguna)),
              yoSoy: 'Luis Herrera'),
          miFicha: 'mi_ficha');
      expect(errores, isEmpty);
      expect(find.text('tú'), findsOneWidget);
      expect(_pantalla(tester), contains('1 jugando esta ronda'));

      // Y tocarla no me saca de mi propia ronda: no hay casilla que desmarcar.
      await tester.tap(find.text('CAV'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_pantalla(tester), contains('1 jugando esta ronda'));
    });

    testWidgets('ni se me ofrece como "del directorio" en mi propia ronda',
        (tester) async {
      // Salía ahí al dejar de estar en la lista editable: soy un hecho, y los
      // dos sitios que ofrecen gente tienen que saberlo.
      final errores = await _montarArranque(
          tester,
          PuntoDeTorneo.seguido(
              _publicar(_liga(ventaja: VentajaDeTorneo.ninguna)),
              yoSoy: 'Luis Herrera'),
          miFicha: 'mi_ficha');
      expect(errores, isEmpty);
      expect(find.text('+ CAV'), findsNothing);
      expect(find.text('+ Luis Herrera'), findsNothing);
    });

    testWidgets('CRITERIO 2: elegir campo se queda en el arranque',
        (tester) async {
      final errores = await _montarArranque(
          tester,
          PuntoDeTorneo.seguido(
              _publicar(_liga(ventaja: VentajaDeTorneo.ninguna)),
              yoSoy: 'Luis Herrera'),
          miFicha: 'mi_ficha');
      expect(errores, isEmpty);
      await tester.tap(find.text('Campo'));
      await tester.pump(const Duration(milliseconds: 400));
      // La hoja de campo es la del asistente, pero se abre ENCIMA: el arranque
      // sigue ahí debajo y al elegir se vuelve a él.
      expect(find.byType(QuickStartScreen), findsOneWidget);
      expect(find.byType(SetupScreen), findsNothing);
    });

    testWidgets('CRITERIO 3: por score se lanza sin pasar por el asistente',
        (tester) async {
      // La medida es el score, así que no hay nada que apostar y no queda
      // ninguna pregunta: la ronda empieza.
      final errores = await _montarArranque(
          tester,
          PuntoDeTorneo.seguido(_publicar(Torneo(
            id: 'cp',
            nombre: 'Copa de Primavera',
            fuente: FuenteDeRondas.marcadas,
            metodo: MetodoDePuntuacion.scoreNeto,
            participantes: cuatro,
            ventaja: VentajaDeTorneo.ninguna,
            campo: _campoPrueba,
          )), yoSoy: 'Luis Herrera'),
          miFicha: 'mi_ficha');
      expect(errores, isEmpty);
      expect(find.text('Empezar ronda'), findsOneWidget);
      expect(find.text('Elegir qué se juega y empezar'), findsNothing);
      // Con dos dentro ya no falta nada, y ahí se dice por qué se puede lanzar.
      await tester.tap(find.text('+ Ana Ruiz'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('No falta nada por decidir.'), findsOneWidget);
      expect(_pantalla(tester), contains('no hace falta apostar nada'));
    });

    test('y la decisión de lanzar o preguntar vive en el modelo', () {
      TorneoPublicado pub(MetodoDePuntuacion m) => _publicar(Torneo(
          id: 'cp',
          nombre: 'Copa',
          fuente: FuenteDeRondas.marcadas,
          metodo: m,
          participantes: cuatro));
      // Por score: nada que preguntar.
      for (final m in [
        MetodoDePuntuacion.scoreNeto,
        MetodoDePuntuacion.stableford
      ]) {
        expect(PuntoDeTorneo.seguido(pub(m)).pideApuestas, isFalse,
            reason: m.name);
      }
      // Por dinero y por posición: la medida sale de lo apostado.
      for (final m in [
        MetodoDePuntuacion.dinero,
        MetodoDePuntuacion.posicion
      ]) {
        final p = PuntoDeTorneo.seguido(pub(m));
        expect(p.pideApuestas, isTrue, reason: m.name);
        expect(p.motivoApuestas, contains('la medida sale de lo apostado'));
      }
      // Instantánea vieja, sin método: se pregunta. Preguntar de más cuesta un
      // paso; arrancar de menos cuesta una tabla en blanco.
      const vieja = PuntoDeTorneo(
          torneoId: 'cp', nombre: 'Copa', emoji: '🏆', padron: ['Luis']);
      expect(vieja.pideApuestas, isTrue);
      expect(vieja.motivoApuestas, contains('no dice cómo puntúa'));
      // Y con plantilla nunca: las trae puestas.
      expect(
          PuntoDeTorneo.propio(_liga(plantillaId: 'bg_1'), nombres: nombres)
              .pideApuestas,
          isFalse);
    });

    test('el asistente aterriza en la primera pregunta SIN responder', () {
      // Es lo que evita volver a "paso 1 de 8 · Campo" con el campo ya elegido.
      final pasos = setupSteps(
          porEquipos: false,
          conCuenta: true,
          conParticipantes: true,
          conVentaja: true,
          jugadores: 3);
      // Lo que deja resuelto el arranque de un torneo sin plantilla.
      expect(
          primerPasoSinResolver(pasos, {
            SetupStep.campo,
            SetupStep.jugadores,
            SetupStep.ventaja,
          }),
          SetupStep.compiten);
      // Y con plantilla no queda nada: se aterriza donde se confirma.
      expect(
          primerPasoSinResolver(pasos, {
            SetupStep.campo,
            SetupStep.ventaja,
            ...resueltosPorGrupo(),
          }),
          SetupStep.revisar);
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 12 · LA NÓMINA LLEGA A LA RONDA
//
// Donde se perdía el que se añadía del padrón: nominaInicial solo se leía dentro
// de _precargarDesdeGrupo, y una ronda de torneo sin plantilla entra SIN grupo.
// La lista llegaba entera y no la leía nadie; solo _autoAddMyself metía a
// alguien, y de ahí el síntoma exacto —yo sí, Pepe no—.
//
// Estos tests miran la capa donde el dato se perdía, no el contador de la
// pantalla anterior, que decía la verdad de su propio estado.
// ─────────────────────────────────────────────────────────────────────────────
Future<List<String>> _montarAsistente(
  WidgetTester tester, {
  List<String>? nomina,
  List<Player> nuevos = const [],
  BettingGroup? grupo,
}) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final errores = <String>[];
  final anterior = FlutterError.onError;
  FlutterError.onError = (d) => errores.add(d.exceptionAsString());

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => RoundProvider()),
      ChangeNotifierProvider(create: (_) => HandicapProvider()),
      ChangeNotifierProvider(create: (_) => BettingGroupProvider()),
      ChangeNotifierProvider(create: (_) => TorneoProvider()),
      ChangeNotifierProvider(create: (_) => PerfilProvider()),
      ChangeNotifierProvider<UserProfileProvider>.value(
          value: UserProfileProvider()
            ..sembrar(const UserProfile(
                uid: 'uid_yo',
                displayName: 'CAV',
                email: 'yo@x.com',
                myPlayerId: 'mi_ficha'))),
      ChangeNotifierProvider<PlayerProvider>.value(
          value: PlayerProvider()
            ..sembrar([
              PlayerWithLink(
                  player: Player(id: 'mi_ficha', name: 'CAV', handicapBase: 12)),
              for (final e in nombres.entries)
                PlayerWithLink(player: Player(id: e.key, name: e.value)),
            ])),
    ],
    child: MaterialApp(
      theme: GolfTheme.classic.toMaterial(),
      home: SetupScreen(
          torneoInicial: 'cp',
          nominaInicial: nomina,
          jugadoresNuevos: nuevos,
          grupoInicial: grupo,
          pasosResueltos: const {SetupStep.campo, SetupStep.jugadores}),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
  FlutterError.onError = anterior;
  return errores;
}

/// Los nombres que el asistente tiene EN LA RONDA, no los que ofrece.
///
/// Sale del paso Jugadores: las fichas elegidas se pintan con su handicap al
/// lado, y las ofrecidas no. Contar filas ahí es lo más cerca de "contar filas
/// en la captura" que llega el harness, y es la capa exacta donde se perdía.
Set<String> _enLaRonda(WidgetTester tester) {
  final estado = tester.state(find.byType(SetupScreen));
  // ignore: avoid_dynamic_calls
  final players = (estado as dynamic).jugadoresDeLaRonda as List<Player>;
  return players.map((p) => p.name).toSet();
}

void _laNominaLlegaALaRonda() {
  group('12 · la nómina llega a la ronda', () {
    testWidgets('CRITERIO 1: quien se añadió del padrón está en la ronda',
        (tester) async {
      final errores = await _montarAsistente(
          tester, nomina: const ['mi_ficha', beto]);
      expect(errores, isEmpty);
      expect(_enLaRonda(tester), {'CAV', 'Ana Ruiz'});
    });

    testWidgets('CRITERIO 2: varios seguidos, todos llegan', (tester) async {
      final errores = await _montarAsistente(tester,
          nomina: const ['mi_ficha', beto, caro, dani]);
      expect(errores, isEmpty);
      expect(_enLaRonda(tester).length, 4);
      expect(_enLaRonda(tester),
          {'CAV', 'Ana Ruiz', 'Dani Sotó', 'Rafa Gil'});
    });

    testWidgets('y el materializado sin ficha en el directorio TAMBIÉN',
        (tester) async {
      // El caso que apuntabas: el del padrón sin ficha local. Viaja en
      // jugadoresNuevos y _agregarDelDirectorio lo mira ANTES del directorio,
      // así que no depende de que createPlayer haya llegado a Firestore.
      final errores = await _montarAsistente(
        tester,
        nomina: const ['mi_ficha', 'pad_nuevo'],
        nuevos: [
          Player(id: 'pad_nuevo', name: 'Pepe Pérez', handicapBase: 0),
        ],
      );
      expect(errores, isEmpty);
      expect(_enLaRonda(tester), {'CAV', 'Pepe Pérez'});
    });

    testWidgets('sin nómina sigo estando yo, y solo yo', (tester) async {
      // El contrapeso: si la precarga metiera de más, esto lo caza.
      final errores = await _montarAsistente(tester);
      expect(errores, isEmpty);
      expect(_enLaRonda(tester), {'CAV'});
    });

    testWidgets('y con grupo sigue funcionando como antes', (tester) async {
      // El camino que ya iba: la nómina de hoy manda sobre los habituales.
      final errores = await _montarAsistente(
        tester,
        nomina: const ['mi_ficha', beto],
        grupo: BettingGroup(
            id: 'bg_1',
            name: 'Los sábados',
            playerIds: const [caro, dani],
            updatedAt: DateTime(2026, 1, 1)),
      );
      expect(errores, isEmpty);
      expect(_enLaRonda(tester), {'CAV', 'Ana Ruiz'});
    });
  });
}
