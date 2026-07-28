// ─────────────────────────────────────────────────────────────────────────────
// BETTING GROUPS SCREEN — Lista de grupos habituales de apuestas
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../models/models.dart';
import '../../providers/betting_group_provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/round_provider.dart';
import '../../widgets/common_widgets.dart';
import 'betting_group_editor_screen.dart';

class BettingGroupsScreen extends StatelessWidget {
  const BettingGroupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RoundProvider>();
    final t    = prov.theme;
    GolfThemeExt.setCurrent(t);
    final bgProv = context.watch<BettingGroupProvider>();

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(children: [
          // ── Header ─────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
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
                  child: Icon(Icons.arrow_back_ios_new,
                      color: t.text, size: 16),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: t.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.groups_rounded,
                    color: t.onPrimary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Betting Groups',
                        style: TextStyle(
                            color: t.text,
                            fontWeight: FontWeight.w800,
                            fontSize: 20)),
                    Text('Grupos habituales con apuestas por duelo',
                        style: TextStyle(color: t.sub, fontSize: 11)),
                  ],
                ),
              ),
              // Botón crear
              GestureDetector(
                onTap: () => _openEditor(context, t, null),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: t.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.add, color: t.onPrimary, size: 20),
                ),
              ),
            ]),
          ),

          // ── Contenido ──────────────────────────────────────────────────────
          Expanded(
            child: bgProv.loading
                ? Center(child: CircularProgressIndicator(color: t.primary))
                : bgProv.groups.isEmpty
                    ? _emptyState(context, t)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                        itemCount: bgProv.groups.length,
                        itemBuilder: (ctx, i) => _groupCard(
                            ctx, bgProv.groups[i], bgProv, t),
                      ),
          ),
        ]),
      ),
      floatingActionButton: bgProv.groups.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(context, t, null),
              backgroundColor: t.primary,
              foregroundColor: t.onPrimary,
              icon: const Icon(Icons.add),
              label: const Text('Nuevo grupo',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
    );
  }

  // ── Card de grupo ──────────────────────────────────────────────────────────
  Widget _groupCard(BuildContext context, BettingGroup g,
      BettingGroupProvider bgProv, GolfTheme t) {
    final playerProv = context.read<PlayerProvider>();

    // Nombre de jugadores del grupo
    String nameOf(String id) {
      try {
        return playerProv.directory
            .firstWhere((p) => p.player.id == id)
            .player
            .name
            .split(' ')
            .first;
      } catch (_) {
        return id.length > 6 ? id.substring(0, 6) : id;
      }
    }

    final playerNames = g.playerIds.take(5).map(nameOf).join(' · ');
    final moreCount   = g.playerIds.length > 5 ? g.playerIds.length - 5 : 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Header de card ───────────────────────────────────────────────
          Row(children: [
            // Emoji + nombre
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: t.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(g.emoji,
                    style: const TextStyle(fontSize: 22)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g.name,
                    style: TextStyle(
                        color: t.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
                if (g.description != null && g.description!.isNotEmpty)
                  Text(g.description!,
                      style: TextStyle(color: t.sub, fontSize: 12)),
              ],
            )),
            // Menú
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: t.sub, size: 20),
              color: t.card,
              onSelected: (v) async {
                if (v == 'edit') {
                  _openEditor(context, t, g);
                } else if (v == 'dup') {
                  await _duplicate(context, g, bgProv);
                } else if (v == 'del') {
                  await _confirmDelete(context, g, bgProv, t);
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
                    const Text('Eliminar',
                        style: TextStyle(color: Colors.red)),
                  ]),
                ),
              ],
            ),
          ]),

          const SizedBox(height: 10),
          const GDivider(),
          const SizedBox(height: 10),

          // ── Stats ────────────────────────────────────────────────────────
          Row(children: [
            _statChip(
              icon: Icons.people_outline,
              label: '${g.playerIds.length} jugadores',
              color: t.primary,
              t: t,
            ),
            const SizedBox(width: 8),
            _statChip(
              icon: Icons.compare_arrows_rounded,
              label: '${g.pairRules.length} duelos',
              color: t.accent,
              t: t,
            ),
            const SizedBox(width: 8),
            _statChip(
              icon: Icons.monetization_on_outlined,
              label: '${g.activeRulesCount} con apuestas',
              color: Colors.green.shade600,
              t: t,
            ),
          ]),

          // ── Jugadores ────────────────────────────────────────────────────
          const SizedBox(height: 10),
          Text(
            moreCount > 0
                ? '$playerNames  +$moreCount más'
                : playerNames,
            style: TextStyle(color: t.sub, fontSize: 11),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          // ── Botón editar ─────────────────────────────────────────────────
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openEditor(context, t, g),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: t.primary.withValues(alpha: 0.4)),
                foregroundColor: t.primary,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: Icon(Icons.edit_outlined, size: 15, color: t.primary),
              label: Text('Editar grupo y apuestas',
                  style: TextStyle(
                      color: t.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _statChip({
    required IconData icon,
    required String label,
    required Color color,
    required GolfTheme t,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      );

  // ── Estado vacío ───────────────────────────────────────────────────────────
  Widget _emptyState(BuildContext context, GolfTheme t) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: t.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.groups_rounded,
                    color: t.primary, size: 40),
              ),
              const SizedBox(height: 20),
              Text('Sin grupos aún',
                  style: TextStyle(
                      color: t.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                'Crea un grupo con tus compañeros habituales y define apuestas por duelo. '
                'Al iniciar una ronda, las apuestas se aplican automáticamente.',
                style: TextStyle(
                    color: t.sub, fontSize: 13, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: () => _openEditor(context, t, null),
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.primary,
                  foregroundColor: t.onPrimary,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Crear primer grupo',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ],
          ),
        ),
      );

  // ── Acciones ───────────────────────────────────────────────────────────────
  void _openEditor(BuildContext context, GolfTheme t, BettingGroup? existing) {
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
      id:        '',
      name:      '${g.name} (copia)',
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

  Future<void> _confirmDelete(BuildContext context, BettingGroup g,
      BettingGroupProvider bgProv, GolfTheme t) async {
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
