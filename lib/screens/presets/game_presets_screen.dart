// ─────────────────────────────────────────────────────────────────────────────
// GAME PRESETS SCREEN — Configuraciones de partida guardadas
// Permite crear, editar y eliminar configuraciones de módulos de apuesta.
// Al crear una ronda, estas configuraciones se pueden cargar y solo hay que
// asignar los jugadores.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/app_theme.dart';
import '../../models/models.dart';
import '../../providers/round_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/format_config_fields.dart';

class GamePresetsScreen extends StatefulWidget {
  const GamePresetsScreen({super.key});

  @override
  State<GamePresetsScreen> createState() => _GamePresetsScreenState();
}

class _GamePresetsScreenState extends State<GamePresetsScreen> {
  List<GamePreset> _presets = [];
  bool _loading = true;

  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    _loadPresets();
  }

  Future<void> _loadPresets() async {
    setState(() { _loading = true; _loadError = false; });
    try {
      final presets = await FirestoreService.getGamePresets();
      if (mounted) setState(() { _presets = presets; _loading = false; });
    } catch (e) {
      if (kDebugMode) debugPrint('Error cargando presets: $e');
      if (mounted) setState(() { _loading = false; _loadError = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<RoundProvider>().theme;
    GolfThemeExt.setCurrent(t);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: gAppBar('Mis Configuraciones', t, showBack: true, ctx: context),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: t.primary))
          : _loadError
              ? _errorState(t)
              : _presets.isEmpty
                  ? _emptyState(t)
                  : _presetList(t),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openPresetEditor(context, t, null),
        backgroundColor: t.primary,
        icon: Icon(Icons.add, color: t.onPrimary),
        label: Text('Nueva config', style: TextStyle(color: t.onPrimary, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _errorState(GolfTheme t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 70, height: 70,
              decoration: BoxDecoration(
                color: t.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(Icons.wifi_off_outlined, color: t.danger, size: 36),
            ),
            const SizedBox(height: 20),
            Text('Error de conexión',
                style: TextStyle(color: t.text, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(
              'No se pudieron cargar las configuraciones.\n'
              'Si usas un bloqueador de anuncios, desactívalo para esta página.',
              style: TextStyle(color: t.sub, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _loadPresets,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: t.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('Reintentar',
                    style: TextStyle(color: t.onPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(GolfTheme t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: t.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.tune, color: t.primary, size: 40),
            ),
            const SizedBox(height: 20),
            Text(
              'Sin configuraciones guardadas',
              style: TextStyle(color: t.text, fontSize: 18, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Crea configuraciones con los parámetros de tus apuestas favoritas. '
              'Al crear una nueva ronda, podrás cargarlas y solo asignar los jugadores.',
              style: TextStyle(color: t.sub, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: () => _openPresetEditor(context, t, null),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: t.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '+ Crear primera configuración',
                  style: TextStyle(color: t.onPrimary, fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _presetList(GolfTheme t) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: _presets.length,
      itemBuilder: (_, i) => _presetCard(_presets[i], t),
    );
  }

  Widget _presetCard(GamePreset preset, GolfTheme t) {
    final modTypes = _moduleTypesFromJson(preset.modulesJson);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Header ──────────────────────────────────────────────────────
          Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: t.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(child: Text(preset.emoji, style: const TextStyle(fontSize: 22))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(preset.name,
                  style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 16)),
              if (preset.description.isNotEmpty)
                Text(preset.description,
                    style: TextStyle(color: t.sub, fontSize: 12),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            // Botón editar
            GestureDetector(
              onTap: () => _openPresetEditor(context, t, preset),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: t.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Editar', style: TextStyle(
                    color: t.primary, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _confirmDelete(context, t, preset),
              child: Icon(Icons.delete_outline, color: t.danger.withValues(alpha: 0.7), size: 20),
            ),
          ]),

          if (modTypes.isNotEmpty) ...[
            const SizedBox(height: 12),
            const GDivider(),
            const SizedBox(height: 10),
            // ── Módulos ─────────────────────────────────────────────────────
            Wrap(spacing: 6, runSpacing: 6, children: modTypes.map((mod) => _modChip(mod, t)).toList()),
          ],

          if (preset.useCount > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Usada ${preset.useCount} veces',
              style: TextStyle(color: t.sub, fontSize: 11),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _modChip(BetModuleInstance mod, GolfTheme t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: t.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.primary.withValues(alpha: 0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(mod.type.icon, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 4),
        Text(mod.summaryLabel,
            style: TextStyle(color: t.primary, fontSize: 10, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  List<BetModuleInstance> _moduleTypesFromJson(List<Map<String, dynamic>> json) {
    try {
      return json.map((j) => BetModuleInstance.fromJson(j)).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('Error parsing modules: $e');
      return [];
    }
  }

  Future<void> _confirmDelete(BuildContext ctx, GolfTheme t, GamePreset preset) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: t.card,
        title: Text('Eliminar configuración',
            style: TextStyle(color: t.text, fontWeight: FontWeight.w800)),
        content: Text(
          '¿Eliminar "${preset.name}"? Esta acción no se puede deshacer.',
          style: TextStyle(color: t.sub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar', style: TextStyle(color: t.sub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Eliminar', style: TextStyle(color: t.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await FirestoreService.deleteGamePreset(preset.id);
      setState(() => _presets.removeWhere((p) => p.id == preset.id));
    }
  }

  // ── Editor de preset ───────────────────────────────────────────────────────
  void _openPresetEditor(BuildContext ctx, GolfTheme t, GamePreset? existing) {
    Navigator.push(
      ctx,
      MaterialPageRoute(
        builder: (_) => _PresetEditorScreen(
          existing: existing,
          onSaved: (saved) {
            setState(() {
              final idx = _presets.indexWhere((p) => p.id == saved.id);
              if (idx >= 0) {
                _presets[idx] = saved;
              } else {
                _presets.insert(0, saved);
              }
            });
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EDITOR DE PRESET
// ─────────────────────────────────────────────────────────────────────────────
class _PresetEditorScreen extends StatefulWidget {
  final GamePreset? existing;
  final void Function(GamePreset) onSaved;

  const _PresetEditorScreen({this.existing, required this.onSaved});

  @override
  State<_PresetEditorScreen> createState() => _PresetEditorScreenState();
}

class _PresetEditorScreenState extends State<_PresetEditorScreen> {
  static const _uuid = Uuid();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late String _emoji;
  late List<BetModuleInstance> _modules;
  bool _saving = false;

  // Emojis para elegir
  static const _emojis = ['⛳️', '🏌️', '🎯', '💰', '🏆', '🎲', '🃏', '🤑', '🔥', '⚡'];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _emoji = e?.emoji ?? '⛳️';
    _modules = e != null
        ? e.toModules([]) // Sin jugadores por ahora (se asignan al crear ronda)
        : [];
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<RoundProvider>().theme;
    GolfThemeExt.setCurrent(t);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: gAppBar(
        widget.existing == null ? 'Nueva Configuración' : 'Editar Configuración',
        t, showBack: true, ctx: context,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Nombre e icono ───────────────────────────────────────────────
          GCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('NOMBRE', style: TextStyle(color: t.sub, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
            const SizedBox(height: 8),
            Row(children: [
              // Emoji picker
              GestureDetector(
                onTap: () => _pickEmoji(context, t),
                child: Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.divider),
                  ),
                  child: Center(child: Text(_emoji, style: const TextStyle(fontSize: 26))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: TextField(
                controller: _nameCtrl,
                style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Ej: Nassau clásico',
                  hintStyle: TextStyle(color: t.sub, fontWeight: FontWeight.w400, fontSize: 14),
                  fillColor: t.surface, filled: true,
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
              )),
            ]),
            const SizedBox(height: 12),
            Text('DESCRIPCIÓN (opcional)', style: TextStyle(color: t.sub, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
            const SizedBox(height: 8),
            TextField(
              controller: _descCtrl,
              maxLines: 2,
              style: TextStyle(color: t.text, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Ej: Nassau con press y skins carry',
                hintStyle: TextStyle(color: t.sub, fontSize: 13),
                fillColor: t.surface, filled: true,
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
          ])),

          const SizedBox(height: 24),

          // ── Módulos de apuesta ───────────────────────────────────────────
          GSectionHeader(title: 'APUESTAS CONFIGURADAS'),
          const SizedBox(height: 8),

          // Info sobre jugadores
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.accent.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: t.accent.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, color: t.accent, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'Configura los parámetros de cada apuesta. Los jugadores se asignan cuando creas una nueva ronda.',
                style: TextStyle(color: t.sub, fontSize: 12),
              )),
            ]),
          ),
          const SizedBox(height: 12),

          // Lista de módulos
          ..._modules.asMap().entries.map((e) => _moduleTile(e.key, e.value, t)),

          const SizedBox(height: 8),

          // Botón agregar módulo
          GestureDetector(
            onTap: () => _addModule(context, t),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: t.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.primary.withValues(alpha: 0.3)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.add_circle_outline, color: t.primary, size: 18),
                const SizedBox(width: 8),
                Text('Agregar apuesta', style: TextStyle(
                    color: t.primary, fontWeight: FontWeight.w700, fontSize: 14)),
              ]),
            ),
          ),

          const SizedBox(height: 32),

          // Botón guardar
          GPrimaryButton(
            label: _saving ? 'Guardando...' : '💾  Guardar Configuración',
            onTap: _saving ? null : () => _save(context, t),
          ),
        ]),
      ),
    );
  }

  Widget _moduleTile(int idx, BetModuleInstance mod, GolfTheme t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.divider),
        ),
        child: Row(children: [
          Text(mod.type.icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(mod.name, style: TextStyle(
                color: t.text, fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 2),
            Text(mod.summaryLabel, style: TextStyle(color: t.sub, fontSize: 11)),
          ])),
          GestureDetector(
            onTap: () => _editModule(context, idx, mod, t),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: t.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Editar', style: TextStyle(
                  color: t.primary, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() => _modules.removeAt(idx)),
            child: Icon(Icons.close, color: t.sub, size: 18),
          ),
        ]),
      ),
    );
  }

  void _pickEmoji(BuildContext ctx, GolfTheme t) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: t.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Elige un ícono', style: TextStyle(
              color: t.text, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12, runSpacing: 12,
            children: _emojis.map((e) => GestureDetector(
              onTap: () { setState(() => _emoji = e); Navigator.pop(ctx); },
              child: Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: e == _emoji ? t.primary.withValues(alpha: 0.15) : t.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: e == _emoji ? t.primary : t.divider,
                    width: e == _emoji ? 2 : 1,
                  ),
                ),
                child: Center(child: Text(e, style: const TextStyle(fontSize: 26))),
              ),
            )).toList(),
          ),
        ]),
      ),
    );
  }

  void _addModule(BuildContext ctx, GolfTheme t) {
    final selected = <BetModuleType>{};
    showModalBottomSheet(
      context: ctx,
      backgroundColor: t.card,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (bCtx) => StatefulBuilder(
        builder: (bCtx2, setSt) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(bCtx2).viewInsets.bottom + 24,
            left: 20, right: 20, top: 24,
          ),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('Agregar apuesta', style: TextStyle(
                    color: t.text, fontSize: 18, fontWeight: FontWeight.w800)),
                const Spacer(),
                GestureDetector(onTap: () => Navigator.pop(bCtx2),
                    child: Icon(Icons.close, color: t.sub)),
              ]),
              const SizedBox(height: 4),
              Text('Selecciona el tipo de apuesta', style: TextStyle(color: t.sub, fontSize: 12)),
              const SizedBox(height: 16),

              // De betTypeSections, como las otras dos hojas de "Agregar
              // apuesta". Eran dos listas literales.
              for (final sec in betTypeSections) ...[
                Text(sec.familia.label, style: TextStyle(color: t.sub, fontSize: 10,
                    fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                const SizedBox(height: 8),
                ...sec.tipos.map((bt) => _betTypeTile(bt, selected, setSt, t)),
                const SizedBox(height: 16),
              ],
              GPrimaryButton(
                label: selected.isEmpty
                    ? 'Selecciona al menos uno'
                    : 'Agregar ${selected.length} módulo${selected.length > 1 ? 's' : ''}',
                onTap: selected.isEmpty ? null : () {
                  final startIdx = _modules.length;
                  setState(() {
                    for (final bt in selected) {
                      // Sin participantIds — se asignan al crear ronda
                      _modules.add(BetModuleInstance.defaultFor(bt, [], id: '${bt.name}_${_uuid.v4()}'));
                    }
                  });
                  Navigator.pop(bCtx2);
                  if (selected.length == 1) {
                    Future.delayed(const Duration(milliseconds: 200), () {
                      if (mounted) _editModule(ctx, startIdx, _modules[startIdx], t);
                    });
                  }
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _betTypeTile(BetModuleType bt, Set<BetModuleType> selected, StateSetter setSt, GolfTheme t) {
    final isSel = selected.contains(bt);
    final isMatchType = bt.family == BetFamily.matchPlay;
    final accentColor = isMatchType ? t.accent : t.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => setSt(() {
          if (isSel) {
            selected.remove(bt);
          } else {
            selected.add(bt);
          }
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSel ? accentColor.withValues(alpha: 0.1) : t.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSel ? accentColor : t.divider, width: isSel ? 1.5 : 1),
          ),
          child: Row(children: [
            Text(bt.icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(bt.label, style: TextStyle(
                  color: t.text, fontWeight: FontWeight.w700, fontSize: 14)),
              Text(bt.description, style: TextStyle(color: t.sub, fontSize: 11)),
            ])),
            if (isSel) Icon(Icons.check_circle, color: accentColor, size: 20)
            else Icon(Icons.add_circle_outline, color: t.sub, size: 20),
          ]),
        ),
      ),
    );
  }

  void _editModule(BuildContext ctx, int idx, BetModuleInstance mod, GolfTheme t) {
    var cfg = mod;
    showModalBottomSheet(
      context: ctx,
      backgroundColor: t.card,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (bCtx) => StatefulBuilder(
        builder: (bCtx2, setSt) => DraggableScrollableSheet(
          initialChildSize: 0.85, minChildSize: 0.5, maxChildSize: 0.95, expand: false,
          builder: (_, sc) => Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(bCtx2).viewInsets.bottom),
            child: SingleChildScrollView(
              controller: sc,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('${cfg.type.icon} ${cfg.type.label}',
                      style: TextStyle(color: t.text, fontSize: 20, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  GestureDetector(onTap: () => Navigator.pop(bCtx2),
                      child: Icon(Icons.close, color: t.sub)),
                ]),
                const SizedBox(height: 4),
                Text(cfg.type.description, style: TextStyle(color: t.sub, fontSize: 12)),
                const SizedBox(height: 16),

                // Info: sin participantes (se asignan al usar el preset)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: t.accent.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: t.accent.withValues(alpha: 0.2)),
                  ),
                  child: Row(children: [
                    Icon(Icons.people_outline, color: t.accent, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      'Los jugadores se asignan al crear la ronda, no aquí.',
                      style: TextStyle(color: t.sub, fontSize: 12),
                    )),
                  ]),
                ),
                const SizedBox(height: 20),

                // Widgets de configuración específicos por tipo
                ..._PresetConfigWidgets.build(cfg, t, setSt, (updated) => cfg = updated),

                const SizedBox(height: 24),
                GPrimaryButton(
                  label: 'Guardar',
                  onTap: () {
                    setState(() => _modules[idx] = cfg);
                    Navigator.pop(bCtx2);
                  },
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save(BuildContext ctx, GolfTheme t) async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        backgroundColor: t.danger,
        content: const Text('El nombre es requerido'),
      ));
      return;
    }
    if (_modules.isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        backgroundColor: t.danger,
        content: const Text('Agrega al menos una apuesta'),
      ));
      return;
    }

    setState(() => _saving = true);
    try {
      final preset = GamePreset(
        id: widget.existing?.id ?? '',
        name: name,
        emoji: _emoji,
        description: _descCtrl.text.trim(),
        modulesJson: _modules.map((m) => m.toJson()).toList(),
        updatedAt: DateTime.now(),
        useCount: widget.existing?.useCount ?? 0,
      );
      final saved = await FirestoreService.saveGamePreset(preset);
      widget.onSaved(saved);
      if (mounted) Navigator.pop(ctx);
    } catch (e) {
      if (kDebugMode) debugPrint('Error guardando preset: $e');
      if (mounted) {
        final errStr = e.toString();
        String msg;
        if (errStr.contains('permission-denied') || errStr.contains('PERMISSION_DENIED')) {
          msg = 'Sin permisos. Verifica que estés autenticado.';
        } else if (errStr.contains('network') || errStr.contains('unavailable') || errStr.contains('ERR_BLOCKED')) {
          msg = 'Sin conexión. Verifica tu internet o desactiva bloqueadores de anuncios.';
        } else {
          msg = 'Error al guardar. Intenta de nuevo.';
        }
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          backgroundColor: t.danger,
          content: Text(msg),
          duration: const Duration(seconds: 4),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS DE CONFIGURACIÓN POR TIPO (reutilizable desde el editor de preset)
// ─────────────────────────────────────────────────────────────────────────────
class _PresetConfigWidgets {
  // ── Helper: selector de modo de formato (1 Pot / Todos vs Todos) ──────────
  static List<Widget> _formatSelector(
    BetModuleInstance cfg, GolfTheme t, StateSetter setSt, void Function(BetModuleInstance) update,
  ) {
    return [
      _label('ESTRUCTURA DE APUESTA', t),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _FormatCard(
          isSelected: cfg.formatMode == BetFormatMode.onePot,
          icon: '🏆', title: '1 Pot',
          description: 'Un solo pozo grupal.\nEl ganador cobra a todos.',
          t: t,
          onTap: () => setSt(() => update(cfg.copyWith(formatMode: BetFormatMode.onePot))),
        )),
        const SizedBox(width: 10),
        Expanded(child: _FormatCard(
          isSelected: cfg.formatMode == BetFormatMode.allVsAll,
          icon: '⚔️', title: 'Todos vs Todos',
          description: 'Cada pareja tiene su\nduelo independiente.',
          t: t,
          onTap: () => setSt(() => update(cfg.copyWith(formatMode: BetFormatMode.allVsAll))),
        )),
      ]),
      const SizedBox(height: 6),
      Text(
        cfg.formatMode == BetFormatMode.onePot
            ? '1 Pot: un solo ganador por hoyo/segmento toma del resto del grupo.'
            : 'Todos vs Todos: A vs B, A vs C y B vs C cada uno con su apuesta propia.',
        style: TextStyle(color: t.sub, fontSize: 11, fontStyle: FontStyle.italic),
      ),
      const SizedBox(height: 20),
    ];
  }

  static List<Widget> build(
    BetModuleInstance cfg,
    GolfTheme t,
    StateSetter setSt,
    void Function(BetModuleInstance) update,
  ) {
    switch (cfg.type) {
      case BetModuleType.nassauLowHigh:
        // Necesita dos equipos de dos, y un preset guarda módulos SIN
        // jugadores, así que aquí no hay lados que configurar.
        return [
          _label('BOLA BAJA / BOLA ALTA', t),
          const SizedBox(height: 8),
          Text(
            'Este formato se arma con dos equipos de dos jugadores, así que '
            'se configura dentro de la ronda y no en una configuración guardada.',
            style: TextStyle(color: t.sub, fontSize: 12, height: 1.4),
          ),
        ];
      case BetModuleType.stableford:
        return stablefordFields(
          t: t,
          cfg: cfg.stableford,
          montoCtrl: TextEditingController(
              text: cfg.stableford.value.toStringAsFixed(0)),
          onChanged: (c) => update(cfg.copyWith(stablefordConfig: c)),
        );
      case BetModuleType.wolf:
        return wolfFields(
          t: t,
          cfg: cfg.wolf,
          montoCtrl:
              TextEditingController(text: cfg.wolf.value.toStringAsFixed(0)),
          onChanged: (c) => update(cfg.copyWith(wolfConfig: c)),
        );
      case BetModuleType.rabbit:
        return rabbitFields(
          t: t,
          cfg: cfg.rabbit,
          montoCtrl:
              TextEditingController(text: cfg.rabbit.value.toStringAsFixed(0)),
          onChanged: (c) => update(cfg.copyWith(rabbitConfig: c)),
        );
      case BetModuleType.snake:
        return snakeFields(
          t: t,
          cfg: cfg.snake,
          // Controller en línea, igual que los hermanos de este archivo
          // (ver _skinsWidgets): es el patrón local.
          montoCtrl: TextEditingController(
              text: cfg.snake.value.toStringAsFixed(0)),
          onChanged: (c) => update(cfg.copyWith(snakeConfig: c)),
        );
      case BetModuleType.skins:
        return _skinsWidgets(cfg, t, setSt, update);
      case BetModuleType.nassau:
        return _nassauWidgets(cfg, t, setSt, update);
      case BetModuleType.matchAutoPress:
        return _matchPressWidgets(cfg, t, setSt, update);

      case BetModuleType.medal:
        return _medalWidgets(cfg, t, setSt, update);
      case BetModuleType.putts:
        return _puttsWidgets(cfg, t, setSt, update);
      case BetModuleType.oyeses:
        return _oyesesWidgets(cfg, t, setSt, update);
      case BetModuleType.units:
        return _unitsWidgets(cfg, t, setSt, update);
    }
  }

  // ── Skins ──────────────────────────────────────────────────────────────────
  static List<Widget> _skinsWidgets(BetModuleInstance cfg, GolfTheme t, StateSetter setSt, void Function(BetModuleInstance) update) {
    final s = cfg.skins;
    final ctrl = TextEditingController(text: s.valuePerSkin.toStringAsFixed(0));
    ctrl.addListener(() {
      final v = double.tryParse(ctrl.text);
      if (v != null) update(cfg.copyWith(skinsConfig: s.copyWith(valuePerSkin: v)));
    });
    return [
      ..._formatSelector(cfg, t, setSt, update),
      _label('VALOR POR SKIN', t),
      const SizedBox(height: 8),
      _amountField('Valor por skin', ctrl, t),
      const SizedBox(height: 16),
      _label('JUEGO', t),
      const SizedBox(height: 8),
      _segmented(['Gross', 'Net'], s.mode == GrossNetMode.net ? 1 : 0, t, (i) {
        setSt(() => update(cfg.copyWith(skinsConfig: s.copyWith(mode: i == 1 ? GrossNetMode.net : GrossNetMode.gross))));
      }),
      const SizedBox(height: 16),
      _label('CARRY OVER', t),
      const SizedBox(height: 8),
      GestureDetector(
        onTap: () => setSt(() => update(cfg.copyWith(skinsConfig: s.copyWith(carryOver: !s.carryOver)))),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: s.carryOver ? t.accent.withValues(alpha: 0.10) : t.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: s.carryOver ? t.accent.withValues(alpha: 0.55) : t.divider,
              width: s.carryOver ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            Text(s.carryOver ? '🔥' : '❌', style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Acumular empates (Carry)',
                  style: TextStyle(color: s.carryOver ? t.accent : t.text,
                      fontWeight: FontWeight.w700, fontSize: 14)),
              Text(s.carryOver ? 'Los empates acumulan al siguiente hoyo 🔥'
                  : 'Los empates no se acumulan',
                  style: TextStyle(color: t.sub, fontSize: 11)),
            ])),
            Switch(
              value: s.carryOver,
              onChanged: (v) => setSt(() => update(cfg.copyWith(skinsConfig: s.copyWith(carryOver: v)))),
              activeThumbColor: t.accent,
              activeTrackColor: t.accent.withValues(alpha: 0.4),
              inactiveTrackColor: t.divider,
            ),
          ]),
        ),
      ),
    ];
  }

  // ── Nassau ─────────────────────────────────────────────────────────────────
  static List<Widget> _nassauWidgets(BetModuleInstance cfg, GolfTheme t, StateSetter setSt, void Function(BetModuleInstance) update) {
    final n = cfg.nassau;
    final cFront = TextEditingController(text: n.frontValue.toStringAsFixed(0));
    final cBack  = TextEditingController(text: n.backValue.toStringAsFixed(0));
    final cTotal = TextEditingController(text: n.totalValue.toStringAsFixed(0));
    final cPF    = TextEditingController(text: n.frontPressValue.toStringAsFixed(0));
    final cPB    = TextEditingController(text: n.backPressValue.toStringAsFixed(0));
    void save() {
      final fv  = double.tryParse(cFront.text) ?? n.frontValue;
      final bv  = double.tryParse(cBack.text)  ?? n.backValue;
      final tv  = double.tryParse(cTotal.text) ?? n.totalValue;
      final pfv = double.tryParse(cPF.text)    ?? n.frontPressValue;
      final pbv = double.tryParse(cPB.text)    ?? n.backPressValue;
      update(cfg.copyWith(nassauConfig: n.copyWith(
        frontValue: fv, backValue: bv, totalValue: tv,
        frontPressValue: pfv, backPressValue: pbv,
      )));
    }
    cFront.addListener(save); cBack.addListener(save); cTotal.addListener(save);
    cPF.addListener(save); cPB.addListener(save);
    return [
      ..._formatSelector(cfg, t, setSt, update),

      // ── Valores base ──────────────────────────────────────────────────────
      _label('VALORES', t), const SizedBox(height: 8),
      _amountField('Front 9', cFront, t), const SizedBox(height: 8),
      _amountField('Back 9', cBack, t), const SizedBox(height: 8),
      _amountField('Total 18', cTotal, t),
      const SizedBox(height: 16),

      // ── Modo de juego ─────────────────────────────────────────────────────
      _label('JUEGO', t), const SizedBox(height: 8),
      _segmented(['Gross', 'Net'], n.mode == GrossNetMode.net ? 1 : 0, t, (i) {
        setSt(() => update(cfg.copyWith(nassauConfig: n.copyWith(mode: i == 1 ? GrossNetMode.net : GrossNetMode.gross))));
      }),
      const SizedBox(height: 16),

      // ── Regla de empate ───────────────────────────────────────────────────
      _label('EMPATE EN SEGMENTO', t), const SizedBox(height: 8),
      _segmented(['Push (devuelve)', 'Carry (acumula)'],
          n.tieRule == TieRule.carryOver ? 1 : 0, t, (i) {
        setSt(() => update(cfg.copyWith(nassauConfig: n.copyWith(
          tieRule: i == 1 ? TieRule.carryOver : TieRule.push,
          carryEnabled: i == 1 ? true : n.carryEnabled,
        ))));
      }),
      const SizedBox(height: 4),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Text(
          n.tieRule == TieRule.carryOver
              ? 'El valor del segmento empatado se acumula al siguiente automáticamente.'
              : 'El valor del segmento empatado se devuelve (nadie gana ese segmento).',
          style: TextStyle(color: t.sub, fontSize: 11),
        ),
      ),
      const SizedBox(height: 16),

      // ── Carry en Back 9 ───────────────────────────────────────────────────
      _toggleRow(
        title: 'Carry en Back 9',
        subtitle: n.carryEnabled
            ? 'Si el F9 termina empatado, el B9 vale x${n.carryFactor.toStringAsFixed(0)}'
            : 'Sin carry — el B9 siempre vale su monto normal',
        value: n.carryEnabled,
        onChanged: (v) => setSt(() => update(cfg.copyWith(nassauConfig: n.copyWith(carryEnabled: v)))),
        t: t,
      ),
      if (n.carryEnabled) ...[
        const SizedBox(height: 12),
        _label('MULTIPLICADOR CARRY', t), const SizedBox(height: 8),
        _segmented(['x2', 'x3', 'x4'],
            n.carryFactor >= 4 ? 2 : n.carryFactor >= 3 ? 1 : 0, t, (i) {
          setSt(() => update(cfg.copyWith(nassauConfig: n.copyWith(
            carryFactor: (i + 2).toDouble(),
          ))));
        }),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            'Si el F9 termina igualado, el B9 (\$${n.backValue.toStringAsFixed(0)}) '
            'pasa a valer \$${(n.backValue * n.carryFactor).toStringAsFixed(0)}.',
            style: TextStyle(color: t.sub, fontSize: 11),
          ),
        ),
      ],
      const SizedBox(height: 16),

      // ── Press automático ──────────────────────────────────────────────────
      _toggleRow(
        title: 'Activar Press automático',
        subtitle: n.pressEnabled ? 'Trigger: ${n.autoPressTrigger} down' : 'Sin press',
        value: n.pressEnabled,
        onChanged: (v) => setSt(() => update(cfg.copyWith(nassauConfig: n.copyWith(pressEnabled: v)))),
        t: t,
      ),
      if (n.pressEnabled) ...[
        const SizedBox(height: 12),
        _label('TRIGGER', t), const SizedBox(height: 8),
        _segmented(['1 down', '2 down', '3 down'], n.autoPressTrigger - 1, t, (i) {
          setSt(() => update(cfg.copyWith(nassauConfig: n.copyWith(autoPressTrigger: i + 1))));
        }),
        const SizedBox(height: 16),
        _label('VALOR PRESS', t), const SizedBox(height: 8),
        _amountField('Press Front 9', cPF, t), const SizedBox(height: 8),
        _amountField('Press Back 9', cPB, t),
        const SizedBox(height: 16),
        _toggleRow(
          title: 'Presiones múltiples',
          subtitle: n.allowMultiplePresses
              ? 'Puede haber más de una por segmento'
              : 'Solo 1 por segmento',
          value: n.allowMultiplePresses,
          onChanged: (v) => setSt(() => update(cfg.copyWith(nassauConfig: n.copyWith(allowMultiplePresses: v)))),
          t: t,
        ),
        if (!n.allowMultiplePresses) ...[
          const SizedBox(height: 12),
          _label('MÁX. PRESIONES POR SEGMENTO', t), const SizedBox(height: 8),
          _segmented(['1', '2', '3'],
              (n.maxPresses == null || n.maxPresses! <= 1) ? 0
              : n.maxPresses! == 2 ? 1 : 2, t, (i) {
            setSt(() => update(cfg.copyWith(nassauConfig: n.copyWith(maxPresses: i + 1))));
          }),
        ],
      ],
    ];
  }

  // ── Match + Auto Press ─────────────────────────────────────────────────────
  static List<Widget> _matchPressWidgets(BetModuleInstance cfg, GolfTheme t, StateSetter setSt, void Function(BetModuleInstance) update) {
    final m = cfg.matchAutoPress;
    final cMatch = TextEditingController(text: m.matchValue.toStringAsFixed(0));
    final cPress = TextEditingController(text: m.pressValue.toStringAsFixed(0));
    cMatch.addListener(() { final v = double.tryParse(cMatch.text); if (v != null) update(cfg.copyWith(matchAutoPressConfig: m.copyWith(matchValue: v))); });
    cPress.addListener(() { final v = double.tryParse(cPress.text); if (v != null) update(cfg.copyWith(matchAutoPressConfig: m.copyWith(pressValue: v))); });
    return [
      ..._formatSelector(cfg, t, setSt, update),
      _label('MATCH PRINCIPAL', t), const SizedBox(height: 8),
      _amountField('Valor del match', cMatch, t),
      const SizedBox(height: 16),
      _label('PRESIONES', t), const SizedBox(height: 8),
      _amountField('Valor por presión', cPress, t),
      const SizedBox(height: 16),
      _label('TRIGGER DE PRESIÓN', t), const SizedBox(height: 8),
      _segmented(['1 up', '2 up', '3 up'], m.pressTriggerValue - 1, t, (i) {
        setSt(() => update(cfg.copyWith(matchAutoPressConfig: m.copyWith(pressTriggerValue: i + 1))));
      }),
      const SizedBox(height: 16),
      _label('HANDICAP', t), const SizedBox(height: 8),
      _segmented(['Gross', 'Net'], m.mode == GrossNetMode.net ? 1 : 0, t, (i) {
        setSt(() => update(cfg.copyWith(matchAutoPressConfig: m.copyWith(mode: i == 1 ? GrossNetMode.net : GrossNetMode.gross))));
      }),
    ];
  }

  // ── Medal ──────────────────────────────────────────────────────────────────
  static List<Widget> _medalWidgets(BetModuleInstance cfg, GolfTheme t, StateSetter setSt, void Function(BetModuleInstance) update) {
    final m = cfg.medal;
    final ctrl = TextEditingController(text: m.value.toStringAsFixed(0));
    ctrl.addListener(() { final v = double.tryParse(ctrl.text); if (v != null) update(cfg.copyWith(medalConfig: m.copyWith(value: v))); });
    return [
      ..._formatSelector(cfg, t, setSt, update),
      _label('VALOR', t), const SizedBox(height: 8),
      _amountField('Monto', ctrl, t),
      const SizedBox(height: 16),
      _label('HOYOS', t), const SizedBox(height: 8),
      _segmented(['9 hoyos', '18 hoyos'], m.holes == 18 ? 1 : 0, t, (i) {
        setSt(() => update(cfg.copyWith(medalConfig: m.copyWith(holes: i == 1 ? 18 : 9))));
      }),
      const SizedBox(height: 16),
      _label('JUEGO', t), const SizedBox(height: 8),
      _segmented(['Gross', 'Net'], m.mode == GrossNetMode.net ? 1 : 0, t, (i) {
        setSt(() => update(cfg.copyWith(medalConfig: m.copyWith(mode: i == 1 ? GrossNetMode.net : GrossNetMode.gross))));
      }),
    ];
  }

  // ── Putts ──────────────────────────────────────────────────────────────────
  static List<Widget> _puttsWidgets(BetModuleInstance cfg, GolfTheme t, StateSetter setSt, void Function(BetModuleInstance) update) {
    final p = cfg.putts;
    final ctrl = TextEditingController(text: p.value.toStringAsFixed(0));
    ctrl.addListener(() { final v = double.tryParse(ctrl.text); if (v != null) update(cfg.copyWith(puttsConfig: p.copyWith(value: v))); });
    return [
      ..._formatSelector(cfg, t, setSt, update),
      _label('VALOR', t), const SizedBox(height: 8),
      _amountField('Monto por segmento', ctrl, t),
      const SizedBox(height: 16),
      _label('MODO', t), const SizedBox(height: 8),
      _segmented(['Por segmento', 'Hoyo a hoyo'], p.puttsMode == PuttsMode.perHole ? 1 : 0, t, (i) {
        setSt(() => update(cfg.copyWith(puttsConfig: p.copyWith(puttsMode: i == 1 ? PuttsMode.perHole : PuttsMode.total))));
      }),
      const SizedBox(height: 16),
      _toggleRow(
        title: 'Penalti por 3-putt',
        subtitle: p.threePuttPenalty ? 'Se cobra por cada 3-putt' : 'Sin penalti',
        value: p.threePuttPenalty,
        onChanged: (v) => setSt(() => update(cfg.copyWith(puttsConfig: p.copyWith(threePuttPenalty: v)))),
        t: t,
      ),
    ];
  }

  // ── Oyeses ─────────────────────────────────────────────────────────────────
  static List<Widget> _oyesesWidgets(BetModuleInstance cfg, GolfTheme t, StateSetter setSt, void Function(BetModuleInstance) update) {
    final o = cfg.oyeses;
    final isAllVsAll = cfg.isAllVsAll;
    final ctrl = TextEditingController(text: o.value.toStringAsFixed(0));
    ctrl.addListener(() { final v = double.tryParse(ctrl.text); if (v != null) update(cfg.copyWith(oyesesConfig: o.copyWith(value: v))); });
    final zapatoCtrl = TextEditingController(text: o.zapatoValue > 0 ? o.zapatoValue.toStringAsFixed(0) : '');
    zapatoCtrl.addListener(() {
      final v = double.tryParse(zapatoCtrl.text) ?? 0;
      update(cfg.copyWith(oyesesConfig: o.copyWith(zapatoValue: v)));
    });
    return [
      // ── Formato ────────────────────────────────────────────────────────────
      ..._formatSelector(cfg, t, setSt, update),

      // ── Valor por oyés ─────────────────────────────────────────────────────
      _label('VALOR POR OYÉS', t), const SizedBox(height: 8),
      _amountField('Monto por oyés', ctrl, t),
      const SizedBox(height: 20),

      // ── Zapato ─────────────────────────────────────────────────────────────
      _label('👟 ZAPATO', t),
      const SizedBox(height: 6),
      Text(
        isAllVsAll
            ? 'Todos vs Todos: si A le gana TODOS los oyeses a B, A hace zapato vs B (puede haber varios zapatos).'
            : '1 Pot: si un jugador gana TODOS los oyeses del campo, cobra el zapato a todo el grupo.',
        style: TextStyle(color: t.sub, fontSize: 11),
      ),
      const SizedBox(height: 10),
      _toggleRow(
        title: 'Activar zapato 👟',
        subtitle: o.zapatoEnabled
            ? (isAllVsAll
                ? 'Zapato por pareja: quien gane todos los oyeses vs otro cobra extra'
                : 'Zapato grupal: el ganador absoluto cobra a todos')
            : 'Sin regla de zapato',
        value: o.zapatoEnabled,
        onChanged: (v) => setSt(() => update(cfg.copyWith(oyesesConfig: o.copyWith(zapatoEnabled: v)))),
        t: t,
      ),
      if (o.zapatoEnabled) ...[
        const SizedBox(height: 12),
        _label('VALOR DEL ZAPATO', t),
        const SizedBox(height: 6),
        Text(
          o.zapatoValue == 0
              ? 'Automático = total oyeses × valor por oyés'
              : 'Valor fijo configurado',
          style: TextStyle(color: t.sub, fontSize: 11),
        ),
        const SizedBox(height: 8),
        _amountField('Monto fijo (vacío = automático)', zapatoCtrl, t),
        const SizedBox(height: 12),
        _label('APLICA EN', t),
        const SizedBox(height: 8),
        _segmented(['Solo campo 18H', 'Cualquier ronda'], o.zapatoRequires18 ? 0 : 1, t, (i) {
          setSt(() => update(cfg.copyWith(oyesesConfig: o.copyWith(zapatoRequires18: i == 0))));
        }),
        const SizedBox(height: 6),
        Text(
          o.zapatoRequires18
              ? 'Solo aplica en campos con 3+ par-3s (rondas de 18 hoyos).'
              : 'Aplica en cualquier campo al completarse todos sus par-3s.',
          style: TextStyle(color: t.sub, fontSize: 11),
        ),
      ],
    ];
  }

  // ── Units ──────────────────────────────────────────────────────────────────
  static List<Widget> _unitsWidgets(BetModuleInstance cfg, GolfTheme t, StateSetter setSt, void Function(BetModuleInstance) update) {
    final u = cfg.units;
    final ctrls = <UnitEventType, TextEditingController>{
      for (final e in UnitEventType.values)
        e: TextEditingController(text: u.valueFor(e).toStringAsFixed(0)),
    };
    void rebuild() {
      final newMap = <UnitEventType, double>{};
      for (final e in UnitEventType.values) {
        final v = double.tryParse(ctrls[e]!.text);
        if (v != null) newMap[e] = v;
      }
      update(cfg.copyWith(unitsConfig: UnitsConfig(eventValues: newMap)));
    }
    for (final e in UnitEventType.values) {
      ctrls[e]!.addListener(rebuild);
    }

    return [
      _label('VALOR POR EVENTO', t),
      const SizedBox(height: 6),
      Text('Valor individual que paga cada evento.', style: TextStyle(color: t.sub, fontSize: 11)),
      const SizedBox(height: 12),
      ...UnitEventType.values.map((e) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.label, style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 13)),
            Text(e.description, style: TextStyle(color: t.sub, fontSize: 10)),
          ])),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: TextField(
              controller: ctrls[e],
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              textAlign: TextAlign.right,
              style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14),
              decoration: InputDecoration(
                prefixText: '\$ ',
                prefixStyle: TextStyle(color: t.sub, fontSize: 12),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                fillColor: t.surface, filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.divider)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.divider)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.primary, width: 1.5)),
              ),
            ),
          ),
        ]),
      )),
    ];
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  static Widget _label(String label, GolfTheme t) => Text(
    label, style: TextStyle(color: t.sub, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6),
  );

  static Widget _amountField(String label, TextEditingController ctrl, GolfTheme t) => TextField(
    controller: ctrl, keyboardType: TextInputType.number, style: TextStyle(color: t.text),
    decoration: InputDecoration(
      labelText: label, prefixText: '\$ ', fillColor: t.surface, filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.primary, width: 2)),
      labelStyle: TextStyle(color: t.sub),
    ),
  );

  static Widget _segmented(List<String> options, int selected, GolfTheme t, void Function(int) onSelect) {
    return Row(children: options.asMap().entries.map((e) {
      final isSel = e.key == selected;
      return Expanded(child: GestureDetector(
        onTap: () => onSelect(e.key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(vertical: 9),
          margin: EdgeInsets.only(right: e.key < options.length - 1 ? 6 : 0),
          decoration: BoxDecoration(
            color: isSel ? t.primary : t.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSel ? t.primary : t.divider),
          ),
          alignment: Alignment.center,
          child: Text(e.value, style: TextStyle(
            color: isSel ? t.onPrimary : t.sub,
            fontWeight: FontWeight.w700, fontSize: 12,
          )),
        ),
      ));
    }).toList());
  }

  static Widget _toggleRow({required String title, required String subtitle, required bool value, required void Function(bool) onChanged, required GolfTheme t}) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: t.divider)),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(color: t.sub, fontSize: 11)),
        ])),
        Switch(value: value, onChanged: onChanged,
          activeThumbColor: t.primary,
          activeTrackColor: t.primary.withValues(alpha: 0.4),
          inactiveTrackColor: t.divider),
      ]),
    );
}

// ── Tarjeta de selección de modo de formato (en presets) ─────────────────────
class _FormatCard extends StatelessWidget {
  final bool isSelected;
  final String icon;
  final String title;
  final String description;
  final GolfTheme t;
  final VoidCallback onTap;

  const _FormatCard({
    required this.isSelected,
    required this.icon,
    required this.title,
    required this.description,
    required this.t,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? t.primary.withValues(alpha: 0.10) : t.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? t.primary : t.divider,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 26)),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? t.primary : t.text,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(color: t.sub, fontSize: 10, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
