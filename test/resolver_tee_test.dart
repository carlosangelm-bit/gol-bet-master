// ─────────────────────────────────────────────────────────────────────────────
// LA SALIDA QUE SE PIDE Y LA QUE SE JUEGA
//
// El fallo: cuatro caídas encadenadas, todas en silencio.
//
//     _teeByName(name) ?? _playerTees[p.id] ?? _defaultMaleTee ?? TeeInfo.standard
//
// Ninguna con voz. El eslabón que acababa mandando era `_defaultMaleTee`, que es
// EL PRIMER TEE DE LA LISTA. Así que pedir blancas y jugar azules no daba error:
// daba un CR y un Slope de otra salida, y un diferencial plausible calculado con
// ellos.
//
// Es la misma familia que las siete rondas con diferencial imposible: un valor
// creíble sustituye a uno que falta, y nadie se entera hasta tres semanas
// después, mirando el índice.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/resolver_tee.dart';

const azules = SalidaCandidata(
    nombre: 'AZULES', courseRating: 71.7, slopeRating: 149);
const blancas = SalidaCandidata(
    nombre: 'BLANCAS', courseRating: 69.5, slopeRating: 138);
const doradas = SalidaCandidata(
    nombre: 'DORADAS', courseRating: 67.1, slopeRating: 129);

/// El campo de Carlos: azules PRIMERO, que es lo que hacía el daño.
const campo = [azules, blancas, doradas];

void main() {
  group('1 · el caso que falló', () {
    test('CLAVE: pedir BLANCAS devuelve blancas, no la primera', () {
      final r = resolverSalida(campo, pedida: 'BLANCAS');
      expect(r.salida, blancas);
      expect(r.como, ComoSeResolvio.porNombre);
      expect(r.hayQueAvisar, isFalse);
    });

    test('y sus números son los suyos, no los de azules', () {
      // Es de donde salía el diferencial calculado con el tee de otro.
      final r = resolverSalida(campo, pedida: 'BLANCAS');
      expect(r.salida!.courseRating, 69.5);
      expect(r.salida!.slopeRating, 138);
    });

    test('CLAVE: y si NO está, se dice — no se cae en silencio', () {
      // Lo que no puede pasar es que nadie se entere.
      final r = resolverSalida(campo, pedida: 'VERDES');
      expect(r.hayQueAvisar, isTrue);
      expect(r.aviso, contains('VERDES'), reason: 'con lo que se pidió');
      expect(r.aviso, contains('AZULES'), reason: 'y con lo que se va a usar');
      // Sigue devolviendo una para que la ronda pueda crearse: bloquear por
      // esto sería peor que avisar.
      expect(r.salida, azules);
    });
  });

  group('2 · el nombre no basta como llave', () {
    test('CLAVE: la API con prefijos casa con el nombre limpio', () {
      // "50715, USGA, White, Men" es lo que devuelve la API; la app enseña el
      // nombre limpio, y el usuario guarda lo que ve. Comparar en crudo no
      // casaba nunca.
      const conBasura = [
        SalidaCandidata(
            nombre: '50715, USGA, White, Men',
            courseRating: 69.5,
            slopeRating: 138),
      ];
      final r = resolverSalida(conBasura, pedida: 'White Men');
      expect(r.salida, isNotNull);
      expect(r.como, ComoSeResolvio.porNombreLimpio);
      expect(r.hayQueAvisar, isFalse, reason: 'es la que se pidió: no hay nada '
          'que avisar');
    });

    test('y al revés: guardado en crudo, buscado limpio', () {
      const limpio = [
        SalidaCandidata(
            nombre: 'White Men', courseRating: 69.5, slopeRating: 138),
      ];
      final r = resolverSalida(limpio, pedida: '50715, USGA, White, Men');
      expect(r.salida, isNotNull);
      expect(r.como, ComoSeResolvio.porNombreLimpio);
    });

    test('CLAVE: si la API RENOMBRA el tee, el CR y el Slope lo salvan', () {
      // Son los dos números que distinguen una salida dentro de un campo. Un
      // nombre puede cambiar; estos no.
      const renombrado = [
        azules,
        SalidaCandidata(
            nombre: 'Championship White',
            courseRating: 69.5,
            slopeRating: 138),
      ];
      final r = resolverSalida(renombrado,
          pedida: 'BLANCAS', crPedido: 69.5, slopePedido: 138);
      expect(r.salida!.nombre, 'Championship White');
      expect(r.como, ComoSeResolvio.porRating);
    });

    test('CONTRAPESO: pero el rating NO atrapa cualquier cosa', () {
      // Sin esto, una tolerancia grande devolvería la salida de al lado y el
      // fallo volvería con otra cara.
      final r = resolverSalida(campo,
          pedida: 'VERDES', crPedido: 70.6, slopePedido: 144);
      expect(r.hayQueAvisar, isTrue,
          reason: 'a medio camino entre dos salidas no es ninguna');
    });

    test('y el Slope tiene que coincidir EXACTO', () {
      final r = resolverSalida(campo,
          pedida: 'X', crPedido: 69.5, slopePedido: 139);
      expect(r.hayQueAvisar, isTrue);
    });
  });

  group('3 · el orden de la cascada', () {
    test('CLAVE: el nombre exacto gana al rating', () {
      // Si dos salidas comparten CR y Slope —pasa con tees de hombre y mujer—
      // manda el nombre. Al revés se elegiría cualquiera de las dos.
      const gemelas = [
        SalidaCandidata(
            nombre: 'BLANCAS M', courseRating: 69.5, slopeRating: 138),
        SalidaCandidata(
            nombre: 'BLANCAS F', courseRating: 69.5, slopeRating: 138),
      ];
      final r = resolverSalida(gemelas,
          pedida: 'BLANCAS F', crPedido: 69.5, slopePedido: 138);
      expect(r.salida!.nombre, 'BLANCAS F');
      expect(r.como, ComoSeResolvio.porNombre);
    });

    test('sin preferencia, la primera y sin avisar', () {
      // No pedir nada no es un fallo.
      final r = resolverSalida(campo);
      expect(r.salida, azules);
      expect(r.como, ComoSeResolvio.sinPreferencia);
      expect(r.hayQueAvisar, isFalse);
    });

    test('un campo sin tees no revienta', () {
      final r = resolverSalida(const [], pedida: 'BLANCAS');
      expect(r.salida, isNull);
      expect(r.hayQueAvisar, isTrue);
    });

    test('CONTRAPESO: no avisa cuando encuentra lo que se pidió', () {
      // Sin esto, un `hayQueAvisar => true` fijo pasaría la prueba del aviso y
      // el usuario vería una alarma en cada ronda.
      for (final p in ['AZULES', 'blancas', 'DoRaDaS']) {
        expect(resolverSalida(campo, pedida: p).hayQueAvisar, isFalse,
            reason: p);
      }
    });
  });

  group('4 · qué salida usó una ronda vieja', () {
    test('CLAVE: se recupera del CR y el Slope, no se adivina', () {
      // Los diferenciales de antes no guardaban el tee, pero sí los dos números
      // con los que se calcularon. Es lo que permite saber qué rondas salieron
      // con el tee equivocado.
      expect(salidaSegunRating(campo, 71.7, 149), 'AZULES');
      expect(salidaSegunRating(campo, 69.5, 138), 'BLANCAS');
    });

    test('REGRESIÓN: la ronda del reporte era de AZULES', () {
      // CR 71.7 · Slope 149, con blancas pedidas.
      expect(salidaSegunRating(campo, 71.7, 149), 'AZULES');
      expect(salidaSegunRating(campo, 71.7, 149), isNot('BLANCAS'));
    });

    test('CONTRAPESO: y si no cuadra con ninguna, se dice que no', () {
      // Devolver la más parecida sería inventar el dato en vez de la cifra.
      expect(salidaSegunRating(campo, 70.0, 140), isNull);
      expect(salidaSegunRating(const [], 71.7, 149), isNull);
    });
  });

  group('5 · la limpieza de nombres', () {
    test('quita códigos y USGA, deja el resto', () {
      expect(limpiarNombreDeTee('50715, USGA, White, Men'), 'white men');
      expect(limpiarNombreDeTee('BLANCAS'), 'blancas');
    });

    test('CONTRAPESO: y no se come un nombre entero', () {
      // Si todo lo que hay son números, se queda con lo que había: mejor un
      // nombre feo que ninguno.
      expect(limpiarNombreDeTee('12345'), '12345');
      expect(limpiarNombreDeTee(''), '');
    });
  });
}
