// ─────────────────────────────────────────────────────────────────────────────
// APP SHELL — Navegación principal con Firebase Auth
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/app_theme.dart';
import 'core/escuchas.dart';
import 'providers/round_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/player_provider.dart';
import 'screens/capture/capture_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/scorecard/scorecard_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/templates/templates_screen.dart';
import 'screens/bets/bets_screen.dart';

/// Los destinos de la barra principal.
enum MainDestination { inicio, score, apuestas, resultados }

extension MainDestinationLabel on MainDestination {
  String get label => switch (this) {
        MainDestination.inicio => 'Inicio',
        MainDestination.score => 'Score',
        MainDestination.apuestas => 'Apuestas',
        MainDestination.resultados => 'Resultados',
      };
}

/// Qué destinos existen ahora mismo. **Única definición de la composición.**
///
/// La fase 5 los bajó de siete a cuatro. Esta función es la que consume el
/// build para armar las pestañas Y la que comprueban los tests: una lista
/// duplicada en el test no cazaría un cambio en la de verdad, que es
/// exactamente el fallo del catálogo de Inicio.
///
/// [hideScore] es el caso del invitado en una ronda live con captura de admin:
/// no ve Score, pero sí todo lo demás.
List<MainDestination> mainDestinations({
  required bool hasRound,
  required bool hideScore,
}) =>
    [
      MainDestination.inicio,
      if (hasRound) ...[
        if (!hideScore) MainDestination.score,
        MainDestination.apuestas,
        MainDestination.resultados,
      ],
    ];

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _listenersStarted = false;
  Timer? _reintento;

  @override
  void dispose() {
    _reintento?.cancel();
    super.dispose();
  }

  void _startListenersIfNeeded() {
    if (_listenersStarted) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isAuth) return;
    // OJO: el flag se pone con lo que DEVUELVE, no antes de llamar.
    //
    // Ponerlo antes era decir "ya está" sobre algo que todavía no había pasado.
    // startListening() se rinde en silencio si aún no hay uid, así que un
    // intento medio segundo pronto quedaba como definitivo y la sesión entera
    // se quedaba sin torneos. Se vio en el portal de organizador, pero el latch
    // era el mismo aquí.
    //
    // La lista vive en core/escuchas.dart: el portal es otra raíz y arranca las
    // mismas, y dos copias se habrían separado.
    _listenersStarted = iniciarEscuchas(context);
    if (!_listenersStarted) {
      _reintento ??= Timer.periodic(const Duration(milliseconds: 400), (tm) {
        if (!mounted) {
          tm.cancel();
          return;
        }
        _startListenersIfNeeded();
        if (_listenersStarted) {
          tm.cancel();
          _reintento = null;
        }
      });
    }
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
      // stopListening() llama a notifyListeners(), y hacerlo DENTRO de build
      // lanza "setState() called during build". Además solo tiene sentido en
      // la transición sesión→sin sesión, no en cada rebuild de la pantalla de
      // login. Por eso se condiciona al flag y se difiere al siguiente frame.
      if (_listenersStarted) {
        _listenersStarted = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _reintento?.cancel();
            _reintento = null;
            detenerEscuchas(context);
          }
        });
      }
      return const AuthScreen();
    }

    // NOTA: NO llamar startListening() aquí dentro del build() — causa loop infinito.
    // Se inicia UNA SOLA VEZ via _startListenersIfNeeded() (usa flag _listenersStarted).
    //
    // Los start*/init de los providers llaman a notifyListeners() de forma
    // síncrona (ponen _loading=true), así que invocarlos durante build lanza
    // "setState() called during build". Se difieren al siguiente frame.
    if (auth.status == AuthStatus.authenticated && !_listenersStarted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startListenersIfNeeded();
      });
    }

    final hasRound = prov.hasRound;

    // Determinar si se muestra el tab de Score:
    // Se oculta cuando la ronda es live, en modo 'admin', y el usuario NO es el owner.
    final round = prov.round;
    final hideScoreTab = hasRound &&
        (round?.isLive ?? false) &&
        (round?.isAdminScoring ?? false) &&
        !prov.isLiveOwner;

    // ── Cuatro destinos ───────────────────────────────────────────────────
    //
    // Eran siete, por encima del techo cómodo, y dos pares se solapaban:
    //
    //   · Tarjeta y Resultados responden la MISMA pregunta —"cómo va la cosa"—
    //     así que se fusionan en un destino con pestañas. Tenerlas separadas
    //     obligaba a elegir entre ellas sin saber cuál tenía el dato.
    //   · Historial y Ajustes no compiten por atención DURANTE una ronda, así
    //     que no merecen sitio en la barra: se llega a ellos desde Inicio.
    //
    // Con cuatro hay ancho para objetivos de toque más grandes, que importa con
    // guante y a una mano.
    // La composición la decide mainDestinations, que es lo que también
    // comprueban los tests. Aquí solo se le pone cara a cada uno.
    final tabs = [
      for (final d in mainDestinations(
          hasRound: hasRound, hideScore: hideScoreTab))
        switch (d) {
          MainDestination.inicio => _TabEntry(
              label: d.label,
              icon: Icons.home_outlined,
              activeIcon: Icons.home,
              screen: const HomeScreen()),
          MainDestination.score => _TabEntry(
              label: d.label,
              icon: Icons.edit_outlined,
              activeIcon: Icons.edit,
              screen: const CaptureScreen()),
          MainDestination.apuestas => _TabEntry(
              label: d.label,
              icon: Icons.paid_outlined,
              activeIcon: Icons.paid,
              screen: const BetsScreen()),
          // La pantalla anfitriona es ScorecardScreen: ya tenía el
          // TabController y las tres vistas, y Resumen entra como primera
          // pestaña.
          MainDestination.resultados => _TabEntry(
              label: d.label,
              icon: Icons.account_balance_wallet_outlined,
              activeIcon: Icons.account_balance_wallet,
              screen: const ScorecardScreen()),
        },
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
      // Con una sola pestaña la barra no decide nada: sin ronda solo queda
      // Inicio, y una barra de un elemento es ruido que además roba alto.
      bottomNavigationBar: tabs.length > 1
          ? _GolfNavBar(tabs: tabs, selectedIndex: idx, t: t)
          : null,
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
/// Ajustes con la ficha del usuario encima.
///
/// Público desde la fase 5: Ajustes dejó de ser un destino de la barra —no
/// compite por atención durante una ronda— y se abre desde Inicio, así que
/// tiene que ser alcanzable desde fuera de este archivo.
class SettingsWithProfile extends StatelessWidget {
  final AuthProvider auth;
  final GolfTheme t;
  const SettingsWithProfile({super.key, required this.auth, required this.t});

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
          child: Text('Cerrar sesión', style: TextStyle(color: t.danger, fontWeight: FontWeight.w700)),
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
