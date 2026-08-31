// ─────────────────────────────────────────────────────────────────────────────
// EQUIPOS Y «THRU» EN VIVO
//
// «La inmensa mayoría de los torneos recreativos se juegan por equipos de 4.»
//
// Y el criterio que manda sobre todos los demás: «Copa de Primavera, Liga por
// Score y Match Play Anual son individuales, y llevamos semanas verificándolos.
// Si el cambio los rompe, es peor que no hacerlo.»
//
// Por eso el grupo 1 de este fichero no prueba los equipos: prueba que SIN
// equipos no cambia nada. Es el que decide si esta entrega vale.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/leaderboard_publico.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/shotgun.dart';
import 'package:golf_bet_master/models/torneo.dart';
import 'package:golf_bet_master/screens/organizador/publicador_de_thru.dart';

CourseInfo _campo() => CourseInfo(
      name: 'Los Encinos',
      holes: List.generate(
          18,
          (i) => CourseHole(
              hole: i + 1,
              par: const {3, 7, 12, 16}.contains(i + 1) ? 3 : 4,
              strokeIndex: i + 1)),
    );

List<String> _padron(int n) => [for (var i = 1; i <= n; i++) 'j$i'];

Map<String, Player> _porId(int n) => {
      for (var i = 1; i <= n; i++)
        'j$i': Player(id: 'j$i', name: 'Jugador $i'),
    };

PlanDeShotgun _plan({int gente = 88}) =>
    planDeShotgun(padron: _padron(gente), campo: _campo(), tamano: 4);

GrupoDelTorneo _grupo(String nombre, {int ultimo = 0, int llevados = 0}) =>
    GrupoDelTorneo(
      roundId: 'r_$nombre',
      nombre: nombre,
      jugadores: const ['Ana', 'Beto'],
      hoyosCapturados: llevados,
      ultimoHoyo: ultimo,
      totalHoles: 18,
      cerrada: false,
    );

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // 1 · LO INDIVIDUAL NO SE MUEVE
  //
  // El criterio 5, y el primero por algo. Todo lo nuevo es opcional y apagado
  // por defecto; si algo de aquí falla, la entrega no vale.
  // ───────────────────────────────────────────────────────────────────────────
  group('1 · los torneos individuales siguen igual', () {
    test('CLAVE: un torneo nace INDIVIDUAL y sin equipos', () {
      final t = Torneo(id: 't1', nombre: 'Copa de Primavera');
      expect(t.porEquipos, isFalse);
      expect(t.equipos, isEmpty);
      // Y no engorda su documento con lo nuevo.
      final j = t.toJson();
      expect(j.containsKey('porEquipos'), isFalse);
      expect(j.containsKey('equipos'), isFalse);
    });

    test('CLAVE: un torneo guardado ANTES de esto sigue siendo individual', () {
      // El caso real: Copa de Primavera existe en Firestore sin estas claves.
      final viejo = Torneo.fromJson({
        'id': 't1',
        'nombre': 'Copa de Primavera',
        'participantes': ['ana', 'beto'],
      });
      expect(viejo.porEquipos, isFalse);
      expect(viejo.equipos, isEmpty);
    });

    test('CLAVE: las rondas del reparto se llaman por su SALIDA, como antes',
        () {
      // Sin equipos, `rondasDelPlan` no cambia ni un nombre ni un id.
      final rondas = rondasDelPlan(
          plan: _plan(),
          torneoId: 't1',
          campo: _campo(),
          porId: _porId(88),
          cuando: DateTime(2026, 8, 31));
      expect(rondas.first.name, 'Hoyo 1');
      expect(rondas.map((r) => r.name), contains('Hoyo 3B'));
      expect(rondas.first.id, 't1_s1');
    });

    test('CLAVE: y la instantánea individual no lleva Thru', () {
      final lb = LeaderboardPublico.desde(
        token: 'tv_a',
        ownerUid: 'u',
        torneo: Torneo(id: 't1', nombre: 'Copa', participantes: const ['ana']),
        tabla: tablaDe(
            Torneo(id: 't1', nombre: 'Copa', participantes: const ['ana']),
            const []),
        cuando: DateTime(2026, 8, 31),
      );
      expect(lb.thru, isEmpty);
      expect(lb.toJson().containsKey('thru'), isFalse);
    });

    test('CLAVE: el publicador no publica nada en un torneo individual', () {
      // Es la guarda que impide que el temporizador escriba en la pared de un
      // torneo que no tiene equipos.
      final t = Torneo(id: 't1', nombre: 'Copa', tokenTele: 'tv_a');
      expect(thruDeLosGrupos(t, [_grupo('Hoyo 1', ultimo: 5, llevados: 5)],
              DateTime(2026, 8, 31)),
          isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('2 · los equipos salen del reparto, con número y nombre', () {
    test('CLAVE: uno por grupo con salida, numerados desde 1', () {
      final equipos = equiposDelPlan(_plan());
      expect(equipos.length, 22);
      expect(equipos.first.numero, 1);
      expect(equipos.last.numero, 22);
      // Y cada uno con la salida de su grupo: el equipo ES el grupo de salida.
      expect(equipos[2].salida, 'Hoyo 3A');
      expect(equipos[3].salida, 'Hoyo 3B');
    });

    test('CLAVE: sin nombre se queda con su número, a dos cifras', () {
      final equipos = equiposDelPlan(_plan());
      expect(equipos[6].etiqueta, 'Equipo 07',
          reason: 'dos cifras: en una lista de 22, el 7 y el 17 se alinean');
      expect(equipos[6].id, 'e07');
    });

    test('CLAVE: con nombre, las dos cosas', () {
      final equipos = equiposDelPlan(_plan(), nombresPuestos: {7: 'Sierra'});
      expect(equipos[6].etiqueta, 'Equipo 07 · Sierra');
      // El id NO cambia al renombrar: el equipo 7 sigue siendo el 7.
      expect(equipos[6].id, 'e07');
    });

    test('CLAVE: y el nombre se queda con el NÚMERO al volver a repartir', () {
      // Cambiar el tamaño de grupo cambia quién está en cada equipo. El nombre
      // se queda con el número, que es lo que el equipo reconoce.
      final otro = planDeShotgun(
          padron: _padron(66), campo: _campo(), tamano: 3);
      final equipos = equiposDelPlan(otro, nombresPuestos: {7: 'Sierra'});
      expect(equipos[6].nombre, 'Sierra');
      expect(equipos[6].miembros.length, 3, reason: 'otra gente, mismo nombre');
    });

    test('CONTRAPESO: un grupo sin salida no llega a ser equipo', () {
      // 93 en grupos de 4 son 24 grupos y solo 22 salidas.
      final equipos = equiposDelPlan(_plan(gente: 93));
      expect(equipos.length, 22);
      expect(equipos.every((e) => e.miembros.isNotEmpty), isTrue);
    });

    test('CLAVE: las rondas llevan el equipo Y la salida', () {
      // El jugador busca su equipo; el organizador canta la salida. Y es lo
      // que permite emparejar el Thru sin ids de persona.
      final plan = _plan();
      final rondas = rondasDelPlan(
        plan: plan,
        torneoId: 't1',
        campo: _campo(),
        porId: _porId(88),
        cuando: DateTime(2026, 8, 31),
        equipos: equiposDelPlan(plan, nombresPuestos: {1: 'Sierra'}),
      );
      expect(rondas.first.name, 'Equipo 01 · Sierra · Hoyo 1');
      expect(rondas[3].name, 'Equipo 04 · Hoyo 3B');
      // Los ids NO cambian: siguen saliendo de la salida, así que volver a
      // crear sigue actualizando en vez de duplicar.
      expect(rondas.first.id, 't1_s1');
    });

    test('los equipos sobreviven al viaje por Firestore', () {
      final t = Torneo(id: 't1', nombre: 'Copa').copyWith(
          porEquipos: true,
          equipos: equiposDelPlan(_plan(), nombresPuestos: {7: 'Sierra'}));
      final vuelta = Torneo.fromJson(t.toJson());
      expect(vuelta.porEquipos, isTrue);
      expect(vuelta.equipos.length, 22);
      expect(vuelta.equipos[6].nombre, 'Sierra');
      // El séptimo equipo sale del hoyo 6: las salidas van 1, 2, 3A, 3B, 4,
      // 5, 6… así que el número del equipo y el del hoyo dejan de coincidir en
      // cuanto aparece el primer par 3. Es justo lo que hace falta que no se
      // confunda al cantar salidas.
      expect(vuelta.equipos[6].salida, 'Hoyo 6');
      expect(vuelta.equipos[7].salida, 'Hoyo 7A');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 3 · EL «THRU» EN VIVO
  //
  // Lo que se descartó y vuelve. La objeción de «la pared no tiene sesión»
  // estaba mal planteada: leaderboards/{token} ya se lee sin sesión. Lo único
  // que cambia es cuándo se reescribe.
  // ───────────────────────────────────────────────────────────────────────────
  group('3 · el Thru dice por dónde van, y cuándo se supo', () {
    Torneo conEquipos() => Torneo(id: 't1', nombre: 'Copa', tokenTele: 'tv_a')
        .copyWith(porEquipos: true, equipos: equiposDelPlan(_plan()));

    test('CLAVE: se empareja por SALIDA, no por posición en la lista', () {
      // Cruzar por posición funciona el primer día y se tuerce en cuanto un
      // grupo se cierra antes que otro y el orden cambia.
      final mapa = thruDeLosGrupos(
          conEquipos(),
          [
            _grupo('Equipo 04 · Hoyo 3B', ultimo: 12, llevados: 10),
            _grupo('Equipo 01 · Hoyo 1', ultimo: 5, llevados: 5),
          ],
          DateTime(2026, 8, 31, 11));
      expect(mapa['e04']?.hoyo, 12);
      expect(mapa['e01']?.hoyo, 5);
    });

    test('CLAVE: el HOYO y los HOYOS LLEVADOS son cosas distintas', () {
      // Con salida en el 7, el catorceavo hoyo jugado es el 3. El contador dice
      // cuánto llevan; el hoyo dice dónde están.
      final mapa = thruDeLosGrupos(
          conEquipos(),
          [_grupo('Equipo 01 · Hoyo 1', ultimo: 3, llevados: 14)],
          DateTime(2026, 8, 31, 11));
      expect(mapa['e01']?.hoyo, 3);
      expect(mapa['e01']?.llevados, 14);
      expect(mapa['e01']?.etiqueta, '3');
    });

    test('CLAVE: F al terminar, y guion si no ha empezado', () {
      final cero = DateTime(2026);
      final fin =
          ThruDeEquipo(hoyo: 18, llevados: 18, total: 18, cuando: cero);
      expect(fin.etiqueta, 'F');
      expect(fin.termino, isTrue);
      final sinEmpezar =
          ThruDeEquipo(hoyo: 0, llevados: 0, total: 18, cuando: cero);
      expect(sinEmpezar.etiqueta, '—');
    });

    test('CLAVE: un Thru de hace dos horas CADUCA', () {
      // Era el motivo exacto por el que esto se había descartado: un "va por el
      // 12" viejo presentado como actual es peor que no decir nada.
      final ahora = DateTime(2026, 8, 31, 13);
      final reciente =
          ThruDeEquipo(hoyo: 12, llevados: 12, total: 18, cuando: ahora);
      final viejo = ThruDeEquipo(
          hoyo: 12,
          llevados: 12,
          total: 18,
          cuando: ahora.subtract(const Duration(hours: 2)));
      expect(reciente.vigente(ahora), isTrue);
      expect(viejo.vigente(ahora), isFalse);
      // Y el límite: media hora es lo que tarda un grupo en dos hoyos.
      expect(
          ThruDeEquipo(
                  hoyo: 12,
                  llevados: 12,
                  total: 18,
                  cuando: ahora.subtract(const Duration(minutes: 29)))
              .vigente(ahora),
          isTrue);
    });

    test('CLAVE: la fila encuentra su Thru por el número del equipo', () {
      final lb = LeaderboardPublico(
        token: 'tv_a',
        ownerUid: 'u',
        nombre: 'Copa',
        emoji: 'trofeo',
        publicadoEn: DateTime(2026, 8, 31),
        comoSePuntua: 'Por score neto',
        rondas: 1,
        tabla: const [
          FilaProyectada(
              puesto: 1, nombre: 'Equipo 07 · Sierra', jugadas: 1, medida: 71),
          FilaProyectada(puesto: 2, nombre: 'Equipo 12', jugadas: 1, medida: 74),
        ],
        thru: {
          'e07': ThruDeEquipo(
              hoyo: 14,
              llevados: 14,
              total: 18,
              cuando: DateTime(2026, 8, 31, 12)),
        },
      );
      final ahora = DateTime(2026, 8, 31, 12, 5);
      expect(lb.thruDe('Equipo 07 · Sierra', ahora)?.hoyo, 14);
      expect(lb.thruDe('Equipo 12', ahora), isNull,
          reason: 'sin dato no se inventa uno');
      // Y con el nombre cambiado sigue encontrándolo: une el NÚMERO.
      expect(lb.thruDe('Equipo 07 · Otro nombre', ahora)?.hoyo, 14);
    });

    test('CLAVE: y el Thru viaja en la instantánea', () {
      final lb = LeaderboardPublico(
        token: 'tv_a',
        ownerUid: 'u',
        nombre: 'Copa',
        emoji: 'trofeo',
        publicadoEn: DateTime(2026, 8, 31),
        comoSePuntua: 'Por score neto',
        rondas: 1,
        tabla: const [],
        thru: {
          'e07': ThruDeEquipo(
              hoyo: 14, llevados: 14, total: 18, cuando: DateTime(2026, 8, 31)),
        },
      );
      final vuelta = LeaderboardPublico.fromJson('tv_a', lb.toJson());
      expect(vuelta.thru['e07']?.hoyo, 14);
      expect(vuelta.thru['e07']?.llevados, 14);
      expect(vuelta.thru['e07']?.cuando, DateTime(2026, 8, 31));
    });

    test('la cadencia es un minuto, y está escrita en un sitio', () {
      // Con el número delante: 22 equipos en UNA escritura por minuto son 300
      // en cinco horas de torneo, con un solo escritor y ninguna regla nueva.
      expect(cadenciaDelThru, const Duration(seconds: 60));
    });
  });
}
