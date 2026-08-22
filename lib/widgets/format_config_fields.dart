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
