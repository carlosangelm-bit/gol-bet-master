// ─────────────────────────────────────────────────────────────────────────────
// PATROCINIO — el inventario, desde el portal
//
// Es lo que Carlos vende, y hasta ahora solo se podía configurar desde el móvil:
// un organizador cargando creatividades desde un teléfono no es un producto.
//
// ── Lo que esta pantalla PIDE, y por qué se pide todo ───────────────────────
//
// Los activos del §11 salen de una lista en el modelo, no de aquí, para que el
// día que el manual añada uno se añada en un sitio. De esa lista, dos cosas no
// son opcionales y se tratan distinto:
//
//   · La ETIQUETA de patrocinio. Sin ella se pinta una marca sin decir que es
//     publicidad, que es lo que el §6 prohíbe. Bloquea el guardado.
//   · El TITULAR de más de siete palabras se AVISA, no se recorta. Recortarlo en
//     silencio convierte un incumplimiento en media frase en la pared del club.
//
// ── Y el archivo se sube, no se enlaza ──────────────────────────────────────
//
// Decisión de Carlos. Una URL al servidor del patrocinador es gratis y es peor:
// el día que la marca cambie su web, el banner que pagaron desaparece de la
// pantalla. Con el archivo en Storage la imagen es nuestra.
//
// El borrado es EXPLÍCITO y del organizador. Nada limpia esto solo, ni al cerrar
// el torneo: un torneo puede querer conservar su resumen con los patrocinadores
// dentro mucho después.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ancho.dart';
import '../../core/app_theme.dart';
import '../../models/patrocinio.dart';
import '../../models/torneo.dart';
import '../../providers/torneo_provider.dart';
import '../../services/patrocinio_storage.dart';

class PatrocinioSeccion extends StatelessWidget {
  final Torneo torneo;
  final Ancho ancho;
  final GolfTheme t;
  const PatrocinioSeccion({
    super.key,
    required this.torneo,
    required this.ancho,
    required this.t,
  });

  Future<void> _guardar(BuildContext context, InventarioProyectado inv) async {
    final prov = context.read<TorneoProvider>();
    final vivo = prov.torneos
        .firstWhere((x) => x.id == torneo.id, orElse: () => torneo);
    await prov.guardar(vivo.copyWith(inventario: inv));
  }

  @override
  Widget build(BuildContext context) {
    final inv = torneo.inventario;
    return ListView(
      padding: EdgeInsets.fromLTRB(
          ancho.esTabla ? 24 : 14, 16, ancho.esTabla ? 24 : 14, 32),
      children: [
        Text(
            'Lo que se ve en la pantalla del club. Un espacio sin patrocinador '
            'no deja hueco: simplemente no se dibuja.',
            style: TextStyle(color: t.sub, fontSize: 12.5, height: 1.4)),
        const SizedBox(height: 18),
        _Espacio(
          espacio: EspacioDePatrocinio.cabecera,
          torneo: torneo,
          t: t,
          piezas: inv.cabecera == null ? const [] : [inv.cabecera!],
          onCambio: (lista) => _guardar(
              context, _con(inv, cabecera: lista.isEmpty ? null : lista.first)),
        ),
        _Espacio(
          espacio: EspacioDePatrocinio.pie,
          torneo: torneo,
          t: t,
          piezas: inv.pie,
          varias: true,
          onCambio: (lista) => _guardar(context, _con(inv, pie: lista)),
        ),
        if (inv.pie.length > 1) ...[
          const SizedBox(height: 4),
          _Rotacion(
            segundos: inv.segundosDeRotacion,
            t: t,
            onCambio: (s) => _guardar(context, _con(inv, segundos: s)),
          ),
        ],
        _Espacio(
          espacio: EspacioDePatrocinio.lateral,
          torneo: torneo,
          t: t,
          piezas: inv.lateral == null ? const [] : [inv.lateral!],
          onCambio: (lista) => _guardar(
              context, _con(inv, lateral: lista.isEmpty ? null : lista.first)),
        ),
        const SizedBox(height: 22),
        _Nota(t: t),
      ],
    );
  }

  /// Un copyWith para el inventario, que no lo tiene.
  ///
  /// Con banderas explícitas de limpieza: sin ellas, quitar la cabecera es
  /// indistinguible de no tocarla, que es el fallo clásico de los copyWith con
  /// nulos.
  static InventarioProyectado _con(
    InventarioProyectado i, {
    PiezaDePatrocinio? cabecera,
    List<PiezaDePatrocinio>? pie,
    PiezaDePatrocinio? lateral,
    int? segundos,
    bool tocaCabecera = true,
    bool tocaLateral = true,
  }) =>
      InventarioProyectado(
        cabecera: tocaCabecera ? cabecera : i.cabecera,
        pie: pie ?? i.pie,
        lateral: tocaLateral ? lateral : i.lateral,
        segundosDeRotacion: segundos ?? i.segundosDeRotacion,
      );
}

class _Rotacion extends StatelessWidget {
  final int segundos;
  final GolfTheme t;
  final void Function(int) onCambio;
  const _Rotacion(
      {required this.segundos, required this.t, required this.onCambio});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 4, right: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Los logotipos del pie cambian cada $segundos segundos',
              style: TextStyle(
                  color: t.text, fontSize: 12.5, fontWeight: FontWeight.w700)),
          Slider(
            value: segundos.toDouble().clamp(5, 60),
            min: 5,
            max: 60,
            divisions: 11,
            label: '$segundos s',
            onChanged: (v) => onCambio(v.round()),
          ),
          Text(
              'Demasiado rápido no da tiempo a leer la marca; demasiado lento y '
              'los últimos socios casi no salen.',
              style: TextStyle(color: t.sub, fontSize: 11.5, height: 1.35)),
        ]),
      );
}

class _Espacio extends StatelessWidget {
  final EspacioDePatrocinio espacio;
  final Torneo torneo;
  final GolfTheme t;
  final List<PiezaDePatrocinio> piezas;
  final bool varias;
  final void Function(List<PiezaDePatrocinio>) onCambio;
  const _Espacio({
    required this.espacio,
    required this.torneo,
    required this.t,
    required this.piezas,
    required this.onCambio,
    this.varias = false,
  });

  Future<void> _editar(BuildContext context, int? indice) async {
    final r = await showModalBottomSheet<(bool, PiezaDePatrocinio?)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => EditorDePieza(
          espacio: espacio,
          torneoId: torneo.id,
          pieza: indice == null ? null : piezas[indice],
          t: t),
    );
    if (r == null) return;
    final lista = [...piezas];
    if (r.$2 == null) {
      if (indice != null) lista.removeAt(indice);
    } else if (indice == null) {
      lista.add(r.$2!);
    } else {
      lista[indice] = r.$2!;
    }
    onCambio(lista);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: piezas.isEmpty ? t.divider : t.primary),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Wrap y no Row: en 390 px "Pie rotatorio" más "240 × 60 por
          // logotipo" no caben en una línea, y un Row se desbordaba 116 px. La
          // medida no se puede recortar —es lo que hay que pedirle a la marca—
          // así que baja de línea.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(espacio.titulo,
                  style: TextStyle(
                      color: t.text, fontSize: 15, fontWeight: FontWeight.w800)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: t.card, borderRadius: BorderRadius.circular(6)),
                child: Text(espacio.medida,
                    style: TextStyle(
                        color: t.sub,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(espacio.donde,
              style: TextStyle(color: t.sub, fontSize: 11.5, height: 1.35)),
          const SizedBox(height: 12),
          for (var i = 0; i < piezas.length; i++)
            _Tarjeta(
              pieza: piezas[i],
              t: t,
              onTap: () => _editar(context, i),
            ),
          if (piezas.isEmpty || varias)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _editar(context, null),
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: t.divider),
                    foregroundColor: t.text,
                    padding: const EdgeInsets.symmetric(vertical: 12)),
                icon: const Icon(Icons.add, size: 17),
                label: Text(piezas.isEmpty
                    ? 'Añadir patrocinador'
                    : 'Añadir otro socio'),
              ),
            ),
        ]),
      ),
    );
  }
}

class _Tarjeta extends StatelessWidget {
  final PiezaDePatrocinio pieza;
  final GolfTheme t;
  final VoidCallback onTap;
  const _Tarjeta({required this.pieza, required this.t, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.divider)),
            child: Row(children: [
              if (pieza.logoUrl.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(pieza.logoUrl,
                      width: 54,
                      height: 34,
                      fit: BoxFit.contain,
                      // Una imagen que no carga se dice. Un hueco callado en la
                      // pantalla del organizador es un banner roto en la pared.
                      errorBuilder: (_, __, ___) => Tooltip(
                          message: 'El archivo está subido, pero el navegador '
                              'no lo deja pintar. Suele ser el CORS del '
                              'bucket: ver DESPLIEGUE.md.',
                          child: Icon(Icons.broken_image,
                              size: 22, color: t.sub))),
                ),
                const SizedBox(width: 11),
              ],
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pieza.etiqueta.toUpperCase(),
                          style: TextStyle(
                              color: t.sub,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8)),
                      if (pieza.titular.isNotEmpty)
                        Text(pieza.titular,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: t.text,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700)),
                      if (pieza.logoUrl.isEmpty)
                        Text('Sin logotipo',
                            style: TextStyle(color: t.sub, fontSize: 11)),
                    ]),
              ),
              Icon(Icons.edit, size: 16, color: t.sub),
            ]),
          ),
        ),
      );
}

class _Nota extends StatelessWidget {
  final GolfTheme t;
  const _Nota({required this.t});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: t.divider)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('LO QUE PEDIRLE AL PATROCINADOR', style: GolfType.label(t.sub)),
          const SizedBox(height: 9),
          for (final a in activosDelPatrocinador) ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(a.obligatorio ? Icons.star : Icons.circle,
                  size: a.obligatorio ? 12 : 5,
                  color: a.obligatorio ? t.primary : t.sub),
              const SizedBox(width: 8),
              Expanded(
                child: RichText(
                  text: TextSpan(children: [
                    TextSpan(
                        text: '${a.etiqueta} — ',
                        style: TextStyle(
                            color: t.text,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700)),
                    TextSpan(
                        text: a.porQue,
                        style: TextStyle(
                            color: t.sub, fontSize: 11.5, height: 1.35)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 7),
          ],
          const SizedBox(height: 2),
          Text(
              'Los archivos se guardan con este torneo y se borran cuando tú lo '
              'pidas: no se limpian solos al cerrarlo.',
              style: TextStyle(color: t.sub, fontSize: 11, height: 1.35)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// EL FORMULARIO DE UNA PIEZA
// ─────────────────────────────────────────────────────────────────────────────

/// Devuelve `(true, pieza)`, `(true, null)` al quitarla, o null si se cancela.
class EditorDePieza extends StatefulWidget {
  final EspacioDePatrocinio espacio;
  final String torneoId;
  final PiezaDePatrocinio? pieza;
  final GolfTheme t;

  /// Para tests: evita abrir el selector de archivos del sistema.
  final Future<PlatformFile?> Function()? elegirArchivo;

  const EditorDePieza({
    super.key,
    required this.espacio,
    required this.torneoId,
    required this.pieza,
    required this.t,
    this.elegirArchivo,
  });

  @override
  State<EditorDePieza> createState() => _EditorDePiezaState();
}

class _EditorDePiezaState extends State<EditorDePieza> {
  late final _etiqueta =
      TextEditingController(text: widget.pieza?.etiqueta ?? '');
  late final _titular = TextEditingController(text: widget.pieza?.titular ?? '');
  late final _cta = TextEditingController(text: widget.pieza?.cta ?? '');
  late final _destino =
      TextEditingController(text: widget.pieza?.destinoUrl ?? '');
  late final _alt =
      TextEditingController(text: widget.pieza?.textoAlternativo ?? '');

  late String _logo = widget.pieza?.logoUrl ?? '';
  bool _subiendo = false;
  String? _aviso;

  /// El archivo con el que se entró. Nunca cambia.
  ///
  /// ── El huérfano que se estaba creando ─────────────────────────────────────
  ///
  /// Reemplazar subía un archivo nuevo y dejaba el viejo en Storage para
  /// siempre. Se vio en la primera subida real: dos archivos de 49 KB en la
  /// misma carpeta, y solo uno en uso.
  ///
  /// Y es justo lo que este diseño venía a evitar —"los torneos usan sus
  /// activos y los borran después"—, porque el que sobra ya no lo conoce nadie:
  /// el modelo guarda una sola URL, y la regla no deja listar la carpeta para
  /// encontrarlo.
  ///
  /// Así que se limpia en el momento, y hacia el lado que toque:
  ///
  ///   · al GUARDAR   → sobra el viejo, se borra el viejo
  ///   · al SALIR sin guardar → sobra el nuevo, se borra el nuevo
  late final String _urlOriginal = widget.pieza?.logoUrl ?? '';
  bool _guardado = false;

  @override
  void dispose() {
    // Sin guardar y con archivo nuevo: el nuevo es el que sobra. Sin await, que
    // dispose no espera a nadie; si falla queda un huérfano, que es exactamente
    // lo que había antes en todos los casos.
    if (!_guardado && _logo != _urlOriginal && _logo.isNotEmpty) {
      PatrocinioStorage.borrar(_logo);
    }
    for (final c in [_etiqueta, _titular, _cta, _destino, _alt]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Cierra devolviendo la pieza, y limpia el archivo que deja de usarse.
  Future<void> _guardar() async {
    _guardado = true;
    final viejo = _urlOriginal;
    final pieza = _armar();
    if (viejo.isNotEmpty && viejo != _logo) {
      // Se borra ANTES de cerrar: después, este State ya no existe y nadie se
      // acordaría del archivo que se quedó.
      await PatrocinioStorage.borrar(viejo);
    }
    if (mounted) Navigator.pop(context, (true, pieza));
  }

  /// Quita la pieza entera, y su archivo con ella.
  Future<void> _quitarPieza() async {
    _guardado = true;
    if (_logo.isNotEmpty) await PatrocinioStorage.borrar(_logo);
    if (mounted) Navigator.pop(context, (true, null));
  }

  int get _palabras => palabrasDelTitular(_titular.text);

  /// La etiqueta es obligatoria —§6— y hace falta algo que dibujar.
  bool get _valida =>
      _etiqueta.text.trim().isNotEmpty &&
      (_titular.text.trim().isNotEmpty || _logo.isNotEmpty);

  Future<void> _subir() async {
    setState(() {
      _subiendo = true;
      _aviso = null;
    });
    PlatformFile? archivo;
    try {
      if (widget.elegirArchivo != null) {
        archivo = await widget.elegirArchivo!();
      } else {
        final r = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: PatrocinioStorage.extensiones,
          withData: true,
        );
        archivo = r?.files.firstOrNull;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _subiendo = false;
          _aviso = 'No se pudo abrir el selector de archivos: $e';
        });
      }
      return;
    }
    if (archivo == null) {
      // Canceló. No es un fallo y no se dice nada.
      if (mounted) setState(() => _subiendo = false);
      return;
    }
    final datos = archivo.bytes;
    if (datos == null) {
      // ESTO SÍ es un fallo, y hasta ahora se veía igual que cancelar.
      //
      // `withData: true` pide el contenido al elegir; si aun así llega vacío,
      // el archivo se seleccionó y no se pudo leer. Callarlo deja al
      // organizador pulsando el botón una y otra vez sin saber por qué no pasa
      // nada — que es el mismo modo de fallo que costó dos rondas con el botón
      // de importar.
      if (mounted) {
        setState(() {
          _subiendo = false;
          _aviso = 'El navegador no entregó el contenido de "${archivo!.name}". '
              'Prueba con otro archivo, o vuelve a elegirlo.';
        });
      }
      return;
    }
    final r = await PatrocinioStorage.subir(
      torneoId: widget.torneoId,
      espacio: widget.espacio.clave,
      nombreOriginal: archivo.name,
      datos: datos,
    );
    if (!mounted) return;
    setState(() {
      _subiendo = false;
      if (r.ok) {
        _logo = r.url!;
      } else {
        _aviso = r.frase;
      }
    });
  }

  Future<void> _quitarArchivo() async {
    final url = _logo;
    setState(() {
      _logo = '';
      _subiendo = true;
    });
    // Se borra de Storage, no solo del modelo. Dejar el archivo colgado es lo
    // que hace crecer el almacenamiento sin control.
    final ok = await PatrocinioStorage.borrar(url);
    if (!mounted) return;
    setState(() {
      _subiendo = false;
      _aviso = ok ? null : 'El logotipo se quitó de la pieza, pero el archivo '
          'sigue en el almacenamiento.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 18, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(widget.espacio.titulo,
                  style: TextStyle(
                      color: t.text, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('${widget.espacio.medida} · ${widget.espacio.donde}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.sub, fontSize: 11.5, height: 1.35)),
              const SizedBox(height: 16),
              _bloqueLogo(t),
              const SizedBox(height: 14),
              _campo(t, _etiqueta, 'Etiqueta de patrocinio *',
                  'Patrocinador oficial',
                  obligatorio: true),
              _campo(t, _titular, 'Titular', 'Eleva cada gran ronda'),
              if (_palabras > maxPalabrasTitular)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                      'El manual pide $maxPalabrasTitular palabras como máximo; '
                      'van $_palabras. Se guarda igual — recortarlo aquí en '
                      'silencio dejaría una frase a medias en la pared.',
                      style: TextStyle(
                          color: t.danger, fontSize: 11.5, height: 1.4)),
                ),
              _campo(t, _alt, 'Texto alternativo del logotipo',
                  'Logotipo de la marca'),
              _campo(t, _cta, 'Llamada a la acción', 'Conoce la experiencia'),
              _campo(t, _destino, 'Enlace de destino', 'https://…'),
              if (_aviso != null) ...[
                Text(_aviso!,
                    style: TextStyle(
                        color: t.danger, fontSize: 11.5, height: 1.35)),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _valida && !_subiendo ? _guardar : null,
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
                      'Hace falta la etiqueta de patrocinio y, al menos, un '
                      'titular o un logotipo: sin nada que dibujar la pieza no '
                      'se pinta.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: t.sub, fontSize: 11.5)),
                ),
              if (widget.pieza != null)
                TextButton(
                  onPressed: _subiendo ? null : _quitarPieza,
                  style: TextButton.styleFrom(foregroundColor: t.sub),
                  child: const Text('Quitar de la pantalla'),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _bloqueLogo(GolfTheme t) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: t.divider)),
        child: Column(children: [
          if (_logo.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: Image.network(_logo,
                  height: 70,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Column(children: [
                        Icon(Icons.broken_image, size: 26, color: t.sub),
                        const SizedBox(height: 4),
                        Text(_porQueNoSePinta,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: t.sub, fontSize: 11, height: 1.3)),
                      ])),
            ),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _subiendo ? null : _subir,
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: t.divider),
                    foregroundColor: t.text,
                    padding: const EdgeInsets.symmetric(vertical: 11)),
                icon: Icon(_logo.isEmpty ? Icons.upload_file : Icons.sync,
                    size: 16),
                label: Text(_subiendo
                    ? 'Subiendo…'
                    : _logo.isEmpty
                        ? 'Subir logotipo'
                        : 'Reemplazar'),
              ),
            ),
            if (_logo.isNotEmpty) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: _subiendo ? null : _quitarArchivo,
                tooltip: 'Borrar el archivo',
                icon: Icon(Icons.delete_outline, size: 19, color: t.sub),
              ),
            ],
          ]),
          const SizedBox(height: 6),
          Text(
              _logo.isEmpty
                  ? '${widget.espacio.medida} · PNG, JPG, SVG o WEBP, '
                      'hasta ${PatrocinioStorage.maxMB} MB'
                  : 'El archivo está guardado con este torneo. Borrarlo es cosa '
                      'tuya: no se limpia solo al cerrar.',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.sub, fontSize: 10.5, height: 1.3)),
        ]),
      );

  /// Por qué un archivo que SÍ está no se pinta.
  ///
  /// Pasó en la primera subida real y el síntoma engaña: el archivo estaba en
  /// Storage, con su tipo y su tamaño, y en pantalla salía un icono roto.
  ///
  /// CanvasKit no dibuja las imágenes con un `<img>` del DOM: las lleva a un
  /// canvas, y para eso el navegador las pide en modo CORS y exige la cabecera
  /// `Access-Control-Allow-Origin` EN LA RESPUESTA del GET. Un bucket recién
  /// creado no la manda —aunque el preflight sí—, así que la imagen se
  /// descarta.
  ///
  /// Se dice aquí porque un icono roto sin explicación manda a buscar el
  /// problema al sitio equivocado: parece que la subida falló, y la subida fue
  /// bien.
  static const _porQueNoSePinta =
      'El archivo está subido, pero el navegador no lo deja pintar.\n'
      'Suele ser el CORS del bucket: ver DESPLIEGUE.md.';

  PiezaDePatrocinio _armar() => PiezaDePatrocinio(
        etiqueta: _etiqueta.text.trim(),
        titular: _titular.text.trim(),
        logoUrl: _logo,
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
          hintStyle:
              TextStyle(color: t.sub.withValues(alpha: 0.5), fontSize: 13),
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
