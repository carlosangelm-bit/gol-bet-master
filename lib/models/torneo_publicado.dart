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

class TorneoPublicado {
  /// El token del enlace. Es el id del documento.
  final String token;

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

  final List<FilaPublicada> tabla;

  /// El bote final: lo que hay y cómo se reparte, en texto.
  final double boteTotal;
  final String? boteReparto;
  final String? boteProvisional;

  final List<JornadaPublicada> jornadas;
  final double boteJornadaEntrada;

  const TorneoPublicado({
    required this.token,
    required this.ownerUid,
    required this.nombre,
    required this.emoji,
    required this.publicadoEn,
    required this.comoSePuntua,
    required this.comoSeAcumula,
    required this.rondas,
    required this.cerrado,
    required this.tabla,
    this.boteTotal = 0,
    this.boteReparto,
    this.boteProvisional,
    this.jornadas = const [],
    this.boteJornadaEntrada = 0,
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
  }) {
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
      ownerUid: ownerUid,
      nombre: torneo.nombre,
      emoji: torneo.emoji,
      publicadoEn: cuando,
      comoSePuntua: torneo.metodo.descripcion,
      comoSeAcumula: torneo.acumulacion == Acumulacion.mejoresDeN
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
    );
  }

  Map<String, dynamic> toJson() => {
        'ownerUid': ownerUid,
        'nombre': nombre,
        'emoji': emoji,
        'publicadoEn': publicadoEn.toIso8601String(),
        'comoSePuntua': comoSePuntua,
        'comoSeAcumula': comoSeAcumula,
        'rondas': rondas,
        if (cerrado) 'cerrado': true,
        'tabla': tabla.map((f) => f.toJson()).toList(),
        if (boteTotal != 0) 'boteTotal': boteTotal,
        if (boteReparto != null) 'boteReparto': boteReparto,
        if (boteProvisional != null) 'boteProvisional': boteProvisional,
        if (jornadas.isNotEmpty)
          'jornadas': jornadas.map((j) => j.toJson()).toList(),
        if (boteJornadaEntrada != 0) 'boteJornadaEntrada': boteJornadaEntrada,
      };

  factory TorneoPublicado.fromJson(String token, Map<String, dynamic> j) =>
      TorneoPublicado(
        token: token,
        ownerUid: (j['ownerUid'] as String?) ?? '',
        nombre: (j['nombre'] as String?) ?? 'Torneo',
        emoji: (j['emoji'] as String?) ?? '🏆',
        publicadoEn:
            DateTime.tryParse((j['publicadoEn'] as String?) ?? '') ??
                DateTime(2000),
        comoSePuntua: (j['comoSePuntua'] as String?) ?? '',
        comoSeAcumula: (j['comoSeAcumula'] as String?) ?? '',
        rondas: (j['rondas'] as num?)?.toInt() ?? 0,
        cerrado: j['cerrado'] == true,
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
}
