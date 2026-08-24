// ─────────────────────────────────────────────────────────────────────────────
// IMPORTAR JUGADORES — pegando, no con un archivo
//
// ── POR QUÉ PEGAR Y NO ELEGIR UN ARCHIVO ────────────────────────────────────
//
// Carlos dijo "Excel". Las opciones eran .xlsx, CSV o pegar. Pegar gana por tres
// razones, y ninguna es que sea más fácil de programar:
//
//   1 · MENOS PASOS PARA EL USUARIO. Con archivo: guardar como CSV, buscarlo en
//       Archivos, elegirlo. Pegando: seleccionar las celdas y Cmd+C. En un
//       teléfono, "buscar el archivo" es el paso que hace abandonar.
//   2 · EXCEL YA PONE EL FORMATO BUENO EN EL PORTAPAPELES: columnas separadas
//       por TABULADOR. Y el tabulador no aparece dentro de un nombre, mientras
//       que la coma sí —"Pérez, Juan"— así que un CSV es MÁS ambiguo que lo que
//       Excel copia.
//   3 · FUNCIONA IGUAL EN WEB Y EN IOS, y sin dependencia nueva. Un selector de
//       archivos son dos implementaciones y configuración por plataforma.
//
// Se aceptan tabulador, coma y punto y coma, así que un CSV pegado también entra.
//
// ── QUÉ HACE CON QUIEN YA EXISTE ────────────────────────────────────────────
//
// Se REUTILIZA, nunca se crea otra ficha. Acabamos de arreglar que el mismo id no
// se duplique al crear un jugador en el asistente; crear fichas nuevas aquí
// reproduciría "dos filas con el mismo nombre" treinta veces de golpe.
//
// Se identifica por NOMBRE NORMALIZADO —sin acentos, sin mayúsculas, sin espacios
// de más— porque es lo único que trae una hoja de cálculo. Es frágil y se dice:
// el resumen enseña a quién va a reutilizar ANTES de importar, para que quien
// tenga dos Carlos lo vea y lo arregle a mano.
//
// ── Y NUNCA A MEDIAS EN SILENCIO ────────────────────────────────────────────
//
// El parseo NO importa nada: devuelve qué entraría, qué no y por qué. Confirmar
// es un segundo paso. Un archivo de treinta filas con dos malas tiene que decir
// cuáles son las dos antes de tocar nada.
// ─────────────────────────────────────────────────────────────────────────────

/// Una fila que se puede importar.
class JugadorImportado {
  /// El número de línea del texto pegado, para poder señalarla.
  final int linea;
  final String nombre;
  final double handicap;

  /// El id del jugador del directorio que ya es esta persona, si lo hay.
  ///
  /// Con id se REUTILIZA; sin id se crea.
  final String? idExistente;

  const JugadorImportado({
    required this.linea,
    required this.nombre,
    required this.handicap,
    this.idExistente,
  });

  bool get yaEstaba => idExistente != null;
}

/// Una fila que no se puede importar, y por qué.
class FilaRechazada {
  final int linea;

  /// El texto tal cual, para que el usuario la reconozca.
  final String texto;

  /// El motivo, ya redactado.
  final String motivo;

  const FilaRechazada(
      {required this.linea, required this.texto, required this.motivo});
}

/// Lo que el texto pegado produciría.
class ResultadoDeImportacion {
  /// Los que se crearían: no están en el directorio.
  final List<JugadorImportado> nuevos;

  /// Los que se reutilizarían: ya están.
  final List<JugadorImportado> existentes;

  final List<FilaRechazada> rechazadas;

  const ResultadoDeImportacion({
    this.nuevos = const [],
    this.existentes = const [],
    this.rechazadas = const [],
  });

  /// Todo lo que entraría, en el orden del texto.
  List<JugadorImportado> get todos =>
      [...nuevos, ...existentes]..sort((a, b) => a.linea.compareTo(b.linea));

  bool get hayAlgo => nuevos.isNotEmpty || existentes.isNotEmpty;

  /// El resumen en una línea, para la pantalla.
  String get resumen {
    final partes = <String>[];
    if (nuevos.isNotEmpty) {
      partes.add('${nuevos.length} nuevo${nuevos.length == 1 ? '' : 's'}');
    }
    if (existentes.isNotEmpty) {
      partes.add('${existentes.length} ya '
          '${existentes.length == 1 ? 'estaba' : 'estaban'}');
    }
    if (rechazadas.isNotEmpty) {
      partes.add('${rechazadas.length} sin leer');
    }
    return partes.isEmpty ? 'Nada que importar' : partes.join(' · ');
  }
}

/// Un nombre comparable: sin acentos, sin mayúsculas, sin espacios de más.
///
/// Lo mínimo para que "José Pérez", "jose perez" y "  JOSÉ   PÉREZ " sean la
/// misma persona. No intenta más: dos personas que se llaman igual son un
/// problema que la app no puede resolver sola, y por eso se enseña antes.
String nombreComparable(String s) {
  const con = 'áàäâãéèëêíìïîóòöôõúùüûñçÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇ';
  const sin = 'aaaaaeeeeiiiiooooouuuuncAAAAAEEEEIIIIOOOOOUUUUNC';
  var out = s.trim().toLowerCase();
  final b = StringBuffer();
  for (final ch in out.split('')) {
    final i = con.indexOf(ch);
    b.write(i >= 0 ? sin[i] : ch);
  }
  out = b.toString();
  return out.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Lee el texto pegado.
///
/// [existentes] es nombre comparable → id del directorio. Lo que coincida se
/// reutiliza.
///
/// NO importa nada: devuelve qué pasaría. Confirmar es otro paso.
ResultadoDeImportacion parsearJugadores(
  String texto, {
  Map<String, String> existentes = const {},
}) {
  final nuevos = <JugadorImportado>[];
  final yaEstan = <JugadorImportado>[];
  final malas = <FilaRechazada>[];
  // Repetidos DENTRO del texto: pegar la misma columna dos veces pasa, y meter a
  // alguien dos veces en el mismo torneo no es lo que nadie quiere.
  final vistos = <String>{};

  final lineas = texto.split(RegExp(r'\r?\n'));
  for (var i = 0; i < lineas.length; i++) {
    final linea = i + 1;
    final cruda = lineas[i];
    if (cruda.trim().isEmpty) continue;

    // Tabulador primero: es lo que Excel pone en el portapapeles, y no aparece
    // dentro de un nombre. La coma sí —"Pérez, Juan"— así que solo se usa si no
    // hay tabuladores.
    final sep = cruda.contains('\t')
        ? '\t'
        : cruda.contains(';')
            ? ';'
            : ',';
    final campos = cruda.split(sep).map((c) => c.trim()).toList();
    final nombre = campos.isEmpty ? '' : campos.first;

    if (nombre.isEmpty) {
      malas.add(FilaRechazada(
          linea: linea, texto: cruda.trim(), motivo: 'Sin nombre'));
      continue;
    }
    // Una cabecera pegada por error —"Nombre  Handicap"— se salta sin contarla
    // como fallo: es lo que pasa al copiar la tabla entera.
    if (linea == 1 &&
        const ['nombre', 'jugador', 'name', 'participante']
            .contains(nombreComparable(nombre))) {
      continue;
    }

    final clave = nombreComparable(nombre);
    if (!vistos.add(clave)) {
      malas.add(FilaRechazada(
          linea: linea,
          texto: cruda.trim(),
          motivo: 'Repetido en la lista: "$nombre" ya sale antes'));
      continue;
    }

    // El handicap: la segunda columna si la hay. Sin ella se toma 0 y se dice en
    // el resumen —no se rechaza la fila—: un nombre sin handicap sigue siendo
    // alguien que juega, y el handicap se pone después.
    var hcp = 0.0;
    if (campos.length > 1 && campos[1].isNotEmpty) {
      // La coma decimal es lo normal en español: "12,5".
      final crudo = campos[1].replaceAll(',', '.');
      final n = double.tryParse(crudo);
      if (n == null) {
        malas.add(FilaRechazada(
            linea: linea,
            texto: cruda.trim(),
            motivo: '"${campos[1]}" no es un handicap'));
        continue;
      }
      // Un handicap fuera de rango es un dato mal pegado —una columna de otra
      // cosa— y colarlo estropearía todos los netos de la ronda.
      if (n < -10 || n > 54) {
        malas.add(FilaRechazada(
            linea: linea,
            texto: cruda.trim(),
            motivo: 'Handicap $n fuera de rango (−10 a 54)'));
        continue;
      }
      hcp = n;
    }

    final id = existentes[clave];
    final j = JugadorImportado(
        linea: linea, nombre: nombre, handicap: hcp, idExistente: id);
    (id == null ? nuevos : yaEstan).add(j);
  }

  return ResultadoDeImportacion(
      nuevos: nuevos, existentes: yaEstan, rechazadas: malas);
}
