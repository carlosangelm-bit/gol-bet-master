// ─────────────────────────────────────────────────────────────────────────────
// QUÉ SE PUBLICA EN LA PANTALLA QUE VE CUALQUIERA
//
// El leaderboard proyectable se lee SIN SESIÓN: lo ve todo el que pase por
// delante de la tele de la casa club, incluidos los que no juegan.
//
// ── Por qué la lista es CERRADA ───────────────────────────────────────────────
//
// El riesgo no es el código de hoy: es que dentro de seis meses alguien añada un
// campo útil sin darse cuenta de que esa instantánea la ve cualquiera. Un test
// que comprueba que los campos esperados ESTÁN no caza eso; uno que comprueba
// que no hay ninguno más, sí — y falla en la línea donde se añadió, no en una
// pantalla seis meses después.
//
// Es el mismo test que ya protege sharedTorneos, y por el mismo motivo.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/leaderboard_publico.dart';
import 'package:golf_bet_master/models/round_result.dart';
import 'package:golf_bet_master/models/torneo.dart';

const ana = 'pid_a', beto = 'pid_b', caro = 'pid_c';
const nombres = {ana: 'Luis Herrera', beto: 'Ana Ruiz', caro: 'Dani Sotó'};

RoundResult _ronda(String id, Map<String, double> dinero,
        {Map<String, int> netos = const {}}) =>
    RoundResult(
      roundId: id,
      roundName: 'Sábado',
      courseName: 'Los Encinos',
      playedAt: DateTime(2026, 8, 29),
      holesPlayed: 18,
      playerIds: dinero.keys.toList(),
      playerNames: {for (final k in dinero.keys) k: nombres[k] ?? k},
      balances: dinero,
      pairBalances: const {},
      grossByPlayer: const {},
      netByPlayer: netos,
      stablefordByPlayer: const {},
      torneoIds: const ['t1'],
    );

Torneo _torneo({MetodoDePuntuacion metodo = MetodoDePuntuacion.posicion}) =>
    Torneo(
      id: 't1',
      nombre: 'Copa de Primavera',
      fuente: FuenteDeRondas.marcadas,
      metodo: metodo,
      participantes: const [ana, beto, caro],
      bote: const BoteConfig(entrada: 500),
    );

LeaderboardPublico _publicar({
  MetodoDePuntuacion metodo = MetodoDePuntuacion.posicion,
  InventarioProyectado inventario = const InventarioProyectado(),
}) {
  final t = _torneo(metodo: metodo);
  final rondas = [
    _ronda('r1', {ana: 300, beto: -100, caro: -200},
        netos: {ana: 70, beto: 74, caro: 78})
  ];
  return LeaderboardPublico.desde(
    token: 'tok',
    ownerUid: 'uid_org',
    torneo: t,
    tabla: tablaDe(t, rondas, nombres: nombres),
    cuando: DateTime(2026, 8, 29, 14, 0),
    inventario: inventario,
  );
}

void main() {
  group('1 · la lista cerrada de campos', () {
    test('el documento tiene EXACTAMENTE estos campos', () {
      final claves = _publicar().toJson().keys.toSet();
      expect(claves, {
        'ownerUid',
        'nombre',
        'emoji',
        'publicadoEn',
        'comoSePuntua',
        'rondas',
        'tabla',
      }, reason: 'la lista es cerrada a propósito: revisar antes de ampliarla');
    });

    test('y una fila tiene EXACTAMENTE estos', () {
      final fila =
          (_publicar().toJson()['tabla'] as List).first as Map<String, dynamic>;
      expect(fila.keys.toSet(), {'puesto', 'nombre', 'jugadas', 'medida'},
          reason: 'ni playerId, ni balances, ni roundId');
    });
  });

  group('2 · ni un solo importe', () {
    test('no aparece el bote ni ninguna de sus claves', () {
      final json = _publicar().toJson().toString();
      for (final prohibido in [
        'bote',
        'boteTotal',
        'boteReparto',
        'aportaBote',
        'cobraBote',
        'balances',
        'pairBalances',
        'jornadas',
      ]) {
        expect(json.contains(prohibido), isFalse, reason: prohibido);
      }
    });

    test('ni ids de jugador ni de ronda', () {
      // Lo mismo que se excluye de la instantánea con dinero: identifican
      // personas y rondas, y aquí encima no hay sesión que los proteja.
      final json = _publicar().toJson().toString();
      for (final prohibido in [ana, beto, caro, 'r1', 't1']) {
        expect(json.contains(prohibido), isFalse, reason: prohibido);
      }
    });

    test('CLAVE: con el torneo por DINERO, la medida no viaja', () {
      // El caso que obliga a que la medida sea opcional. La tabla guarda un
      // `total` cuyo significado depende del método, y con "por dinero ganado"
      // SON PESOS. Copiarlo sin mirar publicaría dinero en la pantalla más
      // expuesta del sistema, sin que nada avisara.
      final copia = _publicar(metodo: MetodoDePuntuacion.dinero);
      expect(copia.ocultaLaMedida, isTrue);
      for (final f in copia.tabla) {
        expect(f.medida, isNull);
      }
      expect(copia.toJson().toString().contains('300'), isFalse,
          reason: 'los \$300 de la ronda no pueden salir por ninguna vía');
    });

    test('y con score neto SÍ viaja: no es dinero', () {
      // El contrapeso. Si ocultar fuera siempre, la pantalla no serviría.
      final copia = _publicar(metodo: MetodoDePuntuacion.scoreNeto);
      expect(copia.ocultaLaMedida, isFalse);
      expect(copia.tabla.first.medida, isNotNull);
    });

    test('por posición también: los puntos no son pesos', () {
      final copia = _publicar();
      expect(copia.ocultaLaMedida, isFalse);
      expect(copia.tabla.first.medida, 10, reason: 'el primero, 10 puntos');
    });
  });

  group('3 · lo que SÍ tiene que estar', () {
    test('los nombres y los puestos, que son la pantalla', () {
      // Sin este contrapeso, un documento vacío pasaría todo lo de arriba.
      final copia = _publicar();
      expect(copia.tabla.length, 3);
      expect(copia.tabla.map((f) => f.nombre),
          containsAll(['Luis Herrera', 'Ana Ruiz', 'Dani Sotó']));
      expect(copia.tabla.first.puesto, 1);
      expect(copia.nombre, 'Copa de Primavera');
      expect(copia.comoSePuntua, isNotEmpty);
    });

    test('los que no llegan al mínimo también salen', () {
      // En una pantalla de casa club, no verse es peor que verse al final.
      final t = Torneo(
          id: 't1',
          nombre: 'Copa',
          fuente: FuenteDeRondas.marcadas,
          metodo: MetodoDePuntuacion.posicion,
          participantes: const [ana, beto, caro],
          minimoRondas: 5);
      final copia = LeaderboardPublico.desde(
        token: 'tok',
        ownerUid: 'uid',
        torneo: t,
        tabla: tablaDe(t, [_ronda('r1', {ana: 300, beto: -300})],
            nombres: nombres),
        cuando: DateTime(2026, 8, 29),
      );
      expect(copia.tabla.length, 3);
    });
  });

  group('4 · el inventario de patrocinio', () {
    InventarioProyectado lleno() => const InventarioProyectado(
          cabecera: PiezaDePatrocinio(
              etiqueta: 'PATROCINADOR OFICIAL',
              titular: 'Eleva cada gran ronda',
              logoUrl: 'https://x/logo.svg',
              cta: 'Conoce la experiencia',
              destinoUrl: 'https://x',
              textoAlternativo: 'Logotipo de la marca'),
          pie: [
            PiezaDePatrocinio(etiqueta: 'Socio', logoUrl: 'https://x/1.svg'),
            PiezaDePatrocinio(etiqueta: 'Socio', logoUrl: 'https://x/2.svg'),
          ],
          segundosDeRotacion: 10,
        );

    test('viaja entero y vuelve igual', () {
      final copia = _publicar(inventario: lleno());
      final ida = LeaderboardPublico.fromJson('tok', copia.toJson());
      expect(ida.inventario.cabecera?.titular, 'Eleva cada gran ronda');
      expect(ida.inventario.pie.length, 2);
      expect(ida.inventario.segundosDeRotacion, 10);
    });

    test('sin patrocinio no engorda el documento', () {
      // §13.2: un torneo sin patrocinador no muestra un hueco ni un
      // placeholder. Si el campo no está, la pantalla no tiene qué dibujar.
      expect(_publicar().toJson().containsKey('inventario'), isFalse);
      expect(const InventarioProyectado().vacio, isTrue);
    });

    test('una pieza a medias no se pinta, pero no rompe el documento', () {
      const aMedias = PiezaDePatrocinio(etiqueta: 'Socio');
      expect(aMedias.pintable, isFalse);
      const buena = PiezaDePatrocinio(etiqueta: 'Socio', logoUrl: 'x');
      expect(buena.pintable, isTrue);
    });

    test('el pie rota, y aquí sí puede', () {
      // §14.2: la prohibición del manual (§5.4) habla de los socios DENTRO de
      // la app, donde compiten con controles. En una TV la rotación es lo
      // esperado.
      expect(lleno().segundosDeRotacion, greaterThan(0));
    });
  });

  group('5 · apagar y encender', () {
    test('el documento apagado no lleva ni nombres ni tabla', () {
      // Mismo trato que sharedTorneos: revocar sin romper el enlace.
      final apagado = LeaderboardPublico.fromJson(
          'tok', {'ownerUid': 'uid', 'activo': false});
      expect(apagado.activo, isFalse);
      expect(apagado.tabla, isEmpty);
    });

    test('ausente = encendido: los enlaces de antes siguen sirviendo', () {
      expect(_publicar().activo, isTrue);
      expect(_publicar().toJson().containsKey('activo'), isFalse);
    });
  });
}
