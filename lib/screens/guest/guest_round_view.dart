// ─────────────────────────────────────────────────────────────────────────────
// GUEST ROUND VIEW — Contenedor del invitado
// Usa exactamente los mismos ScorecardScreen y ResultsScreen de la app original.
// Solo muestra las pestañas "Tarjeta" y "Resultados".
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../models/models.dart';
import '../../providers/round_provider.dart';
import '../../screens/results/results_screen.dart';
import '../../screens/scorecard/scorecard_screen.dart';

class GuestRoundView extends StatelessWidget {
  final Round round;
  final String playerId;
  final String token;

  const GuestRoundView({
    super.key,
    required this.round,
    required this.playerId,
    required this.token,
  });

  @override
  Widget build(BuildContext context) {
    // Crear un RoundProvider local para el invitado.
    // No interfiere con el RoundProvider global de la app.
    return ChangeNotifierProvider(
      create: (_) {
        final prov = RoundProvider();
        // joinLiveRound inyecta la ronda y activa el stream de Firestore
        // (actualización en tiempo real) sin escribir nada en Firestore.
        prov.joinLiveRound(round);
        return prov;
      },
      child: const _GuestShell(),
    );
  }
}

// ── Shell con las dos pestañas ────────────────────────────────────────────────
class _GuestShell extends StatefulWidget {
  const _GuestShell();

  @override
  State<_GuestShell> createState() => _GuestShellState();
}

class _GuestShellState extends State<_GuestShell> {
  int _selectedIndex = 0;

  static const _tabs = [
    _TabEntry(label: 'Tarjeta',    icon: Icons.grid_on_outlined,                activeIcon: Icons.grid_on),
    _TabEntry(label: 'Resultados', icon: Icons.account_balance_wallet_outlined, activeIcon: Icons.account_balance_wallet),
  ];

  static const _screens = [
    ScorecardScreen(),
    ResultsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RoundProvider>();
    final t    = prov.theme;
    GolfThemeExt.setCurrent(t);

    return Scaffold(
      backgroundColor: t.bg,
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: _GuestNavBar(
        tabs: _tabs,
        selectedIndex: _selectedIndex,
        t: t,
        onTap: (i) => setState(() => _selectedIndex = i),
      ),
    );
  }
}

// ── Modelo de pestaña ─────────────────────────────────────────────────────────
class _TabEntry {
  final String label;
  final IconData icon;
  final IconData activeIcon;

  const _TabEntry({required this.label, required this.icon, required this.activeIcon});
}

// ── Barra de navegación inferior (idéntica al diseño original) ────────────────
class _GuestNavBar extends StatelessWidget {
  final List<_TabEntry> tabs;
  final int selectedIndex;
  final GolfTheme t;
  final ValueChanged<int> onTap;

  const _GuestNavBar({
    required this.tabs,
    required this.selectedIndex,
    required this.t,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(top: BorderSide(color: t.divider, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: tabs.asMap().entries.map((e) {
              final i   = e.key;
              final tab = e.value;
              final sel = i == selectedIndex;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: sel ? t.primary.withValues(alpha: 0.12) : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        sel ? tab.activeIcon : tab.icon,
                        color: sel ? t.primary : t.sub,
                        size: 22,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tab.label,
                      style: TextStyle(
                        color: sel ? t.primary : t.sub,
                        fontSize: 10,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ]),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
