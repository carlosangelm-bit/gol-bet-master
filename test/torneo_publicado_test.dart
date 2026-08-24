// ─────────────────────────────────────────────────────────────────────────────
// LA COPIA PUBLICADA
//
// La regla "la tabla se deriva, nunca se guarda" no queda derogada: queda
// precisada. Existía para evitar que un total calculado se quede desfasado sin
// avisar —lo que pasó con el tablero de Inicio— y un total guardado en silencio
// PRETENDE ser la verdad. Una instantánea con sello de fecha se declara copia.
//
// El test que más protege es el de QUÉ NO CONTIENE. Es la mitad del diseño: lo
// que hace segura la regla de Firestore no es la condición, es que el documento
// solo tenga lo que se quiso compartir. Si un campo se cuela aquí, la regla
// sigue estando "bien escrita" y los datos salen igual.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/round_result.dart';
import 'package:golf_bet_master/models/torneo.dart';
import 'package:golf_bet_master/models/torneo_publicado.dart';

// Ids con la forma de los reales: un uuid, no un nombre. Buscarlos por
// subcadena solo dice algo si no aparecen por casualidad dentro de una palabra
// —"g-ana-ste" contiene "ana"— y ese falso positivo me hizo perseguir un fallo
// que no existía.
const ana = 'pid_7f3a91', beto = 'pid_2c8e04', caro = 'pid_b5d117';

RoundResult _r(String id, int dia, Map<String, double> dinero) => RoundResult(
      roundId: id,
      roundName: 'Sábado $dia',
      courseName: 'Los Encinos',
      playedAt: DateTime(2026, 3, dia),
      holesPlayed: 18,
      playerIds: dinero.keys.toList(),
      playerNames: {
        for (final k in dinero.keys)
          k: {ana: 'ANA', beto: 'BETO', caro: 'CARO'}[k] ?? k,
      },
      balances: dinero,
      // Datos que NO deben acabar publicados.
      pairBalances: const {'pid_2c8e04|pid_7f3a91': 300.0},
      grossByPlayer: const {ana: 78},
      netByPlayer: const {ana: 70},
      stablefordByPlayer: const {ana: 40},
      bettingGroupIds: const ['grupo_secreto'],
    );

Torneo _t({double entrada = 500, double jornada = 0, int minimo = 0}) => Torneo(
      id: 't1', nombre: 'Copa CGM 2026',
      fuente: FuenteDeRondas.rango,
      metodo: MetodoDePuntuacion.dinero,
      participantes: const [ana, beto, caro],
      minimoRondas: minimo,
      bote: BoteConfig(entrada: entrada, entradaPorJornada: jornada),
    );

TorneoPublicado _publicar(Torneo t, List<RoundResult> rondas,
    {DateTime? cuando}) {
  final tabla = tablaDe(t, rondas);
  return TorneoPublicado.desde(
    token: 'tok_x',
    ownerUid: 'uid_org',
    torneo: t,
    tabla: tabla,
    bote: boteDe(t, tabla),
    jornadas: botesPorJornada(t, tabla),
    cuando: cuando ?? DateTime(2026, 4, 1, 12),
  );
}

List<RoundResult> _rondas() => [
      _r('1', 1, {ana: 300, beto: -150, caro: -150}),
      _r('2', 8, {ana: -50, beto: 100, caro: -50}),
    ];

void main() {
  group('1 · qué NO contiene la copia', () {
    test('ni ids de jugadores, ni de grupos, ni de rondas', () {
      // Es la mitad del diseño. Lo que hace segura la regla de Firestore no es
      // la condición, es que el documento solo tenga lo que se quiso compartir.
      final json = _publicar(_t(), _rondas()).toJson().toString();
      // Las CONSTANTES, no literales: la lista tiene que seguir a los ids del
      // fixture. Con literales, cambiar los ids dejaba el test comprobando
      // cadenas que ya no existían — pasando en verde sin mirar nada.
      for (final prohibido in [
        ana, beto, caro,                // ids de jugadores
        'grupo_secreto',                // el grupo de apuesta
        'tok_x',                        // el token no va dentro; es el id del doc
      ]) {
        expect(json.contains(prohibido), isFalse,
            reason: '"$prohibido" se ha colado en la copia');
      }
    });

    test('ni scores, ni balances de pareja, ni el bruto', () {
      final json = _publicar(_t(), _rondas()).toJson().toString();
      for (final clave in [
        'pairBalances', 'grossByPlayer', 'netByPlayer',
        'stablefordByPlayer', 'balances', 'bettingGroupIds',
      ]) {
        expect(json.contains(clave), isFalse, reason: clave);
      }
    });

    test('ni el nombre de los campos, ni siquiera vacíos', () {
      // Un campo vacío publicado hoy es un campo con datos mañana, cuando
      // alguien lo rellene sin acordarse de esto.
      final claves = _publicar(_t(), _rondas()).toJson().keys.toSet();
      expect(claves, {
        'ownerUid', 'nombre', 'emoji', 'publicadoEn',
        'comoSePuntua', 'comoSeAcumula', 'rondas', 'tabla',
        'boteTotal', 'boteReparto', 'boteProvisional',
        // REVISADO al añadirlo: es el id del PROPIO objeto que se comparte, no
        // el de una persona ni el de una ronda —que es lo que esta lista
        // protege—. El token ya lo identifica públicamente igual de bien, y hace
        // falta porque quien sigue el torneo tiene que poder publicarle
        // resultados con el id por el que el organizador los consulta.
        'torneoId',
        // REVISADO al añadirlo: cómo puntúa el torneo. Es CONFIGURACIÓN, no
        // datos de nadie, y ya viajaba en prosa como comoSePuntua. Está en
        // máquina porque hay que DECIDIR con él: si el torneo puntúa por score,
        // una ronda suya empieza sin configurar apuestas —la medida es el
        // score— y a quien la crea no hay que preguntarle nada.
        'metodo',
      }, reason: 'la lista es cerrada a propósito: revisar antes de ampliarla');
    });

    test('los nombres SÍ van: son lo que hace legible la tabla', () {
      // El contrapeso. Si no fuera nada, los tres de arriba pasarían con una
      // copia vacía.
      final copia = _publicar(_t(), _rondas());
      expect(copia.tabla.map((f) => f.nombre).toSet(), {'ANA', 'BETO', 'CARO'});
      expect(copia.nombre, 'Copa CGM 2026');
    });
  });

  group('2 · la copia coincide con lo que se ve en la app', () {
    test('mismos puestos y mismos totales que la tabla derivada', () {
      // No recalcula: recibe la tabla ya hecha. Si calculara por su cuenta, el
      // enlace podría enseñar otra cosa que la pantalla.
      final t = _t();
      final tabla = tablaDe(t, _rondas());
      final copia = _publicar(t, _rondas());
      for (final f in tabla.filas) {
        final pub = copia.tabla.firstWhere((x) => x.nombre == f.nombre);
        expect(pub.puesto, f.puesto, reason: f.nombre);
        expect(pub.total, f.total, reason: f.nombre);
      }
    });

    test('y el bote también', () {
      final t = _t(entrada: 500);
      final copia = _publicar(t, _rondas());
      expect(copia.boteTotal, 1500, reason: 'tres inscritos × 500');
    });

    test('los que no llegan al mínimo van marcados, no fuera', () {
      final t = _t(minimo: 2);
      final copia = _publicar(t, _rondas());
      // Ana, Beto y Caro juegan las dos, así que nadie queda fuera... se fuerza
      // con un mínimo imposible.
      final imposible = _publicar(_t(minimo: 5), _rondas());
      expect(imposible.tabla.every((f) => f.bajoMinimo), isTrue);
      expect(copia.tabla.every((f) => !f.bajoMinimo), isTrue);
    });

    test('las jornadas se publican con NOMBRES, no ids', () {
      final t = _t(jornada: 100);
      final copia = _publicar(t, _rondas());
      expect(copia.jornadas, hasLength(2));
      expect(copia.jornadas.first.cobran.every((n) => n == n.toUpperCase()),
          isTrue, reason: 'nombres en mayúscula del fixture, no ids');
    });
  });

  group('3 · el sello que la declara copia', () {
    test('la antigüedad se dice en palabras', () {
      final copia = _publicar(_t(), _rondas(), cuando: DateTime(2026, 4, 1, 12));
      expect(copia.antiguedad(DateTime(2026, 4, 1, 12, 1)), 'hace un momento');
      expect(copia.antiguedad(DateTime(2026, 4, 1, 12, 30)), 'hace 30 minutos');
      expect(copia.antiguedad(DateTime(2026, 4, 1, 15)), 'hace 3 horas');
      expect(copia.antiguedad(DateTime(2026, 4, 4, 12)), 'hace 3 días');
      expect(copia.antiguedad(DateTime(2026, 6, 1, 12)), 'hace 2 meses');
    });

    test('a partir de una semana se considera rancia', () {
      // Es lo que hace visible un enlace viejo: sin esto, una tabla de marzo
      // parecería la de hoy.
      final copia = _publicar(_t(), _rondas(), cuando: DateTime(2026, 4, 1));
      expect(copia.estaRancia(DateTime(2026, 4, 5)), isFalse);
      expect(copia.estaRancia(DateTime(2026, 4, 9)), isTrue);
    });

    test('la fecha viaja en el JSON: sin ella no habría sello', () {
      final copia = _publicar(_t(), _rondas());
      final vuelta = TorneoPublicado.fromJson(
          'tok_x', Map<String, dynamic>.from(copia.toJson()));
      expect(vuelta.publicadoEn, copia.publicadoEn);
    });
  });

  group('4 · el viaje completo', () {
    test('lo publicado se lee igual', () {
      final copia = _publicar(_t(entrada: 500, jornada: 100), _rondas());
      final vuelta = TorneoPublicado.fromJson(
          'tok_x', Map<String, dynamic>.from(copia.toJson()));
      expect(vuelta.nombre, copia.nombre);
      expect(vuelta.tabla.length, copia.tabla.length);
      expect(vuelta.tabla.first.nombre, copia.tabla.first.nombre);
      expect(vuelta.boteTotal, copia.boteTotal);
      expect(vuelta.jornadas.length, copia.jornadas.length);
      expect(vuelta.cerrado, copia.cerrado);
    });

    test('un documento incompleto no revienta al leerse', () {
      // Un enlace de una versión anterior de la app existe. Que la pantalla del
      // invitado se caiga es la peor primera impresión posible.
      final v = TorneoPublicado.fromJson('tok', const {});
      expect(v.nombre, 'Torneo');
      expect(v.tabla, isEmpty);
      expect(v.boteTotal, 0);
    });
  });

  group('6 · el cuadro publicado: nombres, y el por qué', () {
    Torneo cuadro() => Torneo(
          id: 't1',
          nombre: 'Match Play CGM',
          formato: FormatoDeTorneo.eliminacion,
          fuente: FuenteDeRondas.marcadas,
          metodo: MetodoDePuntuacion.dinero,
          participantes: const [ana, beto],
        );

    RoundResult marcada() => RoundResult(
          roundId: 'ronda_secreta_1',
          roundName: 'Sábado 7',
          courseName: 'Los Encinos',
          playedAt: DateTime(2026, 3, 7),
          holesPlayed: 18,
          playerIds: const [ana, beto],
          playerNames: const {ana: 'ANA', beto: 'BETO'},
          balances: const {ana: 300, beto: -300},
          pairBalances: const {},
          grossByPlayer: const {},
          netByPlayer: const {},
          stablefordByPlayer: const {},
          bettingGroupIds: const [],
          torneoIds: const ['t1'],
        );

    TorneoPublicado publicada() {
      final t = cuadro();
      final rondas = [marcada()];
      final tabla = tablaDe(t, rondas);
      return TorneoPublicado.desde(
        token: 'tok_x',
        ownerUid: 'uid_org',
        torneo: t,
        tabla: tabla,
        bote: boteDe(t, tabla),
        jornadas: botesPorJornada(t, tabla),
        cuando: DateTime(2026, 4, 1, 12),
        llave: llaveDe(t, rondas),
      );
    }

    test('el cuadro va con NOMBRES, nunca con ids', () {
      final copia = publicada();
      expect(copia.llave, hasLength(1));
      expect(copia.llave.first.a, 'ANA');
      expect(copia.llave.first.ganador, 'ANA');
      expect(copia.campeon, 'ANA');
      final json = copia.toJson().toString();
      for (final prohibido in [ana, beto]) {
        expect(json.contains(prohibido), isFalse, reason: prohibido);
      }
    });

    test('el roundId NO se publica; el nombre de la ronda sí', () {
      // Al invitado el id no le sirve —no puede abrir esa ronda— y publicarlo
      // enseñaría la forma interna. El nombre es el "por qué pasó quien pasó".
      final json = publicada().toJson().toString();
      expect(json.contains('ronda_secreta_1'), isFalse);
      expect(json.contains('Sábado 7'), isTrue);
      expect(publicada().llave.first.enRonda, 'Sábado 7');
    });

    test('una liga no publica cuadro ni campeón', () {
      final claves = _publicar(_t(), _rondas()).toJson().keys.toSet();
      expect(claves, isNot(contains('llave')));
      expect(claves, isNot(contains('campeon')));
    });

    test('la copia del cuadro sobrevive el JSON', () {
      final ida = TorneoPublicado.fromJson('tok_x', publicada().toJson());
      expect(ida.campeon, 'ANA');
      expect(ida.llave, hasLength(1));
      expect(ida.llave.first.faseNombre, 'Final');
      expect(ida.llave.first.cuando, DateTime(2026, 3, 7));
    });

    test('un empate publicado se ve como empate, sin ganador inventado', () {
      final t = cuadro();
      final rondas = [
        RoundResult(
          roundId: 'r1',
          roundName: 'Sábado 7',
          courseName: 'C',
          playedAt: DateTime(2026, 3, 7),
          holesPlayed: 18,
          playerIds: const [ana, beto],
          playerNames: const {ana: 'ANA', beto: 'BETO'},
          balances: const {ana: 0, beto: 0},
          pairBalances: const {},
          grossByPlayer: const {},
          netByPlayer: const {},
          stablefordByPlayer: const {},
          bettingGroupIds: const [],
          torneoIds: const ['t1'],
        ),
      ];
      final tabla = tablaDe(t, rondas);
      final copia = TorneoPublicado.desde(
        token: 'tok_x',
        ownerUid: 'uid_org',
        torneo: t,
        tabla: tabla,
        bote: boteDe(t, tabla),
        jornadas: botesPorJornada(t, tabla),
        cuando: DateTime(2026, 4, 1),
        llave: llaveDe(t, rondas),
      );
      expect(copia.llave.first.empatado, isTrue);
      expect(copia.llave.first.ganador, isNull);
      expect(copia.campeon, isNull);
    });

    test('el que pasa con bye tiene nombre, no un guion', () {
      // No aparece en ninguna fila de la tabla —no jugó— así que sin el mapa de
      // nombres saldría como '—' en el cuadro publicado.
      final t = Torneo(
        id: 't1',
        nombre: 'Match Play',
        formato: FormatoDeTorneo.eliminacion,
        fuente: FuenteDeRondas.marcadas,
        metodo: MetodoDePuntuacion.dinero,
        participantes: const [ana, beto, caro],
      );
      final tabla = tablaDe(t, const []);
      final copia = TorneoPublicado.desde(
        token: 'tok_x',
        ownerUid: 'uid_org',
        torneo: t,
        tabla: tabla,
        bote: boteDe(t, tabla),
        jornadas: botesPorJornada(t, tabla),
        cuando: DateTime(2026, 4, 1),
        llave: llaveDe(t, const []),
        nombres: const {ana: 'ANA', beto: 'BETO', caro: 'CARO'},
      );
      final bye = copia.llave.where((p) => p.bye).toList();
      expect(bye, isNotEmpty);
      expect(bye.first.ganador, isNotNull);
      expect(bye.first.ganador, isNot('—'));
    });
  });

  group('5 · el token identifica el documento, no va dentro', () {
    test('revocar es borrar: el token no lleva estado', () {
      // Si el token llevara un "activo: true" dentro, revocar sería un update y
      // un fallo de escritura dejaría el enlace vivo. Borrando, no hay estado
      // intermedio posible.
      final json = _publicar(_t(), _rondas()).toJson();
      expect(json.containsKey('token'), isFalse);
      expect(json.containsKey('activo'), isFalse);
      expect(json.containsKey('revocado'), isFalse);
    });

    test('el ownerUid SÍ va: la regla de Firestore lo necesita', () {
      // Es lo que impide que otro actualice o borre el enlace.
      expect(_publicar(_t(), _rondas()).toJson()['ownerUid'], 'uid_org');
    });
  });
}
