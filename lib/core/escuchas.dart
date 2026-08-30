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

/// Arranca los streams de la sesión. Idempotente por parte de cada provider.
///
/// Devuelve **true si prendieron de verdad**, y esa es la parte que importa.
///
/// ── Por qué devuelve algo, en vez de ser void ────────────────────────────────
///
/// `TorneoProvider.startListening()` se rinde en silencio si todavía no hay uid:
/// no lanza, no avisa, simplemente no se suscribe. Quien lo llamaba marcaba
/// "ya arrancado" y no volvía a intentarlo nunca, así que un intento que llegó
/// medio segundo pronto se convertía en no arrancar en toda la sesión — y lo
/// que se veía era una pantalla diciendo que un torneo propio no era tuyo.
///
/// Ahora quien llama puede saber si prendió y volver a intentarlo.
///
/// ── Y por qué cada uno va en su propio try ──────────────────────────────────
///
/// Iban seguidos en una sola secuencia. TorneoProvider es el SEXTO: cualquier
/// excepción en los cinco de antes se lo llevaba por delante sin dejar rastro,
/// y el síntoma habría sido el mismo. Que uno falle es un problema de ese uno.
///
/// NO llamar dentro de un build(): los start*/init llaman a notifyListeners()
/// de forma síncrona y eso lanza "setState() called during build". Se difiere
/// al siguiente frame en los dos sitios que lo usan.
bool iniciarEscuchas(BuildContext context) {
  void intentar(String quien, void Function() fn) {
    try {
      fn();
    } catch (e) {
      // Se traga y sigue: el fallo de uno no puede dejar sin datos a los otros
      // seis. Queda en el log, que es donde se busca cuando algo sale vacío.
      debugPrint('[escuchas] $quien no arrancó: $e');
    }
  }

  // OJO: el `context.read` va DENTRO del closure, no como argumento.
  //
  // Con `intentar('X', context.read<X>().start)` la búsqueda del provider se
  // evalúa al construir el argumento, o sea FUERA del try. Un
  // ProviderNotFoundException se escapaba y se llevaba por delante a los que
  // venían detrás — que es el fallo que este try venía justo a impedir.
  intentar('RoundProvider', () => context.read<RoundProvider>().syncFromFirestore());
  intentar('PlayerProvider', () => context.read<PlayerProvider>().startListening());
  intentar('UserProfileProvider',
      () => context.read<UserProfileProvider>().startListening());
  intentar('HandicapProvider',
      () => context.read<HandicapProvider>().startListening());
  intentar('PerfilProvider', () => context.read<PerfilProvider>().startListening());
  intentar('TorneoProvider', () => context.read<TorneoProvider>().startListening());
  intentar('BettingGroupProvider', () => context.read<BettingGroupProvider>().init());

  // TorneoProvider es el testigo: es el único que sabe decir si se suscribió, y
  // es el que hace falta para que una ruta propia sepa de qué torneo habla.
  try {
    return context.read<TorneoProvider>().escuchando;
  } catch (_) {
    return false;
  }
}

/// Corta los streams al cerrar sesión y olvida la identidad.
void detenerEscuchas(BuildContext context) {
  context.read<HandicapProvider>().stopListening();
  context.read<PerfilProvider>().stopListening();
  context.read<TorneoProvider>().stopListening();
  // El siguiente usuario no hereda la identidad del anterior.
  UserProfileService.olvidaIdentidad();
}
