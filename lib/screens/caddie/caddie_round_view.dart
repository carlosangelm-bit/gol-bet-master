// ─────────────────────────────────────────────────────────────────────────────
// CADDIE ROUND VIEW — Vista de solo lectura para caddies / espectadores
//
// Reutiliza exactamente las mismas pantallas que los jugadores:
//   • ScorecardScreen  →  tarjeta de hoyos (1v1, scoring, skins…)
//   • ResultsScreen    →  balance de apuestas
//
// Diferencias vs GuestRoundView:
//   • No ocupa cupo de jugador (el caddie no está en round.players).
//   • No muestra el botón "Cerrar ronda" (el caddie no es owner).
//   • Muestra un banner permanente de "Solo visualización" para recordar el rol.
//   • El RoundProvider local se alimenta de liveRounds en tiempo real
//     igual que el de un jugador invitado, pero sin escribir nada.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../models/models.dart';
import '../../providers/round_provider.dart';
import '../../screens/results/results_screen.dart';
import '../../screens/scorecard/scorecard_screen.dart';

class CaddieRoundView extends StatelessWidget {
  final Round round;
  const CaddieRoundView({super.key, required this.round});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final prov = RoundProvider();
        // joinLiveRound: suscribe al stream de liveRounds en tiempo real
        // sin escribir nada en Firestore.
        prov.joinLiveRound(round);
        return prov;
      },
      child: const _CaddieShell(),
    );
  }
}

// ── Shell principal ───────────────────────────────────────────────────────────
class _CaddieShell extends StatefulWidget {
  const _CaddieShell();
  @override
  State<_CaddieShell> createState() => _CaddieShellState();
}

class _CaddieShellState extends State<_CaddieShell> {
  int _selectedIndex = 0;

  static const _tabs = [
    _TabEntry(
        label: 'Tarjeta',
        icon: Icons.grid_on_outlined,
        activeIcon: Icons.grid_on),
    _TabEntry(
        label: 'Resultados',
        icon: Icons.account_balance_wallet_outlined,
        activeIcon: Icons.account_balance_wallet),
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
      body: Column(children: [
        // Banner permanente "Solo visualización"
        _CaddieBanner(t: t),
        Expanded(
          child: IndexedStack(
            index: _selectedIndex,
            children: _screens,
          ),
        ),
      ]),
      bottomNavigationBar: _CaddieNavBar(
        tabs: _tabs,
        selectedIndex: _selectedIndex,
        t: t,
        onTap: (i) => setState(() => _selectedIndex = i),
      ),
    );
  }
}

// ── Banner permanente de solo lectura ─────────────────────────────────────────
class _CaddieBanner extends StatelessWidget {
  final GolfTheme t;
  const _CaddieBanner({required this.t});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF006064).withValues(alpha: 0.95),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.visibility_rounded,
              color: Color(0xFF80DEEA), size: 14),
          const SizedBox(width: 8),
          Text(
            'Acceso Caddie — Solo visualización',
            style: TextStyle(
              color: const Color(0xFF80DEEA),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Modelo de pestaña ─────────────────────────────────────────────────────────
class _TabEntry {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  const _TabEntry(
      {required this.label,
      required this.icon,
      required this.activeIcon});
}

// ── Barra de navegación inferior ──────────────────────────────────────────────
class _CaddieNavBar extends StatelessWidget {
  final List<_TabEntry> tabs;
  final int selectedIndex;
  final GolfTheme t;
  final ValueChanged<int> onTap;

  const _CaddieNavBar({
    required this.tabs,
    required this.selectedIndex,
    required this.t,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF00BCD4);
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
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          decoration: BoxDecoration(
                            color: sel
                                ? teal.withValues(alpha: 0.14)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            sel ? tab.activeIcon : tab.icon,
                            color: sel ? teal : t.sub,
                            size: 22,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tab.label,
                          style: TextStyle(
                            color: sel ? teal : t.sub,
                            fontSize: 10,
                            fontWeight: sel
                                ? FontWeight.w700
                                : FontWeight.w400,
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
