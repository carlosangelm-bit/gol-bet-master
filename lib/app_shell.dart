// ─────────────────────────────────────────────────────────────────────────────
// APP SHELL — Navegación principal con Firebase Auth
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/app_theme.dart';
import 'providers/round_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/player_provider.dart';
import 'providers/user_profile_provider.dart';
import 'screens/capture/capture_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/players/players_screen.dart';
import 'screens/results/results_screen.dart';
import 'screens/scorecard/scorecard_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/history/history_screen.dart';
import 'screens/templates/templates_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _listenersStarted = false;

  void _startListenersIfNeeded() {
    if (_listenersStarted) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isAuth) return;
    _listenersStarted = true;
    context.read<RoundProvider>().syncFromFirestore();
    context.read<PlayerProvider>().startListening();
    context.read<UserProfileProvider>().startListening();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startListenersIfNeeded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RoundProvider>();
    final auth = context.watch<AuthProvider>();
    final t    = prov.theme;
    GolfThemeExt.setCurrent(t);

    // Mientras Firebase determina el estado de auth → splash con logo
    if (auth.status == AuthStatus.unknown) {
      return Scaffold(
        backgroundColor: t.bg,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: t.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Center(child: Text('⛳️', style: TextStyle(fontSize: 40))),
              ),
              const SizedBox(height: 20),
              Text('Golf Bet Master',
                  style: TextStyle(color: t.text, fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 24),
              SizedBox(
                width: 28, height: 28,
                child: CircularProgressIndicator(color: t.primary, strokeWidth: 2.5),
              ),
            ],
          ),
        ),
      );
    }

    // Si el usuario cierra sesión, reseteamos el flag para el próximo login
    if (auth.status == AuthStatus.unauthenticated) {
      _listenersStarted = false;
      return const AuthScreen();
    }

    // NOTA: NO llamar startListening() aquí dentro del build() — causa loop infinito.
    // Se inicia UNA SOLA VEZ via _startListenersIfNeeded() (usa flag _listenersStarted).
    if (auth.status == AuthStatus.authenticated) {
      _startListenersIfNeeded();
    }

    final hasRound = prov.hasRound;

    final tabs = <_TabEntry>[
      _TabEntry(label: 'Inicio',       icon: Icons.home_outlined,                   activeIcon: Icons.home,                      screen: const HomeScreen()),
      _TabEntry(label: 'Compañeros',   icon: Icons.people_outline,                  activeIcon: Icons.people,                    screen: const PlayersScreen()),
      if (hasRound) ...[
        _TabEntry(label: 'Score',      icon: Icons.edit_outlined,                   activeIcon: Icons.edit,                      screen: const CaptureScreen()),
        _TabEntry(label: 'Tarjeta',    icon: Icons.grid_on_outlined,                activeIcon: Icons.grid_on,                   screen: const ScorecardScreen()),
        _TabEntry(label: 'Resultados', icon: Icons.account_balance_wallet_outlined, activeIcon: Icons.account_balance_wallet,    screen: const ResultsScreen()),
      ],
      _TabEntry(label: 'Historial',    icon: Icons.history_outlined,                activeIcon: Icons.history,                   screen: const HistoryScreen()),
      _TabEntry(label: 'Ajustes',      icon: Icons.settings_outlined,               activeIcon: Icons.settings,                  screen: _SettingsWithProfile(auth: auth, t: t)),
    ];

    final maxTab = tabs.length - 1;
    final idx    = prov.tabIndex.clamp(0, maxTab);

    // Detectar si hay error de bloqueador de anuncios
    final playerProv = context.watch<PlayerProvider>();
    final hasBlockerError = playerProv.error != null &&
        (playerProv.error!.contains('unavailable') ||
         playerProv.error!.contains('INTERNAL') ||
         playerProv.error!.contains('network') ||
         playerProv.error!.contains('Failed'));

    return Scaffold(
      backgroundColor: t.bg,
      body: Column(children: [
        // Banner de advertencia bloqueador (solo en web si hay error de red)
        if (hasBlockerError)
          _BlockerWarningBanner(t: t, onDismiss: () => playerProv.retry()),
        Expanded(
          child: IndexedStack(
            index: idx,
            children: tabs.map((e) => e.screen).toList(),
          ),
        ),
      ]),
      bottomNavigationBar: _GolfNavBar(tabs: tabs, selectedIndex: idx, t: t),
    );
  }
}

// ── Banner de advertencia por bloqueador de anuncios ─────────────────────────
class _BlockerWarningBanner extends StatefulWidget {
  final GolfTheme t;
  final VoidCallback onDismiss;
  const _BlockerWarningBanner({required this.t, required this.onDismiss});

  @override
  State<_BlockerWarningBanner> createState() => _BlockerWarningBannerState();
}

class _BlockerWarningBannerState extends State<_BlockerWarningBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    final t = widget.t;
    return SafeArea(
      bottom: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          const Text('⚠️', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'Bloqueador detectado',
              style: TextStyle(
                color: t.text,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
            Text(
              'Desactiva AdBlock/uBlock para esta página o usa modo incógnito.',
              style: TextStyle(color: t.sub, fontSize: 11),
            ),
          ])),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              setState(() => _dismissed = true);
              widget.onDismiss();
            },
            child: Icon(Icons.close, color: t.sub, size: 18),
          ),
        ]),
      ),
    );
  }
}

// ── Wrapper de Settings que agrega perfil del usuario ─────────────────────────
class _SettingsWithProfile extends StatelessWidget {
  final AuthProvider auth;
  final GolfTheme t;
  const _SettingsWithProfile({required this.auth, required this.t});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Banner de usuario
      SafeArea(
        bottom: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.divider),
          ),
          child: Row(children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: t.primary.withValues(alpha: 0.15),
              child: Text(
                auth.displayName.isNotEmpty ? auth.displayName[0].toUpperCase() : '?',
                style: TextStyle(color: t.primary, fontWeight: FontWeight.w800, fontSize: 18),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(auth.displayName, style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 15)),
              Text(auth.email, style: TextStyle(color: t.sub, fontSize: 12)),
            ])),
            // Botón plantillas
            IconButton(
              icon: Icon(Icons.bookmark_outline, color: t.primary),
              tooltip: 'Mis plantillas',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TemplatesScreen())),
            ),
            // Cerrar sesión
            IconButton(
              icon: Icon(Icons.logout, color: t.sub),
              tooltip: 'Cerrar sesión',
              onPressed: () => _confirmSignOut(context),
            ),
          ]),
        ),
      ),
      const Expanded(child: SettingsScreen()),
    ]);
  }

  void _confirmSignOut(BuildContext context) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: t.card,
      title: Text('Cerrar sesión', style: TextStyle(color: t.text, fontWeight: FontWeight.w800)),
      content: Text('¿Seguro que quieres cerrar sesión?', style: TextStyle(color: t.sub)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancelar', style: TextStyle(color: t.sub))),
        TextButton(
          onPressed: () { Navigator.pop(ctx); context.read<AuthProvider>().signOut(); },
          child: Text('Cerrar sesión', style: TextStyle(color: t.loss, fontWeight: FontWeight.w700)),
        ),
      ],
    ));
  }
}

// ── Tab entry model ───────────────────────────────────────────────────────────
class _TabEntry {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Widget screen;
  const _TabEntry({required this.label, required this.icon, required this.activeIcon, required this.screen});
}

// ── Custom bottom nav bar ─────────────────────────────────────────────────────
class _GolfNavBar extends StatelessWidget {
  final List<_TabEntry> tabs;
  final int selectedIndex;
  final GolfTheme t;
  const _GolfNavBar({required this.tabs, required this.selectedIndex, required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: t.bg, border: Border(top: BorderSide(color: t.divider, width: 1))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: tabs.asMap().entries.map((e) {
              final i = e.key; final tab = e.value; final sel = i == selectedIndex;
              return Expanded(
                child: GestureDetector(
                  onTap: () => context.read<RoundProvider>().setTab(i),
                  behavior: HitTestBehavior.opaque,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: sel ? t.primary.withValues(alpha: 0.12) : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(sel ? tab.activeIcon : tab.icon, color: sel ? t.primary : t.sub, size: 22),
                    ),
                    const SizedBox(height: 2),
                    Text(tab.label, style: TextStyle(color: sel ? t.primary : t.sub, fontSize: 10, fontWeight: sel ? FontWeight.w700 : FontWeight.w400)),
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
