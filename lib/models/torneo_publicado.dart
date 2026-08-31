// ─────────────────────────────────────────────────────────────────────────────
// TORNEO PUBLICADO — una COPIA FECHADA, nunca la fuente
//
// ══════════════════════════════════════════════════════════════════════════════
// LA REGLA "LA TABLA SE DERIVA, NUNCA SE GUARDA" NO QUEDA DEROGADA: SE PRECISA.
//
// Existía para evitar un problema concreto —que un total calculado se quede
// desfasado sin avisar— que es justo lo que pasó con el tablero de Inicio
// leyendo RoundResult viejos. Un total guardado en silencio PRETENDE ser la
// verdad.
//
// Una instantánea publicada a propósito, con sello de "actualizada hace X", no
// es eso: se declara copia. Si el enlace está rancio, se ve.
//
// Así que: LA FUENTE SIGUE SIENDO DERIVADA, lo publicado es una copia fechada, y
// NUNCA SE LEE PARA CALCULAR NADA DENTRO DE LA APP. Dentro, tablaDe() manda
// siempre. Esto solo existe para que alguien sin la app pueda ver el torneo.
// ══════════════════════════════════════════════════════════════════════════════
//
// Qué NO va aquí, y es la mitad del diseño: los RoundResult completos, los
// balances de rondas ajenas al torneo, el directorio de jugadores, el correo de
// nadie. Solo clasificación, botes y participantes. La duda se resuelve fuera:
// si dudas de si un campo entra, no entra.
//
// Eso es lo que hace segura la regla de Firestore. Es `read` sobre un documento
// que solo contiene lo que se quiso compartir, sin get() cruzados ni condiciones
// sobre users/** que alguien tenga que razonar. El criterio se cumple POR
// CONSTRUCCIÓN, no porque la regla esté bien escrita — que es mejor, porque no
// depende de que lo esté.
import 'models.dart';
import 'torneo.dart';

/// Una fila de la clasificación, aplanada para publicar.
class FilaPublicada {
  final int puesto;
  final String nombre;
  final double total;
  final int jugadas;
  final int contadas;
  final bool bajoMinimo;

  /// Lo que pone y cobra del bote final. 0 si no hay bote.
  final double aportaBote;
  final double cobraBote;

  const FilaPublicada({
    required this.puesto,
    required this.nombre,
    required this.total,
    required this.jugadas,
    required this.contadas,
    required this.bajoMinimo,
    required this.aportaBote,
    required this.cobraBote,
  });

  Map<String, dynamic> toJson() => {
        'puesto': puesto,
        // El NOMBRE, no el id: un id no le dice nada a quien mira desde fuera y
        // publicarlo enseñaría la forma interna del directorio sin necesidad.
        'nombre': nombre,
        'total': total,
        'jugadas': jugadas,
        'contadas': contadas,
        if (bajoMinimo) 'bajoMinimo': true,
        if (aportaBote != 0) 'aportaBote': aportaBote,
        if (cobraBote != 0) 'cobraBote': cobraBote,
      };

  factory FilaPublicada.fromJson(Map<String, dynamic> j) => FilaPublicada(
        puesto: (j['puesto'] as num?)?.toInt() ?? 0,
        nombre: (j['nombre'] as String?) ?? '',
        total: (j['total'] as num?)?.toDouble() ?? 0,
        jugadas: (j['jugadas'] as num?)?.toInt() ?? 0,
        contadas: (j['contadas'] as num?)?.toInt() ?? 0,
        bajoMinimo: j['bajoMinimo'] == true,
        aportaBote: (j['aportaBote'] as num?)?.toDouble() ?? 0,
        cobraBote: (j['cobraBote'] as num?)?.toDouble() ?? 0,
      );
}

/// Una jornada publicada.
class JornadaPublicada {
  final String nombreRonda;
  final DateTime fecha;
  final int jugadores;
  final double total;
  final List<String> cobran;

  const JornadaPublicada({
    required this.nombreRonda,
    required this.fecha,
    required this.jugadores,
    required this.total,
    required this.cobran,
  });

  Map<String, dynamic> toJson() => {
        'nombreRonda': nombreRonda,
        'fecha': fecha.toIso8601String(),
        'jugadores': jugadores,
        'total': total,
        'cobran': cobran,
      };

  factory JornadaPublicada.fromJson(Map<String, dynamic> j) => JornadaPublicada(
        nombreRonda: (j['nombreRonda'] as String?) ?? 'Ronda',
        fecha: DateTime.tryParse((j['fecha'] as String?) ?? '') ?? DateTime(2000),
        jugadores: (j['jugadores'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toDouble() ?? 0,
        cobran: ((j['cobran'] as List?) ?? const []).map((e) => '$e').toList(),
      );
}

/// Un partido del cuadro, aplanado para publicar.
///
/// Con NOMBRES, no ids —igual que la tabla— y con lo que sacó cada uno en la
/// ronda que lo resolvió: un resultado de partido sin sus dos cifras es un
/// veredicto sin motivo, y eso hace discutir el número en vez de la regla.
///
/// Lo que NO lleva: el roundId. Al invitado no le sirve —no puede abrir esa
/// ronda— y publicarlo enseñaría la forma interna sin necesidad. El nombre de la
/// ronda y la fecha sí, porque son el "por qué".
class PartidoPublicado {
  final int ronda;

  /// Dónde está dentro de su fase, contando desde arriba.
  ///
  /// Es lo único que le faltaba a la instantánea para que la vista de invitado
  /// pueda dibujar el ÁRBOL y no una lista: el partido i de la fase n lo
  /// alimentan el 2i y el 2i+1 de la n-1, y sin la posición eso no se puede
  /// reconstruir. Es un número, no un id: la regla de qué no va en la
  /// instantánea sigue intacta.
  final int posicion;

  final String faseNombre;
  final String? a;
  final String? b;
  final String? ganador;
  final bool bye;
  final bool empatado;
  final String? enRonda;
  final DateTime? cuando;
  final double? medidaA;
  final double? medidaB;

  const PartidoPublicado({
    required this.ronda,
    this.posicion = 0,
    required this.faseNombre,
    this.a,
    this.b,
    this.ganador,
    this.bye = false,
    this.empatado = false,
    this.enRonda,
    this.cuando,
    this.medidaA,
    this.medidaB,
  });

  Map<String, dynamic> toJson() => {
        'ronda': ronda,
        if (posicion != 0) 'posicion': posicion,
        'faseNombre': faseNombre,
        if (a != null) 'a': a,
        if (b != null) 'b': b,
        if (ganador != null) 'ganador': ganador,
        if (bye) 'bye': true,
        if (empatado) 'empatado': true,
        if (enRonda != null) 'enRonda': enRonda,
        if (cuando != null) 'cuando': cuando!.toIso8601String(),
        if (medidaA != null) 'medidaA': medidaA,
        if (medidaB != null) 'medidaB': medidaB,
      };

  factory PartidoPublicado.fromJson(Map<String, dynamic> j) => PartidoPublicado(
        ronda: (j['ronda'] as num?)?.toInt() ?? 0,
        posicion: (j['posicion'] as num?)?.toInt() ?? 0,
        faseNombre: (j['faseNombre'] as String?) ?? '',
        a: j['a'] as String?,
        b: j['b'] as String?,
        ganador: j['ganador'] as String?,
        bye: j['bye'] == true,
        empatado: j['empatado'] == true,
        enRonda: j['enRonda'] as String?,
        cuando: DateTime.tryParse((j['cuando'] as String?) ?? ''),
        medidaA: (j['medidaA'] as num?)?.toDouble(),
        medidaB: (j['medidaB'] as num?)?.toDouble(),
      );
}

class TorneoPublicado {
  /// El token del enlace. Es el id del documento.
  final String token;

  /// El id del torneo del organizador.
  ///
  /// ── Por qué SÍ entra, cuando los ids de jugador y el roundId no ───────────
  ///
  /// Lo que se excluye de la instantánea son los ids que identifican PERSONAS y
  /// RONDAS: no le sirven a quien mira y enseñan la forma interna. Este es el id
  /// del propio objeto que se está compartiendo, y el token ya lo identifica
  /// públicamente igual de bien.
  ///
  /// Y hace falta: quien sigue el torneo tiene que publicarle resultados, y la
  /// tabla del organizador los consulta por SU id. Sin esto se usaba el token
  /// como identidad, y entonces lo escrito y lo consultado no coincidían.
  ///
  /// Vacío en las instantáneas publicadas antes de que este campo existiera. Se
  /// trata como "todavía no se puede seguir" y se dice, en vez de crear una
  /// referencia que no funcionaría.
  final String torneoId;

  /// Quién publicó. Lo usa la regla de Firestore para saber quién puede
  /// actualizar y revocar; no se enseña.
  final String ownerUid;

  final String nombre;
  final String emoji;

  /// Cuándo se publicó esta copia. **El sello que la declara copia.**
  ///
  /// Es lo que separa esto de un total guardado en silencio: si el enlace está
  /// rancio, se ve en la pantalla.
  final DateTime publicadoEn;

  /// Las reglas, en texto ya resuelto. No se publica el objeto Torneo entero
  /// para no exponer ids de grupos ni de rondas.
  final String comoSePuntua;
  final String comoSeAcumula;

  final int rondas;
  final bool cerrado;

  /// Si el enlace está encendido.
  ///
  /// ── Por qué un interruptor y no borrar ────────────────────────────────────
  ///
  /// El enlace de un torneo es ESTABLE toda su vida: nadie reenvía por WhatsApp
  /// el mismo enlace cada semana de una temporada. Y revocar borrando el
  /// documento obligaba a generar otro token al volver a publicar, o sea a
  /// reenviarlo.
  ///
  /// Apagado NO significa "el documento sigue ahí con todo dentro": significa que
  /// el documento se queda VACÍO —solo el dueño y esta bandera— así que apagar de
  /// verdad deja de servir los nombres y las cifras. Lo que no se destruye es el
  /// TOKEN, ni el torneo del organizador. Encender vuelve a publicar la
  /// instantánea entera.
  ///
  /// Es la diferencia entre "dejo de compartir esto" y "rompo el enlace que
  /// mandé a doce personas".
  final bool activo;

  final List<FilaPublicada> tabla;

  /// El bote final: lo que hay y cómo se reparte, en texto.
  final double boteTotal;
  final String? boteReparto;
  final String? boteProvisional;

  final List<JornadaPublicada> jornadas;
  final double boteJornadaEntrada;

  /// El cuadro, si el torneo es de eliminación. Vacío si es una liga.
  ///
  /// Se publica porque sin él el enlace de un torneo de eliminación enseñaría
  /// una tabla acumulada donde el invitado espera ver a quién le toca — cierto,
  /// pero no lo que fue a buscar.
  final List<PartidoPublicado> llave;

  /// Quién ganó, por nombre. Null mientras la final no se juegue.
  final String? campeon;

  /// La ventaja que fija el torneo, y el campo si lo fija. Null = no lo fija.
  ///
  /// ── Por qué SÍ entran en la instantánea ───────────────────────────────────
  ///
  /// Son CONFIGURACIÓN DEL TORNEO, no datos de personas: qué ventaja se juega y
  /// en qué campo. Cero riesgo de exponer a nadie, y la regla de qué no entra
  /// —ids de jugador, roundId, resultados ajenos, el directorio— se respeta tal
  /// cual está. [comoSePuntua] ya viajaba por el mismo motivo.
  ///
  /// Y hacen falta: sin ellos, quien sigue el torneo y crea su ronda vuelve a
  /// elegir la ventaja, que es justo lo que el torneo tiene que fijar para que
  /// dos jornadas sean comparables.
  ///
  /// Lo que NO viaja aquí, y es deliberado: la PLANTILLA. Vive en el espacio del
  /// organizador y sus reglas por duelo llevan ids de jugador, así que
  /// publicarla rompería la regla. El seguidor hereda con quién juega, con qué
  /// ventaja y dónde; qué se apuesta lo elige él, que además es lo suyo.
  final VentajaDeTorneo? ventaja;
  final CourseInfo? campo;

  /// Cómo puntúa el torneo, en máquina y no solo en prosa.
  ///
  /// [comoSePuntua] ya lo decía en texto para que se lea. Esto es el mismo dato
  /// para poder DECIDIR con él: si el torneo puntúa por score, una ronda suya
  /// puede empezar sin configurar apuestas —la medida es el score— y entonces al
  /// que la crea no hay que preguntarle nada. Si puntúa por dinero, las apuestas
  /// SON la medida y arrancar sin ellas le daría cero a todo el mundo.
  ///
  /// Es el método EFECTIVO, el mismo que se publica en prosa: un cuadro con "por
  /// posición" se resuelve por dinero, y las dos cosas tienen que decir lo mismo.
  ///
  /// Null en instantáneas anteriores al campo. Se trata como "hace falta
  /// preguntar", que es lo prudente: preguntar de más cuesta un paso, arrancar de
  /// menos cuesta una tabla en blanco.
  final MetodoDePuntuacion? metodo;

  const TorneoPublicado({
    required this.token,
    this.torneoId = '',
    required this.ownerUid,
    required this.nombre,
    required this.emoji,
    required this.publicadoEn,
    required this.comoSePuntua,
    required this.comoSeAcumula,
    required this.rondas,
    required this.cerrado,
    this.activo = true,
    required this.tabla,
    this.boteTotal = 0,
    this.boteReparto,
    this.boteProvisional,
    this.jornadas = const [],
    this.boteJornadaEntrada = 0,
    this.llave = const [],
    this.campeon,
    this.ventaja,
    this.campo,
    this.metodo,
  });

  /// Construye la copia desde la tabla YA CALCULADA.
  ///
  /// Recibe lo derivado; no vuelve a calcular nada. Un segundo cálculo aquí
  /// podría discrepar del que se ve en la app, y entonces el enlace enseñaría
  /// otra cosa que la pantalla.
  factory TorneoPublicado.desde({
    required String token,
    required String ownerUid,
    required Torneo torneo,
    required TablaDelTorneo tabla,
    required BoteDelTorneo bote,
    required List<BoteDeJornada> jornadas,
    required DateTime cuando,
    LlaveDelTorneo? llave,
    Map<String, String> nombres = const {},
  }) {
    // Los nombres para el cuadro. La tabla ya los trae resueltos, así que sale
    // de ahí; lo que pase [nombres] manda, para el que tiene bye y no aparece en
    // ninguna fila. Nunca se cae al id: publicarlo enseñaría la forma interna.
    final nombreDe = <String, String>{
      for (final f in [...tabla.filas, ...tabla.bajoMinimo]) f.playerId: f.nombre,
      ...nombres,
    };
    String? conNombre(String? pid) => pid == null ? null : (nombreDe[pid] ?? '—');
    double aporta(String pid) => bote.lineas
        .where((l) => l.playerId == pid)
        .fold(0.0, (s, l) => s + l.aporta);
    double cobra(String pid) => bote.lineas
        .where((l) => l.playerId == pid)
        .fold(0.0, (s, l) => s + l.cobra);

    FilaPublicada fila(FilaDelTorneo f) => FilaPublicada(
          puesto: f.puesto,
          nombre: f.nombre,
          total: f.total,
          jugadas: f.jugadas,
          contadas: f.contadas,
          bajoMinimo: f.bajoMinimo,
          aportaBote: aporta(f.playerId),
          cobraBote: cobra(f.playerId),
        );

    return TorneoPublicado(
      token: token,
      torneoId: torneo.id,
      ownerUid: ownerUid,
      nombre: torneo.nombre,
      emoji: torneo.emoji,
      publicadoEn: cuando,
      // El método EFECTIVO, no el guardado: un cuadro con "por posición" se
      // resuelve por dinero, y el enlace no puede decir otra cosa que la app.
      comoSePuntua: metodoEfectivo(torneo).descripcion,
      comoSeAcumula: torneo.formato == FormatoDeTorneo.eliminacion
          ? 'Eliminación directa: los dos del partido juegan la misma ronda y el '
              'que pierde queda fuera.'
          : torneo.acumulacion == Acumulacion.mejoresDeN
              ? 'Solo cuentan las ${torneo.mejoresN} mejores de cada uno.'
              : 'Suman todas las rondas.',
      rondas: tabla.rondas,
      cerrado: torneo.cerrado,
      tabla: [
        ...tabla.filas.map(fila),
        ...tabla.bajoMinimo.map(fila),
      ],
      boteTotal: bote.total,
      boteReparto: bote.hayBote ? torneo.bote.reparto.label : null,
      boteProvisional: bote.provisional,
      jornadas: jornadas
          .map((j) => JornadaPublicada(
                nombreRonda: j.nombreRonda,
                fecha: j.fecha,
                jugadores: j.jugadores,
                total: j.total,
                cobran:
                    j.cobran.keys.map((k) => j.nombres[k] ?? '—').toList(),
              ))
          .toList(),
      boteJornadaEntrada: torneo.bote.entradaPorJornada,
      llave: [
        for (final nivel in llave?.rondas ?? const <List<Enfrentamiento>>[])
          for (final e in nivel)
            PartidoPublicado(
              ronda: e.ronda,
              posicion: e.posicion,
              faseNombre: nombreDeRondaDeLlave(nivel.length),
              a: conNombre(e.a),
              b: conNombre(e.b),
              ganador: conNombre(e.ganador),
              bye: e.bye,
              empatado: e.empatado,
              enRonda: e.roundName,
              cuando: e.cuando,
              medidaA: e.medidaA,
              medidaB: e.medidaB,
            ),
      ],
      campeon: conNombre(llave?.campeon),
      ventaja: torneo.ventaja,
      campo: torneo.campo,
      metodo: metodoEfectivo(torneo),
    );
  }

  Map<String, dynamic> toJson() => {
        'ownerUid': ownerUid,
        if (torneoId.isNotEmpty) 'torneoId': torneoId,
        'nombre': nombre,
        'emoji': emoji,
        'publicadoEn': publicadoEn.toIso8601String(),
        'comoSePuntua': comoSePuntua,
        'comoSeAcumula': comoSeAcumula,
        'rondas': rondas,
        if (cerrado) 'cerrado': true,
        // Solo cuando está apagado: un enlace vivo no engorda el documento.
        if (!activo) 'activo': false,
        'tabla': tabla.map((f) => f.toJson()).toList(),
        if (boteTotal != 0) 'boteTotal': boteTotal,
        if (boteReparto != null) 'boteReparto': boteReparto,
        if (boteProvisional != null) 'boteProvisional': boteProvisional,
        if (jornadas.isNotEmpty)
          'jornadas': jornadas.map((j) => j.toJson()).toList(),
        if (boteJornadaEntrada != 0) 'boteJornadaEntrada': boteJornadaEntrada,
        if (llave.isNotEmpty) 'llave': llave.map((e) => e.toJson()).toList(),
        if (campeon != null) 'campeon': campeon,
        if (ventaja != null) 'ventaja': ventaja!.name,
        if (campo != null) 'campo': campo!.toJson(),
        if (metodo != null) 'metodo': metodo!.name,
      };

  factory TorneoPublicado.fromJson(String token, Map<String, dynamic> j) =>
      TorneoPublicado(
        token: token,
        torneoId: (j['torneoId'] as String?) ?? '',
        ownerUid: (j['ownerUid'] as String?) ?? '',
        nombre: (j['nombre'] as String?) ?? 'Torneo',
        emoji: (j['emoji'] as String?) ?? 'trofeo',
        publicadoEn:
            DateTime.tryParse((j['publicadoEn'] as String?) ?? '') ??
                DateTime(2000),
        comoSePuntua: (j['comoSePuntua'] as String?) ?? '',
        comoSeAcumula: (j['comoSeAcumula'] as String?) ?? '',
        rondas: (j['rondas'] as num?)?.toInt() ?? 0,
        cerrado: j['cerrado'] == true,
        // Ausente = encendido: los enlaces publicados antes de que esto
        // existiera siguen sirviendo.
        activo: j['activo'] != false,
        tabla: ((j['tabla'] as List?) ?? const [])
            .map((f) => FilaPublicada.fromJson(Map<String, dynamic>.from(f as Map)))
            .toList(),
        boteTotal: (j['boteTotal'] as num?)?.toDouble() ?? 0,
        boteReparto: j['boteReparto'] as String?,
        boteProvisional: j['boteProvisional'] as String?,
        jornadas: ((j['jornadas'] as List?) ?? const [])
            .map((x) =>
                JornadaPublicada.fromJson(Map<String, dynamic>.from(x as Map)))
            .toList(),
        boteJornadaEntrada:
            (j['boteJornadaEntrada'] as num?)?.toDouble() ?? 0,
        llave: ((j['llave'] as List?) ?? const [])
            .map((x) =>
                PartidoPublicado.fromJson(Map<String, dynamic>.from(x as Map)))
            .toList(),
        campeon: j['campeon'] as String?,
        ventaja: j['ventaja'] == null
            ? null
            : VentajaDeTorneo.values.firstWhere((v) => v.name == j['ventaja'],
                orElse: () => VentajaDeTorneo.handicap),
        campo: j['campo'] is Map
            ? CourseInfo.fromJson(Map<String, dynamic>.from(j['campo'] as Map))
            : null,
        metodo: j['metodo'] == null
            ? null
            : MetodoDePuntuacion.values.firstWhere((m) => m.name == j['metodo'],
                orElse: () => MetodoDePuntuacion.dinero),
      );

  /// Cuánto hace que se publicó, en palabras.
  ///
  /// Es lo que hace visible un enlace rancio, así que se dice siempre y sin
  /// suavizarlo.
  String antiguedad(DateTime ahora) {
    final d = ahora.difference(publicadoEn);
    if (d.inMinutes < 2) return 'hace un momento';
    if (d.inHours < 1) return 'hace ${d.inMinutes} minutos';
    if (d.inHours < 24) return 'hace ${d.inHours} hora${d.inHours == 1 ? '' : 's'}';
    final dias = d.inDays;
    if (dias < 30) return 'hace $dias día${dias == 1 ? '' : 's'}';
    final meses = dias ~/ 30;
    return 'hace $meses mes${meses == 1 ? '' : 'es'}';
  }

  /// True si la copia lleva tanto tiempo que conviene decirlo más alto.
  bool estaRancia(DateTime ahora) =>
      ahora.difference(publicadoEn).inDays >= 7;

  /// EL PADRÓN, como nombres. Los inscritos del torneo, jueguen o no.
  ///
  /// Verificado antes de construir nada sobre él: una liga con inscritos y CERO
  /// rondas publica una fila por inscrito con su nombre real —[tablaDe] los
  /// añade y el nombre sale del directorio del organizador, que el publicador le
  /// pasa entero—. Y un cuadro los trae además en la llave. Así que el padrón
  /// está aquí desde antes de que nadie juegue, que es justo cuando hace falta
  /// para crear la primera ronda.
  ///
  /// Sale de la tabla Y de la llave porque el que tiene bye puede no aparecer en
  /// ninguna fila. El '—' se filtra: es lo que se enseña cuando un nombre no se
  /// pudo resolver, y no es una persona a la que se pueda invitar.
  ///
  /// Esta era la lista que la pantalla de invitado calculaba por su cuenta para
  /// "¿Cuál eres tú?". Vive aquí para que el padrón que se elige y el padrón con
  /// el que se juega sean el mismo — dos definiciones habrían sido la cuarta vez
  /// que dos caminos al mismo sitio divergen.
  List<String> get padron {
    final out = <String>{};
    for (final f in tabla) {
      if (f.nombre.isNotEmpty && f.nombre != '—') out.add(f.nombre);
    }
    for (final p in llave) {
      for (final n in [p.a, p.b]) {
        if (n != null && n.isNotEmpty && n != '—') out.add(n);
      }
    }
    return out.toList();
  }
}
