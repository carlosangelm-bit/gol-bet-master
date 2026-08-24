// ─────────────────────────────────────────────────────────────────────────────
// EL ÁRBOL DEL CUADRO — de dónde viene cada plaza, y a dónde va
//
// Lo que había era una lista de fases apiladas: correcta, legible, y sin lo que
// hace que un bracket sea un bracket. Para saber que si Luis gana juega la final
// contra el ganador de Andrés-Pepe, había que deducirlo.
//
// ── LO QUE SE MIDIÓ ANTES DE DECIDIR CÓMO SE NAVEGA ─────────────────────────
//
// Una celda necesita ~118 px para que dos nombres de pila quepan sin recortarse.
// A 390 px, quitando los 16 de margen a cada lado, quedan 358: caben TRES
// columnas justas, dos cómodas. A 320 px, dos.
//
//   · 4 plazas  → 2 fases → cabe entero, hasta a 320
//   · 8 plazas  → 3 fases → cabe a 390, rueda un poco a 320
//   · 16 plazas → 4 fases → rueda siempre
//
// Así que: SCROLL HORIZONTAL, y no zoom. El zoom se descartó por lo que pasa en
// el campo: pinchar para acercar con guante, entre golpe y golpe, para leer un
// nombre, es peor que arrastrar. Y el scroll conserva la lectura de izquierda a
// derecha, que es la que dice "esto avanza hacia la final".
//
// Y como el scroll solo no basta —quien abre esto quiere SU partido, no la
// primera fase— el árbol arranca desplazado a la fase donde estás. Lo que la
// pregunta "¿contra quién voy si gano?" necesita es tu columna y la siguiente, y
// eso es exactamente lo que se ve al abrir.
//
// ── Y DÓNDE DEJA DE SER UN ÁRBOL ────────────────────────────────────────────
//
// La medición de arriba era solo del ANCHO. El ALTO crece más rápido y se
// compone, porque la primera columna apila plazas/2 partidos:
//
//   plazas   fases   ancho   alto     ¿cabe en 358 × 600?
//        4       2     258    176     sí, entero y sin rodar
//        8       3     398    368     rueda 40 px en horizontal, cabe a lo alto
//       16       4     538    680     NO: se sale 180 de ancho y 80 de alto
//       32       5     678   1304     NO: 320 de ancho y 704 de alto
//
// A partir de 16 plazas el árbol exige arrastrar en las DOS direcciones a la vez,
// y eso con guante entre golpe y golpe no se hace. Además la celda de la final
// mide 624 px de alto con dos nombres dentro: un rectángulo casi vacío del tamaño
// de la pantalla.
//
// Así que POR ENCIMA DE TRES FASES esto deja de dibujarse como árbol y pasa a
// VISTA POR FASES: una fase a la vez, en vertical, y cada partido dice de dónde
// vienen sus dos plazas Y a dónde va el que gane. Es la misma información del
// árbol —de dónde viene cada plaza y a dónde va— sin pedir dos scrolls.
//
// No es una versión degradada: es la forma que cabe. Un árbol que no se lee de un
// vistazo es peor que una lista, y eso lo decidía la propia medición.
//
// ── LA GEOMETRÍA DEL ÁRBOL, SIN MATEMÁTICAS GLOBALES ────────────────────────
//
// El truco clásico: la celda de la fase n mide el DOBLE de alto que la de la
// fase n-1, con su contenido centrado. Así cada partido queda alineado con el
// punto medio de los dos que lo alimentan, sin que nadie calcule posiciones
// absolutas. Los conectores se pintan dentro de cada celda, mirando a su propia
// izquierda.
//
// ── UN SOLO WIDGET PARA LAS DOS PANTALLAS ───────────────────────────────────
//
// La app y la vista de invitado consumen el MISMO árbol a través de una forma
// neutra —[ArbolDeLlave]— que las dos construyen. Dos dibujos del mismo cuadro
// habrían divergido en cuanto alguien tocara uno: es lo que pasó con el catálogo
// de tipos de apuesta en cinco pantallas.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// Un partido del árbol, con los nombres YA resueltos.
///
/// Nombres y no ids: la vista de invitado nunca ve ids, y el árbol tiene que
/// servir a las dos pantallas con la misma forma.
class NodoDeLlave {
  final int ronda;
  final int posicion;

  /// Los dos lados. null = plaza por decidir.
  final String? a;
  final String? b;

  /// Quién pasa, por nombre. null si no está resuelto.
  final String? ganador;

  final bool bye;
  final bool empatado;

  /// La ronda que lo resolvió, por su nombre. null si aún no se jugó.
  final String? nota;

  /// El empate lo deshizo una persona, no el resultado.
  final bool desempatadoAMano;

  /// Lo que sacó cada uno, si se sabe.
  final String? medidaA;
  final String? medidaB;

  const NodoDeLlave({
    required this.ronda,
    required this.posicion,
    this.a,
    this.b,
    this.ganador,
    this.bye = false,
    this.empatado = false,
    this.desempatadoAMano = false,
    this.nota,
    this.medidaA,
    this.medidaB,
  });

  bool get esperando => (a == null || b == null) && !bye;
}

/// El cuadro entero, en la forma que el árbol dibuja.
class ArbolDeLlave {
  /// Los partidos por fase. `rondas[0]` es la primera; la última, la final.
  final List<List<NodoDeLlave>> rondas;

  /// El campeón, por nombre.
  final String? campeon;

  final int plazas;
  final int byes;

  const ArbolDeLlave({
    required this.rondas,
    this.campeon,
    this.plazas = 0,
    this.byes = 0,
  });

  bool get vacia => rondas.isEmpty;

  /// El nombre de la fase con [partidos] partidos, contando desde el final.
  static String nombreDeFase(int partidos) => switch (partidos) {
        1 => 'Final',
        2 => 'Semifinales',
        4 => 'Cuartos',
        8 => 'Octavos',
        16 => 'Dieciseisavos',
        _ => 'Ronda de ${partidos * 2}',
      };

  /// A dónde va el que gane [n]. null si es la final.
  ///
  /// Es la otra mitad de la conexión, y la que el árbol dibujaba con una línea.
  /// Sin árbol hay que decirla con palabras.
  String? destinoDe(NodoDeLlave n) {
    final siguiente = n.ronda + 1;
    if (siguiente >= rondas.length) return null;
    final fase = nombreDeFase(rondas[siguiente].length);
    final idx = n.posicion ~/ 2;
    return rondas[siguiente].length == 1
        ? 'Pasa a la $fase'
        : 'Pasa a $fase ${idx + 1}';
  }

  /// De dónde sale la plaza [lado] (0 = A, 1 = B) del partido [n].
  ///
  /// "Ganador de Semifinal 1" en vez de un hueco vacío: un vacío no dice si
  /// falta jugarse o si el cuadro está mal armado.
  String? procedenciaDe(NodoDeLlave n, int lado) {
    if (n.ronda == 0) return null;
    final anterior = n.ronda - 1;
    if (anterior >= rondas.length) return null;
    final idx = n.posicion * 2 + lado;
    if (idx >= rondas[anterior].length) return null;
    final fase = nombreDeFase(rondas[anterior].length);
    // Con una sola final no hace falta numerar: "Ganador de la Final" es único.
    return rondas[anterior].length == 1
        ? 'Ganador de la $fase'
        : 'Ganador de $fase ${idx + 1}';
  }

  /// Los nombres por los que pasa el camino de [quien] hasta donde llegó.
  ///
  /// Sirve para resaltar: un cuadro de dieciséis con el camino de uno marcado se
  /// lee; sin marcar, hay que buscarse.
  Set<String> caminoDe(String? quien) {
    if (quien == null) return const {};
    final out = <String>{};
    for (final fase in rondas) {
      for (final n in fase) {
        if (n.a == quien || n.b == quien) {
          out.add('${n.ronda}-${n.posicion}');
        }
      }
    }
    return out;
  }
}

/// El árbol, con scroll horizontal y la fase de [miNombre] a la vista.
class ArbolDeLlaveVista extends StatefulWidget {
  final ArbolDeLlave arbol;
  final GolfTheme t;

  /// El nombre del usuario, para resaltar su camino. null = no resaltar.
  final String? miNombre;

  const ArbolDeLlaveVista(
      {super.key, required this.arbol, required this.t, this.miNombre});

  @override
  State<ArbolDeLlaveVista> createState() => _ArbolDeLlaveVistaState();
}

class _ArbolDeLlaveVistaState extends State<ArbolDeLlaveVista> {
  final _scroll = ScrollController();

  /// Ancho de una celda. Medido: 118 px es lo mínimo para dos nombres de pila
  /// sin recortar; por debajo, "Guillermo" se convierte en "Guill…".
  static const _ancho = 118.0;

  /// Alto de una celda de la primera fase. Las siguientes doblan.
  ///
  /// 78 y no 62: la celda lleva dos nombres, la nota del bye o del empate Y el
  /// por qué —"Se resolvió en Sábado 20"—. Con 62 se salía 3 px por abajo, y ese
  /// por qué no es adorno: un cuadro que dice quién pasó sin decir con qué ronda
  /// es un veredicto sin motivo, y eso hace discutir el número en vez de la
  /// regla.
  static const _alto = 78.0;

  /// Separación entre columnas, donde van los conectores.
  static const _hueco = 22.0;

  @override
  void initState() {
    super.initState();
    // Arrancar en MI fase, no en la primera. Quien abre esto quiere su partido.
    WidgetsBinding.instance.addPostFrameCallback((_) => _aMiFase());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _aMiFase() {
    if (!mounted || !_scroll.hasClients) return;
    final mio = widget.miNombre;
    if (mio == null) return;
    // La fase más avanzada donde aparezco: es la que está en juego para mí.
    var fase = -1;
    for (var r = 0; r < widget.arbol.rondas.length; r++) {
      if (widget.arbol.rondas[r].any((n) => n.a == mio || n.b == mio)) fase = r;
    }
    if (fase <= 0) return;
    // Se deja la columna anterior asomando: el contexto de dónde vienes ayuda a
    // leer contra quién vas.
    final destino = (fase - 1) * (_ancho + _hueco);
    _scroll.jumpTo(destino.clamp(0, _scroll.position.maxScrollExtent));
  }

  /// Hasta cuántas fases se dibuja como árbol.
  ///
  /// Tres: con cuatro el árbol se sale 180 px de ancho y 80 de alto a 390 px, y
  /// pide arrastrar en diagonal. Medido, no supuesto.
  static const _maxFasesArbol = 3;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final arbol = widget.arbol;
    if (arbol.vacia) return const SizedBox.shrink();

    // Cuadro grande: por fases, en vertical. Ver la cabecera del archivo.
    if (arbol.rondas.length > _maxFasesArbol) {
      return _PorFases(
          arbol: arbol, t: t, miNombre: widget.miNombre);
    }

    final camino = arbol.caminoDe(widget.miNombre);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // El aviso de que esto se arrastra. Sin él, un cuadro de dieciséis parece
      // cortado en vez de navegable.
      if (arbol.rondas.length > 2)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('Arrastra para ver las fases siguientes →',
              style: TextStyle(color: t.sub, fontSize: 10.5)),
        ),
      SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        // Físicas normales: es un arrastre, no un carrusel con posiciones.
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var r = 0; r < arbol.rondas.length; r++) ...[
              if (r > 0) SizedBox(width: _hueco),
              SizedBox(
                width: _ancho,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // La cabecera de la fase, pegada a su columna.
                      SizedBox(
                        height: 20,
                        child: Text(
                            ArbolDeLlave.nombreDeFase(arbol.rondas[r].length)
                                .toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: t.sub,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6)),
                      ),
                      for (final n in arbol.rondas[r])
                        SizedBox(
                          // El doble por fase: así cada partido queda centrado
                          // con el punto medio de los dos que lo alimentan.
                          height: _alto * (1 << r),
                          child: Stack(children: [
                            // Los conectores de ESTA celda, mirando a su
                            // izquierda. Cada celda pinta los suyos, así que no
                            // hay geometría global que mantener.
                            if (r > 0)
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _Conectores(
                                    color: camino.contains(
                                            '${n.ronda}-${n.posicion}')
                                        ? t.primary
                                        : t.divider,
                                    hueco: _hueco,
                                    altoFeeder: _alto * (1 << (r - 1)),
                                  ),
                                ),
                              ),
                            Center(
                                child: _Celda(
                                    n: n,
                                    arbol: arbol,
                                    t: t,
                                    mio: widget.miNombre,
                                    enMiCamino: camino
                                        .contains('${n.ronda}-${n.posicion}'))),
                          ]),
                        ),
                    ]),
              ),
            ],
            // El campeón, cerrando el árbol a la derecha.
            if (arbol.campeon != null) ...[
              SizedBox(width: _hueco),
              SizedBox(
                width: 96,
                child: Column(children: [
                  const SizedBox(height: 20),
                  SizedBox(
                    height: _alto * (1 << (arbol.rondas.length - 1)),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 7),
                        decoration: BoxDecoration(
                          color: t.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: t.primary),
                        ),
                        child: Column(children: [
                          const Text('🏆', style: TextStyle(fontSize: 16)),
                          Text(arbol.campeon!,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: t.text,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800)),
                        ]),
                      ),
                    ),
                  ),
                ]),
              ),
            ],
          ],
        ),
      ),
      if (arbol.byes > 0) ...[
        const SizedBox(height: 8),
        Text(
            '${arbol.byes} ${arbol.byes == 1 ? "jugador pasa" : "jugadores pasan"} '
            'sin jugar la primera fase: el cuadro tiene ${arbol.plazas} plazas y '
            'hay ${arbol.plazas - arbol.byes} inscritos, así que sobran '
            '${arbol.byes}. Se los llevan los primeros de la siembra.',
            style: TextStyle(color: t.sub, fontSize: 11, height: 1.35)),
      ],
    ]);
  }
}

/// Una celda del árbol: los dos lados, con su procedencia si aún no se sabe.
class _Celda extends StatelessWidget {
  final NodoDeLlave n;
  final ArbolDeLlave arbol;
  final GolfTheme t;
  final String? mio;
  final bool enMiCamino;

  const _Celda(
      {required this.n,
      required this.arbol,
      required this.t,
      required this.mio,
      required this.enMiCamino});

  @override
  Widget build(BuildContext context) {
    Widget lado(String? nombre, int cual, String? medida) {
      final gana = nombre != null && nombre == n.ganador;
      final soyYo = nombre != null && nombre == mio;
      // Sin nombre no es un vacío: es una plaza que todavía tiene dueño por
      // decidir, y se dice de dónde va a salir.
      final texto = nombre ?? arbol.procedenciaDe(n, cual) ?? 'Por decidir';
      return Row(children: [
        Expanded(
          child: Text(texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: nombre == null
                      ? t.sub
                      : gana
                          ? t.text
                          : t.sub,
                  fontSize: 11.5,
                  fontStyle:
                      nombre == null ? FontStyle.italic : FontStyle.normal,
                  fontWeight: soyYo
                      ? FontWeight.w900
                      : gana
                          ? FontWeight.w800
                          : FontWeight.w500)),
        ),
        if (medida != null)
          Text(medida,
              style: TextStyle(
                  color: gana ? t.text : t.sub,
                  fontSize: 10,
                  fontWeight: FontWeight.w700)),
      ]);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: BoxDecoration(
        color: enMiCamino ? t.primary.withValues(alpha: 0.08) : t.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: n.empatado
                ? t.scoreOver.withValues(alpha: 0.7)
                : enMiCamino
                    ? t.primary
                    : t.divider,
            width: enMiCamino ? 1.4 : 1),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        lado(n.a, 0, n.medidaA),
        const SizedBox(height: 3),
        lado(n.b, 1, n.medidaB),
        // El POR QUÉ, que es lo que separa un cuadro de un veredicto. El bye se
        // explica —"pasa sin jugar" a secas deja pensando si falta alguien— y el
        // partido resuelto dice con qué ronda.
        if (n.bye || n.empatado || n.nota != null) ...[
          const SizedBox(height: 3),
          Text(
              n.bye
                  ? 'Sin rival: pasa directo'
                  : n.empatado
                      ? 'Empate en ${n.nota ?? "la ronda"} · falta decidir'
                      : n.desempatadoAMano
                          ? 'Empataron en ${n.nota}. Lo decidisteis vosotros.'
                          : 'Se resolvió en ${n.nota}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: n.empatado ? t.scoreOver : t.sub,
                  fontSize: 9,
                  height: 1.2)),
        ],
      ]),
    );
  }
}

/// Las dos líneas que entran a una celda desde su izquierda.
///
/// Se pintan por celda y no de una vez para todo el árbol: cada celda sabe
/// dónde está su punto medio y a qué altura quedan sus dos alimentadores, así
/// que no hay posiciones absolutas que mantener sincronizadas.
class _Conectores extends CustomPainter {
  final Color color;
  final double hueco;
  final double altoFeeder;

  const _Conectores(
      {required this.color, required this.hueco, required this.altoFeeder});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final medio = size.height / 2;
    // Los dos alimentadores están centrados en la mitad de arriba y en la de
    // abajo de esta celda.
    final arriba = altoFeeder / 2;
    final abajo = size.height - altoFeeder / 2;
    final x = -hueco / 2;

    // Vertical que une los dos, y la horizontal que entra a esta celda.
    canvas.drawLine(Offset(x, arriba), Offset(x, abajo), p);
    canvas.drawLine(Offset(x, medio), Offset(0, medio), p);
    canvas.drawLine(Offset(x - hueco / 2, arriba), Offset(x, arriba), p);
    canvas.drawLine(Offset(x - hueco / 2, abajo), Offset(x, abajo), p);
  }

  @override
  bool shouldRepaint(_Conectores old) =>
      old.color != color || old.altoFeeder != altoFeeder;
}

/// El cuadro grande, por fases y en vertical.
///
/// Una fase a la vez. Cada partido dice de dónde vienen sus dos plazas y a dónde
/// va el que gane, así que la conexión que el árbol dibujaba con una línea aquí
/// se dice con palabras. Se elige la fase con los chips de arriba, que sí ruedan
/// —son cuatro o cinco etiquetas cortas— pero el contenido no.
///
/// Arranca en MI fase. Con dieciséis o treinta y dos personas, la primera fase no
/// es donde nadie mira.
class _PorFases extends StatefulWidget {
  final ArbolDeLlave arbol;
  final GolfTheme t;
  final String? miNombre;

  const _PorFases({required this.arbol, required this.t, this.miNombre});

  @override
  State<_PorFases> createState() => _PorFasesState();
}

class _PorFasesState extends State<_PorFases> {
  late int _fase;

  @override
  void initState() {
    super.initState();
    _fase = _miFase();
  }

  /// La fase más avanzada donde aparezco; si no aparezco, la primera sin
  /// resolver, que es donde está el torneo.
  int _miFase() {
    final mio = widget.miNombre;
    if (mio != null) {
      for (var r = widget.arbol.rondas.length - 1; r >= 0; r--) {
        if (widget.arbol.rondas[r].any((n) => n.a == mio || n.b == mio)) return r;
      }
    }
    for (var r = 0; r < widget.arbol.rondas.length; r++) {
      if (widget.arbol.rondas[r].any((n) => n.ganador == null)) return r;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final arbol = widget.arbol;
    final camino = arbol.caminoDe(widget.miNombre);
    final fase = arbol.rondas[_fase];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Por qué esto no es un árbol, dicho una vez. Un usuario que ha visto el
      // árbol en un cuadro de cuatro se pregunta por qué aquí no está.
      Text(
          'Cuadro de ${arbol.plazas} plazas: se ve por fases, porque un árbol de '
          '${arbol.rondas.length} columnas no cabe en un teléfono sin arrastrar '
          'en diagonal.',
          style: TextStyle(color: t.sub, fontSize: 10.5, height: 1.3)),
      const SizedBox(height: 8),
      // Los chips de fase. Cortos, así que su scroll no molesta.
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (var r = 0; r < arbol.rondas.length; r++) ...[
            if (r > 0) const SizedBox(width: 6),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _fase = r),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: r == _fase
                      ? t.primary.withValues(alpha: 0.14)
                      : t.surface,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                      color: r == _fase ? t.primary : t.divider,
                      width: r == _fase ? 1.5 : 1),
                ),
                child: Text(
                    ArbolDeLlave.nombreDeFase(arbol.rondas[r].length),
                    style: TextStyle(
                        color: r == _fase ? t.text : t.sub,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 10),
      for (var i = 0; i < fase.length; i++)
        _FilaDeFase(
          n: fase[i],
          numero: i + 1,
          arbol: arbol,
          t: t,
          mio: widget.miNombre,
          enMiCamino: camino.contains('${fase[i].ronda}-${fase[i].posicion}'),
        ),
      if (arbol.campeon != null) ...[
        const SizedBox(height: 10),
        Row(children: [
          const Text('🏆', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Campeón: ${arbol.campeon}',
                style: TextStyle(
                    color: t.text, fontSize: 14, fontWeight: FontWeight.w800)),
          ),
        ]),
      ],
      if (arbol.byes > 0) ...[
        const SizedBox(height: 8),
        Text(
            '${arbol.byes} ${arbol.byes == 1 ? "jugador pasa" : "jugadores pasan"} '
            'sin jugar la primera fase: el cuadro tiene ${arbol.plazas} plazas y '
            'hay ${arbol.plazas - arbol.byes} inscritos.',
            style: TextStyle(color: t.sub, fontSize: 11, height: 1.35)),
      ],
    ]);
  }
}

/// Un partido en la vista por fases, con sus dos conexiones dichas.
class _FilaDeFase extends StatelessWidget {
  final NodoDeLlave n;
  final int numero;
  final ArbolDeLlave arbol;
  final GolfTheme t;
  final String? mio;
  final bool enMiCamino;

  const _FilaDeFase(
      {required this.n,
      required this.numero,
      required this.arbol,
      required this.t,
      required this.mio,
      required this.enMiCamino});

  @override
  Widget build(BuildContext context) {
    Widget lado(String? nombre, int cual, String? medida) {
      final gana = nombre != null && nombre == n.ganador;
      final soyYo = nombre != null && nombre == mio;
      final texto = nombre ?? arbol.procedenciaDe(n, cual) ?? 'Por decidir';
      return Row(children: [
        Expanded(
          child: Text(texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: nombre == null
                      ? t.sub
                      : gana
                          ? t.text
                          : t.sub,
                  fontSize: 13,
                  fontStyle:
                      nombre == null ? FontStyle.italic : FontStyle.normal,
                  fontWeight: soyYo
                      ? FontWeight.w900
                      : gana
                          ? FontWeight.w800
                          : FontWeight.w500)),
        ),
        if (medida != null)
          Text(medida,
              style: TextStyle(
                  color: gana ? t.text : t.sub,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700)),
        if (gana) ...[
          const SizedBox(width: 6),
          Icon(Icons.arrow_forward, size: 13, color: t.primary),
        ],
      ]);
    }

    final destino = arbol.destinoDe(n);

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: enMiCamino ? t.primary.withValues(alpha: 0.08) : t.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: n.empatado
                ? t.scoreOver.withValues(alpha: 0.7)
                : enMiCamino
                    ? t.primary
                    : t.divider,
            width: enMiCamino ? 1.4 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // El número del partido dentro de su fase: es lo que hace que
        // "Ganador de Cuartos 3" se pueda seguir hasta aquí.
        Text(
            '${ArbolDeLlave.nombreDeFase(arbol.rondas[n.ronda].length)} '
            '$numero',
            style: TextStyle(
                color: t.sub,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5)),
        const SizedBox(height: 5),
        lado(n.a, 0, n.medidaA),
        const SizedBox(height: 4),
        lado(n.b, 1, n.medidaB),
        if (n.bye || n.empatado || n.nota != null) ...[
          const SizedBox(height: 5),
          Text(
              n.bye
                  ? 'Sin rival: pasa directo'
                  : n.empatado
                      ? 'Empate en ${n.nota ?? "la ronda"} · falta decidir'
                      : n.desempatadoAMano
                          ? 'Empataron en ${n.nota}. Lo decidisteis vosotros.'
                          : 'Se resolvió en ${n.nota}',
              style: TextStyle(
                  color: n.empatado ? t.scoreOver : t.sub,
                  fontSize: 10.5,
                  height: 1.25)),
        ],
        // La conexión hacia arriba, que es lo que el árbol dibujaba con una
        // línea: a dónde va el que gane.
        if (destino != null) ...[
          const SizedBox(height: 4),
          Text('→ $destino',
              style: TextStyle(
                  color: t.primary, fontSize: 10.5, fontWeight: FontWeight.w700)),
        ],
      ]),
    );
  }
}
