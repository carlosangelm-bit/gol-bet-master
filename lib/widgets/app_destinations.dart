// ─────────────────────────────────────────────────────────────────────────────
// APP DESTINATIONS — los destinos que salieron de la barra
//
// La fase 5 bajó la navegación de siete a cuatro. Historial y Ajustes no
// compiten por atención DURANTE una ronda, así que no merecen sitio permanente:
// se abren desde Inicio.
//
// Viven aquí y no en app_shell para no crear un ciclo de imports —el shell ya
// importa Inicio— y para que haya UN solo sitio que sepa cómo se llega a cada
// uno. Repartir eso por las pantallas es lo que produce dos rutas al mismo
// destino que se comportan distinto.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_shell.dart';
import '../core/app_theme.dart';
import '../providers/auth_provider.dart';
import '../screens/history/history_screen.dart';

void openHistory(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => const HistoryScreen(),
  ));
}

void openSettings(BuildContext context) {
  final auth = context.read<AuthProvider>();
  final t = GolfThemeExt.current;
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        title: Text('Ajustes',
            style: TextStyle(
                color: t.text, fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: SettingsWithProfile(auth: auth, t: t),
    ),
  ));
}
