// ─────────────────────────────────────────────────────────────────────────────
// TORNEO PROVIDER — la definición se guarda, la tabla se deriva
//
// Hermano de PerfilProvider y montado igual. Lo único que transmite son las
// DEFINICIONES de torneo; la tabla la calcula tablaDe() con los resultados que
// PerfilProvider ya tiene en memoria.
//
// Ninguna tabla se guarda, y es a propósito: si se guardara, corregir una ronda
// dejaría la clasificación vieja sin avisar. Es exactamente lo que pasó con los
// balances del tablero de Inicio.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/torneo.dart';
import '../models/torneo_seguido.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

class TorneoProvider extends ChangeNotifier {
  StreamSubscription<List<Torneo>>? _sub;
  List<Torneo> _torneos = [];
  bool _loading = false;
  String? _error;

  /// Si ya llegó el PRIMER snapshot.
  ///
  /// ── La diferencia que faltaba ─────────────────────────────────────────────
  ///
  /// `loading` no sirve para esto: nace en false, así que entre que una pantalla
  /// se monta y que alguien llama a startListening() hay un hueco en el que
  /// `loading == false` y la lista está vacía. Quien lea eso concluye "no hay
  /// torneos" cuando lo cierto es "todavía no lo sé".
  ///
  /// Eso es lo que enseñaba "este torneo no está en tu cuenta" en el portal de
  /// organizador, con un torneo que sí era suyo. Una lista vacía y una lista sin
  /// cargar se veían igual, y esa confusión es indistinguible de un permiso
  /// denegado.
  bool _cargado = false;

  List<Torneo> get torneos => _torneos;
  bool get loading => _loading;
  String? get error => _error;

  /// Si ya se sabe la respuesta. Ver [_cargado].
  bool get cargado => _cargado;

  /// Si la suscripción está viva de verdad.
  ///
  /// Existe porque [startListening] puede rendirse en silencio —sin uid todavía
  /// no hay nada a lo que suscribirse— y quien lo llamó necesita saber si tiene
  /// que volver a intentarlo. Sin esto, un intento fallido se quedaba como
  /// intento definitivo.
  bool get escuchando => _sub != null;

  /// Si está esperando a que aparezca el uid para suscribirse.
  bool get reintentando => _reintento != null;

  /// Siembra sin Firestore, para los tests de widget.
  @visibleForTesting
  void sembrar(List<Torneo> t) {
    _torneos = t;
    _loading = false;
    _cargado = true;
    notifyListeners();
  }

  Timer? _reintento;
  int _intentos = 0;

  /// Cuántas veces se vuelve a intentar cuando todavía no hay uid.
  ///
  /// Acotado a propósito: sin tope, una sesión cerrada dejaría un reloj girando
  /// para siempre. Ocho segundos cubren de sobra la propagación del token, que
  /// es lo único que se está esperando.
  static const _maxIntentos = 20;

  /// ── POR QUÉ ESTO REINTENTA, Y NO LO HACE CADA PANTALLA ────────────────────
  ///
  /// Esta función se rendía en silencio: sin uid, `return`. No lanzaba, no
  /// avisaba, no se suscribía. Quien la llamaba —AppShell, el portal de
  /// organizador, la pantalla del enlace— marcaba "ya arrancado" y no volvía a
  /// intentarlo nunca, así que un intento medio segundo pronto se convertía en
  /// no tener torneos en toda la sesión.
  ///
  /// Ha aparecido CUATRO veces con formas distintas, siempre "algo que AppShell
  /// hacía y que las rutas propias no heredan". Ponerle el reintento a cada
  /// pantalla habría sido esperar a la quinta. El agujero está aquí, así que se
  /// tapa aquí y las tres lo heredan.
  void startListening() {
    if (_sub != null) return;
    if (AuthService.uid == null) {
      if (_intentos >= _maxIntentos) {
        // Se cancela AQUÍ, no en el siguiente tic: un reloj que sigue vivo
        // esperando a apagarse solo es un reloj vivo, y en una sesión cerrada
        // no tiene nada que hacer.
        _reintento?.cancel();
        _reintento = null;
        return;
      }
      _intentos++;
      _reintento ??= Timer.periodic(
          const Duration(milliseconds: 400), (_) => startListening());
      return;
    }
    _reintento?.cancel();
    _reintento = null;
    _loading = true;
    notifyListeners();
    _subSeguidos ??= FirestoreService.torneosSeguidosStream().listen((l) {
      _seguidos = l;
      notifyListeners();
    }, onError: (_) {});
    _sub = FirestoreService.torneosStream().listen((lista) {
      _torneos = lista;
      _loading = false;
      _cargado = true;
      _error = null;
      notifyListeners();
    }, onError: (e) {
      _error = e.toString();
      _loading = false;
      // También cargado: ya se sabe la respuesta, y es que falló. Dejarlo en
      // false colgaría la pantalla en "cargando…" para siempre, que es el otro
      // extremo del mismo error.
      _cargado = true;
      notifyListeners();
    });
  }

  void stopListening() {
    _reintento?.cancel();
    _reintento = null;
    _intentos = 0;
    _sub?.cancel();
    _sub = null;
    _subSeguidos?.cancel();
    _subSeguidos = null;
    _seguidos = [];
    _torneos = [];
    _loading = false;
    // Vuelve a "todavía no lo sé": la lista vacía de después de cerrar sesión no
    // es una respuesta sobre los torneos de nadie.
    _cargado = false;
    notifyListeners();
  }

  Future<void> guardar(Torneo t) async {
    final guardado = await FirestoreService.saveTorneo(t);
    // Optimista: el stream lo confirmará. Sin esto, crear un torneo y volver a
    // la lista lo enseña vacío hasta que Firestore contesta.
    final i = _torneos.indexWhere((x) => x.id == guardado.id);
    if (i >= 0) {
      _torneos[i] = guardado;
    } else {
      _torneos = [..._torneos, guardado];
    }
    notifyListeners();
  }

  /// Los torneos AJENOS que sigo, para poder marcarles rondas.
  ///
  /// Van aparte de los míos a propósito: un torneo seguido es una referencia
  /// —nombre, token y dueño— no una copia de la configuración. Mezclarlos en una
  /// sola lista habría hecho creer que se pueden editar.
  List<TorneoSeguido> _seguidos = [];
  List<TorneoSeguido> get seguidos => _seguidos;
  StreamSubscription<List<TorneoSeguido>>? _subSeguidos;

  @visibleForTesting
  void sembrarSeguidos(List<TorneoSeguido> s) {
    _seguidos = s;
    notifyListeners();
  }

  /// Sigue un torneo, ACTUALIZANDO PRIMERO y guardando después.
  ///
  /// El orden importa y estaba al revés: escribía y luego actualizaba, así que
  /// mientras la escritura estuviera en vuelo —o si nunca resolvía, que en web
  /// pasa— el botón se quedaba igual y parecía que el toque no había hecho nada.
  ///
  /// Es el mismo patrón optimista que ya usaba `guardar`: la pantalla refleja la
  /// intención al instante y el stream confirma. Si la escritura falla se
  /// deshace, así que no se queda diciendo algo que no es.
  Future<void> seguir(TorneoSeguido s) async {
    if (_seguidos.any((x) => x.torneoId == s.torneoId)) return;
    final antes = _seguidos;
    _seguidos = [..._seguidos, s];
    notifyListeners();
    try {
      await FirestoreService.seguirTorneo(s);
    } catch (e) {
      _seguidos = antes;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> dejarDeSeguir(String torneoId) async {
    final antes = _seguidos;
    _seguidos = _seguidos.where((x) => x.torneoId != torneoId).toList();
    notifyListeners();
    try {
      await FirestoreService.dejarDeSeguir(torneoId);
    } catch (e) {
      _seguidos = antes;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> borrar(String id) async {
    await FirestoreService.deleteTorneo(id);
    _torneos = _torneos.where((x) => x.id != id).toList();
    notifyListeners();
  }

  @override
  void dispose() {
    _reintento?.cancel();
    _subSeguidos?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
