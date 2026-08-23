// ─────────────────────────────────────────────────────────────────────────────
// EL BOTE — contabilidad, no un cobro
//
// La restricción que manda sobre todo está escrita en torneo.dart, donde se
// decide: LA APP NO PROCESA PAGOS. El bote es una cuenta, igual que las apuestas
// de cada ronda, y eso no es una limitación técnica que alguien pueda arreglar
// más adelante: es la línea que separa "llevar la cuenta entre amigos" de
// "facilitar apuestas con dinero real".
//
// Consecuencia comprobable: no hay estado "pagado" en ninguna parte de este
// archivo. Hay quién puso, quién cobra, y si el reparto ya es definitivo.
//
// El test que más protege: el bote y el balance de las rondas NO SE SUMAN. Una
// está cobrada y la otra es una expectativa, y una cifra que las junte no
// significa nada.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/models/round_result.dart';
import 'package:golf_bet_master/models/torneo.dart';
import 'package:golf_bet_master/providers/handicap_provider.dart';
import 'package:golf_bet_master/providers/perfil_provider.dart';
import 'package:golf_bet_master/providers/torneo_provider.dart';
import 'package:golf_bet_master/providers/user_profile_provider.dart';
import 'package:golf_bet_master/screens/home/tablero_inicio.dart';
import 'package:golf_bet_master/services/user_profile_service.dart';

const ana = 'ana', beto = 'beto', caro = 'caro', dani = 'dani';

RoundResult _r(String id, int dia, Map<String, double> dinero) => RoundResult(
      roundId: id,
      roundName: 'R$id',
      courseName: 'C',
      playedAt: DateTime(2026, 3, dia),
      holesPlayed: 18,
      playerIds: dinero.keys.toList(),
      playerNames: {for (final k in dinero.keys) k: k.toUpperCase()},
      balances: dinero,
      pairBalances: const {},
      grossByPlayer: const {},
    );

Torneo _t({
  double entrada = 100,
  RepartoDelBote reparto = RepartoDelBote.ganadorTodo,
  List<int> porcentajes = const [60, 30, 10],
  // Nullable a propósito: si el helper fijara un valor, taparía el default del
  // modelo y un test sobre el default no probaría nada. Lo descubrí escribiendo
  // justo ese test.
  EntradaSinMinimo? sinMinimo,
  int minimoRondas = 0,
  bool cerrado = false,
}) =>
    Torneo(
      id: 't', nombre: 'T',
      fuente: FuenteDeRondas.rango,
      metodo: MetodoDePuntuacion.dinero,
      minimoRondas: minimoRondas,
      cerrado: cerrado,
      bote: sinMinimo == null
          ? BoteConfig(
              entrada: entrada, reparto: reparto, porcentajes: porcentajes)
          : BoteConfig(
              entrada: entrada,
              reparto: reparto,
              porcentajes: porcentajes,
              sinMinimo: sinMinimo),
    );

/// Cuatro jugadores, tres rondas. Ana gana, luego Beto, luego Caro.
/// Dani solo juega una: es el que puede quedarse bajo el mínimo.
List<RoundResult> _temporada() => [
      _r('1', 1, {ana: 300, beto: -100, caro: -100, dani: -100}),
      _r('2', 2, {ana: -50, beto: 150, caro: -100}),
      _r('3', 3, {ana: -50, beto: -50, caro: 100}),
    ];

void main() {
  _enInicio();

  _dosBotes();

  group('1 · lo que hay en el bote', () {
    test('la entrada por cada uno de los que aparecen en la tabla', () {
      final t = _t(entrada: 100);
      final bote = boteDe(t, tablaDe(t, _temporada()));
      expect(bote.recaudado, 400, reason: 'cuatro jugadores × 100');
      expect(bote.total, 400);
      expect(bote.lineas, hasLength(4));
    });

    test('sin entrada no hay bote', () {
      final t = _t(entrada: 0);
      final bote = boteDe(t, tablaDe(t, _temporada()));
      expect(bote.hayBote, isFalse);
      expect(bote.lineas, isEmpty);
    });

    test('un torneo sin rondas no inventa un bote', () {
      final t = _t();
      expect(boteDe(t, tablaDe(t, const [])).hayBote, isFalse);
    });
  });

  group('2 · el reparto', () {
    test('el primero se lo lleva todo', () {
      final t = _t(entrada: 100);
      final tabla = tablaDe(t, _temporada());
      final bote = boteDe(t, tabla);
      final primero = tabla.filas.first.playerId;
      final suya = bote.lineas.firstWhere((l) => l.playerId == primero);
      expect(suya.cobra, 400);
      expect(suya.saldo, 300, reason: 'cobra 400 y había puesto 100');
      // Y nadie más cobra.
      expect(bote.lineas.where((l) => l.cobra > 0), hasLength(1));
    });

    test('podio: los porcentajes reparten el total, ni más ni menos', () {
      final t = _t(
          entrada: 100,
          reparto: RepartoDelBote.podio,
          porcentajes: const [60, 30, 10]);
      final bote = boteDe(t, tablaDe(t, _temporada()));
      final cobrado = bote.lineas.fold(0.0, (s, l) => s + l.cobra);
      expect(cobrado, 400, reason: 'el bote entero, sin crear ni perder dinero');
      // CUATRO cobran, no tres, y es correcto: en esta temporada Caro y Dani
      // empatan a −100, así que comparten el tercer puesto y se reparten su
      // premio. Lo escribí esperando tres y el test me corrigió — que es
      // exactamente para lo que estaba.
      expect(bote.lineas.where((l) => l.cobra > 0), hasLength(4));
      final deCaro = bote.lineas.firstWhere((l) => l.playerId == caro);
      final deDani = bote.lineas.firstWhere((l) => l.playerId == dani);
      expect(deCaro.cobra, deDani.cobra, reason: 'empatados, mismo premio');
      expect(deCaro.cobra + deDani.cobra, 40, reason: 'el 10% del tercero');
    });

    test('unos porcentajes que no suman 100 se normalizan', () {
      // Repartir más dinero del que hay no puede pasar con un bote.
      final t = _t(
          entrada: 100,
          reparto: RepartoDelBote.podio,
          porcentajes: const [50, 30, 30]); // suma 110
      final bote = boteDe(t, tablaDe(t, _temporada()));
      final cobrado = bote.lineas.fold(0.0, (s, l) => s + l.cobra);
      expect((cobrado - 400).abs() < 1, isTrue, reason: 'cobrado = $cobrado');
    });

    test('los empatados en la tabla se reparten sus premios', () {
      // Mismo principio que los puntos: dos empatados en el primero se llevan la
      // media de los dos primeros premios.
      final rondas = [
        _r('1', 1, {ana: 100, beto: 100, caro: -200}),
      ];
      final t = _t(
          entrada: 90,
          reparto: RepartoDelBote.podio,
          porcentajes: const [60, 30, 10]);
      final tabla = tablaDe(t, rondas);
      final bote = boteDe(t, tabla);
      // 270 en el bote. Primero 162, segundo 81 → 121.5 cada uno.
      final deAna = bote.lineas.firstWhere((l) => l.playerId == ana);
      final deBeto = bote.lineas.firstWhere((l) => l.playerId == beto);
      expect(deAna.cobra, deBeto.cobra);
      expect((deAna.cobra + deBeto.cobra - 243).abs() < 1, isTrue);
    });
  });

  group('3 · quien no llega al mínimo', () {
    // Dani juega una ronda de tres. Con mínimo 2 no clasifica.
    Torneo conMinimo(EntradaSinMinimo regla) =>
        _t(entrada: 120, minimoRondas: 2, sinMinimo: regla);

    test('por defecto pierde lo puesto, y engorda el bote', () {
      final t = conMinimo(EntradaSinMinimo.pierde);
      final bote = boteDe(t, tablaDe(t, _temporada()));
      expect(bote.total, 480, reason: 'los cuatro aportan');
      final deDani = bote.lineas.firstWhere((l) => l.playerId == dani);
      expect(deDani.aporta, 120);
      expect(deDani.devuelto, 0);
      expect(deDani.cobra, 0);
      expect(deDani.saldo, -120);
    });

    test('el default es "devolver": quien no clasifica tampoco puso', () {
      // Este test decía "pierde", que es lo más común en ligas y fue la elección
      // de la vez anterior. Cambió con datos reales: una fuente por fechas
      // arrastró ochenta rondas de prueba, la tabla se llenó de 55 personas y el
      // bote dio $27500. Y con "pierde", SUBIR EL MÍNIMO NO ARREGLA EL NÚMERO
      // —los que no clasifican siguen aportando— así que la herramienta que
      // existía para acotarlo no servía.
      //
      // "Devolver" implementa "quien no clasifica tampoco puso", que es la
      // lectura correcta: el bote a repartir es el de los que compiten por él.
      // Las otras dos siguen ahí para el grupo que las quiera.
      expect(BoteConfig.def.sinMinimo, EntradaSinMinimo.devolver);
    });

    test('y con el default, subir el mínimo SÍ acota el bote', () {
      // La comprobación de que el cambio sirve para lo que se hizo.
      final sinMinimo = _t(entrada: 120, minimoRondas: 0);
      final conMinimo = _t(entrada: 120, minimoRondas: 2);
      expect(boteDe(sinMinimo, tablaDe(sinMinimo, _temporada())).total, 480);
      expect(boteDe(conMinimo, tablaDe(conMinimo, _temporada())).total, 360,
          reason: 'Dani no clasifica, así que su entrada no está en el bote');
    });

    test('con "devolver" el bote a repartir es menor', () {
      final t = conMinimo(EntradaSinMinimo.devolver);
      final bote = boteDe(t, tablaDe(t, _temporada()));
      expect(bote.recaudado, 480, reason: 'lo que entró');
      expect(bote.total, 360, reason: 'lo que queda para repartir');
      final deDani = bote.lineas.firstWhere((l) => l.playerId == dani);
      expect(deDani.aporta, 0);
      expect(deDani.devuelto, 120);
      expect(deDani.saldo, 0, reason: 'no juega el bote, no pierde nada');
    });

    test('con "prorratear" aporta lo de las rondas que jugó', () {
      final t = conMinimo(EntradaSinMinimo.prorratear);
      final bote = boteDe(t, tablaDe(t, _temporada()));
      final deDani = bote.lineas.firstWhere((l) => l.playerId == dani);
      expect(deDani.aporta, 40, reason: '120 × 1 de 3 rondas');
      expect(deDani.devuelto, 80);
    });

    test('y quien no clasifica no cobra nunca, aunque fuera primero', () {
      // Dani ganó dinero en su única ronda; si el reparto lo incluyera, el
      // mínimo no serviría para nada.
      final rondas = [_r('1', 1, {dani: 500, ana: -500})];
      final t = _t(entrada: 100, minimoRondas: 5);
      final bote = boteDe(t, tablaDe(t, rondas));
      expect(bote.lineas.every((l) => l.cobra == 0), isTrue);
    });
  });

  group('4 · abierto contra cerrado', () {
    test('abierto: el reparto es provisional y se dice', () {
      final t = _t(cerrado: false);
      final bote = boteDe(t, tablaDe(t, _temporada()));
      expect(bote.cerrado, isFalse);
      expect(bote.provisional, isNotNull);
      expect(bote.provisional, contains('cambia con cada ronda'));
    });

    test('cerrado: el reparto es definitivo', () {
      final t = _t(cerrado: true);
      final bote = boteDe(t, tablaDe(t, _temporada()));
      expect(bote.cerrado, isTrue);
      expect(bote.provisional, isNull);
    });

    test('cerrar NO significa pagado: no existe ese estado', () {
      // La app no procesa pagos. Si algún día aparece un campo "pagado", este
      // test es el sitio donde la conversación tiene que ocurrir.
      final j = _t(cerrado: true).toJson();
      expect(j.keys.any((k) => k.toLowerCase().contains('pag')), isFalse);
      final b = _t(cerrado: true).bote.toJson();
      expect(b.keys.any((k) => k.toLowerCase().contains('pag')), isFalse);
    });
  });

  group('5 · el bote NO se suma al balance de las rondas', () {
    test('son dos cifras distintas y ninguna incluye a la otra', () {
      // El punto delicado del encargo. El dinero de las rondas está cobrado; el
      // bote es una expectativa mientras el torneo está abierto. Una cifra que
      // las junte no significa nada.
      final rondas = _temporada();
      final t = _t(entrada: 100);
      final tabla = tablaDe(t, rondas);
      final bote = boteDe(t, tabla);

      // Lo de las rondas: Ana suma 300 − 50 − 50 = 200.
      final deAnaEnRondas = rondas.fold(0.0, (s, r) => s + r.netoDe(ana));
      expect(deAnaEnRondas, 200);

      // Lo del bote: cobra 400 y puso 100 → saldo 300.
      final deAnaEnBote =
          bote.lineas.firstWhere((l) => l.playerId == ana).saldo;
      expect(deAnaEnBote, 300);

      // Y son independientes: el bote no mira el dinero de las rondas más que
      // para ordenar la tabla, y el balance de las rondas no sabe del bote.
      expect(deAnaEnRondas, isNot(deAnaEnBote));
      expect(tabla.filas.first.total, 200,
          reason: 'la tabla puntúa por dinero de ronda, sin el bote');
    });

    test('cambiar la entrada del bote no toca la tabla', () {
      // Si el bote entrara en la puntuación, subir la entrada movería la
      // clasificación. Es la comprobación de que no se han cruzado.
      final rondas = _temporada();
      final barato = tablaDe(_t(entrada: 10), rondas);
      final caro2 = tablaDe(_t(entrada: 10000), rondas);
      expect(barato.filas.map((f) => f.playerId).toList(),
          caro2.filas.map((f) => f.playerId).toList());
      expect(barato.filas.first.total, caro2.filas.first.total);
    });
  });

  group('6 · el viaje a JSON', () {
    test('conserva la configuración del bote', () {
      final t = _t(
          entrada: 250,
          reparto: RepartoDelBote.podio,
          porcentajes: const [50, 30, 20],
          sinMinimo: EntradaSinMinimo.prorratear);
      final v = Torneo.fromJson(Map<String, dynamic>.from(t.toJson()));
      expect(v.bote.entrada, 250);
      expect(v.bote.reparto, RepartoDelBote.podio);
      expect(v.bote.porcentajes, const [50, 30, 20]);
      expect(v.bote.sinMinimo, EntradaSinMinimo.prorratear);
    });

    test('un torneo sin bote no escribe la clave', () {
      // Aditivo: los torneos guardados antes de que existiera el bote se leen
      // igual, sin bote.
      final j = _t(entrada: 0).toJson();
      expect(j.containsKey('bote'), isFalse);
      final v = Torneo.fromJson(Map<String, dynamic>.from(j));
      expect(v.bote.hayBote, isFalse);
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Y EN INICIO SALE APARTE, SIN SUMARSE
//
// El punto delicado del encargo, comprobado en la pantalla: el bloque del
// balance histórico y el de "EN JUEGO" son dos, con dos totales, y el segundo
// dice "no cobrado". Si alguna vez alguien los suma, este test cae.
// ─────────────────────────────────────────────────────────────────────────────
void _enInicio() {
  Future<void> montar(WidgetTester tester,
      {required List<Torneo> torneos, required List<RoundResult> res}) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    UserProfileService.identidadDePrueba(ana);
    addTearDown(UserProfileService.olvidaIdentidad);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<PerfilProvider>.value(
            value: PerfilProvider()..sembrar(res)),
        ChangeNotifierProvider(create: (_) => HandicapProvider()),
        ChangeNotifierProvider(create: (_) => UserProfileProvider()),
        ChangeNotifierProvider<TorneoProvider>.value(
            value: TorneoProvider()..sembrar(torneos)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: HistoricoInicio(t: GolfTheme.classic),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 150));
  }

  group('7 · el bote no se mezcla con el balance en Inicio', () {
    testWidgets('los dos bloques existen, con sus dos totales', (tester) async {
      // Ana lleva +200 en rondas y hay 400 en el bote. Ninguna de las dos cifras
      // puede ser 600.
      await montar(tester,
          torneos: [_t(entrada: 100)], res: _temporada());

      expect(find.textContaining('BALANCE HISTÓRICO'), findsOneWidget);
      expect(find.text('+\$200'), findsOneWidget, reason: 'lo cobrado');

      expect(find.textContaining('EN JUEGO'), findsOneWidget);
      expect(find.textContaining('no cobrado'), findsOneWidget,
          reason: 'la etiqueta es la mitad del mensaje');
      expect(find.text('\$400'), findsOneWidget, reason: 'lo que hay en juego');

      // Y la suma NO aparece en ninguna parte.
      expect(find.text('+\$600'), findsNothing);
      expect(find.text('\$600'), findsNothing);
    });

    testWidgets('un torneo CERRADO ya no está en juego', (tester) async {
      // Cerrado significa que la tabla no cambia. Seguir enseñándolo como
      // expectativa sería mentir en la otra dirección.
      await montar(tester,
          torneos: [_t(entrada: 100, cerrado: true)], res: _temporada());
      expect(find.textContaining('EN JUEGO'), findsNothing);
    });

    testWidgets('sin torneos con bote no aparece el bloque', (tester) async {
      await montar(tester, torneos: [_t(entrada: 0)], res: _temporada());
      expect(find.textContaining('EN JUEGO'), findsNothing);
      // Pero el balance sí: el contrapeso de que el bloque no tape nada.
      expect(find.textContaining('BALANCE HISTÓRICO'), findsOneWidget);
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// DOS BOTES A LA VEZ, Y NINGUNA CIFRA QUE LOS JUNTE
//
// El de la jornada está COBRADO —esa ronda se cerró— y el final es una
// EXPECTATIVA mientras el torneo esté abierto. Es el mismo criterio que separa
// el bote de las apuestas de ronda, un nivel más adentro.
//
// Se eligieron DOS ENTRADAS separadas y no una repartida: pones lo del día
// cuando juegas y lo de la temporada al empezar. Con una entrada única, quien
// falta tres sábados habría puesto el bote de esos tres días.
// ─────────────────────────────────────────────────────────────────────────────
void _dosBotes() {
  Torneo conJornada({
    double temporada = 500,
    double jornada = 100,
    RepartoDelBote repartoJornada = RepartoDelBote.ganadorTodo,
    int minimoRondas = 0,
  }) =>
      Torneo(
        id: 't', nombre: 'T',
        fuente: FuenteDeRondas.rango,
        metodo: MetodoDePuntuacion.dinero,
        minimoRondas: minimoRondas,
        bote: BoteConfig(
            entrada: temporada,
            entradaPorJornada: jornada,
            repartoJornada: repartoJornada),
      );

  group('8 · el bote de la jornada', () {
    test('uno por ronda, con lo que puso quien jugó ESE día', () {
      // La ronda 1 la jugaron cuatro; la 2 y la 3, tres.
      final t = conJornada(jornada: 100);
      final jornadas = botesPorJornada(t, tablaDe(t, _temporada()));
      expect(jornadas, hasLength(3));
      final r1 = jornadas.firstWhere((j) => j.roundId == '1');
      expect(r1.jugadores, 4);
      expect(r1.total, 400);
      final r2 = jornadas.firstWhere((j) => j.roundId == '2');
      expect(r2.jugadores, 3);
      expect(r2.total, 300);
    });

    test('lo cobra quien ganó ese día, no quien va primero en la tabla', () {
      // Ana gana la 1, Beto la 2, Caro la 3. Si el bote del día lo cobrara el
      // líder de la temporada, Ana se llevaría los tres.
      final t = conJornada(jornada: 100);
      final jornadas = botesPorJornada(t, tablaDe(t, _temporada()));
      expect(jornadas.firstWhere((j) => j.roundId == '1').cobran.keys, [ana]);
      expect(jornadas.firstWhere((j) => j.roundId == '2').cobran.keys, [beto]);
      expect(jornadas.firstWhere((j) => j.roundId == '3').cobran.keys, [caro]);
    });

    test('el ganador del día se lleva el bote entero de ese día', () {
      final t = conJornada(jornada: 100);
      final r1 = botesPorJornada(t, tablaDe(t, _temporada()))
          .firstWhere((j) => j.roundId == '1');
      expect(r1.cobran[ana], 400);
    });

    test('con podio, el reparto del día puede ser distinto del final', () {
      final t = conJornada(jornada: 90, repartoJornada: RepartoDelBote.podio);
      final r1 = botesPorJornada(t, tablaDe(t, _temporada()))
          .firstWhere((j) => j.roundId == '1');
      // 360 en juego. Ana 1ª; Beto, Caro y Dani empatan a −100 en el segundo.
      final cobrado = r1.cobran.values.fold(0.0, (s, v) => s + v);
      expect((cobrado - 360).abs() < 1, isTrue, reason: 'cobrado = $cobrado');
      expect(r1.cobran[ana]! > (r1.cobran[beto] ?? 0), isTrue);
    });

    test('quien no juega una jornada no pone ni cobra en ella', () {
      // Dani solo juega la ronda 1.
      final t = conJornada(jornada: 100);
      final jornadas = botesPorJornada(t, tablaDe(t, _temporada()));
      expect(jornadas.firstWhere((j) => j.roundId == '1').nombres.keys,
          contains(dani));
      expect(jornadas.firstWhere((j) => j.roundId == '2').nombres.keys,
          isNot(contains(dani)));
      expect(saldoDeJornadas(dani, jornadas), -100,
          reason: 'puso una vez y no cobró: solo pierde esa');
    });

    test('el bote del día NO mira el mínimo de la temporada', () {
      // El mínimo es una regla de la temporada; el bote del día es del día.
      // Dani no clasifica pero jugó esa ronda y puso.
      final t = conJornada(jornada: 100, minimoRondas: 3);
      final r1 = botesPorJornada(t, tablaDe(t, _temporada()))
          .firstWhere((j) => j.roundId == '1');
      expect(r1.jugadores, 4);
      expect(r1.nombres.keys, contains(dani));
    });

    test('sin entrada por jornada no hay botes del día', () {
      final t = conJornada(jornada: 0);
      expect(botesPorJornada(t, tablaDe(t, _temporada())), isEmpty);
      expect(t.bote.hayBoteJornada, isFalse);
    });
  });

  group('9 · los dos botes no se suman', () {
    test('el final no incluye lo de las jornadas, ni al revés', () {
      final t = conJornada(temporada: 500, jornada: 100);
      final tabla = tablaDe(t, _temporada());
      final finalDelTorneo = boteDe(t, tabla);
      final jornadas = botesPorJornada(t, tabla);

      // Cuatro jugadores × 500 de temporada.
      expect(finalDelTorneo.total, 2000);
      // Y 400 + 300 + 300 en los tres días.
      expect(jornadas.fold(0.0, (s, j) => s + j.total), 1000);

      // Ninguna cifra vale 3000.
      expect(finalDelTorneo.total, isNot(3000));
      expect(finalDelTorneo.recaudado, isNot(3000));
    });

    test('el saldo de Ana en cada bolsa se lee por separado', () {
      final t = conJornada(temporada: 500, jornada: 100);
      final tabla = tablaDe(t, _temporada());
      final jornadas = botesPorJornada(t, tabla);

      // Ana gana la jornada 1: cobra 400 y puso 100 en cada una de las tres.
      expect(saldoDeJornadas(ana, jornadas), 100);
      // Y en el final: cobra los 2000 y había puesto 500.
      final suya = boteDe(t, tabla).lineas.firstWhere((l) => l.playerId == ana);
      expect(suya.saldo, 1500);
      // Son dos números, y ninguno es 1600.
      expect(suya.saldo + saldoDeJornadas(ana, jornadas), 1600,
          reason: 'la suma EXISTE aritméticamente; lo que no existe es una '
              'cifra en la app que la muestre');
    });

    test('cambiar la entrada por jornada no toca el bote final', () {
      final tabla = tablaDe(conJornada(), _temporada());
      final barato = boteDe(conJornada(jornada: 1), tabla);
      final caro2 = boteDe(conJornada(jornada: 9999), tabla);
      expect(barato.total, caro2.total);
    });

    test('y cambiar la entrada de temporada no toca los del día', () {
      final tabla = tablaDe(conJornada(), _temporada());
      final a = botesPorJornada(conJornada(temporada: 1), tabla);
      final b = botesPorJornada(conJornada(temporada: 9999), tabla);
      expect(a.map((j) => j.total).toList(), b.map((j) => j.total).toList());
    });

    test('el viaje a JSON conserva los dos', () {
      final t = conJornada(
          temporada: 500, jornada: 250, repartoJornada: RepartoDelBote.podio);
      final v = Torneo.fromJson(Map<String, dynamic>.from(t.toJson()));
      expect(v.bote.entrada, 500);
      expect(v.bote.entradaPorJornada, 250);
      expect(v.bote.repartoJornada, RepartoDelBote.podio);
    });

    test('un torneo sin bote por jornada no escribe esas claves', () {
      final j = conJornada(jornada: 0).toJson()['bote'] as Map;
      expect(j.containsKey('entradaPorJornada'), isFalse);
      expect(j.containsKey('repartoJornada'), isFalse);
    });
  });

  group('10 · el aviso de arrastre', () {
    test('con pocos jugadores no avisa', () {
      final t = conJornada();
      expect(avisoDeArrastre(t, tablaDe(t, _temporada())), isNull);
    });

    test('con muchos avisa, con el número y el importe', () {
      // El caso real: una fuente por fechas que arrastra rondas de otros grupos.
      final muchas = [
        for (var i = 0; i < 30; i++)
          _r('x$i', 1 + (i % 20), {'p$i': 10, 'q$i': -10}),
      ];
      final t = conJornada(temporada: 500);
      final aviso = avisoDeArrastre(t, tablaDe(t, muchas));
      expect(aviso, isNotNull);
      expect(aviso, contains('60 jugadores'));
      expect(aviso, contains('\$30000'), reason: 'el importe, no solo el número');
      expect(aviso, contains('sube el mínimo'),
          reason: 'y qué hacer al respecto');
    });

    test('sin bote avisa del número pero no inventa un importe', () {
      final muchas = [
        for (var i = 0; i < 30; i++)
          _r('x$i', 1 + (i % 20), {'p$i': 10, 'q$i': -10}),
      ];
      final t = conJornada(temporada: 0, jornada: 0);
      final aviso = avisoDeArrastre(t, tablaDe(t, muchas));
      expect(aviso, contains('60 jugadores'));
      expect(aviso, isNot(contains('\$')));
    });
  });

  group('11 · nombres duplicados', () {
    test('dos ids con el mismo nombre se detectan', () {
      // El caso real: alguien creado a mano en una ronda y el del directorio en
      // otra. La app los cuenta como dos personas, y hay que decirlo.
      final rondas = [
        RoundResult(
          roundId: 'r1', roundName: 'R1', courseName: 'C',
          playedAt: DateTime(2026, 3, 1), holesPlayed: 18,
          playerIds: const ['id_dir', 'id_mano'],
          playerNames: const {'id_dir': 'CAM', 'id_mano': 'CAM'},
          balances: const {'id_dir': 100.0, 'id_mano': -100.0},
          pairBalances: const {}, grossByPlayer: const {},
        ),
      ];
      final t = conJornada();
      final tabla = tablaDe(t, rondas);
      expect(tabla.nombresDuplicados.keys, ['CAM']);
      expect(tabla.nombresDuplicados['CAM'], ['id_dir', 'id_mano']);
    });

    test('NO se fusionan: siguen siendo dos filas', () {
      // Agrupar por nombre sumaría a dos personas que se llaman igual sin que
      // nadie lo pidiera. Se dice y se deja que el usuario decida.
      final rondas = [
        RoundResult(
          roundId: 'r1', roundName: 'R1', courseName: 'C',
          playedAt: DateTime(2026, 3, 1), holesPlayed: 18,
          playerIds: const ['id_dir', 'id_mano'],
          playerNames: const {'id_dir': 'CAM', 'id_mano': 'CAM'},
          balances: const {'id_dir': 100.0, 'id_mano': -100.0},
          pairBalances: const {}, grossByPlayer: const {},
        ),
      ];
      final t = conJornada();
      final tabla = tablaDe(t, rondas);
      expect(tabla.filas, hasLength(2));
      expect(tabla.filas.map((f) => f.nombre).toSet(), {'CAM'});
      expect(tabla.filas.map((f) => f.total).toList(), [100, -100]);
    });

    test('nombres distintos no se marcan', () {
      final t = conJornada();
      expect(tablaDe(t, _temporada()).nombresDuplicados, isEmpty);
    });
  });
}
