// ─────────────────────────────────────────────────────────────────────────────
// PLAYER FILTER BAR — EL selector de jugador para filtrar duelos
//
// Vivía dentro de _FiltersBar en scorecard_screen, mezclado con los chips de
// estado de esa pantalla. Cuando la pestaña Duelos de Apuestas necesitó filtrar
// —con 6 jugadores hay 15 duelos y con 9 llegan a 36— la salida fácil era hacer
// otro selector.
//
// No se hizo. Dos selectores de jugador divergen en cuanto uno gane un
// comportamiento —recordar la última elección, buscar por nombre— y entonces
// filtrar en la Tarjeta y en Apuestas dejan de sentirse igual.
//
// Se extrajo solo la MITAD de jugador: los chips de estado se quedaron en
// scorecard porque son de esa vista —ganados, acumulados, perdidos— y no
// significan nada en la lista de duelos de Apuestas. Compartir lo que se
// comparte, no todo.
//
// LO QUE FALTA, dicho para que no se pierda: scorecard tiene DOS selectores más
// con su propio picker —_MyMatchesToggle y _PlayerSelector— para otras vistas.
// O sea que la divergencia que este widget evita ya existe ahí dentro, en tres
// copias. Unificar las tres es un refactor mayor que el encargo que motivó este
// archivo, y las otras dos sirven vistas con necesidades distintas, así que se
// dejan. Este es el sitio donde deberían acabar.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../models/models.dart';
import 'common_widgets.dart';

class PlayerFilterBar extends StatelessWidget {
  /// Si el filtro está activo. Con false se ven todos los duelos.
  final bool onlyMine;

  /// El jugador elegido. null = ninguno todavía.
  final Player? myPlayer;

  final List<Player> allPlayers;
  final GolfTheme t;

  /// Enciende y apaga el filtro. Solo se llama si hay jugador elegido.
  final VoidCallback onToggleMine;

  /// Elige jugador. Al elegir uno, el filtro se enciende.
  final void Function(String pid) onPickPlayer;

  const PlayerFilterBar({
    super.key,
    required this.onlyMine,
    required this.myPlayer,
    required this.allPlayers,
    required this.t,
    required this.onToggleMine,
    required this.onPickPlayer,
  });

  void _showPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final bottomPad = MediaQuery.of(ctx).viewPadding.bottom;
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPad > 0 ? bottomPad : 20),
            child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('¿Cuál jugador eres tú?',
                  style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 4),
              Text('Filtrará solo los duelos donde participas.',
                  style: TextStyle(color: t.sub, fontSize: 12)),
              const SizedBox(height: 14),
              ...allPlayers.map((p) => ListTile(
                leading: GAvatar(name: p.name, colorIndex: p.colorIndex, size: 36),
                title: Text(p.name,
                    style: TextStyle(color: t.text, fontWeight: FontWeight.w700)),
                subtitle: Text('HCP ${p.handicapBase.toStringAsFixed(0)}',
                    style: TextStyle(color: t.sub)),
                trailing: myPlayer?.id == p.id
                    ? Icon(Icons.check_circle, color: t.primary, size: 20)
                    : null,
                onTap: () {
                  onPickPlayer(p.id);
                  Navigator.pop(ctx);
                },
              )),
            ]),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPlayer = myPlayer != null;
    final myName = myPlayer?.name.split(' ').first ?? '';

    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(
        child: GestureDetector(
          onTap: hasPlayer ? onToggleMine : () => _showPicker(context),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              gradient: (onlyMine && hasPlayer)
                  ? const LinearGradient(
                      colors: [Color(0xFF1F8F3A), Color(0xFF0D5020)])
                  : null,
              color: (onlyMine && hasPlayer) ? null : const Color(0xFF2C2C2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (onlyMine && hasPlayer)
                    ? const Color(0xFF35C759).withValues(alpha: 0.50)
                    : Colors.white.withValues(alpha: 0.08),
                width: 1.2,
              ),
            ),
            child: Row(children: [
              Icon(
                (onlyMine && hasPlayer) ? Icons.person : Icons.people_outline,
                color: (onlyMine && hasPlayer) ? Colors.white : t.sub,
                size: 15,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  (onlyMine && hasPlayer)
                      ? 'Mis duelos ($myName)'
                      : 'Todos',
                  style: TextStyle(
                    color: (onlyMine && hasPlayer) ? Colors.white : t.sub,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _MiniSwitch(active: onlyMine && hasPlayer),
            ]),
          ),
        ),
      ),

      const SizedBox(width: 6),

      // ── Botón elegir jugador ──────────────────────────────────────────
      GestureDetector(
        onTap: () => _showPicker(context),
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: hasPlayer
                ? t.primary.withValues(alpha: 0.15)
                : const Color(0xFF2C2C2E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: hasPlayer
                    ? t.primary.withValues(alpha: 0.35)
                    : Colors.white.withValues(alpha: 0.08)),
          ),
          child: Icon(
            hasPlayer ? Icons.edit_outlined : Icons.person_search_outlined,
            color: hasPlayer ? t.primary : t.sub,
            size: 16,
          ),
        ),
      ),

      const SizedBox(width: 6),

      // ── Separador vertical ────────────────────────────────────────────
    ]);
  }
}

/// Interruptor pequeño del toggle. Se mueve con el selector porque solo lo
/// usaba él.
class _MiniSwitch extends StatelessWidget {
  final bool active;
  const _MiniSwitch({required this.active});
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 36, height: 20,
      decoration: BoxDecoration(
        color: active
            ? Colors.white.withValues(alpha: 0.25)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: Colors.white.withValues(alpha: active ? 0.40 : 0.12)),
      ),
      child: Stack(children: [
        AnimatedPositioned(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          left: active ? 17 : 2,
          top: 2,
          child: Container(
            width: 16, height: 16,
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.white38,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ]),
    );
  }
}
