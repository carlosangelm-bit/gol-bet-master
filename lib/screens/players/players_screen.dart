// ─────────────────────────────────────────────────────────────────────────────
// PLAYERS SCREEN — Directorio de compañeros de golf
// ─────────────────────────────────────────────────────────────────────────────
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../widgets/importar_jugadores_sheet.dart';
import '../../providers/player_provider.dart';
import '../../providers/round_provider.dart';
import '../../services/player_service.dart';
import '../../widgets/common_widgets.dart';

class PlayersScreen extends StatefulWidget {
  const PlayersScreen({super.key});
  @override State<PlayersScreen> createState() => _PlayersScreenState();
}

class _PlayersScreenState extends State<PlayersScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text));
    // NO llamar startListening() aquí — AppShell ya lo inicia una sola vez.
    // Solo verificar si hay datos o loading para decidir si mostrar skeleton.
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t    = context.watch<RoundProvider>().theme;
    final prov = context.watch<PlayerProvider>();
    GolfThemeExt.setCurrent(t);

    final all  = prov.search(_query);
    final favs = all.where((p) => p.isFavorite).toList();
    final rest = all.where((p) => !p.isFavorite).toList();

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(children: [
          // ── Header ─────────────────────────────────────────────────────────
          _Header(t: t, onAdd: () => _showPlayerSheet(context, t)),

          // ── Importar una lista ─────────────────────────────────────────────
          //
          // Aquí y no en el torneo: el directorio es de donde tiran las rondas,
          // los grupos y los torneos, así que se importa a los treinta del club
          // UNA vez y se usan en todo. Importar directamente en un torneo crearía
          // gente que solo existe dentro de ese torneo, que es el problema de
          // "dos filas con el mismo nombre" a escala.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final ids = await showImportarJugadoresSheet(context, t: t);
                  if (ids == null || !context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('${ids.length} jugador'
                        '${ids.length == 1 ? '' : 'es'} en tu directorio.'),
                    duration: const Duration(seconds: 3),
                  ));
                },
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: t.divider),
                    foregroundColor: t.text,
                    padding: const EdgeInsets.symmetric(vertical: 11)),
                icon: Icon(Icons.content_paste_go, size: 17, color: t.sub),
                label: const Text('Importar una lista (pegar de Excel)',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ),
          ),

          // ── Buscador ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              style: TextStyle(color: t.text, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Buscar compañero...',
                hintStyle: TextStyle(color: t.sub),
                prefixIcon: Icon(Icons.search, color: t.sub, size: 20),
                suffixIcon: _query.isNotEmpty
                    ? GestureDetector(
                        onTap: () { _searchCtrl.clear(); setState(() => _query = ''); },
                        child: Icon(Icons.close, color: t.sub, size: 18),
                      )
                    : null,
                fillColor: t.surface,
                filled: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: t.divider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: t.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: t.primary, width: 1.5),
                ),
              ),
            ),
          ),

          // ── Lista ──────────────────────────────────────────────────────────
          Expanded(child: _buildBody(context, t, prov, favs, rest)),
        ]),
      ),

      floatingActionButton: FloatingActionButton(
        backgroundColor: t.primary,
        foregroundColor: t.onPrimary,
        onPressed: () => _showPlayerSheet(context, t),
        child: const Icon(Icons.person_add),
      ),
    );
  }

  Widget _buildBody(
    BuildContext ctx, GolfTheme t, PlayerProvider prov,
    List<PlayerWithLink> favs, List<PlayerWithLink> rest,
  ) {
    if (prov.loading) {
      return Center(child: CircularProgressIndicator(color: t.primary));
    }

    // Mostrar error con opción de reintentar
    if (prov.error != null && prov.isEmpty) {
      final errStr = prov.error ?? '';
      final isBlocked = errStr.contains('ERR_BLOCKED') ||
          errStr.contains('unavailable') ||
          errStr.contains('network') ||
          errStr.contains('Failed to fetch') ||
          errStr.contains('INTERNAL');
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 70, height: 70,
              decoration: BoxDecoration(
                color: t.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                isBlocked ? Icons.block_outlined : Icons.cloud_off_outlined,
                color: t.danger, size: 36,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isBlocked ? 'Bloqueado por extensión' : 'Sin conexión',
              style: TextStyle(color: t.text, fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              isBlocked
                  ? 'Una extensión del navegador (AdBlock, uBlock, etc.) está bloqueando Firebase.\n\n'
'Solución: abre esta app en modo incógnito (sin extensiones) o desactiva el bloqueador para esta página.'
                  : 'Verifica tu conexión a internet e intenta de nuevo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.sub, fontSize: 13, height: 1.5),
            ),
            // Error técnico visible para diagnóstico
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: t.divider.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                errStr,
                textAlign: TextAlign.left,
                style: TextStyle(color: t.sub, fontSize: 10, fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: 24),
            GPrimaryButton(
              label: 'Reintentar',
              icon: Icons.refresh,
              onTap: () => ctx.read<PlayerProvider>().retry(),
            ),
          ]),
        ),
      );
    }

    if (prov.isEmpty && _query.isEmpty) {
      return _EmptyState(t: t, onAdd: () => _showPlayerSheet(ctx, t));
    }

    if (favs.isEmpty && rest.isEmpty) {
      return Center(
        child: Text('Sin resultados para "$_query"',
            style: TextStyle(color: t.sub, fontSize: 14)),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      children: [
        // Favoritos
        if (favs.isNotEmpty) ...[
          _sectionLabel('FAVORITOS', t),
          ...favs.map((pw) => _PlayerTile(
            pw: pw, t: t,
            onTap:   () => _showPlayerSheet(ctx, t, existing: pw),
            onFav:   () => ctx.read<PlayerProvider>().toggleFavorite(pw.player.id),
            onDelete:() => _confirmDelete(ctx, t, pw),
          )),
          const SizedBox(height: 16),
        ],
        // Resto
        if (rest.isNotEmpty) ...[
          if (favs.isNotEmpty) _sectionLabel('TODOS', t),
          ...rest.map((pw) => _PlayerTile(
            pw: pw, t: t,
            onTap:   () => _showPlayerSheet(ctx, t, existing: pw),
            onFav:   () => ctx.read<PlayerProvider>().toggleFavorite(pw.player.id),
            onDelete:() => _confirmDelete(ctx, t, pw),
          )),
        ],
      ],
    );
  }

  Widget _sectionLabel(String label, GolfTheme t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(label,
        style: TextStyle(color: t.sub, fontSize: 10,
            fontWeight: FontWeight.w700, letterSpacing: 0.8)),
  );

  // ── Sheet crear / editar jugador ─────────────────────────────────────────
  void _showPlayerSheet(BuildContext ctx, GolfTheme t, {PlayerWithLink? existing}) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: t.card,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PlayerFormSheet(
        t: t,
        existing: existing,
        onSave: (name, hcp, colorIdx, isFav, customName, sliding, notes) async {
          final prov = ctx.read<PlayerProvider>();
          if (existing == null) {
            // Crear nuevo
            await prov.createPlayer(
              name: name, handicap: hcp, colorIndex: colorIdx,
              isFavorite: isFav, customDisplayName: customName,
              defaultSlidingAdjustment: sliding, notes: notes,
            );
          } else {
            // Actualizar datos del jugador
            await prov.updatePlayer(existing.player.copyWith(
              name: name, handicapBase: hcp, colorIndex: colorIdx,
            ));
            // Actualizar link
            if (existing.link != null) {
              await prov.updateLink(existing.link!.copyWith(
                isFavorite: isFav,
                customDisplayName: customName,
                defaultSlidingAdjustment: sliding,
                notes: notes,
              ));
            }
          }
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext ctx, GolfTheme t, PlayerWithLink pw) async {
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (d) => AlertDialog(
        backgroundColor: t.card,
        title: Text('Quitar del directorio', style: TextStyle(color: t.text)),
        content: Text(
          '¿Quitar a ${pw.displayName} de tu directorio?\n'
          'El jugador no se borrará del historial de rondas.',
          style: TextStyle(color: t.sub, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false),
              child: Text('Cancelar', style: TextStyle(color: t.sub))),
          TextButton(onPressed: () => Navigator.pop(d, true),
              child: Text('Quitar', style: TextStyle(color: t.danger))),
        ],
      ),
    );
    if (confirm == true && ctx.mounted) {
      await ctx.read<PlayerProvider>().removeFromDirectory(pw.player.id);
    }
  }
}

// ── Header ────────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final GolfTheme t;
  final VoidCallback onAdd;
  const _Header({required this.t, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: BoxDecoration(
          color: t.bg,
          border: Border(bottom: BorderSide(color: t.divider))),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
              color: t.primary, borderRadius: BorderRadius.circular(10)),
          child: Icon(Icons.people, color: t.onPrimary, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Compañeros',
                style: TextStyle(color: t.text,
                    fontWeight: FontWeight.w800, fontSize: 20)),
            Consumer<PlayerProvider>(
              builder: (_, p, __) => Text(
                '${p.directory.length} jugador${p.directory.length == 1 ? '' : 'es'} · '
                '${p.favorites.length} favorito${p.favorites.length == 1 ? '' : 's'}',
                style: TextStyle(color: t.sub, fontSize: 11),
              ),
            ),
          ]),
        ),
        // Botón cerrar (volver a Ajustes)
        if (Navigator.canPop(context))
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close, color: t.sub, size: 18),
            ),
          ),
      ]),
    );
  }
}

// ── Tile de jugador ───────────────────────────────────────────────────────────
class _PlayerTile extends StatelessWidget {
  final PlayerWithLink pw;
  final GolfTheme t;
  final VoidCallback onTap;
  final VoidCallback onFav;
  final VoidCallback onDelete;
  const _PlayerTile({
    required this.pw, required this.t,
    required this.onTap, required this.onFav, required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final link          = pw.link;
    final hasCustomName = link?.customDisplayName?.isNotEmpty == true;
    final sliding       = link?.defaultSlidingAdjustment ?? 0;
    final isLinked      = pw.player.linkedUserId != null &&
                          pw.player.linkedUserId!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isLinked
                ? t.primary.withValues(alpha: 0.06)
                : t.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isLinked ? t.primary.withValues(alpha: 0.45) : t.divider,
              width: isLinked ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            // Avatar con indicador de vinculación
            Stack(clipBehavior: Clip.none, children: [
              GAvatar(name: pw.displayName, colorIndex: pw.player.colorIndex, size: 40),
              if (isLinked)
                Positioned(
                  right: -4, bottom: -4,
                  child: Container(
                    width: 18, height: 18,
                    decoration: BoxDecoration(
                      color: t.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: t.card, width: 2),
                    ),
                    child: const Icon(Icons.link_rounded, color: Colors.white, size: 10),
                  ),
                ),
            ]),
            const SizedBox(width: 12),

            // Datos
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Línea 1: nombre · badge App · chip slide (todos en la misma fila)
              Row(children: [
                Expanded(
                  child: Text(pw.displayName,
                      style: TextStyle(color: t.text,
                          fontWeight: FontWeight.w700, fontSize: 14),
                      overflow: TextOverflow.ellipsis),
                ),
                // Badge "App" alineado con el nombre
                if (isLinked) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: t.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: t.primary.withValues(alpha: 0.35)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.smartphone_rounded, color: t.primary, size: 10),
                      const SizedBox(width: 3),
                      Text('App', style: TextStyle(color: t.primary, fontSize: 9, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ],
                // Chip sliding
                if (sliding != 0) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: sliding > 0
                          ? t.profit.withValues(alpha: 0.12)
                          : t.loss.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${sliding > 0 ? '+' : ''}${sliding.toStringAsFixed(0)} slide',
                      style: TextStyle(
                        color: sliding > 0 ? t.primary : t.sub,
                        fontSize: 10, fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 2),
              // Línea 2: nombre real (si custom) · HCP · cuenta vinculada
              Row(children: [
                if (hasCustomName) ...[
                  Text(pw.player.name,
                      style: TextStyle(color: t.sub, fontSize: 11)),
                  const SizedBox(width: 6),
                  Container(width: 1, height: 10, color: t.divider),
                  const SizedBox(width: 6),
                ],
                Text('HCP ${pw.player.handicapBase.toStringAsFixed(1)}',
                    style: TextStyle(color: t.sub, fontSize: 11)),
                if (isLinked) ...[
                  const SizedBox(width: 6),
                  Container(width: 1, height: 10, color: t.divider),
                  const SizedBox(width: 6),
                  Icon(Icons.verified_rounded, color: t.primary, size: 11),
                  const SizedBox(width: 2),
                  Text('Cuenta vinculada',
                      style: TextStyle(color: t.primary, fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ],
              ]),
            ])),

            // Acciones: estrella y eliminar apiladas, centradas en la card
            const SizedBox(width: 8),
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              GestureDetector(
                onTap: onFav,
                child: Icon(
                  pw.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                  color: pw.isFavorite ? Colors.amber : t.sub,
                  size: 22,
                ),
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: onDelete,
                child: Icon(Icons.remove_circle_outline,
                    color: t.danger.withValues(alpha: 0.6), size: 20),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final GolfTheme t;
  final VoidCallback onAdd;
  const _EmptyState({required this.t, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.people_outline, color: t.sub, size: 64),
          const SizedBox(height: 16),
          Text('Tu directorio está vacío',
              style: TextStyle(color: t.text,
                  fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Agrega a tus compañeros habituales de golf para '
            'seleccionarlos rápidamente al crear una ronda.',
            textAlign: TextAlign.center,
            style: TextStyle(color: t.sub, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 24),
          GPrimaryButton(
            label: '+ Agregar compañero',
            onTap: onAdd,
            icon: Icons.person_add,
          ),
        ]),
      ),
    );
  }
}

// ── Sheet de formulario crear/editar ─────────────────────────────────────────
class _PlayerFormSheet extends StatefulWidget {
  final GolfTheme t;
  final PlayerWithLink? existing;
  final Future<void> Function(
    String name, double hcp, int colorIdx, bool isFav,
    String? customName, double sliding, String? notes,
  ) onSave;

  const _PlayerFormSheet({
    required this.t, required this.onSave, this.existing,
  });

  @override
  State<_PlayerFormSheet> createState() => _PlayerFormSheetState();
}

class _PlayerFormSheetState extends State<_PlayerFormSheet> {
  late final _nameCtrl  = TextEditingController(
      text: widget.existing?.player.name ?? '');
  late final _hcpCtrl   = TextEditingController(
      text: widget.existing?.player.handicapBase.toStringAsFixed(1) ?? '0.0');
  late final _aliasCtrl = TextEditingController(
      text: widget.existing?.link?.customDisplayName ?? '');
  late final _notesCtrl = TextEditingController(
      text: widget.existing?.link?.notes ?? '');
  late final _emailCtrl = TextEditingController();

  // Sliding como int, no como TextEditingController — evita el problema
  // del teclado numérico móvil que no muestra el símbolo '−'.
  late int _slidingVal = (widget.existing?.link?.defaultSlidingAdjustment ?? 0).round();

  late bool _isFav    = widget.existing?.isFavorite ?? false;
  late int  _colorIdx = widget.existing?.player.colorIndex ?? 0;
  bool _saving        = false;

  // ── Estado de vinculación ──────────────────────────────────────────────────
  // linkedUserId actual del jugador (puede ser null)
  String? _linkedUserId;
  // Info del usuario vinculado (cargada al abrir el sheet si existe)
  String? _linkedEmail;
  String? _linkedName;
  bool    _loadingLink   = false;
  bool    _linkingEmail  = false;   // spinner al intentar vincular
  String? _linkMsg;                 // mensaje resultado
  bool    _linkSuccess   = false;

  // Colores de avatar disponibles
  static const _colors = [
    Colors.green, Colors.blue, Colors.orange, Colors.purple,
    Colors.red, Colors.teal, Colors.amber, Colors.indigo,
  ];

  @override
  void initState() {
    super.initState();
    _linkedUserId = widget.existing?.player.linkedUserId;
    if (_linkedUserId != null && _linkedUserId!.isNotEmpty) {
      _loadLinkedInfo();
    }
  }

  Future<void> _loadLinkedInfo() async {
    setState(() => _loadingLink = true);
    final info = await PlayerService.getLinkedUserInfo(_linkedUserId!);
    if (mounted) {
      setState(() {
        _linkedEmail  = info?['email'];
        _linkedName   = info?['displayName'];
        _loadingLink  = false;
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _hcpCtrl, _aliasCtrl, _notesCtrl, _emailCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  // Botón auxiliar para el stepper de sliding
  Widget _slidingBtn(String label, Color color, VoidCallback onTap, GolfTheme t) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t     = widget.t;
    final isNew = widget.existing == null;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 20, right: 20, top: 24,
      ),
      child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título
          Row(children: [
            Text(isNew ? 'Nuevo compañero' : 'Editar compañero',
                style: TextStyle(color: t.text,
                    fontSize: 18, fontWeight: FontWeight.w800)),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Icon(Icons.close, color: t.sub),
            ),
          ]),
          const SizedBox(height: 20),

          // ── Color avatar ────────────────────────────────────────────────
          Text('COLOR', style: TextStyle(color: t.sub, fontSize: 10,
              fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          Row(children: List.generate(_colors.length, (i) => GestureDetector(
            onTap: () => setState(() => _colorIdx = i),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: _colors[i],
                shape: BoxShape.circle,
                border: _colorIdx == i
                    ? Border.all(color: t.text, width: 2.5)
                    : null,
              ),
            ),
          ))),
          const SizedBox(height: 16),

          // ── Nombre real ─────────────────────────────────────────────────
          _Field(label: 'Nombre', ctrl: _nameCtrl, t: t),
          const SizedBox(height: 12),

          // ── HCP ─────────────────────────────────────────────────────────
          _Field(
            label: 'HCP Índice',
            ctrl: _hcpCtrl, t: t,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            hint: '0.0 – 54.0',
          ),
          const SizedBox(height: 12),

          // ── Apodo personal ──────────────────────────────────────────────
          _Field(
            label: 'Apodo (opcional)',
            ctrl: _aliasCtrl, t: t,
            hint: 'Cómo lo verás en tus rondas',
          ),
          const SizedBox(height: 12),

          // ── Sliding por defecto ─────────────────────────────────────────
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('SLIDING POR DEFECTO',
                style: TextStyle(color: t.sub, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 4),
            Text(
              _slidingVal == 0
                  ? 'Sin ventaja — se calcula por HCP y tees'
                  : _slidingVal > 0
                      ? 'Recibes $_slidingVal golpe${_slidingVal != 1 ? "s" : ""} del compañero'
                      : 'Das ${_slidingVal.abs()} golpe${_slidingVal.abs() != 1 ? "s" : ""} al compañero',
              style: TextStyle(
                color: _slidingVal == 0
                    ? t.sub
                    : _slidingVal > 0 ? t.primary : t.sub,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              _slidingBtn('−5', t.sub, () => setState(() => _slidingVal -= 5), t),
              const SizedBox(width: 4),
              _slidingBtn('−1', t.sub, () => setState(() => _slidingVal -= 1), t),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: _slidingVal == 0
                        ? t.surface
                        : (_slidingVal > 0 ? t.primary : t.sub).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _slidingVal == 0
                          ? t.divider
                          : (_slidingVal > 0 ? t.primary : t.sub).withValues(alpha: 0.5),
                      width: _slidingVal == 0 ? 1 : 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _slidingVal > 0 ? '+$_slidingVal' : '$_slidingVal',
                      style: TextStyle(
                        color: _slidingVal == 0
                            ? t.sub
                            : (_slidingVal > 0 ? t.primary : t.sub),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _slidingBtn('+1', t.primary, () => setState(() => _slidingVal += 1), t),
              const SizedBox(width: 4),
              _slidingBtn('+5', t.primary, () => setState(() => _slidingVal += 5), t),
            ]),
            if (_slidingVal != 0) ...[
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () => setState(() => _slidingVal = 0),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.restart_alt, color: t.sub, size: 14),
                  const SizedBox(width: 4),
                  Text('Restablecer a 0 (calcular por HCP)',
                      style: TextStyle(color: t.sub, fontSize: 11)),
                ]),
              ),
            ],
          ]),
          const SizedBox(height: 12),

          // ── Notas ───────────────────────────────────────────────────────
          _Field(label: 'Notas (opcional)', ctrl: _notesCtrl, t: t,
              maxLines: 2),
          const SizedBox(height: 12),

          // ══════════════════════════════════════════════════════════════
          // ── Sección: Cuenta vinculada ──────────────────────────────
          // ══════════════════════════════════════════════════════════════
          if (!isNew) _buildLinkedAccountSection(t, context),

          const SizedBox(height: 12),

          // ── Favorito toggle ─────────────────────────────────────────────
          GestureDetector(
            onTap: () => setState(() => _isFav = !_isFav),
            child: Row(children: [
              Icon(
                _isFav ? Icons.star_rounded : Icons.star_border_rounded,
                color: _isFav ? Colors.amber : t.sub, size: 22,
              ),
              const SizedBox(width: 8),
              Text('Marcar como favorito',
                  style: TextStyle(color: t.text, fontSize: 14)),
            ]),
          ),
          const SizedBox(height: 20),

          // ── Guardar ─────────────────────────────────────────────────────
          GPrimaryButton(
            label: _saving ? 'Guardando...' : (isNew ? 'Agregar compañero' : 'Guardar cambios'),
            onTap: _saving ? null : () => _save(context),
          ),
        ],
      )),
    );
  }

  // ── Widget sección "Cuenta vinculada" ─────────────────────────────────────
  Widget _buildLinkedAccountSection(GolfTheme t, BuildContext context) {
    final isLinked = _linkedUserId != null && _linkedUserId!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isLinked
            ? t.primary.withValues(alpha: 0.06)
            : t.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLinked
              ? t.primary.withValues(alpha: 0.3)
              : t.divider,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header de la sección
        Row(children: [
          Icon(
            isLinked ? Icons.link : Icons.link_off,
            color: isLinked ? t.primary : t.sub,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            'CUENTA VINCULADA',
            style: TextStyle(
              color: isLinked ? t.primary : t.sub,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ]),
        const SizedBox(height: 8),

        if (isLinked) ...[
          // ── Estado: VINCULADO ─────────────────────────────────────────
          if (_loadingLink)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: t.primary),
                ),
                const SizedBox(width: 8),
                Text('Cargando info...', style: TextStyle(color: t.sub, fontSize: 12)),
              ]),
            )
          else ...[
            Row(children: [
              Icon(Icons.verified_user_outlined, color: t.primary, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (_linkedName != null && _linkedName!.isNotEmpty)
                    Text(_linkedName!,
                        style: TextStyle(color: t.text, fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  if (_linkedEmail != null && _linkedEmail!.isNotEmpty)
                    Text(_linkedEmail!,
                        style: TextStyle(color: t.sub, fontSize: 11)),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            // Botón desvincular
            GestureDetector(
              onTap: () => _confirmUnlink(context, t),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.link_off, color: t.danger, size: 14),
                const SizedBox(width: 4),
                Text('Desvincular cuenta',
                    style: TextStyle(color: t.danger, fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ],
        ] else ...[
          // ── Estado: SIN VINCULAR ─────────────────────────────────────
          Text(
            'Vincula este jugador a su cuenta de la app para que '
            'reciba invitaciones de rondas en vivo.',
            style: TextStyle(color: t.sub, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 10),

          // Campo email + botón
          Row(children: [
            Expanded(
              child: TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(color: t.text, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'correo@ejemplo.com',
                  hintStyle: TextStyle(color: t.sub.withValues(alpha: 0.6), fontSize: 12),
                  prefixIcon: Icon(Icons.email_outlined, color: t.sub, size: 18),
                  fillColor: t.bg,
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: t.divider)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: t.divider)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: t.primary, width: 2)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Botón vincular
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _linkingEmail
                  ? SizedBox(
                      key: const ValueKey('loading'),
                      width: 36, height: 36,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: t.primary),
                      ),
                    )
                  : GestureDetector(
                      key: const ValueKey('btn'),
                      onTap: () => _doLinkByEmail(context, t),
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: t.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.person_search,
                            color: t.onPrimary, size: 20),
                      ),
                    ),
            ),
          ]),

          // Mensaje de resultado
          if (_linkMsg != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(
                _linkSuccess ? Icons.check_circle_outline : Icons.info_outline,
                color: _linkSuccess ? t.primary : t.danger,
                size: 14,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _linkMsg!,
                  style: TextStyle(
                    color: _linkSuccess ? t.primary : t.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ]),
          ],
        ],
      ]),
    );
  }

  // ── Acción: vincular por email ─────────────────────────────────────────────
  Future<void> _doLinkByEmail(BuildContext ctx, GolfTheme t) async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() {
        _linkMsg     = 'Ingresa un correo electrónico.';
        _linkSuccess = false;
      });
      return;
    }
    if (!email.contains('@')) {
      setState(() {
        _linkMsg     = 'El correo no tiene un formato válido.';
        _linkSuccess = false;
      });
      return;
    }

    final playerId = widget.existing?.player.id;
    if (playerId == null) return;

    setState(() {
      _linkingEmail = true;
      _linkMsg      = null;
    });

    final (result, errorDetail) = await PlayerService.linkPlayerByEmail(
      playerId: playerId,
      email:    email,
    );

    if (!mounted) return;

    String msg     = errorDetail ?? 'Ocurrió un error. Intenta nuevamente.';
    bool   success = false;

    switch (result) {
      case LinkResult.success:
        msg     = '¡Vinculado con éxito! Ya puede recibir invitaciones.';
        success = true;
        // Recargar el UID vinculado leyendo el player actualizado
        final pSnap = await FirebaseFirestore.instance
            .collection('players').doc(playerId).get();
        final newLinkedUid = pSnap.data()?['linkedUserId'] as String?;
        if (mounted && newLinkedUid != null) {
          final info = await PlayerService.getLinkedUserInfo(newLinkedUid);
          setState(() {
            _linkedUserId = newLinkedUid;
            _linkedEmail  = info?['email'] ?? email;
            _linkedName   = info?['displayName'];
          });
        }
      case LinkResult.userNotFound:
        msg = 'No existe ninguna cuenta registrada con ese correo.';
      case LinkResult.alreadyLinked:
        msg = 'Este jugador ya está vinculado a esa cuenta.';
      case LinkResult.alreadyUsed:
        msg = 'Ese correo ya está vinculado a otro jugador de tu directorio.';
      case LinkResult.error:
        // msg ya viene de errorDetail o el default
        break;
    }

    setState(() {
      _linkMsg      = msg;
      _linkSuccess  = success;
      _linkingEmail = false;
      if (success) _emailCtrl.clear();
    });
  }

  // ── Confirmar desvinculación ───────────────────────────────────────────────
  Future<void> _confirmUnlink(BuildContext ctx, GolfTheme t) async {
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (d) => AlertDialog(
        backgroundColor: t.card,
        title: Text('Desvincular cuenta', style: TextStyle(color: t.text)),
        content: Text(
          'Se eliminará la vinculación con ${_linkedName ?? _linkedEmail ?? 'este usuario'}.\n'
          'El jugador permanecerá en tu directorio.',
          style: TextStyle(color: t.sub, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false),
              child: Text('Cancelar', style: TextStyle(color: t.sub))),
          TextButton(onPressed: () => Navigator.pop(d, true),
              child: Text('Desvincular', style: TextStyle(color: t.danger))),
        ],
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;

    final playerId = widget.existing?.player.id;
    if (playerId == null) return;

    await PlayerService.unlinkPlayer(playerId);
    if (mounted) {
      setState(() {
        _linkedUserId = null;
        _linkedEmail  = null;
        _linkedName   = null;
        _linkMsg      = null;
      });
    }
  }

  Future<void> _save(BuildContext ctx) async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        backgroundColor: widget.t.danger,
        content: const Text('El nombre no puede estar vacío'),
      ));
      return;
    }

    setState(() => _saving = true);
    try {
      final hcp   = double.tryParse(_hcpCtrl.text.replaceAll(',', '.')) ?? 0;
      final alias = _aliasCtrl.text.trim().isEmpty ? null : _aliasCtrl.text.trim();
      final notes = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

      await widget.onSave(name, hcp, _colorIdx, _isFav, alias, _slidingVal.toDouble(), notes);
      if (ctx.mounted) Navigator.pop(ctx);
    } catch (e) {
      if (kDebugMode) debugPrint('Error saving player: $e');
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          backgroundColor: widget.t.danger,
          content: Text('Error al guardar: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ── Campo de texto reutilizable en el sheet ───────────────────────────────────
class _Field extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final GolfTheme t;
  final TextInputType? keyboardType;
  final String? hint;
  final int maxLines;
  const _Field({
    required this.label, required this.ctrl, required this.t,
    this.keyboardType, this.hint, this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: TextStyle(color: t.text, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: t.sub.withValues(alpha: 0.6), fontSize: 12),
        labelStyle: TextStyle(color: t.sub),
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
      ),
    );
  }
}
