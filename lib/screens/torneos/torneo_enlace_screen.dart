// ─────────────────────────────────────────────────────────────────────────────
// ABRIR UN ENLACE DE TORNEO
//
// Es literalmente la primera pantalla que va a ver alguien que no tiene la app,
// así que hace tres cosas y ninguna más: pide identificarse, carga la copia, y
// dice claro cuando el enlace ya no vale.
//
// Por qué pedir cuenta: la regla de Firestore exige `request.auth != null` para
// leer, y eso es a propósito — aquí hay dinero y nombres de terceros a la vista.
// Un enlace de WhatsApp acaba donde no se previó, y al menos así queda quién
// entró.
//
// Y cuando el enlace no vale se dice sin rodeos. Un "algo ha ido mal" en la
// primera pantalla que ve un usuario nuevo es la peor primera impresión posible;
// "el organizador revocó este enlace" es información.
import '../../core/golf_icons.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../models/torneo_publicado.dart';
import '../../providers/auth_provider.dart';
import '../../providers/torneo_provider.dart';
import '../../services/firestore_service.dart';
import '../auth/auth_screen.dart';
import 'torneo_invitado_screen.dart';

class TorneoEnlaceScreen extends StatefulWidget {
  final String token;
  const TorneoEnlaceScreen({super.key, required this.token});

  @override
  State<TorneoEnlaceScreen> createState() => _TorneoEnlaceScreenState();
}

class _TorneoEnlaceScreenState extends State<TorneoEnlaceScreen> {
  TorneoPublicado? _copia;
  bool _cargando = false;
  bool _cargado = false;

  Future<void> _cargar() async {
    if (_cargando || _cargado) return;
    setState(() => _cargando = true);
    // Los torneos que ya sigo, para que el botón sepa si este es uno.
    //
    // Hay que arrancarlo AQUÍ: por esta ruta la app no monta AppShell —el enlace
    // es su propio `home`— así que nadie había llamado a startListening y la
    // lista llegaba siempre vacía. Es idempotente y se protege sola sin sesión.
    //
    // Segundo caso del mismo patrón en esta pantalla: la lógica construida y la
    // superficie sin conectar. Lo encontró la auditoría de la cadena, no un test.
    if (mounted) context.read<TorneoProvider>().startListening();

    final c = await FirestoreService.leerTorneoPublicado(widget.token);
    if (!mounted) return;
    setState(() {
      _copia = c;
      _cargando = false;
      _cargado = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.gt;
    final auth = context.watch<AuthProvider>();

    // Sin cuenta no se lee: la regla lo exige y el motivo se explica en vez de
    // soltar al recién llegado en una pantalla de login sin contexto.
    if (auth.status != AuthStatus.authenticated) {
      return Scaffold(
        backgroundColor: t.bg,
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                const Icon(GolfIcons.trofeo, size: GolfIcons.juntoAlHeroe),
                const SizedBox(height: 10),
                Text('Te han compartido un torneo',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: t.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                    'Para verlo hace falta una cuenta. Es rápido, y es lo que '
                    'evita que la clasificación y los nombres de los jugadores '
                    'queden abiertos a cualquiera que reciba el enlace.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.sub, fontSize: 13, height: 1.45)),
              ]),
            ),
            const Expanded(child: AuthScreen()),
          ]),
        ),
      );
    }

    // Autenticado: cargar.
    if (!_cargado) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
      return Scaffold(
        backgroundColor: t.bg,
        body: Center(
            child: CircularProgressIndicator(color: t.primary)),
      );
    }

    final copia = _copia;
    // Apagado: el documento existe pero no sirve contenido. Se dice, y se dice
    // que el MISMO enlace vuelve a servir —no que haya que pedir otro—, porque
    // ahora eso es verdad.
    if (copia != null && !copia.activo) {
      return Scaffold(
        backgroundColor: t.bg,
        appBar: AppBar(
            backgroundColor: t.bg, foregroundColor: t.text, elevation: 0),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.visibility_off_rounded, size: 40, color: t.sub),
                  const SizedBox(height: 12),
                  Text('Este torneo ya no se comparte',
                      style: TextStyle(
                          color: t.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                      'El organizador lo apagó. Guarda el enlace: es el mismo '
                      'siempre, así que volverá a funcionar si lo comparte otra '
                      'vez.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: t.sub, fontSize: 13, height: 1.45)),
                ]),
          ),
        ),
      );
    }
    if (copia == null) {
      return Scaffold(
        backgroundColor: t.bg,
        appBar: AppBar(
            backgroundColor: t.bg, foregroundColor: t.text, elevation: 0),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.link_off_rounded, size: 40, color: t.sub),
                  const SizedBox(height: 12),
                  Text('Este enlace ya no vale',
                      style: TextStyle(
                          color: t.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                      'El organizador lo revocó, o el torneo se dejó de '
                      'compartir. Pídele uno nuevo.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: t.sub, fontSize: 13, height: 1.45)),
                ]),
          ),
        ),
      );
    }

    return TorneoInvitadoScreen(copia: copia);
  }
}
