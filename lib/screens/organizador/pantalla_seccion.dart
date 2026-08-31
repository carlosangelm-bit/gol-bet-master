// ─────────────────────────────────────────────────────────────────────────────
// LA PANTALLA — dónde el organizador elige cómo se ve su torneo proyectado
//
// ── Por qué es una sección APARTE de Patrocinio, y no una pestaña suya ──────
//
// Las dos deciden cosas de la misma pared, así que la tentación es juntarlas.
// Son distintas en lo que importa:
//
//   · Patrocinio es INVENTARIO: archivos que se suben, se enseñan un fin de
//     semana y se borran después. Es contenido, y tiene un borrado explícito.
//   · Esto es un AJUSTE: tres decisiones que se toman una vez y se quedan.
//     No hay nada que borrar.
//
// Juntarlas pondría un botón de borrar archivos al lado de un selector de
// color, y el día del torneo, con prisa, esa vecindad es cara.
//
// ── Y por qué no hay selector de color libre para el fondo ──────────────────
//
// Ver la cabecera de plantilla_de_tele.dart: el acento es libre porque es la
// marca del organizador, y el fondo no porque es lo que decide si la pantalla
// se lee. Aquí eso se traduce en dos controles con forma distinta a propósito:
// el fondo es una elección entre tres, el acento es un color.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ancho.dart';
import '../../core/app_theme.dart';
import '../../core/golf_icons.dart';
import '../../models/torneo.dart';
import '../../providers/torneo_provider.dart';

class PantallaSeccion extends StatelessWidget {
  final Torneo torneo;
  final Ancho ancho;
  final GolfTheme t;
  const PantallaSeccion({
    super.key,
    required this.torneo,
    required this.ancho,
    required this.t,
  });

  Future<void> _guardar(BuildContext context, IdentidadDeTorneo id) async {
    final prov = context.read<TorneoProvider>();
    final vivo = prov.torneos
        .firstWhere((x) => x.id == torneo.id, orElse: () => torneo);
    await prov.guardar(vivo.copyWith(identidad: id));
  }

  @override
  Widget build(BuildContext context) {
    final id = torneo.identidad;
    final plantilla = PlantillasDeTele.deClave(id.plantilla);
    final ancha = ancho.esTabla;

    return ListView(
      padding: EdgeInsets.fromLTRB(ancha ? 24 : 14, 16, ancha ? 24 : 14, 32),
      children: [
        Text(
            'Cómo se ve tu torneo en la pantalla del club. El tamaño del texto '
            'y el orden de las columnas no cambian: eso es lo que hace que se '
            'lea desde el otro lado del salón.',
            style: TextStyle(color: t.sub, fontSize: 12.5, height: 1.4)),
        const SizedBox(height: 18),

        // ── La vista previa, arriba ────────────────────────────────────────
        //
        // Antes de los controles y no después: quien viene a cambiar el color
        // quiere ver el resultado, y un selector encima de una previa que hay
        // que ir a buscar es lo que produce el "lo dejo como estaba".
        _Previa(identidad: id, t: t),
        const SizedBox(height: 22),

        _Etiqueta('DISEÑO', t: t),
        const SizedBox(height: 8),
        for (final p in PlantillasDeTele.todas)
          _OpcionDePlantilla(
            plantilla: p,
            elegida: p.clave == plantilla.clave,
            t: t,
            // Al cambiar de plantilla la profundidad se conserva y el acento
            // NO: el acento por defecto es parte de la identidad de cada
            // diseño, y arrastrar el anterior daría una mezcla que nadie eligió.
            onTap: () => _guardar(
                context, id.copyWith(plantilla: p.clave, borrarAcento: true)),
          ),

        const SizedBox(height: 22),
        _Etiqueta('FONDO', t: t),
        const SizedBox(height: 4),
        Text('Tres profundidades del diseño elegido. Las tres se leen.',
            style: TextStyle(color: t.sub, fontSize: 11.5)),
        const SizedBox(height: 8),
        Row(children: [
          for (var i = 0; i < PlantillaDeTele.profundidades; i++) ...[
            Expanded(
              child: _Muestra(
                color: plantilla.fondos[i],
                elegida: id.profundidad == i,
                t: t,
                onTap: () => _guardar(context, id.copyWith(profundidad: i)),
              ),
            ),
            if (i < PlantillaDeTele.profundidades - 1)
              const SizedBox(width: 8),
          ],
        ]),

        const SizedBox(height: 22),
        _Etiqueta('COLOR DEL TORNEO', t: t),
        const SizedBox(height: 4),
        Text(
            'El color de tu marca. Si no contrasta con el fondo se aclara u '
            'oscurece lo justo para que se vea — el tono no cambia.',
            style: TextStyle(color: t.sub, fontSize: 11.5, height: 1.35)),
        const SizedBox(height: 8),
        _ElegirAcento(
          plantilla: plantilla,
          identidad: id,
          t: t,
          onColor: (c) => _guardar(
              context,
              c == null
                  ? id.copyWith(borrarAcento: true)
                  : id.copyWith(acento: c.toARGB32())),
        ),
      ],
    );
  }
}

/// La previa: la misma cuenta que hace la pantalla real.
///
/// No es una maqueta con colores parecidos — llama a `identidad.piel`, que es
/// exactamente lo que usa la tele. Una previa que no comparte el cálculo acaba
/// enseñando algo que la pared no enseña.
class _Previa extends StatelessWidget {
  final IdentidadDeTorneo identidad;
  final GolfTheme t;
  const _Previa({required this.identidad, required this.t});

  @override
  Widget build(BuildContext context) {
    final p = identidad.piel;
    // Las tres filas de ejemplo llevan un bajo par, un par y un sobre par: es
    // lo que hay que poder juzgar de un vistazo, y con tres iguales no se ve.
    const ejemplo = [
      (1, 'Ana Robles', -7, '3/3'),
      (2, 'Beto Lara', 0, '3/3'),
      (3, 'Caro Díaz', 4, '2/3'),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.fondo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(GolfIcons.trofeo, size: GolfIcons.juntoAValor, color: p.acento),
          const SizedBox(width: 6),
          Text('Tu torneo',
              style: TextStyle(
                  color: p.texto, fontSize: 15, fontWeight: FontWeight.w900)),
          const Spacer(),
          Text('3 rondas',
              style: TextStyle(color: p.textoSuave, fontSize: 10)),
        ]),
        const SizedBox(height: 8),
        for (final (puesto, nombre, bajo, thru) in ejemplo)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: puesto <= 3 ? p.filaPodio : p.fila,
              borderRadius: BorderRadius.circular(6),
              border: puesto == 1
                  ? Border(bottom: BorderSide(color: p.separador, width: 2))
                  : null,
            ),
            child: Row(children: [
              SizedBox(
                width: 20,
                child: Text('$puesto',
                    style: TextStyle(
                        color: p.acento,
                        fontSize: 13,
                        fontWeight: FontWeight.w900)),
              ),
              Expanded(
                child: Text(nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.texto,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
              Text(thru,
                  style: TextStyle(color: p.textoSuave, fontSize: 10)),
              const SizedBox(width: 10),
              SizedBox(
                width: 30,
                child: Text(bajo == 0 ? 'E' : (bajo > 0 ? '+$bajo' : '$bajo'),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        color: bajo < 0 ? p.bajoPar : p.texto,
                        fontSize: 14,
                        fontWeight: FontWeight.w900)),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  final String texto;
  final GolfTheme t;
  const _Etiqueta(this.texto, {required this.t});

  @override
  Widget build(BuildContext context) => Text(texto,
      style: GolfType.label(t.sub));
}

class _OpcionDePlantilla extends StatelessWidget {
  final PlantillaDeTele plantilla;
  final bool elegida;
  final GolfTheme t;
  final VoidCallback onTap;
  const _OpcionDePlantilla({
    required this.plantilla,
    required this.elegida,
    required this.t,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final piel = plantilla.resolver();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: elegida ? t.primary.withValues(alpha: 0.10) : t.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: elegida ? t.primary : t.divider,
              width: elegida ? 1.5 : 1),
        ),
        child: Row(children: [
          // La muestra dice más que el nombre: "Retransmisión" no se imagina.
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: piel.fondo,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: t.divider),
            ),
            alignment: Alignment.center,
            child: Container(
              width: 14,
              height: 4,
              decoration: BoxDecoration(
                color: piel.acento,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(plantilla.nombre,
                  style: TextStyle(
                      color: elegida ? t.primary : t.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800)),
              Text(plantilla.paraQue,
                  style: TextStyle(color: t.sub, fontSize: 11.5, height: 1.3)),
            ]),
          ),
          if (elegida)
            Icon(Icons.check_circle, color: t.primary, size: 18)
          else
            Icon(Icons.radio_button_unchecked, color: t.divider, size: 18),
        ]),
      ),
    );
  }
}

class _Muestra extends StatelessWidget {
  final Color color;
  final bool elegida;
  final GolfTheme t;
  final VoidCallback onTap;
  const _Muestra({
    required this.color,
    required this.elegida,
    required this.t,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
                color: elegida ? t.primary : t.divider,
                width: elegida ? 2 : 1),
          ),
          alignment: Alignment.center,
          child: elegida
              ? Icon(Icons.check, color: t.primary, size: 16)
              : null,
        ),
      );
}

/// El acento: los de la plantilla más los que un torneo corporativo necesita.
///
/// La rejilla ofrece un punto de partida —y el "el de la plantilla", que es el
/// que devuelve a cero—. La cuadrícula no pretende cubrir todas las marcas: es
/// lo que hace que la mayoría no tenga que pensar.
class _ElegirAcento extends StatelessWidget {
  final PlantillaDeTele plantilla;
  final IdentidadDeTorneo identidad;
  final GolfTheme t;
  final void Function(Color?) onColor;
  const _ElegirAcento({
    required this.plantilla,
    required this.identidad,
    required this.t,
    required this.onColor,
  });

  static const _colores = <Color>[
    Color(0xFF6FE39A), Color(0xFF4FA8FF), Color(0xFFE8B84B),
    Color(0xFFFF8A5B), Color(0xFFB68CFF), Color(0xFF00C2B2),
    Color(0xFFFF5A8A), Color(0xFFC9D1D9),
  ];

  @override
  Widget build(BuildContext context) {
    final fondo = plantilla.fondos[
        identidad.profundidad.clamp(0, plantilla.fondos.length - 1)];
    return Wrap(spacing: 8, runSpacing: 8, children: [
      _Punto(
        color: plantilla.acentoPorDefecto,
        fondo: fondo,
        elegido: identidad.acento == null,
        t: t,
        onTap: () => onColor(null),
      ),
      for (final c in _colores)
        _Punto(
          color: c,
          fondo: fondo,
          elegido: identidad.acento == c.toARGB32(),
          t: t,
          onTap: () => onColor(c),
        ),
    ]);
  }
}

class _Punto extends StatelessWidget {
  final Color color;
  final Color fondo;
  final bool elegido;
  final GolfTheme t;
  final VoidCallback onTap;
  const _Punto({
    required this.color,
    required this.fondo,
    required this.elegido,
    required this.t,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Se enseña el color YA CORREGIDO. Enseñar el elegido y proyectar otro
    // sería la peor de las dos opciones: el organizador cree que eligió algo
    // que la pared nunca va a enseñar.
    final real = PlantillaDeTele.corregirContra(color, fondo);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: real,
          shape: BoxShape.circle,
          border: Border.all(
              color: elegido ? t.text : t.divider, width: elegido ? 2.5 : 1),
        ),
      ),
    );
  }
}
