// ─────────────────────────────────────────────────────────────────────────────
// TEMPLATES SCREEN — Plantillas de apuestas favoritas
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../models/models.dart';
import '../../providers/round_provider.dart';
import '../../providers/betting_group_provider.dart';
import '../setup/setup_screen.dart';
import '../setup/quick_start_screen.dart';
import '../setup/setup_flow.dart';
import '../../services/firestore_service.dart';
import '../../widgets/common_widgets.dart';

class TemplatesScreen extends StatelessWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.watch<RoundProvider>().theme;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        title: Text('Mis Plantillas', style: TextStyle(color: t.text, fontWeight: FontWeight.w800)),
        iconTheme: IconThemeData(color: t.text),
      ),
      // ── Dos clases de punto de partida, COUBICADAS ─────────────────────
      //
      // RoundTemplate y BettingGroup son objetos distintos en el modelo, pero el
      // usuario los percibe igual: "lo de siempre". La distinción es de
      // implementación, no de intención.
      //
      // Se coubican antes de unificar: si al usarlas resulta que la etiqueta no
      // le dice nada a nadie, esa es la señal para fundirlas en un solo concepto
      // —y entonces con motivo, no por intuición.
      body: StreamBuilder<List<RoundTemplate>>(
        stream: FirestoreService.templatesStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: t.primary));
          }
          final templates = snap.data ?? [];
          final grupos = context.watch<BettingGroupProvider>().groups;

          if (templates.isEmpty && grupos.isEmpty) {
            return _EmptyTemplates(t: t);
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (grupos.isNotEmpty) ...[
                _Seccion(
                  titulo: 'GRUPOS DE APUESTA',
                  // Dice qué precarga y qué no, para que nadie espere que el
                  // grupo elija también el campo.
                  detalle: 'Arrancan con los jugadores y las apuestas puestas. '
                      'El campo y la ventaja se eligen al empezar.',
                  t: t,
                ),
                for (final bg in grupos) _GrupoCard(grupo: bg, t: t),
                const SizedBox(height: 20),
              ],
              if (templates.isNotEmpty) ...[
                _Seccion(
                  titulo: 'PLANTILLAS DE RONDA',
                  detalle: 'Guardan la ronda completa, campo incluido.',
                  t: t,
                ),
                for (final tpl in templates)
                  _TemplateCard(template: tpl, t: t),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ── Pantalla vacía ────────────────────────────────────────────────────────────
class _EmptyTemplates extends StatelessWidget {
  final GolfTheme t;
  const _EmptyTemplates({required this.t});

  @override
  Widget build(BuildContext context) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text('📋', style: const TextStyle(fontSize: 60)),
      const SizedBox(height: 16),
      Text('Sin plantillas aún', style: TextStyle(color: t.text, fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Text(
          'Guarda tus configuraciones de apuestas favoritas para replicarlas con un clic.',
          style: TextStyle(color: t.sub, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ),
      const SizedBox(height: 24),
      Text('Ve a Inicio → ⋮ → "Guardar como plantilla"', style: TextStyle(color: t.primary, fontSize: 12, fontWeight: FontWeight.w600)),
    ]));
  }
}

// ── Tarjeta de plantilla ──────────────────────────────────────────────────────
class _TemplateCard extends StatelessWidget {
  final RoundTemplate template;
  final GolfTheme t;
  const _TemplateCard({required this.template, required this.t});

  @override
  Widget build(BuildContext context) {
    final betTypes = _extractBetTypes(template.betGroupsJson);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(template.emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(template.name, style: TextStyle(color: t.text, fontSize: 15, fontWeight: FontWeight.w700)),
            if (template.description.isNotEmpty)
              Text(template.description, style: TextStyle(color: t.sub, fontSize: 12)),
          ])),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: t.sub, size: 20),
            color: t.card,
            onSelected: (val) => _onAction(context, val),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'edit',   child: Row(children: [Icon(Icons.edit, size: 16, color: t.text), const SizedBox(width: 8), Text('Editar', style: TextStyle(color: t.text))])),
              PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 16, color: t.danger), const SizedBox(width: 8), Text('Eliminar', style: TextStyle(color: t.danger))])),
            ],
          ),
        ]),
        const SizedBox(height: 10),
        // Jugadores
        if (template.playerNames.isNotEmpty) ...[
          Wrap(spacing: 6, runSpacing: 4, children: template.playerNames.map((name) =>
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: t.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
              child: Text(name.split(' ').first, style: TextStyle(color: t.primary, fontSize: 11, fontWeight: FontWeight.w600)),
            )
          ).toList()),
          const SizedBox(height: 8),
        ],
        // Tipos de apuesta
        if (betTypes.isNotEmpty)
          Wrap(spacing: 6, runSpacing: 4, children: betTypes.map((bt) =>
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: t.divider)),
              child: Text('${bt.icon} ${bt.label}', style: TextStyle(color: t.sub, fontSize: 11)),
            )
          ).toList()),
        const SizedBox(height: 12),
        // Botón usar
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: Text('Usar plantilla', style: const TextStyle(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.primary, foregroundColor: Colors.white,
              elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onPressed: () => _useTemplate(context),
          ),
        ),
        if (template.useCount > 0) ...[
          const SizedBox(height: 6),
          Text('Usada ${template.useCount} ${template.useCount == 1 ? 'vez' : 'veces'}',
            style: TextStyle(color: t.sub, fontSize: 11), textAlign: TextAlign.center),
        ],
      ]),
      ),
    );
  }

  List<BetModuleType> _extractBetTypes(List<Map<String, dynamic>> groupsJson) {
    final types = <BetModuleType>{};
    for (final g in groupsJson) {
      final mods = (g['modules'] as List? ?? []);
      for (final m in mods) {
        final typeName = (m as Map)['type'] as String?;
        if (typeName != null) {
          try { types.add(BetModuleType.values.byName(typeName)); } catch (_) {}
        }
      }
    }
    return types.toList();
  }

  void _useTemplate(BuildContext context) {
    Navigator.of(context).pop(template);
  }

  void _onAction(BuildContext context, String action) {
    if (action == 'delete') {
      _confirmDelete(context);
    } else if (action == 'edit') {
      _editTemplate(context);
    }
  }

  void _confirmDelete(BuildContext context) {
    final t = this.t;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: t.card,
      title: Text('Eliminar plantilla', style: TextStyle(color: t.text, fontWeight: FontWeight.w800)),
      content: Text('¿Eliminar "${template.name}"? Esta acción no se puede deshacer.', style: TextStyle(color: t.sub)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancelar', style: TextStyle(color: t.sub))),
        TextButton(
          onPressed: () async {
            Navigator.pop(ctx);
            await FirestoreService.deleteTemplate(template.id);
          },
          child: Text('Eliminar', style: TextStyle(color: t.danger, fontWeight: FontWeight.w700)),
        ),
      ],
    ));
  }

  void _editTemplate(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EditTemplateSheet(template: template, t: t),
    );
  }
}

// ── Sheet edición de plantilla ────────────────────────────────────────────────
class _EditTemplateSheet extends StatefulWidget {
  final RoundTemplate template;
  final GolfTheme t;
  const _EditTemplateSheet({required this.template, required this.t});
  @override State<_EditTemplateSheet> createState() => _EditTemplateSheetState();
}

class _EditTemplateSheetState extends State<_EditTemplateSheet> {
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  String _emoji = '⛳️';
  bool _saving = false;
  static const _emojis = ['⛳️','🏌️','🏆','💰','🎯','🃏','⚡️','🔥','💎','🎖️','🥇','🤝'];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.template.name);
    _descCtrl = TextEditingController(text: widget.template.description);
    _emoji    = widget.template.emoji;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: t.divider, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        Text('Editar plantilla', style: TextStyle(color: t.text, fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        // Emoji selector
        Text('Ícono', style: TextStyle(color: t.sub, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: _emojis.map((e) => GestureDetector(
          onTap: () => setState(() => _emoji = e),
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: _emoji == e ? t.primary.withValues(alpha: 0.12) : t.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _emoji == e ? t.primary : t.divider),
            ),
            child: Center(child: Text(e, style: const TextStyle(fontSize: 20))),
          ),
        )).toList()),
        const SizedBox(height: 16),
        TextField(
          controller: _nameCtrl,
          style: TextStyle(color: t.text),
          decoration: InputDecoration(labelText: 'Nombre', labelStyle: TextStyle(color: t.sub), filled: true, fillColor: t.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.primary, width: 1.5)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descCtrl,
          style: TextStyle(color: t.text),
          decoration: InputDecoration(labelText: 'Descripción (opcional)', labelStyle: TextStyle(color: t.sub), filled: true, fillColor: t.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.primary, width: 1.5)),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(backgroundColor: t.primary, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: _saving ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2) : const Text('Guardar cambios', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final updated = widget.template.copyWith(name: _nameCtrl.text.trim(), emoji: _emoji, description: _descCtrl.text.trim());
    await FirestoreService.updateTemplate(updated);
    if (mounted) Navigator.pop(context);
  }
}

// ── Dialog para guardar plantilla desde la ronda activa ───────────────────────
class SaveTemplateDialog extends StatefulWidget {
  final List<BetGroup> betGroups;
  final List<Player> players;

  /// Campo de la ronda actual, para poder incluirlo. null si no hay.
  final String? courseName;

  final GolfTheme t;
  const SaveTemplateDialog({
    required this.betGroups,
    required this.players,
    required this.t,
    this.courseName,
    super.key,
  });
  @override State<SaveTemplateDialog> createState() => _SaveTemplateDialogState();
}

class _SaveTemplateDialogState extends State<SaveTemplateDialog> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _emoji = '⛳️';
  bool _saving = false;

  /// Incluir el campo. Apagado por defecto.
  ///
  /// Es la UNICA decision que separaba "plantilla de ronda" de "grupo de
  /// apuesta", y ahora es una casilla en vez de dos conceptos. Quien juega
  /// siempre en el mismo campo la marca; quien rota entre campos, no.
  ///
  /// Apagado por defecto porque incluirlo es lo mas restrictivo: una
  /// plantilla con campo sirve para menos rondas que una sin el.
  bool _conCampo = false;
  static const _emojis = ['⛳️','🏌️','🏆','💰','🎯','🃏','⚡️','🔥','💎','🎖️','🥇','🤝'];

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return AlertDialog(
      backgroundColor: t.card,
      title: Text('Guardar plantilla', style: TextStyle(color: t.text, fontWeight: FontWeight.w800)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Guarda esta configuración para usarla en futuras rondas.', style: TextStyle(color: t.sub, fontSize: 13)),
        if (widget.courseName != null) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => setState(() => _conCampo = !_conCampo),
            child: Row(children: [
              Icon(
                  _conCampo
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  color: _conCampo ? t.primary : t.divider,
                  size: 20),
              const SizedBox(width: 8),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Incluir el campo',
                        style: TextStyle(color: t.text, fontSize: 13.5)),
                    Text(
                        _conCampo
                            ? widget.courseName!
                            : 'Se elegirá al empezar cada ronda',
                        style: TextStyle(color: t.sub, fontSize: 11.5)),
                  ])),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        // Emoji
        Wrap(spacing: 8, children: _emojis.map((e) => GestureDetector(
          onTap: () => setState(() => _emoji = e),
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: _emoji == e ? t.primary.withValues(alpha: 0.15) : t.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _emoji == e ? t.primary : t.divider),
            ),
            child: Center(child: Text(e, style: const TextStyle(fontSize: 18))),
          ),
        )).toList()),
        const SizedBox(height: 12),
        TextField(
          controller: _nameCtrl,
          style: TextStyle(color: t.text, fontSize: 14),
          decoration: InputDecoration(labelText: 'Nombre de la plantilla *', labelStyle: TextStyle(color: t.sub, fontSize: 13),
            filled: true, fillColor: t.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.primary, width: 1.5)),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _descCtrl,
          style: TextStyle(color: t.text, fontSize: 14),
          decoration: InputDecoration(labelText: 'Descripción (opcional)', labelStyle: TextStyle(color: t.sub, fontSize: 13),
            filled: true, fillColor: t.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.primary, width: 1.5)),
          ),
        ),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancelar', style: TextStyle(color: t.sub))),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(backgroundColor: t.primary, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Guardar', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingresa un nombre para la plantilla')));
      return;
    }
    setState(() => _saving = true);
    final template = RoundTemplate(
      id: '',
      name: _nameCtrl.text.trim(),
      emoji: _emoji,
      description: _descCtrl.text.trim(),
      playerNames: widget.players.map((p) => p.name).toList(),
      betGroupsJson: widget.betGroups.map((g) => g.toJson()).toList(),
      updatedAt: DateTime.now(),
      courseName: _conCampo ? widget.courseName : null,
    );
    await FirestoreService.saveTemplate(template);
    if (mounted) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Plantilla "${template.name}" guardada'), backgroundColor: Colors.green));
    }
  }
}

/// Encabezado de sección con lo que la sección hace.
class _Seccion extends StatelessWidget {
  final String titulo;
  final String detalle;
  final GolfTheme t;
  const _Seccion(
      {required this.titulo, required this.detalle, required this.t});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titulo,
            style: TextStyle(
                color: t.sub,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8)),
        const SizedBox(height: 3),
        Text(detalle, style: TextStyle(color: t.sub, fontSize: 11.5, height: 1.35)),
      ]),
    );
  }
}

/// Un grupo de apuesta como punto de entrada a una ronda nueva.
class _GrupoCard extends StatelessWidget {
  final BettingGroup grupo;
  final GolfTheme t;
  const _GrupoCard({required this.grupo, required this.t});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Al ATAJO, no al wizard.
      //
      // Antes abría SetupScreen y aterrizaba en "paso 1 de 8" sin un check: la
      // precarga funcionaba pero había que pulsar Siguiente seis veces
      // confirmando lo que el grupo ya respondía. El wizard sigue a un toque,
      // desde "Revisar todo".
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => QuickStartScreen(grupo: grupo),
      )),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.divider),
        ),
        child: Row(children: [
          Text(grupo.emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(grupo.name,
                    style: TextStyle(
                        color: t.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
                const SizedBox(height: 2),
                Text(
                    '${grupo.playerIds.length} jugadores · '
                    '${grupo.activeRulesCount} duelos · '
                    '${grupo.totalModules} apuestas',
                    style: TextStyle(color: t.sub, fontSize: 12)),
                const SizedBox(height: 3),
                // Qué falta por decidir, no de qué TIPO es.
                //
                // "Grupo de apuesta" contra "plantilla de ronda" describe
                // implementación; el usuario piensa "hoy juego con los del
                // viernes". Lo que le permite decidir si tocar la tarjeta es
                // saber qué queda pendiente, y eso además vuelve la distinción
                // innecesaria en la etiqueta.
                Text(
                    faltaPorDecidir(preguntasPendientes(
                        traeCampo: false, traeVentaja: false)),
                    style: TextStyle(
                        color: t.primary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600)),
              ])),
          Icon(Icons.chevron_right, color: t.sub, size: 20),
        ]),
      ),
    );
  }
}
