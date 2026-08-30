// ─────────────────────────────────────────────────────────────────────────────
// ENCONTRAR LA SALIDA QUE SE PIDIÓ — y decirlo cuando no se encuentra
//
// ── El fallo: cuatro caídas encadenadas, todas en silencio ──────────────────
//
// El campo favorito guarda "la salida preferida" por NOMBRE. Al cargar el campo
// se busca ese nombre entre los tees de la API, y si no aparece:
//
//     _teeByName(name) ?? _playerTees[p.id] ?? _defaultMaleTee ?? TeeInfo.standard
//
// Cuatro `??` seguidos, ninguno con voz. El último eslabón de verdad es
// `_defaultMaleTee`, que es EL PRIMER TEE DE LA LISTA — azules en el campo de
// Carlos. Así que pedir blancas y jugar azules no daba error: daba un CR y un
// Slope de otra salida, y un diferencial plausible calculado con ellos.
//
// Es la misma familia que las siete rondas con diferencial imposible: un valor
// creíble sustituye a uno que falta, y nadie se entera hasta tres semanas
// después.
//
// ── Por qué el nombre no basta como llave ───────────────────────────────────
//
// Los nombres los pone la API y vienen como vienen: "BLANCAS", "White",
// "50715, USGA, White, Men". La app los limpia para enseñarlos, así que lo que
// el usuario ve y lo que se guarda pueden separarse — y una API que renombre un
// tee rompe la preferencia sin avisar.
//
// Los tees no traen id. Pero el CR y el Slope SÍ identifican una salida dentro
// de un campo: son justo los dos números que la distinguen. Así que se guardan
// también, y se buscan en cascada, de lo más exacto a lo más tolerante.
// ─────────────────────────────────────────────────────────────────────────────

/// Cómo se encontró la salida. Importa porque decide si hay que avisar.
enum ComoSeResolvio {
  /// Por el nombre, tal cual. Lo normal.
  porNombre,

  /// Por el nombre una vez limpiado de prefijos de la API.
  porNombreLimpio,

  /// Por su CR y su Slope: la API le cambió el nombre.
  porRating,

  /// No se encontró y se cayó al primero de la lista. **Hay que decirlo.**
  noSeEncontro,

  /// No se pidió ninguna en concreto.
  sinPreferencia,
}

/// Lo mínimo que identifica una salida. Aparte de TeeInfo y de ApiTeeBox para
/// que esto se pueda probar sin arrastrar ni el modelo de la app ni el de la
/// API.
class SalidaCandidata {
  final String nombre;
  final double courseRating;
  final int slopeRating;

  const SalidaCandidata({
    required this.nombre,
    required this.courseRating,
    required this.slopeRating,
  });
}

class SalidaResuelta {
  final SalidaCandidata? salida;
  final ComoSeResolvio como;

  /// Lo que se pidió, para poder decirlo.
  final String? pedida;

  const SalidaResuelta(this.salida, this.como, {this.pedida});

  /// Si hay que avisar al crear la ronda.
  ///
  /// Solo cuando NO se encontró. Que se resuelva por nombre limpio o por rating
  /// es correcto y no merece interrumpir a nadie: la salida es la que se pidió.
  bool get hayQueAvisar => como == ComoSeResolvio.noSeEncontro;

  /// El aviso, con lo que se pidió y lo que se va a usar.
  String get aviso {
    if (!hayQueAvisar) return '';
    final usada = salida?.nombre ?? 'la primera de la lista';
    return 'No encontré la salida "$pedida" en este campo. Se va a jugar con '
        '$usada, y el handicap se calculará con su CR y su Slope. Cámbiala en '
        'el paso de campo si no es la que quieres.';
  }
}

/// Quita de un nombre de tee lo que la API le añade: códigos y "USGA".
///
/// Misma lógica que la limpieza que usa la pantalla para enseñarlo. Está aquí
/// además de allí porque aquí se COMPARA, y comparar con una limpieza distinta
/// de la que se enseña es cómo el usuario acaba viendo un nombre que el buscador
/// no reconoce.
String limpiarNombreDeTee(String crudo) {
  final partes = crudo
      .split(',')
      .map((s) => s.trim())
      .where((s) =>
          s.isNotEmpty &&
          !RegExp(r'^\d+$').hasMatch(s) &&
          s.toUpperCase() != 'USGA')
      .toList();
  return (partes.isEmpty ? crudo : partes.join(' ')).toLowerCase();
}

/// Busca [pedida] entre [tees], en cascada.
///
/// [crPedido] y [slopePedido] son la red de seguridad: si el nombre cambió, los
/// números siguen siendo los mismos.
SalidaResuelta resolverSalida(
  List<SalidaCandidata> tees, {
  String? pedida,
  double? crPedido,
  int? slopePedido,
}) {
  if (tees.isEmpty) {
    return SalidaResuelta(null, ComoSeResolvio.noSeEncontro, pedida: pedida);
  }
  if (pedida == null || pedida.trim().isEmpty) {
    return SalidaResuelta(tees.first, ComoSeResolvio.sinPreferencia);
  }

  // 1 · El nombre, tal cual. Es lo que pasa el 99% de las veces.
  for (final t in tees) {
    if (t.nombre.toLowerCase() == pedida.toLowerCase()) {
      return SalidaResuelta(t, ComoSeResolvio.porNombre, pedida: pedida);
    }
  }

  // 2 · El nombre limpio. Caza el caso de guardar lo que se VE y buscar lo que
  //     la API MANDA, o al revés.
  final limpiaPedida = limpiarNombreDeTee(pedida);
  for (final t in tees) {
    if (limpiarNombreDeTee(t.nombre) == limpiaPedida) {
      return SalidaResuelta(t, ComoSeResolvio.porNombreLimpio, pedida: pedida);
    }
  }

  // 3 · El CR y el Slope. Si la API renombró el tee, estos no cambian.
  if (crPedido != null && slopePedido != null) {
    for (final t in tees) {
      if ((t.courseRating - crPedido).abs() < 0.05 &&
          t.slopeRating == slopePedido) {
        return SalidaResuelta(t, ComoSeResolvio.porRating, pedida: pedida);
      }
    }
  }

  // 4 · No está. Se devuelve la primera para que la ronda pueda seguir, pero
  //     marcada, porque lo que no puede pasar es que nadie se entere.
  return SalidaResuelta(tees.first, ComoSeResolvio.noSeEncontro, pedida: pedida);
}

/// Qué salida se usó en una ronda vieja, deducida de su CR y su Slope.
///
/// ── Para saber qué rondas del histórico salieron con el tee equivocado ──────
///
/// Los diferenciales de antes no guardaban el tee, pero SÍ guardan el CR y el
/// Slope con los que se calcularon — y esos dos números identifican la salida
/// dentro del campo. Así que el nombre se recupera exacto, no se adivina.
///
/// Devuelve null si no cuadra con ninguna: entonces la pantalla enseña el CR y
/// el Slope, que siguen siendo la evidencia.
String? salidaSegunRating(
  List<SalidaCandidata> tees,
  double courseRating,
  int slopeRating,
) {
  for (final t in tees) {
    if ((t.courseRating - courseRating).abs() < 0.05 &&
        t.slopeRating == slopeRating) {
      return t.nombre;
    }
  }
  return null;
}
