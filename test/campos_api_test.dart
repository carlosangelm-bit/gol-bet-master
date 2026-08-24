// ─────────────────────────────────────────────────────────────────────────────
// LO QUE LLEGA DE LA API NO SE DA POR BUENO
//
// El fallo: "Error al buscar: TypeError: 3: type 'int' is not a subtype of type
// 'List<dynamic>?'". Un campo devolvió un NÚMERO donde el parseo esperaba una
// lista —el 3 del mensaje ES el valor— el cast lanzó, y se cayó TODA la
// búsqueda. No ese campo: la búsqueda entera.
//
// Son datos de un tercero, así que su forma no se puede garantizar. Lo que sí se
// puede es que una forma inesperada no tumbe la pantalla, y eso es lo que se
// prueba aquí: cada campo de la respuesta se lee por su cuenta y el que no se
// pueda leer se omite.
//
// El test más importante es el último: con una respuesta donde UN campo está mal
// y dos están bien, salen los dos buenos. Es la diferencia entre "ese campo no
// aparece" y "no puedes buscar".
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/services/golf_course_service.dart';

/// Un campo bien formado, para partir de algo que funciona.
Map<String, dynamic> _bueno({String id = 'abc123', String nombre = 'Los Encinos'}) => {
      'id': id,
      'club_name': nombre,
      'course_name': 'Campo Sur',
      'location': <String, dynamic>{
        'city': 'Ciudad de México',
        'state': 'CDMX',
        'country': 'MX'
      },
      // <dynamic> a propósito: el test mete números y nulos donde la API los
      // mete, y con literales tipados no cabrían.
      'tees': <String, dynamic>{
        'male': <dynamic>[
          <String, dynamic>{
            'tee_name': 'Azules',
            'course_rating': 72.4,
            'slope_rating': 130,
            'par_total': 72,
            'total_yards': 6800,
            'number_of_holes': 18,
            'holes': <dynamic>[
              for (var h = 1; h <= 18; h++)
                <String, dynamic>{'par': 4, 'yardage': 380, 'handicap': h}
            ],
          }
        ],
      },
    };

void main() {
  group('1 · el caso exacto del fallo: "holes" llega como número', () {
    test('no lanza, y el campo se puede seguir eligiendo', () {
      // Es el TypeError del reporte: el 3 era el valor de un campo que se
      // casteaba a lista.
      final j = _bueno();
      (j['tees'] as Map)['male'][0]['holes'] = 3;

      late final campo;
      expect(() => campo = ApiCourse.fromJson(j), returnsNormally);
      expect(campo.clubName, 'Los Encinos');
      expect(campo.maleTees, hasLength(1));
      // Sin hoyos, pero el tee existe: el usuario puede elegir el campo, que es
      // lo que quería hacer.
      expect(campo.maleTees.first.holes, isEmpty);
      expect(campo.maleTees.first.teeName, 'Azules');
    });

    test('y con los hoyos bien, siguen entrando los 18', () {
      // El contrapeso: si el arreglo hubiera vaciado los hoyos siempre, este
      // test lo diría.
      final campo = ApiCourse.fromJson(_bueno());
      expect(campo.maleTees.first.holes, hasLength(18));
      expect(campo.maleTees.first.holes.first.par, 4);
    });
  });

  group('2 · cualquier campo con otra forma se aguanta', () {
    test('"tees" como lista en vez de mapa', () {
      final j = _bueno()..['tees'] = [1, 2, 3];
      late final campo;
      expect(() => campo = ApiCourse.fromJson(j), returnsNormally);
      expect(campo.allTees, isEmpty);
      expect(campo.clubName, 'Los Encinos');
    });

    test('"location" como texto en vez de mapa', () {
      final j = _bueno()..['location'] = 'Ciudad de México';
      late final campo;
      expect(() => campo = ApiCourse.fromJson(j), returnsNormally);
      expect(campo.city, isEmpty);
    });

    test('nombres como números', () {
      final j = _bueno()
        ..['club_name'] = 42
        ..['course_name'] = 7;
      late final campo;
      expect(() => campo = ApiCourse.fromJson(j), returnsNormally);
      expect(campo.clubName, 'Campo sin nombre');
      expect(campo.courseName, isEmpty);
    });

    test('"male" como número, y un tee suelto que no es mapa', () {
      final j = _bueno();
      (j['tees'] as Map)['male'] = 2;
      expect(() => ApiCourse.fromJson(j), returnsNormally);

      final k = _bueno();
      (k['tees'] as Map)['male'] = <dynamic>[
        1,
        'dos',
        null,
        ...((k['tees'] as Map)['male'] as List)
      ];
      final campo = ApiCourse.fromJson(k);
      // Los basura se omiten y el bueno entra.
      expect(campo.maleTees, hasLength(1));
      expect(campo.maleTees.first.teeName, 'Azules');
    });

    test('un hoyo suelto con la forma rara se omite y los demás entran', () {
      final j = _bueno();
      final holes = (j['tees'] as Map)['male'][0]['holes'] as List;
      holes[3] = 5; // un número donde iba un mapa
      holes[7] = null;
      final campo = ApiCourse.fromJson(j);
      expect(campo.maleTees.first.holes, hasLength(16));
    });

    test('el campo sin tees ninguno sigue siendo elegible', () {
      final j = _bueno()..remove('tees');
      final campo = ApiCourse.fromJson(j);
      expect(campo.allTees, isEmpty);
      expect(campo.displayName, contains('Los Encinos'));
    });
  });

  group('3 · UN campo malo no tumba la búsqueda', () {
    test('con uno roto y dos buenos, salen los dos buenos', () {
      // Es el test que importa. Antes un solo campo con un dato raro dejaba al
      // usuario sin poder buscar nada.
      final roto = _bueno(id: 'malo', nombre: 'Campo Roto');
      // Algo que sí hace lanzar al parseo del tee, no solo una forma rara.
      (roto['tees'] as Map)['male'] = <dynamic>[
        <String, dynamic>{
          'tee_name': 'X',
          'holes': <String, dynamic>{'no': 'es una lista'}
        }
      ];
      final body = {
        'courses': [
          _bueno(id: 'uno', nombre: 'Los Encinos'),
          roto,
          _bueno(id: 'dos', nombre: 'Chapultepec'),
        ]
      };
      final res = GolfCourseService.camposDeLaRespuesta(body);
      expect(res.map((c) => c.clubName), containsAll(['Los Encinos', 'Chapultepec']));
      expect(res, hasLength(greaterThanOrEqualTo(2)));
    });

    test('"courses" como número devuelve vacío en vez de lanzar', () {
      expect(GolfCourseService.camposDeLaRespuesta({'courses': 3}), isEmpty);
      expect(GolfCourseService.camposDeLaRespuesta({'courses': null}), isEmpty);
      expect(GolfCourseService.camposDeLaRespuesta('no soy un mapa'), isEmpty);
      expect(GolfCourseService.camposDeLaRespuesta(null), isEmpty);
      expect(GolfCourseService.camposDeLaRespuesta(3), isEmpty);
    });

    test('entradas basura dentro de courses se omiten', () {
      final res = GolfCourseService.camposDeLaRespuesta({
        'courses': [3, null, 'texto', _bueno(nombre: 'El bueno'), []]
      });
      expect(res, hasLength(1));
      expect(res.first.clubName, 'El bueno');
    });

    test('una respuesta buena entera sigue funcionando', () {
      // El contrapeso final: sin esto, todo lo de arriba pasaría con un parser
      // que devolviera siempre vacío.
      final res = GolfCourseService.camposDeLaRespuesta({
        'courses': [_bueno(nombre: 'A'), _bueno(nombre: 'B')]
      });
      expect(res.map((c) => c.clubName), ['A', 'B']);
      expect(res.first.maleTees.first.holes, hasLength(18));
    });
  });
}
