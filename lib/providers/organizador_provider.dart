// ─────────────────────────────────────────────────────────────────────────────
// LA MARCA DE ORGANIZADOR, EN MEMORIA
//
// Se consulta UNA vez por sesión y se guarda. La marca no cambia mientras la
// app está abierta —la pone Carlos desde la consola, no el usuario— así que
// preguntarlo en cada pintado del logo sería una lectura de Firestore por
// fotograma.
//
// ── Tres estados, y el tercero importa ─────────────────────────────────────
//
// «Todavía no lo sé» no es lo mismo que «no». Es la distinción que ya costó dos
// entregas en el portal: `loading` nace en false, así que antes de que nadie
// pregunte hay un hueco donde la respuesta parece «no» y no lo es.
//
// Con el logo eso se vería como un módulo que aparece un segundo después de
// abrir la app, o peor, como un toque que no hace nada la primera vez.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/foundation.dart';

import '../services/organizador_service.dart';

class OrganizadorProvider extends ChangeNotifier {
  bool? _marcado;

  /// True si la cuenta tiene el módulo. Null mientras no se sepa.
  bool? get marcado => _marcado;

  /// Si ya hay respuesta. Sin esto, «no sé» y «no» se leen igual.
  bool get resuelto => _marcado != null;

  bool _preguntando = false;

  /// Pregunta una vez. Volver a llamarla no repite la consulta.
  Future<void> comprobar() async {
    if (_marcado != null || _preguntando) return;
    _preguntando = true;
    final r = await OrganizadorService.esOrganizador();
    _preguntando = false;
    _marcado = r;
    notifyListeners();
  }

  /// Al cerrar sesión: la marca es de la cuenta, no del aparato.
  void olvidar() {
    _marcado = null;
    _preguntando = false;
    notifyListeners();
  }

  @visibleForTesting
  void sembrar(bool? valor) {
    _marcado = valor;
    notifyListeners();
  }
}
