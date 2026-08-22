// ─────────────────────────────────────────────────────────────────────────────
// LA VENTAJA PRECARGADA SOBREVIVE A ELEGIR HANDICAP
//
// Reportado jugando: "el sliding auto de la ronda entre un jugador y otro puede
// ser Jugador A da a B 5 golpes, pero luego en la ronda 1v1 no se refleja ese
// sliding sino otro. En cuanto se modifica de forma manual el sliding, se aplica
// correctamente."
//
// Era una regresión mía del commit de ventajas: condicioné el acumulado del
// grupo a `ventaja == sliding`, así que una ronda creada con Handicap lo
// descartaba en silencio. La tarjeta 1v1 caía entonces a la diferencia de
// handicap —"otro sliding"—, y editar a mano funcionaba porque ese editor
// escribe pairSliding directo, saltándose esta ruta.
//
// El test que valía era este, no el que confirmaba que sliding funciona: la
// combinación rota era justo la que nadie había puesto a prueba.
//
// Vivía dentro de _createAndStartRound, donde ningún test podía llegar. Por eso
// el arreglo incluyó sacarlo a `slidingDeRonda`.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/bet_recipe.dart';

const a = 'jug-a';
const b = 'jug-b';
const c = 'jug-c';

/// A le da 5 golpes a B. La clave es recv(idMenor, idMayor): 'jug-a|jug-b'
/// significa lo que recibe jug-a, así que -5.
const acuerdo = {'jug-a|jug-b': -5.0};

void main() {
  group('1 · el acumulado del grupo entra con cada sistema', () {
    test('con HANDICAP elegido, el acuerdo bilateral sigue puesto', () {
      // El bug exacto. Antes devolvía {}.
      final r = slidingDeRonda(
        ventaja: SistemaDeVentaja.handicap,
        acumuladoDelGrupo: acuerdo,
        participantIds: [a, b],
      );
      expect(r['jug-a|jug-b'], -5.0,
          reason: 'elegir handicap no retira un acuerdo que nadie retiró');
    });

    test('con SLIDING elegido también, obviamente', () {
      final r = slidingDeRonda(
        ventaja: SistemaDeVentaja.sliding,
        acumuladoDelGrupo: acuerdo,
        participantIds: [a, b],
      );
      expect(r['jug-a|jug-b'], -5.0);
    });

    test('con SIN VENTAJA se vacía: ahí la instrucción es explícita', () {
      // El contrapeso. Si el acumulado entrara siempre, "todos brutos" quedaría
      // contradicho por strokes por pareja y el arreglo habría creado otro bug.
      final r = slidingDeRonda(
        ventaja: SistemaDeVentaja.ninguna,
        acumuladoDelGrupo: acuerdo,
        participantIds: [a, b],
      );
      expect(r, isEmpty);
    });
  });

  group('2 · la prioridad entre fuentes', () {
    test('lo editado en el paso de Ventaja manda sobre lo acumulado', () {
      final r = slidingDeRonda(
        ventaja: SistemaDeVentaja.sliding,
        acumuladoDelGrupo: acuerdo,
        participantIds: [a, b],
        editadoEnElPaso: (x, y) => -2.0,
      );
      expect(r['jug-a|jug-b'], -2.0,
          reason: 'el usuario acaba de tocarlo en pantalla');
    });

    test('con handicap, lo editado en el paso de sliding NO se escribe', () {
      // El motor prioriza pairSliding sobre el handicap: escribir aquí lo que
      // quedó en un paso que no se eligió aplicaría una ventaja que nadie pidió.
      final r = slidingDeRonda(
        ventaja: SistemaDeVentaja.handicap,
        acumuladoDelGrupo: acuerdo,
        participantIds: [a, b],
        editadoEnElPaso: (x, y) => -99.0,
      );
      expect(r['jug-a|jug-b'], -5.0);
    });

    test('la ventaja propia de un duelo manda sobre todo', () {
      // La ronda va con handicap y estos dos acuerdan lo suyo a scratch: 0
      // explícito, que el motor honra.
      final r = slidingDeRonda(
        ventaja: SistemaDeVentaja.handicap,
        acumuladoDelGrupo: acuerdo,
        participantIds: [a, b],
        duelosConVentajaPropia: [(a: a, b: b, delta: 0.0)],
      );
      expect(r['jug-a|jug-b'], 0.0);
    });

    test('y entra incluso con sin ventaja, porque es un pacto aparte', () {
      final r = slidingDeRonda(
        ventaja: SistemaDeVentaja.ninguna,
        acumuladoDelGrupo: acuerdo,
        participantIds: [a, b],
        duelosConVentajaPropia: [(a: a, b: b, delta: -3.0)],
      );
      expect(r['jug-a|jug-b'], -3.0);
    });

    test('el signo se invierte si el primero no es el id menor', () {
      // delta es lo que recibe d.a de d.b; la clave es recv(idMenor, idMayor).
      final r = slidingDeRonda(
        ventaja: SistemaDeVentaja.handicap,
        acumuladoDelGrupo: const {},
        participantIds: [a, b],
        duelosConVentajaPropia: [(a: b, b: a, delta: -3.0)],
      );
      expect(r['jug-a|jug-b'], 3.0,
          reason: 'si b recibe -3, a recibe +3');
    });
  });

  group('3 · quien no juega hoy no trae ventaja', () {
    test('se descarta el par cuyo rival no está en la ronda', () {
      final r = slidingDeRonda(
        ventaja: SistemaDeVentaja.handicap,
        acumuladoDelGrupo: const {'jug-a|jug-b': -5.0, 'jug-a|jug-c': -3.0},
        participantIds: [a, b],
      );
      expect(r.keys, ['jug-a|jug-b']);
      expect(r.containsKey('jug-a|jug-c'), isFalse,
          reason: 'jug-c no juega');
    });

    test('con los tres presentes se conservan ambos', () {
      final r = slidingDeRonda(
        ventaja: SistemaDeVentaja.handicap,
        acumuladoDelGrupo: const {'jug-a|jug-b': -5.0, 'jug-a|jug-c': -3.0},
        participantIds: [a, b, c],
      );
      expect(r.length, 2);
    });
  });
}
