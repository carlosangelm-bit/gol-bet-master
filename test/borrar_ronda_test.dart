// ─────────────────────────────────────────────────────────────────────────────
// BORRAR UNA RONDA — hasta dónde llega y dónde se para
//
// Una ronda vive en cinco sitios y solo cuatro se pueden borrar desde la app. El
// quinto es el que manda: una instantánea publicada es una COPIA con fecha, y
// solo la cambia el organizador volviendo a publicar.
//
// Así que borrar una ronda de un torneo publicado dejaría la tabla del
// organizador diciendo algo que ya no existe. Es el patrón que este proyecto ya
// pagó varias veces —arreglar en un sitio y dejarlo en otro— y aquí se para en
// seco en vez de intentarlo a medias.
//
// Lo que se prueba aquí es la REGLA. El borrado en sí necesita Firestore.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/borrar_ronda.dart';
import 'package:golf_bet_master/models/torneo.dart';

Torneo _t(String id,
        {String? token, String? tele, String nombre = 'Copa de Primavera'}) =>
    Torneo(
      id: id,
      nombre: nombre,
      fuente: FuenteDeRondas.marcadas,
      metodo: MetodoDePuntuacion.posicion,
      tokenCompartido: token,
      tokenTele: tele,
    );

void main() {
  group('1 · el caso simple: no cuenta para nada', () {
    test('CLAVE: una ronda sin torneos se borra', () {
      final r = sePuedeBorrar(const [], [_t('tor_1')]);
      expect(r.si, isTrue);
      expect(r.explicacion, isEmpty);
    });

    test('y da igual cuántos torneos tenga la cuenta', () {
      expect(sePuedeBorrar(const [], []).si, isTrue);
      expect(
          sePuedeBorrar(const [], [_t('a'), _t('b', token: 'tok')]).si, isTrue);
    });
  });

  group('2 · torneos MÍOS sin publicar: también se puede', () {
    test('CLAVE: las tablas se derivan, así que se arreglan solas', () {
      // El balance y las tablas de torneo salen de roundResults, no se guardan.
      // Borrando la ronda desaparecen de las dos, y no queda nada fuera de mi
      // cuenta.
      final r = sePuedeBorrar(const ['tor_1'], [_t('tor_1')]);
      expect(r.si, isTrue);
    });

    test('con varios torneos míos sin publicar, igual', () {
      final r = sePuedeBorrar(const ['a', 'b'], [_t('a'), _t('b')]);
      expect(r.si, isTrue);
    });
  });

  group('3 · publicado: NO, y se dice por qué', () {
    test('CLAVE: con enlace de WhatsApp no se borra', () {
      // La instantánea es una copia con fecha. Solo la arregla el organizador
      // volviendo a publicar, y eso no se puede hacer desde esta pantalla.
      final r = sePuedeBorrar(const ['tor_1'], [_t('tor_1', token: 'tok_abc')]);
      expect(r.si, isFalse);
      expect(r.motivo, PorQueNo.torneoPublicado);
      expect(r.explicacion, contains('Copa de Primavera'),
          reason: 'con el nombre: "no se puede" no dice qué hacer');
      expect(r.explicacion, contains('Deja de compartir'),
          reason: 'y con la salida');
    });

    test('con la pantalla de la tele encendida, tampoco', () {
      // Es la superficie MÁS expuesta: se lee sin cuenta.
      final r = sePuedeBorrar(const ['tor_1'], [_t('tor_1', tele: 'tv_abc')]);
      expect(r.si, isFalse);
      expect(r.motivo, PorQueNo.torneoPublicado);
    });

    test('y basta con que UNO de los torneos esté publicado', () {
      final r = sePuedeBorrar(
          const ['a', 'b'], [_t('a'), _t('b', token: 'tok', nombre: 'Liga')]);
      expect(r.si, isFalse);
      expect(r.torneos, ['Liga'], reason: 'y se nombra el que lo impide');
    });
  });

  group('4 · torneos que no son míos', () {
    test('CLAVE: una ronda de un torneo ajeno no se borra desde aquí', () {
      // Borrarla dejaría la tabla del organizador con una fila que ya no
      // existe, y él no se enteraría.
      final r = sePuedeBorrar(const ['de_otro'], [_t('tor_1')]);
      expect(r.si, isFalse);
      expect(r.motivo, PorQueNo.torneoDesconocido);
    });

    test('y un torneo mío BORRADO se trata igual, a propósito', () {
      // Sin el torneo delante no se distingue "de otro" de "mío y borrado". Los
      // dos se tratan como el peor caso: suponer cuál es sería adivinar sobre
      // la tabla de alguien.
      final r = sePuedeBorrar(const ['ya_no_esta'], []);
      expect(r.si, isFalse);
      expect(r.explicacion, contains('ya no está en tu cuenta'));
    });
  });

  group('5 · los contrapesos', () {
    test('CONTRAPESO: la regla no dice que NO a todo', () {
      // Sin esto, un `si => false` fijo pasaría casi todas las de arriba y la
      // función no serviría para nada.
      expect(sePuedeBorrar(const [], []).si, isTrue);
      expect(sePuedeBorrar(const ['a'], [_t('a')]).si, isTrue);
    });

    test('CONTRAPESO: ni que SÍ a todo', () {
      expect(sePuedeBorrar(const ['a'], [_t('a', token: 'x')]).si, isFalse);
      expect(sePuedeBorrar(const ['b'], [_t('a')]).si, isFalse);
    });

    test('cada motivo trae su explicación, y son distintas', () {
      // Un motivo sin frase propia es un "no se puede" con otro nombre.
      final frases = <String>{};
      for (final m in PorQueNo.values) {
        final f = SePuedeBorrar(m, torneos: const ['X']).explicacion;
        if (m == PorQueNo.siSePuede) {
          expect(f, isEmpty);
          continue;
        }
        expect(f, isNotEmpty, reason: m.name);
        frases.add(f);
      }
      expect(frases, hasLength(PorQueNo.values.length - 1));
    });
  });
}
