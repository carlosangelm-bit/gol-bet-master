// ─────────────────────────────────────────────────────────────────────────────
// QUE UN CAMBIO LLEGUE A LA PARED
//
// «El color no llegó a la tele hasta que republiqué desde la app. Elegí la
// plantilla en el portal, y la pantalla siguió en verde hasta que apagué y
// encendí el enlace en otro sitio.»
//
// ── Por qué pasaba, y por qué no era solo del color ─────────────────────────
//
// La tele no lee el torneo: lee `leaderboards/{token}`, una INSTANTÁNEA. Es
// deliberado —la pared no tiene sesión y no puede leer el documento del
// torneo— y tiene una consecuencia que hay que atender: todo lo que viaja en
// la instantánea se queda viejo hasta que alguien la vuelve a publicar.
//
// En la instantánea viajan tres cosas: la TABLA, el INVENTARIO de patrocinio y
// la IDENTIDAD. La tabla ya se refrescaba sola al cerrar una ronda. Las otras
// dos no, y las dos se editan desde el portal:
//
//   · cambiar el diseño          → la pared seguía con el anterior
//   · cambiar un banner de marca → lo mismo, y esto ya estaba así antes
//
// El segundo caso nadie lo había reportado, pero es el mismo fallo: un
// organizador cambia el patrocinador de cabecera un sábado por la mañana y la
// pared sigue enseñando el del sábado pasado.
//
// ── La decisión: automático, no un aviso ────────────────────────────────────
//
// «Dilo en el portal — o hazlo automático al guardar.» Automático.
//
// Un aviso que dice "recuerda republicar" es trabajo que se le pasa al usuario
// para que el programa no tenga que hacerlo, y el día del torneo nadie lo lee.
// Y aquí no hay ninguna decisión que tomar: si la pantalla está encendida,
// querer el cambio Y no querer verlo en la pared no es un estado que exista.
//
// Lo que NO hace: encender. Si la pantalla está apagada esto no la enciende —
// guardar un color no puede empezar a proyectar en una pared. Es la misma
// línea que ya sostiene `Tele.debeRefrescar`.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/torneo.dart';
import '../../providers/perfil_provider.dart';
import '../../services/auth_service.dart';
import '../../services/tele_service.dart';

/// Republica la instantánea de [torneo] si su pantalla está encendida.
///
/// Devuelve true si llegó a publicar. Quien llama decide si lo cuenta: en el
/// portal no se dice nada cuando sale bien —el cambio ya se ve en la previa—
/// y sí cuando falla, que es lo que el organizador no puede adivinar.
Future<bool> republicarPantalla(BuildContext context, Torneo torneo) async {
  if (!Tele.debeRefrescar(torneo)) return false;
  final uid = AuthService.uid;
  if (uid == null) return false;

  // La tabla se calcula igual que en todas partes, de los resultados que ya
  // están en memoria. Un segundo cálculo propio aquí podría discrepar del que
  // se ve en la app, que es el error que este archivo existe para no repetir.
  final resultados = context.read<PerfilProvider>().resultados;
  final tabla = tablaDe(torneo, resultados);

  final (resultado, _) = await Tele.publicar(
    ownerUid: uid,
    torneo: torneo,
    tabla: tabla,
    cuando: DateTime.now(),
  );
  return resultado == ResultadoTele.publicada;
}

/// La frase para cuando NO se pudo. Ver [republicarPantalla].
const avisoDeRepublicacionFallida =
    'El cambio se guardó, pero no llegó a la pantalla proyectada. '
    'Apágala y enciéndela para forzarlo.';
