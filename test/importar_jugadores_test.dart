// ─────────────────────────────────────────────────────────────────────────────
// IMPORTAR JUGADORES
//
// El parser es puro a propósito: lo que decide si esto sirve es qué hace con un
// archivo REAL —con la cabecera pegada por error, con un handicap vacío, con
// alguien repetido, con "12,5" en vez de "12.5"— y eso se prueba sin pantalla.
//
// Y el criterio que más protege: NO IMPORTA NADA. Devuelve qué pasaría. Importar
// treinta y descubrir después que dos fallaron obliga a revisar treinta fichas.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/importar_jugadores.dart';

void main() {
  group('1 · lo que Excel pone en el portapapeles: tabuladores', () {
    test('nombre y handicap por columnas', () {
      final r = parsearJugadores('Rafael Villalobos\t12\nAlan Betancourt\t18.5');
      expect(r.nuevos, hasLength(2));
      expect(r.nuevos[0].nombre, 'Rafael Villalobos');
      expect(r.nuevos[0].handicap, 12);
      expect(r.nuevos[1].handicap, 18.5);
      expect(r.rechazadas, isEmpty);
    });

    test('la coma decimal española: "18,5"', () {
      // Excel en español escribe 18,5. Rechazarlo sería rechazar el caso normal.
      final r = parsearJugadores('Alan\t18,5');
      expect(r.nuevos.first.handicap, 18.5);
    });

    test('un CSV pegado también entra', () {
      final r = parsearJugadores('Rafael,12\nAlan,18');
      expect(r.nuevos, hasLength(2));
      expect(r.nuevos[1].handicap, 18);
    });

    test('y con punto y coma, que es lo que exporta Excel en español', () {
      final r = parsearJugadores('Rafael;12\nAlan;18');
      expect(r.nuevos, hasLength(2));
    });

    test('el TABULADOR gana sobre la coma: "Pérez, Juan" es un nombre', () {
      // Un nombre con coma es normal y un CSV lo partiría en dos. Excel copia
      // con tabuladores, así que el tabulador manda cuando está.
      final r = parsearJugadores('Pérez, Juan\t14');
      expect(r.nuevos, hasLength(1));
      expect(r.nuevos.first.nombre, 'Pérez, Juan');
      expect(r.nuevos.first.handicap, 14);
    });

    test('solo nombres, sin handicap: entran con 0', () {
      // Un nombre sin handicap sigue siendo alguien que juega. Rechazar la fila
      // dejaría fuera a media lista por un dato que se pone después.
      final r = parsearJugadores('Rafael\nAlan\nMemo');
      expect(r.nuevos, hasLength(3));
      expect(r.nuevos.every((j) => j.handicap == 0), isTrue);
      expect(r.rechazadas, isEmpty);
    });

    test('las líneas vacías se saltan sin contarse como fallo', () {
      final r = parsearJugadores('Rafael\t12\n\n\nAlan\t18\n');
      expect(r.nuevos, hasLength(2));
      expect(r.rechazadas, isEmpty);
    });

    test('la cabecera pegada por error se salta', () {
      // Copiar la tabla entera incluye "Nombre  Handicap". Contarlo como fallo
      // haría dudar de una importación que salió bien.
      final r = parsearJugadores('Nombre\tHandicap\nRafael\t12');
      expect(r.nuevos, hasLength(1));
      expect(r.nuevos.first.nombre, 'Rafael');
      expect(r.rechazadas, isEmpty);
    });
  });

  group('2 · CRITERIO 4: los errores se dicen, con línea y motivo', () {
    test('un handicap que no es un número', () {
      final r = parsearJugadores('Rafael\t12\nAlan\tno sé\nMemo\t18');
      expect(r.nuevos, hasLength(2), reason: 'los buenos entran');
      expect(r.rechazadas, hasLength(1));
      expect(r.rechazadas.first.linea, 2);
      expect(r.rechazadas.first.motivo, contains('no es un handicap'));
      expect(r.rechazadas.first.texto, contains('Alan'));
    });

    test('un handicap fuera de rango: una columna mal pegada', () {
      // 6800 son las yardas del campo, no un handicap. Colarlo estropearía
      // todos los netos.
      final r = parsearJugadores('Rafael\t6800');
      expect(r.nuevos, isEmpty);
      expect(r.rechazadas.first.motivo, contains('fuera de rango'));
    });

    test('un repetido dentro de la lista', () {
      // Pegar la misma columna dos veces pasa, y meter a alguien dos veces en el
      // mismo torneo no es lo que nadie quiere.
      final r = parsearJugadores('Rafael\t12\nAlan\t18\nrafael\t12');
      expect(r.nuevos, hasLength(2));
      expect(r.rechazadas, hasLength(1));
      expect(r.rechazadas.first.linea, 3);
      expect(r.rechazadas.first.motivo, contains('Repetido'));
    });

    test('una fila sin nombre', () {
      final r = parsearJugadores('Rafael\t12\n\t18');
      expect(r.rechazadas.first.motivo, 'Sin nombre');
    });

    test('el resumen cuenta las tres cosas', () {
      final r = parsearJugadores('Rafael\t12\nAlan\tmal\nMemo\t18',
          existentes: const {'memo': 'pid_memo'});
      expect(r.resumen, contains('1 nuevo'));
      expect(r.resumen, contains('1 ya estaba'));
      expect(r.resumen, contains('1 sin leer'));
    });

    test('con la lista entera mal, no hay nada que importar, y se dice', () {
      final r = parsearJugadores('\tsin nombre\nOtro\t9999');
      expect(r.hayAlgo, isFalse);
      // El resumen NO dice "nada que importar" a secas: dice cuántas no se
      // leyeron, que es lo que hace falta para arreglarlas.
      expect(r.resumen, '2 sin leer');
      expect(r.rechazadas, hasLength(2));
    });

    test('con el texto vacío sí es "nada que importar"', () {
      expect(parsearJugadores('').resumen, 'Nada que importar');
      expect(parsearJugadores('   \n  \n').hayAlgo, isFalse);
    });
  });

  group('3 · CRITERIO 3: quien ya está se REUTILIZA', () {
    test('con el mismo nombre sale como existente, con su id', () {
      final r = parsearJugadores('Rafael\t12\nNuevo\t8',
          existentes: const {'rafael': 'pid_rafa'});
      expect(r.existentes, hasLength(1));
      expect(r.existentes.first.idExistente, 'pid_rafa');
      expect(r.existentes.first.yaEstaba, isTrue);
      expect(r.nuevos, hasLength(1));
      expect(r.nuevos.first.nombre, 'Nuevo');
      expect(r.nuevos.first.yaEstaba, isFalse);
    });

    test('el nombre se compara sin acentos ni mayúsculas ni espacios de más',
        () {
      // Es lo único que trae una hoja de cálculo, así que al menos que no falle
      // por escribirlo distinto.
      for (final variante in [
        'José Pérez',
        'jose perez',
        '  JOSÉ   PÉREZ  ',
        'Jose Pérez',
      ]) {
        final r = parsearJugadores('$variante\t12',
            existentes: const {'jose perez': 'pid_jose'});
        expect(r.existentes, hasLength(1), reason: variante);
        expect(r.nuevos, isEmpty, reason: variante);
      }
    });

    test('nombreComparable normaliza lo que tiene que normalizar', () {
      expect(nombreComparable('  Ñoño   Muñiz '), 'nono muniz');
      expect(nombreComparable('Cavazos'), nombreComparable('CAVAZOS'));
      // Y NO junta a dos personas distintas.
      expect(nombreComparable('Juan Pérez') == nombreComparable('Juan Peréz'),
          isTrue,
          reason: 'los acentos mal puestos son la misma persona');
      expect(nombreComparable('Juan') == nombreComparable('Juana'), isFalse);
    });

    test('todos juntos van en el orden del texto', () {
      final r = parsearJugadores('Uno\t1\nDos\t2\nTres\t3',
          existentes: const {'dos': 'pid_dos'});
      expect(r.todos.map((j) => j.nombre), ['Uno', 'Dos', 'Tres']);
    });
  });

  group('4 · una lista de 32, que es el caso del encargo', () {
    test('entran las 32 y ninguna se pierde', () {
      final texto = [
        for (var i = 1; i <= 32; i++) 'Jugador $i\t${i % 30}',
      ].join('\n');
      final r = parsearJugadores(texto);
      expect(r.nuevos, hasLength(32));
      expect(r.rechazadas, isEmpty);
      expect(r.todos, hasLength(32));
    });

    test('con 30 ya en el directorio, solo se crean 2', () {
      final texto = [
        for (var i = 1; i <= 32; i++) 'Jugador $i\t12',
      ].join('\n');
      final r = parsearJugadores(texto, existentes: {
        for (var i = 1; i <= 30; i++) 'jugador $i': 'pid_$i',
      });
      expect(r.existentes, hasLength(30));
      expect(r.nuevos, hasLength(2));
    });
  });
}
