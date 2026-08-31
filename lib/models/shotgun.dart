// ─────────────────────────────────────────────────────────────────────────────
// SHOTGUN — repartir el padrón, asignar salidas, y decirlo cuando no cuadra
//
// «No existe modelo de grupos ni de salidas. Un "grupo" hoy es una ronda viva
// marcada con el torneoId. Así que lo que falta en el shotgun no es estructura
// de datos: es creación por lotes.»
//
// Eso sigue siendo verdad, y por eso aquí no hay ningún documento nuevo. Lo que
// hay es el CÁLCULO: cómo se parte una lista de 150 nombres en grupos, a qué
// salida va cada uno, y qué decir cuando los números no encajan.
//
// Vive aparte de la pantalla por el mismo motivo que la tabla de inscritos: se
// puede probar sin montar una sesión, y el reparto de 150 personas es
// exactamente el tipo de aritmética donde un caso raro —cinco jugadores— pasa
// desapercibido hasta el día del torneo.
//
// ── LAS DOS SALIDAS EN LOS PAR 3 ────────────────────────────────────────────
//
// Un campo de 18 con cuatro par 3 da 22 puntos de salida: los 18 hoyos más una
// letra B en cada par 3. Y de ahí sale lo que importa: la asignación NO es
// "hoyo N", es "hoyo N, letra A o B". Un grupo que solo sabe su número no sabe
// dónde ponerse cuando hay otro grupo en el mismo tee.
//
// ── Y QUÉ SE DICE CUANDO NO CUADRA ──────────────────────────────────────────
//
// «Que lo diga con el número, no que reparta como se pueda.» Con 20 grupos y 22
// salidas sobran dos; con 24 no caben dos. Las dos frases llevan la cifra,
// porque "no cuadra" no dice qué hacer y "faltan 2 salidas" sí.
// ─────────────────────────────────────────────────────────────────────────────
import 'models.dart';

/// Un punto de salida: el hoyo y, si comparte tee, la letra.
class PuntoDeSalida {
  final int hoyo;

  /// `null` cuando el hoyo tiene una sola salida. 'A' y 'B' cuando son dos.
  ///
  /// Null y 'A' NO son lo mismo: en un hoyo con una sola salida decir "1A"
  /// invita a buscar el 1B, y el organizador tendría que explicar que no existe.
  final String? letra;

  const PuntoDeSalida(this.hoyo, [this.letra]);

  /// Como se dice en voz alta y como se escribe en la hoja.
  String get etiqueta => letra == null ? 'Hoyo $hoyo' : 'Hoyo $hoyo$letra';

  @override
  bool operator ==(Object other) =>
      other is PuntoDeSalida && other.hoyo == hoyo && other.letra == letra;
  @override
  int get hashCode => Object.hash(hoyo, letra);
}

/// Los puntos de salida de [campo], en el orden en que se cantan.
///
/// [dosEnPar3] es la decisión de Carlos y viene por parámetro porque un torneo
/// pequeño no la necesita: con 40 jugadores sobran salidas y meter dos grupos
/// en un tee sin hacer falta solo hace esperar.
///
/// [par3AMano] es la anulación del organizador, y SUSTITUYE al dato del campo
/// en vez de sumarse a él.
///
/// ── Por qué sustituye ──────────────────────────────────────────────────────
///
/// Sumarse solo permitiría AÑADIR. Y hace falta quitar: un campo mal cargado
/// puede traer un par 3 donde hay un par 4, y entonces la app pondría dos
/// grupos en un tee donde no caben. Con "sumarse", el botón de quitar de la
/// pantalla no haría nada — una interfaz que dice "toca para quitar" y no quita
/// es peor que no ofrecerlo.
///
/// Vacío = manda el campo, que es el caso normal. Con algo dentro, manda el
/// organizador, que es quien está mirando el tee.
List<PuntoDeSalida> salidasDe(
  CourseInfo campo, {
  bool dosEnPar3 = true,
  Set<int> par3AMano = const {},
}) {
  final salidas = <PuntoDeSalida>[];
  for (final h in campo.holes) {
    final esPar3 =
        par3AMano.isEmpty ? h.isPar3 : par3AMano.contains(h.hole);
    if (dosEnPar3 && esPar3) {
      salidas.add(PuntoDeSalida(h.hole, 'A'));
      salidas.add(PuntoDeSalida(h.hole, 'B'));
    } else {
      salidas.add(PuntoDeSalida(h.hole));
    }
  }
  salidas.sort((a, b) {
    final porHoyo = a.hoyo.compareTo(b.hoyo);
    return porHoyo != 0 ? porHoyo : (a.letra ?? '').compareTo(b.letra ?? '');
  });
  return salidas;
}

/// Un grupo del shotgun: quién juega y desde dónde sale.
class GrupoDeSalida {
  /// Los ids del padrón, en el orden en que se pusieron.
  final List<String> jugadores;

  /// Su salida. `null` cuando no hay salidas para todos —ver [PlanDeShotgun].
  final PuntoDeSalida? salida;

  const GrupoDeSalida({required this.jugadores, this.salida});

  GrupoDeSalida con({List<String>? jugadores, PuntoDeSalida? salida}) =>
      GrupoDeSalida(
          jugadores: jugadores ?? this.jugadores, salida: salida ?? this.salida);
}

/// El reparto completo, con lo que hay que decir.
class PlanDeShotgun {
  final List<GrupoDeSalida> grupos;
  final List<PuntoDeSalida> salidas;

  /// Lo que impide seguir. `null` cuando el plan es utilizable.
  ///
  /// Es un motivo y no un bool porque las tres razones piden acciones
  /// distintas: sin campo se elige campo, sin gente se inscribe gente, y con
  /// más grupos que salidas se cambia el tamaño de los grupos.
  final String? impedimento;

  /// Lo que conviene saber pero no impide nada. Sobrar salidas no es un error.
  final String? aviso;

  const PlanDeShotgun({
    required this.grupos,
    required this.salidas,
    this.impedimento,
    this.aviso,
  });

  bool get utilizable => impedimento == null && grupos.isNotEmpty;

  /// Cuántos jugadores entran en el plan.
  int get jugadores => grupos.fold(0, (s, g) => s + g.jugadores.length);
}

/// Reparte [padron] en grupos de [tamano] y les asigna las salidas de [campo].
///
/// ── El reparto: por qué no es "de cuatro en cuatro" ─────────────────────────
///
/// Cortar la lista en trozos de cuatro deja el último con lo que sobre: con 150
/// jugadores, treinta y siete grupos de cuatro y uno de DOS. Y un grupo de dos
/// en un shotgun de 88 personas es el que va a esperar a todos los demás.
///
/// Así que primero se decide CUÁNTOS grupos hacen falta y luego se reparte a
/// partes iguales: 150 en 38 grupos son 36 de cuatro y 2 de tres. Ninguno queda
/// corto, y la diferencia entre el mayor y el menor nunca pasa de uno.
PlanDeShotgun planDeShotgun({
  required List<String> padron,
  required CourseInfo? campo,
  int tamano = 4,
  bool dosEnPar3 = true,
  Set<int> par3AMano = const {},
}) {
  // ── Criterio 5: si el campo no trae hoyos, se dice ────────────────────────
  //
  // Suponer 18 hoyos con cuatro par 3 daría 22 salidas inventadas, y el
  // organizador se enteraría en el tee. Un campo sin hoyos es un campo a medio
  // cargar, no un campo estándar.
  if (campo == null) {
    return const PlanDeShotgun(
        grupos: [],
        salidas: [],
        // Y no se manda a nadie a otro sitio: el selector está en la misma
        // pantalla, arriba. El aviso decía "elige el campo y vuelve" cuando no
        // había dónde elegirlo — mandar a un sitio sin nombrarlo es peor que
        // no decir nada.
        impedimento: 'Elige el campo arriba: las salidas salen de sus hoyos y '
            'de cuáles son par 3.');
  }
  if (campo.holes.isEmpty) {
    return PlanDeShotgun(
        grupos: const [],
        salidas: const [],
        // Sin NINGÚN hoyo, marcar par 3 a mano no sirve: no se sabe cuántos
        // hoyos hay que marcar. Decirlo aquí sería ofrecer una salida que no
        // existe, que es el fallo que este mensaje acaba de tener.
        impedimento: '"${campo.name}" no trae sus hoyos, así que no se sabe '
            'cuántas salidas hay. Elige otro campo, o vuelve a cargar este '
            'desde el buscador.');
  }

  final salidas = salidasDe(campo, dosEnPar3: dosEnPar3, par3AMano: par3AMano);

  if (padron.isEmpty) {
    return PlanDeShotgun(
        grupos: const [],
        salidas: salidas,
        impedimento: 'No hay nadie inscrito todavía. Los grupos salen del '
            'padrón.');
  }

  final n = padron.length;
  final cuantos = (n / tamano).ceil();
  final base = n ~/ cuantos;
  final conUnoMas = n % cuantos;

  // Los grandes primero: si alguien tiene que ir en un grupo de tres, mejor
  // que sean los últimos de la lista y no los primeros — que son los que el
  // organizador inscribió primero y suele reconocer.
  final tamanos = [
    for (var i = 0; i < cuantos; i++) i < conUnoMas ? base + 1 : base,
  ];

  final grupos = <GrupoDeSalida>[];
  var i = 0;
  for (var g = 0; g < cuantos; g++) {
    final trozo = padron.sublist(i, i + tamanos[g]);
    i += tamanos[g];
    grupos.add(GrupoDeSalida(
      jugadores: trozo,
      salida: g < salidas.length ? salidas[g] : null,
    ));
  }

  // ── Criterio 4: cuando no caben, con el número ────────────────────────────
  String? impedimento;
  String? aviso;
  if (grupos.length > salidas.length) {
    final sobran = grupos.length - salidas.length;
    impedimento = '${grupos.length} grupos y ${salidas.length} salidas: no '
        'caben $sobran. Sube el tamaño de los grupos, o saca $sobran grupo'
        '${sobran == 1 ? '' : 's'} de este shotgun.';
  } else if (grupos.length < salidas.length) {
    final libres = salidas.length - grupos.length;
    aviso = '${grupos.length} grupos en ${salidas.length} salidas: sobran '
        '$libres. Las últimas quedan vacías.';
  }

  // El reparto imposible: cinco jugadores no se parten en grupos de tres o
  // cuatro de ninguna manera. Se dice en vez de dejar un grupo de dos callado.
  final corto = tamanos.where((x) => x < 3).toList();
  if (corto.isNotEmpty && impedimento == null) {
    final ya = aviso == null ? '' : '$aviso ';
    aviso = '$ya$n jugador${n == 1 ? '' : 'es'} no se reparte'
        '${n == 1 ? '' : 'n'} en grupos de 3 o 4: '
        'quedaría${corto.length == 1 ? '' : 'n'} ${corto.length} grupo'
        '${corto.length == 1 ? '' : 's'} de ${corto.join(' y ')}.';
  }

  return PlanDeShotgun(
      grupos: grupos,
      salidas: salidas,
      impedimento: impedimento,
      aviso: aviso);
}

/// Mueve [jugador] al grupo [destino], sacándolo del que estaba.
///
/// ── Por qué mover y no arrastrar ────────────────────────────────────────────
///
/// «Un organizador siempre quiere mover a alguien de sitio.» Cierto, y por eso
/// el reparto automático es un PUNTO DE PARTIDA y no un resultado.
///
/// Se mueve eligiendo destino, no arrastrando. Arrastrar entre 38 grupos en una
/// lista que se desplaza es la interacción que falla en el móvil y el día del
/// torneo el organizador tiene el teléfono en una mano y una hoja en la otra.
///
/// Las salidas NO se mueven con el jugador: la salida es del grupo. Cambiar de
/// grupo es cambiar de salida, y eso es lo que se está pidiendo.
List<GrupoDeSalida> moviendo(
  List<GrupoDeSalida> grupos,
  String jugador,
  int destino,
) {
  if (destino < 0 || destino >= grupos.length) return grupos;
  if (grupos[destino].jugadores.contains(jugador)) return grupos;
  return [
    for (var i = 0; i < grupos.length; i++)
      grupos[i].con(
        jugadores: i == destino
            ? [...grupos[i].jugadores, jugador]
            : grupos[i].jugadores.where((x) => x != jugador).toList(),
      ),
  ];
}

/// Las rondas que hay que crear para [plan]. Una por grupo.
///
/// ── Qué lleva cada ronda, y por qué tan poco ────────────────────────────────
///
/// El nombre dice la SALIDA —"Hoyo 7B"— y no "Grupo 14". El organizador canta
/// salidas por megafonía y el jugador busca su hoyo, no su número de grupo. Y
/// en la sección de scores en vivo, una lista de veintidós "Grupo N" no le dice
/// a nadie dónde está ninguno.
///
/// La marca del torneo viaja en `torneoIds`, que es lo que hace que estas
/// rondas aparezcan solas en la tabla y en el portal. Sin ella son veintidós
/// rondas sueltas de un sábado.
///
/// Las apuestas van VACÍAS. En un shotgun de 88 personas la apuesta no la pacta
/// el organizador: cada grupo pacta lo suyo, o no pacta nada porque el torneo se
/// puntúa por score. Rellenarlas aquí sería decidir por ochenta y ocho personas
/// a la vez — y la ronda se puede configurar después, que es lo que ya hace la
/// pantalla de apuestas.
List<Round> rondasDelPlan({
  required PlanDeShotgun plan,
  required String torneoId,
  required CourseInfo campo,
  required Map<String, Player> porId,
  required DateTime cuando,
  /// El handicap con el que entra cada jugador. Vacío = todos a cero.
  Map<String, double> handicaps = const {},
}) {
  final rondas = <Round>[];
  for (var i = 0; i < plan.grupos.length; i++) {
    final g = plan.grupos[i];
    if (g.jugadores.isEmpty) continue;
    // Un grupo sin salida no se crea: el plan ya lo impide con su motivo, y
    // crear una ronda cuyo nombre no puede decir de dónde sale es peor que no
    // crearla.
    if (g.salida == null) continue;

    final jugadores = [
      for (final pid in g.jugadores)
        porId[pid] ?? Player(id: pid, name: 'Jugador'),
    ];
    rondas.add(Round(
      // Determinista: el mismo plan crea las mismas rondas. Volver a darle al
      // botón ACTUALIZA en vez de duplicar veintidós grupos, que es el error
      // que un botón lento produce solo.
      id: '${torneoId}_s${g.salida!.hoyo}${g.salida!.letra ?? ''}',
      name: g.salida!.etiqueta,
      course: campo,
      players: jugadores,
      roundPlayers: [
        for (final p in jugadores)
          RoundPlayer(
              playerId: p.id, handicapEnRonda: handicaps[p.id] ?? 0),
      ],
      betGroups: const [],
      scores: const {},
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: cuando,
      torneoIds: [torneoId],
      totalHoles: campo.holes.length >= 18 ? 18 : campo.holes.length,
      // El organizador captura, o su acompañante: en un shotgun de 88 personas
      // no todos traen la app.
      scoringMode: 'admin',
    ));
  }
  return rondas;
}
