import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../models/models.dart';
import '../../providers/betting_group_provider.dart';
import 'betting_group_editor_screen.dart';

/// Menú de administración (3 puntos) de una tarjeta de GRUPO de apuesta:
/// **Editar** (→ editor de ESE grupo) · **Duplicar** · **Eliminar**.
///
/// Componente ÚNICO, reutilizado por la lista de grupos ([BettingGroupsScreen])
/// y por "Mis Plantillas" ([TemplatesScreen]), para que no existan dos menús que
/// puedan divergir. En la tarjeta, el chevron sigue siendo "jugar" y este menú
/// es "administrar" —la misma distinción que ya usan las tarjetas de plantilla.
class BettingGroupCardMenu extends StatelessWidget {
  final BettingGroup group;
  final GolfTheme t;
  const BettingGroupCardMenu({super.key, required this.group, required this.t});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: t.sub, size: 20),
      color: t.card,
      onSelected: (v) async {
        final bgProv = context.read<BettingGroupProvider>();
        if (v == 'edit') {
          _openEditor(context, group);
        } else if (v == 'dup') {
          await _duplicate(context, group, bgProv);
        } else if (v == 'del') {
          await _confirmDelete(context, group, bgProv);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'edit',
          child: Row(children: [
            Icon(Icons.edit_outlined, color: t.text, size: 16),
            const SizedBox(width: 8),
            Text('Editar', style: TextStyle(color: t.text)),
          ]),
        ),
        PopupMenuItem(
          value: 'dup',
          child: Row(children: [
            Icon(Icons.copy_outlined, color: t.text, size: 16),
            const SizedBox(width: 8),
            Text('Duplicar', style: TextStyle(color: t.text)),
          ]),
        ),
        PopupMenuItem(
          value: 'del',
          child: Row(children: [
            Icon(Icons.delete_outline, color: Colors.red, size: 16),
            const SizedBox(width: 8),
            const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ]),
        ),
      ],
    );
  }

  /// "Editar" lleva DIRECTO al editor de este grupo (no a la lista): el editor
  /// se siembra con `existing`, así que aterriza en el grupo concreto.
  void _openEditor(BuildContext context, BettingGroup existing) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BettingGroupEditorScreen(existing: existing),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _duplicate(
      BuildContext context, BettingGroup g, BettingGroupProvider bgProv) async {
    final copy = g.copyWith(
      id: '',
      name: '${g.name} (copia)',
      updatedAt: DateTime.now(),
    );
    await bgProv.save(copy);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Grupo duplicado: ${copy.name}'),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, BettingGroup g, BettingGroupProvider bgProv) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.card,
        title: Text('Eliminar grupo',
            style: TextStyle(
                color: t.text, fontWeight: FontWeight.w800, fontSize: 16)),
        content: Text('¿Eliminar "${g.name}"? Esta acción no se puede deshacer.',
            style: TextStyle(color: t.sub, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar', style: TextStyle(color: t.sub)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await bgProv.delete(g.id);
    }
  }
}
