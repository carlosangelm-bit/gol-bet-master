// BET MODULE EDIT SHEET — Widget reutilizable para editar la configuración
// de un BetModuleInstance. Se usa tanto desde home_screen (ronda activa)
// como desde setup_screen (revisión antes de lanzar).
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../models/models.dart';

// Tipos de módulo que admiten configuración de lados (equipo vs equipo).
const _teamSupportedTypes = {
  BetModuleType.matchAutoPress,
  BetModuleType.nassau,
  BetModuleType.skins,
};

class BetModuleEditSheet extends StatefulWidget {
  final BetGroup group;
  final BetModuleInstance mod;
  final GolfTheme t;
  final CourseInfo? courseInfo;
  final void Function(BetModuleInstance) onSave;
  /// Jugadores disponibles para asignar a lados. Si es null o vacío,
  /// se usa group.playerIds como IDs pero sin nombres (se muestra el ID).
  final List<Player>? players;

  const BetModuleEditSheet({
    super.key,
    required this.group,
    required this.mod,
    required this.t,
    required this.onSave,
    this.courseInfo,
    this.players,
  });
  @override
  State<BetModuleEditSheet> createState() => _BetModuleEditSheetState();
}

class _BetModuleEditSheetState extends State<BetModuleEditSheet> {
  late BetModuleInstance _current;

  late final TextEditingController _skinCtrl;
  late final TextEditingController _nassauF, _nassauB, _nassauT;
  late final TextEditingController _matchM, _matchP;
  late final TextEditingController _npF, _npB, _npT, _npPF, _npPB;
  late final TextEditingController _medalCtrl;
  late final TextEditingController _puttsCtrl;
  late final TextEditingController _oyesCtrl, _zapatoCtrl;
  late final Map<UnitEventType, TextEditingController> _unitCtrls;

  // ── Estado de configuración de lados ──────────────────────────────────────
  // _sidesEnabled: si el usuario activó el modo equipo en este módulo.
  // _sideAIds / _sideBIds: jugadores asignados a cada lado (mutable en UI).
  late bool _sidesEnabled;
  late List<String> _sideAIds;
  late List<String> _sideBIds;

  // Nombre editable de cada lado
  final _nameACtrl = TextEditingController();
  final _nameBCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _current = widget.mod;
    final m = _current;
    _skinCtrl   = TextEditingController(text: m.skins.valuePerSkin.toStringAsFixed(0));
    _nassauF    = TextEditingController(text: m.nassau.frontValue.toStringAsFixed(0));
    _nassauB    = TextEditingController(text: m.nassau.backValue.toStringAsFixed(0));
    _nassauT    = TextEditingController(text: m.nassau.totalValue.toStringAsFixed(0));
    _matchM     = TextEditingController(text: m.matchAutoPress.matchValue.toStringAsFixed(0));
    _matchP     = TextEditingController(text: m.matchAutoPress.pressValue.toStringAsFixed(0));
    _npF        = TextEditingController(text: m.nassauPress.frontValue.toStringAsFixed(0));
    _npB        = TextEditingController(text: m.nassauPress.backValue.toStringAsFixed(0));
    _npT        = TextEditingController(text: m.nassauPress.totalValue.toStringAsFixed(0));
    _npPF       = TextEditingController(text: m.nassauPress.frontPressValue.toStringAsFixed(0));
    _npPB       = TextEditingController(text: m.nassauPress.backPressValue.toStringAsFixed(0));
    _medalCtrl  = TextEditingController(text: m.medal.value.toStringAsFixed(0));
    _puttsCtrl  = TextEditingController(text: m.putts.value.toStringAsFixed(0));
    _oyesCtrl   = TextEditingController(text: m.oyeses.value.toStringAsFixed(0));
    _zapatoCtrl = TextEditingController(
        text: m.oyeses.zapatoValue > 0 ? m.oyeses.zapatoValue.toStringAsFixed(0) : '');
    _unitCtrls  = {
      for (final e in UnitEventType.values)
        e: TextEditingController(text: m.units.valueFor(e).toStringAsFixed(0)),
    };

    // ── Inicializar estado de lados ─────────────────────────────────────────
    if (m.hasTeamSides) {
      _sidesEnabled = true;
      _sideAIds = List<String>.from(m.sideA.playerIds);
      _sideBIds = List<String>.from(m.sideB.playerIds);
      _nameACtrl.text = m.sideA.name;
      _nameBCtrl.text = m.sideB.name;
    } else {
      _sidesEnabled = false;
      _sideAIds = [];
      _sideBIds = [];
      _nameACtrl.text = 'Lado A';
      _nameBCtrl.text = 'Lado B';
    }
  }

  @override
  void dispose() {
    _skinCtrl.dispose();
    _nassauF.dispose(); _nassauB.dispose(); _nassauT.dispose();
    _matchM.dispose(); _matchP.dispose();
    _npF.dispose(); _npB.dispose(); _npT.dispose(); _npPF.dispose(); _npPB.dispose();
    _medalCtrl.dispose();
    _puttsCtrl.dispose();
    _oyesCtrl.dispose(); _zapatoCtrl.dispose();
    for (final c in _unitCtrls.values) c.dispose();
    _nameACtrl.dispose();
    _nameBCtrl.dispose();
    super.dispose();
  }

  void _update(BetModuleInstance updated) => setState(() => _current = updated);

  // ── Construir BetSide actualizados desde el estado de UI ──────────────────
  List<BetSide>? _buildSides() {
    if (!_sidesEnabled) return null;
    final nameA = _nameACtrl.text.trim().isEmpty ? 'Lado A' : _nameACtrl.text.trim();
    final nameB = _nameBCtrl.text.trim().isEmpty ? 'Lado B' : _nameBCtrl.text.trim();
    return [
      BetSide(id: 'sideA_${_current.id}', name: nameA, playerIds: List.from(_sideAIds)),
      BetSide(id: 'sideB_${_current.id}', name: nameB, playerIds: List.from(_sideBIds)),
    ];
  }

  // ── Error de validación de lados en tiempo real ───────────────────────────
  String? get _sidesError {
    if (!_sidesEnabled) return null;
    final sides = _buildSides();
    if (sides == null) return null;
    return BetSide.validateDuel(sides);
  }

  // ── Guardar: inyecta sides y actualiza participantIds ─────────────────────
  void _save() {
    final sides = _buildSides();
    // Participantes = unión de todos los jugadores de ambos lados (retrocompat)
    final newParticipants = sides != null
        ? {for (final s in sides) ...s.playerIds}.toList()
        : _current.participantIds;

    final saved = _current.copyWith(
      participantIds: newParticipants,
      sides: sides,
      clearSides: !_sidesEnabled,
    );
    widget.onSave(saved);
    Navigator.pop(context);
  }

  // ── Jugadores disponibles del grupo ───────────────────────────────────────
  List<Player> get _availablePlayers {
    final ps = widget.players;
    if (ps != null && ps.isNotEmpty) {
      // Solo mostrar jugadores que pertenecen al grupo
      final groupIds = widget.group.playerIds.toSet();
      return ps.where((p) => groupIds.contains(p.id)).toList();
    }
    // Fallback: construir Player mínimo desde los IDs del grupo
    return widget.group.playerIds
        .map((id) => Player(id: id, name: id))
        .toList();
  }

  String _playerName(String id) {
    final p = _availablePlayers.firstWhere(
      (p) => p.id == id,
      orElse: () => Player(id: id, name: id),
    );
    return p.name;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final error = _sidesError;
    final canSave = error == null;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, ctrl) => Column(children: [
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          width: 40, height: 4,
          decoration: BoxDecoration(color: t.divider, borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Text(_current.type.icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Editar ${_current.type.label}', style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 17)),
              Text(widget.group.name, style: TextStyle(color: t.sub, fontSize: 12)),
            ])),
          ]),
        ),
        Divider(height: 20, color: t.divider),
        Expanded(
          child: SingleChildScrollView(
            controller: ctrl,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ..._buildFields(t),
                // ── Sección de equipos (solo para tipos compatibles) ────────
                if (_teamSupportedTypes.contains(_current.type)) ...[
                  const SizedBox(height: 24),
                  _buildSidesSection(t),
                ],
              ],
            ),
          ),
        ),
        // ── Banner de error de validación ───────────────────────────────────
        if (_sidesEnabled && error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: t.loss.withValues(alpha: 0.12),
            child: Row(children: [
              Icon(Icons.warning_amber_rounded, color: t.loss, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(error, style: TextStyle(color: t.loss, fontSize: 12, fontWeight: FontWeight.w600))),
            ]),
          ),
        // ── Botón Guardar ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: canSave ? _save : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: canSave ? t.primary : t.divider,
                foregroundColor: t.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                canSave ? 'Guardar cambios' : 'Corrige los equipos para guardar',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  List<Widget> _buildFields(GolfTheme t) {
    switch (_current.type) {
      case BetModuleType.skins:         return _skinsFields(t);
      case BetModuleType.nassau:        return _nassauFields(t);
      case BetModuleType.matchAutoPress: return _matchFields(t);
      case BetModuleType.nassauPress:   return _nassauPressFields(t);
      case BetModuleType.medal:         return _medalFields(t);
      case BetModuleType.putts:         return _puttsFields(t);
      case BetModuleType.oyeses:        return _oyesesFields(t);
      case BetModuleType.units:         return _unitsFields(t);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SECCIÓN DE EQUIPOS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildSidesSection(GolfTheme t) {
    final players = _availablePlayers;
    // Jugadores sin asignar
    final assignedIds = {..._sideAIds, ..._sideBIds};
    final unassigned = players.where((p) => !assignedIds.contains(p.id)).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Header con toggle ─────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _sidesEnabled ? t.primary.withValues(alpha: 0.5) : t.divider),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _sidesEnabled ? t.primary.withValues(alpha: 0.15) : t.divider.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.group_outlined,
              color: _sidesEnabled ? t.primary : t.sub, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Juego por equipos', style: TextStyle(
              color: t.text, fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 2),
            Text(
              _sidesEnabled
                  ? 'Lado A vs Lado B — best ball'
                  : 'Activar para definir Lado A y Lado B',
              style: TextStyle(color: t.sub, fontSize: 11),
            ),
          ])),
          Switch(
            value: _sidesEnabled,
            onChanged: (v) => setState(() {
              _sidesEnabled = v;
              if (v && _sideAIds.isEmpty && _sideBIds.isEmpty) {
                // Auto-asignar: primera mitad a A, segunda a B (helper)
                _autoAssignSides(players);
              }
            }),
            activeThumbColor: t.primary,
            activeTrackColor: t.primary.withValues(alpha: 0.35),
            inactiveTrackColor: t.divider,
          ),
        ]),
      ),

      if (_sidesEnabled) ...[
        const SizedBox(height: 16),

        // ── Instrucción ──────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: t.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Icon(Icons.touch_app_outlined, color: t.primary, size: 14),
            const SizedBox(width: 6),
            Expanded(child: Text(
              'Toca un jugador para moverlo entre Lado A, Lado B o Sin asignar.',
              style: TextStyle(color: t.primary, fontSize: 11, fontWeight: FontWeight.w500),
            )),
          ]),
        ),

        const SizedBox(height: 14),

        // ── Lado A y Lado B en fila ───────────────────────────────────────
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _sidePanel(
            t,
            label: 'LADO A',
            nameCtrl: _nameACtrl,
            playerIds: _sideAIds,
            color: t.primary,
            onAdd: (pid) => setState(() { _sideBIds.remove(pid); _sideAIds.add(pid); }),
            onRemove: (pid) => setState(() => _sideAIds.remove(pid)),
          )),
          const SizedBox(width: 10),
          Expanded(child: _sidePanel(
            t,
            label: 'LADO B',
            nameCtrl: _nameBCtrl,
            playerIds: _sideBIds,
            color: t.accent,
            onAdd: (pid) => setState(() { _sideAIds.remove(pid); _sideBIds.add(pid); }),
            onRemove: (pid) => setState(() => _sideBIds.remove(pid)),
          )),
        ]),

        // ── Sin asignar ──────────────────────────────────────────────────
        if (unassigned.isNotEmpty) ...[
          const SizedBox(height: 14),
          _label('SIN ASIGNAR', t),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: unassigned.map((p) =>
              _playerChip(t, p, color: t.sub, onTap: () {
                // Tapping unassigned → va a A si A tiene menos, sino a B
                setState(() {
                  if (_sideAIds.length <= _sideBIds.length) {
                    _sideAIds.add(p.id);
                  } else {
                    _sideBIds.add(p.id);
                  }
                });
              })
            ).toList(),
          ),
        ],

        // ── Botón para limpiar todos ──────────────────────────────────────
        const SizedBox(height: 12),
        Center(child: TextButton.icon(
          onPressed: () => setState(() { _sideAIds.clear(); _sideBIds.clear(); }),
          icon: Icon(Icons.refresh, size: 14, color: t.sub),
          label: Text('Reiniciar asignación', style: TextStyle(color: t.sub, fontSize: 12)),
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
        )),
      ],
    ]);
  }

  // ── Panel de un lado (A o B) ──────────────────────────────────────────────
  Widget _sidePanel(
    GolfTheme t, {
    required String label,
    required TextEditingController nameCtrl,
    required List<String> playerIds,
    required Color color,
    required void Function(String) onAdd,
    required void Function(String) onRemove,
  }) {
    // Jugadores no asignados a este lado (para el menú de agregar)
    final assignedIds = {..._sideAIds, ..._sideBIds};
    final available = _availablePlayers.where((p) => !assignedIds.contains(p.id)).toList();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Etiqueta del lado
        Row(children: [
          Container(width: 10, height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 0.8)),
        ]),
        const SizedBox(height: 6),
        // Nombre editable
        TextField(
          controller: nameCtrl,
          onChanged: (_) => setState(() {}),
          style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            fillColor: color.withValues(alpha: 0.08),
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: color.withValues(alpha: 0.3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: color.withValues(alpha: 0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: color, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Chips de jugadores asignados
        if (playerIds.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('Sin jugadores', style: TextStyle(color: t.sub, fontSize: 11)),
          )
        else
          Wrap(
            spacing: 6, runSpacing: 6,
            children: playerIds.map((pid) =>
              _playerChip(t, Player(id: pid, name: _playerName(pid)), color: color,
                onTap: () => onRemove(pid),
                trailing: Icon(Icons.close, size: 12, color: color),
              )
            ).toList(),
          ),
        // Botón agregar (si hay jugadores sin asignar)
        if (available.isNotEmpty) ...[
          const SizedBox(height: 6),
          _addPlayerButton(t, available, color, onAdd),
        ],
      ]),
    );
  }

  // ── Chip de jugador ───────────────────────────────────────────────────────
  Widget _playerChip(GolfTheme t, Player p, {
    required Color color,
    required VoidCallback onTap,
    Widget? trailing,
  }) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(p.name, style: TextStyle(
            color: color, fontWeight: FontWeight.w700, fontSize: 12,
          )),
          if (trailing != null) ...[const SizedBox(width: 4), trailing],
        ]),
      ),
    );

  // ── Botón "+" para agregar jugador sin asignar ─────────────────────────
  Widget _addPlayerButton(GolfTheme t, List<Player> available, Color color, void Function(String) onAdd) {
    if (available.length == 1) {
      // Un solo disponible: acción directa
      return GestureDetector(
        onTap: () => onAdd(available.first.id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.4), style: BorderStyle.solid),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add, size: 14, color: color),
            const SizedBox(width: 4),
            Text(available.first.name, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
    }
    // Varios disponibles: popup menu
    return PopupMenuButton<String>(
      onSelected: onAdd,
      color: t.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (_) => available.map((p) => PopupMenuItem(
        value: p.id,
        child: Text(p.name, style: TextStyle(color: t.text, fontSize: 13)),
      )).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.4), style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.add, size: 14, color: color),
          const SizedBox(width: 4),
          Text('Agregar jugador', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // ── Auto-asignar primera vez: mitad a A, mitad a B ──────────────────────
  void _autoAssignSides(List<Player> players) {
    _sideAIds.clear();
    _sideBIds.clear();
    for (int i = 0; i < players.length; i++) {
      if (i.isEven) {
        _sideAIds.add(players[i].id);
      } else {
        _sideBIds.add(players[i].id);
      }
    }
  }

  // ── SKINS ───────────────────────────────────────────────────────────────────
  List<Widget> _skinsFields(GolfTheme t) {
    final s = _current.skins;
    return [
      _label('VALOR POR SKIN', t),
      _amountField('Monto', _skinCtrl, t, onChanged: (v) {
        _update(_current.copyWith(skinsConfig: s.copyWith(valuePerSkin: v)));
      }),
      const SizedBox(height: 16),
      _label('JUEGO', t),
      _segmented(['Gross', 'Net'], s.mode == GrossNetMode.net ? 1 : 0, t, (i) {
        _update(_current.copyWith(skinsConfig: s.copyWith(mode: i == 1 ? GrossNetMode.net : GrossNetMode.gross)));
      }),
      const SizedBox(height: 16),
      _toggle('Carry-over', s.carryOver ? 'Empates acumulan al siguiente hoyo 🔥' : 'Sin acumulación', s.carryOver, t, (v) {
        _update(_current.copyWith(skinsConfig: s.copyWith(carryOver: v)));
      }),
    ];
  }

  // ── NASSAU ──────────────────────────────────────────────────────────────────
  List<Widget> _nassauFields(GolfTheme t) {
    final n = _current.nassau;
    void saveNassau() {
      final fv = double.tryParse(_nassauF.text) ?? n.frontValue;
      final bv = double.tryParse(_nassauB.text) ?? n.backValue;
      final tv = double.tryParse(_nassauT.text) ?? n.totalValue;
      _update(_current.copyWith(nassauConfig: n.copyWith(frontValue: fv, backValue: bv, totalValue: tv)));
    }
    return [
      _label('VALORES', t),
      _amountField('Front 9', _nassauF, t, onChanged: (_) => saveNassau()),
      const SizedBox(height: 8),
      _amountField('Back 9', _nassauB, t, onChanged: (_) => saveNassau()),
      const SizedBox(height: 8),
      _amountField('Total 18', _nassauT, t, onChanged: (_) => saveNassau()),
      const SizedBox(height: 16),
      _label('JUEGO', t),
      _segmented(['Gross', 'Net'], n.mode == GrossNetMode.net ? 1 : 0, t, (i) {
        _update(_current.copyWith(nassauConfig: n.copyWith(mode: i == 1 ? GrossNetMode.net : GrossNetMode.gross)));
      }),
      const SizedBox(height: 16),
      _toggle('Activar Press automático', n.pressEnabled ? 'Trigger: ${n.autoPressTrigger} down' : 'Sin press', n.pressEnabled, t, (v) {
        _update(_current.copyWith(nassauConfig: n.copyWith(pressEnabled: v)));
      }),
      if (n.pressEnabled) ...[
        const SizedBox(height: 12),
        _label('TRIGGER', t),
        _segmented(['1 down', '2 down', '3 down'], n.autoPressTrigger - 1, t, (i) {
          _update(_current.copyWith(nassauConfig: n.copyWith(autoPressTrigger: i + 1)));
        }),
      ],
    ];
  }

  // ── MATCH + PRESS ───────────────────────────────────────────────────────────
  List<Widget> _matchFields(GolfTheme t) {
    final m = _current.matchAutoPress;
    return [
      _label('VALORES', t),
      _amountField('Valor del match', _matchM, t, onChanged: (v) {
        _update(_current.copyWith(matchAutoPressConfig: m.copyWith(matchValue: v)));
      }),
      const SizedBox(height: 8),
      _amountField('Valor por press/dígito', _matchP, t, onChanged: (v) {
        _update(_current.copyWith(matchAutoPressConfig: m.copyWith(pressValue: v)));
      }),
      const SizedBox(height: 16),
      _label('TRIGGER (hoyos de diferencia para nueva presión)', t),
      _segmented(['1 up', '2 up', '3 up'], m.pressTriggerValue - 1, t, (i) {
        _update(_current.copyWith(matchAutoPressConfig: m.copyWith(pressTriggerValue: i + 1)));
      }),
      const SizedBox(height: 16),
      _label('JUEGO', t),
      _segmented(['Gross', 'Net'], m.mode == GrossNetMode.net ? 1 : 0, t, (i) {
        _update(_current.copyWith(matchAutoPressConfig: m.copyWith(mode: i == 1 ? GrossNetMode.net : GrossNetMode.gross)));
      }),
    ];
  }

  // ── NASSAU + PRESS ──────────────────────────────────────────────────────────
  List<Widget> _nassauPressFields(GolfTheme t) {
    final n = _current.nassauPress;

    void saveNP({
      double? fv, double? bv, double? tv,
      double? pfv, double? pbv,
    }) {
      _update(_current.copyWith(nassauPressConfig: n.copyWith(
        frontValue:       fv  ?? double.tryParse(_npF.text)  ?? n.frontValue,
        backValue:        bv  ?? double.tryParse(_npB.text)  ?? n.backValue,
        totalValue:       tv  ?? double.tryParse(_npT.text)  ?? n.totalValue,
        frontPressValue:  pfv ?? double.tryParse(_npPF.text) ?? n.frontPressValue,
        backPressValue:   pbv ?? double.tryParse(_npPB.text) ?? n.backPressValue,
      )));
    }

    return [
      // ── Valores Nassau ─────────────────────────────────────────────────────
      _label('VALORES NASSAU', t),
      _amountField('Front 9', _npF, t, onChanged: (_) => saveNP()),
      const SizedBox(height: 8),
      _amountField('Back 9',  _npB, t, onChanged: (_) => saveNP()),
      const SizedBox(height: 8),
      _amountField('Total 18', _npT, t, onChanged: (_) => saveNP()),
      const SizedBox(height: 16),

      // ── Valores de presión por segmento ────────────────────────────────────
      _label('VALOR PRESS', t),
      _amountField('Press Front 9', _npPF, t, onChanged: (_) => saveNP()),
      const SizedBox(height: 8),
      _amountField('Press Back 9',  _npPB, t, onChanged: (_) => saveNP()),
      const SizedBox(height: 16),

      // ── Trigger ────────────────────────────────────────────────────────────
      _label('TRIGGER (down para nueva presión)', t),
      _segmented(['1 down', '2 down', '3 down'], n.pressTriggerValue - 1, t, (i) {
        _update(_current.copyWith(nassauPressConfig: n.copyWith(pressTriggerValue: i + 1)));
      }),
      const SizedBox(height: 16),

      // ── Presiones múltiples ────────────────────────────────────────────────
      _toggle('Presiones múltiples por segmento',
          n.allowMultiplePresses ? 'Se puede abrir más de una presión' : 'Solo 1 presión por segmento',
          n.allowMultiplePresses, t, (v) {
        _update(_current.copyWith(nassauPressConfig: n.copyWith(allowMultiplePresses: v)));
      }),
      const SizedBox(height: 16),

      // ── Carry ──────────────────────────────────────────────────────────────
      _toggle('Carry en Back 9',
          n.carryEnabled
              ? 'Si F9 empata, el B9 vale x${n.carryFactor.toStringAsFixed(0)}'
              : 'Sin carry',
          n.carryEnabled, t, (v) {
        _update(_current.copyWith(nassauPressConfig: n.copyWith(carryEnabled: v)));
      }),
      const SizedBox(height: 16),

      // ── Modo Gross/Net ─────────────────────────────────────────────────────
      _label('JUEGO', t),
      _segmented(['Gross', 'Net'], n.mode == GrossNetMode.net ? 1 : 0, t, (i) {
        _update(_current.copyWith(nassauPressConfig: n.copyWith(
            mode: i == 1 ? GrossNetMode.net : GrossNetMode.gross)));
      }),
    ];
  }

  // ── MEDAL ───────────────────────────────────────────────────────────────────
  List<Widget> _medalFields(GolfTheme t) {
    final m = _current.medal;
    return [
      _label('VALOR', t),
      _amountField('Monto', _medalCtrl, t, onChanged: (v) {
        _update(_current.copyWith(medalConfig: m.copyWith(value: v)));
      }),
      const SizedBox(height: 16),
      _label('HOYOS', t),
      _segmented(['9 hoyos', '18 hoyos'], m.holes == 18 ? 1 : 0, t, (i) {
        _update(_current.copyWith(medalConfig: m.copyWith(holes: i == 1 ? 18 : 9)));
      }),
      const SizedBox(height: 16),
      _label('JUEGO', t),
      _segmented(['Gross', 'Net'], m.mode == GrossNetMode.net ? 1 : 0, t, (i) {
        _update(_current.copyWith(medalConfig: m.copyWith(mode: i == 1 ? GrossNetMode.net : GrossNetMode.gross)));
      }),
    ];
  }

  // ── PUTTS ───────────────────────────────────────────────────────────────────
  List<Widget> _puttsFields(GolfTheme t) {
    final p = _current.putts;
    return [
      _label('VALOR POR SEGMENTO', t),
      _amountField('Monto', _puttsCtrl, t, onChanged: (v) {
        _update(_current.copyWith(puttsConfig: p.copyWith(value: v)));
      }),
      const SizedBox(height: 16),
      _label('MODO', t),
      _segmented(['Total 18H', 'F9 + B9'], p.puttsMode == PuttsMode.total ? 0 : 1, t, (i) {
        _update(_current.copyWith(puttsConfig: p.copyWith(puttsMode: i == 0 ? PuttsMode.total : PuttsMode.perHole)));
      }),
      const SizedBox(height: 8),
      Text(
        p.puttsMode == PuttsMode.total
            ? '1 apuesta: el que menos putts en 18 hoyos gana \$${p.value.toStringAsFixed(0)}'
            : '2 apuestas: F9 (\$${p.value.toStringAsFixed(0)}) + B9 (\$${p.value.toStringAsFixed(0)})',
        style: TextStyle(color: t.sub, fontSize: 11),
      ),
      const SizedBox(height: 16),
      _toggle('Penalti 3-putt', p.threePuttPenalty ? 'Se cobra penalti por cada 3-putt' : 'Sin penalti', p.threePuttPenalty, t, (v) {
        _update(_current.copyWith(puttsConfig: p.copyWith(threePuttPenalty: v)));
      }),
    ];
  }

  // ── OYESES ──────────────────────────────────────────────────────────────────
  List<Widget> _oyesesFields(GolfTheme t) {
    final o = _current.oyeses;
    final realPar3Holes = (widget.courseInfo?.holes ?? CourseInfo.standard.holes)
        .where((h) => h.isPar3)
        .map((h) => h.hole)
        .toList()
      ..sort();
    final par3count = o.eligibleHoles.isEmpty ? realPar3Holes.length : o.eligibleHoles.length;

    return [
      _label('VALOR POR OYÉS', t),
      _amountField('Monto', _oyesCtrl, t, onChanged: (v) {
        _update(_current.copyWith(oyesesConfig: o.copyWith(value: v)));
      }),
      const SizedBox(height: 20),
      _label('👟 ZAPATO', t),
      Text('El jugador que gana TODOS los oyeses cobra el zapato.', style: TextStyle(color: t.sub, fontSize: 11)),
      const SizedBox(height: 10),
      _toggle('Activar zapato', o.zapatoEnabled ? 'Ganador de todos los oyeses cobra extra' : 'Sin regla de zapato', o.zapatoEnabled, t, (v) {
        _update(_current.copyWith(oyesesConfig: o.copyWith(zapatoEnabled: v)));
      }),
      if (o.zapatoEnabled) ...[
        const SizedBox(height: 12),
        _label('VALOR DEL ZAPATO', t),
        Text(
          o.zapatoValue == 0
              ? 'Automático: $par3count oyeses × \$${o.value.toStringAsFixed(0)} = \$${(par3count * o.value).toStringAsFixed(0)}'
              : 'Valor fijo configurado',
          style: TextStyle(color: t.sub, fontSize: 11),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _zapatoCtrl,
          onChanged: (txt) {
            final v = double.tryParse(txt) ?? 0;
            _update(_current.copyWith(oyesesConfig: _current.oyeses.copyWith(zapatoValue: v)));
          },
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
          textAlign: TextAlign.right,
          style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14),
          decoration: InputDecoration(
            labelText: 'Monto fijo (vacío = automático)',
            labelStyle: TextStyle(color: t.sub, fontSize: 12),
            prefixText: '\$ ',
            prefixStyle: TextStyle(color: t.sub, fontSize: 13),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            fillColor: t.surface, filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.primary, width: 1.5)),
          ),
        ),
        const SizedBox(height: 12),
        _label('APLICA EN', t),
        _segmented(['Solo 18 hoyos', 'También 9 hoyos'], o.zapatoRequires18 ? 0 : 1, t, (i) {
          _update(_current.copyWith(oyesesConfig: _current.oyeses.copyWith(zapatoRequires18: i == 0)));
        }),
        const SizedBox(height: 6),
        Text(
          o.zapatoRequires18
              ? 'Solo aplica si se juegan todos los par-3 del campo.'
              : 'Aplica con 2 o más oyeses registrados (válido en 9H).',
          style: TextStyle(color: t.sub, fontSize: 11),
        ),
      ],
    ];
  }

  // ── UNITS ───────────────────────────────────────────────────────────────────
  List<Widget> _unitsFields(GolfTheme t) {
    final icons = {
      UnitEventType.birdie:      '🐦',
      UnitEventType.eagle:       '🦅',
      UnitEventType.sandyPar:    '🏖️',
      UnitEventType.parUnico:    '⭐',
      UnitEventType.birdieUnico: '💫',
      UnitEventType.holeOut:     '🕳️',
    };

    return [
      _label('VALOR POR EVENTO', t),
      const SizedBox(height: 4),
      Text('Cada jugador que logra el evento cobra este monto de cada rival.', style: TextStyle(color: t.sub, fontSize: 11)),
      const SizedBox(height: 12),
      ...UnitEventType.values.map((e) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Text(icons[e]!, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.label, style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 13)),
            Text(e.description, style: TextStyle(color: t.sub, fontSize: 10)),
          ])),
          SizedBox(
            width: 90,
            child: TextField(
              controller: _unitCtrls[e],
              onChanged: (_) {
                final newMap = <UnitEventType, double>{};
                for (final ev in UnitEventType.values) {
                  final v = double.tryParse(_unitCtrls[ev]!.text);
                  if (v != null) newMap[ev] = v;
                }
                _update(_current.copyWith(unitsConfig: UnitsConfig(eventValues: newMap)));
              },
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              textAlign: TextAlign.right,
              style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14),
              decoration: InputDecoration(
                prefixText: '\$ ',
                prefixStyle: TextStyle(color: t.sub, fontSize: 11),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                fillColor: t.surface,
                filled: true,
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

  // ── Helpers UI ──────────────────────────────────────────────────────────────
  Widget _label(String text, GolfTheme t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
  );

  Widget _amountField(String hint, TextEditingController ctrl, GolfTheme t,
      {void Function(double)? onChanged}) =>
    TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: false),
      textAlign: TextAlign.right,
      style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 16),
      onChanged: onChanged == null ? null : (txt) {
        final v = double.tryParse(txt);
        if (v != null) onChanged(v);
      },
      decoration: InputDecoration(
        labelText: hint,
        labelStyle: TextStyle(color: t.sub, fontSize: 13),
        prefixText: '\$ ',
        prefixStyle: TextStyle(color: t.sub, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        fillColor: t.surface,
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.primary, width: 1.5)),
      ),
    );

  Widget _segmented(List<String> labels, int selected, GolfTheme t, void Function(int) onTap) => Row(
    children: labels.asMap().entries.map((e) {
      final sel = e.key == selected;
      return Expanded(child: GestureDetector(
        onTap: () => setState(() => onTap(e.key)),
        child: Container(
          margin: EdgeInsets.only(right: e.key < labels.length - 1 ? 6 : 0),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: sel ? t.primary : t.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sel ? t.primary : t.divider),
          ),
          alignment: Alignment.center,
          child: Text(e.value, style: TextStyle(
            color: sel ? t.onPrimary : t.text,
            fontWeight: FontWeight.w700, fontSize: 13,
          )),
        ),
      ));
    }).toList(),
  );

  Widget _toggle(String title, String subtitle, bool value, GolfTheme t, void Function(bool) onChanged) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: t.divider)),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 2),
        Text(subtitle, style: TextStyle(color: t.sub, fontSize: 11)),
      ])),
      Switch(
        value: value,
        onChanged: (v) { setState(() => onChanged(v)); },
        activeThumbColor: t.accent,
        activeTrackColor: t.accent.withValues(alpha: 0.4),
        inactiveTrackColor: t.divider,
      ),
    ]),
  );
}
