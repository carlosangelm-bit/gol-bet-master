// ─────────────────────────────────────────────────────────────────────────────
// MAIN — Golf Bet Master
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/firebase_options.dart';
import 'providers/round_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/player_provider.dart';
import 'providers/user_profile_provider.dart';
import 'providers/handicap_provider.dart';
import 'providers/perfil_provider.dart';
import 'providers/torneo_provider.dart';
import 'providers/betting_group_provider.dart';
import 'app_shell.dart';
import 'screens/guest/guest_join_screen.dart';
import 'screens/caddie/caddie_join_screen.dart';

void main() {
  // Capturar y mostrar errores de framework (incluido release)
  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details);
  };

  // Capturar errores no controlados en zonas
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Inicializar datos de formato de fecha para el locale 'es'
    await initializeDateFormatting('es', null);

    // Configurar el ErrorWidget antes de cualquier render
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return _AppErrorWidget(details: details);
    };

    if (!kIsWeb) {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }

    // Inicializar Firebase con manejo de errores robusto
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

      // En Web, forzar Long Polling en lugar de WebChannel para evitar:
      // "WebChannelConnection RPC 'Listen' stream transport errored"
      // autoDetect no es suficiente — forzamos Long Polling directamente.
      // Esto garantiza compatibilidad con cualquier red/proxy/Safari.
      // persistenceEnabled: true → caché local IndexedDB en Web.
      // Permite que el perfil y los campos favoritos se sirvan desde
      // caché local sin esperar respuesta de red en cada apertura de
      // Ajustes, eliminando el spinner de "Cargando perfil…".
      if (kIsWeb) {
        FirebaseFirestore.instance.settings = const Settings(
          webExperimentalForceLongPolling: true,
          persistenceEnabled: true,
          ignoreUndefinedProperties: true,
        );
      }
    } catch (e) {
      debugPrint('Firebase init error: $e');
      runApp(_ErrorApp(message: 'Firebase init error: $e'));
      return;
    }

    RoundProvider? prov;
    try {
      prov = RoundProvider();
      await prov.loadPrefs();
    } catch (e) {
      debugPrint('RoundProvider init error: $e');
      prov ??= RoundProvider();
    }

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<RoundProvider>.value(value: prov),
          ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
          ChangeNotifierProvider<PlayerProvider>(create: (_) => PlayerProvider()),
          ChangeNotifierProvider<UserProfileProvider>(create: (_) => UserProfileProvider()),
          ChangeNotifierProvider<HandicapProvider>(create: (_) => HandicapProvider()),
          ChangeNotifierProvider<PerfilProvider>(create: (_) => PerfilProvider()),
          ChangeNotifierProvider<TorneoProvider>(create: (_) => TorneoProvider()),
          ChangeNotifierProvider<BettingGroupProvider>(create: (_) => BettingGroupProvider()),
        ],
        child: const GolfBetApp(),
      ),
    );
  }, (e, st) {
    debugPrint('Zone error: $e\n$st');
    // Si hay un error fatal antes de runApp, mostrar pantalla de error
    try {
      runApp(_ErrorApp(message: 'Error fatal: $e'));
    } catch (_) {}
  });
}

class GolfBetApp extends StatelessWidget {
  const GolfBetApp({super.key});

  // ── Detectar ruta /guest/:token o /caddie/:token en la URL del navegador ────
  static String? _extractGuestToken() {
    if (!kIsWeb) return null;
    try {
      final uri      = Uri.base;
      final segments = uri.pathSegments;
      if (segments.length >= 2 && segments[0] == 'guest') {
        return segments[1];
      }
    } catch (_) {}
    return null;
  }

  static String? _extractCaddieToken() {
    if (!kIsWeb) return null;
    try {
      final uri      = Uri.base;
      final segments = uri.pathSegments;
      if (segments.length >= 2 && segments[0] == 'caddie') {
        return segments[1];
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final prov        = context.watch<RoundProvider>();
    final guestToken  = _extractGuestToken();
    final caddieToken = _extractCaddieToken();

    return MaterialApp(
      title: 'Golf Bet Master', // v1.1.0+5
      debugShowCheckedModeBanner: false,
      theme: prov.theme.toMaterial(),
      // Mostrar errores de widget en pantalla (no pantalla en blanco)
      builder: (context, child) {
        ErrorWidget.builder = (FlutterErrorDetails details) {
          return _AppErrorWidget(details: details);
        };
        return child ?? const SizedBox.shrink();
      },
      // Prioridad: caddie > guest > app normal
      home: caddieToken != null
          ? CaddieJoinScreen(token: caddieToken)
          : guestToken != null
              ? GuestJoinScreen(token: guestToken)
              : const AppShell(),
      onGenerateRoute: (settings) {
        final name = settings.name ?? '';
        if (name.startsWith('/caddie/')) {
          final token = name.replaceFirst('/caddie/', '');
          return MaterialPageRoute(
            builder: (_) => CaddieJoinScreen(token: token),
          );
        }
        if (name.startsWith('/guest/')) {
          final token = name.replaceFirst('/guest/', '');
          return MaterialPageRoute(
            builder: (_) => GuestJoinScreen(token: token),
          );
        }
        return null;
      },
    );
  }
}

/// App de error mínima para errores antes de inicialización
class _ErrorApp extends StatelessWidget {
  final String message;
  const _ErrorApp({required this.message});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('⚠️', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 16),
                const Text('Error de inicialización',
                    style: TextStyle(color: Color(0xFFE53935),
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D2D44),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(message,
                      style: const TextStyle(color: Color(0xFFFF8A80),
                          fontSize: 12, fontFamily: 'monospace')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Widget de error visual que reemplaza la pantalla en blanco
class _AppErrorWidget extends StatelessWidget {
  final FlutterErrorDetails details;
  const _AppErrorWidget({required this.details});

  @override
  Widget build(BuildContext context) {
    final msg = details.exceptionAsString();
    final stack = details.stack?.toString() ?? '';
    final shortStack = stack.split('\n').take(10).join('\n');

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Text('⚠️', style: TextStyle(fontSize: 24)),
                SizedBox(width: 8),
                Expanded(child: Text('Error de la aplicación',
                    style: TextStyle(color: Color(0xFFE53935),
                        fontSize: 16, fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2D44),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE53935).withValues(alpha: 0.4)),
                ),
                child: Text(msg,
                    style: const TextStyle(color: Color(0xFFFF8A80),
                        fontSize: 12, fontFamily: 'monospace')),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(shortStack,
                      style: const TextStyle(color: Color(0xFF9E9E9E),
                          fontSize: 10, fontFamily: 'monospace')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
