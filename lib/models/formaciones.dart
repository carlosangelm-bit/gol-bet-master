// ─────────────────────────────────────────────────────────────────────────────
// FORMACIONES — el atajo que arma los lados, no un motor nuevo
//
// High and Low y Pair vs Field YA se pueden jugar: BetSide.playerIds admite ≥1
// sin exigir simetría, así que 2 contra 3 funciona, y el best ball existe. Lo
// que faltaba es no tener que arrastrar cinco jugadores a mano para conseguirlo.
//
// Así que esto NO toca cálculo. Es una función pura que dice, dados los
// jugadores, qué dos lados salen — y el panel de equipos sigue siendo editable
// después: es un atajo, no un carril.
//
// El catálogo es declarativo por lo mismo que el de tipos de apuesta: cada
// formación es una fila con sus tamaños admitidos y su motivo, y el motivo se
// GENERA del conjunto. Ocho veces en esta app una lista literal se quedó vieja
// cuando el enum creció.
// ─────────────────────────────────────────────────────────────────────────────
import 'models.dart';

/// Cómo se arman los dos lados de una ronda por equipos.
enum Formacion {
  /// El reparto alternado de siempre, para tocarlo a mano. Es lo que había.
  manual,

  /// Los handicaps más bajos contra los más altos.
  highAndLow,

  /// Una pareja fija contra todos los demás.
  parejaVsResto,

  /// Una pareja base contra CADA pareja posible del resto.
  ///
  /// Con cinco salen tres enfrentamientos simultáneos, y es la primera formación
  /// que produce más de uno. No es lo mismo que [parejaVsResto]: allí los tres
  /// rivales son un solo lado con su mejor bola; aquí se cruzan de dos en dos y
  /// cada cruce es una apuesta.
  parejaBaseVsCampo,
}

class ReglasDeFormacion {
  final String icon;
  final String label;
  final String descripcion;

  /// Con cuántos jugadores tiene sentido. null = con cualquiera.
  final Set<int>? jugadoresAdmitidos;

  /// Por qué no con menos, y por qué no con más. Dos motivos porque son dos
  /// razones distintas.
  final String? sinEseNumeroPocos;
  final String? sinEseNumeroMuchos;

  /// El criterio con el que se decide, para decirlo EN PANTALLA.
  ///
  /// Un atajo que reparte a la gente en silencio deja la sospecha de que lo hizo
  /// mal. Dicho el criterio, la discusión es sobre el criterio y no sobre el
  /// reparto.
  final String? comoSeDecide;

  const ReglasDeFormacion({
    required this.icon,
    required this.label,
    required this.descripcion,
    this.jugadoresAdmitidos,
    this.sinEseNumeroPocos,
    this.sinEseNumeroMuchos,
    this.comoSeDecide,
  });
}

extension FormacionInfo on Formacion {
  ReglasDeFormacion get reglas => switch (this) {
        Formacion.manual => const ReglasDeFormacion(
            icon: '👥',
            label: 'Por equipos',
            descripcion: '2 lados · 1 enfrentamiento. Los armas tú.',
          ),
        Formacion.highAndLow => const ReglasDeFormacion(
            icon: '⚖️',
            label: 'High and Low',
            // El matiz del manual, dicho aquí: sin él la primera reacción a un
            // 2 contra 3 es que está desequilibrado, y no lo está tanto.
            descripcion:
                'Los handicaps más bajos contra los más altos, best ball, '
                'equipos fijos toda la ronda.\n\n'
                'Con cinco sale 2 contra 3, y desequilibra menos de lo que '
                'parece: el lado de tres necesita más intentos para sacar su '
                'mejor bola, y eso compensa la diferencia de nivel.',
            jugadoresAdmitidos: {4, 5, 6},
            sinEseNumeroPocos:
                'Con tres o menos no hay dos mitades que separar: el lado bajo '
                'se queda en una persona y eso ya es otro formato —una pareja '
                'contra uno—.',
            sinEseNumeroMuchos:
                'Con siete o más el lado alto acumula tantas bolas que el best '
                'ball deja de compensar: gana casi siempre.',
            comoSeDecide:
                'Se ordena por handicap y se parte por la mitad; el lado bajo '
                'se queda con la mitad de abajo. Con dos al mismo índice en la '
                'frontera pasa el que va antes en la lista de jugadores.',
          ),
        Formacion.parejaBaseVsCampo => const ReglasDeFormacion(
            icon: '🎲',
            label: 'Pareja base contra el campo',
            // La asimetría se explica AQUÍ y se llama formato, no defecto.
            descripcion:
                'La pareja base juega contra cada pareja posible del resto: con '
                'cinco son tres enfrentamientos a la vez, best ball en cada uno.'
                '\n\n'
                'La exposición es asimétrica A PROPÓSITO: la pareja base juega '
                'los tres y cada rival solo dos, así que gana más y pierde más. '
                'Eso no es un desequilibrio que haya que corregir bajando '
                'importes: es el formato, y es de lo que va.',
            jugadoresAdmitidos: {5},
            sinEseNumeroPocos:
                'Con cuatro solo hay una pareja posible en el resto, así que '
                'sale un 2 contra 2 normal —eso ya lo hacen las formaciones de '
                'arriba—.',
            sinEseNumeroMuchos:
                'Con seis el resto da seis parejas, o sea seis apuestas a la '
                'vez: la pareja base jugaría seis y cada rival dos, y eso deja '
                'de ser una ronda de golf.',
            comoSeDecide:
                'Se propone la pareja de handicap combinado más bajo. Tócala '
                'para cambiarla: la pareja base se elige a mano y no rota, así '
                'que si la queréis a suertes, sorteadla vosotros y ponedla aquí.',
          ),
        Formacion.parejaVsResto => const ReglasDeFormacion(
            icon: '🎯',
            label: 'Pair vs Field',
            descripcion:
                'Una pareja fija contra todos los demás, sin rotación en toda '
                'la ronda. Best ball por lado.\n\n'
                'Si gana la pareja, lo ganado se parte entre dos y lo pagan '
                'todos los del otro lado: por eso es la apuesta más agresiva '
                'del manual.',
            jugadoresAdmitidos: {3, 4, 5, 6},
            sinEseNumeroPocos:
                'Con dos jugadores no hay pareja contra nadie: es un duelo.',
            sinEseNumeroMuchos:
                'Con siete o más el resto tiene tantas bolas que la pareja no '
                'gana un hoyo ni jugando bien.',
            comoSeDecide:
                'Se propone la pareja de handicap combinado más bajo, que es lo '
                'que sugiere el manual. Tócala para cambiarla: la pareja se '
                'elige a mano y no rota.',
          ),
      };

  /// Por qué esta formación no vale con [jugadores], si no vale.
  ///
  /// El prefijo se GENERA del conjunto admitido, así que ampliar los tamaños no
  /// deja un texto hablando de otro número. Es la misma función que atenúa los
  /// tipos de apuesta, con la misma forma.
  String? motivoNoDisponible(int jugadores) {
    final admitidos = reglas.jugadoresAdmitidos;
    if (admitidos == null || admitidos.contains(jugadores)) return null;

    final orden = admitidos.toList()..sort();
    final cuales = orden.length == 1
        ? '${orden.first}'
        : '${orden.take(orden.length - 1).join(', ')} o ${orden.last}';
    final detalle = jugadores < orden.first
        ? reglas.sinEseNumeroPocos
        : reglas.sinEseNumeroMuchos;

    return '${reglas.label} se juega con $cuales jugadores, y esta ronda tiene '
        '$jugadores.${detalle == null ? '' : ' $detalle'}';
  }

  /// Cómo quedarían los lados, en una línea, para verlo antes de elegir.
  String reparto(int jugadores) {
    if (motivoNoDisponible(jugadores) != null) return '';
    return switch (this) {
      Formacion.manual => '2 lados · 1 enfrentamiento.',
      Formacion.highAndLow =>
        '${jugadores ~/ 2} contra ${jugadores - jugadores ~/ 2}, por handicap.',
      Formacion.parejaVsResto => '2 contra ${jugadores - 2}.',
      Formacion.parejaBaseVsCampo =>
        '${_crucesDelResto(jugadores - 2)} enfrentamientos a la vez.',
    };
  }
}

/// El nombre de un lado, hecho con los nombres de quien juega: "CAV+CAM".
///
/// Existe porque "Equipo A" sirve para un 2 contra 2 y no sirve para tres
/// enfrentamientos con la misma pareja base: tres apuestas llamadas "Equipo A vs
/// Equipo B" son indistinguibles, y hay que poder editar la tercera.
///
/// [nombres] es id → nombre completo; se usa el primero de pila, que es como se
/// nombra a la gente en el resto de la app.
String nombreDeLado(List<String> ids, Map<String, String> nombres) {
  if (ids.isEmpty) return '—';
  return ids
      .map((id) => (nombres[id] ?? id).split(' ').first)
      .join('+');
}

/// El enfrentamiento entero: "CAV+CAM vs AAM+RICH".
String nombreDeEnfrentamiento(
        List<String> a, List<String> b, Map<String, String> nombres) =>
    '${nombreDeLado(a, nombres)} vs ${nombreDeLado(b, nombres)}';

/// Clave estable de un enfrentamiento entre dos lados.
///
/// Los ids de cada lado ordenados, y los dos lados ordenados entre sí, para que
/// dé igual quién sea A y quién sea B. Es lo que permite guardar un importe por
/// enfrentamiento sin que reordenar la siembra se lo adjudique a otro.
String claveDeEnfrentamiento(List<String> a, List<String> b) {
  final la = ([...a]..sort()).join(',');
  final lb = ([...b]..sort()).join(',');
  return ([la, lb]..sort()).join('|');
}

/// Cuántas parejas salen de [n] jugadores. Solo para redactar el reparto.
int _crucesDelResto(int n) => n < 2 ? 0 : n * (n - 1) ~/ 2;

/// TODOS los enfrentamientos que arma [f], en orden.
///
/// Casi todas las formaciones dan uno —dos lados y una apuesta— pero
/// [Formacion.parejaBaseVsCampo] da tres, y por eso el primitivo es una LISTA.
/// [armarFormacion] delega aquí y devuelve el primero, que es lo que consume el
/// panel de dos equipos.
///
/// Lista vacía si la formación no aplica a este número de jugadores.
List<(List<String>, List<String>)> enfrentamientosDe(
  Formacion f,
  List<Player> jugadores, {
  List<String> parejaBase = const [],
}) {
  if (f.motivoNoDisponible(jugadores.length) != null) return const [];

  if (f != Formacion.parejaBaseVsCampo) {
    final uno = _dosLados(f, jugadores, parejaBase: parejaBase);
    return uno == null ? const [] : [uno];
  }

  // La pareja base, y el resto en orden de handicap.
  final (base, resto) =
      _dosLados(Formacion.parejaVsResto, jugadores, parejaBase: parejaBase)!;

  // Cada pareja del resto es un enfrentamiento. El orden es estable —índices
  // crecientes sobre el resto ya ordenado— así que rearmar da lo mismo.
  return [
    for (var i = 0; i < resto.length; i++)
      for (var j = i + 1; j < resto.length; j++)
        ([...base], [resto[i], resto[j]]),
  ];
}

/// La pareja base y sus rivales, DEDUCIDOS de unos módulos ya montados.
///
/// Se deriva en vez de guardarse, y eso vale doble: la pantalla de captura puede
/// decir quién juega contra quién sin un campo nuevo en la ronda, y funciona
/// también con las tres apuestas montadas A MANO —que es como este formato ya se
/// podía jugar antes de existir el atajo—.
///
/// El criterio: dos o más módulos de 2 contra 2 que comparten un lado idéntico.
/// Ese lado repetido es la pareja base. Devuelve null si no hay tal patrón.
({List<String> base, List<List<String>> rivales})? parejaBaseDe(
    List<BetModuleInstance> modulos) {
  String clave(List<String> l) => ([...l]..sort()).join('|');

  // Cuántas veces aparece cada lado de dos, y contra quién.
  final apariciones = <String, List<List<String>>>{};
  final ladoDe = <String, List<String>>{};
  for (final m in modulos) {
    final s = m.sides;
    if (s == null || s.length != 2) continue;
    if (s[0].playerIds.length != 2 || s[1].playerIds.length != 2) continue;
    for (final par in [(s[0], s[1]), (s[1], s[0])]) {
      final k = clave(par.$1.playerIds);
      // La PRIMERA vez que se ve, no la última: así el orden en que se enseña
      // la pareja no depende de cómo estuviera escrito el último módulo. Con
      // las apuestas montadas a mano los lados vienen en cualquier orden.
      ladoDe.putIfAbsent(k, () => par.$1.playerIds);
      (apariciones[k] ??= []).add(par.$2.playerIds);
    }
  }

  // El lado que más se repite, y solo si se repite. Empate a dos candidatos:
  // gana el que más rivales distintos tenga; si siguen iguales, no se elige uno
  // al azar —se devuelve null y la pantalla no dice nada, que es mejor que
  // decir algo falso—.
  final repetidos = apariciones.entries.where((e) => e.value.length >= 2).toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));
  if (repetidos.isEmpty) return null;
  if (repetidos.length > 1 &&
      repetidos[0].value.length == repetidos[1].value.length) {
    return null;
  }
  return (base: ladoDe[repetidos.first.key]!, rivales: repetidos.first.value);
}

/// Los dos lados que arma [f] con estos [jugadores].
///
/// Devuelve (lado A, lado B) con A = el lado "bajo" o la pareja. null si la
/// formación no aplica a este número de jugadores, para que la pantalla no tenga
/// que repetir la comprobación.
///
/// ── El handicap que usa, y por qué importa decirlo ──────────────────────────
///
/// El REGISTRADO, que es el único que existe cuando se arman los equipos: el
/// paso de Ventaja va después de Compiten. Consecuencia real: cambiar el
/// handicap más tarde NO rearma los lados. Por eso la pantalla ofrece rearmar en
/// vez de hacerlo sola —rearmar solo movería a la gente de equipo sin avisar—.
///
/// ── El empate de handicap en la frontera ────────────────────────────────────
///
/// Se rompe por el ORDEN DE LA LISTA, que es estable, reproducible y visible: el
/// usuario ve ese orden en la pantalla anterior. Las alternativas —alfabético,
/// sorteo— son igual de arbitrarias y menos predecibles, y un sorteo además da
/// un reparto distinto cada vez que se toca el botón.
(List<String>, List<String>)? armarFormacion(
  Formacion f,
  List<Player> jugadores, {
  /// La pareja base de [Formacion.parejaVsResto]. Vacía = se propone la de
  /// handicap combinado más bajo.
  List<String> parejaBase = const [],
}) {
  // Con varios enfrentamientos devuelve el PRIMERO: es lo que el panel de dos
  // equipos puede enseñar, y con la pareja base en el lado A —que es la que hay
  // que poder tocar—.
  final todos = enfrentamientosDe(f, jugadores, parejaBase: parejaBase);
  return todos.isEmpty ? null : todos.first;
}

(List<String>, List<String>)? _dosLados(
  Formacion f,
  List<Player> jugadores, {
  List<String> parejaBase = const [],
}) {
  final n = jugadores.length;
  if (f.motivoNoDisponible(n) != null) return null;

  // Por handicap, y a igualdad por posición en la lista. El índice entra en la
  // comparación en vez de confiar en que el sort sea estable.
  final porHandicap = [
    for (var i = 0; i < n; i++) (i: i, p: jugadores[i]),
  ]..sort((x, y) {
      final c = x.p.handicapBase.compareTo(y.p.handicapBase);
      return c != 0 ? c : x.i.compareTo(y.i);
    });

  switch (f) {
    case Formacion.manual:
      // El reparto alternado de siempre: dos del mismo nivel no caen juntos
      // solo por el orden en que se capturaron.
      final a = <String>[], b = <String>[];
      for (var i = 0; i < n; i++) {
        (i.isEven ? a : b).add(jugadores[i].id);
      }
      return (a, b);

    case Formacion.highAndLow:
      // La mitad de abajo contra la de arriba. Con impares el lado bajo se
      // queda con uno menos, que es el 2 contra 3 del manual.
      final corte = n ~/ 2;
      return (
        [for (final e in porHandicap.take(corte)) e.p.id],
        [for (final e in porHandicap.skip(corte)) e.p.id],
      );

    // La pareja base se resuelve como parejaVsResto y luego se cruza el resto;
    // ver enfrentamientosDe. Aquí se comparte la rama para no tener dos formas
    // de proponer la misma pareja.
    case Formacion.parejaBaseVsCampo:
    case Formacion.parejaVsResto:
      // El handicap combinado más bajo son los dos más bajos: no hay que probar
      // combinaciones.
      final pareja = parejaBase.length == 2 &&
              parejaBase.every((id) => jugadores.any((p) => p.id == id))
          ? parejaBase
          : [for (final e in porHandicap.take(2)) e.p.id];
      // El resto en orden de handicap, igual que High and Low: así los dos
      // paneles se leen de la misma manera y el orden no depende de cómo se
      // capturó a la gente.
      return (
        [...pareja],
        [for (final e in porHandicap) if (!pareja.contains(e.p.id)) e.p.id],
      );
  }
}
