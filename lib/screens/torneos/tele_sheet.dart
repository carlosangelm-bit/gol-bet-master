// ─────────────────────────────────────────────────────────────────────────────
// LA PANTALLA DE LA CASA CLUB, DESDE EL LADO DEL ORGANIZADOR
//
// Dos superficies en un mismo sitio, y conviene que se lean como dos cosas
// distintas porque lo son:
//
//   · el enlace de WhatsApp   → pide cuenta, lleva el bote y los balances
//   · la pantalla de la tele  → se ve SIN cuenta, y no lleva un solo importe
//
// Por eso la pantalla se enciende aparte en vez de venir de regalo con el
// enlace: proyectar el torneo en una pared donde lo ve cualquiera que pase
// —incluido el que entrega los palos— es una decisión, no un efecto secundario
// de haber compartido una tabla por WhatsApp.
//
// Al revés no: APAGAR EL ENLACE APAGA TAMBIÉN LA PANTALLA. Si "dejar de
// compartir" dejara encendida la superficie MÁS expuesta de las dos, la frase
// del botón sería mentira. Lo hace [apagarTele], que llama el botón de "dejar
// de compartir" además del suyo propio.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../models/patrocinio.dart';
import '../../models/torneo.dart';
import '../../providers/torneo_provider.dart';
import '../../services/auth_service.dart';
import '../../services/tele_service.dart';

String enlaceDeTele(String token) => 'https://golf-bet-master.web.app/tv/$token';

/// Apaga la pantalla. La llama el botón de aquí y también el de "dejar de
/// compartir": ver la cabecera de este archivo.
Future<void> apagarTele(Torneo torneo) => Tele.apagar(torneo);

/// El bloque de la tele dentro de la hoja de compartir.
class BloqueTele extends StatefulWidget {
  final Torneo torneo;
  final TablaDelTorneo tabla;
  const BloqueTele({super.key, required this.torneo, required this.tabla});

  @override
  State<BloqueTele> createState() => _BloqueTeleState();
}

class _BloqueTeleState extends State<BloqueTele> {
  bool _trabajando = false;

  /// El torneo VIVO. La hoja puede quedarse abierta mientras se enciende la
  /// pantalla, y con la copia del argumento el botón seguiría diciendo
  /// "Encender" con la tele ya encendida — el bug del enlace, otra vez.
  Torneo get _t =>
      context.watch<TorneoProvider>().torneos.firstWhere(
            (x) => x.id == widget.torneo.id,
            orElse: () => widget.torneo,
          );

  Future<void> _encender() async {
    final uid = AuthService.uid;
    if (uid == null) return;
    setState(() => _trabajando = true);
    final prov = context.read<TorneoProvider>();
    final ahora = DateTime.now();
    final torneo = _t;
    final (resultado, token) = await Tele.publicar(
      ownerUid: uid,
      torneo: torneo,
      tabla: widget.tabla,
      cuando: ahora,
      encender: true,
    );
    if (resultado == ResultadoTele.publicada && token != null) {
      await prov.guardar(torneo.copyWith(tokenTele: token, teleDesde: ahora));
    }
    if (!mounted) return;
    setState(() => _trabajando = false);
    final mensajes = {
      ResultadoTele.publicada: 'Pantalla encendida. Abre el enlace en el '
          'navegador de la sala y ponlo a pantalla completa.',
      ResultadoTele.sinParticipantes: 'Define primero los participantes: '
          'proyectar una tabla con gente que no se inscribió lo empeora, y en '
          'una pared lo empeora delante de todo el club.',
      ResultadoTele.fallo: 'No se pudo encender la pantalla. El enlace de '
          'WhatsApp no se ha tocado.',
      ResultadoTele.apagada: '',
    };
    final frase = mensajes[resultado] ?? '';
    if (frase.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(frase), duration: const Duration(seconds: 5)));
    }
  }

  Future<void> _apagar() async {
    setState(() => _trabajando = true);
    final prov = context.read<TorneoProvider>();
    final torneo = _t;
    await Tele.apagar(torneo);
    // El TOKEN se conserva: volver a encender usa el mismo enlace, así que al
    // del club no hay que darle otro.
    await prov.guardar(torneo.copyWith(apagarTele: true));
    if (!mounted) return;
    setState(() => _trabajando = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Pantalla apagada. El mismo enlace vuelve a servir '
            'cuando la enciendas otra vez.'),
        duration: Duration(seconds: 4)));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.gt;
    final torneo = _t;
    final encendida = torneo.tokenTele != null && torneo.teleDesde != null;
    final piezas = torneo.inventario;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Divider(color: t.divider, height: 26),
      Row(children: [
        Icon(Icons.tv, size: 17, color: t.sub),
        const SizedBox(width: 7),
        Text('Pantalla de la casa club',
            style: TextStyle(
                color: t.text, fontSize: 15, fontWeight: FontWeight.w800)),
        const Spacer(),
        if (encendida)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: t.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20)),
            child: Text('En antena',
                style: TextStyle(
                    color: t.primary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800)),
          ),
      ]),
      const SizedBox(height: 6),
      Text(
          encendida
              // Lo que hace falta saber para no llevarse una sorpresa: esta es
              // la única superficie del sistema que se lee sin cuenta.
              ? 'Se ve SIN cuenta y se actualiza sola al cerrar cada ronda. No '
                  'muestra el bote ni ningún importe: es otro enlace y otra '
                  'tabla, no la de arriba en grande.'
              : 'Un enlace aparte para proyectar la clasificación en la tele '
                  'del club. Se ve SIN cuenta —por eso no lleva el bote ni '
                  'ningún importe— y se actualiza sola al cerrar cada ronda.',
          style: TextStyle(color: t.sub, fontSize: 12, height: 1.4)),
      const SizedBox(height: 12),
      if (encendida) ...[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: t.divider),
          ),
          child: SelectableText(enlaceDeTele(torneo.tokenTele!),
              style: TextStyle(color: t.text, fontSize: 12.5)),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(
                  ClipboardData(text: enlaceDeTele(torneo.tokenTele!)));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Enlace de la pantalla copiado')));
            },
            style: OutlinedButton.styleFrom(
                side: BorderSide(color: t.divider),
                foregroundColor: t.text,
                padding: const EdgeInsets.symmetric(vertical: 12)),
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copiar enlace de la pantalla'),
          ),
        ),
      ] else
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _trabajando ? null : _encender,
            style: OutlinedButton.styleFrom(
                side: BorderSide(color: t.divider),
                foregroundColor: t.text,
                padding: const EdgeInsets.symmetric(vertical: 12)),
            icon: const Icon(Icons.tv, size: 16),
            label: Text(_trabajando ? 'Encendiendo…' : 'Encender la pantalla'),
          ),
        ),
      const SizedBox(height: 8),
      // El inventario se puede preparar ANTES de encender: el patrocinio se
      // pacta antes de que se juegue nada.
      InkWell(
        onTap: () => abrirInventario(context, torneo),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          child: Row(children: [
            Icon(Icons.workspace_premium_outlined, size: 16, color: t.sub),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                  piezas.vacio
                      ? 'Añadir patrocinadores a la pantalla'
                      : 'Patrocinadores: ${_resumen(piezas)}',
                  style: TextStyle(color: t.sub, fontSize: 12.5)),
            ),
            Icon(Icons.chevron_right, size: 17, color: t.sub),
          ]),
        ),
      ),
      if (encendida) ...[
        const SizedBox(height: 2),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: _trabajando ? null : _apagar,
            style: TextButton.styleFrom(foregroundColor: t.sub),
            child: const Text('Apagar la pantalla'),
          ),
        ),
      ],
    ]);
  }

  static String _resumen(InventarioProyectado i) {
    final partes = <String>[
      if (i.cabecera != null) 'cabecera',
      if (i.pie.isNotEmpty) '${i.pie.length} en el pie',
      if (i.lateral != null) 'lateral',
    ];
    return partes.join(' · ');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EL INVENTARIO
//
// Tres espacios, los del §14.3 que hoy tienen origen. El ranking de oyes y el
// longest drive NO están: los mide alguien del staff en el campo y dependen de
// la web de organizador, que no existe. Cuando exista, entran aquí.
//
// Lo que el §6 del manual obliga y por eso no es opcional en el formulario: la
// ETIQUETA. Una pieza sin "Patrocinador oficial" —o lo que corresponda— pinta
// una marca sin decir que es publicidad, y eso es lo que el manual prohíbe.
// ─────────────────────────────────────────────────────────────────────────────
Future<void> abrirInventario(BuildContext context, Torneo torneo) async {
  final prov = context.read<TorneoProvider>();
  final nuevo = await Navigator.of(context).push<InventarioProyectado>(
    MaterialPageRoute(builder: (_) => InventarioScreen(torneo: torneo)),
  );
  if (nuevo == null) return;
  final vivo = prov.torneos.firstWhere((x) => x.id == torneo.id,
      orElse: () => torneo);
  await prov.guardar(vivo.copyWith(inventario: nuevo));
}

class InventarioScreen extends StatefulWidget {
  final Torneo torneo;
  const InventarioScreen({super.key, required this.torneo});

  @override
  State<InventarioScreen> createState() => _InventarioScreenState();
}

class _InventarioScreenState extends State<InventarioScreen> {
  late PiezaDePatrocinio? _cabecera = widget.torneo.inventario.cabecera;
  late PiezaDePatrocinio? _lateral = widget.torneo.inventario.lateral;
  late List<PiezaDePatrocinio> _pie = [...widget.torneo.inventario.pie];
  late int _rotacion = widget.torneo.inventario.segundosDeRotacion;

  InventarioProyectado get _actual => InventarioProyectado(
        cabecera: _cabecera,
        pie: _pie,
        lateral: _lateral,
        segundosDeRotacion: _rotacion,
      );

  Future<void> _editar({
    required String espacio,
    required String ayuda,
    required PiezaDePatrocinio? pieza,
    required void Function(PiezaDePatrocinio?) alGuardar,
  }) async {
    final r = await showModalBottomSheet<(bool, PiezaDePatrocinio?)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.gt.bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) =>
          _EditorDePieza(espacio: espacio, ayuda: ayuda, pieza: pieza),
    );
    if (r == null) return;
    alGuardar(r.$2);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = context.gt;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        foregroundColor: t.text,
        title: const Text('Patrocinadores de la pantalla'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _actual),
            child: const Text('Guardar',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
              'Lo que aparece en la tele del club. Un espacio sin patrocinador '
              'no deja hueco: simplemente no se dibuja.',
              style: TextStyle(color: t.sub, fontSize: 12.5, height: 1.4)),
          const SizedBox(height: 8),
          // El móvil edita los textos; los archivos son del portal. Cargar
          // creatividades desde un teléfono no es lo que hace un organizador.
          Text(
              'Los logotipos se suben desde el portal de organizador, en un '
              'navegador. Aquí puedes ajustar los textos.',
              style: TextStyle(color: t.sub, fontSize: 11.5, height: 1.35)),
          const SizedBox(height: 18),
          _Espacio(
            titulo: 'Cabecera',
            nota: 'Banner ancho, siempre visible. El titular del torneo.',
            pieza: _cabecera,
            onTap: () => _editar(
                espacio: 'Cabecera',
                ayuda: 'Es la pieza más vista del día: está en pantalla las '
                    'ocho horas. Una marca, un mensaje, una acción.',
                pieza: _cabecera,
                alGuardar: (p) => _cabecera = p),
          ),
          _Espacio(
            titulo: 'Pie rotatorio',
            nota: _pie.isEmpty
                ? 'Los socios del evento. Rotan entre sí.'
                : '${_pie.length} ${_pie.length == 1 ? "socio" : "socios"} · '
                    'cambia cada $_rotacion s',
            pieza: null,
            resumen: _pie.map((p) => p.titular.isEmpty ? p.etiqueta : p.titular)
                .join(' · '),
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => _PieScreen(
                        piezas: _pie,
                        segundos: _rotacion,
                        alCambiar: (lista, seg) =>
                            setState(() { _pie = lista; _rotacion = seg; }),
                      )));
              if (mounted) setState(() {});
            },
          ),
          _Espacio(
            titulo: 'Lateral',
            nota: 'Columna 300×600. Solo aparece si la pantalla es ancha; en '
                'una más estrecha desaparece antes de comprimir la tabla.',
            pieza: _lateral,
            onTap: () => _editar(
                espacio: 'Lateral',
                ayuda: 'Formato alto. Si la tele del club es 16:9 normal, '
                    'esta columna se ve; en una pantalla estrecha no.',
                pieza: _lateral,
                alGuardar: (p) => _lateral = p),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.divider)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, size: 16, color: t.sub),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                    'La etiqueta ("Patrocinador oficial", "Presentado por"…) es '
                    'obligatoria en cada pieza: sin ella se pinta una marca sin '
                    'decir que es publicidad.\n\n'
                    'Para subir logotipos, abre el portal de organizador desde '
                    'un navegador: /organizador/{id del torneo}.',
                    style:
                        TextStyle(color: t.sub, fontSize: 11.5, height: 1.45)),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Espacio extends StatelessWidget {
  final String titulo;
  final String nota;
  final PiezaDePatrocinio? pieza;
  final String? resumen;
  final VoidCallback onTap;
  const _Espacio({
    required this.titulo,
    required this.nota,
    required this.pieza,
    required this.onTap,
    this.resumen,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.gt;
    final texto = resumen ??
        (pieza == null
            ? ''
            : (pieza!.titular.isEmpty ? pieza!.etiqueta : pieza!.titular));
    final lleno = texto.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: lleno ? t.primary : t.divider),
          ),
          child: Row(children: [
            Expanded(
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titulo,
                    style: TextStyle(
                        color: t.text,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(lleno ? texto : nota,
                    style: TextStyle(
                        color: lleno ? t.primary : t.sub,
                        fontSize: 12,
                        height: 1.35,
                        fontWeight:
                            lleno ? FontWeight.w700 : FontWeight.w400)),
              ]),
            ),
            Icon(lleno ? Icons.edit : Icons.add, size: 17, color: t.sub),
          ]),
        ),
      ),
    );
  }
}

class _PieScreen extends StatefulWidget {
  final List<PiezaDePatrocinio> piezas;
  final int segundos;
  final void Function(List<PiezaDePatrocinio>, int) alCambiar;
  const _PieScreen({
    required this.piezas,
    required this.segundos,
    required this.alCambiar,
  });

  @override
  State<_PieScreen> createState() => _PieScreenState();
}

class _PieScreenState extends State<_PieScreen> {
  late final List<PiezaDePatrocinio> _lista = [...widget.piezas];
  late int _seg = widget.segundos;

  void _propagar() => widget.alCambiar(_lista, _seg);

  Future<void> _editar(int? indice) async {
    final r = await showModalBottomSheet<(bool, PiezaDePatrocinio?)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.gt.bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EditorDePieza(
          espacio: 'Socio del evento',
          ayuda: 'Los socios rotan entre sí en el pie de la pantalla. Aquí la '
              'rotación sí está permitida: en una TV es lo esperado, y no '
              'compite con ningún control.',
          pieza: indice == null ? null : _lista[indice]),
    );
    if (r == null) return;
    setState(() {
      if (r.$2 == null) {
        if (indice != null) _lista.removeAt(indice);
      } else if (indice == null) {
        _lista.add(r.$2!);
      } else {
        _lista[indice] = r.$2!;
      }
    });
    _propagar();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.gt;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
          backgroundColor: t.bg,
          foregroundColor: t.text,
          title: const Text('Socios del evento')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          for (var i = 0; i < _lista.length; i++)
            _Espacio(
              titulo: _lista[i].etiqueta,
              nota: '',
              pieza: _lista[i],
              onTap: () => _editar(i),
            ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _editar(null),
              style: OutlinedButton.styleFrom(
                  side: BorderSide(color: t.divider),
                  foregroundColor: t.text,
                  padding: const EdgeInsets.symmetric(vertical: 13)),
              icon: const Icon(Icons.add, size: 17),
              label: const Text('Añadir socio'),
            ),
          ),
          if (_lista.length > 1) ...[
            const SizedBox(height: 22),
            Text('Cambia cada $_seg segundos',
                style: TextStyle(
                    color: t.text, fontSize: 13.5, fontWeight: FontWeight.w700)),
            Slider(
              value: _seg.toDouble().clamp(5, 60),
              min: 5,
              max: 60,
              divisions: 11,
              label: '$_seg s',
              onChanged: (v) => setState(() => _seg = v.round()),
              onChangeEnd: (_) => _propagar(),
            ),
            Text(
                'Demasiado rápido no da tiempo a leer la marca; demasiado lento '
                'y los últimos socios casi no salen.',
                style: TextStyle(color: t.sub, fontSize: 11.5, height: 1.4)),
          ],
        ],
      ),
    );
  }
}

/// El formulario de una pieza. Devuelve `(true, pieza)` o `(true, null)` al
/// quitarla; null si se cancela.
class _EditorDePieza extends StatefulWidget {
  final String espacio;
  final String ayuda;
  final PiezaDePatrocinio? pieza;
  const _EditorDePieza({
    required this.espacio,
    required this.ayuda,
    required this.pieza,
  });

  @override
  State<_EditorDePieza> createState() => _EditorDePiezaState();
}

class _EditorDePiezaState extends State<_EditorDePieza> {
  late final _etiqueta =
      TextEditingController(text: widget.pieza?.etiqueta ?? '');
  late final _titular = TextEditingController(text: widget.pieza?.titular ?? '');
  late final _logo = TextEditingController(text: widget.pieza?.logoUrl ?? '');
  late final _cta = TextEditingController(text: widget.pieza?.cta ?? '');
  late final _destino =
      TextEditingController(text: widget.pieza?.destinoUrl ?? '');
  late final _alt =
      TextEditingController(text: widget.pieza?.textoAlternativo ?? '');

  @override
  void dispose() {
    for (final c in [_etiqueta, _titular, _logo, _cta, _destino, _alt]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Las siete palabras del §6.2. Se AVISA, no se recorta: cortar el titular en
  /// silencio convierte un incumplimiento en una frase a medias.
  int get _palabras =>
      _titular.text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  bool get _valida =>
      _etiqueta.text.trim().isNotEmpty &&
      (_titular.text.trim().isNotEmpty || _logo.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final t = context.gt;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 18, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(widget.espacio,
                style: TextStyle(
                    color: t.text, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(widget.ayuda,
                textAlign: TextAlign.center,
                style: TextStyle(color: t.sub, fontSize: 12, height: 1.4)),
            const SizedBox(height: 16),
            _campo(t, _etiqueta, 'Etiqueta de patrocinio *',
                'Patrocinador oficial', obligatorio: true),
            _campo(t, _titular, 'Titular', 'Eleva cada gran ronda'),
            if (_palabras > 7)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                    'El manual pide siete palabras como máximo; van $_palabras. '
                    'Se guarda igual — recortarlo aquí en silencio dejaría una '
                    'frase a medias en la pared.',
                    style: TextStyle(
                        color: t.danger, fontSize: 11.5, height: 1.4)),
              ),
            _campo(t, _logo, 'URL del logotipo', 'https://…/logo.svg'),
            _campo(t, _alt, 'Texto alternativo del logotipo',
                'Logotipo de la marca'),
            _campo(t, _cta, 'Llamada a la acción', 'Conoce la experiencia'),
            _campo(t, _destino, 'Enlace de destino', 'https://…'),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    _valida ? () => Navigator.pop(context, (true, _armar())) : null,
                style: ElevatedButton.styleFrom(
                    backgroundColor: t.primary,
                    foregroundColor: t.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 13)),
                child: const Text('Guardar',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            if (!_valida)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    'Hace falta la etiqueta y, al menos, un titular o un '
                    'logotipo: sin nada que dibujar la pieza no se pinta.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.sub, fontSize: 11.5)),
              ),
            if (widget.pieza != null)
              TextButton(
                onPressed: () => Navigator.pop(context, (true, null)),
                style: TextButton.styleFrom(foregroundColor: t.sub),
                child: const Text('Quitar de la pantalla'),
              ),
          ]),
        ),
      ),
    );
  }

  PiezaDePatrocinio _armar() => PiezaDePatrocinio(
        etiqueta: _etiqueta.text.trim(),
        titular: _titular.text.trim(),
        logoUrl: _logo.text.trim(),
        cta: _cta.text.trim().isEmpty ? null : _cta.text.trim(),
        destinoUrl: _destino.text.trim().isEmpty ? null : _destino.text.trim(),
        textoAlternativo: _alt.text.trim().isEmpty ? null : _alt.text.trim(),
      );

  Widget _campo(GolfTheme t, TextEditingController c, String etiqueta,
      String ejemplo,
      {bool obligatorio = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        onChanged: (_) => setState(() {}),
        style: TextStyle(color: t.text, fontSize: 14),
        decoration: InputDecoration(
          labelText: etiqueta,
          hintText: ejemplo,
          labelStyle: TextStyle(
              color: obligatorio && c.text.trim().isEmpty ? t.danger : t.sub,
              fontSize: 13),
          hintStyle: TextStyle(color: t.sub.withValues(alpha: 0.5), fontSize: 13),
          filled: true,
          fillColor: t.surface,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: t.divider)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: t.divider)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }
}
