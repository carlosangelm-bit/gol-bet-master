// ─────────────────────────────────────────────────────────────────────────────
// APP NAVIGATION — volver al shell cuando la ronda arranca
//
// El bug: iniciar la ronda desde una plantilla devolvía a "Mis Plantillas" en
// vez de a la ronda. Y no era la pestaña —startRound ya pone tabIndex en Score—
// sino la PILA.
//
// _createAndStartRound hacía un solo Navigator.pop(), que basta cuando el wizard
// se abrió desde Nueva Ronda:
//
//     [Shell, Setup]                    → un pop → Shell        ✅
//
// Pero desde una plantilla hay dos pantallas encima, porque QuickStartScreen
// reemplaza y Plantillas se queda debajo:
//
//     [Shell, Plantillas, Setup]        → un pop → Plantillas   ❌
//
// Un número fijo de pops solo funciona para el camino desde el que se escribió.
// Es la misma forma que el doble pop del sheet de apuesta: navegación repartida
// entre sitios que no saben cuántos hay.
//
// La convención: al arrancar una ronda se vuelve al SHELL, esté donde esté la
// pila. Así el número de pantallas intermedias deja de importar, y una entrada
// nueva —otro atajo, otro punto de partida— no vuelve a descuadrarlo.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';

/// Cierra todo lo que haya encima del shell.
///
/// El shell es la primera ruta, así que [Route.isFirst] lo identifica sin que
/// haya que saber por dónde se entró. Con la pila ya en el shell no hace nada,
/// que es lo correcto: llamarlo dos veces no puede dejar la app sin pantallas.
void volverAlShell(BuildContext context) {
  Navigator.of(context).popUntil((r) => r.isFirst);
}
