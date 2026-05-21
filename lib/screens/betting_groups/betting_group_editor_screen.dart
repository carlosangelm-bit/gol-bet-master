// ─────────────────────────────────────────────────────────────────────────────
// BETTING GROUP EDITOR SCREEN — Crear / editar un grupo habitual
// Secciones:
//   1. Nombre y emoji del grupo
//   2. Jugadores habituales (seleccionar del directorio)
//   3. Pair rules — matriz de duelos con módulos por par
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/app_theme.dart';
import '../../models/models.dart';
import '../../providers/betting_group_provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/round_provider.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/bet_module_edit_sheet.dart';
import '../../services/player_service.dart' show PlayerWithLink;

class BettingGroupEditorScreen extends StatefulWidget {
  final BettingGroup? existing;
  const BettingGroupEditorScreen({super.key, this.existing});
  @override
  State<BettingGroupEditorScreen> createState() =>
      _BettingGroupEditorScreenState();
}

class _BettingGroupEditorScreenState
    extends State<BettingGroupEditorScreen> {
  static const _uuid = Uuid();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late String       _emoji;
  late List<String> _playerIds;   // jugadores del grupo
  late List<PairBetRule> _rules;  // reglas por duelo

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final g = widget.existing;
    _nameCtrl  = TextEditingController(text: g?.name  ?? '');
    _descCtrl  = TextEditingController(text: g?.description ?? '');
    _emoji     = g?.emoji ?? '⛳';
    _playerIds = List<String>.from(g?.playerIds ?? []);
    _rules     = List<PairBetRule>.from(g?.pairRules ?? []);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  // ── Genera/actualiza pairRules cuando cambia la lista de jugadores ──────────
  void _syncPairRules() {
    final existing = { for (final r in _rules) r.pairKey: r };
    final newRules = <PairBetRule>[];
    final ids      = _playerIds;
    for (int i = 0; i < ids.length; i++) {
      for (int j = i + 1; j < ids.length; j++) {
        final a  = ids[i];
        final b  = ids[j];
        final pk = BetModuleInstance.pairKey(a, b);
        // Conservar regla existente (con sus módulos) si ya existía
        newRules.add(existing[pk] ?? PairBetRule(
          id:        _uuid.v4(),
          playerAId: a,
          playerBId: b,
        ));
      }
    }
    setState(() { _rules = newRules; });
  }

  // ── Guardar ────────────────────────────────────────────────────────────────
  Future<void> _save(BettingGroupProvider bgProv) async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('El grupo necesita un nombre')));
      return;
    }
    setState(() { _saving = true; });
    final group = BettingGroup(
      id:          widget.existing?.id ?? '',
      name:        name,
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      emoji:       _emoji,
      playerIds:   _playerIds,
      pairRules:   _rules,
      updatedAt:   DateTime.now(),
    );
    final saved = await bgProv.save(group);
    setState(() { _saving = false; });
    if (mounted) {
      if (saved != null) {
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Error al guardar el grupo'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final prov    = context.watch<RoundProvider>();
    final t       = prov.theme;
    GolfThemeExt.setCurrent(t);
    final bgProv  = context.read<BettingGroupProvider>();
    final plProv  = context.watch<PlayerProvider>();

    // Directorio de jugadores disponibles
    final directory = plProv.directory;

    String nameOf(String id) {
      try {
        return directory
            .firstWhere((p) => p.player.id == id)
            .player
            .name;
      } catch (_) {
        return id;
      }
    }

    String shortNameOf(String id) => nameOf(id).split(' ').first;

    int colorOf(String id) {
      try {
        return directory
            .firstWhere((p) => p.player.id == id)
            .player
            .colorIndex;
      } catch (_) {
        return 0;
      }
    }

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(children: [
          // ── Header ─────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: t.bg,
              border: Border(bottom: BorderSide(color: t.divider)),
            ),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.divider),
                  ),
                  child: Icon(Icons.close, color: t.text, size: 18),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.existing == null
                      ? 'Nuevo Betting Group'
                      : 'Editar Betting Group',
                  style: TextStyle(
                      color: t.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 18),
                ),
              ),
              // Guardar
              GestureDetector(
                onTap: _saving ? null : () => _save(bgProv),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: _saving
                        ? t.divider
                        : t.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _saving
                      ? SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: t.onPrimary),
                        )
                      : Text('Guardar',
                          style: TextStyle(
                              color: t.onPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14)),
                ),
              ),
            ]),
          ),

          // ── Contenido scrolleable ───────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // ── Sección 1: Nombre y emoji ───────────────────────────
                  GSectionHeader(title: 'NOMBRE DEL GRUPO'),
                  const SizedBox(height: 10),
                  GCard(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Emoji picker + nombre en una fila
                      Row(children: [
                        // Emoji selector
                        GestureDetector(
                          onTap: () => _pickEmoji(context, t),
                          child: Container(
                            width: 52, height: 52,
                            decoration: BoxDecoration(
                              color: t.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: t.divider),
                            ),
                            child: Center(
                              child: Text(_emoji,
                                  style: const TextStyle(fontSize: 26)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Nombre
                        Expanded(child: TextField(
                          controller: _nameCtrl,
                          style: TextStyle(
                              color: t.text,
                              fontWeight: FontWeight.w700,
                              fontSize: 16),
                          decoration: InputDecoration(
                            hintText: 'Ej: Viernes Campestre',
                            hintStyle:
                                TextStyle(color: t.sub, fontSize: 14),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
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
                                borderSide: BorderSide(
                                    color: t.primary, width: 1.5)),
                          ),
                        )),
                      ]),
                      const SizedBox(height: 12),
                      // Descripción opcional
                      TextField(
                        controller: _descCtrl,
                        style:
                            TextStyle(color: t.sub, fontSize: 13),
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'Descripción opcional (ej: "Partida habitual los viernes")',
                          hintStyle:
                              TextStyle(color: t.sub.withValues(alpha: 0.6), fontSize: 12),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
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
                              borderSide: BorderSide(
                                  color: t.primary, width: 1.5)),
                        ),
                      ),
                    ],
                  )),

                  const SizedBox(height: 24),

                  // ── Sección 2: Jugadores ────────────────────────────────
                  Row(children: [
                    Expanded(child: GSectionHeader(title: 'JUGADORES HABITUALES')),
                    GestureDetector(
                      onTap: () => _pickPlayers(context, t, directory),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: t.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.person_add_outlined,
                              color: t.primary, size: 14),
                          const SizedBox(width: 4),
                          Text('Seleccionar',
                              style: TextStyle(
                                  color: t.primary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12)),
                        ]),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),

                  if (_playerIds.isEmpty)
                    GCard(child: Row(children: [
                      Icon(Icons.info_outline, color: t.accent, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Selecciona los jugadores habituales del grupo. '
                          'Los duelos se generan automáticamente.',
                          style: TextStyle(color: t.sub, fontSize: 12),
                        ),
                      ),
                    ]))
                  else
                    GCard(child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _playerIds.map((id) => _playerChip(
                        id: id,
                        name: nameOf(id),
                        color: colorOf(id),
                        t: t,
                        onRemove: () {
                          setState(() {
                            _playerIds.remove(id);
                          });
                          _syncPairRules();
                        },
                      )).toList(),
                    )),

                  const SizedBox(height: 24),

                  // ── Sección 3: Pair Rules ───────────────────────────────
                  Row(children: [
                    Expanded(child: GSectionHeader(title: 'DUELOS Y APUESTAS')),
                    if (_playerIds.length >= 2)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: t.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${_rules.length} duelos',
                          style: TextStyle(
                              color: t.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 4),
                  if (_playerIds.length < 2)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Selecciona al menos 2 jugadores para generar los duelos.',
                        style: TextStyle(color: t.sub, fontSize: 12),
                      ),
                    )
                  else
                    Text(
                      'Cada duelo puede tener apuestas independientes. '
                      'Solo se activarán los duelos cuyos dos jugadores estén presentes en la ronda.',
                      style: TextStyle(color: t.sub, fontSize: 12),
                    ),
                  const SizedBox(height: 12),

                  // Lista de pares
                  ..._rules.map((rule) => _pairRuleCard(
                    rule:        rule,
                    nameA:       shortNameOf(rule.playerAId),
                    nameB:       shortNameOf(rule.playerBId),
                    colorA:      colorOf(rule.playerAId),
                    colorB:      colorOf(rule.playerBId),
                    t:           t,
                    context:     context,
                    directory:   directory,
                  )),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Card de duelo ──────────────────────────────────────────────────────────
  Widget _pairRuleCard({
    required PairBetRule    rule,
    required String         nameA,
    required String         nameB,
    required int            colorA,
    required int            colorB,
    required GolfTheme      t,
    required BuildContext   context,
    required List<PlayerWithLink> directory,
  }) {
    final ruleIdx = _rules.indexWhere((r) => r.id == rule.id);
    final hasModules = rule.modules.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasModules
                ? t.primary.withValues(alpha: 0.35)
                : t.divider,
            width: hasModules ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header del duelo ────────────────────────────────────────
            Row(children: [
              GAvatar(name: nameA, colorIndex: colorA, size: 28),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text('vs',
                    style: TextStyle(
                        color: t.sub,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
              GAvatar(name: nameB, colorIndex: colorB, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$nameA vs $nameB',
                  style: TextStyle(
                      color: t.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 14),
                ),
              ),
              // Badge de N apuestas
              if (hasModules)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: t.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${rule.modules.length} apuesta${rule.modules.length > 1 ? 's' : ''}',
                    style: TextStyle(
                        color: t.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700),
                  ),
                ),
            ]),

            // ── Módulos existentes ────────────────────────────────────
            if (hasModules) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                ...rule.modules.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final tpl = entry.value;
                  return GestureDetector(
                    onTap: () => _editModule(
                      context: context,
                      t: t,
                      ruleIdx: ruleIdx,
                      moduleIdx: idx,
                      tpl: tpl,
                      playerAId: rule.playerAId,
                      playerBId: rule.playerBId,
                      nameA: nameA,
                      nameB: nameB,
                      directory: directory,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: t.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: t.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(tpl.type.icon,
                            style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: 4),
                        Text(
                          '${tpl.type.label} · ${tpl.summaryLabel}',
                          style: TextStyle(
                              color: t.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 12),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => setState(() {
                            final mods = List<BetModuleTemplate>.from(
                                _rules[ruleIdx].modules);
                            mods.removeAt(idx);
                            _rules[ruleIdx] =
                                _rules[ruleIdx].copyWith(modules: mods);
                          }),
                          child: Icon(Icons.close,
                              color: t.sub, size: 13),
                        ),
                      ]),
                    ),
                  );
                }),
              ]),
            ],

            // ── Botón agregar apuesta ───────────────────────────────────
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => _addModule(
                context: context,
                t: t,
                ruleIdx: ruleIdx,
                playerAId: rule.playerAId,
                playerBId: rule.playerBId,
                nameA: nameA,
                nameB: nameB,
                directory: directory,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: t.accent.withValues(alpha: 0.25),
                    style: BorderStyle.solid,
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add, color: t.accent, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    hasModules ? 'Añadir apuesta' : 'Agregar apuesta',
                    style: TextStyle(
                        color: t.accent,
                        fontWeight: FontWeight.w600,
                        fontSize: 12),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Añadir módulo: picker de tipo ──────────────────────────────────────────
  void _addModule({
    required BuildContext context,
    required GolfTheme t,
    required int ruleIdx,
    required String playerAId,
    required String playerBId,
    required String nameA,
    required String nameB,
    required List<PlayerWithLink> directory,
  }) {
    // Mostrar picker de tipo de apuesta
    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final types = BetModuleType.values;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      'Agregar apuesta  •  $nameA vs $nameB',
                      style: TextStyle(
                          color: t.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 16),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Icon(Icons.close, color: t.sub),
                  ),
                ]),
                const SizedBox(height: 16),
                ...types.map((bt) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: t.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(bt.icon,
                          style: const TextStyle(fontSize: 18)),
                    ),
                  ),
                  title: Text(bt.label,
                      style: TextStyle(
                          color: t.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                  subtitle: Text(bt.description,
                      style: TextStyle(color: t.sub, fontSize: 11)),
                  onTap: () {
                    Navigator.pop(ctx);
                    final tpl = BetModuleTemplate.defaultFor(bt);
                    _openModuleEditor(
                      context: context,
                      t: t,
                      ruleIdx: ruleIdx,
                      moduleIdx: null,
                      tpl: tpl,
                      playerAId: playerAId,
                      playerBId: playerBId,
                      nameA: nameA,
                      nameB: nameB,
                      directory: directory,
                    );
                  },
                )),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Editar módulo existente ────────────────────────────────────────────────
  void _editModule({
    required BuildContext context,
    required GolfTheme t,
    required int ruleIdx,
    required int moduleIdx,
    required BetModuleTemplate tpl,
    required String playerAId,
    required String playerBId,
    required String nameA,
    required String nameB,
    required List<PlayerWithLink> directory,
  }) {
    _openModuleEditor(
      context: context,
      t: t,
      ruleIdx: ruleIdx,
      moduleIdx: moduleIdx,
      tpl: tpl,
      playerAId: playerAId,
      playerBId: playerBId,
      nameA: nameA,
      nameB: nameB,
      directory: directory,
    );
  }

  // ── Editor de módulo usando BetModuleEditSheet ─────────────────────────────
  // Convierte BetModuleTemplate → BetModuleInstance temporal, edita con el
  // sheet estándar, y convierte el resultado de vuelta a BetModuleTemplate.
  void _openModuleEditor({
    required BuildContext context,
    required GolfTheme t,
    required int ruleIdx,
    required int? moduleIdx,  // null = nuevo
    required BetModuleTemplate tpl,
    required String playerAId,
    required String playerBId,
    required String nameA,
    required String nameB,
    required List<PlayerWithLink> directory,
  }) {
    // ── Grupo temporal para satisfacer la interfaz de BetModuleEditSheet ──
    final tempGroup = BetGroup(
      id:        'temp_${_uuid.v4()}',
      name:      '$nameA vs $nameB',
      format:    PartidaFormat.allInOnePot,
      playerIds: [playerAId, playerBId],
      modules:   [],
    );

    // ── Instancia temporal a partir de la plantilla ────────────────────────
    final tempInstance = tpl.toInstance(
      id:             'temp_mod_${_uuid.v4()}',
      participantIds: [playerAId, playerBId],
    );

    // ── Players lista para el sheet ────────────────────────────────────────
    final players = directory
        .where((p) => p.player.id == playerAId || p.player.id == playerBId)
        .map((p) => p.player)
        .toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => BetModuleEditSheet(
        group:      tempGroup,
        mod:        tempInstance,
        t:          t,
        players:    players,
        onSave:     (savedInstance) {
          // Convertir BetModuleInstance → BetModuleTemplate
          final newTpl = BetModuleTemplate(
            type:                  savedInstance.type,
            formatMode:            savedInstance.formatMode,
            skinsConfig:           savedInstance.skinsConfig,
            nassauConfig:          savedInstance.nassauConfig,
            matchAutoPressConfig:  savedInstance.matchAutoPressConfig,
            medalConfig:           savedInstance.medalConfig,
            puttsConfig:           savedInstance.puttsConfig,
            oyesesConfig:          savedInstance.oyesesConfig,
            unitsConfig:           savedInstance.unitsConfig,
          );
          setState(() {
            final mods = List<BetModuleTemplate>.from(
                _rules[ruleIdx].modules);
            if (moduleIdx == null) {
              mods.add(newTpl);
            } else {
              mods[moduleIdx] = newTpl;
            }
            _rules[ruleIdx] = _rules[ruleIdx].copyWith(modules: mods);
          });
        },
      ),
    );
  }

  // ── Selector de jugadores ─────────────────────────────────────────────────
  Future<void> _pickPlayers(BuildContext context, GolfTheme t,
      List<PlayerWithLink> directory) async {
    final selected = Set<String>.from(_playerIds);

    await showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSt) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, sc) => Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(children: [
                Expanded(
                  child: Text('Jugadores habituales',
                      style: TextStyle(
                          color: t.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 18)),
                ),
                GestureDetector(
                  onTap: () {
                    setState(() { _playerIds = selected.toList(); });
                    _syncPairRules();
                    Navigator.pop(ctx2);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: t.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('Aplicar',
                        style: TextStyle(
                            color: t.onPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '${selected.length} jugador${selected.length != 1 ? 'es' : ''} seleccionado${selected.length != 1 ? 's' : ''}',
                style: TextStyle(color: t.sub, fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: directory.isEmpty
                  ? Center(
                      child: Text(
                        'No hay jugadores en el directorio.\nAgrega compañeros en la sección "Compañeros".',
                        style: TextStyle(color: t.sub, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      controller: sc,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: directory.length,
                      itemBuilder: (_, i) {
                        final p   = directory[i].player;
                        final sel = selected.contains(p.id);
                        return CheckboxListTile(
                          value: sel,
                          activeColor: t.primary,
                          onChanged: (_) => setSt(() {
                            if (sel) { selected.remove(p.id); }
                            else     { selected.add(p.id); }
                          }),
                          title: Text(p.name,
                              style: TextStyle(
                                  color: t.text,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14)),
                          subtitle: Text('HCP ${p.handicapBase.toStringAsFixed(0)}',
                              style: TextStyle(
                                  color: t.sub, fontSize: 11)),
                          secondary: GAvatar(
                              name: p.name,
                              colorIndex: p.colorIndex,
                              size: 36),
                          controlAffinity: ListTileControlAffinity.trailing,
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Chip de jugador ───────────────────────────────────────────────────────
  Widget _playerChip({
    required String id,
    required String name,
    required int color,
    required GolfTheme t,
    required VoidCallback onRemove,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: t.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: t.primary.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          GAvatar(name: name, colorIndex: color, size: 20),
          const SizedBox(width: 6),
          Text(name.split(' ').first,
              style: TextStyle(
                  color: t.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close, color: t.sub, size: 14),
          ),
        ]),
      );

  // ── Emoji picker ──────────────────────────────────────────────────────────
  void _pickEmoji(BuildContext context, GolfTheme t) {
    const emojis = [
      '⛳', '🏌️', '⛳️', '🥇', '💰', '🏆', '🎯', '🔥', '⚡', '🌟',
      '💎', '🃏', '🤝', '👊', '🎲', '🏅', '💪', '🦅', '🦁', '🐯',
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Selecciona un emoji',
                style: TextStyle(
                    color: t.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 16)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: emojis.map((e) => GestureDetector(
                onTap: () {
                  setState(() { _emoji = e; });
                  Navigator.pop(ctx);
                },
                child: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: _emoji == e
                        ? t.primary.withValues(alpha: 0.15)
                        : t.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _emoji == e
                          ? t.primary
                          : t.divider,
                    ),
                  ),
                  child: Center(
                    child: Text(e,
                        style: const TextStyle(fontSize: 24)),
                  ),
                ),
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
