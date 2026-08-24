// ─────────────────────────────────────────────────────────────────────────────
// LA AGREGACIÓN DEL TORNEO — qué rondas cuentan, y desde dónde
//
// La tabla sale de tablaDe(t, resultados), y esos resultados son los del que
// mira. El resultado de una ronda se escribe al CERRARLA, en la colección de
// quien cierra, y cerrar una ronda en vivo está reservado al dueño.
//
// De ahí sale la propiedad que hace que esto funcione sin colección nueva: si el
// organizador es dueño de las rondas de su torneo, sus resultados caen donde la
// tabla los busca. Lo que se prueba aquí es lo que se puede probar sin red: que
// la tabla agrega N rondas de N grupos distintos, y que la marca es lo que
// decide —no quién jugó—.
//
// La frontera de permisos se prueba con el emulador, en test_rules/run.mjs
// bloque 12.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/round_result.dart';
import 'package:golf_bet_master/models/torneo.dart';

/// Un grupo de cuatro con su ronda cerrada, como la que cierra el organizador.
RoundResult _grupo(int n, {String torneo = 'tor_1'}) {
  final gente = [for (var i = 0; i < 4; i++) 'pid_g${n}_$i'];
  return RoundResult(
    roundId: 'ronda_g$n',
    roundName: 'Grupo $n',
    courseName: 'Los Encinos',
    playedAt: DateTime(2026, 5, 10),
    holesPlayed: 18,
    playerIds: gente,
    playerNames: {for (final g in gente) g: g.toUpperCase()},
    // El primero de cada grupo gana; los otros tres pagan.
    balances: {
      for (var i = 0; i < gente.length; i++) gente[i]: i == 0 ? 300.0 : -100.0
    },
    pairBalances: const {},
    grossByPlayer: const {},
    netByPlayer: const {},
    stablefordByPlayer: const {},
    bettingGroupIds: const [],
    torneoIds: [torneo],
  );
}

Torneo _t({List<String>? participantes, double entrada = 0}) => Torneo(
      id: 'tor_1',
      nombre: 'Torneo del club',
      fuente: FuenteDeRondas.marcadas,
      metodo: MetodoDePuntuacion.dinero,
      participantes: participantes ??
          [for (var n = 1; n <= 5; n++) for (var i = 0; i < 4; i++) 'pid_g${n}_$i'],
      bote: BoteConfig(entrada: entrada),
    );

void main() {
  group('1 · cinco grupos, veinte personas: la tabla los agrega', () {
    final rondas = [for (var n = 1; n <= 5; n++) _grupo(n)];

    test('las cinco rondas cuentan', () {
      final tabla = tablaDe(_t(), rondas);
      expect(tabla.rondas, 5);
      // Y los veinte están, cada uno con su cifra.
      expect(tabla.filas.length + tabla.bajoMinimo.length, 20);
    });

    test('los cinco ganadores empatan arriba, con 300 cada uno', () {
      final tabla = tablaDe(_t(), rondas);
      final arriba = tabla.filas.where((f) => f.total == 300);
      expect(arriba, hasLength(5));
      expect(arriba.every((f) => f.puesto == 1), isTrue,
          reason: 'cinco que ganaron su grupo comparten el primer puesto');
    });

    test('la suma de la tabla es cero: nadie inventa dinero', () {
      final tabla = tablaDe(_t(), rondas);
      final suma = [...tabla.filas, ...tabla.bajoMinimo]
          .fold(0.0, (s, f) => s + f.total);
      expect(suma, closeTo(0, 0.001));
    });

    test('una ronda sin cerrar no está: la tabla solo ve resultados', () {
      // Es la propiedad que hace que "cerrar" sea la puerta. Una ronda a medio
      // jugar no tiene RoundResult, así que no puede contar.
      final tabla = tablaDe(_t(), rondas.take(3).toList());
      expect(tabla.rondas, 3);
    });
  });

  group('2 · la MARCA decide, no quién jugó', () {
    test('una ronda de otro torneo no entra', () {
      final mias = [_grupo(1), _grupo(2)];
      final ajena = _grupo(3, torneo: 'otro_torneo');
      final tabla = tablaDe(_t(), [...mias, ajena]);
      expect(tabla.rondas, 2);
      // Su gente SÍ aparece —están inscritos— pero con CERO: lo que no entra es
      // el dinero de una ronda que no es de este torneo. Aparecer inscrito y no
      // haber jugado es un estado legítimo; que te cuenten una ronda ajena, no.
      final delTres = [...tabla.filas, ...tabla.bajoMinimo]
          .where((f) => f.playerId.startsWith('pid_g3'));
      expect(delTres, hasLength(4));
      expect(delTres.every((f) => f.total == 0), isTrue,
          reason: 'una ronda de otro torneo movió cifras aquí');
      expect(delTres.every((f) => f.jugadas == 0), isTrue);
    });

    test('una ronda sin marca tampoco', () {
      final sinMarca = RoundResult(
        roundId: 'suelta',
        roundName: 'Sábado cualquiera',
        courseName: 'C',
        playedAt: DateTime(2026, 5, 10),
        holesPlayed: 18,
        playerIds: const ['pid_g1_0'],
        playerNames: const {'pid_g1_0': 'A'},
        balances: const {'pid_g1_0': 5000},
        pairBalances: const {},
        grossByPlayer: const {},
        netByPlayer: const {},
        stablefordByPlayer: const {},
        bettingGroupIds: const [],
      );
      final tabla = tablaDe(_t(), [_grupo(1), sinMarca]);
      expect(tabla.rondas, 1);
      // Y los 5000 no se cuelan en el total de nadie.
      expect(tabla.filas.every((f) => f.total.abs() <= 300), isTrue);
    });

    test('una ronda marcada para DOS torneos cuenta en los dos', () {
      final doble = RoundResult(
        roundId: 'doble',
        roundName: 'Cuenta doble',
        courseName: 'C',
        playedAt: DateTime(2026, 5, 11),
        holesPlayed: 18,
        playerIds: const ['pid_g1_0', 'pid_g1_1'],
        playerNames: const {'pid_g1_0': 'A', 'pid_g1_1': 'B'},
        balances: const {'pid_g1_0': 100, 'pid_g1_1': -100},
        pairBalances: const {},
        grossByPlayer: const {},
        netByPlayer: const {},
        stablefordByPlayer: const {},
        bettingGroupIds: const [],
        torneoIds: const ['tor_1', 'tor_2'],
      );
      expect(rondasDelTorneo(_t(), [doble]), hasLength(1));
      final otro = Torneo(
          id: 'tor_2',
          nombre: 'El otro',
          fuente: FuenteDeRondas.marcadas,
          participantes: const ['pid_g1_0', 'pid_g1_1']);
      expect(rondasDelTorneo(otro, [doble]), hasLength(1));
    });
  });

  group('3 · a escala de 25 grupos', () {
    test('cien personas, veinticinco rondas, y la tabla cuadra', () {
      final rondas = [for (var n = 1; n <= 25; n++) _grupo(n)];
      final t = _t(participantes: [
        for (var n = 1; n <= 25; n++)
          for (var i = 0; i < 4; i++) 'pid_g${n}_$i'
      ]);
      final tabla = tablaDe(t, rondas);
      expect(tabla.rondas, 25);
      expect(tabla.filas.length + tabla.bajoMinimo.length, 100);
      final suma = [...tabla.filas, ...tabla.bajoMinimo]
          .fold(0.0, (s, f) => s + f.total);
      expect(suma, closeTo(0, 0.001));
    });

    test('con bote, cada uno aporta una vez y el total es el que puso', () {
      // Cien personas a $200 son $20.000, y ni un peso más: el bote se cobra por
      // INSCRITO, no por ronda jugada.
      final t = _t(
          participantes: [
            for (var n = 1; n <= 25; n++)
              for (var i = 0; i < 4; i++) 'pid_g${n}_$i'
          ],
          entrada: 200);
      final rondas = [for (var n = 1; n <= 25; n++) _grupo(n)];
      final bote = boteDe(t, tablaDe(t, rondas));
      expect(bote.total, closeTo(20000, 0.001));
      expect(bote.lineas, hasLength(100));
      expect(bote.lineas.every((l) => l.aporta == 200), isTrue);
    });

    test('y un inscrito que no jugó sigue en la lista', () {
      // Con cien personas siempre falta alguien, y no verse después de pagar la
      // entrada sería lo peor que puede hacer esta pantalla.
      final t = _t(participantes: [
        for (var i = 0; i < 4; i++) 'pid_g1_$i',
        'pid_no_vino',
      ]);
      final tabla = tablaDe(t, [_grupo(1)]);
      final ids =
          [...tabla.filas, ...tabla.bajoMinimo].map((f) => f.playerId);
      expect(ids, contains('pid_no_vino'));
    });
  });
}
