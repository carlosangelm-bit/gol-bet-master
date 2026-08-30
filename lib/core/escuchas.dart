// ─────────────────────────────────────────────────────────────────────────────
// QUIÉN SE PONE A ESCUCHAR AL ENTRAR — una sola definición
//
// Los streams de Firestore no arrancan solos: alguien tiene que llamar a
// startListening() por cada provider. Hasta ahora ese alguien era AppShell, y
// era suficiente porque todo pasaba por AppShell.
//
// El portal de organizador NO pasa por AppShell —es otra raíz, con su propio
// layout— así que necesita arrancarlos también. La forma cómoda era copiar la
// lista. Y una lista copiada se pudre: el día que se añada un provider, alguien
// lo añade en un sitio, el otro sigue funcionando "casi", y lo que falla es una
// pantalla que sale vacía sin decir por qué.
//
// Es la misma lección que mainDestinations en app_shell.dart: la composición se
// define UNA vez y las dos pantallas la consumen.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/betting_group_provider.dart';
import '../providers/handicap_provider.dart';
import '../providers/perfil_provider.dart';
import '../providers/player_provider.dart';
import '../providers/round_provider.dart';
import '../providers/torneo_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/user_profile_service.dart';

/// Los nombres de lo que se arranca. Existe para que un test pueda comprobar
/// que las dos raíces arrancan LO MISMO sin instanciar Firebase.
const escuchasQueArrancan = <String>[
  'RoundProvider',
  'PlayerProvider',
  'UserProfileProvider',
  'HandicapProvider',
  'PerfilProvider',
  'TorneoProvider',
  'BettingGroupProvider',
];

/// Arranca los streams de la sesión. Idempotente por parte de cada provider,
/// pero quien llama debe hacerlo una sola vez —ver el flag de AppShell—.
///
/// NO llamar dentro de un build(): los start*/init llaman a notifyListeners()
/// de forma síncrona y eso lanza "setState() called during build". Se difiere
/// al siguiente frame en los dos sitios que lo usan.
void iniciarEscuchas(BuildContext context) {
  context.read<RoundProvider>().syncFromFirestore();
  context.read<PlayerProvider>().startListening();
  context.read<UserProfileProvider>().startListening();
  context.read<HandicapProvider>().startListening();
  context.read<PerfilProvider>().startListening();
  context.read<TorneoProvider>().startListening();
  context.read<BettingGroupProvider>().init();
}

/// Corta los streams al cerrar sesión y olvida la identidad.
void detenerEscuchas(BuildContext context) {
  context.read<HandicapProvider>().stopListening();
  context.read<PerfilProvider>().stopListening();
  context.read<TorneoProvider>().stopListening();
  // El siguiente usuario no hereda la identidad del anterior.
  UserProfileService.olvidaIdentidad();
}
