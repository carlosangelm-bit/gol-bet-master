// ─────────────────────────────────────────────────────────────────────────────
// BETTING GROUP EDITOR SCREEN — Crear / editar un grupo habitual
//
// Secciones:
//   1. Nombre y emoji del grupo
//   2. Jugadores habituales (seleccionar del directorio)
//   3. Pair rules — matriz de duelos con módulos por par
//
// Nuevas funciones (v2):
//   · "Usar partida guardada" al agregar apuesta en un duelo
//   · "Aplicar a múltiples duelos" (botón global en la sección)
//   · "Copiar a otros duelos" por duelo individual
// ─────────────────────────────────────────────────────────────────────────────
import '../../core/golf_icons.dart';
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
import '../../services/firestore_service.dart';
import '../../services/player_service.dart' show PlayerWithLink;

// ── Helper: snapshot de GamePreset → List<BetModuleTemplate> ─────────────────
// Cada duelo recibe una copia independiente (no comparte instancias).
List<BetModuleTemplate> _templatesFromPreset(GamePreset preset) {
  const dummyIds = ['__a__', '__b__'];
  final instances = preset.toModules(dummyIds);
  return instances.map(BetModuleTemplate.fromInstance).toList();
}

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
  late String            _emoji;
  late List<String>      _playerIds;
  late List<PairBetRule> _rules;
  late List<BetModuleTemplate> _dePartida;

  bool _saving = false;

  // Cache de presets cargados perezosamente (se carga la 1ª vez que se necesita)
  List<GamePreset>? _presetsCache;
  bool              _presetsLoading = false;

  @override
  void initState() {
    super.initState();
    final g    = widget.existing;
    _nameCtrl  = TextEditingController(text: g?.name  ?? '');
    _descCtrl  = TextEditingController(text: g?.description ?? '');
    _emoji     = g?.emoji ?? '⛳';
    _playerIds = List<String>.from(g?.playerIds ?? []);
    _rules     = List<PairBetRule>.from(g?.pairRules ?? []);
    _dePartida = List<BetModuleTemplate>.from(g?.modulosDePartida ?? []);
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
        newRules.add(existing[pk] ?? PairBetRule(
          id:        _uuid.v4(),
          playerAId: a,
          playerBId: b,
        ));
      }
    }
    setState(() { _rules = newRules; });
  }

  // ── Carga perezosa de presets guardados ────────────────────────────────────
  Future<List<GamePreset>> _loadPresets() async {
    if (_presetsCache != null) return _presetsCache!;
    setState(() { _presetsLoading = true; });
    try {
      final list = await FirestoreService.getGamePresets();
      _presetsCache = list;
      return list;
    } finally {
      if (mounted) setState(() { _presetsLoading = false; });
    }
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
      modulosDePartida: _dePartida,
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

  // ── Aplicar módulos a varios duelos a la vez (desde GamePreset) ───────────
  // targetIndices == null → todos los duelos
  void _applyPresetToRules(
      GamePreset preset, List<int> targetIndices, {bool replace = false}) {
    final newTemplates = _templatesFromPreset(preset);
    setState(() {
      for (final idx in targetIndices) {
        final current = List<BetModuleTemplate>.from(_rules[idx].modules);
        if (replace) {
          _rules[idx] = _rules[idx].copyWith(modules: List.from(newTemplates));
        } else {
          // Añadir sin duplicar por tipo
          for (final tpl in newTemplates) {
            if (!current.any((m) => m.type == tpl.type)) {
              current.add(tpl);
            }
          }
          _rules[idx] = _rules[idx].copyWith(modules: current);
        }
      }
    });
  }

  /// Añade UNA apuesta a los duelos elegidos.
  ///
  /// No reemplaza nunca. Un duelo que ya tiene ese tipo se SALTA, porque
  /// pisarlo en silencio borraría un monto pactado —y un monto pactado entre dos
  /// personas es justo el dato que este editor existe para guardar—.
  ///
  /// Y se dice cuántos se saltaron. "Añadida a 12 de 15" es un resultado;
  /// "aplicado" a secas deja al usuario sin saber si funcionó.
  void _applyTipoToRules(
      BetModuleType tipo, double? monto, List<int> targetIndices) {
    // El monto se aplica con withBaseValue, así que no hace falta duplicar por
    // cuarta vez los constructores de campos de cada tipo. Nassau devuelve null
    // —tiene tres importes y uno solo no lo describe— y entra con su default.
    var base = BetModuleInstance.defaultFor(tipo, const ['a', 'b'], id: 'tmp');
    if (monto != null && monto > 0) {
      base = base.withBaseValue(monto) ?? base;
    }
    final plantilla = BetModuleTemplate.fromInstance(base);

    var anadidos = 0, yaLaTenian = 0;
    setState(() {
      for (final idx in targetIndices) {
        final actuales = List<BetModuleTemplate>.from(_rules[idx].modules);
        if (actuales.any((m) => m.type == tipo)) {
          yaLaTenian++;
          continue;
        }
        actuales.add(plantilla);
        _rules[idx] = _rules[idx].copyWith(modules: actuales);
        anadidos++;
      }
    });

    if (!mounted) return;
    final total = targetIndices.length;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(anadidos == 0
          ? '${tipo.label}: los $total duelos ya la tenían, no se cambió nada.'
          : yaLaTenian == 0
              ? '${tipo.label} añadida a $anadidos duelo${anadidos == 1 ? '' : 's'}.'
              : '${tipo.label} añadida a $anadidos de $total · '
                  '$yaLaTenian ya la ${yaLaTenian == 1 ? 'tenía' : 'tenían'} y '
                  'no se ${yaLaTenian == 1 ? 'tocó' : 'tocaron'}.'),
      duration: const Duration(seconds: 4),
    ));
  }

  // ── Copiar módulos de un duelo a otros duelos seleccionados ───────────────
  void _copyRuleToOthers(int sourceIdx, List<int> targetIndices) {
    final sourceMods = _rules[sourceIdx].modules;
    setState(() {
      for (final idx in targetIndices) {
        if (idx == sourceIdx) continue;
        // Snapshot independiente por duelo
        _rules[idx] = _rules[idx].copyWith(
          modules: sourceMods.map((m) => BetModuleTemplate(
            type:                  m.type,
            formatMode:            m.formatMode,
            skinsConfig:           m.skinsConfig,
            nassauConfig:          m.nassauConfig,
            matchAutoPressConfig:  m.matchAutoPressConfig,
            medalConfig:           m.medalConfig,
            puttsConfig:           m.puttsConfig,
            oyesesConfig:          m.oyesesConfig,
            unitsConfig:           m.unitsConfig,
            snakeConfig:           m.snakeConfig,
            rabbitConfig:          m.rabbitConfig,
            wolfConfig:            m.wolfConfig,
            stablefordConfig:      m.stablefordConfig,
          )).toList(),
        );
      }
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final prov   = context.watch<RoundProvider>();
    final t      = prov.theme;
    GolfThemeExt.setCurrent(t);
    final bgProv = context.read<BettingGroupProvider>();
    final plProv = context.watch<PlayerProvider>();
    final dir    = plProv.directory;

    String nameOf(String id) {
      try {
        return dir.firstWhere((p) => p.player.id == id).player.name;
      } catch (_) { return id; }
    }
    String shortOf(String id) => nameOf(id).split(' ').first;
    int colorOf(String id) {
      try {
        return dir.firstWhere((p) => p.player.id == id).player.colorIndex;
      } catch (_) { return 0; }
    }

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(children: [

          // ── Header ───────────────────────────────────────────────────────
          _Header(
            isNew:   widget.existing == null,
            saving:  _saving,
            t:       t,
            onClose: () => Navigator.pop(context),
            onSave:  () => _save(bgProv),
          ),

          // ── Contenido ────────────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // ── 1. Nombre y emoji ─────────────────────────────────
                  GSectionHeader(title: 'NOMBRE DEL GRUPO'),
                  const SizedBox(height: 10),
                  GCard(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        _EmojiButton(
                          emoji: _emoji, t: t,
                          onTap: () => _pickEmoji(context, t),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: _StyledTextField(
                          ctrl:      _nameCtrl,
                          hint:      'Ej: Viernes Campestre',
                          t:         t,
                          fontWeight: FontWeight.w700,
                          fontSize:   16,
                        )),
                      ]),
                      const SizedBox(height: 12),
                      _StyledTextField(
                        ctrl:     _descCtrl,
                        hint:     'Descripción opcional',
                        t:        t,
                        maxLines: 2,
                        fontSize: 13,
                      ),
                    ],
                  )),

                  const SizedBox(height: 24),

                  // ── 2. Jugadores ──────────────────────────────────────
                  Row(children: [
                    Expanded(child: GSectionHeader(title: 'JUGADORES HABITUALES')),
                    _SmallButton(
                      icon:  Icons.person_add_outlined,
                      label: 'Seleccionar',
                      t:     t,
                      onTap: () => _pickPlayers(context, t, dir),
                    ),
                  ]),
                  const SizedBox(height: 8),

                  if (_playerIds.isEmpty)
                    GCard(child: Row(children: [
                      Icon(Icons.info_outline, color: t.accent, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        'Selecciona los jugadores habituales. '
                        'Los duelos se generan automáticamente.',
                        style: TextStyle(color: t.sub, fontSize: 12),
                      )),
                    ]))
                  else
                    GCard(child: Wrap(
                      spacing: 8, runSpacing: 8,
                      children: _playerIds.map((id) => _PlayerChip(
                        name:    nameOf(id),
                        color:   colorOf(id),
                        t:       t,
                        onRemove: () {
                          setState(() { _playerIds.remove(id); });
                          _syncPairRules();
                        },
                      )).toList(),
                    )),

                  const SizedBox(height: 24),

                  // ── 3. Apuestas de partida ────────────────────────────
                  //
                  // ANTES de los duelos, y el orden es la explicación: una
                  // apuesta de partida aplica a todos, así que es el caso
                  // general; los duelos son las excepciones. General primero,
                  // excepciones después.
                  Row(children: [
                    Expanded(
                        child: GSectionHeader(title: 'APUESTAS DE LA PARTIDA')),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showPartidaSheet(context, t),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: t.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('Añadir',
                            style: TextStyle(
                                color: t.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text(
                      'Se juegan entre todos los que vengan, no por duelo. '
                      'Snake, Rabbit, Oyes, Unidades y Wolf.',
                      style: TextStyle(color: t.sub, fontSize: 11.5, height: 1.35)),
                  const SizedBox(height: 10),
                  if (_dePartida.isEmpty)
                    Text('Ninguna todavía.',
                        style: TextStyle(color: t.sub, fontSize: 12))
                  else
                    ..._dePartida.asMap().entries.map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: t.card,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: t.divider),
                            ),
                            child: Row(children: [
                              Icon(e.value.type.icono, size: GolfIcons.juntoAValor),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(e.value.type.label,
                                          style: TextStyle(
                                              color: t.text,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13)),
                                      Text(e.value.summaryLabel,
                                          style: TextStyle(
                                              color: t.sub, fontSize: 11)),
                                      // Si el tipo exige un número de
                                      // jugadores, se dice contra los
                                      // habituales del grupo. No es un error
                                      // —puede faltar gente y volverse
                                      // jugable— pero conviene saberlo al
                                      // guardarlo, no el sábado.
                                      if (_avisoTamano(e.value.type) != null)
                                        Text(_avisoTamano(e.value.type)!,
                                            style: TextStyle(
                                                color: t.scoreOver
                                                    .withValues(alpha: 0.9),
                                                fontSize: 10.5,
                                                height: 1.3)),
                                    ]),
                              ),
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => setState(
                                    () => _dePartida.removeAt(e.key)),
                                child: Icon(Icons.delete_outline,
                                    color: t.sub, size: 18),
                              ),
                            ]),
                          ),
                        )),

                  const SizedBox(height: 24),

                  // ── 4. Pair rules ─────────────────────────────────────
                  Row(children: [
                    Expanded(child: GSectionHeader(title: 'DUELOS Y APUESTAS')),
                    if (_rules.isNotEmpty) ...[
                      // Badge de duelos
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
                              color: t.accent, fontSize: 11,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Botón global "Aplicar a múltiples duelos"
                      _SmallButton(
                        icon:  Icons.bolt,
                        // Antes decía 'Aplicar a varios' y solo ofrecía
                        // configuraciones guardadas: se leía como "elige una
                        // apuesta y ponla en todos" y era otra cosa. Con las
                        // dos vías dentro, el nombre ya es cierto.
                        label: 'Aplicar a varios',
                        t:     t,
                        color: t.primary,
                        onTap: () => _showApplyToManySheet(context, t),
                      ),
                    ],
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
                      'Cada duelo tiene apuestas independientes. '
                      'Solo se activan cuando ambos jugadores están en la ronda.',
                      style: TextStyle(color: t.sub, fontSize: 12),
                    ),
                  const SizedBox(height: 12),

                  // Lista de pair rule cards
                  ..._rules.asMap().entries.map((e) => _PairRuleCard(
                    key:        ValueKey(e.value.id),
                    rule:       e.value,
                    ruleIdx:    e.key,
                    nameA:      shortOf(e.value.playerAId),
                    nameB:      shortOf(e.value.playerBId),
                    colorA:     colorOf(e.value.playerAId),
                    colorB:     colorOf(e.value.playerBId),
                    allRules:   _rules,
                    t:          t,
                    directory:  dir,
                    onChanged:  (updated) =>
                        setState(() { _rules[e.key] = updated; }),
                    onAddFromPreset: (presets, targetIdx) =>
                        _showPresetPickerForRule(context, t, presets, targetIdx),
                    onCopyToOthers: (srcIdx, targets) =>
                        _copyRuleToOthers(srcIdx, targets),
                    loadPresets: _loadPresets,
                    openModuleEditor: ({
                      required int ruleIdx,
                      required int? moduleIdx,
                      required BetModuleTemplate tpl,
                      required String playerAId,
                      required String playerBId,
                      required String nameA,
                      required String nameB,
                    }) => _openModuleEditor(
                      context: context, t: t,
                      ruleIdx: ruleIdx, moduleIdx: moduleIdx,
                      tpl: tpl, playerAId: playerAId, playerBId: playerBId,
                      nameA: nameA, nameB: nameB, directory: dir,
                    ),
                  )),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SHEETS / MODALS
  // ══════════════════════════════════════════════════════════════════════════

  // ── Sheet "Aplicar partida guardada a múltiples duelos" ───────────────────
  /// Aviso si este tipo no sería jugable con los habituales del grupo.
  ///
  /// Se calcula con la MISMA función que atenúa el tipo en los selectores y que
  /// decide si entra en la ronda, así que el editor no puede decir una cosa y el
  /// arranque otra.
  ///
  /// Es un AVISO y no un bloqueo: el grupo de los viernes puede ser de seis y
  /// jugar Wolf casi todos los sábados porque suelen faltar dos. Prohibirlo por
  /// lo que pasa cuando vienen todos sería quitarle el formato el resto de las
  /// veces.
  String? _avisoTamano(BetModuleType tipo) {
    final motivo = tipo.motivoNoDisponible(_playerIds.length);
    if (motivo == null) return null;
    return 'Con los ${_playerIds.length} habituales no entra. Se juega los días '
        'que venga el número que pide.';
  }

  /// Hoja para añadir una apuesta de partida.
  ///
  /// Los tipos salen de la marca deLaPartida, no de una lista: es lo que impide
  /// que el próximo formato de partida se quede fuera sin que nada falle.
  void _showPartidaSheet(BuildContext context, GolfTheme t) {
    final candidatos = creatableBetTypes
        .where((tipo) => tipo.rules.deLaPartida)
        .where((tipo) => !_dePartida.any((m) => m.type == tipo))
        .toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: t.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(
                child: Text('Apuesta de la partida',
                    style: TextStyle(
                        color: t.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 17)),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Icon(Icons.close, color: t.sub),
              ),
            ]),
            const SizedBox(height: 4),
            Text('Se juega entre todos los presentes, con su monto guardado.',
                style: TextStyle(color: t.sub, fontSize: 12)),
            const SizedBox(height: 14),
            if (candidatos.isEmpty)
              Text('Ya están todas añadidas.',
                  style: TextStyle(color: t.sub, fontSize: 12))
            else
              ...candidatos.map((tipo) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        Navigator.pop(ctx);
                        setState(() => _dePartida
                            .add(BetModuleTemplate.defaultFor(tipo)));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 11),
                        decoration: BoxDecoration(
                          color: t.card,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: t.divider),
                        ),
                        child: Row(children: [
                          Icon(tipo.icono, size: GolfIcons.juntoAValor),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(tipo.label,
                                      style: TextStyle(
                                          color: t.text,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13)),
                                  Text(tipo.description,
                                      style: TextStyle(
                                          color: t.sub,
                                          fontSize: 10.5,
                                          height: 1.3)),
                                  if (_avisoTamano(tipo) != null)
                                    Text(_avisoTamano(tipo)!,
                                        style: TextStyle(
                                            color: t.scoreOver
                                                .withValues(alpha: 0.9),
                                            fontSize: 10.5,
                                            height: 1.3)),
                                ]),
                          ),
                          Icon(Icons.add_circle_outline, color: t.sub, size: 18),
                        ]),
                      ),
                    ),
                  )),
          ]),
        ),
      ),
    );
  }

  void _showApplyToManySheet(BuildContext context, GolfTheme t) {
    // Ya NO se exige tener configuraciones guardadas para abrir. Con la vía de
    // "una apuesta" la hoja es útil sin ninguna, y el mensaje de "crea una en
    // Ajustes" mandaba a dar un rodeo para algo que ahora se hace aquí.
    _loadPresets().then((presets) {
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => _ApplyToManySheet(
          presets:    presets,
          rules:      _rules,
          t:          t,
          onApply:    (preset, selectedIndices, replace) {
            Navigator.pop(context);
            _applyPresetToRules(preset, selectedIndices, replace: replace);
          },
          onApplyTipo: (tipo, monto, selectedIndices) {
            Navigator.pop(context);
            _applyTipoToRules(tipo, monto, selectedIndices);
          },
        ),
      );
    });
  }

  // ── Picker de preset para un duelo individual ─────────────────────────────
  void _showPresetPickerForRule(
      BuildContext context, GolfTheme t,
      List<GamePreset> presets, int ruleIdx) {
    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _PresetPickerSheet(
        presets: presets,
        t:       t,
        onPick:  (preset) {
          Navigator.pop(ctx);
          final newMods = _templatesFromPreset(preset);
          setState(() {
            final current = List<BetModuleTemplate>.from(_rules[ruleIdx].modules);
            for (final m in newMods) {
              if (!current.any((c) => c.type == m.type)) current.add(m);
            }
            _rules[ruleIdx] = _rules[ruleIdx].copyWith(modules: current);
          });
        },
      ),
    );
  }

  // ── Editor de módulo usando BetModuleEditSheet ─────────────────────────────
  void _openModuleEditor({
    required BuildContext context,
    required GolfTheme t,
    required int ruleIdx,
    required int? moduleIdx,
    required BetModuleTemplate tpl,
    required String playerAId,
    required String playerBId,
    required String nameA,
    required String nameB,
    required List<PlayerWithLink> directory,
  }) {
    final tempGroup = BetGroup(
      id:        'temp_${_uuid.v4()}',
      name:      '$nameA vs $nameB',
      format:    PartidaFormat.allInOnePot,
      playerIds: [playerAId, playerBId],
      modules:   [],
    );
    final tempInstance = tpl.toInstance(
      id:             'temp_mod_${_uuid.v4()}',
      participantIds: [playerAId, playerBId],
    );
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
        group:   tempGroup,
        mod:     tempInstance,
        t:       t,
        players: players,
        onSave:  (saved) {
          final newTpl = BetModuleTemplate.fromInstance(saved);
          setState(() {
            final mods = List<BetModuleTemplate>.from(_rules[ruleIdx].modules);
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
                Expanded(child: Text('Jugadores habituales',
                    style: TextStyle(color: t.text,
                        fontWeight: FontWeight.w800, fontSize: 18))),
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
                        style: TextStyle(color: t.onPrimary,
                            fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '${selected.length} seleccionado${selected.length != 1 ? 's' : ''}',
                style: TextStyle(color: t.sub, fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: directory.isEmpty
                  ? Center(child: Text(
                      'No hay jugadores.\nAgrega compañeros en Ajustes.',
                      style: TextStyle(color: t.sub, fontSize: 13),
                      textAlign: TextAlign.center,
                    ))
                  : ListView.builder(
                      controller: sc,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: directory.length,
                      itemBuilder: (_, i) {
                        final p   = directory[i].player;
                        final sel = selected.contains(p.id);
                        return CheckboxListTile(
                          value:       sel,
                          activeColor: t.primary,
                          onChanged:   (_) => setSt(() {
                            if (sel) {
                              selected.remove(p.id);
                            } else {
                              selected.add(p.id);
                            }
                          }),
                          title: Text(p.name,
                              style: TextStyle(color: t.text,
                                  fontWeight: FontWeight.w700, fontSize: 14)),
                          subtitle: Text('HCP ${p.handicapBase.toStringAsFixed(0)}',
                              style: TextStyle(color: t.sub, fontSize: 11)),
                          secondary: GAvatar(name: p.name,
                              colorIndex: p.colorIndex, size: 36),
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Selecciona un emoji',
              style: TextStyle(color: t.text,
                  fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12, runSpacing: 12,
            children: emojis.map((e) => GestureDetector(
              onTap: () {
                setState(() { _emoji = e; });
                Navigator.pop(ctx);
              },
              child: Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color:  _emoji == e
                      ? t.primary.withValues(alpha: 0.15) : t.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: _emoji == e ? t.primary : t.divider),
                ),
                child: Center(child: Text(e,
                    style: const TextStyle(fontSize: 24))),
              ),
            )).toList(),
          ),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SUBWIDGETS PRIVADOS
// ═════════════════════════════════════════════════════════════════════════════

// ── Header de pantalla ───────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  const _Header({
    required this.isNew,
    required this.saving,
    required this.t,
    required this.onClose,
    required this.onSave,
  });
  final bool         isNew;
  final bool         saving;
  final GolfTheme    t;
  final VoidCallback onClose;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    decoration: BoxDecoration(
      color: t.bg,
      border: Border(bottom: BorderSide(color: t.divider)),
    ),
    child: Row(children: [
      GestureDetector(
        onTap: onClose,
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
      Expanded(child: Text(
        isNew ? 'Nuevo Betting Group' : 'Editar Betting Group',
        style: TextStyle(color: t.text,
            fontWeight: FontWeight.w800, fontSize: 18),
      )),
      GestureDetector(
        onTap: saving ? null : onSave,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: saving ? t.divider : t.primary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: saving
              ? SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: t.onPrimary))
              : Text('Guardar',
                  style: TextStyle(color: t.onPrimary,
                      fontWeight: FontWeight.w700, fontSize: 14)),
        ),
      ),
    ]),
  );
}

// ── Botón emoji ──────────────────────────────────────────────────────────────
class _EmojiButton extends StatelessWidget {
  const _EmojiButton({required this.emoji, required this.t, required this.onTap});
  final String     emoji;
  final GolfTheme  t;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 52, height: 52,
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.divider),
      ),
      child: Center(child: Text(emoji,
          style: const TextStyle(fontSize: 26))),
    ),
  );
}

// ── TextField estilizado ─────────────────────────────────────────────────────
class _StyledTextField extends StatelessWidget {
  const _StyledTextField({
    required this.ctrl,
    required this.hint,
    required this.t,
    this.maxLines  = 1,
    this.fontWeight = FontWeight.normal,
    this.fontSize   = 14,
  });
  final TextEditingController ctrl;
  final String     hint;
  final GolfTheme  t;
  final int        maxLines;
  final FontWeight fontWeight;
  final double     fontSize;

  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    maxLines:   maxLines,
    style: TextStyle(color: t.text, fontWeight: fontWeight, fontSize: fontSize),
    decoration: InputDecoration(
      hintText:  hint,
      hintStyle: TextStyle(color: t.sub.withValues(alpha: 0.6), fontSize: fontSize - 1),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      fillColor:   t.surface,
      filled:      true,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: t.divider)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: t.divider)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: t.primary, width: 1.5)),
    ),
  );
}

// ── Botón pequeño de acción ──────────────────────────────────────────────────
class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.icon,
    required this.label,
    required this.t,
    required this.onTap,
    this.color,
  });
  final IconData   icon;
  final String     label;
  final GolfTheme  t;
  final VoidCallback onTap;
  final Color?     color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? t.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: c, size: 14),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(color: c,
                  fontWeight: FontWeight.w700, fontSize: 12)),
        ]),
      ),
    );
  }
}

// ── Chip de jugador ──────────────────────────────────────────────────────────
class _PlayerChip extends StatelessWidget {
  const _PlayerChip({
    required this.name,
    required this.color,
    required this.t,
    required this.onRemove,
  });
  final String     name;
  final int        color;
  final GolfTheme  t;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
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
          style: TextStyle(color: t.text,
              fontWeight: FontWeight.w600, fontSize: 13)),
      const SizedBox(width: 4),
      GestureDetector(
        onTap: onRemove,
        child: Icon(Icons.close, color: t.sub, size: 14),
      ),
    ]),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// PAIR RULE CARD (StatefulWidget propio para gestionar su menú)
// ═════════════════════════════════════════════════════════════════════════════
class _PairRuleCard extends StatefulWidget {
  const _PairRuleCard({
    super.key,
    required this.rule,
    required this.ruleIdx,
    required this.nameA,
    required this.nameB,
    required this.colorA,
    required this.colorB,
    required this.allRules,
    required this.t,
    required this.directory,
    required this.onChanged,
    required this.onAddFromPreset,
    required this.onCopyToOthers,
    required this.loadPresets,
    required this.openModuleEditor,
  });

  final PairBetRule              rule;
  final int                      ruleIdx;
  final String                   nameA;
  final String                   nameB;
  final int                      colorA;
  final int                      colorB;
  final List<PairBetRule>        allRules;
  final GolfTheme                t;
  final List<PlayerWithLink>     directory;
  final void Function(PairBetRule) onChanged;
  final void Function(List<GamePreset>, int) onAddFromPreset;
  final void Function(int srcIdx, List<int> targets) onCopyToOthers;
  final Future<List<GamePreset>> Function() loadPresets;
  final void Function({
    required int ruleIdx,
    required int? moduleIdx,
    required BetModuleTemplate tpl,
    required String playerAId,
    required String playerBId,
    required String nameA,
    required String nameB,
  }) openModuleEditor;

  @override
  State<_PairRuleCard> createState() => _PairRuleCardState();
}

class _PairRuleCardState extends State<_PairRuleCard> {

  // ── Agregar módulo: picker 2 opciones ────────────────────────────────────
  void _showAddModuleSheet(BuildContext context) {
    final t = widget.t;
    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Título
              Row(children: [
                Expanded(child: Text(
                  'Agregar apuesta  •  ${widget.nameA} vs ${widget.nameB}',
                  style: TextStyle(color: t.text,
                      fontWeight: FontWeight.w800, fontSize: 16),
                )),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Icon(Icons.close, color: t.sub),
                ),
              ]),
              const SizedBox(height: 16),

              // Opción A: Usar partida guardada
              _OptionTile(
                icon:     Icons.bookmark_outlined,
                iconColor: t.primary,
                title:    'Usar partida guardada',
                subtitle: 'Importar configuración de una partida existente',
                t:        t,
                onTap:    () {
                  Navigator.pop(ctx);
                  widget.loadPresets().then((presets) {
                    if (!mounted) return;
                    if (presets.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('No hay partidas guardadas.'),
                      ));
                      return;
                    }
                    widget.onAddFromPreset(presets, widget.ruleIdx);
                  });
                },
              ),

              Divider(color: t.divider, height: 20),

              // Opción B: Crear nueva (lista de tipos)
              Text('Crear nueva apuesta',
                  style: TextStyle(color: t.sub,
                      fontWeight: FontWeight.w700, fontSize: 12)),
              const SizedBox(height: 8),
              ...creatableBetTypes.map((bt) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: t.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(child: Icon(bt.icono, size: GolfIcons.juntoAValor)),
                ),
                title: Text(bt.label,
                    style: TextStyle(color: t.text,
                        fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: Text(bt.description,
                    style: TextStyle(color: t.sub, fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  final tpl = BetModuleTemplate.defaultFor(bt);
                  widget.openModuleEditor(
                    ruleIdx:   widget.ruleIdx,
                    moduleIdx: null,
                    tpl:       tpl,
                    playerAId: widget.rule.playerAId,
                    playerBId: widget.rule.playerBId,
                    nameA:     widget.nameA,
                    nameB:     widget.nameB,
                  );
                },
              )),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sheet "Copiar a otros duelos" ─────────────────────────────────────────
  void _showCopyToOthersSheet(BuildContext context) {
    final t       = widget.t;
    final others  = widget.allRules.asMap().entries
        .where((e) => e.key != widget.ruleIdx)
        .toList();
    if (others.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Solo hay un duelo, no hay a dónde copiar.'),
      ));
      return;
    }

    final selected = <int>{};
    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSt) => DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.35,
          maxChildSize: 0.85,
          expand: false,
          builder: (_, sc) => Column(children: [
            // Handle
            Center(child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: t.divider,
                  borderRadius: BorderRadius.circular(2)),
            )),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Copiar apuestas a...',
                        style: TextStyle(color: t.text,
                            fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(
                      'Módulos de ${widget.nameA} vs ${widget.nameB} '
                      '→ duelos seleccionados',
                      style: TextStyle(color: t.sub, fontSize: 11),
                    ),
                  ],
                )),
                TextButton(
                  onPressed: selected.isEmpty ? null : () {
                    Navigator.pop(ctx2);
                    widget.onCopyToOthers(widget.ruleIdx, selected.toList());
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                        'Copiado a ${selected.length} duelo${selected.length > 1 ? 's' : ''}'),
                    ));
                  },
                  child: Text('Copiar (${selected.length})',
                      style: TextStyle(color: t.primary,
                          fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
            // Select all toggle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                Expanded(child: Text('Seleccionar todos',
                    style: TextStyle(color: t.sub, fontSize: 12))),
                Switch(
                  value:     selected.length == others.length,
                  onChanged: (_) => setSt(() {
                    if (selected.length == others.length) {
                      selected.clear();
                    } else {
                      selected.addAll(others.map((e) => e.key));
                    }
                  }),
                  activeThumbColor: t.primary,
                ),
              ]),
            ),
            Divider(color: t.divider, height: 1),
            Expanded(
              child: ListView(
                controller: sc,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: others.map((e) {
                  final rule = e.value;
                  final nameA2 = _shortNameFromDirectory(
                      rule.playerAId, widget.directory);
                  final nameB2 = _shortNameFromDirectory(
                      rule.playerBId, widget.directory);
                  final sel = selected.contains(e.key);
                  return CheckboxListTile(
                    value:       sel,
                    activeColor: t.primary,
                    onChanged:   (_) => setSt(() {
                      if (sel) {
                        selected.remove(e.key);
                      } else {
                        selected.add(e.key);
                      }
                    }),
                    title: Text('$nameA2 vs $nameB2',
                        style: TextStyle(color: t.text,
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    subtitle: rule.modules.isEmpty
                        ? Text('Sin apuestas',
                            style: TextStyle(color: t.sub, fontSize: 11))
                        : Text(
                            rule.modules.map((m) => m.type.label).join(', '),
                            style: TextStyle(color: t.sub, fontSize: 11),
                          ),
                    controlAffinity: ListTileControlAffinity.trailing,
                  );
                }).toList(),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  String _shortNameFromDirectory(String id, List<PlayerWithLink> dir) {
    try {
      return dir.firstWhere((p) => p.player.id == id).player.name.split(' ').first;
    } catch (_) { return id; }
  }

  @override
  Widget build(BuildContext context) {
    final t      = widget.t;
    final rule   = widget.rule;
    final hasM   = rule.modules.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasM ? t.primary.withValues(alpha: 0.35) : t.divider,
            width: hasM ? 1.5 : 1,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Header del duelo ─────────────────────────────────────────
          Row(children: [
            GAvatar(name: widget.nameA, colorIndex: widget.colorA, size: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('vs',
                  style: TextStyle(color: t.sub,
                      fontSize: 11, fontWeight: FontWeight.w600)),
            ),
            GAvatar(name: widget.nameB, colorIndex: widget.colorB, size: 28),
            const SizedBox(width: 10),
            Expanded(child: Text('${widget.nameA} vs ${widget.nameB}',
                style: TextStyle(color: t.text,
                    fontWeight: FontWeight.w700, fontSize: 14))),

            // Badge de N apuestas
            if (hasM)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: t.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${rule.modules.length} apuesta${rule.modules.length > 1 ? 's' : ''}',
                  style: TextStyle(color: t.primary,
                      fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),

            // Menú contextual
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: t.sub, size: 18),
              color: t.card,
              onSelected: (v) {
                if (v == 'copy') _showCopyToOthersSheet(context);
                if (v == 'clear') {
                  widget.onChanged(rule.copyWith(modules: []));
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'copy',
                  child: Row(children: [
                    Icon(Icons.copy_outlined, size: 16, color: t.text),
                    const SizedBox(width: 8),
                    Text('Copiar a otros duelos',
                        style: TextStyle(color: t.text, fontSize: 13)),
                  ]),
                ),
                if (hasM)
                  PopupMenuItem(
                    value: 'clear',
                    child: Row(children: [
                      Icon(Icons.delete_sweep_outlined, size: 16, color: t.danger),
                      const SizedBox(width: 8),
                      Text('Limpiar apuestas',
                          style: TextStyle(color: t.danger, fontSize: 13)),
                    ]),
                  ),
              ],
            ),
          ]),

          // ── Chips de módulos ─────────────────────────────────────────
          if (hasM) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6,
              children: rule.modules.asMap().entries.map((entry) {
                final idx = entry.key;
                final tpl = entry.value;
                return GestureDetector(
                  onTap: () => widget.openModuleEditor(
                    ruleIdx:   widget.ruleIdx,
                    moduleIdx: idx,
                    tpl:       tpl,
                    playerAId: rule.playerAId,
                    playerBId: rule.playerBId,
                    nameA:     widget.nameA,
                    nameB:     widget.nameB,
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
                      Icon(tpl.type.icono, size: GolfIcons.juntoAEtiqueta),
                      const SizedBox(width: 4),
                      Text(
                        '${tpl.type.label} · ${tpl.summaryLabel}',
                        style: TextStyle(color: t.primary,
                            fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () {
                          final mods = List<BetModuleTemplate>.from(
                              rule.modules)..removeAt(idx);
                          widget.onChanged(rule.copyWith(modules: mods));
                        },
                        child: Icon(Icons.close, color: t.sub, size: 13),
                      ),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ],

          // ── Botón agregar apuesta ────────────────────────────────────
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => _showAddModuleSheet(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: t.accent.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.accent.withValues(alpha: 0.25)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add, color: t.accent, size: 14),
                const SizedBox(width: 4),
                Text(hasM ? 'Añadir apuesta' : 'Agregar apuesta',
                    style: TextStyle(color: t.accent,
                        fontWeight: FontWeight.w600, fontSize: 12)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SHEETS INDEPENDIENTES
// ═════════════════════════════════════════════════════════════════════════════

// ── Picker de preset para un duelo ──────────────────────────────────────────
class _PresetPickerSheet extends StatelessWidget {
  const _PresetPickerSheet({
    required this.presets,
    required this.t,
    required this.onPick,
  });
  final List<GamePreset>         presets;
  final GolfTheme                t;
  final void Function(GamePreset) onPick;

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: 0.55,
    minChildSize: 0.35,
    maxChildSize: 0.85,
    expand: false,
    builder: (_, sc) => Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        // Handle
        Center(child: Container(
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          width: 40, height: 4,
          decoration: BoxDecoration(
              color: t.divider, borderRadius: BorderRadius.circular(2)),
        )),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Row(children: [
            Expanded(child: Text('Usar partida guardada',
                style: TextStyle(color: t.text,
                    fontWeight: FontWeight.w800, fontSize: 17))),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Icon(Icons.close, color: t.sub),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Los módulos se copian como snapshot independiente. '
            'Modificar el duelo no afecta la partida original.',
            style: TextStyle(color: t.sub, fontSize: 12),
          ),
        ),
        const SizedBox(height: 8),
        Divider(color: t.divider, height: 1),
        Expanded(
          child: ListView.builder(
            controller: sc,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            itemCount: presets.length,
            itemBuilder: (_, i) {
              final p = presets[i];
              // Obtener lista de tipos de módulos del preset
              final types = _presetModuleTypes(p);
              return ListTile(
                leading: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: t.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(child: Text(p.emoji,
                      style: const TextStyle(fontSize: 22))),
                ),
                title: Text(p.name,
                    style: TextStyle(color: t.text,
                        fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: types.isNotEmpty
                    ? Text(types.join(' · '),
                        style: TextStyle(color: t.sub, fontSize: 11))
                    : null,
                trailing: Icon(Icons.arrow_forward_ios,
                    color: t.sub, size: 14),
                onTap: () => onPick(p),
              );
            },
          ),
        ),
      ]),
    ),
  );

  List<String> _presetModuleTypes(GamePreset p) {
    try {
      const dummyIds = ['__a__', '__b__'];
      final instances = p.toModules(dummyIds);
      return instances.map((m) => '${m.type.label}').toList();
    } catch (_) { return []; }
  }
}

// ── Sheet "Aplicar a múltiples duelos" ───────────────────────────────────────
/// Las dos maneras de aplicar algo a varios duelos.
///
/// Responden a preguntas distintas: "quiero meter Putts en todos" y "quiero el
/// paquete de los viernes". Antes solo existía la segunda, y el botón se llamaba
/// como si hiciera la primera.
enum _ViaAplicar { unaApuesta, configuracion }

class _ApplyToManySheet extends StatefulWidget {
  const _ApplyToManySheet({
    required this.presets,
    required this.rules,
    required this.t,
    required this.onApply,
    required this.onApplyTipo,
  });
  final List<GamePreset>     presets;
  final List<PairBetRule>    rules;
  final GolfTheme            t;
  final void Function(GamePreset preset, List<int> indices, bool replace) onApply;
  final void Function(BetModuleType tipo, double? monto, List<int> indices)
      onApplyTipo;

  @override
  State<_ApplyToManySheet> createState() => _ApplyToManySheetState();
}

class _ApplyToManySheetState extends State<_ApplyToManySheet> {
  _ViaAplicar  _via = _ViaAplicar.unaApuesta;
  GamePreset?  _selected;
  BetModuleType? _tipo;
  final _montoCtrl = TextEditingController();
  Set<int>     _targetIndices = {};
  bool         _replaceMode   = false;   // false = añadir, true = reemplazar

  @override
  void dispose() {
    _montoCtrl.dispose();
    super.dispose();
  }

  /// Qué falta para poder aplicar, en orden de lectura.
  ///
  /// El primer hueco manda: decir "selecciona duelos" cuando aún no se ha
  /// elegido QUÉ aplicar manda a hacer el segundo paso antes del primero.
  String get _etiquetaBoton {
    if (_via == _ViaAplicar.configuracion && _selected == null) {
      return 'Elige una configuración';
    }
    if (_via == _ViaAplicar.unaApuesta && _tipo == null) {
      return 'Elige una apuesta';
    }
    if (_targetIndices.isEmpty) return 'Elige los duelos';
    final n = _targetIndices.length;
    return 'Aplicar a $n duelo${n == 1 ? '' : 's'}';
  }

  bool get _listoParaAplicar =>
      _targetIndices.isNotEmpty &&
      (_via == _ViaAplicar.configuracion ? _selected != null : _tipo != null);

  /// true si este tipo acepta un importe único.
  ///
  /// Se PREGUNTA al modelo con withBaseValue en vez de mantener una lista:
  /// Nassau devuelve null porque tiene tres importes y uno solo no lo describe,
  /// y esa es la misma razón por la que su regla no admite monto por pareja.
  bool _aceptaMonto(BetModuleType t) =>
      BetModuleInstance.defaultFor(t, const ['a', 'b'], id: 'x')
          .withBaseValue(1) !=
      null;

  @override
  Widget build(BuildContext context) {
    final t    = widget.t;
    final allSelected = _targetIndices.length == widget.rules.length;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize:     0.5,
      maxChildSize:     0.95,
      expand: false,
      builder: (_, sc) => Container(
        decoration: BoxDecoration(
          color: t.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          // Handle
          Center(child: Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: t.divider, borderRadius: BorderRadius.circular(2)),
          )),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Aplicar a múltiples duelos',
                      style: TextStyle(color: t.text,
                          fontWeight: FontWeight.w800, fontSize: 17)),
                  Text('Una apuesta o una configuración, y a qué duelos',
                      style: TextStyle(color: t.sub, fontSize: 12)),
                ],
              )),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Icon(Icons.close, color: t.sub),
              ),
            ]),
          ),
          Divider(color: t.divider, height: 1),

          Expanded(
            child: ListView(
              controller: sc,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [

                // ── 1. Qué se aplica ───────────────────────────────────
                Text('1. Qué se aplica',
                    style: TextStyle(color: t.text,
                        fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 8),
                Row(children: [
                  for (final v in _ViaAplicar.values)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _via = v),
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          decoration: BoxDecoration(
                            color: _via == v
                                ? t.primary.withValues(alpha: 0.12)
                                : t.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: _via == v ? t.primary : t.divider,
                                width: _via == v ? 1.6 : 1),
                          ),
                          child: Text(
                            v == _ViaAplicar.unaApuesta
                                ? 'Una apuesta'
                                : 'Una configuración',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _via == v ? t.primary : t.sub,
                              fontSize: 12.5,
                              fontWeight: _via == v
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 12),

                // ── Vía A: una apuesta suelta ──────────────────────────
                //
                // Los tipos salen de betTypeSections, la misma fuente que las
                // tres hojas de "Agregar apuesta". Ni una lista literal.
                if (_via == _ViaAplicar.unaApuesta) ...[
                  for (final sec in betTypeSections) ...[
                    Text(sec.familia.label,
                        style: TextStyle(color: t.sub, fontSize: 10,
                            fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                    const SizedBox(height: 6),
                    ...sec.tipos.map((bt) => _FilaTipo(
                          tipo: bt,
                          seleccionada: _tipo == bt,
                          t: t,
                          onTap: () => setState(() {
                            _tipo = bt;
                            _montoCtrl.text = _aceptaMonto(bt)
                                ? BetModuleInstance
                                    .defaultFor(bt, const ['a', 'b'], id: 'x')
                                    .value
                                    .toStringAsFixed(0)
                                : '';
                          }),
                        )),
                    const SizedBox(height: 12),
                  ],
                  // El importe, solo donde un número único describe la apuesta.
                  // Sin esto, aplicar Putts a quince duelos con el valor por
                  // defecto obliga a entrar en los quince: no resuelve nada.
                  if (_tipo != null && _aceptaMonto(_tipo!)) ...[
                    Text('Importe', style: TextStyle(color: t.sub,
                        fontSize: 11, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _montoCtrl,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: t.text),
                      decoration: InputDecoration(
                        prefixText: '\$ ',
                        isDense: true,
                        fillColor: t.surface, filled: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: t.divider)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: t.divider)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('Se aplica el mismo importe a todos los duelos '
                        'elegidos. Después se puede ajustar duelo a duelo.',
                        style: TextStyle(color: t.sub, fontSize: 11,
                            fontStyle: FontStyle.italic)),
                  ] else if (_tipo == BetModuleType.nassau) ...[
                    Text('Nassau tiene tres importes —Front, Back y Total— así '
                        'que entra con su configuración por defecto y se ajusta '
                        'en cada duelo.',
                        style: TextStyle(color: t.sub, fontSize: 11,
                            fontStyle: FontStyle.italic)),
                  ],
                  const SizedBox(height: 8),
                ],

                // ── Vía B: una configuración guardada ──────────────────
                if (_via == _ViaAplicar.configuracion && widget.presets.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: t.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: t.divider),
                    ),
                    child: Text(
                        'No tienes configuraciones guardadas. Se crean en '
                        'Ajustes → Mis Configuraciones. Para meter UNA apuesta '
                        'en varios duelos no hace falta: usa la otra vía.',
                        style: TextStyle(color: t.sub, fontSize: 12, height: 1.4)),
                  ),
                if (_via == _ViaAplicar.configuracion)
                ...widget.presets.map((p) {
                  final sel = _selected?.id == p.id;
                  return GestureDetector(
                    onTap: () => setState(() { _selected = p; }),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: sel
                            ? t.primary.withValues(alpha: 0.1) : t.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: sel ? t.primary : t.divider,
                          width: sel ? 1.5 : 1,
                        ),
                      ),
                      child: Row(children: [
                        Text(p.emoji,
                            style: const TextStyle(fontSize: 20)),
                        const SizedBox(width: 10),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name,
                                style: TextStyle(color: t.text,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                            if (p.description.isNotEmpty)
                              Text(p.description,
                                  style: TextStyle(color: t.sub,
                                      fontSize: 11),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                          ],
                        )),
                        if (sel)
                          Icon(Icons.check_circle,
                              color: t.primary, size: 18),
                      ]),
                    ),
                  );
                }),

                const SizedBox(height: 20),

                // ── 2. Elegir duelos destino ───────────────────────────
                Row(children: [
                  Expanded(child: Text('2. Elige los duelos',
                      style: TextStyle(color: t.text,
                          fontWeight: FontWeight.w700, fontSize: 13))),
                  // Toggle "todos"
                  GestureDetector(
                    onTap: () => setState(() {
                      if (allSelected) {
                        _targetIndices.clear();
                      } else {
                        _targetIndices = Set.from(
                            Iterable.generate(widget.rules.length));
                      }
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: allSelected
                            ? t.primary.withValues(alpha: 0.12) : t.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: allSelected ? t.primary : t.divider,
                        ),
                      ),
                      child: Text(
                        allSelected ? 'Deseleccionar todos' : 'Todos',
                        style: TextStyle(
                          color: allSelected ? t.primary : t.sub,
                          fontSize: 11, fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                ...widget.rules.asMap().entries.map((e) {
                  final idx  = e.key;
                  final rule = e.value;
                  final sel  = _targetIndices.contains(idx);
                  return GestureDetector(
                    onTap: () => setState(() {
                      if (sel) {
                        _targetIndices.remove(idx);
                      } else {
                        _targetIndices.add(idx);
                      }
                    }),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: sel
                            ? t.primary.withValues(alpha: 0.07) : t.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: sel ? t.primary : t.divider,
                          width: sel ? 1.5 : 1,
                        ),
                      ),
                      child: Row(children: [
                        Icon(
                          sel
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          color: sel ? t.primary : t.sub, size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: _RuleSummaryText(
                          rule: rule, t: t)),
                      ]),
                    ),
                  );
                }),

                const SizedBox(height: 20),

                // ── 3. Modo de aplicación ─────────────────────────────
                //
                // Solo para la vía de configuración. Una apuesta suelta NUNCA
                // reemplaza: un duelo que ya la tiene se salta, porque pisarlo
                // borraría un monto pactado entre dos personas, que es justo el
                // dato que este editor existe para guardar. Y se dice cuántos se
                // saltaron al terminar.
                if (_via == _ViaAplicar.configuracion) ...[
                  Text('3. Modo de aplicación',
                      style: TextStyle(color: t.text,
                          fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 8),
                  _ModeToggle(
                    replace: _replaceMode,
                    t: t,
                    onChange: (v) => setState(() { _replaceMode = v; }),
                  ),
                ] else
                  Text('Los duelos que ya tengan esa apuesta se dejan como '
                      'están: no se pisa un monto ya pactado.',
                      style: TextStyle(color: t.sub, fontSize: 11,
                          fontStyle: FontStyle.italic)),

                const SizedBox(height: 24),

                // ── Botón Aplicar ─────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: !_listoParaAplicar
                        ? null
                        : () {
                            if (_via == _ViaAplicar.configuracion) {
                              widget.onApply(_selected!,
                                  _targetIndices.toList(), _replaceMode);
                            } else {
                              widget.onApplyTipo(
                                  _tipo!,
                                  double.tryParse(_montoCtrl.text),
                                  _targetIndices.toList());
                            }
                          },
                    icon: const Icon(Icons.bolt, size: 16),
                    label: Text(_etiquetaBoton),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: t.primary,
                      foregroundColor: t.onPrimary,
                      disabledBackgroundColor: t.divider,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Resumen de una regla (para la lista de selección) ────────────────────────
class _RuleSummaryText extends StatelessWidget {
  const _RuleSummaryText({required this.rule, required this.t});
  final PairBetRule rule;
  final GolfTheme   t;

  @override
  Widget build(BuildContext context) {
    final plProv = context.read<PlayerProvider>();
    String short(String id) {
      try {
        return plProv.directory
            .firstWhere((p) => p.player.id == id)
            .player.name.split(' ').first;
      } catch (_) { return id; }
    }
    final nameA = short(rule.playerAId);
    final nameB = short(rule.playerBId);
    final mods  = rule.modules;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$nameA vs $nameB',
          style: TextStyle(color: t.text,
              fontWeight: FontWeight.w700, fontSize: 13)),
      if (mods.isNotEmpty)
        Text(mods.map((m) => m.type.label).join(' · '),
            style: TextStyle(color: t.sub, fontSize: 11))
      else
        Text('Sin apuestas',
            style: TextStyle(color: t.sub, fontSize: 11)),
    ]);
  }
}

// ── Toggle Añadir / Reemplazar ───────────────────────────────────────────────
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.replace,
    required this.t,
    required this.onChange,
  });
  final bool      replace;
  final GolfTheme t;
  final void Function(bool) onChange;

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: GestureDetector(
      onTap: () => onChange(false),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: !replace
              ? t.primary.withValues(alpha: 0.1) : t.card,
          borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(8)),
          border: Border.all(color: !replace ? t.primary : t.divider),
        ),
        child: Column(children: [
          Icon(Icons.add_circle_outline,
              color: !replace ? t.primary : t.sub, size: 18),
          const SizedBox(height: 2),
          Text('Añadir',
              style: TextStyle(
                color: !replace ? t.primary : t.sub,
                fontSize: 12, fontWeight: FontWeight.w700)),
          Text('sin duplicar tipos',
              style: TextStyle(color: t.sub, fontSize: 10)),
        ]),
      ),
    )),
    Expanded(child: GestureDetector(
      onTap: () => onChange(true),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: replace
              ? t.danger.withValues(alpha: 0.08) : t.card,
          borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(8)),
          border: Border.all(color: replace ? t.danger : t.divider),
        ),
        child: Column(children: [
          Icon(Icons.swap_horiz,
              color: replace ? t.danger : t.sub, size: 18),
          const SizedBox(height: 2),
          Text('Reemplazar',
              style: TextStyle(
                color: replace ? t.danger : t.sub,
                fontSize: 12, fontWeight: FontWeight.w700)),
          Text('borra apuestas previas',
              style: TextStyle(color: t.sub, fontSize: 10)),
        ]),
      ),
    )),
  ]);
}

// ── Tile de opción genérico ──────────────────────────────────────────────────
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.t,
    required this.onTap,
  });
  final IconData   icon;
  final Color      iconColor;
  final String     title;
  final String     subtitle;
  final GolfTheme  t;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Container(
      width: 42, height: 42,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: iconColor, size: 20),
    ),
    title: Text(title,
        style: TextStyle(color: t.text,
            fontWeight: FontWeight.w700, fontSize: 14)),
    subtitle: Text(subtitle,
        style: TextStyle(color: t.sub, fontSize: 11)),
    trailing: Icon(Icons.arrow_forward_ios, color: t.sub, size: 14),
    onTap: onTap,
  );
}

// ── Una fila de tipo de apuesta en "Aplicar a varios" ────────────────────────
//
// Los tipos que NO se pactan por duelo salen atenuados con su motivo, y el
// motivo dice DÓNDE sí funcionan. Es la diferencia entre "no puedes" —que deja
// al usuario sin salida— y "no aquí, allí sí".
//
// Y es más de la mitad del catálogo: de los diez tipos creables solo cuatro se
// pactan cruce a cruce. Un grupo de apuesta es por dentro una lista de duelos
// —BettingGroup.pairRules, y toBetModuleInstancesForToday crea cada módulo con
// exactamente dos participantes— así que Snake, Rabbit, Wolf, Oyes y Unidades no
// caben ahí de ninguna forma. Enseñarlos apagados y explicados es la única
// respuesta honesta: esconderlos haría buscar en un sitio donde tampoco están.
class _FilaTipo extends StatelessWidget {
  const _FilaTipo({
    required this.tipo,
    required this.seleccionada,
    required this.t,
    required this.onTap,
  });
  final BetModuleType tipo;
  final bool seleccionada;
  final GolfTheme t;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final motivo = tipo.motivoSinDuelo;
    final bloqueada = motivo != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: bloqueada ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bloqueada
                ? t.surface
                : seleccionada
                    ? t.primary.withValues(alpha: 0.1)
                    : t.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: seleccionada && !bloqueada ? t.primary : t.divider,
                width: seleccionada && !bloqueada ? 1.5 : 1),
          ),
          child: Row(children: [
            Icon(tipo.icono, size: GolfIcons.juntoAValor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tipo.label,
                      style: TextStyle(
                          color: bloqueada ? t.sub : t.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                  Text(motivo ?? tipo.description,
                      style: TextStyle(
                          color: t.sub,
                          fontSize: 10.5,
                          height: 1.3,
                          fontStyle:
                              bloqueada ? FontStyle.italic : FontStyle.normal)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (bloqueada)
              Icon(Icons.block, color: t.sub, size: 16)
            else if (seleccionada)
              Icon(Icons.check_circle, color: t.primary, size: 18)
            else
              Icon(Icons.add_circle_outline, color: t.sub, size: 18),
          ]),
        ),
      ),
    );
  }
}
