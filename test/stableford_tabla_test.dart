// ─────────────────────────────────────────────────────────────────────────────
// LA TABLA STABLEFORD NO CAMBIÓ AL PARAMETRIZARSE
//
// La implementación anterior era una escalera de ifs. Se sustituyó por
// `clamp(puntosDelPar - rel, piso, techo)`, que con 2/0/5 da lo mismo — y ESTO
// es lo que lo demuestra, valor por valor, con los números copiados de la
// función vieja antes de tocarla.
//
// Sin este test la parametrización sería un cambio de comportamiento disfrazado
// de refactor: nadie estaba probando la tabla.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/engines/game_engine.dart';

/// La tabla vieja, transcrita de la escalera de ifs original.
int _vieja(int rel) {
  if (rel >= 2) return 0;
  if (rel == 1) return 1;
  if (rel == 0) return 2;
  if (rel == -1) return 3;
  if (rel == -2) return 4;
  return 5;
}

void main() {
  group('1 · la tabla clásica es idéntica a la anterior', () {
    test('para todo relativo al par entre -8 y +8', () {
      for (var rel = -8; rel <= 8; rel++) {
        expect(GameEngine.stablefordPuntos(rel), _vieja(rel),
            reason: 'rel = $rel');
      }
    });

    test('y los valores con nombre son los estándar', () {
      expect(GameEngine.stablefordPuntos(-3), 5, reason: 'albatros');
      expect(GameEngine.stablefordPuntos(-2), 4, reason: 'eagle');
      expect(GameEngine.stablefordPuntos(-1), 3, reason: 'birdie');
      expect(GameEngine.stablefordPuntos(0), 2, reason: 'par');
      expect(GameEngine.stablefordPuntos(1), 1, reason: 'bogey');
      expect(GameEngine.stablefordPuntos(2), 0, reason: 'doble');
      expect(GameEngine.stablefordPuntos(5), 0, reason: 'desastre');
    });
  });

  group('2 · los parámetros hacen lo que dicen', () {
    test('subir los puntos del par sube toda la tabla', () {
      expect(GameEngine.stablefordPuntos(0, puntosDelPar: 3, techo: 9), 3);
      expect(GameEngine.stablefordPuntos(-1, puntosDelPar: 3, techo: 9), 4);
    });

    test('bajar el piso permite puntos negativos', () {
      expect(GameEngine.stablefordPuntos(3, piso: -2), -1);
      expect(GameEngine.stablefordPuntos(5, piso: -2), -2,
          reason: 'y se detiene en el piso');
    });

    test('el techo corta por arriba', () {
      expect(GameEngine.stablefordPuntos(-9, techo: 5), 5);
      expect(GameEngine.stablefordPuntos(-9, techo: 8), 8);
    });
  });
}
