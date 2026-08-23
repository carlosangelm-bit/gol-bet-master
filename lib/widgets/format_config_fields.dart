// ─────────────────────────────────────────────────────────────────────────────
// CAMPOS DE CONFIGURACIÓN DE LOS FORMATOS NUEVOS — escritos UNA vez
//
// Hay tres editores de configuración de apuesta en la app —la hoja compartida,
// el paso de detalle de Setup y las configuraciones guardadas— y cada uno tiene
// su propio constructor de campos por tipo. Con los tres formatos nuevos eso
// serían NUEVE bloques casi idénticos.
//
// Y ya sabemos cómo acaba: el catálogo de tipos vivía repartido por cinco
// pantallas y costó dos bugs silenciosos —al añadir Bola Baja / Bola Alta quedó
// fuera del selector de Setup y de la sección de equipos, sin error en ninguno
// de los dos casos—.
//
// Así que los campos de Snake se escriben aquí y los tres editores llaman. El
// estilo se replica del de Setup para que no se note el cambio de casa; si algún
// día divergen de verdad, se parametriza.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../models/models.dart';

Widget _etiqueta(String texto, GolfTheme t) => Text(
      texto,
      style: TextStyle(
          color: t.sub,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6),
    );

Widget _nota(String texto, GolfTheme t) => Text(
      texto,
      style: TextStyle(color: t.sub, fontSize: 11, fontStyle: FontStyle.italic),
    );

Widget _monto(String label, TextEditingController ctrl, GolfTheme t,
        {required ValueChanged<double> onChanged}) =>
    TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      style: TextStyle(color: t.text),
      onChanged: (txt) {
        final v = double.tryParse(txt);
        if (v != null) onChanged(v);
      },
      decoration: InputDecoration(
        labelText: label,
        prefixText: '\$ ',
        fillColor: t.surface,
        filled: true,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: t.divider)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: t.divider)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: t.primary, width: 2)),
        labelStyle: TextStyle(color: t.sub),
      ),
    );

Widget _opciones(List<String> etiquetas, int seleccionada, GolfTheme t,
        ValueChanged<int> onSelect) =>
    Row(
      children: etiquetas.asMap().entries.map((e) {
        final sel = e.key == seleccionada;
        return Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect(e.key),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: sel ? t.primary.withValues(alpha: 0.14) : t.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: sel ? t.primary : t.divider, width: sel ? 1.6 : 1),
              ),
              child: Text(
                e.value,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: sel ? t.primary : t.sub,
                  fontSize: 12.5,
                  fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );

// ── SNAKE ────────────────────────────────────────────────────────────────────

/// Los campos de Snake: monto, umbral de putts y qué hacer con un empate.
///
/// No hay selector de bruto/neto —los putts no se ajustan por handicap— ni de
/// segmentos: es UNA serpiente por ronda, la última.
List<Widget> snakeFields({
  required GolfTheme t,
  required SnakeConfig cfg,
  required TextEditingController montoCtrl,
  required ValueChanged<SnakeConfig> onChanged,
}) =>
    [
      _etiqueta('MONTO A CADA RIVAL', t),
      const SizedBox(height: 8),
      _monto('Monto', montoCtrl, t,
          onChanged: (v) => onChanged(cfg.copyWith(value: v))),
      const SizedBox(height: 6),
      _nota(
          'El dueño de la serpiente paga esto a cada uno de los demás. Se '
          'define por rival para que el importe no cambie de significado al '
          'variar el número de jugadores.',
          t),
      const SizedBox(height: 18),

      _etiqueta('A PARTIR DE CUÁNTOS PUTTS', t),
      const SizedBox(height: 8),
      _opciones(['3 putts', '4 putts'], cfg.umbral >= 4 ? 1 : 0, t,
          (i) => onChanged(cfg.copyWith(umbral: i == 1 ? 4 : 3))),
      const SizedBox(height: 6),
      _nota(
          'Se busca el ÚLTIMO hoyo de la ronda donde alguien llega a esta '
          'cifra. Los putts ya se capturan en la tarjeta: Snake no pide nada '
          'nuevo en el campo.',
          t),
      const SizedBox(height: 18),

      // El empate es una ELECCIÓN visible, no un accidente del orden de la
      // lista de jugadores. Con dos que llegan al umbral en el mismo último
      // hoyo hay dos respuestas defendibles y ninguna es obvia.
      _etiqueta('SI DOS EMPATAN EN EL ÚLTIMO HOYO', t),
      const SizedBox(height: 8),
      _opciones([SnakeEmpate.ambosPagan.label, SnakeEmpate.dividen.label],
          cfg.empate == SnakeEmpate.dividen ? 1 : 0, t,
          (i) => onChanged(cfg.copyWith(
              empate:
                  i == 1 ? SnakeEmpate.dividen : SnakeEmpate.ambosPagan))),
      const SizedBox(height: 6),
      _nota(cfg.empate.description, t),
    ];

// ── RABBIT ───────────────────────────────────────────────────────────────────

Widget _interruptor(
        String titulo, String explica, bool valor, GolfTheme t,
        ValueChanged<bool> onChanged) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo,
                style: TextStyle(
                    color: t.text, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(explica,
                style: TextStyle(color: t.sub, fontSize: 11, height: 1.35)),
          ]),
        ),
        const SizedBox(width: 10),
        Switch(value: valor, onChanged: onChanged, activeThumbColor: t.primary),
      ]),
    );

/// Los campos de Rabbit: el importe por nueve y las variantes.
///
/// Las variantes van TODAS apagadas por defecto, que es el estándar, y cada una
/// dice qué cambia. Un interruptor sin explicación en un formato que casi nadie
/// conoce de memoria es un interruptor que se deja como está por miedo.
///
/// Falta una de las cuatro que pedía el encargo: **patas (legs)**. El resumen de
/// la especificación la lista pero no dice qué hace, y no hay a quién preguntar.
/// Un interruptor con el nombre de una variante real y una regla que yo me haya
/// inventado detrás es peor que no ofrecerla: el usuario la activa creyendo que
/// juega a lo que su grupo llama "patas". Queda reportado, no adivinado.
List<Widget> rabbitFields({
  required GolfTheme t,
  required RabbitConfig cfg,
  required TextEditingController montoCtrl,
  required ValueChanged<RabbitConfig> onChanged,
}) =>
    [
      _etiqueta('MONTO POR CADA NUEVE', t),
      const SizedBox(height: 8),
      _monto('Monto', montoCtrl, t,
          onChanged: (v) => onChanged(cfg.copyWith(value: v))),
      const SizedBox(height: 6),
      _nota(
          'Quien tenga el conejo al cerrar los primeros nueve cobra esto a cada '
          'uno de los demás. Y otra vez al cerrar los segundos: el conejo se '
          'suelta y la caza empieza de cero.',
          t),
      const SizedBox(height: 18),

      _etiqueta('CÓMO SE CAPTURA', t),
      const SizedBox(height: 6),
      _nota(
          'Lo agarra quien gana el hoyo SOLO —el neto más bajo, sin empate—. Un '
          'hoyo empatado no lo mueve: quien lo tenía sigue teniéndolo.',
          t),
      const SizedBox(height: 18),

      _etiqueta('VARIANTES', t),
      const SizedBox(height: 10),
      _interruptor(
          'Conejo robable',
          cfg.robable
              ? 'Ganarle al dueño se lo quita en el acto.'
              : 'Ganarle al dueño SUELTA el conejo; hay que ganar otro hoyo '
                  'para agarrarlo. Es lo estándar.',
          cfg.robable, t,
          (v) => onChanged(cfg.copyWith(robable: v))),
      _interruptor(
          'Acumular el bote no cobrado',
          cfg.acumula
              ? 'Si nadie lo tiene al cerrar los primeros nueve, ese importe se '
                  'suma al de los segundos.'
              : 'Si nadie lo tiene al cerrar, ese importe se pierde. Es lo '
                  'estándar.',
          cfg.acumula, t,
          (v) => onChanged(cfg.copyWith(acumula: v))),
      _interruptor(
          'Squirrel',
          cfg.squirrel
              ? 'Para capturar hace falta birdie neto, no solo ganar el hoyo.'
              : 'Basta con ganar el hoyo. Es lo estándar.',
          cfg.squirrel, t,
          (v) => onChanged(cfg.copyWith(squirrel: v))),
    ];

// ── WOLF ─────────────────────────────────────────────────────────────────────

/// Los campos de Wolf: el importe del hoyo y el multiplicador del Lone Wolf.
///
/// Dos controles, y el segundo existe por una razón concreta: Carlos no juega
/// Wolf. Conoce grupos que sí, pero no el detalle. Así que lo que no se sabe va
/// configurable con el valor estándar por defecto en vez de decidirse a ciegas.
///
/// Lo que NO está aquí, y es deliberado:
///
///   · **El Lone Wolf que pierde** paga sencillo a cada rival. Es lo estándar y
///     no se hace configurable: un control por cada regla convierte la hoja en
///     un formulario y deja de leerse.
///   · **La regla de los hoyos 17-18.** Algunos grupos hacen que sea Wolf el que
///     va perdiendo; sin dato, rotación simple. Vive en WolfEngine.wolfDelHoyo.
///   · **Blind Wolf.** Variante sobre variante y sin nadie a quien preguntar.
///
/// Y lo importante: el diseño de captura —una pregunta por hoyo— no depende de
/// ninguna de las tres. Añadir cualquiera después es una opción más, no rehacer
/// el formato.
///
/// [jugadores] es cuántas personas juegan, si se sabe. Solo se usa para redactar
/// las notas con el número real —"contra los otros tres" o "los otros cuatro"—
/// y para avisar de que con cinco el multiplicador suele subirse. Null en una
/// configuración guardada, que no tiene jugadores.
List<Widget> wolfFields({
  required GolfTheme t,
  required WolfConfig cfg,
  required TextEditingController montoCtrl,
  required ValueChanged<WolfConfig> onChanged,
  int? jugadores,
}) {
  final rivalesDelSolo = jugadores == null ? null : jugadores - 1;
  final cinco = jugadores == 5;
  return [
      _etiqueta('MONTO POR HOYO', t),
      const SizedBox(height: 8),
      _monto('Monto', montoCtrl, t,
          onChanged: (v) => onChanged(cfg.copyWith(value: v))),
      const SizedBox(height: 6),
      _nota(
          'Cada perdedor del hoyo paga esto a cada ganador. El hoyo se decide '
          'por la mejor bola neta de la pareja del Wolf contra la de los '
          'demás.',
          t),
      const SizedBox(height: 18),

      // Con cinco jugadores el lado del Wolf es 2 contra 3. Se dice aquí porque
      // es lo que explica un importe al doble en el resultado.
      if (cinco) ...[
        _etiqueta('CON CINCO JUGADORES', t),
        const SizedBox(height: 6),
        _nota(
            'El Wolf y su compañero juegan 2 contra 3, así que van en minoría: '
            'si ganan el hoyo, cobran el doble. Es la regla del formato, no una '
            'opción.',
            t),
        const SizedBox(height: 18),
      ],

      _etiqueta('LONE WOLF QUE GANA', t),
      const SizedBox(height: 8),
      _opciones(
          ['×2', '×3', '×4'],
          cfg.loneMultiplier >= 4 ? 2 : (cfg.loneMultiplier >= 3 ? 1 : 0),
          t,
          (i) => onChanged(cfg.copyWith(loneMultiplier: [2.0, 3.0, 4.0][i]))),
      const SizedBox(height: 6),
      _nota(
          'Ir solo contra '
          '${rivalesDelSolo == null ? 'los demás' : 'los otros $rivalesDelSolo'} '
          'y ganar paga ×${cfg.loneMultiplier.toStringAsFixed(0)}. Si pierde, '
          'paga sencillo a cada rival — eso es lo estándar y no se cambia.',
          t),
      // Se AVISA en vez de cambiar el valor por defecto según el tamaño. Ir solo
      // contra cuatro es más duro que contra tres y muchos grupos lo suben, pero
      // un default distinto por número de jugadores es una regla que nadie pidió
      // y que sorprendería a quien ya tenía su valor elegido.
      if (cinco) ...[
        const SizedBox(height: 4),
        _nota(
            'Con cinco se va solo contra cuatro, y muchos grupos suben el '
            'multiplicador por eso. Se deja como lo tengas: tú sabes cómo lo '
            'juega el tuyo.',
            t),
      ],
      const SizedBox(height: 18),

      _etiqueta('QUIÉN ES EL WOLF', t),
      const SizedBox(height: 6),
      _nota(
          'Se deriva del orden de salida y rota un hoyo por jugador: el 1 le '
          'toca al primero, el 2 al segundo, y así. Con cuatro el ciclo cierra '
          'cada cuatro hoyos y con cinco cada cinco. No hay nada que elegir ni '
          'que ver durante el hoyo — la app solo pregunta con quién jugó al '
          'anotar el score.',
          t),
  ];
}

// ── STABLEFORD ───────────────────────────────────────────────────────────────

/// Los campos de Stableford: el monto, bruto/neto y la tabla de puntos.
///
/// La tabla es configurable porque sale gratis: la clásica es exactamente
/// `clamp(puntosDelPar - relativoAlPar, piso, techo)` con 2/0/5, comprobado
/// valor por valor contra la implementación anterior. Cambiar cuánto vale un par
/// o dónde está el suelo es mover un número, no otra función.
///
/// Lo que NO cabe, y queda dicho aquí en vez de inventado: el **Stableford
/// Modificado** —8/5/2/0/−1/−3— no es lineal, así que necesitaría una tabla
/// explícita hoyo por resultado. Un grupo que penalice el doble bogey con −1
/// tampoco es expresable con estos tres números. Cuando alguien lo pida con las
/// reglas concretas de su grupo, es un mapa aquí y nada más.
List<Widget> stablefordFields({
  required GolfTheme t,
  required StablefordConfig cfg,
  required TextEditingController montoCtrl,
  required ValueChanged<StablefordConfig> onChanged,
}) =>
    [
      _etiqueta('MONTO', t),
      const SizedBox(height: 8),
      _monto('Monto', montoCtrl, t,
          onChanged: (v) => onChanged(cfg.copyWith(value: v))),
      const SizedBox(height: 6),
      _nota('Lo paga quien pierde a quien gana. Gana el que más puntos sume.', t),
      const SizedBox(height: 18),

      _etiqueta('BRUTO O NETO', t),
      const SizedBox(height: 8),
      _opciones(['Neto', 'Bruto'], cfg.mode == GrossNetMode.gross ? 1 : 0, t,
          (i) => onChanged(cfg.copyWith(
              mode: i == 1 ? GrossNetMode.gross : GrossNetMode.net))),
      const SizedBox(height: 6),
      _nota(
          cfg.mode == GrossNetMode.net
              ? 'Neto: se descuentan los golpes que recibe cada uno por stroke '
                  'index antes de contar los puntos. Es el Stableford habitual.'
              : 'Bruto: los puntos salen del score sin ventaja.',
          t),
      const SizedBox(height: 18),

      _etiqueta('TABLA DE PUNTOS', t),
      const SizedBox(height: 6),
      // La tabla se enseña resuelta, no como tres números sueltos: "el par vale
      // 2" no dice qué vale un birdie, y es lo que el jugador quiere saber.
      _nota(_tablaEnPalabras(cfg), t),
      const SizedBox(height: 10),
      _opciones(['Par vale 2', 'Par vale 1'], cfg.puntosDelPar == 1 ? 1 : 0, t,
          (i) => onChanged(cfg.copyWith(puntosDelPar: i == 1 ? 1 : 2))),
      const SizedBox(height: 6),
      _opciones(['Suelo 0', 'Suelo −1', 'Suelo −2'],
          cfg.piso <= -2 ? 2 : (cfg.piso == -1 ? 1 : 0), t,
          (i) => onChanged(cfg.copyWith(piso: [0, -1, -2][i]))),
      const SizedBox(height: 6),
      _nota(
          cfg.piso == 0
              ? 'Con suelo 0 un desastre no resta: simplemente no suma.'
              : 'Con suelo ${cfg.piso} los hoyos malos restan puntos.',
          t),
    ];

/// La tabla resuelta, de albatros a desastre.
String _tablaEnPalabras(StablefordConfig cfg) {
  int p(int rel) {
    final bruto = cfg.puntosDelPar - rel;
    return bruto < cfg.piso ? cfg.piso : (bruto > cfg.techo ? cfg.techo : bruto);
  }

  return 'Eagle ${p(-2)} · Birdie ${p(-1)} · Par ${p(0)} · '
      'Bogey ${p(1)} · Doble ${p(2)} · Peor ${p(3)}';
}
