// ─────────────────────────────────────────────────────────────────────────────
// LA PANTALLA DE LA CASA CLUB, DEL LADO DEL ORGANIZADOR
//
// Hasta este punto el leaderboard proyectable no tenía ORIGEN: la pantalla
// existía, la regla existía, el modelo existía, y nadie escribía el documento.
// Es la forma que más veces se ha repetido en este proyecto —el dato existe, la
// capa siguiente no lo lee— y aquí le tocaba al último eslabón.
//
// La prueba que más vale de este archivo es la del TOKEN. Ver el grupo 1.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/patrocinio.dart';
import 'package:golf_bet_master/models/round_result.dart';
import 'package:golf_bet_master/models/torneo.dart';
import 'package:golf_bet_master/services/tele_service.dart';

const ana = 'pid_a', beto = 'pid_b';
const nombres = {ana: 'Luis Herrera', beto: 'Ana Ruiz'};

RoundResult _ronda() => RoundResult(
      roundId: 'r1',
      roundName: 'Sábado',
      courseName: 'Los Encinos',
      playedAt: DateTime(2026, 8, 29),
      holesPlayed: 18,
      playerIds: const [ana, beto],
      playerNames: nombres,
      balances: const {ana: 300, beto: -300},
      pairBalances: const {},
      grossByPlayer: const {},
      netByPlayer: const {ana: 70, beto: 74},
      stablefordByPlayer: const {},
      torneoIds: const ['t1'],
    );

Torneo _torneo({
  String? tokenTele,
  DateTime? teleDesde,
  bool cerrado = false,
  List<String> participantes = const [ana, beto],
  InventarioProyectado inventario = const InventarioProyectado(),
}) =>
    Torneo(
      id: 't1',
      nombre: 'Copa de Primavera',
      fuente: FuenteDeRondas.marcadas,
      metodo: MetodoDePuntuacion.posicion,
      participantes: participantes,
      bote: const BoteConfig(entrada: 500),
      tokenCompartido: 'tor_abc',
      tokenTele: tokenTele,
      teleDesde: teleDesde,
      cerrado: cerrado,
      inventario: inventario,
    );

TablaDelTorneo _tabla(Torneo t) => tablaDe(t, [_ronda()], nombres: nombres);

void main() {
  group('1 · el token de la tele NO es el del enlace', () {
    // ── La prueba más importante del archivo ─────────────────────────────────
    //
    // La idea inicial era reutilizar el token: "una dirección para la gente y
    // otra para la tele". Está mal, y solo se ve mirando la regla:
    //
    //   sharedTorneos → allow get: if request.auth != null
    //
    // O sea, CUALQUIER cuenta con el token lee el bote y los balances; no se
    // comprueba que estés invitado. El token ES la credencial.
    //
    // Y el token de la tele es el string menos secreto del sistema: se proyecta
    // en una pared ocho horas y se le manda al del club. Con uno solo, quien
    // leyera la URL de la pantalla y se registrara gratis leería el dinero.
    test('CLAVE: vive en otro espacio de nombres', () {
      final tele = Tele.nuevoToken();
      expect(tele.startsWith('tv_'), isTrue);
      expect(tele.startsWith('tor_'), isFalse);
    });

    test('y encender la pantalla no reutiliza el del torneo', () {
      final t = _torneo();
      expect(t.tokenCompartido, 'tor_abc');
      expect(t.tokenTele, isNull,
          reason: 'compartir por WhatsApp no enciende ninguna pared');
      expect(Tele.nuevoToken(), isNot('tor_abc'));
    });

    test('el enlace apunta a /tv/, no a /torneo/', () {
      expect(Tele.nuevoToken().startsWith('tv_'), isTrue);
    });
  });

  group('2 · encender es una decisión; refrescar no la toma', () {
    test('sin haber encendido, cerrar una ronda no proyecta nada', () {
      // Cerrar una ronda no puede empezar a emitir en una pared del club por su
      // cuenta. Es el mismo criterio que ya rige el enlace: republicar refresca
      // lo que hay, crear es del organizador.
      expect(Tele.debeRefrescar(_torneo()), isFalse);
    });

    test('con token pero apagada, tampoco', () {
      // El caso del apagado: el token sobrevive para no tener que dar otro, así
      // que el token SOLO no puede significar "encendida".
      expect(Tele.debeRefrescar(_torneo(tokenTele: 'tv_x')), isFalse);
    });

    test('encendida sí se refresca', () {
      expect(
          Tele.debeRefrescar(
              _torneo(tokenTele: 'tv_x', teleDesde: DateTime(2026, 8, 29))),
          isTrue);
    });

    test('un torneo cerrado ya no se refresca', () {
      // Una instantánea final es final, igual que con el enlace.
      expect(
          Tele.debeRefrescar(_torneo(
              tokenTele: 'tv_x',
              teleDesde: DateTime(2026, 8, 29),
              cerrado: true)),
          isFalse);
    });

    test('y publicar sin encender devuelve "apagada" sin tocar nada', () async {
      final t = _torneo();
      final (r, token) = await Tele.publicar(
          ownerUid: 'uid', torneo: t, tabla: _tabla(t), cuando: DateTime(2026));
      expect(r, ResultadoTele.apagada);
      expect(token, isNull);
    });
  });

  group('3 · sin inscritos no se proyecta', () {
    test('ni siquiera encendiéndola a mano', () async {
      // Mismo criterio que el botón de compartir. En una pared es peor: la
      // tabla mal hecha se ve desde la barra.
      final t = _torneo(participantes: const []);
      final tabla = _tabla(t);
      expect(tabla.sinListaDeParticipantes, isTrue);
      final (r, token) = await Tele.publicar(
          ownerUid: 'uid',
          torneo: t,
          tabla: tabla,
          cuando: DateTime(2026),
          encender: true);
      expect(r, ResultadoTele.sinParticipantes);
      expect(token, isNull);
    });
  });

  group('4 · la instantánea que se construye', () {
    Torneo conPatrocinio() => _torneo(
        tokenTele: 'tv_x',
        teleDesde: DateTime(2026, 8, 29),
        inventario: const InventarioProyectado(
          cabecera: PiezaDePatrocinio(
              etiqueta: 'Patrocinador oficial',
              titular: 'Eleva cada gran ronda'),
          pie: [PiezaDePatrocinio(etiqueta: 'Socio', titular: 'Marca A')],
          segundosDeRotacion: 20,
        ));

    test('lleva el inventario que pactó el organizador', () {
      final t = conPatrocinio();
      final copia = Tele.instantanea(
          token: 'tv_x',
          ownerUid: 'uid',
          torneo: t,
          tabla: _tabla(t),
          cuando: DateTime(2026, 8, 29));
      expect(copia.inventario.cabecera?.titular, 'Eleva cada gran ronda');
      expect(copia.inventario.pie.length, 1);
      expect(copia.inventario.segundosDeRotacion, 20);
    });

    test('y NI UN IMPORTE, aunque el torneo tenga bote', () {
      // El contrapeso de todo lo anterior. Esta instantánea se lee sin sesión.
      final t = conPatrocinio();
      expect(t.bote.entrada, 500);
      final json = Tele.instantanea(
              token: 'tv_x',
              ownerUid: 'uid',
              torneo: t,
              tabla: _tabla(t),
              cuando: DateTime(2026, 8, 29))
          .toJson()
          .toString();
      for (final prohibido in ['bote', '500', '300', ana, beto, 'r1']) {
        expect(json.contains(prohibido), isFalse, reason: prohibido);
      }
      expect(json.contains('Luis Herrera'), isTrue,
          reason: 'los nombres y los puestos SÍ: son la pantalla');
    });
  });

  group('5 · lo que el torneo guarda', () {
    test('los tres campos viajan y vuelven', () {
      final t = _torneo(
          tokenTele: 'tv_x',
          teleDesde: DateTime(2026, 8, 29, 14),
          inventario: const InventarioProyectado(
              lateral: PiezaDePatrocinio(
                  etiqueta: 'Marca', titular: 'Precisión')));
      final ida = Torneo.fromJson(t.toJson());
      expect(ida.tokenTele, 'tv_x');
      expect(ida.teleDesde, DateTime(2026, 8, 29, 14));
      expect(ida.inventario.lateral?.titular, 'Precisión');
    });

    test('un torneo de antes se lee igual: los campos son aditivos', () {
      // Nada de lo guardado hasta hoy tiene estas claves.
      final viejo = Torneo.fromJson({
        'id': 't9',
        'nombre': 'Copa vieja',
        'fuente': FuenteDeRondas.marcadas.name,
        'metodo': MetodoDePuntuacion.posicion.name,
      });
      expect(viejo.tokenTele, isNull);
      expect(viejo.teleDesde, isNull);
      expect(viejo.inventario.vacio, isTrue);
    });

    test('sin patrocinio no engorda el documento del torneo', () {
      expect(_torneo().toJson().containsKey('inventario'), isFalse);
    });

    test('CLAVE: apagar conserva el token', () {
      // Se le dio al del club. Obligarle a pedir otro cada vez que se apaga no
      // es apagar, es romper — la misma decisión que ya rige el enlace.
      final encendida =
          _torneo(tokenTele: 'tv_x', teleDesde: DateTime(2026, 8, 29));
      final apagada = encendida.copyWith(apagarTele: true);
      expect(apagada.teleDesde, isNull);
      expect(apagada.tokenTele, 'tv_x');
      expect(Tele.debeRefrescar(apagada), isFalse);
    });

    test('y "dejar de compartir" se lleva los DOS tokens', () {
      // Apagar el enlace tiene que apagar la superficie más expuesta de las
      // dos; si no, la frase del botón sería mentira.
      final encendida =
          _torneo(tokenTele: 'tv_x', teleDesde: DateTime(2026, 8, 29));
      final revocada = encendida.copyWith(limpiarCompartido: true);
      expect(revocada.tokenCompartido, isNull);
      expect(revocada.tokenTele, isNull);
      expect(revocada.teleDesde, isNull);
    });
  });
}
