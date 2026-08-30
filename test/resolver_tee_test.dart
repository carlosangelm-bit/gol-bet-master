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
import 'package:golf_bet_master/services/golf_course_service.dart';

const azules = SalidaCandidata(
    nombre: 'AZULES', courseRating: 71.7, slopeRating: 149, genero: 'M');
const blancas = SalidaCandidata(
    nombre: 'BLANCAS', courseRating: 69.5, slopeRating: 138, genero: 'M');
const doradas = SalidaCandidata(
    nombre: 'DORADAS', courseRating: 67.1, slopeRating: 129, genero: 'M');

/// Y la BLANCAS DE MUJERES, que se llama igual y tiene otros números.
///
/// Es la que hacía que una ronda nueva llegara marcada como "blancas de
/// mujeres": el género se calculaba preguntando si alguna salida de mujeres se
/// llamaba igual, así que la de hombres se etiquetaba como de ellas.
const blancasF = SalidaCandidata(
    nombre: 'BLANCAS', courseRating: 72.4, slopeRating: 131, genero: 'F');

/// El campo de Carlos: azules PRIMERO, que es lo que hacía el daño.
const campo = [azules, blancas, doradas];

/// El mismo campo con las salidas de mujeres detrás, como los da la API.
const campoConDamas = [azules, blancas, doradas, blancasF];

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

  // ───────────────────────────────────────────────────────────────────────────
  // 6 · DOS SALIDAS QUE SE LLAMAN IGUAL
  //
  // El campo de Carlos tiene BLANCAS de hombres y BLANCAS de mujeres. Es el
  // caso que la cascada ya preveía —"el nombre exacto gana al rating porque los
  // tees de hombre y mujer comparten CR y Slope"— y encima destapó un tercer
  // caso de la misma familia: el género se calculaba por NOMBRE, así que la de
  // hombres se etiquetaba como de mujeres.
  // ───────────────────────────────────────────────────────────────────────────
  group('6 · el género es de la lista, no del nombre', () {
    test('CLAVE: cada candidata sabe de qué lista viene', () {
      expect(blancas.genero, 'M');
      expect(blancasF.genero, 'F');
      expect(blancas.nombre, blancasF.nombre,
          reason: 'y se llaman igual: por eso el nombre no sirve de género');
    });

    test('CLAVE: pedir BLANCAS sin más da la de hombres, que va primero', () {
      // La app no guarda el género de la cuenta, así que en un empate manda el
      // orden de la API: masculinas primero. Es lo que había, y ahora es una
      // decisión escrita en vez de un efecto del orden.
      final r = resolverSalida(campoConDamas, pedida: 'BLANCAS');
      expect(r.salida!.genero, 'M');
      expect(r.salida!.courseRating, 69.5);
      expect(r.indice, 1);
    });

    test('CLAVE: y con género pedido, manda el género', () {
      final r = resolverSalida(campoConDamas,
          pedida: 'BLANCAS', generoPreferido: 'F');
      expect(r.salida!.genero, 'F');
      expect(r.salida!.courseRating, 72.4,
          reason: 'y con ello el CR de SU salida, no el de la otra');
      expect(r.indice, 3);
    });

    test('CLAVE: el ÍNDICE distingue lo que el nombre no', () {
      // Devolver solo el nombre obliga a buscarlo otra vez, y esa segunda
      // búsqueda se queda con el primero que se llame igual. De ahí venía que
      // la de hombres acabara etiquetada como de mujeres.
      final m = resolverSalida(campoConDamas, pedida: 'BLANCAS');
      final f = resolverSalida(campoConDamas,
          pedida: 'BLANCAS', generoPreferido: 'F');
      expect(m.salida!.nombre, f.salida!.nombre, reason: 'mismo nombre');
      expect(m.indice, isNot(f.indice), reason: 'y distinta salida');
    });

    test('CONTRAPESO: un género que no existe no rompe la búsqueda', () {
      // Sin esto, pedir un género ausente podría devolver null y dejar la
      // ronda sin salida.
      final r = resolverSalida(campo, pedida: 'BLANCAS', generoPreferido: 'F');
      expect(r.salida, blancas, reason: 'cae en la que hay, no en nada');
      expect(r.hayQueAvisar, isFalse);
    });

    test('y el índice apunta siempre a la lista que se pasó', () {
      for (var i = 0; i < campoConDamas.length; i++) {
        final r = resolverSalida(campoConDamas,
            pedida: campoConDamas[i].nombre,
            generoPreferido: campoConDamas[i].genero);
        expect(campoConDamas[r.indice].courseRating,
            campoConDamas[i].courseRating,
            reason: campoConDamas[i].nombre);
      }
    });
  });

  group('7 · deducir el histórico busca en TODO el campo', () {
    test('CLAVE: la ronda del 28 de agosto sale AZULES', () {
      // Buscar solo en la salida preferida habría acertado únicamente con las
      // rondas que ya estaban bien — justo las que no hace falta deducir.
      expect(salidaSegunRating(campoConDamas, 71.7, 149), 'AZULES');
    });

    test('y las de mujeres también entran en la búsqueda', () {
      expect(salidaSegunRating(campoConDamas, 72.4, 131), 'BLANCAS');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 8 · EL NOMBRE ES PARA LEERLO, NO PARA LLEVAR DATOS DENTRO
  //
  // Cuarta vez en el proyecto que un dato horneado en un nombre acaba
  // mintiendo: el nombre del lado en las apuestas, el "1 Pot" del catálogo, y
  // el tee dentro del nombre del campo.
  //
  // Siempre por lo mismo: el nombre se guarda una vez y el dato cambia después,
  // o se construye desde un sitio distinto del que lo lee.
  // ───────────────────────────────────────────────────────────────────────────
  group('8 · quitar el tee del nombre del campo', () {
    const conocidos = ['AZULES', 'BLANCAS', 'DORADAS'];

    test('CLAVE: se quita cuando lo de dentro es una salida', () {
      expect(
          nombreDeCampoSinTee(
              'Club De Golf Mexico — Mexico (AZULES)', conocidos),
          'Club De Golf Mexico — Mexico');
    });

    test('CLAVE: y NO se quita cuando es parte del nombre del club', () {
      // Sería cambiar un dato mentiroso por un dato mutilado.
      expect(nombreDeCampoSinTee('Club de Golf (Norte)', conocidos),
          'Club de Golf (Norte)');
      expect(nombreDeCampoSinTee('Real Club (1904)', conocidos),
          'Real Club (1904)');
    });

    test('reconoce el tee aunque venga con los prefijos de la API', () {
      expect(
          nombreDeCampoSinTee('Campo (50715, USGA, Blancas)', conocidos),
          'Campo');
    });

    test('CONTRAPESO: sin lista de tees no se toca nada', () {
      // Preferimos un nombre feo a uno cortado.
      expect(nombreDeCampoSinTee('Campo (AZULES)', const []),
          'Campo (AZULES)');
    });

    test('y un nombre sin paréntesis se queda igual', () {
      for (final n in ['Campo', 'Campo — Sur', '', 'Campo ()']) {
        expect(nombreDeCampoSinTee(n, conocidos), n, reason: n);
      }
    });

    test('solo el paréntesis FINAL, no uno del medio', () {
      // "Campo (AZULES) — Sur" no acaba en paréntesis: no se toca.
      expect(nombreDeCampoSinTee('Campo (AZULES) — Sur', conocidos),
          'Campo (AZULES) — Sur');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 9 · EN EL ORIGEN
  //
  // De aquí salía el nombre con el tee dentro. Sin esta prueba, volver a
  // hornearlo no rompía nada: los tests de limpieza pasan igual, porque limpian
  // lo que ya está escrito.
  // ───────────────────────────────────────────────────────────────────────────
  group('9 · el nombre del campo, en el origen', () {
    ApiTeeBox tee(String nombre) => ApiTeeBox(
          teeName: nombre,
          courseRating: 71.7,
          slopeRating: 149,
          parTotal: 72,
          totalYards: 6500,
          numberOfHoles: 18,
          holes: [
            for (var i = 1; i <= 18; i++)
              ApiHole(holeNumber: i, par: 4, yardage: 380, strokeIndex: i)
          ],
        );

    test('CLAVE: el nombre NO lleva la salida dentro', () {
      final c = tee('AZULES').toCourseInfo('Club De Golf Mexico', 'Mexico');
      expect(c.name, 'Club De Golf Mexico — Mexico');
      expect(c.name.contains('AZULES'), isFalse,
          reason: 'el nombre es para leerlo, no para llevar datos dentro');
    });

    test('y da igual qué salida sea: el nombre es el mismo', () {
      // Es la propiedad de verdad: dos salidas del mismo campo no pueden dar
      // dos nombres, porque entonces el nombre lleva el dato otra vez.
      final a = tee('AZULES').toCourseInfo('Club', 'Sur');
      final b = tee('BLANCAS').toCourseInfo('Club', 'Sur');
      expect(a.name, b.name);
    });

    test('CONTRAPESO: y sigue distinguiendo club de recorrido', () {
      // Sin esto, devolver siempre el nombre del club pasaría lo de arriba.
      expect(tee('X').toCourseInfo('Club', 'Sur').name, 'Club — Sur');
      expect(tee('X').toCourseInfo('Club', '').name, 'Club');
      expect(tee('X').toCourseInfo('Club', 'Club').name, 'Club');
    });
  });
}
