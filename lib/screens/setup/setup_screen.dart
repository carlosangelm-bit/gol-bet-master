// SETUP SCREEN — Configurar jugadores, partidas y módulos de apuesta
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/app_theme.dart';
import '../../engines/bet_engine.dart';
import '../../models/bet_recipe.dart';
import 'setup_flow.dart';
import '../../engines/pair_agreement_engine.dart';
import '../../providers/user_profile_provider.dart';
import '../../models/models.dart';
import '../../providers/round_provider.dart';
import '../../providers/player_provider.dart';
import '../../services/golf_course_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/course_picker_sheet.dart';
import '../../widgets/bet_module_edit_sheet.dart';
import '../../services/firestore_service.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../services/player_service.dart';
import '../../services/user_profile_service.dart';
import '../../services/live_round_service.dart';
import '../../services/course_corrections_service.dart';
import '../../providers/betting_group_provider.dart';
import '../betting_groups/betting_groups_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _uuid = const Uuid();

  /// El paso actual se guarda por IDENTIDAD, no por índice.
  ///
  /// Con pasos condicionales un índice es una bomba: al pasar de equipos a
  /// individual la lista se acorta y el mismo número apunta a otra pantalla.
  /// Guardando el enum, quitar un paso no mueve al usuario de sitio.
  SetupStep _current = SetupStep.campo;

  /// Los pasos de ESTA ronda. La lista la decide [setupSteps], que es lógica
  /// pura y testeable: qué pasos existen no debería depender de un widget.
  List<SetupStep> get _steps =>
      setupSteps(porEquipos: _porEquipos, conCuenta: true);

  /// Índice del paso actual, resolviendo el caso de que haya dejado de existir
  /// —el usuario vuelve atrás y cambia a individual estando en "qué bola"—.
  int get _stepIndex => _steps.indexOf(resolveStep(_current, _steps));

  // ── Quiénes compiten ───────────────────────────────────────────────────────
  //
  // Antes esto vivía dentro de la hoja de cada apuesta. Sube a la ronda porque
  // es la respuesta que determina cuántos LADOS hay, y de los lados salen los
  // enfrentamientos y de ahí los montos. Preguntarlo por apuesta obligaba a
  // repetir la misma respuesta tantas veces como apuestas hubiera.
  bool _porEquipos = false;
  final List<String> _teamA = [];
  final List<String> _teamB = [];

  /// Qué bola cuenta. null mientras no se elija; solo aplica con equipos.
  TeamBall? _bola;

  /// Cómo se juega esa única bola. Solo aplica con [TeamBall.unaSola].
  SingleBallMode _submodo = SingleBallMode.scramble;

  // ── Qué se cuenta ──────────────────────────────────────────────────────────
  //
  // Multi-select: una ronda puede llevar skins, match y unidades a la vez, cada
  // una con su configuración. Antes se creaban de una en una.
  final Set<BetCount> _conteos = {};

  /// Partición preferida por conteo. Solo se honra donde divisionDe da opción,
  /// así que una preferencia vieja no sobrevive a un cambio de bola o longitud.
  final Map<BetCount, BetDivision> _particion = {};

  /// Cómo se cobra. Solo se ofrece donde el motor lee formatMode.
  final Map<BetCount, BetFormatMode> _reparto = {};

  static String _defaultRoundName() {
    final now = DateTime.now();
    final months = ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'];
    return 'Ronda Golf ${now.day} ${months[now.month - 1]} ${now.year}';
  }

  late final _nameCtrl = TextEditingController(text: _defaultRoundName());
  final List<Player> _players = [];
  final List<BetGroup> _groups = [];

  // ── Controllers de los sheets de configuración de apuesta ──────────────────
  //
  // Tienen que vivir FUERA del closure de build. _configWidgets se invoca desde
  // el builder de un StatefulBuilder, así que crear los TextEditingController
  // ahí dentro los destruía y recreaba en cada rebuild: el TextField perdía el
  // controller mientras tenía el foco, el IME se desconectaba y el campo de
  // monto resultaba imposible de enfocar. Al vivir aquí sobreviven al rebuild.
  //
  // Clave = identificador estable del campo ('skins.value', 'nassau.front'…).
  // Solo hay un sheet abierto a la vez, así que no hacen falta claves por módulo.
  final Map<String, TextEditingController> _cfgCtrls = {};

  /// Nombre de pila de un jugador de la ronda. Cae al id si no se encuentra,
  /// para que un dato huérfano no deje la UI en blanco.
  String _playerName(String id) => _players
      .firstWhere((p) => p.id == id, orElse: () => Player(id: id, name: id))
      .name
      .split(' ')
      .first;

  /// Devuelve el controller de [key], creándolo con [initial] la primera vez.
  /// En rebuilds posteriores devuelve el mismo, preservando texto y cursor.
  TextEditingController _cfgCtrl(String key, String initial) =>
      _cfgCtrls.putIfAbsent(key, () => TextEditingController(text: initial));

  /// Libera los controllers del sheet. Se llama al abrir uno (para partir de
  /// los valores del módulo que se va a editar) y al cerrarlo.
  void _clearCfgCtrls() {
    for (final c in _cfgCtrls.values) {
      c.dispose();
    }
    _cfgCtrls.clear();
  }

  // ── Campo de golf ──────────────────────────────────────────────────────────
  CourseInfo? _selectedCourse;           // CourseInfo final (con hoyos)
  ApiCourse?  _selectedApiCourse;        // curso API completo (para elegir tees)
  // Corrección pendiente para el campo actualmente seleccionado
  CourseCorrection? _pendingCorrection;
  // ID del campo favorito que se está cargando (null = ninguno)
  String? _loadingFavId;

  // ── Configuración de duración de ronda ────────────────────────────────────
  int _totalHoles = 18;                  // 9 o 18 hoyos

  // ── Cache de presets de apuestas ──────────────────────────────────────────
  List<GamePreset> _presetsCache = [];
  bool _presetsLoading = true;

  // ── Tees y ventajas por jugador ───────────────────────────────────────────
  // playerId → TeeInfo elegido
  final Map<String, TeeInfo> _playerTees = {};
  // playerId → { otroPlayerId → strokes que recibe } (ventaja manual)
  final Map<String, Map<String, double>> _manualHandicaps = {};
  // Mapa canónico de pairSliding: pairKey(a,b) → valor oficial de 18 hoyos
  // (positivo = el jugador con id menor lexicográficamente recibe strokes)
  final Map<String, double> _pairSliding = {};

  // Helper: obtener TeeInfo de un jugador (fallback = estándar)
  TeeInfo _teeOf(String pid) => _playerTees[pid] ?? TeeInfo.standard;

  // Helper: calcular HCP de juego para un jugador dado su tee
  double _playingHcp(Player p) => _teeOf(p.id).playingHandicap(p.handicapBase);

  /// Tee masculino por defecto del campo seleccionado (primer tee masculino).
  /// Retorna null si no hay campo con tees disponibles.
  TeeInfo? get _defaultMaleTee {
    final t = _selectedApiCourse?.maleTees.firstOrNull;
    if (t == null) return null;
    return TeeInfo(name: t.teeName, courseRating: t.courseRating,
        slopeRating: t.slopeRating, parTotal: t.parTotal, gender: 'M');
  }

  /// Busca un tee por nombre en el campo actual (cualquier género).
  /// Retorna null si no existe o no hay campo seleccionado.
  TeeInfo? _teeByName(String teeName) {
    final course = _selectedApiCourse;
    if (course == null) return null;
    for (final t in course.allTees) {
      if (t.teeName.toLowerCase() == teeName.toLowerCase()) {
        final gender = course.femaleTees.any((f) => f.teeName == t.teeName) ? 'F' : 'M';
        return TeeInfo(name: t.teeName, courseRating: t.courseRating,
            slopeRating: t.slopeRating, parTotal: t.parTotal, gender: gender);
      }
    }
    return null;
  }

  /// Auto-asigna el tee a todos los jugadores que aún no tienen tee asignado.
  /// Si se pasa [preferredTeeName], intenta usarlo; si no existe en el campo,
  /// cae al primer tee masculino disponible.
  void _autoAssignDefaultTee({String? preferredTeeName}) {
    final preferred = preferredTeeName != null ? _teeByName(preferredTeeName) : null;
    final def = preferred ?? _defaultMaleTee;
    if (def == null) return;
    for (final p in _players) {
      // Solo asignar si el jugador no tiene tee propio o tiene el estándar
      final current = _playerTees[p.id];
      if (current == null || current.name == TeeInfo.standard.name) {
        _playerTees[p.id] = def;
      }
    }
  }

  /// Asigna el tee por defecto a un jugador recién añadido.
  /// Usa el tee ya asignado a otros jugadores (si todos tienen el mismo) como referencia.
  void _assignDefaultTeeToPlayer(String pid) {
    // Si ya hay jugadores con tee asignado, usar el mismo
    final existing = _playerTees.values
        .where((t) => t.name != TeeInfo.standard.name)
        .toList();
    if (existing.isNotEmpty) {
      _playerTees[pid] = existing.first;
      return;
    }
    final def = _defaultMaleTee;
    if (def == null) return;
    _playerTees[pid] = def;
  }

  /// Aplica el defaultSlidingAdjustment de un PlayerLink al mapa de
  /// manualHandicaps. Se llama al agregar un jugador desde el directorio.
  ///
  /// Convención unificada con _HandicapMatrix, home_screen y scorecard_screen:
  ///   _manualHandicaps[pid][otherId]  =  strokes que pid RECIBE de other  (>0 ventaja para pid)
  ///   _manualHandicaps[otherId][pid]  = -valor  (simétrico)
  ///
  /// defaultSlidingAdjustment en PlayerLink (misma convención):
  ///   > 0 → el usuario RECIBE esos strokes del compañero  (ventaja para el usuario)
  ///   < 0 → el usuario DA esos strokes al compañero       (ventaja para el compañero)
  void _applyDefaultSliding(String newPlayerId, double slidingAdj) {
    if (slidingAdj == 0) return;
    // Aplicar contra todos los jugadores ya en la ronda (excepto el nuevo)
    for (final other in _players) {
      if (other.id == newPlayerId) continue;
      // ── Mantener manualHandicaps para visualización en _HandicapMatrix ──
      _manualHandicaps.putIfAbsent(newPlayerId, () => {});
      _manualHandicaps.putIfAbsent(other.id,    () => {});
      // slidingAdj > 0: newPlayer RECIBE strokes de other
      //   → newPlayer[other] = +slidingAdj  (newPlayer recibe)
      //   → other[newPlayer] = -slidingAdj  (other da)
      // slidingAdj < 0: newPlayer DA strokes a other
      //   → newPlayer[other] = slidingAdj   (newPlayer da, negativo)
      //   → other[newPlayer] = -slidingAdj  (other recibe)
      _manualHandicaps[newPlayerId]![other.id] =  slidingAdj;
      _manualHandicaps[other.id]![newPlayerId] = -slidingAdj;
      // ── Escribir UNA sola vez en el mapa canónico ──────────────────────
      // slidingAdj = recv(newPlayerId, other.id)
      // Clave canónica: lowId|highId. Valor = recv(lowId, highId).
      final lowId = newPlayerId.compareTo(other.id) <= 0 ? newPlayerId : other.id;
      final key = BetEngine.pairKey(newPlayerId, other.id);
      _pairSliding[key] = (newPlayerId == lowId) ? slidingAdj : -slidingAdj;
    }
  }

  @override void dispose() { _nameCtrl.dispose(); _clearCfgCtrls(); super.dispose(); }

  @override
  void initState() {
    super.initState();
    // Auto-cargar el jugador propio al abrir la pantalla de setup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoAddMyself();
      _loadPresetsCache();
      _checkCorrectionsForFavCourses();
    });
  }

  /// Al abrir el setup, verifica si algún campo favorito tiene corrección pendiente.
  /// Si encuentra una corrección, la aplica AUTOMÁTICAMENTE en Firestore.
  /// Espera hasta 3 s a que los favoritos se carguen desde Firestore antes de verificar.
  // Con el nuevo diseño, la corrección global se consulta directamente en
  // _selectFavCourseWithFresh cuando el usuario elige un campo.
  // No hay nada que hacer en segundo plano al abrir la pantalla.
  Future<void> _checkCorrectionsForFavCourses() async {
    // No-op: las correcciones se aplican en tiempo real en _selectFavCourseWithFresh.
  }

  /// Carga los presets de apuestas guardados para mostrarlos directamente en el paso 2.
  Future<void> _loadPresetsCache() async {
    try {
      final presets = await FirestoreService.getGamePresets();
      if (mounted) setState(() { _presetsCache = presets; _presetsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _presetsLoading = false);
    }
  }

  /// Agrega automáticamente al usuario como primer jugador si tiene myPlayerId
  void _autoAddMyself() {
    if (!mounted) return;
    final profProv   = context.read<UserProfileProvider>();
    final playerProv = context.read<PlayerProvider>();
    final myPlayerId = profProv.profile?.myPlayerId;
    if (myPlayerId == null) return;

    // No agregar si ya está en la lista
    if (_players.any((p) => p.id == myPlayerId)) return;

    final pwl = playerProv.directory
        .where((p) => p.player.id == myPlayerId)
        .firstOrNull;
    if (pwl == null) return;

    // Crear Player usando el displayName del link si existe
    final player = pwl.player.copyWith(name: pwl.displayName);

    setState(() {
      // Insertar al inicio
      _players.insert(0, player);
      // El usuario propio no suele tener sliding, pero por consistencia lo aplicamos
      final slide = pwl.link?.defaultSlidingAdjustment ?? 0;
      _applyDefaultSliding(player.id, slide);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<RoundProvider>().theme;
    GolfThemeExt.setCurrent(t);
    return Scaffold(
      backgroundColor: t.bg,
      appBar: gAppBar('Nueva Ronda', t, showBack: true, ctx: context),
      body: Column(children: [
        _StepBar(steps: _steps, index: _stepIndex, t: t),
        Expanded(child: IndexedStack(
          index: _stepIndex,
          children: [for (final s in _steps) _widgetFor(s, t)],
        )),
        _bottomBar(context, t),
      ]),
    );
  }

  // ── Bottom navigation bar ─────────────────────────────────────────────────
  Widget _widgetFor(SetupStep s, GolfTheme t) => switch (s) {
        SetupStep.campo => _stepCourse(t),
        SetupStep.jugadores => _stepPlayers(t),
        SetupStep.compiten => _stepCompiten(t),
        SetupStep.bola => _stepBola(t),
        SetupStep.cuenta => _stepCuenta(t),
        SetupStep.apuestas => _stepGroups(t),
        SetupStep.revisar => _stepReview(t),
        // Existen en el enum pero setupSteps todavía no los emite: se
        // construyen en los bloques siguientes. La rama está aquí para que el
        // switch siga siendo exhaustivo, que es lo que obliga a no olvidar
        // ninguno al añadirlo.
        SetupStep.participantes ||
        SetupStep.montos ||
        SetupStep.ventaja =>
          const SizedBox.shrink(),
      };

  Widget _bottomBar(BuildContext ctx, GolfTheme t) {
    final idx = _stepIndex;
    final isLast = idx == _steps.length - 1;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(ctx).padding.bottom + 12),
      decoration: BoxDecoration(color: t.bg, border: Border(top: BorderSide(color: t.divider))),
      child: Row(children: [
        if (idx > 0) ...[
          Expanded(child: GSecButton(
              label: 'Atrás',
              onTap: () => setState(() => _current = _steps[idx - 1]))),
          const SizedBox(width: 12),
        ],
        Expanded(flex: 2, child: GPrimaryButton(
          label: isLast ? '⛳ Iniciar Ronda' : 'Siguiente →',
          onTap: () {
            // Validaciones por paso
            if (_current == SetupStep.cuenta) _sincronizarModulos();
            if (_current == SetupStep.apuestas && _groups.isEmpty) {
              _addDefaultGroup();
            }
            if (!isLast) {
              setState(() => _current = _steps[idx + 1]);
              return;
            }
            _launchRound(ctx);
          },
        )),
      ]),
    );
  }

  void _addDefaultGroup() {
    final allPids = _players.map((p) => p.id).toList();
    // Con 1 o 0 jugadores no se pueden crear módulos de apuesta (nassau requiere 2+)
    // Se crea un grupo vacío solo para seguimiento de scores
    final modules = allPids.length >= 2
        ? [BetModuleInstance.defaultFor(BetModuleType.nassau, allPids, id: 'nassau_default')]
        : <BetModuleInstance>[];
    _groups.add(BetGroup(
      id: _uuid.v4(), name: 'Partida Principal',
      format: PartidaFormat.allInOnePot,
      playerIds: allPids,
      modules: modules,
    ));
  }

  // ── STEP 0: Campo de Golf ─────────────────────────────────────────────────
  Widget _stepCourse(GolfTheme t) {
    final favCourses = context.watch<UserProfileProvider>().favCourses;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Nombre de la ronda ────────────────────────────────────────────
        GCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Nombre de la ronda',
              style: TextStyle(color: t.sub, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            style: TextStyle(color: t.text),
            decoration: InputDecoration(
              hintText: 'Ej: Sábado 9am',
              fillColor: t.surface, filled: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: t.divider)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: t.divider)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: t.primary, width: 2)),
            ),
          ),
        ])),
        const SizedBox(height: 20),

        // ── Campos favoritos (acceso directo) ─────────────────────────────
        if (favCourses.isNotEmpty) ...[
          GSectionHeader(title: 'MIS CAMPOS FAVORITOS'),
          ...favCourses.map((fav) {
            final isSelected = _selectedApiCourse?.id == fav.courseId ||
                (_selectedCourse?.name == fav.fullName && _selectedApiCourse == null);
            final isLoading = _loadingFavId == fav.courseId;
            final teeName = fav.preferredTeeName;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? t.primary.withValues(alpha: 0.08) : t.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? t.primary : t.divider,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Column(children: [
                  // ── Fila info del campo ──────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                    child: Row(children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: isSelected ? t.primary.withValues(alpha: 0.15) : t.surface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isSelected ? Icons.golf_course : Icons.golf_course_outlined,
                          color: isSelected ? t.primary : t.sub,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          fav.displayName,
                          style: TextStyle(
                            color: isSelected ? t.primary : t.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        if (fav.location.isNotEmpty)
                          Text(fav.location, style: TextStyle(color: t.sub, fontSize: 12)),
                        if (teeName != null) ...[
                          const SizedBox(height: 2),
                          Text('Salida: $teeName',
                              style: TextStyle(color: t.accent, fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ])),
                      if (isSelected)
                        Container(
                          width: 24, height: 24,
                          decoration: BoxDecoration(color: t.primary, shape: BoxShape.circle),
                          child: Icon(Icons.check, color: t.onPrimary, size: 14),
                        ),
                    ]),
                  ),
                  // ── Divisor ──────────────────────────────────────────
                  Divider(height: 1, color: isSelected ? t.primary.withValues(alpha: 0.2) : t.divider),
                  // ── Botón de acción ──────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: isLoading
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              SizedBox(width: 14, height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: t.primary)),
                              const SizedBox(width: 10),
                              Text('Cargando datos del campo…',
                                  style: TextStyle(color: t.primary, fontSize: 13)),
                            ]),
                          )
                        : isSelected
                            ? TextButton.icon(
                                onPressed: () => setState(() {
                                  _selectedCourse = null;
                                  _selectedApiCourse = null;
                                  _playerTees.clear();
                                }),
                                icon: Icon(Icons.close, size: 16, color: t.sub),
                                label: Text('Quitar selección',
                                    style: TextStyle(color: t.sub, fontSize: 13)),
                              )
                            : TextButton.icon(
                                onPressed: () => _selectFavCourseWithFresh(fav),
                                icon: Icon(Icons.sports_golf, size: 16, color: t.primary),
                                label: Text('Jugar en este campo',
                                    style: TextStyle(
                                      color: t.primary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    )),
                              ),
                  ),
                ]),
              ),
            );
          }),
          const SizedBox(height: 4),
        ],



        // ── Campo seleccionado manualmente (no favorito) ──────────────────
        if (_selectedCourse != null &&
            !favCourses.any((f) =>
                f.courseId == _selectedApiCourse?.id ||
                (_selectedApiCourse == null && f.fullName == _selectedCourse!.name))) ...[
          GSectionHeader(title: 'CAMPO SELECCIONADO'),
          GCard(child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: t.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.golf_course, color: t.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_selectedCourse!.name, style: TextStyle(color: t.text, fontWeight: FontWeight.w700)),
              if (_selectedApiCourse != null)
                Text('${_selectedApiCourse!.allTees.length} salidas', style: TextStyle(color: t.accent, fontSize: 11)),
            ])),
            GestureDetector(
              onTap: () => setState(() {
                _selectedCourse = null;
                _selectedApiCourse = null;
                _playerTees.clear();
              }),
              child: Icon(Icons.close, color: t.sub, size: 18),
            ),
          ])),
          const SizedBox(height: 4),
        ],

        // ── Botón buscar otro campo ───────────────────────────────────────
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _openCoursePicker(t),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.divider),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.search, color: t.sub, size: 18),
              const SizedBox(width: 8),
              Text(
                favCourses.isEmpty ? 'Buscar campo de golf' : 'Buscar otro campo',
                style: TextStyle(color: t.sub, fontWeight: FontWeight.w600),
              ),
            ]),
          ),
        ),

        // ── Sin campo seleccionado: nota informativa ──────────────────────
        if (_selectedCourse == null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.accent.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: t.accent.withValues(alpha: 0.25)),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, color: t.accent, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Si no seleccionas un campo se usará el Campo Estándar. '
                  'Seleccionar un campo permite asignar salidas distintas a cada jugador.',
                  style: TextStyle(color: t.sub, fontSize: 12),
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  // ── STEP 1: Jugadores ─────────────────────────────────────────────────────
  Widget _stepPlayers(GolfTheme t) {
    return Consumer<PlayerProvider>(
      builder: (ctx, playerProv, _) {
        final directory = playerProv.directory;
        final favorites = directory.where((pw) => pw.isFavorite).toList();
        final others    = directory.where((pw) => !pw.isFavorite).toList();

        final hasTees   = _selectedApiCourse != null && _selectedApiCourse!.allTees.isNotEmpty;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Banner: recordatorio de salidas cuando hay campo con tees ──
            if (hasTees && _players.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: t.primary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.primary.withValues(alpha: 0.25)),
                  ),
                  child: Row(children: [
                    Icon(Icons.sports_golf, color: t.primary, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      'Toca el chip de salida de cada jugador para cambiarla. '
                      'El HCP de juego se recalcula automáticamente.',
                      style: TextStyle(color: t.primary, fontSize: 12, fontWeight: FontWeight.w500),
                    )),
                  ]),
                ),
              ),
            // ── Jugadores en la ronda ──────────────────────────────────────
            GSectionHeader(title: 'EN ESTA RONDA (${_players.length}/8)'),
            if (_players.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: t.accent.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.accent.withValues(alpha: 0.2)),
                  ),
                  child: Row(children: [
                    Icon(Icons.touch_app_outlined, color: t.accent, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Toca un jugador abajo para agregarlo', style: TextStyle(color: t.sub, fontSize: 13))),
                  ]),
                ),
              )
            else
              ..._players.asMap().entries.map((e) => _playerRow(e.key, e.value, t)),
            const SizedBox(height: 4),

            // ── Botón agregar jugador nuevo ────────────────────────────────
            if (_players.length < 8)
              GestureDetector(
                onTap: _addPlayer,
                child: Container(
                  height: 44, width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: t.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.primary.withValues(alpha: 0.25)),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.person_add_outlined, color: t.primary, size: 16),
                    const SizedBox(width: 8),
                    Text('Crear jugador nuevo', style: TextStyle(color: t.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                  ]),
                ),
              ),

            // ── Directorio: Favoritos ──────────────────────────────────────
            if (favorites.isNotEmpty) ...[
              GSectionHeader(title: 'JUGADORES FAVORITOS'),
              ...favorites.map((pw) => _directoryPlayerTile(pw, t, playerProv)),
              const SizedBox(height: 8),
            ],

            // ── Directorio: Otros compañeros ──────────────────────────────
            if (others.isNotEmpty) ...[
              GSectionHeader(title: favorites.isEmpty ? 'MIS COMPAÑEROS' : 'OTROS COMPAÑEROS'),
              ...others.map((pw) => _directoryPlayerTile(pw, t, playerProv)),
              const SizedBox(height: 8),
            ],

            if (directory.isEmpty)
              GCard(child: Row(children: [
                Icon(Icons.info_outline, color: t.sub, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text('Agrega compañeros en Ajustes → Compañeros para verlos aquí.', style: TextStyle(color: t.sub, fontSize: 13))),
              ])),

            // ── Ventajas (solo si hay 2+ jugadores) ───────────────────────
            if (_players.length >= 2) ...[
              const SizedBox(height: 12),
              GSectionHeader(title: 'VENTAJAS ENTRE JUGADORES'),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'El sliding guardado por jugador tiene prioridad. '  
                  'Si no hay sliding, se calcula por HCP y salida. '
                  'Toca una celda para ajustar manualmente.',
                  style: TextStyle(color: t.sub, fontSize: 11),
                ),
              ),
              const SizedBox(height: 10),
              _HandicapMatrix(
                players: _players,
                playerTees: _playerTees,
                manualHandicaps: _manualHandicaps,
                playingHcp: _playingHcp,
                onEdit: (p1, p2, val) => setState(() {
                  _manualHandicaps.putIfAbsent(p1, () => {});
                  _manualHandicaps.putIfAbsent(p2, () => {});
                  if (val == null) {
                    _manualHandicaps[p1]!.remove(p2);
                    _manualHandicaps[p2]!.remove(p1);
                  } else {
                    _manualHandicaps[p1]![p2] = val;
                    _manualHandicaps[p2]![p1] = -val;
                  }
                }),
                t: t,
              ),
            ],
          ]),
        );
      },
    );
  }

  /// Fila del directorio: al tocar agrega/quita al jugador de la ronda.
  Widget _directoryPlayerTile(PlayerWithLink pw, GolfTheme t, PlayerProvider playerProv) {
    final inRound = _players.any((p) => p.id == pw.player.id);
    final canAdd  = !inRound && _players.length < 8;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () {
          if (inRound) {
            setState(() => _players.removeWhere((p) => p.id == pw.player.id));
          } else if (canAdd) {
            setState(() {
              var player = pw.player.copyWith(name: pw.displayName);
              if (pw.link?.defaultHandicapOverride != null) {
                player = player.copyWith(handicapBase: pw.link!.defaultHandicapOverride!);
              }
              _players.add(player);
              _assignDefaultTeeToPlayer(player.id);
              // Aplicar el sliding predefinido del compañero.
              // El defaultSlidingAdjustment está guardado desde la perspectiva
              // del usuario dueño del link (Carlos), pero _applyDefaultSliding
              // lo interpreta desde la perspectiva de newPlayerId (el compañero).
              // Por eso se invierte el signo: si Carlos da 9 (-9), Rafa recibe 9 (+9).
              final slide = pw.link?.defaultSlidingAdjustment ?? 0;
              _applyDefaultSliding(player.id, -slide);
            });
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: inRound
                ? t.primary.withValues(alpha: 0.10)
                : (!canAdd && !inRound)
                    ? t.surface.withValues(alpha: 0.5)
                    : pw.player.hasLinkedAccount
                        ? t.primary.withValues(alpha: 0.04)
                        : t.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: inRound
                  ? t.primary
                  : pw.player.hasLinkedAccount && !(!canAdd && !inRound)
                      ? t.primary.withValues(alpha: 0.3)
                      : t.divider,
              width: inRound ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            GAvatar(name: pw.displayName, colorIndex: pw.player.colorIndex, size: 36),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(
                  pw.displayName,
                  style: TextStyle(
                    color: (!canAdd && !inRound) ? t.sub : (inRound ? t.primary : t.text),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                if (pw.isFavorite) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                ],
              ]),
              Row(children: [
                Text(
                  'HCP ${pw.player.handicapBase.toStringAsFixed(1)}'
                  '${pw.link?.defaultSlidingAdjustment != 0 && pw.link != null ? "  ·  slide ${pw.link!.defaultSlidingAdjustment > 0 ? "+" : ""}${pw.link!.defaultSlidingAdjustment.toStringAsFixed(0)}" : ""}',
                  style: TextStyle(color: t.sub, fontSize: 11),
                ),
                if (pw.player.hasLinkedAccount) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: t.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.smartphone_rounded, color: t.primary, size: 9),
                      const SizedBox(width: 2),
                      Text('App', style: TextStyle(color: t.primary, fontSize: 9, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ],
              ]),
            ])),
            // Indicador de estado
            if (inRound)
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(color: t.primary, shape: BoxShape.circle),
                child: Icon(Icons.check, color: t.onPrimary, size: 14),
              )
            else if (!canAdd)
              Icon(Icons.block, color: t.divider, size: 20)
            else
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: t.divider, width: 1.5),
                ),
                child: Icon(Icons.add, color: t.sub, size: 14),
              ),
            // Indicador de vinculación
            if (!pw.player.hasLinkedAccount) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => _showLinkAccountDialog(pw.player, t),
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: t.surface,
                    border: Border.all(color: t.divider),
                  ),
                  child: Icon(Icons.link_rounded, color: t.sub, size: 15),
                ),
              ),
            ] else ...[
              const SizedBox(width: 6),
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: t.primary.withValues(alpha: 0.12),
                  border: Border.all(color: t.primary.withValues(alpha: 0.5), width: 1.5),
                ),
                child: Icon(Icons.smartphone_rounded, color: t.primary, size: 15),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  /// Diálogo para vincular un jugador a una cuenta de usuario
  void _showLinkAccountDialog(Player player, GolfTheme t) {
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> results = [];
    bool loading = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSt) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx2).viewInsets.bottom + 24,
              left: 20, right: 20, top: 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Vincular cuenta', style: TextStyle(color: t.text, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Busca la cuenta del jugador "${player.name}" para que pueda unirse a rondas en vivo',
                style: TextStyle(color: t.sub, fontSize: 12)),
            const SizedBox(height: 16),
            // Buscador
            TextField(
              controller: searchCtrl,
              style: TextStyle(color: t.text),
              decoration: InputDecoration(
                hintText: 'Email o nombre del jugador',
                hintStyle: TextStyle(color: t.sub),
                fillColor: t.surface, filled: true,
                prefixIcon: Icon(Icons.search, color: t.sub, size: 20),
                suffixIcon: loading
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: t.primary)))
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.primary, width: 2)),
              ),
              onChanged: (val) async {
                if (val.length < 3) { setSt(() => results = []); return; }
                setSt(() => loading = true);
                final byEmail = await LiveRoundService.searchUsersByEmail(val);
                final byName  = await LiveRoundService.searchUsersByName(val);
                // Combinar sin duplicados
                final map = <String, Map<String, dynamic>>{};
                for (final u in [...byEmail, ...byName]) {
                  map[u['uid'] as String] = u;
                }
                setSt(() { results = map.values.toList(); loading = false; });
              },
            ),
            const SizedBox(height: 12),
            // Resultados
            ...results.map((user) {
              final uid  = user['uid'] as String;
              final name = user['displayName'] as String? ?? '';
              final email = user['email'] as String? ?? '';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: GAvatar(name: name.isEmpty ? email : name, colorIndex: 0, size: 36),
                title: Text(name, style: TextStyle(color: t.text, fontWeight: FontWeight.w600)),
                subtitle: Text(email, style: TextStyle(color: t.sub, fontSize: 11)),
                trailing: TextButton(
                  onPressed: () async {
                    await LiveRoundService.linkPlayerToUser(
                        playerId: player.id, targetUid: uid);
                    // Actualizar el jugador en la lista local
                    setState(() {
                      final idx = _players.indexWhere((p) => p.id == player.id);
                      if (idx >= 0) {
                        _players[idx] = _players[idx].copyWith(linkedUserId: uid);
                      }
                    });
                    if (ctx2.mounted) Navigator.pop(ctx2);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('${player.name} vinculado a $name'),
                        backgroundColor: t.primary,
                      ));
                    }
                  },
                  child: Text('Vincular', style: TextStyle(color: t.primary, fontWeight: FontWeight.w700)),
                ),
              );
            }),
            if (results.isEmpty && searchCtrl.text.length >= 3 && !loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(child: Text('No se encontraron usuarios', style: TextStyle(color: t.sub))),
              ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }
  Widget _playerRow(int i, Player p, GolfTheme t) {
    final hasTees    = _selectedApiCourse != null && _selectedApiCourse!.allTees.isNotEmpty;
    final tee        = _teeOf(p.id);
    final phcp       = _playingHcp(p);
    final isStdTee   = tee.name == TeeInfo.standard.name;
    final teeColor   = tee.gender == 'F' ? t.accent : t.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Fila superior: avatar + nombre + acciones
        Row(children: [
          GAvatar(name: p.name, colorIndex: p.colorIndex),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, style: TextStyle(color: t.text, fontWeight: FontWeight.w700)),
            Text('HCP Index ${p.handicapBase.toStringAsFixed(1)}', style: TextStyle(color: t.sub, fontSize: 12)),
          ])),
          GestureDetector(onTap: () => _editPlayer(i, p, t), child: Icon(Icons.edit_outlined, color: t.sub, size: 18)),
          const SizedBox(width: 8),
          GestureDetector(onTap: () => setState(() => _players.removeAt(i)), child: Icon(Icons.delete_outline, color: t.danger.withValues(alpha: 0.7), size: 18)),
        ]),
        // Selector de tee prominente (solo cuando hay campo con tees)
        if (hasTees) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _pickTee(p, t),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isStdTee
                    ? t.accent.withValues(alpha: 0.06)
                    : teeColor.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isStdTee
                      ? t.accent.withValues(alpha: 0.3)
                      : teeColor.withValues(alpha: 0.4),
                  width: 1.2,
                ),
              ),
              child: Row(children: [
                Icon(Icons.flag, color: isStdTee ? t.accent : teeColor, size: 14),
                const SizedBox(width: 6),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    'Salida: ${tee.name}${tee.gender == "F" ? " (F)" : tee.gender == "M" ? " (M)" : ""}',
                    style: TextStyle(
                      color: isStdTee ? t.accent : teeColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (!isStdTee)
                    Text(
                      'CR ${tee.courseRating.toStringAsFixed(1)}  ·  Slope ${tee.slopeRating}  ·  Par ${tee.parTotal}',
                      style: TextStyle(color: t.sub, fontSize: 10),
                    ),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: isStdTee
                        ? t.accent.withValues(alpha: 0.12)
                        : teeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'HCPj ${phcp.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: isStdTee ? t.accent : teeColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.expand_more, color: t.sub, size: 16),
              ]),
            ),
          ),
        ],
      ])),
    );
  }

  /// Bottom sheet compacto para elegir el tee de un jugador sin abrir el modal completo.
  void _pickTee(Player p, GolfTheme t) {
    if (_selectedApiCourse == null) return;
    TeeInfo selected = _teeOf(p.id);

    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setSt) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header
            Row(children: [
              GAvatar(name: p.name, colorIndex: p.colorIndex, size: 32),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 15)),
                Text('HCP Index ${p.handicapBase.toStringAsFixed(1)}', style: TextStyle(color: t.sub, fontSize: 11)),
              ])),
              IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: Icon(Icons.close, color: t.sub, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
            const SizedBox(height: 16),

            // Tees masculinos
            if ((_selectedApiCourse?.maleTees ?? []).isNotEmpty) ...[
              Text('SALIDAS MASCULINAS', style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const SizedBox(height: 8),
              ..._selectedApiCourse!.maleTees.map((tee) {
                final teeInfo = TeeInfo(name: tee.teeName, courseRating: tee.courseRating,
                    slopeRating: tee.slopeRating, parTotal: tee.parTotal, gender: 'M');
                final isSel = selected.key == teeInfo.key;
                final phcp = teeInfo.playingHandicap(p.handicapBase);
                return GestureDetector(
                  onTap: () {
                    setSt(() => selected = teeInfo);
                    setState(() => _playerTees[p.id] = teeInfo);
                    Navigator.pop(ctx);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSel ? t.primary.withValues(alpha: 0.1) : t.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isSel ? t.primary : t.divider, width: isSel ? 1.5 : 1),
                    ),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tee.teeName, style: TextStyle(color: isSel ? t.primary : t.text, fontWeight: FontWeight.w700, fontSize: 14)),
                        Text('CR ${tee.courseRating.toStringAsFixed(1)}  ·  Slope ${tee.slopeRating}  ·  Par ${tee.parTotal}',
                            style: TextStyle(color: isSel ? t.primary.withValues(alpha: 0.7) : t.sub, fontSize: 11)),
                      ])),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSel ? t.primary.withValues(alpha: 0.15) : t.card,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('HCPj ${phcp.toStringAsFixed(0)}',
                            style: TextStyle(color: isSel ? t.primary : t.sub,
                                fontWeight: FontWeight.w800, fontSize: 13)),
                      ),
                      if (isSel) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.check_circle, color: t.primary, size: 18),
                      ],
                    ]),
                  ),
                );
              }),
            ],

            // Tees femeninos
            if ((_selectedApiCourse?.femaleTees ?? []).isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('SALIDAS FEMENINAS', style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const SizedBox(height: 8),
              ..._selectedApiCourse!.femaleTees.map((tee) {
                final teeInfo = TeeInfo(name: tee.teeName, courseRating: tee.courseRating,
                    slopeRating: tee.slopeRating, parTotal: tee.parTotal, gender: 'F');
                final isSel = selected.key == teeInfo.key;
                final phcp = teeInfo.playingHandicap(p.handicapBase);
                return GestureDetector(
                  onTap: () {
                    setSt(() => selected = teeInfo);
                    setState(() => _playerTees[p.id] = teeInfo);
                    Navigator.pop(ctx);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSel ? t.accent.withValues(alpha: 0.1) : t.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isSel ? t.accent : t.divider, width: isSel ? 1.5 : 1),
                    ),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tee.teeName, style: TextStyle(color: isSel ? t.accent : t.text, fontWeight: FontWeight.w700, fontSize: 14)),
                        Text('CR ${tee.courseRating.toStringAsFixed(1)}  ·  Slope ${tee.slopeRating}  ·  Par ${tee.parTotal}',
                            style: TextStyle(color: isSel ? t.accent.withValues(alpha: 0.7) : t.sub, fontSize: 11)),
                      ])),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSel ? t.accent.withValues(alpha: 0.15) : t.card,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('HCPj ${phcp.toStringAsFixed(0)}',
                            style: TextStyle(color: isSel ? t.accent : t.sub,
                                fontWeight: FontWeight.w800, fontSize: 13)),
                      ),
                      if (isSel) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.check_circle, color: t.accent, size: 18),
                      ],
                    ]),
                  ),
                );
              }),
            ],
          ]),
        ),
      )),
    );
  }

  void _addPlayer() {
    final newPlayer = Player(id: _uuid.v4(), name: 'Jugador ${_players.length + 1}', colorIndex: _players.length);
    setState(() {
      _players.add(newPlayer);
      _assignDefaultTeeToPlayer(newPlayer.id); // ← asignar tee por defecto
    });
    _editPlayer(_players.length - 1, _players.last, context.read<RoundProvider>().theme);
  }


  void _editPlayer(int idx, Player p, GolfTheme t) {
    final nc = TextEditingController(text: p.name);
    final hc = TextEditingController(text: p.handicapBase.toStringAsFixed(1));
    // Tee actual del jugador
    TeeInfo selectedTee = _teeOf(p.id);
    final availableTees = _selectedApiCourse?.allTees ?? [];

    showModalBottomSheet(context: context, backgroundColor: t.card, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setSt) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx2).viewInsets.bottom + 24, left: 20, right: 20, top: 24),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Jugador', style: TextStyle(color: t.text, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          // Nombre
          TextField(controller: nc, style: TextStyle(color: t.text),
            decoration: InputDecoration(labelText: 'Nombre', fillColor: t.surface, filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.primary, width: 2)),
              labelStyle: TextStyle(color: t.sub))),
          const SizedBox(height: 12),
          // HCP Index
          TextField(controller: hc, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: TextStyle(color: t.text),
            decoration: InputDecoration(labelText: 'HCP Index', fillColor: t.surface, filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.primary, width: 2)),
              labelStyle: TextStyle(color: t.sub),
              helperText: availableTees.isNotEmpty
                  ? 'HCP de juego se calculará según tu salida'
                  : 'Handicap base del jugador',
              helperStyle: TextStyle(color: t.sub, fontSize: 10))),

          // ── Selector de salida (solo si hay campo con tees) ──────────
          if (availableTees.isNotEmpty) ...[
            const SizedBox(height: 16),

            // Sección masculinos
            if ((_selectedApiCourse?.maleTees ?? []).isNotEmpty) ...[
              Text('TEEs MASCULINOS', style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: (_selectedApiCourse!.maleTees).map((tee) {
                final cleanName = tee.teeName;
                // Comparar por key (nombre + género) para evitar falsos positivos
                final thisTeeKey = TeeInfo(name: cleanName, courseRating: tee.courseRating, slopeRating: tee.slopeRating, parTotal: tee.parTotal, gender: 'M').key;
                final isSelected = selectedTee.key == thisTeeKey;
                return GestureDetector(
                  onTap: () => setSt(() => selectedTee = TeeInfo(
                    name: cleanName,
                    courseRating: tee.courseRating,
                    slopeRating: tee.slopeRating,
                    parTotal: tee.parTotal,
                    gender: 'M',
                  )),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: isSelected ? t.primary.withValues(alpha: 0.12) : t.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isSelected ? t.primary : t.divider, width: isSelected ? 1.5 : 1),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(cleanName, style: TextStyle(color: isSelected ? t.primary : t.text, fontWeight: FontWeight.w700, fontSize: 13)),
                      Text('CR ${tee.courseRating.toStringAsFixed(1)} / Slope ${tee.slopeRating}',
                          style: TextStyle(color: isSelected ? t.primary.withValues(alpha: 0.7) : t.sub, fontSize: 10)),
                    ]),
                  ),
                );
              }).toList()),
            ],

            // Sección femeninos
            if ((_selectedApiCourse?.femaleTees ?? []).isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('TEEs FEMENINOS', style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: (_selectedApiCourse!.femaleTees).map((tee) {
                final cleanName = tee.teeName;
                final thisTeeKey = TeeInfo(name: cleanName, courseRating: tee.courseRating, slopeRating: tee.slopeRating, parTotal: tee.parTotal, gender: 'F').key;
                final isSelected = selectedTee.key == thisTeeKey;
                return GestureDetector(
                  onTap: () => setSt(() => selectedTee = TeeInfo(
                    name: cleanName,
                    courseRating: tee.courseRating,
                    slopeRating: tee.slopeRating,
                    parTotal: tee.parTotal,
                    gender: 'F',
                  )),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: isSelected ? t.accent.withValues(alpha: 0.12) : t.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isSelected ? t.accent : t.divider, width: isSelected ? 1.5 : 1),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(cleanName, style: TextStyle(color: isSelected ? t.accent : t.text, fontWeight: FontWeight.w700, fontSize: 13)),
                      Text('CR ${tee.courseRating.toStringAsFixed(1)} / Slope ${tee.slopeRating}',
                          style: TextStyle(color: isSelected ? t.accent.withValues(alpha: 0.7) : t.sub, fontSize: 10)),
                    ]),
                  ),
                );
              }).toList()),
            ],
            // Mostrar HCP de juego calculado
            const SizedBox(height: 10),
            Builder(builder: (_) {
              final hcpIdx = double.tryParse(hc.text) ?? p.handicapBase;
              final phcp = selectedTee.playingHandicap(hcpIdx);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: t.primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(Icons.calculate_outlined, color: t.primary, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'HCP de juego: ',
                    style: TextStyle(color: t.sub, fontSize: 12),
                  ),
                  Text(
                    '${phcp.toStringAsFixed(0)} strokes',
                    style: TextStyle(color: t.primary, fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '(${hcpIdx.toStringAsFixed(1)} × ${selectedTee.slopeRating}/113 + ${(selectedTee.courseRating - selectedTee.parTotal).toStringAsFixed(1)})',
                    style: TextStyle(color: t.sub, fontSize: 9),
                  ),
                ]),
              );
            }),
          ],

          const SizedBox(height: 20),
          GPrimaryButton(label: 'Guardar', onTap: () {
            final newHcp = double.tryParse(hc.text) ?? p.handicapBase;
            setState(() {
              _players[idx] = p.copyWith(
                name: nc.text.trim().isEmpty ? 'Jugador ${idx+1}' : nc.text.trim(),
                handicapBase: newHcp,
              );
              // Guardar tee seleccionado
              _playerTees[p.id] = selectedTee;
              // Recalcular HCPs manuales que dependían de auto
              // (limpiar entradas que eran auto para que se recalculen)
            });
            Navigator.pop(ctx);
          }),
        ])),
      )));
  }

  // ── STEP 2: Partidas y módulos (nuevo) ───────────────────────────────────
  // ── PASO · ¿Qué se cuenta? ────────────────────────────────────────────────
  //
  // Multi-select. Al marcar una apuesta su configuración se despliega DEBAJO,
  // en este paso, no en un cajón de avanzados al final.
  //
  // Criterio de reparto: si hay que preguntárselo al grupo antes de salir al
  // tee, va aquí; si el default sirve el 90% de las veces, va en el detalle.
  // Presiones, carry, penaltis, hoyos elegibles y la tabla de unidades son
  // detalle y NO aparecen aquí.
  Widget _stepCuenta(GolfTheme t) {
    final lados = _ladosProvisionales();
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('¿Qué se cuenta?', style: GolfType.title(t.text)),
      const SizedBox(height: 4),
      // SEÑALIZACIÓN. No es adorno: sustituye un cuestionario previo del tipo
      // "¿algún duelo juega distinto?", que obligaba a anticipar una estructura
      // que el usuario aún no ha visto. Quien no lo necesita lee una línea;
      // quien sí, ya sabe dónde ir y no pierde tiempo forzándolo antes.
      Text('Al elegir una, se abre su configuración debajo. '
          'Los montos y quién juega qué vienen después.',
          style: GolfType.body(t.sub)),
      const SizedBox(height: 16),

      // Atajos: rellenan conteo y partición de golpe. Son un preselector DENTRO
      // del paso, no un modo aparte: después se puede cambiar cualquier cosa.
      Text('ATAJOS', style: GolfType.label(t.sub)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final atajo in _atajos)
          GestureDetector(
            onTap: () => setState(() {
              _conteos
                ..clear()
                ..add(atajo.$2);
              _particion.clear();
              if (atajo.$3 != null) _particion[atajo.$2] = atajo.$3!;
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: t.divider, style: BorderStyle.solid),
              ),
              child: Text(atajo.$1, style: GolfType.body(t.sub)),
            ),
          ),
      ]),
      const SizedBox(height: 16),

      for (final cuenta in BetCount.values) ..._fichaConteo(t, cuenta, lados),
      const SizedBox(height: 8),
      if (_conteos.isEmpty)
        Text('Elige al menos una para continuar.', style: GolfType.label(t.sub)),
    ]);
  }

  /// Atajos del paso: (etiqueta, conteo, partición que fijan).
  static const _atajos = <(String, BetCount, BetDivision?)>[
    ('Nassau', BetCount.puntos, BetDivision.frontBackTotal),
    ('Skins', BetCount.skins, null),
    ('Medal', BetCount.scoreTotal, null),
    ('Unidades', BetCount.unidades, null),
  ];

  /// Lados provisionales para consultar el traductor y para que el módulo nazca
  /// ya con equipos. null en individual.
  List<BetSide>? _ladosProvisionales() {
    if (!_porEquipos || _teamA.isEmpty || _teamB.isEmpty) return null;
    final modo = BetRecipe.playModeDe(_bola ?? TeamBall.mejor);
    return [
      BetSide(id: 'lado_A', name: 'Equipo A',
          playerIds: List.of(_teamA), playMode: modo),
      BetSide(id: 'lado_B', name: 'Equipo B',
          playerIds: List.of(_teamB), playMode: modo),
    ];
  }

  List<Widget> _fichaConteo(GolfTheme t, BetCount cuenta, List<BetSide>? lados) {
    final pids = _players.map((p) => p.id).toList();
    final res = BetRecipe.build(
      cuenta: cuenta, bola: _bola, participantIds: pids,
      holesInRound: _totalHoles, sides: lados,
      preferida: _particion[cuenta],
    );
    // Las combinaciones incoherentes no se prohíben con un error: no se
    // ofrecen, y la opción atenuada dice el motivo.
    final ofrecible = res.ok;
    final marcada = _conteos.contains(cuenta);

    return [
      GestureDetector(
        onTap: ofrecible
            ? () => setState(() {
                  if (!_conteos.remove(cuenta)) _conteos.add(cuenta);
                })
            : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: !ofrecible
                ? t.surface
                : marcada
                    ? t.primary.withValues(alpha: 0.08)
                    : t.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: marcada && ofrecible ? t.primary : t.divider,
                width: marcada && ofrecible ? 1.5 : 1),
          ),
          child: Opacity(
            opacity: ofrecible ? 1 : 0.55,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(cuenta.labelCon(_bola),
                        style: GolfType.body(t.text)
                            .copyWith(fontWeight: FontWeight.w600)),
                    if (!ofrecible) ...[
                      const SizedBox(height: 3),
                      Text('No aplica · ${res.rechazo}',
                          style: GolfType.label(t.danger)),
                    ],
                  ])),
              if (ofrecible)
                Icon(
                    marcada
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    color: marcada ? t.primary : t.divider,
                    size: 22),
            ]),
          ),
        ),
      ),
      if (marcada && ofrecible) _configDeConteo(t, cuenta, lados),
    ];
  }

  /// Lo que hay que pactar con el grupo antes del primer tee. Nada más.
  Widget _configDeConteo(GolfTheme t, BetCount cuenta, List<BetSide>? lados) {
    final div = BetRecipe.divisionDe(cuenta,
        bola: _bola, holesInRound: _totalHoles, preferida: _particion[cuenta]);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.primary.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Partición ────────────────────────────────────────────────────────
        //
        // Solo cuando hay dos caminos reales. Cuando el sistema ya sabe la
        // respuesta se ENUNCIA, no se ofrece: un control con una sola opción
        // enseña a pulsar sin leer.
        if (div.hayEleccion) ...[
          Text('¿SE PARTE EN VARIAS APUESTAS?', style: GolfType.label(t.primary)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [
            for (final d in div.disponibles)
              GestureDetector(
                onTap: () => setState(() => _particion[cuenta] = d),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: div.elegida == d
                        ? t.primary.withValues(alpha: 0.12)
                        : t.card,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: div.elegida == d ? t.primary : t.divider,
                        width: div.elegida == d ? 1.5 : 1),
                  ),
                  child: Text(_labelDivision(d),
                      style: GolfType.label(
                          div.elegida == d ? t.primary : t.text)),
                ),
              ),
          ]),
        ] else
          Text(div.explicacion!, style: GolfType.label(t.sub)),

        // ── Cómo se cobra ────────────────────────────────────────────────────
        //
        // Solo donde el motor lee formatMode. En Unidades se dice que no aplica
        // en vez de ofrecer un control que no haría nada.
        const SizedBox(height: 10),
        Text('CÓMO SE COBRA', style: GolfType.label(t.primary)),
        const SizedBox(height: 6),
        if (cuenta.admiteBote)
          Wrap(spacing: 6, children: [
            for (final m in BetFormatMode.values)
              GestureDetector(
                onTap: () => setState(() => _reparto[cuenta] = m),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: (_reparto[cuenta] ?? BetFormatMode.allVsAll) == m
                        ? t.primary.withValues(alpha: 0.12)
                        : t.card,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: (_reparto[cuenta] ?? BetFormatMode.allVsAll) == m
                            ? t.primary
                            : t.divider),
                  ),
                  child: Text(
                      m == BetFormatMode.onePot
                          ? 'Un solo bote'
                          : 'Uno contra uno',
                      style: GolfType.label(t.text)),
                ),
              ),
          ])
        else
          Text('Uno contra uno · ${cuenta.sinBote}',
              style: GolfType.label(t.sub)),
      ]),
    );
  }

  String _labelDivision(BetDivision d) => switch (d) {
        BetDivision.unaSolaApuesta => 'Una sola apuesta',
        BetDivision.frontBackTotal => 'Front · Back · Total',
      };

  /// Materializa los conteos elegidos como módulos de apuesta.
  ///
  /// Los módulos del flujo llevan un id con prefijo para poder reemplazarlos
  /// sin tocar los que el usuario haya creado a mano en el paso de detalle: si
  /// se borrara todo y se reconstruyera, volver atrás a cambiar una casilla
  /// perdería su trabajo.
  void _sincronizarModulos() {
    final pids = _players.map((p) => p.id).toList();
    if (pids.length < 2) return;
    final lados = _ladosProvisionales();

    final delFlujo = <BetModuleInstance>[];
    for (final cuenta in _conteos) {
      final res = BetRecipe.build(
        cuenta: cuenta, bola: _bola, participantIds: pids,
        holesInRound: _totalHoles, sides: lados,
        preferida: _particion[cuenta],
        id: 'flujo_${cuenta.name}',
      );
      if (!res.ok) continue; // se rechazó: no se ofrecía, no hay nada que crear
      var m = res.module!;
      final rep = _reparto[cuenta];
      if (rep != null && cuenta.admiteBote) m = m.copyWith(formatMode: rep);
      delFlujo.add(m);
    }

    if (_groups.isEmpty) {
      _groups.add(BetGroup(
        id: _uuid.v4(), name: 'Partida Principal',
        format: PartidaFormat.allInOnePot,
        playerIds: pids, modules: delFlujo,
      ));
      return;
    }
    final g = _groups.first;
    final ajenos =
        g.modules.where((m) => !m.id.startsWith('flujo_')).toList();
    _groups[0] = g.copyWith(modules: [...ajenos, ...delFlujo]);
  }

  // ── PASO · ¿Quiénes compiten? ─────────────────────────────────────────────
  //
  // Define cuántos LADOS hay. Un lado es un jugador o un equipo, así que
  // individual y equipos no son dos casos: son el mismo con distinto número de
  // lados. De ahí salen los enfrentamientos, y de los enfrentamientos los
  // montos.
  Widget _stepCompiten(GolfTheme t) {
    final n = _players.length;
    final cruces = n * (n - 1) ~/ 2;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('¿Quiénes compiten?', style: GolfType.title(t.text)),
      const SizedBox(height: 4),
      Text('Define cuántos lados hay, y con ellos cuántos enfrentamientos.',
          style: GolfType.body(t.sub)),
      const SizedBox(height: 16),
      _opcionCompiten(t,
          icon: '👤',
          titulo: 'Cada quien por su cuenta',
          detalle: '$n lados · $cruces enfrentamiento${cruces == 1 ? '' : 's'}.',
          activa: !_porEquipos,
          onTap: () => setState(() {
                _porEquipos = false;
                _bola = null; // la bola no aplica sin equipos
              })),
      _opcionCompiten(t,
          icon: '👥',
          titulo: 'Por equipos',
          detalle: '2 lados · 1 enfrentamiento.',
          activa: _porEquipos,
          onTap: () => setState(() {
                _porEquipos = true;
                if (_teamA.isEmpty && _teamB.isEmpty) _repartirEquipos();
              })),
      if (_porEquipos) ...[
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _panelEquipo(t, 'Equipo A', _teamA, 0)),
          const SizedBox(width: 10),
          Expanded(child: _panelEquipo(t, 'Equipo B', _teamB, 1)),
        ]),
        const SizedBox(height: 8),
        Text('Toca un jugador para cambiarlo de lado.',
            style: GolfType.label(t.sub)),
      ],
    ]);
  }

  /// Reparto inicial alternando, para que dos jugadores del mismo nivel no
  /// caigan siempre juntos por el orden en que se capturaron.
  void _repartirEquipos() {
    _teamA.clear();
    _teamB.clear();
    for (var i = 0; i < _players.length; i++) {
      (i.isEven ? _teamA : _teamB).add(_players[i].id);
    }
  }

  Widget _opcionCompiten(GolfTheme t,
      {required String icon,
      required String titulo,
      required String detalle,
      required bool activa,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: activa ? t.primary.withValues(alpha: 0.08) : t.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: activa ? t.primary : t.divider, width: activa ? 1.5 : 1),
        ),
        child: Row(children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 11),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(titulo,
                    style: GolfType.body(t.text)
                        .copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(detalle, style: GolfType.label(t.sub)),
              ])),
          if (activa) Icon(Icons.check_circle, color: t.primary, size: 20),
        ]),
      ),
    );
  }

  Widget _panelEquipo(GolfTheme t, String nombre, List<String> ids, int lado) {
    final color = GAvatar.colorFor(lado == 0 ? 0 : 4);
    return Container(
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(nombre.toUpperCase(), style: GolfType.label(color)),
        const SizedBox(height: 6),
        Wrap(spacing: 5, runSpacing: 5, children: [
          for (final id in ids)
            GestureDetector(
              onTap: () => setState(() {
                (lado == 0 ? _teamA : _teamB).remove(id);
                (lado == 0 ? _teamB : _teamA).add(id);
              }),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: Text(_playerName(id),
                    style: GolfType.label(color)
                        .copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
      ]),
    );
  }

  // ── PASO · ¿Qué bola cuenta? (solo con equipos) ───────────────────────────
  //
  // Determina cuántos puntos reparte cada hoyo, y con ello cómo se llama el
  // conteo: con uno es Match —el marcador se lee "2 UP"—, con dos son Puntos.
  Widget _stepBola(GolfTheme t) {
    final opciones = [
      (TeamBall.mejor, '🏌️', 'La mejor bola',
          'Cuenta el mejor score del equipo en el hoyo.'),
      (TeamBall.mejorYPeor, '⚖️', 'La mejor y la peor',
          'Dos puntos por hoyo: uno por la mejor bola y otro por la peor.'),
      (TeamBall.unaSola, '🎯', 'Una sola bola',
          'El equipo juega un balón y registra un score por hoyo.'),
    ];
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('¿Qué bola cuenta?', style: GolfType.title(t.text)),
      const SizedBox(height: 4),
      Text('Cómo se decide el score del lado en cada hoyo.',
          style: GolfType.body(t.sub)),
      const SizedBox(height: 16),
      for (final (bola, icon, titulo, detalle) in opciones) ...[
        _opcionCompiten(t,
            icon: icon,
            titulo: titulo,
            detalle: detalle,
            activa: _bola == bola,
            onTap: () => setState(() => _bola = bola)),
        // La configuración se despliega DEBAJO de la opción que la abre, no en
        // un cajón de avanzados al final: es una pregunta que hay que hacerle
        // al grupo antes de salir al tee, no un default que sirve el 90%.
        if (bola == TeamBall.unaSola && _bola == TeamBall.unaSola)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.primary.withValues(alpha: 0.4)),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CÓMO SE JUEGA LA BOLA', style: GolfType.label(t.primary)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, children: [
                    for (final m in SingleBallMode.values)
                      GestureDetector(
                        onTap: () => setState(() => _submodo = m),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: _submodo == m
                                ? t.primary.withValues(alpha: 0.12)
                                : t.card,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                                color: _submodo == m ? t.primary : t.divider,
                                width: _submodo == m ? 1.5 : 1),
                          ),
                          child: Text(m.label,
                              style: GolfType.body(
                                      _submodo == m ? t.primary : t.text)
                                  .copyWith(fontWeight: FontWeight.w600)),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  Text(_submodo.description, style: GolfType.label(t.sub)),
                ]),
          ),
      ],
      const SizedBox(height: 8),
      Text(
          'Cada hoyo reparte ${_bola.puntosPorHoyo} '
          'punto${_bola.puntosPorHoyo == 1 ? '' : 's'}.',
          style: GolfType.label(t.sub)),
    ]);
  }

  Widget _stepGroups(GolfTheme t) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Partidas configuradas ─────────────────────────────────────────
        if (_groups.isNotEmpty) ...[
          GSectionHeader(title: 'PARTIDAS CONFIGURADAS'),
          _betsLegend(t),
          ..._groups.asMap().entries.map((e) => _groupCard(e.key, e.value, t)),
          const SizedBox(height: 8),
        ],

        // ── Betting Groups compatibles ────────────────────────────────────
        if (_players.length >= 2) ...[
          _BettingGroupsBanner(
            presentIds: _players.map((p) => p.id).toSet(),
            onApply:    (BettingGroup bg) => _applyBettingGroup(bg),
            t:          t,
          ),
          const SizedBox(height: 16),
        ],

        // ── Apuestas guardadas (acceso directo) ───────────────────────────
        GSectionHeader(title: 'CONFIGURACIONES GUARDADAS'),
        if (_presetsLoading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(color: t.primary, strokeWidth: 2)),
          )
        else if (_presetsCache.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GCard(child: Row(children: [
              Icon(Icons.info_outline, color: t.sub, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(
                'Sin configuraciones guardadas. Ve a Ajustes → Mis Configuraciones para crear una.',
                style: TextStyle(color: t.sub, fontSize: 13),
              )),
            ])),
          )
        else
          ..._presetsCache.map((preset) {
            final alreadyApplied = _groups.any((g) => g.name == preset.name);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: alreadyApplied ? null : () => _applyPresetDirect(preset, t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: alreadyApplied
                        ? t.primary.withValues(alpha: 0.06)
                        : t.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: alreadyApplied ? t.primary.withValues(alpha: 0.4) : t.divider,
                      width: alreadyApplied ? 1.5 : 1,
                    ),
                  ),
                  child: Row(children: [
                    Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: alreadyApplied
                            ? t.primary.withValues(alpha: 0.12)
                            : t.surface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(child: Text(preset.emoji, style: const TextStyle(fontSize: 20))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        preset.name,
                        style: TextStyle(
                          color: alreadyApplied ? t.primary : t.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      if (preset.description.isNotEmpty)
                        Text(preset.description, style: TextStyle(color: t.sub, fontSize: 12)),
                      Text(
                        '${preset.modulesJson.length} apuesta${preset.modulesJson.length != 1 ? "s" : ""}',
                        style: TextStyle(color: t.accent, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ])),
                    if (alreadyApplied)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: t.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('Aplicada', style: TextStyle(color: t.primary, fontSize: 11, fontWeight: FontWeight.w700)),
                      )
                    else
                      Icon(Icons.add_circle_outline, color: t.primary, size: 22),
                  ]),
                ),
              ),
            );
          }),

        const SizedBox(height: 8),

        // ── Botón agregar partida nueva manualmente ───────────────────────
        GestureDetector(
          onTap: () => _addGroup(t),
          child: Container(
            height: 48, width: double.infinity,
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.divider),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.tune, color: t.sub, size: 16),
              const SizedBox(width: 8),
              Text('Configurar partida manualmente', style: TextStyle(color: t.sub, fontWeight: FontWeight.w600, fontSize: 13)),
            ]),
          ),
        ),

        if (_groups.isEmpty) ...[
          const SizedBox(height: 12),
          GCard(child: Row(children: [
            Icon(Icons.info_outline, color: t.sub, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text('Si no configuras partidas, se creará Nassau \$50/\$50/\$100 automáticamente', style: TextStyle(color: t.sub, fontSize: 13))),
          ])),
        ],
      ]),
    );
  }

  // ── BettingGroup: aplicar automáticamente ────────────────────────────────
  void _applyBettingGroup(BettingGroup bg) {
    final presentIds = _players.map((p) => p.id).toSet();
    // Generar el ID del grupo UNA sola vez para que todos los módulos compartan
    // el mismo betGroupId (evita el bug de doble llamada con UUIDs distintos).
    final bgId    = _uuid.v4();
    final modules = bg.toBetModuleInstances(
      presentIds:   presentIds,
      betGroupId:   bgId,
      betGroupName: bg.name,
    );
    if (modules.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No hay duelos activos para los jugadores seleccionados'),
      ));
      return;
    }
    final newGroup = BetGroup(
      id:        bgId,
      name:      bg.name,
      format:    PartidaFormat.allInOnePot,
      playerIds: presentIds.toList(),
      modules:   modules,
    );
    setState(() => _groups.add(newGroup));
  }

  /// Aplica un preset directamente sin sheet intermedio (usa todos los jugadores del grupo).
  void _applyPresetDirect(GamePreset preset, GolfTheme t) {
    final allPids = _players.map((p) => p.id).toList();
    if (allPids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: t.danger,
        content: const Text('Agrega jugadores primero'),
      ));
      return;
    }
    // apply() y no toModules(): además de las reglas del grupo instancia los
    // acuerdos por pareja y los reconcilia entre sí, de modo que una pareja con
    // importe propio no acabe con dos apuestas del mismo tipo.
    final application = preset.apply(allPids, () => _uuid.v4());

    final group = BetGroup(
      id: _uuid.v4(),
      name: preset.name,
      format: PartidaFormat.allInOnePot,
      playerIds: allPids,
      modules: application.modules,
    );
    setState(() => _groups.add(group));
    // Incrementar contador de uso del preset
    FirestoreService.saveGamePreset(preset.copyWith(useCount: preset.useCount + 1));

    // Lo que no se pudo aplicar NO está en la partida, así que hay que decirlo:
    // callar dejaría al usuario creyendo que juega algo que no está configurado.
    if (application.hasConflicts) {
      _showConflicts(application.conflicts, t);
    }
  }

  /// Guarda la partida ya configurada como juego reutilizable.
  ///
  /// Es la otra mitad de [_applyPresetDirect]: aquí se aprende lo que allí se
  /// aplica. El usuario configura como siempre y decide recordarlo al final,
  /// sin declarar nada por adelantado.
  ///
  /// Lo que se guarda no son los módulos tal cual, sino su reparto en reglas de
  /// grupo y acuerdos por pareja — ver [PairAgreementEngine.capture]. Eso es lo
  /// que permite que el martes y el viernes tengan apuestas distintas entre las
  /// mismas personas.
  void _saveGroupAsGame(BetGroup g, GolfTheme t) {
    final capture = PairAgreementEngine.capture(
      modules: g.modules,
      playerIds: g.playerIds,
    );

    if (capture.groupRules.isEmpty && capture.pairAgreements.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: t.danger,
        content: const Text('No hay apuestas que se puedan guardar'),
      ));
      return;
    }

    final nameCtrl = TextEditingController(text: g.name);
    var emoji = '⛳️';
    const emojis = ['⛳️', '🌮', '🍻', '🔥', '🏆', '💰', '🌅', '🎯'];

    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSt) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx2).viewInsets.bottom + 24,
              left: 20,
              right: 20,
              top: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Guardar como juego',
                  style: TextStyle(
                      color: t.text, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                'La próxima vez lo cargas de un toque, con estos jugadores y '
                'lo que cada pareja acordó.',
                style: TextStyle(color: t.sub, fontSize: 12, height: 1.35),
              ),
              const SizedBox(height: 18),

              // ── Nombre ────────────────────────────────────────────────────
              TextField(
                controller: nameCtrl,
                style: TextStyle(color: t.text),
                decoration: InputDecoration(
                  labelText: 'Nombre del juego',
                  hintText: 'Martes, Viernes, Torneo…',
                  labelStyle: TextStyle(color: t.sub),
                  hintStyle: TextStyle(color: t.sub.withValues(alpha: 0.5)),
                  fillColor: t.surface,
                  filled: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: t.divider)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: t.divider)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: t.primary, width: 2)),
                ),
              ),
              const SizedBox(height: 14),

              // ── Emoji ─────────────────────────────────────────────────────
              Text('ICONO',
                  style: TextStyle(
                      color: t.sub, fontSize: 11, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: emojis.map((e) {
                  final sel = e == emoji;
                  return GestureDetector(
                    onTap: () => setSt(() => emoji = e),
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: sel ? t.primary.withValues(alpha: 0.14) : t.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: sel ? t.primary : t.divider,
                            width: sel ? 1.5 : 1),
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 18)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),

              // ── Qué se va a guardar ───────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: t.divider),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _saveSummaryRow(
                        Icons.groups_outlined,
                        '${capture.groupRules.length} '
                            'apuesta${capture.groupRules.length == 1 ? "" : "s"} '
                            'de todo el grupo',
                        t,
                      ),
                      if (capture.pairAgreements.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _saveSummaryRow(
                          Icons.compare_arrows,
                          '${capture.pairAgreements.length} '
                              'acuerdo${capture.pairAgreements.length == 1 ? "" : "s"} '
                              'por pareja',
                          t,
                        ),
                      ],
                      const SizedBox(height: 8),
                      _saveSummaryRow(
                        Icons.person_outline,
                        '${g.playerIds.length} jugadores',
                        t,
                      ),
                    ]),
              ),

              // Lo que NO se puede guardar se dice antes de guardar, no después.
              if (!capture.isComplete) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: t.accent.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: t.accent.withValues(alpha: 0.25)),
                  ),
                  child: Row(children: [
                    Icon(Icons.info_outline, color: t.accent, size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${capture.notCaptured.length} '
                        'apuesta${capture.notCaptured.length == 1 ? "" : "s"} no '
                        'se guardará${capture.notCaptured.length == 1 ? "" : "n"}: '
                        'las de equipos y las de un subgrupo dependen de quién '
                        'juega hoy, así que no se pueden reutilizar tal cual.',
                        style: TextStyle(
                            color: t.accent, fontSize: 11, height: 1.35),
                      ),
                    ),
                  ]),
                ),
              ],

              const SizedBox(height: 20),
              GPrimaryButton(
                label: 'Guardar juego',
                onTap: () async {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(ctx2);

                  final preset = GamePreset.fromCapture(
                    id: '',
                    name: name,
                    emoji: emoji,
                    capture: capture,
                    playerIds: List<String>.from(g.playerIds),
                  );
                  try {
                    await FirestoreService.saveGamePreset(preset);
                    if (!mounted) return;
                    await _loadPresetsCache(); // que aparezca ya en la lista
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      backgroundColor: t.primary,
                      content: Text('$emoji  $name guardado'),
                    ));
                  } catch (e) {
                    if (kDebugMode) debugPrint('[_saveGroupAsGame] $e');
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      backgroundColor: t.danger,
                      content: const Text('No se pudo guardar el juego'),
                    ));
                  }
                },
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(nameCtrl.dispose);
  }

  Widget _saveSummaryRow(IconData icon, String text, GolfTheme t) =>
      Row(children: [
        Icon(icon, color: t.sub, size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: t.text, fontSize: 12)),
        ),
      ]);

  /// Avisa de los acuerdos que no se pudieron aplicar sobre las reglas del
  /// juego. No es un error del usuario: es una combinación que el modelo no
  /// puede representar sin cambiar el significado de la apuesta.
  void _showConflicts(List<PresetConflict> conflicts, GolfTheme t) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.card,
        title: Row(children: [
          Icon(Icons.warning_amber_rounded, color: t.accent, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Se aplicó parcialmente',
                style: TextStyle(
                    color: t.text, fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              conflicts.length == 1
                  ? 'Un acuerdo quedó fuera de la partida:'
                  : '${conflicts.length} acuerdos quedaron fuera de la partida:',
              style: TextStyle(color: t.sub, fontSize: 12),
            ),
            const SizedBox(height: 12),
            ...conflicts.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_playerName(c.p1Id)} vs ${_playerName(c.p2Id)} · ${c.type.label}',
                          style: TextStyle(
                              color: t.text,
                              fontSize: 13,
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(c.reason,
                            style: TextStyle(
                                color: t.sub, fontSize: 11, height: 1.35)),
                      ]),
                )),
            Text(
              'Puedes configurarlo a mano en la partida.',
              style: TextStyle(
                  color: t.sub, fontSize: 11, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Entendido', style: TextStyle(color: t.primary)),
          ),
        ],
      ),
    );
  }

  /// Leyenda que explica cómo leer la lista de apuestas.
  ///
  /// Las tarjetas agrupan apuestas idénticas, así que "1 apuesta ×6" no es
  /// obvio a primera vista; y el alta de jugador con un icono solo pasaba
  /// desapercibida.
  Widget _betsLegend(GolfTheme t) {
    Widget linea(IconData icon, String titulo, String detalle) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              margin: const EdgeInsets.only(top: 1),
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: t.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, color: t.primary, size: 13),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titulo,
                    style: TextStyle(
                        color: t.text, fontWeight: FontWeight.w700, fontSize: 12)),
                Text(detalle,
                    style: TextStyle(color: t.sub, fontSize: 11, height: 1.3)),
              ]),
            ),
          ]),
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 5),
      decoration: BoxDecoration(
        color: t.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.primary.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.lightbulb_outline, color: t.primary, size: 15),
          const SizedBox(width: 6),
          Text('Cómo leer esta lista',
              style: TextStyle(
                  color: t.primary, fontWeight: FontWeight.w800, fontSize: 12.5)),
        ]),
        const SizedBox(height: 10),
        linea(Icons.layers_outlined, 'Una tarjeta = una apuesta',
            'Las apuestas iguales se agrupan. "×6" significa que ese mismo '
            'acuerdo corre en 6 duelos.'),
        linea(Icons.call_split, 'Lo distinto se separa solo',
            'Si un duelo tiene otro importe, aparece en su propia tarjeta.'),
        linea(Icons.person_add_alt_1, 'Puedes meter jugadores a cada apuesta',
            'El botón verde con el número indica cuántos jugadores de la '
            'partida aún NO juegan esa apuesta. Tócalo para añadirlos.'),
      ]),
    );
  }

  Widget _groupCard(int idx, BetGroup g, GolfTheme t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ────────────────────────────────────────────────────────
        Row(children: [
          Expanded(child: Text(g.name, style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 16))),
          if (g.modules.isNotEmpty) ...[
            GestureDetector(
              onTap: () => _saveGroupAsGame(g, t),
              child: Icon(Icons.bookmark_add_outlined, color: t.sub, size: 18),
            ),
            const SizedBox(width: 14),
          ],
          GestureDetector(onTap: () => setState(() => _groups.removeAt(idx)), child: Icon(Icons.close, color: t.sub, size: 18)),
        ]),
        const SizedBox(height: 4),
        Text('${g.playerIds.length} jugadores', style: TextStyle(color: t.sub, fontSize: 12)),
        const SizedBox(height: 12),
        const GDivider(),
        const SizedBox(height: 10),

        // ── Instancias de módulo ──────────────────────────────────────────
        if (g.modules.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: t.accent.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.accent.withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                Icon(Icons.info_outline, color: t.accent, size: 14),
                const SizedBox(width: 8),
                Expanded(child: Text('Sin módulos. Toca + para agregar una apuesta.', style: TextStyle(color: t.sub, fontSize: 12))),
              ]),
            ),
          ),

        ..._renderModules(idx, g, t),
        const SizedBox(height: 8),

        // ── Botón agregar módulo ──────────────────────────────────────────
        GestureDetector(
          onTap: () => _addModule(idx, g, t),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: t.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: t.primary.withValues(alpha: 0.2)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add, color: t.primary, size: 16),
              const SizedBox(width: 6),
              Text('Agregar apuesta', style: TextStyle(color: t.primary, fontWeight: FontWeight.w600, fontSize: 13)),
            ]),
          ),
        ),
      ])),
    );
  }

  Widget _moduleTile(int groupIdx, int modIdx, BetModuleInstance mod, BetGroup g, GolfTheme t) {
    final pCount = mod.participantIds.isEmpty ? g.playerIds.length : mod.participantIds.length;
    // Familia de un solo módulo: se reutiliza la misma lógica de alta que en
    // las tarjetas agrupadas.
    final familiaUnica = [MapEntry(modIdx, mod)];
    final faltantes = mod.participantIds.isEmpty
        ? const <Player>[]   // ya cubre a toda la partida
        : _playersMissingFrom(familiaUnica, g);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.divider),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Fila header del módulo ────────────────────────────────────
          Row(children: [
            Text(mod.type.icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(mod.name, style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 14)),
              Text(mod.summaryLabel, style: TextStyle(color: t.sub, fontSize: 11)),
            ])),
            // ── Botón editar ────────────────────────────────────────────
            GestureDetector(
              onTap: () {
                // Usamos _openModuleEdit que incluye la sección de equipos
                _openModuleEdit(context, g, mod, t);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: t.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Text('Editar', style: TextStyle(color: t.primary, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () { setState(() {
                final mods = List<BetModuleInstance>.from(_groups[groupIdx].modules)..removeAt(modIdx);
                _groups[groupIdx] = _groups[groupIdx].copyWith(modules: mods);
              }); },
              child: Icon(Icons.close, color: t.sub, size: 16),
            ),
          ]),
          // ── Chips informativos ────────────────────────────────────────
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: [
            _infoChip('$pCount jugadores', t.sub, t),
            if (mod.type == BetModuleType.skins && mod.skins.carryOver)
              _infoChip('🔥 Carry ON', t.accent, t),
            if (mod.type == BetModuleType.nassau && mod.nassau.pressEnabled)
              _infoChip('Press ON', t.accent, t),
            if (mod.type == BetModuleType.matchAutoPress)
              _infoChip('⚡ Auto Press', t.accent, t),

            _infoChip(mod.useHandicap ? 'Net' : 'Gross', t.primary, t),
          ]),

          // ── Alta de jugadores ────────────────────────────────────────────
          if (!mod.hasTeamSides && faltantes.isNotEmpty) ...[
            const SizedBox(height: 10),
            _addPlayersRow(groupIdx, familiaUnica, g, faltantes, t),
          ],
        ]),
      ),
    );
  }

  Widget _infoChip(String label, Color color, GolfTheme t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
  );

  // ── Renderizado agrupado de módulos ──────────────────────────────────────
  /// Agrupa los módulos del BetGroup por betGroupId.
  /// - Módulos sin betGroupId (o con betGroupId único): tile individual.
  /// - Módulos que comparten betGroupId: una sola card de familia.
  /// El orden de aparición sigue el orden del primer módulo de cada familia.
  List<Widget> _renderModules(int groupIdx, BetGroup g, GolfTheme t) {
    final modules = g.modules;

    // ── Agrupar por CONFIGURACIÓN, no por par ────────────────────────────────
    //
    // Antes la clave incluía el betGroupId, que BettingGroup.toBetModuleInstances
    // construye con el id de la PairBetRule. Resultado: cada duelo estrenaba su
    // propia familia y 4 jugadores × 5 tipos daban 30 tarjetas.
    //
    // Ahora la clave es la firma de configuración: seis Nassau de $50 son UNA
    // tarjeta, y si uno está a $100 se separa solo. Los duelos por equipos
    // llevan sus lados en la firma, así que nunca se fusionan entre sí.
    final seen   = <String>{};
    final result = <Widget>[];

    // ── Diagnóstico ──────────────────────────────────────────────────────────
    // Si las tarjetas no colapsan, es porque las firmas difieren. Esto imprime
    // cuántos módulos hay, cuántas familias salen y en qué difieren las firmas.
    if (kDebugMode) {
      final firmas = modules.map((m) => m.configSignature).toSet();
      debugPrint('[Setup] ══ AGRUPACIÓN DE APUESTAS ══');
      debugPrint('[Setup] módulos=${modules.length}  familias=${firmas.length}');
      if (firmas.length > 1) {
        for (final f in firmas) {
          final n = modules.where((m) => m.configSignature == f).length;
          debugPrint('[Setup]   ($n) $f');
        }
      }
    }

    for (int i = 0; i < modules.length; i++) {
      final mod = modules[i];
      final familyKey = mod.configSignature;
      if (seen.contains(familyKey)) continue;
      seen.add(familyKey);

      final family = modules
          .asMap()
          .entries
          .where((e) => e.value.configSignature == familyKey)
          .toList(); // List<MapEntry<int, BetModuleInstance>>

      // Un único módulo → tarjeta simple de siempre. Varios → tarjeta de familia.
      result.add(family.length == 1
          ? _moduleTile(groupIdx, i, mod, g, t)
          : _groupModuleTile(groupIdx, family, g, t));
    }

    return result;
  }

  // ── Card de familia (varios módulos con mismo betGroupId) ────────────────
  // ══════════════════════════════════════════════════════════════════════════
  // ALTA DE JUGADOR EN UNA APUESTA EXISTENTE
  // ══════════════════════════════════════════════════════════════════════════

  /// Jugadores ya cubiertos por esta familia de apuestas.
  Set<String> _familyCoverage(List<MapEntry<int, BetModuleInstance>> family) =>
      {for (final e in family) ...e.value.participantIds};

  /// Jugadores de la partida que aún NO juegan esta apuesta.
  List<Player> _playersMissingFrom(
      List<MapEntry<int, BetModuleInstance>> family, BetGroup g) {
    final cubiertos = _familyCoverage(family);
    return _players
        .where((p) => g.playerIds.contains(p.id))
        .where((p) => !cubiertos.contains(p.id))
        .toList();
  }

  /// Mete a [newPid] en la apuesta que representa [family], clonando su config.
  ///
  /// • Familia de duelos 1v1 → crea un duelo nuevo contra CADA jugador ya
  ///   cubierto, con la misma configuración.
  /// • Módulo de grupo (3+ o sin participantes) → lo añade a participantIds.
  ///
  /// Los duelos por equipos no pasan por aquí: el botón no se ofrece, porque
  /// meter a alguien exige decidir en qué lado va.
  void _addPlayerToFamily(
    int groupIdx,
    List<MapEntry<int, BetModuleInstance>> family,
    String newPid,
    GolfTheme t,
  ) {
    final g       = _groups[groupIdx];
    final plantilla = family.first.value;
    final mods    = List<BetModuleInstance>.from(g.modules);

    final esDuelos = family.every((e) => e.value.participantIds.length == 2);

    if (esDuelos) {
      final rivales = _familyCoverage(family).where((id) => id != newPid).toList();
      for (final rival in rivales) {
        mods.add(plantilla.copyForPair(_uuid.v4(), rival, newPid));
      }
    } else {
      // Módulo de grupo: basta con sumarlo a los participantes
      for (final e in family) {
        final actual = e.value.participantIds;
        if (actual.contains(newPid)) continue;
        final nuevos = [...actual, newPid];
        mods[e.key] = e.value.copyWith(
          participantIds: nuevos,
          scope: BetScope.subset(nuevos),
        );
      }
    }

    setState(() => _groups[groupIdx] = g.copyWith(modules: mods));

    final nombre = _players
        .firstWhere((p) => p.id == newPid, orElse: () => Player(id: newPid, name: newPid))
        .name;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: t.primary,
      content: Text('$nombre entra en ${plantilla.type.label}'),
    ));
  }

  /// Hoja para elegir a quién meter en la apuesta.
  void _pickPlayerForFamily(
    int groupIdx,
    List<MapEntry<int, BetModuleInstance>> family,
    BetGroup g,
    GolfTheme t,
  ) {
    final faltantes = _playersMissingFrom(family, g);
    if (faltantes.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Row(children: [
              Text(family.first.value.type.icon,
                  style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('¿Quién entra en ${family.first.value.type.label}?',
                    style: TextStyle(
                        color: t.text, fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(
              family.every((e) => e.value.participantIds.length == 2)
                  ? 'Se le creará un duelo contra cada jugador que ya la juega.'
                  : 'Se sumará a los participantes de esta apuesta.',
              style: TextStyle(color: t.sub, fontSize: 12),
            ),
          ),
          ...faltantes.map((p) => ListTile(
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: t.primary.withValues(alpha: 0.15),
                  child: Text(p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                      style: TextStyle(
                          color: t.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 13)),
                ),
                title: Text(p.name, style: TextStyle(color: t.text)),
                subtitle: Text('HCP ${p.handicapBase.toStringAsFixed(0)}',
                    style: TextStyle(color: t.sub, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _addPlayerToFamily(groupIdx, family, p.id, t);
                },
              )),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _groupModuleTile(
    int groupIdx,
    List<MapEntry<int, BetModuleInstance>> family,
    BetGroup g,
    GolfTheme t,
  ) {
    final template  = family.first.value;               // primer módulo como referencia
    // ── Título principal: siempre el tipo de apuesta (Nassau, Skins, Putts, …)
    // betGroupName se usa solo como subtítulo contextual.
    final typeTitle  = template.type.label;
    final groupName  = template.betGroupName;           // null si no hay nombre de grupo
    final count      = family.length;

    // Pairings legibles: "A vs B", "A vs C", …
    String nameOf(String id) =>
        _players.firstWhere((p) => p.id == id, orElse: () => Player(id: id, name: id)).name;

    final pairings = family.map((e) {
      final pids = e.value.participantIds;
      if (pids.length == 2) return '${nameOf(pids[0])} vs ${nameOf(pids[1])}';
      return pids.map(nameOf).join(', ');
    }).toList();

    // Jugadores de la partida que aún no juegan esta apuesta
    final faltantes = _playersMissingFrom(family, g);

    // Color del acento según tipo
    final isMatch  = template.type == BetModuleType.nassau ||
                     template.type == BetModuleType.matchAutoPress;
    final accent   = isMatch ? t.accent : t.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Cabecera ────────────────────────────────────────────────────
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(template.type.icon, style: const TextStyle(fontSize: 14)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(typeTitle,
                  style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 14)),
              Text(
                // Subtítulo: "N enfrentamientos · resumeLabel"
                // Si hay betGroupName contextual, se muestra como prefijo.
                groupName != null
                    ? '$count enfrentamientos · $groupName · ${template.summaryLabel}'
                    : '$count enfrentamientos · ${template.summaryLabel}',
                style: TextStyle(color: t.sub, fontSize: 11),
              ),
            ])),
            // ── Botón Editar grupo ───────────────────────────────────────
            // (el alta de jugadores va en una fila propia al pie de la tarjeta)
            GestureDetector(
              onTap: () => _editGroupModules(groupIdx, family, g, t),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Editar',
                    style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            // ── Botón Eliminar grupo ─────────────────────────────────────
            GestureDetector(
              onTap: () {
                setState(() {
                  // Eliminar exactamente los módulos de ESTA familia, por firma
                  // de configuración. Antes se filtraba por betGroupId, que
                  // puede ser null en módulos añadidos a mano.
                  final firma = template.configSignature;
                  final mods = _groups[groupIdx].modules
                      .where((m) => m.configSignature != firma)
                      .toList();
                  _groups[groupIdx] = _groups[groupIdx].copyWith(modules: mods);
                });
              },
              child: Icon(Icons.close, color: t.sub, size: 16),
            ),
          ]),

          // ── Lista compacta de pairings ───────────────────────────────────
          const SizedBox(height: 8),
          ...pairings.take(5).map((p) => Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(children: [
              Icon(Icons.sports_golf, color: t.sub, size: 11),
              const SizedBox(width: 4),
              Text(p, style: TextStyle(color: t.sub, fontSize: 11)),
            ]),
          )),
          if (pairings.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('… y ${pairings.length - 5} más',
                  style: TextStyle(color: t.sub, fontSize: 11)),
            ),

          // ── Chips ────────────────────────────────────────────────────────
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: [
            _infoChip(_structureLabelShort(template.structure), accent, t),
            _infoChip(template.useHandicap ? 'Net' : 'Gross', t.primary, t),
            if (template.type == BetModuleType.skins && template.skins.carryOver)
              _infoChip('🔥 Carry ON', t.accent, t),
            if (template.type == BetModuleType.nassau && template.nassau.pressEnabled)
              _infoChip('Press ON', t.accent, t),
          ]),

          // ── Alta de jugadores ────────────────────────────────────────────
          // Fila explícita con los nombres. Un icono suelto pasaba
          // desapercibido y esta es la acción que más falta hacía.
          if (!template.hasTeamSides && faltantes.isNotEmpty) ...[
            const SizedBox(height: 10),
            _addPlayersRow(groupIdx, family, g, faltantes, t),
          ],
        ]),
      ),
    );
  }

  /// Fila de acción para meter a los jugadores que faltan en una apuesta.
  /// Nombra a quién falta en vez de mostrar solo un contador.
  Widget _addPlayersRow(
    int groupIdx,
    List<MapEntry<int, BetModuleInstance>> family,
    BetGroup g,
    List<Player> faltantes,
    GolfTheme t,
  ) {
    final nombres = faltantes.map((p) => p.name.split(' ').first).join(', ');
    final uno = faltantes.length == 1;
    return GestureDetector(
      onTap: () => _pickPlayerForFamily(groupIdx, family, g, t),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: t.primary.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: t.primary.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          Icon(Icons.person_add_alt_1, color: t.primary, size: 15),
          const SizedBox(width: 7),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                uno
                    ? 'Añadir a $nombres a esta apuesta'
                    : 'Añadir jugadores a esta apuesta',
                style: TextStyle(
                    color: t.primary, fontWeight: FontWeight.w700, fontSize: 12),
              ),
              if (!uno)
                Text('$nombres no la juegan todavía',
                    style: TextStyle(color: t.sub, fontSize: 10.5)),
            ]),
          ),
          Icon(Icons.chevron_right, color: t.primary, size: 16),
        ]),
      ),
    );
  }

  // ── Editor en lote para una familia de módulos ───────────────────────────
  /// Abre el editor usando el primer módulo como template.
  /// Al guardar:
  ///   1. Aplica la config tipada base a TODOS los módulos de la familia.
  ///   2. Para cada módulo 1v1 busca pairConfigOverrides[pairKey(pidA,pidB)]
  ///      y recalcula la config tipada efectiva con ese valor.
  ///   3. Preserva id, participantIds, sides, name, betGroupId, betGroupName,
  ///      structure y anchorPlayerId intactos.
  void _editGroupModules(
    int groupIdx,
    List<MapEntry<int, BetModuleInstance>> family,
    BetGroup g,
    GolfTheme t,
  ) {
    var cfg = family.first.value;

    // ── Estado: pairKey → TextEditingController ──────────────────────────────
    // Construimos la lista de pares 1v1 de esta familia (orden de inserción).
    final pairEntries = family
        .where((e) => e.value.participantIds.length == 2)
        .toList();

    // Controladores indexados por pairKey canónico.
    final pairCtrl = <String, TextEditingController>{};
    for (final e in pairEntries) {
      final pids = e.value.participantIds;
      final pk   = BetModuleInstance.pairKey(pids[0], pids[1]);
      // Inicializar desde pairConfigOverrides si ya existe, o legacy playerConfigOverrides.
      final existingOv = cfg.pairConfigOverrides?[pk];
      final legacyVal  = cfg.effectiveValueForDuel(pids[0], pids[1]).$1;
      final ovKey      = cfg.type == BetModuleType.units ? 'allEvents' : 'value';
      final initVal    = existingOv != null
          ? (existingOv[ovKey] as num?)?.toDouble()
          : null;
      // Si había override legacy (playerConfigOverrides), precargarlo también.
      final preload = initVal ?? (cfg.playerConfigOverrides != null ? legacyVal : null);
      pairCtrl[pk] = TextEditingController(
        text: preload != null ? preload.toStringAsFixed(0) : '',
      );
    }

    // Partir de los valores del módulo que se abre, no de los del anterior.
    _clearCfgCtrls();

    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSt) {

          // ── Construir pairConfigOverrides desde el estado UI ───────────────
          // Solo incluye pares con valor explícito (distinto del default o vacío).
          Map<String, Map<String, dynamic>> buildPairOverridesMap() {
            final result  = <String, Map<String, dynamic>>{};
            final ovKey   = cfg.type == BetModuleType.units ? 'allEvents' : 'value';
            final defVal  = cfg.baseValue;
            for (final e in pairEntries) {
              final pids = e.value.participantIds;
              final pk   = BetModuleInstance.pairKey(pids[0], pids[1]);
              final text = pairCtrl[pk]?.text.trim() ?? '';
              final val  = double.tryParse(text);
              // Guardar solo si es un valor válido, positivo y distinto al default.
              if (val != null && val > 0 && val != defVal) {
                result[pk] = {ovKey: val};
              }
            }
            return result;
          }

          // ── Valor a mostrar para un par (override o default) ───────────────
          double displayValueFor(String pk) {
            final text = pairCtrl[pk]?.text.trim() ?? '';
            return double.tryParse(text) ?? cfg.baseValue;
          }

          final supportsOverride = cfg.supportsPlayerOverride;

          return DraggableScrollableSheet(
            initialChildSize: 0.90,
            minChildSize: 0.5,
            maxChildSize: 0.97,
            expand: false,
            builder: (_, sc) {
              final groupName = cfg.betGroupName ?? cfg.type.label;
              return Padding(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(ctx2).viewInsets.bottom),
                child: SingleChildScrollView(
                  controller: sc,
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Header ──────────────────────────────────────────────
                      Row(children: [
                        Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('${cfg.type.icon} ${cfg.type.label}',
                              style: TextStyle(
                                  color: t.text,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800)),
                          Text(groupName,
                              style: TextStyle(color: t.sub, fontSize: 12)),
                        ])),
                        GestureDetector(
                            onTap: () => Navigator.pop(ctx2),
                            child: Icon(Icons.close, color: t.sub)),
                      ]),
                      const SizedBox(height: 6),
                      // Banner info
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: t.primary.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: t.primary.withValues(alpha: 0.2)),
                        ),
                        child: Row(children: [
                          Icon(Icons.info_outline,
                              color: t.primary, size: 14),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(
                            'La configuración base y los valores por duelo se aplicarán a los ${family.length} enfrentamientos.',
                            style:
                                TextStyle(color: t.primary, fontSize: 11),
                          )),
                        ]),
                      ),
                      const SizedBox(height: 20),

                      // ── Config base por tipo ──────────────────────────────
                      // groupMode: true → para Units muestra campo único de valor
                      // base en lugar de la lista detallada por evento.
                      ..._configWidgets(
                          cfg, t, setSt, (updated) {
                            cfg = updated;
                            setSt(() {}); // rebuild preview
                          }, groupMode: true),

                      // ── Valores por duelo (solo tipos soportados) ─────────
                      if (supportsOverride && pairEntries.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        _sectionLabel(
                          cfg.type == BetModuleType.units
                              ? 'VALOR DE UNIDAD POR DUELO'
                              : 'VALORES POR DUELO',
                          t,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          cfg.type == BetModuleType.units
                              ? 'Valor de la unidad para cada enfrentamiento. '
                                'Todas las unidades del duelo valen este monto.'
                              : 'Edita el valor de cada enfrentamiento individualmente. '
                                'Deja el campo vacío o con el valor base para usar el default.',
                          style: TextStyle(color: t.sub, fontSize: 11),
                        ),
                        const SizedBox(height: 10),
                        ...pairEntries.map((e) {
                          final pids   = e.value.participantIds;
                          final pk     = BetModuleInstance.pairKey(pids[0], pids[1]);
                          final ctrl   = pairCtrl[pk]!;
                          final nameA  = _players.firstWhere((p) => p.id == pids[0],
                              orElse: () => Player(id: pids[0], name: pids[0])).name.split(' ').first;
                          final nameB  = _players.firstWhere((p) => p.id == pids[1],
                              orElse: () => Player(id: pids[1], name: pids[1])).name.split(' ').first;
                          final hasOv  = ctrl.text.trim().isNotEmpty &&
                              double.tryParse(ctrl.text.trim()) != null &&
                              double.tryParse(ctrl.text.trim()) != cfg.baseValue;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: hasOv
                                    ? t.primary.withValues(alpha: 0.07)
                                    : t.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: hasOv
                                      ? t.primary.withValues(alpha: 0.4)
                                      : t.divider,
                                  width: hasOv ? 1.5 : 1,
                                ),
                              ),
                              child: Row(children: [
                                // Avatares de los dos jugadores
                                GAvatar(
                                    name: nameA,
                                    colorIndex: _players.firstWhere(
                                        (p) => p.id == pids[0],
                                        orElse: () => Player(id: pids[0], name: pids[0])).colorIndex,
                                    size: 18),
                                const SizedBox(width: 4),
                                Text('vs',
                                    style: TextStyle(
                                        color: t.sub,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(width: 4),
                                GAvatar(
                                    name: nameB,
                                    colorIndex: _players.firstWhere(
                                        (p) => p.id == pids[1],
                                        orElse: () => Player(id: pids[1], name: pids[1])).colorIndex,
                                    size: 18),
                                const SizedBox(width: 8),
                                // Nombres
                                Expanded(
                                  child: Text(
                                    '$nameA vs $nameB',
                                    style: TextStyle(
                                      color: hasOv ? t.text : t.sub,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                // Campo de valor editable
                                SizedBox(
                                  width: 80,
                                  child: TextField(
                                    controller: ctrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: false),
                                    textAlign: TextAlign.center,
                                    onChanged: (_) => setSt(() {}),
                                    style: TextStyle(
                                        color: t.text,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      hintText: cfg.baseValue
                                          .toStringAsFixed(0),
                                      hintStyle:
                                          TextStyle(color: t.sub, fontSize: 13),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 6),
                                      prefixText: '\$',
                                      prefixStyle: TextStyle(
                                          color: t.primary,
                                          fontWeight: FontWeight.w700),
                                      filled: true,
                                      fillColor: hasOv
                                          ? t.card
                                          : t.surface,
                                      border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        borderSide:
                                            BorderSide(color: t.primary),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                            color: hasOv
                                                ? t.primary
                                                    .withValues(alpha: 0.5)
                                                : t.divider),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                            color: t.primary, width: 1.5),
                                      ),
                                    ),
                                  ),
                                ),
                              ]),
                            ),
                          );
                        }),
                      ],

                      // ── Botón guardar ─────────────────────────────────────
                      const SizedBox(height: 24),
                      GPrimaryButton(
                        label:
                            'Aplicar a los ${family.length} enfrentamientos',
                        onTap: () {
                          final pairOvsMap = supportsOverride
                              ? buildPairOverridesMap()
                              : <String, Map<String, dynamic>>{};

                          setState(() {
                            final mods = List<BetModuleInstance>.from(
                                _groups[groupIdx].modules);
                            for (final entry in family) {
                              final mi   = entry.key;
                              final old  = entry.value;
                              final pids = old.participantIds;

                              // Calcular config tipada efectiva para este
                              // módulo 1v1 usando el override de par.
                              SkinsConfig?  effectiveSkins  = cfg.skinsConfig;
                              OyesesConfig? effectiveOyeses = cfg.oyesesConfig;
                              UnitsConfig?  effectiveUnits  = cfg.unitsConfig;
                              PuttsConfig?  effectivePutts  = cfg.puttsConfig;
                              MedalConfig?  effectiveMedal  = cfg.medalConfig;

                              if (supportsOverride && pids.length == 2) {
                                final pk  = BetModuleInstance.pairKey(
                                    pids[0], pids[1]);
                                final ov  = pairOvsMap[pk];
                                final ovKey = cfg.type == BetModuleType.units
                                    ? 'allEvents'
                                    : 'value';
                                final effVal = ov != null
                                    ? (ov[ovKey] as num?)?.toDouble() ??
                                        cfg.baseValue
                                    : cfg.baseValue;

                                switch (cfg.type) {
                                  case BetModuleType.skins:
                                    effectiveSkins = (cfg.skinsConfig ??
                                            SkinsConfig.def)
                                        .copyWith(valuePerSkin: effVal);
                                    break;
                                  case BetModuleType.oyeses:
                                    effectiveOyeses = (cfg.oyesesConfig ??
                                            OyesesConfig.def)
                                        .copyWith(value: effVal);
                                    break;
                                  case BetModuleType.units:
                                    // Aplicar el mismo valor a todos los eventos
                                    // del duelo usando el helper withAllEventsValue.
                                    effectiveUnits = (cfg.unitsConfig ?? UnitsConfig.def)
                                        .withAllEventsValue(effVal);
                                    break;
                                  case BetModuleType.putts:
                                    effectivePutts = (cfg.puttsConfig ??
                                            PuttsConfig.def)
                                        .copyWith(value: effVal);
                                    break;
                                  case BetModuleType.medal:
                                    effectiveMedal = (cfg.medalConfig ??
                                            MedalConfig.def)
                                        .copyWith(value: effVal);
                                    break;
                                  default:
                                    break;
                                }
                              }

                              mods[mi] = old.copyWith(
                                formatMode:           cfg.formatMode,
                                skinsConfig:          effectiveSkins,
                                nassauConfig:         cfg.nassauConfig,
                                matchAutoPressConfig: cfg.matchAutoPressConfig,
                                medalConfig:          effectiveMedal,
                                puttsConfig:          effectivePutts,
                                oyesesConfig:         effectiveOyeses,
                                unitsConfig:          effectiveUnits,
                                // Guardar los overrides por par para que al
                                // reabrir el editor se reconstruya el estado.
                                pairConfigOverrides:
                                    pairOvsMap.isEmpty ? null : pairOvsMap,
                                // Limpiar overrides legacy al guardar.
                                clearPlayerOverrides: true,
                              );
                            }
                            _groups[groupIdx] =
                                _groups[groupIdx].copyWith(modules: mods);
                          });
                          Navigator.pop(ctx2);
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    ).whenComplete(() {
      // pairCtrl se crea por apertura del sheet; sin esto se filtraba uno por
      // duelo cada vez. Se libera tras el pop, cuando ya no hay TextField que
      // lo referencie.
      for (final c in pairCtrl.values) {
        c.dispose();
      }
    });
  }

  // ── Editor de instancia (bottom sheet con config tipada) ─────────────────
  void _editModuleInstance(int gi, int mi, BetModuleInstance mod, BetGroup g, GolfTheme t) {
    var cfg = mod;
    final allPids = g.playerIds;
    var localPids = List<String>.from(
        mod.participantIds.isEmpty ? allPids : mod.participantIds);

    // Partir de los valores del módulo que se abre, no de los del anterior.
    _clearCfgCtrls();

    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSt) {
          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, sc) {
              return Padding(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(ctx2).viewInsets.bottom),
                child: SingleChildScrollView(
                  controller: sc,
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Header ─────────────────────────────────────
                      Row(children: [
                        Text('${cfg.type.icon} ${cfg.type.label}',
                            style: TextStyle(
                                color: t.text,
                                fontSize: 20,
                                fontWeight: FontWeight.w800)),
                        const Spacer(),
                        GestureDetector(
                            onTap: () => Navigator.pop(ctx2),
                            child: Icon(Icons.close, color: t.sub)),
                      ]),
                      const SizedBox(height: 4),
                      Text(cfg.type.description,
                          style: TextStyle(color: t.sub, fontSize: 12)),
                      const SizedBox(height: 16),

                      // ── Participantes ───────────────────────────────
                      _sectionLabel('PARTICIPANTES', t),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: allPids.map((pid) {
                          final player = _players.firstWhere(
                              (p) => p.id == pid,
                              orElse: () => Player(id: pid, name: pid));
                          final sel = localPids.contains(pid);
                          return GestureDetector(
                            onTap: () => setSt(() {
                              if (sel) {
                                if (localPids.length > 2) {
                                  localPids.remove(pid);
                                }
                              } else {
                                localPids.add(pid);
                              }
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: sel
                                    ? t.primary.withValues(alpha: 0.12)
                                    : t.surface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color:
                                        sel ? t.primary : t.divider,
                                    width: sel ? 1.5 : 1),
                              ),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    GAvatar(
                                        name: player.name,
                                        colorIndex: player.colorIndex,
                                        size: 18),
                                    const SizedBox(width: 6),
                                    Text(
                                      player.name.split(' ').first,
                                      style: TextStyle(
                                          color: sel
                                              ? t.primary
                                              : t.text,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13),
                                    ),
                                  ]),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),

                      // ── Config específica por tipo ──────────────────
                      ..._configWidgets(
                          cfg, t, setSt, (updated) => cfg = updated),

                      const SizedBox(height: 24),
                      GPrimaryButton(
                        label: 'Guardar',
                        onTap: () {
                          setState(() {
                            final mods = List<BetModuleInstance>.from(
                                _groups[gi].modules);
                            mods[mi] =
                                cfg.copyWith(participantIds: localPids);
                            _groups[gi] =
                                _groups[gi].copyWith(modules: mods);
                          });
                          Navigator.pop(ctx2);
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ── Widgets de config según tipo ─────────────────────────────────────────
  // [groupMode] = true → editor agrupado: para Units muestra solo el campo
  // de valor base único en lugar de la lista detallada por evento.
  List<Widget> _configWidgets(BetModuleInstance cfg, GolfTheme t, StateSetter setSt, void Function(BetModuleInstance) update, {bool groupMode = false}) {
    // Tipos donde el selector de formato aplica (no Units, que son siempre individuales)
    final showFormatSelector = cfg.type != BetModuleType.units;

    final formatSelector = !showFormatSelector ? <Widget>[] : [
      _sectionLabel('ESTRUCTURA DE APUESTA', t),
      const SizedBox(height: 8),
      // Selector 1 Pot vs Todos vs Todos
      Row(children: [
        Expanded(child: _FormatModeCard(
          isSelected: cfg.formatMode == BetFormatMode.onePot,
          icon: '🏆',
          title: '1 Pot',
          description: 'Un solo pozo grupal.\nEl ganador cobra a todos.',
          t: t,
          onTap: () => setSt(() => update(cfg.copyWith(formatMode: BetFormatMode.onePot))),
        )),
        const SizedBox(width: 10),
        Expanded(child: _FormatModeCard(
          isSelected: cfg.formatMode == BetFormatMode.allVsAll,
          icon: '⚔️',
          title: 'Todos vs Todos',
          description: 'Cada pareja tiene su\nduelo independiente.',
          t: t,
          onTap: () => setSt(() => update(cfg.copyWith(formatMode: BetFormatMode.allVsAll))),
        )),
      ]),
      const SizedBox(height: 6),
      Text(
        cfg.formatMode == BetFormatMode.onePot
            ? '1 Pot: un solo ganador por hoyo/segmento toma del resto del grupo.'
            : 'Todos vs Todos: A vs B, A vs C y B vs C cada uno con su apuesta propia.',
        style: TextStyle(color: t.sub, fontSize: 11, fontStyle: FontStyle.italic),
      ),
      const SizedBox(height: 20),
    ];

    switch (cfg.type) {
      case BetModuleType.nassauLowHigh:
        // Los lados se configuran en BetModuleEditSheet, que es el editor
        // que tiene la sección de equipos. Aquí no hay dónde ponerlos.
        return [
          _sectionLabel('BOLA BAJA / BOLA ALTA', t),
          const SizedBox(height: 8),
          Text(
            'Formato 2 vs 2. Los equipos y los montos se configuran en el '
            'editor de la apuesta: ciérrala y tócala en la tarjeta de la '
            'partida.',
            style: TextStyle(color: t.sub, fontSize: 12, height: 1.4),
          ),
        ];
      case BetModuleType.skins:
        final s = cfg.skins;
        final ctrl = _cfgCtrl('skins.value', s.valuePerSkin.toStringAsFixed(0));
        return [
          ...formatSelector,
          _sectionLabel('VALOR POR SKIN', t),
          const SizedBox(height: 8),
          _amountField('Valor por skin', ctrl, t, onChanged: (v) {
            update(cfg.copyWith(skinsConfig: s.copyWith(valuePerSkin: v)));
          }),
          const SizedBox(height: 16),
          _sectionLabel('JUEGO', t),
          const SizedBox(height: 8),
          _segmentedRow(['Gross', 'Net'], s.mode == GrossNetMode.net ? 1 : 0, t, (i) {
            setSt(() => update(cfg.copyWith(skinsConfig: s.copyWith(mode: i == 1 ? GrossNetMode.net : GrossNetMode.gross))));
          }),
          const SizedBox(height: 16),
          _sectionLabel('ACUMULACIÓN (CARRY)', t),
          const SizedBox(height: 8),
          // Toggle carry con diseño destacado
          GestureDetector(
            onTap: () {
              setSt(() => update(cfg.copyWith(skinsConfig: s.copyWith(carryOver: !s.carryOver))));
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: s.carryOver
                    ? t.accent.withValues(alpha: 0.10)
                    : t.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: s.carryOver ? t.accent.withValues(alpha: 0.55) : t.divider,
                  width: s.carryOver ? 1.5 : 1,
                ),
              ),
              child: Row(children: [
                // Icono + texto
                Text(s.carryOver ? '🔥' : '❌', style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    'Acumular hoyos empatados (Carry)',
                    style: TextStyle(
                      color: s.carryOver ? t.accent : t.text,
                      fontWeight: FontWeight.w700, fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    s.carryOver
                        ? 'Los empates acumulan el skin al siguiente hoyo 🔥'
                        : 'Los empates no se acumulan — el skin se pierde',
                    style: TextStyle(color: t.sub, fontSize: 11),
                  ),
                ])),
                Switch(
                  value: s.carryOver,
                  onChanged: (v) {
                    setSt(() => update(cfg.copyWith(skinsConfig: s.copyWith(carryOver: v))));
                  },
                  activeThumbColor: t.accent,
                  activeTrackColor: t.accent.withValues(alpha: 0.4),
                  inactiveTrackColor: t.divider,
                ),
              ]),
            ),
          ),
        ];

      case BetModuleType.nassau:
        final n = cfg.nassau;
        final cFront = _cfgCtrl('nassau.front',      n.frontValue.toStringAsFixed(0));
        final cBack  = _cfgCtrl('nassau.back',       n.backValue.toStringAsFixed(0));
        final cTotal = _cfgCtrl('nassau.total',      n.totalValue.toStringAsFixed(0));
        final cPF    = _cfgCtrl('nassau.pressFront', n.frontPressValue.toStringAsFixed(0));
        final cPB    = _cfgCtrl('nassau.pressBack',  n.backPressValue.toStringAsFixed(0));
        void saveNassauValues() {
          final fv  = double.tryParse(cFront.text) ?? n.frontValue;
          final bv  = double.tryParse(cBack.text)  ?? n.backValue;
          final tv  = double.tryParse(cTotal.text) ?? n.totalValue;
          final pfv = double.tryParse(cPF.text)    ?? n.frontPressValue;
          final pbv = double.tryParse(cPB.text)    ?? n.backPressValue;
          update(cfg.copyWith(nassauConfig: n.copyWith(
            frontValue: fv, backValue: bv, totalValue: tv,
            frontPressValue: pfv, backPressValue: pbv,
          )));
        }
        return [
          ...formatSelector,
          _sectionLabel('VALORES', t),
          const SizedBox(height: 8),
          _amountField('Front 9', cFront, t, onChanged: (_) => saveNassauValues()),
          const SizedBox(height: 8),
          _amountField('Back 9', cBack, t, onChanged: (_) => saveNassauValues()),
          const SizedBox(height: 8),
          _amountField('Total 18', cTotal, t, onChanged: (_) => saveNassauValues()),
          const SizedBox(height: 16),
          _sectionLabel('JUEGO', t),
          const SizedBox(height: 8),
          _segmentedRow(['Gross', 'Net'], n.mode == GrossNetMode.net ? 1 : 0, t, (i) {
            setSt(() => update(cfg.copyWith(nassauConfig: n.copyWith(mode: i == 1 ? GrossNetMode.net : GrossNetMode.gross))));
          }),
          const SizedBox(height: 16),

          // ── Regla de empate ────────────────────────────────────────────────
          _sectionLabel('EMPATE EN SEGMENTO', t),
          const SizedBox(height: 8),
          _segmentedRow(['Push (devuelve)', 'Carry (acumula)'],
              n.tieRule == TieRule.carryOver ? 1 : 0, t, (i) {
            setSt(() => update(cfg.copyWith(nassauConfig: n.copyWith(
              tieRule: i == 1 ? TieRule.carryOver : TieRule.push,
              carryEnabled: i == 1 ? true : n.carryEnabled,
            ))));
          }),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              n.tieRule == TieRule.carryOver
                  ? 'El valor del segmento empatado se acumula al siguiente automáticamente.'
                  : 'El valor del segmento empatado se devuelve (nadie gana ese segmento).',
              style: TextStyle(color: t.sub, fontSize: 11),
            ),
          ),
          const SizedBox(height: 16),

          // ── Carry en Back 9 (independiente del press) ──────────────────────
          _toggleRow(
            title: 'Carry en Back 9',
            subtitle: n.carryEnabled
                ? 'Si el F9 termina empatado, el B9 vale x${n.carryFactor.toStringAsFixed(0)}'
                : 'Sin carry — el B9 siempre vale su monto normal',
            value: n.carryEnabled,
            onChanged: (v) => setSt(() => update(cfg.copyWith(nassauConfig: n.copyWith(carryEnabled: v)))),
            t: t,
          ),
          if (n.carryEnabled) ...[
            const SizedBox(height: 12),
            _sectionLabel('MULTIPLICADOR CARRY', t),
            const SizedBox(height: 8),
            _segmentedRow(['x2', 'x3', 'x4'],
                n.carryFactor >= 4 ? 2 : n.carryFactor >= 3 ? 1 : 0, t, (i) {
              setSt(() => update(cfg.copyWith(nassauConfig: n.copyWith(
                carryFactor: (i + 2).toDouble(),
              ))));
            }),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                'Si el F9 termina igualado, el B9 (\$${n.backValue.toStringAsFixed(0)}) '
                'pasa a valer \$${(n.backValue * n.carryFactor).toStringAsFixed(0)}.',
                style: TextStyle(color: t.sub, fontSize: 11),
              ),
            ),
          ],
          const SizedBox(height: 16),

          // ── Press automático ───────────────────────────────────────────────
          _toggleRow(
            title: 'Activar presiones (Press)',
            subtitle: n.pressEnabled
                ? 'Trigger: ${n.autoPressTrigger} down'
                : 'Sin presiones — solo Front 9, Back 9 y Total',
            value: n.pressEnabled,
            onChanged: (v) => setSt(() => update(cfg.copyWith(nassauConfig: n.copyWith(pressEnabled: v)))),
            t: t,
          ),
          if (n.pressEnabled) ...[
            const SizedBox(height: 12),
            _sectionLabel('TRIGGER DE PRESIÓN', t),
            const SizedBox(height: 8),
            _segmentedRow(['1 down', '2 down', '3 down'], n.autoPressTrigger - 1, t, (i) {
              setSt(() => update(cfg.copyWith(nassauConfig: n.copyWith(autoPressTrigger: i + 1))));
            }),
            const SizedBox(height: 16),
            _sectionLabel('VALOR DE PRESIONES', t),
            const SizedBox(height: 6),
            Text('Monto que vale cada presión dentro del segmento.',
                style: TextStyle(color: t.sub, fontSize: 11)),
            const SizedBox(height: 8),
            _amountField('Press Front 9', cPF, t, onChanged: (_) => saveNassauValues()),
            const SizedBox(height: 8),
            _amountField('Press Back 9', cPB, t, onChanged: (_) => saveNassauValues()),
            const SizedBox(height: 16),
            _toggleRow(
              title: 'Presiones múltiples por segmento',
              subtitle: n.allowMultiplePresses
                  ? 'Se pueden abrir varias presiones en el mismo segmento'
                  : 'Máximo una presión activa por segmento',
              value: n.allowMultiplePresses,
              onChanged: (v) => setSt(() => update(cfg.copyWith(nassauConfig: n.copyWith(allowMultiplePresses: v)))),
              t: t,
            ),
            if (!n.allowMultiplePresses) ...[
              const SizedBox(height: 12),
              _sectionLabel('MÁX. PRESIONES POR SEGMENTO', t),
              const SizedBox(height: 8),
              _segmentedRow(['1', '2', '3'],
                  (n.maxPresses == null || n.maxPresses! <= 1) ? 0
                  : n.maxPresses! == 2 ? 1 : 2, t, (i) {
                setSt(() => update(cfg.copyWith(nassauConfig: n.copyWith(maxPresses: i + 1))));
              }),
            ],
          ],
        ];

      case BetModuleType.matchAutoPress:
        return [...formatSelector, ..._matchAutoPressConfig(cfg, t, setSt, update)];



      case BetModuleType.medal:
        final m = cfg.medal;
        final ctrl = _cfgCtrl('medal.value', m.value.toStringAsFixed(0));
        return [
          ...formatSelector,
          _sectionLabel('VALOR', t),
          const SizedBox(height: 8),
          _amountField('Monto', ctrl, t, onChanged: (v) {
            update(cfg.copyWith(medalConfig: m.copyWith(value: v)));
          }),
          const SizedBox(height: 16),
          _sectionLabel('HOYOS', t),
          const SizedBox(height: 8),
          _segmentedRow(['9 hoyos', '18 hoyos'], m.holes == 18 ? 1 : 0, t, (i) {
            setSt(() => update(cfg.copyWith(medalConfig: m.copyWith(holes: i == 1 ? 18 : 9))));
          }),
          const SizedBox(height: 16),
          _sectionLabel('JUEGO', t),
          const SizedBox(height: 8),
          _segmentedRow(['Gross', 'Net'], m.mode == GrossNetMode.net ? 1 : 0, t, (i) {
            setSt(() => update(cfg.copyWith(medalConfig: m.copyWith(mode: i == 1 ? GrossNetMode.net : GrossNetMode.gross))));
          }),
        ];

      case BetModuleType.putts:
        final p = cfg.putts;
        final ctrl = _cfgCtrl('putts.value', p.value.toStringAsFixed(0));
        return [
          ...formatSelector,
          _sectionLabel('VALOR', t),
          const SizedBox(height: 8),
          _amountField('Monto por segmento', ctrl, t, onChanged: (v) {
            update(cfg.copyWith(puttsConfig: p.copyWith(value: v)));
          }),
          const SizedBox(height: 16),
          _sectionLabel('MODO', t),
          const SizedBox(height: 8),
          _segmentedRow(['Por segmento', 'Hoyo a hoyo'], p.puttsMode == PuttsMode.perHole ? 1 : 0, t, (i) {
            setSt(() => update(cfg.copyWith(puttsConfig: p.copyWith(puttsMode: i == 1 ? PuttsMode.perHole : PuttsMode.total))));
          }),
          const SizedBox(height: 16),
          _toggleRow(
            title: 'Penalti por 3-putt',
            subtitle: p.threePuttPenalty ? 'Se cobra por cada 3-putt' : 'Sin penalti por 3-putt',
            value: p.threePuttPenalty,
            onChanged: (v) => setSt(() => update(cfg.copyWith(puttsConfig: p.copyWith(threePuttPenalty: v)))),
            t: t,
          ),
        ];

      case BetModuleType.oyeses:
        final o = cfg.oyeses;
        final ctrl = _cfgCtrl('oyeses.value', o.value.toStringAsFixed(0));
        // Controller para valor fijo del zapato (0 = automático)
        final zapatoCtrl = _cfgCtrl('oyeses.zapato',
            o.zapatoValue > 0 ? o.zapatoValue.toStringAsFixed(0) : '');
        // Par-3 reales del campo seleccionado (fallback: estándar)
        final realPar3Holes = (_selectedCourse?.holes ?? CourseInfo.standard.holes)
            .where((h) => h.isPar3)
            .map((h) => h.hole)
            .toList()
          ..sort();
        return [
          _sectionLabel('VALOR POR OYÉS', t),
          const SizedBox(height: 8),
          _amountField('Monto por oyés', ctrl, t, onChanged: (v) {
            update(cfg.copyWith(oyesesConfig: o.copyWith(value: v)));
          }),
          const SizedBox(height: 16),
          _sectionLabel('HOYOS ELEGIBLES', t),
          const SizedBox(height: 6),
          Text('Vacío = todos los par 3. Selecciona para restringir.', style: TextStyle(color: t.sub, fontSize: 11)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: realPar3Holes.map((h) {
            final sel = o.eligibleHoles.isEmpty || o.eligibleHoles.contains(h);
            return GestureDetector(
              onTap: () {
                setSt(() {
                  final current = List<int>.from(o.eligibleHoles.isEmpty
                      ? List<int>.from(realPar3Holes) : o.eligibleHoles);
                  if (current.contains(h)) { current.remove(h); } else { current.add(h); }
                  update(cfg.copyWith(oyesesConfig: o.copyWith(eligibleHoles: current)));
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: sel ? t.primary.withValues(alpha: 0.12) : t.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: sel ? t.primary : t.divider),
                ),
                child: Text('H$h', style: TextStyle(color: sel ? t.primary : t.sub, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            );
          }).toList()),
          const SizedBox(height: 20),
          // ── ZAPATO ──────────────────────────────────────────────────────
          _sectionLabel('👟 ZAPATO', t),
          const SizedBox(height: 6),
          Text(
            cfg.isAllVsAll
                ? 'En Todos vs Todos: si A le gana TODOS los oyeses a B, A hace zapato vs B (puede haber varios zapatos).'
                : 'En 1 Pot: solo si un jugador gana TODOS los oyeses del campo, cobra el zapato al grupo.',
            style: TextStyle(color: t.sub, fontSize: 11),
          ),
          const SizedBox(height: 10),
          _toggleRow(
            title: 'Activar zapato',
            subtitle: o.zapatoEnabled
                ? (cfg.isAllVsAll
                    ? 'Zapato por pareja: quien gane todos los oyeses vs otro cobra extra'
                    : 'Zapato grupal: el ganador absoluto de todos los oyeses cobra a todos')
                : 'Sin regla de zapato',
            value: o.zapatoEnabled,
            onChanged: (v) => setSt(() => update(cfg.copyWith(oyesesConfig: o.copyWith(zapatoEnabled: v)))),
            t: t,
          ),
          if (o.zapatoEnabled) ...[
            const SizedBox(height: 12),
            // Valor del zapato
            Builder(builder: (_) {
              final auto = o.zapatoValue == 0;
              final par3count = o.eligibleHoles.isEmpty ? realPar3Holes.length : o.eligibleHoles.length;
              final autoAmt = par3count * o.value;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _sectionLabel('VALOR DEL ZAPATO', t),
                const SizedBox(height: 6),
                Text(
                  auto
                      ? 'Automático: $par3count oyeses × \$${o.value.toStringAsFixed(0)} = \$${autoAmt.toStringAsFixed(0)} por par afectado'
                      : 'Valor fijo: \$${o.zapatoValue.toStringAsFixed(0)}',
                  style: TextStyle(color: t.sub, fontSize: 11),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: zapatoCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: false),
                  textAlign: TextAlign.right,
                  // Vacío = 0 = automático, así que aquí no se filtra por parseo.
                  onChanged: (txt) => update(cfg.copyWith(
                      oyesesConfig: o.copyWith(zapatoValue: double.tryParse(txt) ?? 0))),
                  style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Monto fijo (dejar vacío = automático)',
                    labelStyle: TextStyle(color: t.sub, fontSize: 12),
                    prefixText: '\$ ',
                    prefixStyle: TextStyle(color: t.sub, fontSize: 13),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    fillColor: t.surface, filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.primary, width: 1.5)),
                  ),
                ),
                const SizedBox(height: 12),
                _sectionLabel('APLICA EN', t),
                const SizedBox(height: 8),
                _segmentedRow(['Solo campo 18H', 'Cualquier ronda'], o.zapatoRequires18 ? 0 : 1, t, (i) {
                  setSt(() => update(cfg.copyWith(oyesesConfig: o.copyWith(zapatoRequires18: i == 0))));
                }),
                const SizedBox(height: 6),
                Text(
                  o.zapatoRequires18
                      ? 'Solo aplica en campos con 3+ par-3s (rondas de 18 hoyos).'
                      : 'Aplica en cualquier campo al completarse todos sus par-3s.',
                  style: TextStyle(color: t.sub, fontSize: 11),
                ),
              ]);
            }),
          ],
        ];

      case BetModuleType.units:
        final u = cfg.units;

        // ── Modo agrupado: campo único de valor base ──────────────────────
        if (groupMode) {
          final ctrlBase = _cfgCtrl(
              'units.base', u.representativeValue.toStringAsFixed(0));
          return [
            _sectionLabel('VALOR DE UNIDAD (BASE)', t),
            const SizedBox(height: 6),
            Text(
              'Valor por defecto de cada unidad para todos los duelos. '
              'Personaliza por pareja en la sección "Valor de unidad por duelo".',
              style: TextStyle(color: t.sub, fontSize: 11),
            ),
            const SizedBox(height: 10),
            _amountField('Valor por unidad', ctrlBase, t, onChanged: (v) {
              if (v > 0) update(cfg.copyWith(unitsConfig: u.withAllEventsValue(v)));
            }),
          ];
        }

        // ── Modo individual: lista completa de eventos ────────────────────
        // Un controller por cada tipo de evento
        final ctrls = <UnitEventType, TextEditingController>{
          for (final e in UnitEventType.values)
            e: _cfgCtrl('units.event.${e.name}', u.valueFor(e).toStringAsFixed(0)),
        };
        // Relee todos los campos y reconstruye el mapa de valores.
        void rebuildUnits() {
          final newMap = <UnitEventType, double>{};
          for (final e in UnitEventType.values) {
            final v = double.tryParse(ctrls[e]!.text);
            if (v != null) newMap[e] = v;
          }
          update(cfg.copyWith(unitsConfig: UnitsConfig(eventValues: newMap)));
        }
        return [
          _sectionLabel('VALOR POR EVENTO', t),
          const SizedBox(height: 6),
          Text('Establece el monto individual que paga cada evento.',
              style: TextStyle(color: t.sub, fontSize: 11)),
          const SizedBox(height: 12),
          // Fila de "aplicar a todos"
          _applyAllRow(ctrls, t, setSt, update, cfg),
          const SizedBox(height: 14),
          // Campo editable por evento
          ...UnitEventType.values.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              // Icono + nombre del evento
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.label,
                    style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 13)),
                Text(e.description,
                    style: TextStyle(color: t.sub, fontSize: 10)),
              ])),
              const SizedBox(width: 12),
              // Campo de monto
              SizedBox(
                width: 100,
                child: TextField(
                  controller: ctrls[e],
                  keyboardType: const TextInputType.numberWithOptions(decimal: false),
                  textAlign: TextAlign.right,
                  onChanged: (_) => rebuildUnits(),
                  style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14),
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    prefixStyle: TextStyle(color: t.sub, fontSize: 12),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    fillColor: t.surface,
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: t.divider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: t.divider),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: t.primary, width: 1.5),
                    ),
                  ),
                ),
              ),
            ]),
          )),
        ];
    }
  }

  // ── Config Match + Auto Press ─────────────────────────────────────────────
  // Este método devuelve los widgets de configuración para matchAutoPress
  // y se llama desde _configWidgets (case matchAutoPress).
  // Se mantiene separado para mantener el switch limpio.
  List<Widget> _matchAutoPressConfig(BetModuleInstance cfg, GolfTheme t, StateSetter setSt, void Function(BetModuleInstance) update) {
    final m = cfg.matchAutoPress;
    final cMatch = _cfgCtrl('match.value', m.matchValue.toStringAsFixed(0));
    final cPress = _cfgCtrl('match.press', m.pressValue.toStringAsFixed(0));
    return [
      _sectionLabel('MATCH PRINCIPAL', t),
      const SizedBox(height: 8),
      _amountField('Valor del match', cMatch, t, onChanged: (v) {
        update(cfg.copyWith(matchAutoPressConfig: m.copyWith(matchValue: v)));
      }),
      const SizedBox(height: 16),
      _sectionLabel('PRESIONES ADICIONALES', t),
      const SizedBox(height: 8),
      _amountField('Valor por presión', cPress, t, onChanged: (v) {
        update(cfg.copyWith(matchAutoPressConfig: m.copyWith(pressValue: v)));
      }),
      const SizedBox(height: 16),
      _sectionLabel('TRIGGER DE PRESIÓN', t),
      const SizedBox(height: 6),
      Text('Se abre una nueva presión cuando alguien llega a N hoyos arriba.',
          style: TextStyle(color: t.sub, fontSize: 11)),
      const SizedBox(height: 8),
      _segmentedRow(['1 up', '2 up', '3 up'], m.pressTriggerValue - 1, t, (i) {
        setSt(() => update(cfg.copyWith(matchAutoPressConfig: m.copyWith(pressTriggerValue: i + 1))));
      }),
      const SizedBox(height: 16),
      _sectionLabel('HANDICAP', t),
      const SizedBox(height: 8),
      _segmentedRow(['Gross', 'Net'], m.mode == GrossNetMode.net ? 1 : 0, t, (i) {
        setSt(() => update(cfg.copyWith(matchAutoPressConfig: m.copyWith(mode: i == 1 ? GrossNetMode.net : GrossNetMode.gross))));
      }),
      const SizedBox(height: 20),
      // Vista previa del juego
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.accent.withValues(alpha: 0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('⚙️  CÓMO FUNCIONA ESTE JUEGO', style: TextStyle(color: t.accent, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
          const SizedBox(height: 8),
          _previewRow('⛳', 'Match principal (Press #1)', '\$${m.matchValue.toStringAsFixed(0)}', t),
          const SizedBox(height: 4),
          _previewRow('⚡', 'Cada presión adicional vale', '\$${m.pressValue.toStringAsFixed(0)}', t),
          const SizedBox(height: 4),
          _previewRow('🎯', 'Se abre cuando alguien llega a', '${m.pressTriggerValue} up', t),
          const SizedBox(height: 4),
          _previewRow('📊', 'Todas las presiones duran', 'hasta hoyo 18', t),
        ]),
      ),
    ];
  }



  Widget _previewRow(String icon, String label, String value, GolfTheme t) {
    return Row(children: [
      Text(icon, style: const TextStyle(fontSize: 13)),
      const SizedBox(width: 8),
      Expanded(child: Text(label, style: TextStyle(color: t.sub, fontSize: 12))),
      Text(value, style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 12)),
    ]);
  }
  Widget _applyAllRow(
    Map<UnitEventType, TextEditingController> ctrls,
    GolfTheme t,
    StateSetter setSt,
    void Function(BetModuleInstance) update,
    BetModuleInstance cfg,
  ) {
    final globalCtrl = TextEditingController(text: '50');
    return Row(children: [
      Expanded(child: Text('Aplicar mismo valor a todos',
          style: TextStyle(color: t.sub, fontSize: 12))),
      const SizedBox(width: 10),
      SizedBox(
        width: 80,
        child: TextField(
          controller: globalCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
          textAlign: TextAlign.right,
          style: TextStyle(color: t.text, fontSize: 13),
          decoration: InputDecoration(
            prefixText: '\$ ',
            prefixStyle: TextStyle(color: t.sub, fontSize: 11),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            fillColor: t.surface,
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: t.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: t.divider),
            ),
          ),
        ),
      ),
      const SizedBox(width: 6),
      GestureDetector(
        onTap: () {
          final v = double.tryParse(globalCtrl.text);
          if (v == null) return;
          final newMap = <UnitEventType, double>{
            for (final e in UnitEventType.values) e: v,
          };
          setSt(() {
            for (final e in UnitEventType.values) {
              ctrls[e]!.text = v.toStringAsFixed(0);
            }
            update(cfg.copyWith(unitsConfig: UnitsConfig(eventValues: newMap)));
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: t.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('Aplicar', style: TextStyle(
            color: t.onPrimary, fontWeight: FontWeight.w700, fontSize: 12)),
        ),
      ),
    ]);
  }

  Widget _sectionLabel(String label, GolfTheme t) => Text(
    label, style: TextStyle(color: t.sub, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6),
  );

  Widget _segmentedRow(List<String> options, int selected, GolfTheme t, void Function(int) onSelect) {
    return Row(children: options.asMap().entries.map((e) {
      final isSel = e.key == selected;
      return Expanded(child: GestureDetector(
        onTap: () => onSelect(e.key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(vertical: 9),
          margin: EdgeInsets.only(right: e.key < options.length - 1 ? 6 : 0),
          decoration: BoxDecoration(
            color: isSel ? t.primary : t.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSel ? t.primary : t.divider),
          ),
          alignment: Alignment.center,
          child: Text(e.value, style: TextStyle(
            color: isSel ? t.onPrimary : t.sub,
            fontWeight: FontWeight.w700, fontSize: 12,
          )),
        ),
      ));
    }).toList());
  }

  Widget _toggleRow({required String title, required String subtitle, required bool value, required void Function(bool) onChanged, required GolfTheme t}) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: t.divider)),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(color: t.sub, fontSize: 11)),
        ])),
        Switch(value: value, onChanged: onChanged, activeThumbColor: t.primary, activeTrackColor: t.primary.withValues(alpha: 0.4), inactiveTrackColor: t.divider),
      ]),
    );

  // [onChanged] recibe el valor ya parseado. Se usa en vez de ctrl.addListener
  // porque el listener se registraba dentro del build y se acumulaba uno nuevo
  // por rebuild; onChanged lo invoca el framework y no necesita limpieza.
  Widget _amountField(String label, TextEditingController ctrl, GolfTheme t,
          {void Function(double)? onChanged}) => TextField(
    controller: ctrl, keyboardType: TextInputType.number, style: TextStyle(color: t.text),
    onChanged: onChanged == null ? null : (txt) {
      final v = double.tryParse(txt);
      if (v != null) onChanged(v);
    },
    decoration: InputDecoration(
      labelText: label, prefixText: '\$ ', fillColor: t.surface, filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.primary, width: 2)),
      labelStyle: TextStyle(color: t.sub),
    ),
  );

  void _addGroup(GolfTheme t) {
    final nameCtrl = TextEditingController(text: 'Partida ${_groups.length + 1}');
    final selectedPids = List<String>.from(_players.map((p) => p.id));
    showModalBottomSheet(context: context, backgroundColor: t.card, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setSt) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx2).viewInsets.bottom + 24, left: 20, right: 20, top: 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Nueva Partida', style: TextStyle(color: t.text, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          TextField(controller: nameCtrl, style: TextStyle(color: t.text),
            decoration: InputDecoration(labelText: 'Nombre', fillColor: t.surface, filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.primary, width: 2)),
              labelStyle: TextStyle(color: t.sub))),
          const SizedBox(height: 12),
          Text('Jugadores', style: TextStyle(color: t.sub, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: _players.map((p) {
            final sel = selectedPids.contains(p.id);
            return GestureDetector(
              onTap: () => setSt(() { if (sel) {
                selectedPids.remove(p.id);
              } else {
                selectedPids.add(p.id);
              } }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: sel ? t.primary.withValues(alpha: 0.15) : t.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sel ? t.primary : t.divider)),
                child: Text(p.name, style: TextStyle(color: sel ? t.primary : t.text, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            );
          }).toList()),
          const SizedBox(height: 16),
          GPrimaryButton(label: 'Crear partida', onTap: () {
            if (selectedPids.length >= 2) {
              final pids = List<String>.from(selectedPids);
              setState(() => _groups.add(BetGroup(
                id: _uuid.v4(), name: nameCtrl.text.trim().isEmpty ? 'Partida' : nameCtrl.text.trim(),
                format: PartidaFormat.allInOnePot, playerIds: pids,
                modules: [BetModuleInstance.defaultFor(BetModuleType.nassau, pids)],
              )));
            }
            Navigator.pop(ctx);
          }),
        ]),
      )));
  }

  void _addModule(int gi, BetGroup g, GolfTheme t) {
    // ── Estado local del sheet (paso 1 = tipo, paso 2 = estructura) ──────────
    final selected    = <BetModuleType>{};
    BetStructure      structure       = BetStructure.group;
    String?           anchorPlayerId;

    // ── Helpers de validación ────────────────────────────────────────────────
    String? validateStructure(BetStructure s, List<String> pids, String? anchor) {
      switch (s) {
        case BetStructure.group:
        case BetStructure.manual:
          return pids.length < 2 ? 'Mínimo 2 jugadores para Grupo único.' : null;
        case BetStructure.headToHead:
          return pids.length != 2 ? 'Head to head requiere exactamente 2 jugadores.' : null;
        case BetStructure.anchorVsMany:
          if (anchor == null) return 'Selecciona el jugador ancla.';
          if (pids.where((id) => id != anchor).isEmpty) return 'El ancla necesita al menos 1 rival.';
          return null;
        case BetStructure.roundRobin:
          return pids.length < 3 ? 'Todos vs todos requiere mínimo 3 jugadores.' : null;
      }
    }

    // ── Resumen del número de módulos que se crearán ─────────────────────────
    String previewCount(BetStructure s, List<String> pids, String? anchor, Set<BetModuleType> sel) {
      if (sel.isEmpty) return '';
      int modsPerType;
      switch (s) {
        case BetStructure.group:
        case BetStructure.manual:
        case BetStructure.headToHead:
          modsPerType = 1; break;
        case BetStructure.anchorVsMany:
          final rivals = pids.where((id) => id != anchor).length;
          modsPerType = rivals > 0 ? rivals : 0; break;
        case BetStructure.roundRobin:
          final n = pids.length;
          modsPerType = n >= 2 ? (n * (n - 1)) ~/ 2 : 0; break;
      }
      final total = sel.length * modsPerType;
      return total == 0 ? '' :
          'Se crearán $total apuesta${total > 1 ? 's' : ''}'
          '${sel.length > 1 ? " ($modsPerType por tipo × ${sel.length} tipos)" : ""}';
    }

    // ── Resumen detallado para anchorVsMany / roundRobin ─────────────────────
    String detailPreview(BetStructure s, List<String> pids, String? anchor,
        Set<BetModuleType> sel, List<Player> players) {
      if (sel.isEmpty) return '';
      String nameOf(String id) =>
          players.firstWhere((p) => p.id == id, orElse: () => Player(id: id, name: id)).name;

      final lines = <String>[];
      for (final bt in sel) {
        switch (s) {
          case BetStructure.anchorVsMany:
            if (anchor == null) break;
            final rivals = pids.where((id) => id != anchor).toList();
            lines.addAll(rivals.map((r) => '${bt.label}: ${nameOf(anchor)} vs ${nameOf(r)}'));
            break;
          case BetStructure.roundRobin:
            for (int i = 0; i < pids.length; i++) {
              for (int k = i + 1; k < pids.length; k++) {
                lines.add('${bt.label}: ${nameOf(pids[i])} vs ${nameOf(pids[k])}');
              }
            }
            break;
          default:
            break;
        }
      }
      return lines.join('\n');
    }

    showModalBottomSheet(
      context: context, backgroundColor: t.card, isScrollControlled: true, useRootNavigator: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setSt) {
        final pids       = g.playerIds;
        final validErr   = validateStructure(structure, pids, anchorPlayerId);
        final canConfirm = selected.isNotEmpty && validErr == null;
        final preview    = previewCount(structure, pids, anchorPlayerId, selected);
        final detail     = detailPreview(structure, pids, anchorPlayerId, selected, _players);

        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx2).viewInsets.bottom + 24, left: 20, right: 20, top: 24),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Cabecera ────────────────────────────────────────────────────
            Row(children: [
              Text('Agregar apuesta', style: TextStyle(color: t.text, fontSize: 18, fontWeight: FontWeight.w800)),
              const Spacer(),
              GestureDetector(onTap: () => Navigator.pop(ctx2), child: Icon(Icons.close, color: t.sub)),
            ]),
            const SizedBox(height: 4),
            Text('Tipo de apuesta y formato de enfrentamiento', style: TextStyle(color: t.sub, fontSize: 12)),
            const SizedBox(height: 16),

            // ── Tipo de apuesta ─────────────────────────────────────────────
            Text('MATCH PLAY', style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            // La lista es explícita para controlar orden y agrupado, pero pasa
            // por isCreatable: así retirar un tipo se hace en un solo sitio
            // —creatableBetTypes— y no hay que acordarse de cinco pantallas.
            // Añadir uno nuevo sí sigue exigiendo meterlo aquí, o queda
            // inalcanzable desde Setup.
            ...[
              BetModuleType.nassau,
              BetModuleType.nassauLowHigh,
            ].where((bt) => bt.isCreatable)
             .map((bt) => _betTypeTile(bt, selected, setSt, t)),
            const SizedBox(height: 16),
            Text('OTRAS APUESTAS', style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            ...[BetModuleType.skins, BetModuleType.medal, BetModuleType.putts, BetModuleType.oyeses, BetModuleType.units].map((bt) => _betTypeTile(bt, selected, setSt, t)),
            const SizedBox(height: 20),

            // ── Selector de estructura ──────────────────────────────────────
            Text('FORMATO DE ENFRENTAMIENTO', style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            ..._structureOptions(pids.length).map((opt) {
              final (s, icon, label, desc) = opt;
              final isSel = structure == s;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () => setSt(() {
                    structure = s;
                    // Resetear anchor si cambia a otro modo
                    if (s != BetStructure.anchorVsMany) anchorPlayerId = null;
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: isSel ? t.primary.withValues(alpha: 0.10) : t.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isSel ? t.primary : t.divider, width: isSel ? 1.5 : 1),
                    ),
                    child: Row(children: [
                      Text(icon, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(label, style: TextStyle(color: isSel ? t.primary : t.text, fontWeight: FontWeight.w700, fontSize: 13)),
                        Text(desc,  style: TextStyle(color: t.sub, fontSize: 11)),
                      ])),
                      if (isSel) Icon(Icons.check_circle, color: t.primary, size: 18)
                      else       Icon(Icons.radio_button_unchecked, color: t.divider, size: 18),
                    ]),
                  ),
                ),
              );
            }),

            // ── Selector de ancla (solo anchorVsMany) ───────────────────────
            if (structure == BetStructure.anchorVsMany) ...[
              const SizedBox(height: 12),
              Text('JUGADOR ANCLA', style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: _players
                  .where((p) => pids.contains(p.id))
                  .map((p) {
                    final sel = anchorPlayerId == p.id;
                    return GestureDetector(
                      onTap: () => setSt(() => anchorPlayerId = sel ? null : p.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: sel ? t.accent.withValues(alpha: 0.15) : t.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: sel ? t.accent : t.divider, width: sel ? 1.5 : 1),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (sel) ...[Icon(Icons.anchor, color: t.accent, size: 13), const SizedBox(width: 4)],
                          Text(p.name, style: TextStyle(color: sel ? t.accent : t.text, fontWeight: FontWeight.w600, fontSize: 13)),
                        ]),
                      ),
                    );
                  }).toList()),
            ],

            // ── Error de validación ─────────────────────────────────────────
            if (validErr != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: t.danger.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: t.danger.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  Icon(Icons.warning_amber_rounded, color: t.danger, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(validErr, style: TextStyle(color: t.danger, fontSize: 12))),
                ]),
              ),
            ],

            // ── Resumen / preview ───────────────────────────────────────────
            if (canConfirm && preview.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: t.primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: t.primary.withValues(alpha: 0.2)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.info_outline, color: t.primary, size: 14),
                    const SizedBox(width: 6),
                    Expanded(child: Text(preview,
                        style: TextStyle(color: t.primary, fontSize: 12, fontWeight: FontWeight.w700))),
                  ]),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(detail, style: TextStyle(color: t.sub, fontSize: 11)),
                  ],
                ]),
              ),
            ],

            // ── Botón confirmar ─────────────────────────────────────────────
            const SizedBox(height: 16),
            GPrimaryButton(
              label: selected.isEmpty
                  ? 'Selecciona al menos un tipo'
                  : !canConfirm
                      ? 'Corrige los errores'
                      : preview.isNotEmpty ? preview : 'Agregar apuesta',
              onTap: canConfirm ? () {
                final grpId   = 'grp_${DateTime.now().millisecondsSinceEpoch}';
                final grpName = '${selected.map((bt) => bt.label).join(' + ')} '
                    '— ${_structureLabelShort(structure)}';
                final startIdx = _groups[gi].modules.length;
                setState(() {
                  final mods = List<BetModuleInstance>.from(_groups[gi].modules);
                  for (final bt in selected) {
                    try {
                      final expanded = BetModuleInstance.expandBetModules(
                        type: bt,
                        structure: structure,
                        participantIds: g.playerIds,
                        anchorPlayerId: anchorPlayerId,
                        betGroupId:    structure == BetStructure.anchorVsMany || structure == BetStructure.roundRobin ? grpId : null,
                        betGroupName:  structure == BetStructure.anchorVsMany || structure == BetStructure.roundRobin ? grpName : null,
                      );
                      mods.addAll(expanded);
                    } catch (_) {
                      // Fallback graceful: añadir módulo básico
                      mods.add(BetModuleInstance.defaultFor(bt, g.playerIds));
                    }
                  }
                  _groups[gi] = _groups[gi].copyWith(modules: mods);
                });
                Navigator.pop(ctx2);
                // Abrir editor solo si se creó exactamente 1 módulo
                final newGroup = _groups[gi];
                if (newGroup.modules.length == startIdx + 1) {
                  final newMod = newGroup.modules[startIdx];
                  Future.delayed(const Duration(milliseconds: 220), () {
                    if (!mounted) return;
                    // Los formatos por equipos van al editor que sabe armar
                    // lados. _editModuleInstance no los ofrece, así que
                    // guardar desde ahí dejaba la apuesta SIN equipos: no
                    // liquidaba nada y en pantalla se veía bien configurada.
                    if (newMod.type.requiresTeams) {
                      _openModuleEdit(context, newGroup, newMod, t);
                    } else {
                      _editModuleInstance(gi, startIdx, newMod, newGroup, t);
                    }
                  });
                }
              } : null,
            ),
          ])),
        );
      }),
    );
  }

  /// Opciones de estructura disponibles según el número de jugadores del grupo.
  List<(BetStructure, String, String, String)> _structureOptions(int playerCount) => [
    (BetStructure.group,       '👥', 'Grupo único',         'Un pot para todos los jugadores'),
    if (playerCount == 2)
      (BetStructure.headToHead, '⚔️', 'Head to head',        '1 vs 1, exactamente 2 jugadores'),
    (BetStructure.anchorVsMany,'🎯', 'Jugador vs varios',   'Un ancla enfrenta a cada rival por separado'),
    (BetStructure.roundRobin,  '🔄', 'Todos contra todos',  'Un duelo por cada combinación de jugadores'),
  ];

  String _structureLabelShort(BetStructure s) => switch (s) {
    BetStructure.group       => 'Grupo',
    BetStructure.headToHead  => '1v1',
    BetStructure.anchorVsMany=> 'Ancla vs varios',
    BetStructure.roundRobin  => 'Todos vs todos',
    BetStructure.manual      => 'Manual',
  };

  Widget _betTypeTile(BetModuleType bt, Set<BetModuleType> selected, StateSetter setSt, GolfTheme t) {
    final isSel = selected.contains(bt);
    // Colores especiales para Match types
    final isMatchType = bt == BetModuleType.nassau || bt == BetModuleType.matchAutoPress;
    final accentColor = isMatchType ? t.accent : t.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => setSt(() { if (isSel) {
          selected.remove(bt);
        } else {
          selected.add(bt);
        } }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSel ? accentColor.withValues(alpha: 0.1) : t.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSel ? accentColor : t.divider, width: isSel ? 1.5 : 1),
          ),
          child: Row(children: [
            Text(bt.icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(bt.label, style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14)),
              Text(bt.description, style: TextStyle(color: t.sub, fontSize: 11)),
            ])),
            if (isSel) Icon(Icons.check_circle, color: accentColor, size: 20)
            else Icon(Icons.add_circle_outline, color: t.sub, size: 20),
          ]),
        ),
      ),
    );
  }

  // ── STEP 3: Revisión ─────────────────────────────────────────────────────
  Widget _stepReview(GolfTheme t) {
    final allPids = _players.map((p) => p.id).toList();
    final effectiveGroups = _groups.isEmpty
        ? [BetGroup(
            id: 'auto', name: 'Partida Principal', format: PartidaFormat.allInOnePot,
            playerIds: allPids,
            // Nassau requiere 2+ jugadores; con 1 o 0 se deja sin módulos
            modules: allPids.length >= 2
                ? [BetModuleInstance.defaultFor(BetModuleType.nassau, allPids)]
                : [],
          )]
        : _groups;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Selector de duración de ronda ──────────────────────────────────
        GSectionHeader(title: 'DURACIÓN DE LA RONDA'),
        GCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.flag_outlined, color: t.primary, size: 16),
            const SizedBox(width: 8),
            Text('Número de hoyos', style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
          const SizedBox(height: 4),
          Text(
            _totalHoles == 9
                ? 'Ronda corta · solo se juegan los primeros 9 hoyos'
                : 'Ronda completa · se juegan los 18 hoyos',
            style: TextStyle(color: t.sub, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _totalHoles = 9),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: _totalHoles == 9 ? t.primary : t.card,
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
                    border: Border.all(
                      color: _totalHoles == 9 ? t.primary : t.divider,
                      width: _totalHoles == 9 ? 2 : 1,
                    ),
                  ),
                  child: Column(children: [
                    Text('9', style: TextStyle(
                      color: _totalHoles == 9 ? t.onPrimary : t.text,
                      fontWeight: FontWeight.w900, fontSize: 22,
                    )),
                    Text('hoyos', style: TextStyle(
                      color: _totalHoles == 9 ? t.onPrimary.withValues(alpha: 0.85) : t.sub,
                      fontSize: 11, fontWeight: FontWeight.w600,
                    )),
                  ]),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _totalHoles = 18),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: _totalHoles == 18 ? t.primary : t.card,
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)),
                    border: Border.all(
                      color: _totalHoles == 18 ? t.primary : t.divider,
                      width: _totalHoles == 18 ? 2 : 1,
                    ),
                  ),
                  child: Column(children: [
                    Text('18', style: TextStyle(
                      color: _totalHoles == 18 ? t.onPrimary : t.text,
                      fontWeight: FontWeight.w900, fontSize: 22,
                    )),
                    Text('hoyos', style: TextStyle(
                      color: _totalHoles == 18 ? t.onPrimary.withValues(alpha: 0.85) : t.sub,
                      fontSize: 11, fontWeight: FontWeight.w600,
                    )),
                  ]),
                ),
              ),
            ),
          ]),
        ])),
        const SizedBox(height: 16),
        GCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.golf_course, color: t.primary, size: 18), const SizedBox(width: 8),
            Text(_nameCtrl.text, style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 16))]),
          const SizedBox(height: 4),
          if (_selectedCourse != null) Text(_selectedCourse!.name, style: TextStyle(color: t.accent, fontSize: 12)),
          Text(
            _players.isEmpty
                ? 'Solo invitados · ${effectiveGroups.length} partidas · $_totalHoles hoyos'
                : '${_players.length} jugador${_players.length == 1 ? "" : "es"} · ${effectiveGroups.length} partidas · $_totalHoles hoyos',
            style: TextStyle(color: t.sub, fontSize: 13),
          ),
        ])),
        const SizedBox(height: 16),
        // Jugadores con tees y HCP de juego
        if (_selectedApiCourse != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: t.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.primary.withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                Icon(Icons.info_outline, color: t.primary, size: 14),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  'Toca el chip de salida para cambiarla antes de iniciar.',
                  style: TextStyle(color: t.primary, fontSize: 11),
                )),
              ]),
            ),
          ),
        GSectionHeader(title: 'JUGADORES'),
        ..._players.map((p) {
          final tee = _teeOf(p.id);
          final phcp = _playingHcp(p);
          final hasTee = _selectedApiCourse != null && _selectedApiCourse!.allTees.isNotEmpty;
          final teeColor = tee.gender == 'F' ? t.accent : t.primary;
          final isStdTee = tee.name == TeeInfo.standard.name;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                GAvatar(name: p.name, colorIndex: p.colorIndex, size: 28),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.name, style: TextStyle(color: t.text, fontWeight: FontWeight.w700)),
                  Text('HCP Index ${p.handicapBase.toStringAsFixed(1)}', style: TextStyle(color: t.sub, fontSize: 11)),
                ])),
              ]),
              if (hasTee) ...[
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => _pickTee(p, t),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isStdTee
                          ? t.accent.withValues(alpha: 0.07)
                          : teeColor.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: isStdTee
                            ? t.accent.withValues(alpha: 0.3)
                            : teeColor.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(children: [
                      Icon(Icons.flag, color: isStdTee ? t.accent : teeColor, size: 12),
                      const SizedBox(width: 5),
                      Text(
                        'Salida ${tee.name}${tee.gender == "F" ? " (F)" : tee.gender == "M" ? " (M)" : ""}',
                        style: TextStyle(
                          color: isStdTee ? t.accent : teeColor,
                          fontSize: 11, fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('HCPj ${phcp.toStringAsFixed(0)}',
                          style: TextStyle(color: t.sub, fontSize: 11, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text('Cambiar', style: TextStyle(color: t.sub, fontSize: 10)),
                      const SizedBox(width: 2),
                      Icon(Icons.chevron_right, color: t.sub, size: 12),
                    ]),
                  ),
                ),
              ],
            ])),
          );
        }),
        const SizedBox(height: 16),
        // ── VENTAJAS (editables) ──────────────────────────────────────────
        if (_players.length >= 2) ...[
          Row(children: [
            Expanded(child: GSectionHeader(title: 'VENTAJAS')),
            GestureDetector(
              onTap: () => setState(() => _current = SetupStep.jugadores),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: t.accent.withValues(alpha: 0.35)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.edit_outlined, color: t.accent, size: 12),
                  const SizedBox(width: 4),
                  Text('Editar', style: TextStyle(color: t.accent, fontSize: 11, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          _HandicapMatrix(
            players: _players,
            playerTees: _playerTees,
            manualHandicaps: _manualHandicaps,
            playingHcp: _playingHcp,
            onEdit: (p1, p2, val) => setState(() {
              _manualHandicaps.putIfAbsent(p1, () => {});
              _manualHandicaps.putIfAbsent(p2, () => {});
              if (val == null) {
                _manualHandicaps[p1]!.remove(p2);
                _manualHandicaps[p2]!.remove(p1);
                _pairSliding.remove(BetEngine.pairKey(p1, p2));
              } else {
                _manualHandicaps[p1]![p2] = val;
                _manualHandicaps[p2]![p1] = -val;
                final lowId = p1.compareTo(p2) <= 0 ? p1 : p2;
                final key = BetEngine.pairKey(p1, p2);
                _pairSliding[key] = (p1 == lowId) ? val : -val;
              }
            }),
            t: t,
          ),
          const SizedBox(height: 16),
        ],
      ]),
    );
  }

  void _openModuleEdit(BuildContext context, BetGroup group, BetModuleInstance mod, GolfTheme t) {
    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => BetModuleEditSheet(
        group: group,
        mod: mod,
        t: t,
        courseInfo: _selectedCourse,
        players: _players,
        onSave: (updatedMod) {
          setState(() {
            final idx = _groups.indexWhere((g) => g.id == group.id);
            if (idx >= 0) {
              _groups[idx] = BetGroup(
                id: group.id, name: group.name, format: group.format,
                playerIds: group.playerIds,
                modules: group.modules.map((m) => m.id == updatedMod.id ? updatedMod : m).toList(),
              );
            }
          });
        },
      ),
    );
  }

  void _launchRound(BuildContext ctx) {
    final t = context.read<RoundProvider>().theme;
    final auth = context.read<AuthProvider>();

    // Última red antes de jugar: una apuesta por equipos SIN equipos no liquida
    // nada, y el fallo solo se descubre al terminar la ronda —con el dinero ya
    // jugado y sin forma de recuperar el resultado. Se corta aquí.
    final sinEquipos = [
      for (final g in _groups)
        for (final m in g.modules)
          if (m.type.requiresTeams && !m.hasTeamSides) '${g.name} · ${m.type.label}',
    ];
    if (sinEquipos.isNotEmpty) {
      showDialog(
        context: ctx,
        builder: (dctx) => AlertDialog(
          backgroundColor: t.card,
          title: Row(children: [
            Icon(Icons.warning_amber_rounded, color: t.danger, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Falta definir equipos',
                  style: TextStyle(
                      color: t.text, fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sinEquipos.length == 1
                    ? 'Esta apuesta es 2 vs 2 y no tiene equipos, así que no '
                        'cobraría nada:'
                    : 'Estas apuestas son 2 vs 2 y no tienen equipos, así que '
                        'no cobrarían nada:',
                style: TextStyle(color: t.sub, fontSize: 12, height: 1.35),
              ),
              const SizedBox(height: 10),
              ...sinEquipos.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('· $e',
                        style: TextStyle(
                            color: t.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  )),
              const SizedBox(height: 10),
              Text(
                'Tócala en la tarjeta de su partida para armar el Lado A y el '
                'Lado B.',
                style: TextStyle(color: t.sub, fontSize: 11, height: 1.35),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: Text('Entendido', style: TextStyle(color: t.primary)),
            ),
          ],
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: ctx,
      backgroundColor: t.card,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => _LaunchSheet(
        t: t,
        isAuth: auth.isAuth,
        players: _players,
        groups: _groups,
        onStart: (startingNine, {bool startLive = false, String scoringMode = 'open'}) {
          Navigator.pop(sheetCtx);
          _createAndStartRound(startingNine, startLive: startLive, scoringMode: scoringMode);
        },
        onStartWithTemplate: (startingNine, name, emoji, desc, {bool startLive = false, String scoringMode = 'open'}) {
          Navigator.pop(sheetCtx);
          _createAndStartRound(startingNine, startLive: startLive, scoringMode: scoringMode);
          // Guardar plantilla tras iniciar ronda
          _saveTemplateNow(name: name, emoji: emoji, desc: desc);
        },
      ),
    );
  }

  Future<void> _saveTemplateNow({
    required String name,
    required String emoji,
    required String desc,
  }) async {
    try {
      final template = RoundTemplate(
        id: '',
        name: name,
        emoji: emoji,
        description: desc,
        playerNames: _players.map((p) => p.name).toList(),
        betGroupsJson: _groups.map((g) => g.toJson()).toList(),
        updatedAt: DateTime.now(),
      );
      await FirestoreService.saveTemplate(template);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ Plantilla "$name" guardada'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo guardar la plantilla: $e'),
          backgroundColor: Colors.orange,
        ));
      }
    }
  }

  /// Muestra un bottom-sheet para elegir la salida preferida de un campo favorito.
  /// Guarda la preferencia en Firestore y actualiza localmente el tee asignado si
  /// ese campo ya está seleccionado en la ronda actual.
  void _showFavTeeSelector(BuildContext context, FavoriteCourse fav, GolfTheme t) {
    // Usar los tees del campo actualmente seleccionado (corrección global o API)
    final course = _selectedApiCourse?.id == fav.courseId
        ? _selectedApiCourse!
        : null;
    // Si el campo no está seleccionado aún, no hay tees disponibles
    if (course == null || course.allTees.isEmpty) return;
    String? pickedName = fav.preferredTeeName;

    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(builder: (ctx, setSt) {
        void saveTee(String name) {
          setSt(() => pickedName = name);
          // Persistir en Firestore
          context.read<UserProfileProvider>().updateFavCourseTee(fav.courseId, name);
          // Si el campo ya está seleccionado, reasignar tees con la nueva preferencia
          final isCurrentCourse =
              _selectedApiCourse?.id == fav.courseId;
          if (isCurrentCourse) {
            setState(() {
              for (final p in _players) {
                _playerTees[p.id] = _teeByName(name) ?? _playerTees[p.id] ?? _defaultMaleTee ?? TeeInfo.standard;
              }
            });
          }
          Navigator.pop(ctx);
        }

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            left: 20, right: 20, top: 24,
          ),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Título
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Salida favorita', style: TextStyle(color: t.text, fontSize: 17, fontWeight: FontWeight.w800)),
                Text(fav.displayName, style: TextStyle(color: t.sub, fontSize: 12)),
              ])),
              GestureDetector(onTap: () => Navigator.pop(ctx), child: Icon(Icons.close, color: t.sub)),
            ]),
            const SizedBox(height: 6),
            Text('Elige tu salida preferida. Se usará cada vez que selecciones este campo.',
                style: TextStyle(color: t.sub, fontSize: 12)),
            const SizedBox(height: 16),

            // Tees masculinos
            if (course.maleTees.isNotEmpty) ...[
              Align(alignment: Alignment.centerLeft,
                child: Text('TEEs MASCULINOS', style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8))),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: course.maleTees.map((tee) {
                final isSelected = pickedName == tee.teeName;
                return GestureDetector(
                  onTap: () => saveTee(tee.teeName),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? t.primary.withValues(alpha: 0.12) : t.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isSelected ? t.primary : t.divider, width: isSelected ? 2 : 1),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        if (isSelected) ...[
                          Icon(Icons.check_circle_rounded, color: t.primary, size: 14),
                          const SizedBox(width: 4),
                        ],
                        Text(tee.teeName, style: TextStyle(color: isSelected ? t.primary : t.text, fontWeight: FontWeight.w700, fontSize: 14)),
                      ]),
                      Text('CR ${tee.courseRating.toStringAsFixed(1)} / Slope ${tee.slopeRating}',
                          style: TextStyle(color: isSelected ? t.primary.withValues(alpha: 0.7) : t.sub, fontSize: 10)),
                    ]),
                  ),
                );
              }).toList()),
            ],

            // Tees femeninos
            if (course.femaleTees.isNotEmpty) ...[
              const SizedBox(height: 14),
              Align(alignment: Alignment.centerLeft,
                child: Text('TEEs FEMENINOS', style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8))),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: course.femaleTees.map((tee) {
                final isSelected = pickedName == tee.teeName;
                return GestureDetector(
                  onTap: () => saveTee(tee.teeName),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? t.accent.withValues(alpha: 0.12) : t.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isSelected ? t.accent : t.divider, width: isSelected ? 2 : 1),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        if (isSelected) ...[
                          Icon(Icons.check_circle_rounded, color: t.accent, size: 14),
                          const SizedBox(width: 4),
                        ],
                        Text(tee.teeName, style: TextStyle(color: isSelected ? t.accent : t.text, fontWeight: FontWeight.w700, fontSize: 14)),
                      ]),
                      Text('CR ${tee.courseRating.toStringAsFixed(1)} / Slope ${tee.slopeRating}',
                          style: TextStyle(color: isSelected ? t.accent.withValues(alpha: 0.7) : t.sub, fontSize: 10)),
                    ]),
                  ),
                );
              }).toList()),
            ],
            const SizedBox(height: 8),
          ])),
        );
      }),
    );
  }

  /// Selecciona un campo favorito.
  ///
  /// Prioridad de datos (de mayor a menor):
  ///   1. Corrección global en courseCorrections/{courseId}  ← fuente de verdad del CAMPO
  ///   2. Llamada fresca a la API
  ///   3. Placeholder con nombre mientras carga
  ///
  /// NUNCA depende de manuallyEdited ni del cachedCourse del usuario.
  /// La corrección aplica igual para todos los usuarios sin configuración por persona.
  Future<void> _selectFavCourseWithFresh(FavoriteCourse fav) async {
    if (_loadingFavId != null) return; // evitar doble tap

    // Mostrar loading + placeholder inmediato
    setState(() {
      _pendingCorrection = null;
      _loadingFavId = fav.courseId;
      _selectedCourse = CourseInfo(name: fav.fullName, holes: CourseInfo.standard.holes);
      _selectedApiCourse = null;
      _playerTees.clear();
    });

    if (fav.courseId.isEmpty) {
      setState(() => _loadingFavId = null);
      return;
    }

    try {
      // ── PASO 1: Corrección global del campo ──────────────────────────────────
      // Vive en courseCorrections/{courseId} — aplica para TODOS los usuarios.
      final correction = await CourseCorrectionsService.getForCourse(fav.courseId);
      if (correction != null && mounted) {
        final correctedApi = correction.correctedCourse;
        setState(() {
          _loadingFavId = null;
          _playerTees.clear();
          _selectedApiCourse = correctedApi;
          _selectedCourse = correctedApi.allTees.first
              .toCourseInfo(correctedApi.clubName, correctedApi.courseName);
          _autoAssignDefaultTee(preferredTeeName: fav.preferredTeeName);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(children: [
              const Icon(Icons.verified_rounded, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text('${correctedApi.clubName}: datos oficiales corregidos')),
            ]),
            backgroundColor: const Color(0xFF34C759),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ));
        }
        return;
      }

      // ── PASO 2: cachedCourse del favorito (fallback antes de API) ────────────
      // Solo se usa si el ID en caché ya es alfanumérico (formato nuevo).
      // Si el ID es numérico legacy, saltamos al PASO 3 para migrar el favorito.
      final cachedIsValid = fav.hasCachedData &&
          fav.cachedCourse!.id.isNotEmpty &&
          int.tryParse(fav.cachedCourse!.id) == null; // null → no es numérico → válido
      if (cachedIsValid && mounted) {
        debugPrint('[Setup] Usando cachedCourse del favorito para ${fav.courseId}');
        final cached = fav.cachedCourse!;
        setState(() {
          _loadingFavId = null;
          _playerTees.clear();
          _selectedApiCourse = cached;
          _selectedCourse = cached.allTees.first
              .toCourseInfo(cached.clubName, cached.courseName);
          _autoAssignDefaultTee(preferredTeeName: fav.preferredTeeName);
        });
        return;
      }

      // ── PASO 3: API fresca (último recurso) ──────────────────────────────────
      debugPrint('[Setup] Sin corrección ni caché para ${fav.courseId}, usando API externa');
      // Pasar fallbackName: si el ID numérico legacy devuelve 404, la API buscará
      // por nombre del club y retornará el campo con el nuevo ID alfanumérico.
      final fresh = await GolfCourseService.getById(
        fav.courseId,
        fallbackName: fav.clubName,
      );
      if (!mounted) return;

      // ── Migración automática de ID legacy ────────────────────────────────────
      // Si el campo volvió con un ID diferente al guardado, el favorito en Firestore
      // tiene un ID numérico obsoleto. Migrar silenciosamente al nuevo ID.
      if (fresh.id != fav.courseId) {
        debugPrint('[Setup] Migrando favorito ${fav.courseId} → ${fresh.id}');
        UserProfileService.migrateFavCourseId(
          oldId:       fav.courseId,
          newId:       fresh.id,
          freshCourse: fresh,
        ); // fire-and-forget: no await para no bloquear la UI
      } else {
        // Misma ID → solo actualizar el cachedCourse
        UserProfileService.updateFavCourseCache(fav.courseId, fresh);
      }

      setState(() {
        _loadingFavId = null;
        _playerTees.clear();
        _selectedApiCourse = fresh;
        if (fresh.allTees.isNotEmpty) {
          _selectedCourse = fresh.allTees.first
              .toCourseInfo(fresh.clubName, fresh.courseName);
        }
        _autoAssignDefaultTee(preferredTeeName: fav.preferredTeeName);
      });

    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingFavId = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error al cargar el campo: $e'),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  /// Aplica la corrección pendiente al caché del usuario y actualiza la UI.
  Future<void> _applyPendingCorrection() async {
    // Con el nuevo diseño, la corrección ya se aplica automáticamente en
    // _selectFavCourseWithFresh. Este método solo aplica si hubiera una
    // corrección pendiente del banner (flujo legacy).
    final correction = _pendingCorrection;
    if (correction == null) return;

    final course = correction.correctedCourse;
    setState(() {
      _playerTees.clear();
      _selectedApiCourse = course;
      _selectedCourse = course.allTees.isNotEmpty
          ? course.allTees.first.toCourseInfo(course.clubName, course.courseName)
          : _selectedCourse;
      _pendingCorrection = null;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('✅ Datos del campo actualizados correctamente'),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 3),
      ));
    }
  }

  void _openCoursePicker(GolfTheme t) {
    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => CoursePickerSheet(
        t: t,
        onSelected: (courseInfo, apiCourse) => setState(() {
          // Limpiar tees del campo anterior al seleccionar uno nuevo
          _playerTees.clear();
          _selectedCourse = courseInfo;
          _selectedApiCourse = apiCourse;
          _autoAssignDefaultTee(); // ← auto-asignar tee del nuevo campo
        }),
      ),
    );
  }

  void _createAndStartRound(StartingNine startingNine, {bool startLive = false, String scoringMode = 'open'}) {
    final allPidsLaunch = _players.map((p) => p.id).toList();

    // ─────────────────────────────────────────────────────────────────────────
    // PASO 0: bajar al modelo la decisión de ronda —quiénes compiten y qué bola—
    //
    // _porEquipos y _bola solo decidían qué PANTALLAS se veían. El paso "Bola"
    // aparecía en la barra, se elegía una, y la ronda se creaba individual
    // igualmente: el módulo salía sin lados y sin playMode. La parte visible
    // funcionando y la que resuelve el problema sin conectar.
    //
    // Se aplica aquí, en un único sitio por el que pasa toda ronda, en vez de
    // en cada punto donde se crea o edita un módulo: esos son varios y basta
    // olvidar uno para reproducir el mismo fallo.
    //
    // conEquiposDeRonda respeta los lados configurados a mano, así que aplicar
    // siempre no pisa nada.
    // ─────────────────────────────────────────────────────────────────────────
    // El grupo por defecto se materializa AQUÍ, no en PASO 3.
    //
    // Estaba creado dentro de effectiveGroups, o sea después de aplicar los
    // equipos y después de escanear los lados para crear los virtuales. Un
    // grupo nacido ahí no podía recibir ninguna de las dos cosas: salía sin
    // lados, sin playMode y sin jugador virtual, en silencio.
    //
    // Es la misma pregunta de siempre —¿pasan todos por el mismo sitio?—
    // aplicada a quién CREA módulos, no a quién los lee.
    if (_groups.isEmpty) {
      _groups.add(BetGroup(
        id: _uuid.v4(), name: 'Partida Principal',
        format: PartidaFormat.allInOnePot,
        playerIds: allPidsLaunch,
        modules: allPidsLaunch.length >= 2
            ? [BetModuleInstance.defaultFor(BetModuleType.nassau, allPidsLaunch)]
            : <BetModuleInstance>[],
      ));
    }

    if (_porEquipos) {
      for (var g = 0; g < _groups.length; g++) {
        _groups[g] = _groups[g].copyWith(
          modules: _groups[g].modules
              .map((m) => BetRecipe.conEquiposDeRonda(m,
                  porEquipos: true,
                  equipoA: _teamA,
                  equipoB: _teamB,
                  bola: _bola,
                  submodo: _submodo))
              .toList(),
        );
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PASO 1: Escanear módulos con sides → crear virtuales para Scramble y Best Ball
    // ─────────────────────────────────────────────────────────────────────────
    final virtualPlayers    = <Player>[];
    final scrambleTeamIds   = <String>{};
    final sideIdToVirtualId = <String, String>{};  // Scramble sideId → virtualId
    final sideIdToBBTeamId  = <String, String>{};  // BestBall sideId → bbTeamId
    final virtualPlayerTees = <String, TeeInfo>{}; // virtualId → tee

    for (final group in (_groups.isEmpty ? [] : _groups)) {
      for (final mod in group.modules) {
        if (mod.sides == null || mod.sides!.isEmpty) continue;

        // Bola Baja / Bola Alta necesita los cuatro scores individuales para
        // sacar la bola baja y la alta de cada equipo, así que un jugador
        // virtual de equipo no representa nada: sería una fila más donde
        // capturar un número que el formato no usa y que contradiría a los
        // reales. Los otros formatos por equipos sí lo aprovechan.
        if (mod.type == BetModuleType.nassauLowHigh) continue;

        for (final side in mod.sides!) {
          if (side.playerIds.length < 2) continue;

          final members = _players.where((p) => side.playerIds.contains(p.id)).toList();
          if (members.isEmpty) continue;

          final hcps      = members.map((p) => _teeOf(p.id).playingHandicap(p.handicapBase)).toList()..sort();
          final tees      = members.map((p) => _teeOf(p.id)).toList();
          final hardestTee = tees.reduce((a, b) => a.courseRating > b.courseRating ? a : b);

          // Handicap combinado del equipo según el reparto configurado.
          // NO se aplica aquí el allowance: lo hace el motor una sola vez en
          // GameEngine.buildTeamHcpMap, para no multiplicarlo dos veces.
          // El default de Scramble (50% × 70/30) reproduce el clásico 35/15.
          final thCfg   = mod.teamHandicapConfig ??
              TeamHandicapConfig.defaultFor(side.playMode);
          final teamHcp = thCfg.combinedHandicap(hcps);

          if (side.playMode == TeamPlayMode.scramble) {
            if (sideIdToVirtualId.containsKey(side.id)) continue;
            final virtualId = 'team_${side.id}';
            virtualPlayers.add(Player(
              id: virtualId, name: side.name,
              handicapBase: teamHcp,
              colorIndex: members.first.colorIndex,
              isVirtual: true, teamMemberIds: side.playerIds,
            ));
            scrambleTeamIds.addAll(side.playerIds);
            sideIdToVirtualId[side.id] = virtualId;
            virtualPlayerTees[virtualId] = hardestTee;

          } else if (side.playMode == TeamPlayMode.bestBall) {
            if (sideIdToBBTeamId.containsKey(side.id)) continue;
            // Best Ball: jugador virtual de equipo para visualización/apuestas
            // Los reales SIGUEN en la ronda para capturar scores individuales
            final bbTeamId = 'bb_team_${side.id}';
            virtualPlayers.add(Player(
              id: bbTeamId, name: side.name,
              handicapBase: teamHcp,
              colorIndex: members.first.colorIndex,
              isVirtual: true, teamMemberIds: side.playerIds,
            ));
            sideIdToBBTeamId[side.id] = bbTeamId;
            virtualPlayerTees[bbTeamId] = hardestTee;
          }
        }
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PASO 2: Lista de jugadores de la ronda
    //  - Scramble real → excluidos (reemplazados por virtual)
    //  - Best Ball real → incluidos (capturan scores individuales)
    //  - Virtuales     → incluidos (para apuestas y visualización de equipos)
    // ─────────────────────────────────────────────────────────────────────────
    final realPlayersNotInScramble = _players.where((p) => !scrambleTeamIds.contains(p.id)).toList();
    final allPlayersForRound = [...realPlayersNotInScramble, ...virtualPlayers];
    // Lista completa (incluye reales de Scramble) para guardar referencias de nombres
    final allPlayersIncludingScrambleMembers = [..._players, ...virtualPlayers];

    // ─────────────────────────────────────────────────────────────────────────
    // PASO 3: Actualizar grupos — participantIds usan IDs virtuales
    // ─────────────────────────────────────────────────────────────────────────
    // _groups ya no puede estar vacío: el grupo por defecto se materializa en
    // PASO 0, para que reciba equipos y virtuales como cualquier otro.
    final effectiveGroups = _groups.map((group) {

      // playerIds del grupo: quitar reales de Scramble, agregar todos los virtuales
      final updatedGroupPlayerIds = group.playerIds
          .where((pid) => !scrambleTeamIds.contains(pid))
          .toList();
      final groupVirtualIds = <String>{};
      for (final mod in group.modules) {
        if (mod.sides != null) {
          for (final side in mod.sides!) {
            final vId = sideIdToVirtualId[side.id] ?? sideIdToBBTeamId[side.id];
            if (vId != null) groupVirtualIds.add(vId);
          }
        }
      }
      updatedGroupPlayerIds.addAll(groupVirtualIds);

      // participantIds por módulo → un ID por equipo
      final updatedModules = group.modules.map((mod) {
        if (mod.sides == null || mod.sides!.isEmpty) return mod;
        final hasTeamSides = mod.sides!.any((s) =>
            sideIdToVirtualId.containsKey(s.id) || sideIdToBBTeamId.containsKey(s.id));
        if (!hasTeamSides) return mod;

        final newParticipantIds = <String>[];
        // ── Los sides también hay que reescribirlos en Scramble ──────────────
        //
        // En Scramble los jugadores REALES quedan fuera de la ronda: no
        // capturan score, lo hace el jugador virtual del equipo. Si el side
        // conservara los IDs reales, el motor buscaría scores que no existen,
        // daría todos los hoyos por no jugados y la apuesta NO PAGARÍA NADA.
        //
        // En Best Ball es al revés: los reales SÍ capturan y el best-ball se
        // calcula sobre sus scores, así que el side conserva los IDs reales.
        final newSides = <BetSide>[];
        for (final side in mod.sides!) {
          final scrambleVirtual = sideIdToVirtualId[side.id];
          if (scrambleVirtual != null) {
            newParticipantIds.add(scrambleVirtual);
            newSides.add(BetSide(
              id:        side.id,
              name:      side.name,
              playerIds: [scrambleVirtual],
              playMode:  side.playMode,
            ));
          } else if (sideIdToBBTeamId.containsKey(side.id)) {
            newParticipantIds.add(sideIdToBBTeamId[side.id]!);
            newSides.add(side); // Best Ball: se juega con los scores reales
          } else {
            newParticipantIds.addAll(side.playerIds);
            newSides.add(side);
          }
        }
        return mod.copyWith(participantIds: newParticipantIds, sides: newSides);
      }).toList();

      // ── Declarar el alcance de cada módulo ──────────────────────────────────
      // Un módulo cuyos participantes son EXACTAMENTE toda la partida se marca
      // con alcance `everyone`, así sus participantes se resuelven en cada
      // cálculo contra los jugadores presentes. Consecuencia: si más tarde se
      // suma un jugador a la partida, entra solo en esas apuestas sin tener que
      // reconfigurar nada.
      //
      // Los módulos de equipo y los de subconjunto/duelo conservan su alcance
      // fijo — ahí la lista de jugadores sí es parte del acuerdo.
      final groupIdSet = updatedGroupPlayerIds.toSet();
      final scopedModules = updatedModules.map((mod) {
        if (mod.scope != null) return mod;          // ya declarado
        if (mod.hasTeamSides) {
          // Además del alcance, dejar declarado el allowance por defecto del
          // formato (Four-Ball 90% / Scramble 50%×70-30). Las rondas ya
          // guardadas se quedan sin la clave → legacy 100%.
          return mod.copyWith(
            scope: const BetScope.teams(),
            teamHandicapConfig: mod.teamHandicapConfig ??
                TeamHandicapConfig.defaultFor(mod.sideA.playMode),
          );
        }
        final pids = mod.participantIds;
        final coversWholeGroup = pids.isEmpty ||
            (pids.length == groupIdSet.length && pids.toSet().containsAll(groupIdSet));
        return mod.copyWith(
          scope: coversWholeGroup
              ? const BetScope.everyone()
              : (pids.length == 2
                  ? BetScope.pair(pids[0], pids[1])
                  : BetScope.subset(pids)),
        );
      }).toList();

      return group.copyWith(modules: scopedModules, playerIds: updatedGroupPlayerIds);
    }).toList();

    final roundPlayers = allPlayersForRound.map((p) {
      // Para jugadores virtuales, usar el tee guardado; para reales, _teeOf(p.id)
      final tee = p.isVirtual ? (virtualPlayerTees[p.id] ?? TeeInfo.standard) : _teeOf(p.id);
      final phcp = p.isVirtual ? p.handicapBase : tee.playingHandicap(p.handicapBase);
      final manual = Map<String, double>.from(_manualHandicaps[p.id] ?? {});
      return RoundPlayer(
        playerId: p.id,
        handicapEnRonda: phcp,
        tee: tee,
        manualHandicaps: manual,
      );
    }).toList();

    // Auto-identificar al creador: si el usuario está autenticado,
    // vinculamos automáticamente su UID al primer jugador de la lista
    // (convención: el creador es quien agrega la ronda).
    final creatorUid = AuthService.uid;
    
    final linkedPlayers = allPlayersIncludingScrambleMembers.map((p) {
      // Si el jugador ya tiene linkedUserId, respetar; si es el primero y no tiene, vincular.
      // No vincular jugadores virtuales
      if (!p.isVirtual && p.linkedUserId == null && creatorUid != null && p == _players.first) {
        return p.copyWith(linkedUserId: creatorUid);
      }
      return p;
    }).toList();

    // ── pairSliding canónico: usar _pairSliding (mantenido en tiempo real) ────
    // _pairSliding se actualiza en cada llamada a onEdit de _HandicapMatrix
    // y en _applyDefaultSliding. Contiene exactamente UN valor por par,
    // con clave '$lowId|$highId' (IDs ordenados lexicográficamente).
    // Filtrar solo pares donde ambos jugadores están en la ronda.
    final roundPlayerIds = allPlayersForRound.map((p) => p.id).toSet();
    final pairSlidingMap = Map<String, double>.fromEntries(
      _pairSliding.entries.where((e) {
        final parts = e.key.split('|');
        return parts.length == 2 &&
            roundPlayerIds.contains(parts[0]) &&
            roundPlayerIds.contains(parts[1]);
      }),
    );

    final round = Round(
      id: _uuid.v4(),
      name: _nameCtrl.text.trim().isEmpty ? 'Ronda Golf' : _nameCtrl.text.trim(),
      course: _selectedCourse ?? CourseInfo.standard,
      players: linkedPlayers,
      roundPlayers: roundPlayers,
      betGroups: effectiveGroups,
      // Inicializar scores para todos los jugadores que necesitan capturar scores:
      // - Jugadores reales no-Scramble
      // - Jugadores reales de Best Ball (todos los del equipo)
      // - Jugadores virtuales de Scramble
      scores: {for (final p in allPlayersForRound) p.id: {}},
      events: {for (final p in allPlayersForRound) p.id: {}},
      oyeseRankings: {},
      sliding: [],
      createdAt: DateTime.now(),
      startingNine: startingNine,
      totalHoles: _totalHoles,
      ownerUid: creatorUid,
      scoringMode: startLive ? scoringMode : 'open',
      pairSliding: pairSlidingMap,
    );

    if (startLive) {
      // Primero iniciar la ronda localmente, luego publicar en vivo
      final prov = context.read<RoundProvider>();
      prov.startRound(round);
      Navigator.of(context).pop();
      // Publicar como ronda en vivo (async, sin bloquear UI)
      prov.publishAsLive().then((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('¡Ronda en vivo activada! Código: ${prov.round?.liveCode ?? ''}'),
            backgroundColor: prov.theme.primary,
            duration: const Duration(seconds: 4),
          ));
        }
      }).catchError((e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error al activar en vivo: $e'),
          ));
        }
      });
    } else {
      context.read<RoundProvider>().startRound(round);
      Navigator.of(context).pop();
    }
  }
}

// ── Barra de pasos ────────────────────────────────────────────────────────────
class _StepBar extends StatelessWidget {
  /// Los pasos que existen en ESTA ronda. La barra se dibuja a partir de la
  /// lista real, no de una constante: si el flujo se acorta, la barra también.
  /// Con una lista fija el usuario vería un punto que nunca se ilumina.
  final List<SetupStep> steps;
  final int index;
  final GolfTheme t;
  const _StepBar({required this.steps, required this.index, required this.t});

  @override
  Widget build(BuildContext context) {
    final labels = steps.map(setupStepLabel).toList();
    final step = index;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(bottom: BorderSide(color: t.divider)),
      ),
      child: Row(children: List.generate(labels.length, (i) {
        final active   = i == step;
        final done     = i < step;
        final inactive = i > step;
        return Expanded(child: Row(children: [
          if (i > 0) Expanded(child: Container(height: 1, color: done ? t.primary : t.divider)),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 24, height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? t.primary : done ? t.primary.withValues(alpha: 0.2) : t.surface,
                border: Border.all(
                  color: active || done ? t.primary : t.divider,
                  width: active ? 2 : 1,
                ),
              ),
              child: Center(child: done
                  ? Icon(Icons.check, size: 12, color: t.primary)
                  : Text('${i+1}', style: TextStyle(
                      color: active ? t.onPrimary : inactive ? t.sub : t.primary,
                      fontSize: 10, fontWeight: FontWeight.w800))),
            ),
            const SizedBox(height: 3),
            Text(labels[i], style: TextStyle(
              color: active ? t.primary : done ? t.primary.withValues(alpha: 0.7) : t.sub,
              fontSize: 9, fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            )),
          ]),
          if (i < labels.length - 1) Expanded(child: Container(height: 1, color: done ? t.primary : t.divider)),
        ]));
      })),
    );
  }
}

// ── Matriz de ventajas ───────────────────────────────────────────────────────
/// Muestra un par (A vs B) por fila con selector +/- claro.
/// La ventaja se expresa siempre como "A da X golpes a B" (positivo = A da, negativo = A recibe).
class _HandicapMatrix extends StatelessWidget {
  final List<Player> players;
  final Map<String, TeeInfo> playerTees;
  final Map<String, Map<String, double>> manualHandicaps;
  final double Function(Player) playingHcp;
  final void Function(String p1, String p2, double? val) onEdit;
  final GolfTheme t;

  const _HandicapMatrix({
    required this.players,
    required this.playerTees,
    required this.manualHandicaps,
    required this.playingHcp,
    required this.onEdit,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    if (players.length < 2) return const SizedBox.shrink();

    // Generar todos los pares únicos (i < j)
    final pairs = <(int, int)>[];
    for (int i = 0; i < players.length; i++) {
      for (int j = i + 1; j < players.length; j++) {
        pairs.add((i, j));
      }
    }

    return Column(
      children: pairs.map((pair) {
        final pA = players[pair.$1];
        final pB = players[pair.$2];
        // Ventaja auto (convención unificada con manualHandicaps):
        //   positivo → pA RECIBE de pB (pA tiene mayor HCP)
        //   negativo → pA DA a pB      (pB tiene mayor HCP)
        final autoVal = (playingHcp(pA) - playingHcp(pB)).round();
        // Ventaja manual guardada (desde perspectiva pA→pB)
        final manualVal = manualHandicaps[pA.id]?[pB.id];
        final isManual  = manualVal != null;
        final current   = isManual ? manualVal.round() : autoVal;

        // Quien da golpes y quién recibe
        // CONVENIO: current > 0 → pA recibe golpes de pB (pA tiene mayor HCP)
        //           current < 0 → pB recibe golpes de pA (pB tiene mayor HCP)
        final String giverLabel;
        final String receiverLabel;
        final Color rowColor;
        if (current > 0) {
          // pA recibe strokes de pB
          giverLabel    = '${pB.name.split(' ').first} da $current 🏌️ a ${pA.name.split(' ').first}';
          receiverLabel = '';
          rowColor      = t.profit;
        } else if (current < 0) {
          // pB recibe strokes de pA
          giverLabel    = '${pA.name.split(' ').first} da ${current.abs()} 🏌️ a ${pB.name.split(' ').first}';
          receiverLabel = '';
          rowColor      = t.loss;
        } else {
          giverLabel    = '${pA.name.split(' ').first} vs ${pB.name.split(' ').first}  (igualdad)';
          receiverLabel = '';
          rowColor      = t.sub;
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isManual ? t.accent.withValues(alpha: 0.06) : t.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isManual ? t.accent.withValues(alpha: 0.4) : t.divider,
                width: isManual ? 1.5 : 1,
              ),
            ),
            child: Row(children: [
              // Descripción
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  GAvatar(name: pA.name, colorIndex: pA.colorIndex, size: 20),
                  const SizedBox(width: 4),
                  Text('vs', style: TextStyle(color: t.divider, fontSize: 11)),
                  const SizedBox(width: 4),
                  GAvatar(name: pB.name, colorIndex: pB.colorIndex, size: 20),
                  if (isManual) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: t.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('Manual', style: TextStyle(color: t.accent, fontSize: 9, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ]),
                const SizedBox(height: 3),
                Text(
                  giverLabel + receiverLabel,
                  style: TextStyle(
                    color: current == 0 ? t.sub : rowColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!isManual)
                  Text('Calculado por HCP automático', style: TextStyle(color: t.sub, fontSize: 10)),
              ])),
              // Controles +/-
              Row(children: [
                // Botón −
                GestureDetector(
                  onTap: () => onEdit(pA.id, pB.id, (current - 1).toDouble()),
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: t.sub.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: t.sub.withValues(alpha: 0.3)),
                    ),
                    child: Icon(Icons.remove, color: t.sub, size: 16),
                  ),
                ),
                // Valor central
                GestureDetector(
                  onTap: () => _showEditDialog(context, pA, pB, isManual ? manualVal : null, autoVal),
                  child: Container(
                    width: 44, height: 32,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: isManual ? t.accent.withValues(alpha: 0.1) : t.card,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isManual ? t.accent : t.divider, width: isManual ? 1.5 : 1),
                    ),
                    child: Center(child: Text(
                      current > 0 ? '+$current' : '$current',
                      style: TextStyle(
                        color: isManual ? t.accent : t.sub,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    )),
                  ),
                ),
                // Botón +
                GestureDetector(
                  onTap: () => onEdit(pA.id, pB.id, (current + 1).toDouble()),
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: t.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: t.primary.withValues(alpha: 0.3)),
                    ),
                    child: Icon(Icons.add, color: t.primary, size: 16),
                  ),
                ),
              ]),
            ]),
          ),
        );
      }).toList(),
    );
  }

  void _showEditDialog(BuildContext ctx, Player pA, Player pB, double? manualCurrent, int autoVal) {
    // Valor editable: si hay manual lo usamos, si no el auto
    int editVal = manualCurrent?.round() ?? autoVal;
    showDialog(
      context: ctx,
      barrierDismissible: true,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx2, setSt) {
          // CONVENIO: positivo → pB da strokes a pA (pA recibe de pB)
          //            negativo → pA da strokes a pB (pB recibe de pA)
          final String desc = editVal > 0
              ? '${pB.name.split(' ').first} da $editVal golpe${editVal != 1 ? 's' : ''} a ${pA.name.split(' ').first}'
              : editVal < 0
                  ? '${pA.name.split(' ').first} da ${editVal.abs()} golpe${editVal.abs() != 1 ? 's' : ''} a ${pB.name.split(' ').first}'
                  : 'Juegan en igualdad (0 golpes)';
          return AlertDialog(
            backgroundColor: t.card,
            title: Row(children: [
              GAvatar(name: pA.name, colorIndex: pA.colorIndex, size: 24),
              const SizedBox(width: 6),
              Text('vs', style: TextStyle(color: t.sub, fontSize: 13)),
              const SizedBox(width: 6),
              GAvatar(name: pB.name, colorIndex: pB.colorIndex, size: 24),
              const SizedBox(width: 8),
              Text('Ventaja', style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              // Descripción dinámica
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: editVal == 0 ? t.surface : (editVal > 0 ? t.primary : t.sub).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: editVal == 0 ? t.divider : (editVal > 0 ? t.primary : t.sub).withValues(alpha: 0.3),
                  ),
                ),
                child: Text(desc, style: TextStyle(
                  color: editVal == 0 ? t.even : (editVal > 0 ? t.primary : t.sub),
                  fontSize: 13, fontWeight: FontWeight.w700,
                ), textAlign: TextAlign.center),
              ),
              const SizedBox(height: 16),
              // Controles grandes
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                // −5
                _bigBtn('−5', t.sub, () => setSt(() => editVal -= 5)),
                const SizedBox(width: 6),
                // −1
                _bigBtn('−1', t.sub, () => setSt(() => editVal -= 1)),
                const SizedBox(width: 12),
                // Valor
                Container(
                  width: 56, height: 48,
                  decoration: BoxDecoration(
                    color: t.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.primary, width: 1.5),
                  ),
                  child: Center(child: Text(
                    editVal > 0 ? '+$editVal' : '$editVal',
                    style: TextStyle(color: t.primary, fontSize: 18, fontWeight: FontWeight.w900),
                  )),
                ),
                const SizedBox(width: 12),
                // +1
                _bigBtn('+1', t.primary, () => setSt(() => editVal += 1)),
                const SizedBox(width: 6),
                // +5
                _bigBtn('+5', t.primary, () => setSt(() => editVal += 5)),
              ]),
              const SizedBox(height: 8),
              Text('(+) = ${pB.name.split(' ').first} da golpes a ${pA.name.split(' ').first}\n(−) = ${pA.name.split(' ').first} da golpes a ${pB.name.split(' ').first}',
                  style: TextStyle(color: t.sub, fontSize: 10), textAlign: TextAlign.center),
            ]),
            actions: [
              if (manualCurrent != null)
                TextButton(
                  onPressed: () { Navigator.pop(dCtx); onEdit(pA.id, pB.id, null); },
                  child: Text('Restablecer auto (${autoVal >= 0 ? '+' : ''}$autoVal  = ${autoVal > 0 ? '${pB.name.split(' ').first} da $autoVal a ${pA.name.split(' ').first}' : autoVal < 0 ? '${pA.name.split(' ').first} da ${autoVal.abs()} a ${pB.name.split(' ').first}' : 'igualdad'})', style: TextStyle(color: t.sub, fontSize: 11)),
                ),
              TextButton(onPressed: () => Navigator.pop(dCtx), child: Text('Cancelar', style: TextStyle(color: t.sub))),
              TextButton(
                onPressed: () { Navigator.pop(dCtx); onEdit(pA.id, pB.id, editVal.toDouble()); },
                child: Text('Guardar', style: TextStyle(color: t.primary, fontWeight: FontWeight.w700)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _bigBtn(String label, Color color, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Center(child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13))),
    ),
  );
}

// ── Sheet de lanzamiento de ronda ─────────────────────────────────────────────
class _LaunchSheet extends StatefulWidget {
  final GolfTheme t;
  final bool isAuth;
  final List<Player> players;
  final List<BetGroup> groups;
  final void Function(StartingNine, {bool startLive, String scoringMode}) onStart;
  final void Function(StartingNine, String name, String emoji, String desc, {bool startLive, String scoringMode}) onStartWithTemplate;

  const _LaunchSheet({
    required this.t,
    required this.isAuth,
    required this.players,
    required this.groups,
    required this.onStart,
    required this.onStartWithTemplate,
  });

  @override
  State<_LaunchSheet> createState() => _LaunchSheetState();
}

class _LaunchSheetState extends State<_LaunchSheet> {
  final bool _saveTemplate  = false;
  bool _startLive     = false;
  String _scoringMode = 'open'; // 'admin' | 'open'
  StartingNine? _selectedStartingNine;
  final _nameCtrl  = TextEditingController();
  final _emojiCtrl = TextEditingController(text: '⛳️');
  final _descCtrl  = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose(); _emojiCtrl.dispose(); _descCtrl.dispose();
    super.dispose();
  }

  void _launch(StartingNine nine) {
    if (_saveTemplate) {
      final name = _nameCtrl.text.trim();
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: widget.t.danger,
          content: const Text('Ingresa un nombre para la plantilla'),
        ));
        return;
      }
      widget.onStartWithTemplate(nine, name, _emojiCtrl.text.trim(), _descCtrl.text.trim(),
          startLive: _startLive, scoringMode: _scoringMode);
    } else {
      widget.onStart(nine, startLive: _startLive, scoringMode: _scoringMode);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 20, right: 20, top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cabecera fija ────────────────────────────────────────────────
          Row(children: [
            Text('Iniciar Ronda',
                style: TextStyle(color: t.text, fontSize: 20, fontWeight: FontWeight.w900)),
            const Spacer(),
            GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Icon(Icons.close, color: t.sub)),
          ]),
          const SizedBox(height: 4),
          Text(
            '${widget.players.isEmpty ? "Solo invitados" : "${widget.players.length} jugador${widget.players.length == 1 ? "" : "es"}"} · ${widget.groups.isEmpty ? (widget.players.length >= 2 ? "Nassau auto" : "Sin apuestas") : "${widget.groups.length} partida${widget.groups.length > 1 ? "s" : ""}"}',
            style: TextStyle(color: t.sub, fontSize: 13),
          ),
          const SizedBox(height: 14),

          // ── Opciones scrollables (Live + ScoringMode) ───────────────────
          // Mostrar opciones de ronda EN VIVO si el usuario está autenticado.
          // No requiere que haya jugadores vinculados: puede ser ronda solo invitados.
          if (widget.isAuth)
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Toggle EN VIVO
                    GestureDetector(
                      onTap: () => setState(() => _startLive = !_startLive),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: _startLive
                              ? Colors.red.withValues(alpha: 0.08)
                              : t.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _startLive ? Colors.red : t.divider,
                            width: _startLive ? 1.5 : 1,
                          ),
                        ),
                        child: Row(children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: _startLive
                                  ? Colors.red.withValues(alpha: 0.15)
                                  : t.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.wifi_tethering_rounded,
                                color: _startLive ? Colors.red : t.sub, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Text('Activar en Vivo',
                                    style: TextStyle(
                                      color: _startLive ? Colors.red : t.text,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    )),
                                if (_startLive) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(4)),
                                    child: const Text('EN VIVO',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 7,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.8)),
                                  ),
                                ],
                              ]),
                              Text(
                                'Los jugadores con cuenta verán la ronda en tiempo real',
                                style: TextStyle(color: t.sub, fontSize: 11),
                              ),
                            ],
                          )),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 22, height: 22,
                            decoration: BoxDecoration(
                              color: _startLive ? Colors.red : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: _startLive ? Colors.red : t.sub),
                            ),
                            child: _startLive
                                ? const Icon(Icons.check,
                                    color: Colors.white, size: 14)
                                : null,
                          ),
                        ]),
                      ),
                    ),
                    // Selector de scoring mode (solo si live activo)
                    if (_startLive) ..._buildScoringModeSelector(t),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),

          // ── Botones de inicio — SIEMPRE VISIBLES al fondo ───────────────
          const SizedBox(height: 16),
          Text('¿DESDE QUÉ LADO EMPEZÁIS?',
              style: TextStyle(
                  color: t.sub,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _startBtn(t, '1️⃣', 'Front 9 primero',
                'Hoyos 1–9 con stroke extra', StartingNine.front)),
            const SizedBox(width: 10),
            Expanded(child: _startBtn(t, '2️⃣', 'Back 9 primero',
                'Hoyos 10–18 con stroke extra', StartingNine.back)),
          ]),
          const SizedBox(height: 12),
          // ── Botón confirmar ──────────────────────────────────────────────
          _confirmBtn(t),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  List<Widget> _buildScoringModeSelector(GolfTheme t) {
    return [
      const SizedBox(height: 12),
      Text('¿QUIÉN CAPTURA LOS SCORES?',
          style: TextStyle(color: t.sub, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _scoringModeBtn(
          t,
          icon: Icons.person_rounded,
          title: 'Solo el admin',
          subtitle: 'Tú capturas todo',
          value: 'admin',
        )),
        const SizedBox(width: 10),
        Expanded(child: _scoringModeBtn(
          t,
          icon: Icons.group_rounded,
          title: 'Todos',
          subtitle: 'Cada quien el suyo',
          value: 'open',
        )),
      ]),
    ];
  }

  Widget _scoringModeBtn(GolfTheme t, {required IconData icon, required String title, required String subtitle, required String value}) {
    final sel = _scoringMode == value;
    return GestureDetector(
      onTap: () => setState(() => _scoringMode = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: sel ? t.primary.withValues(alpha: 0.10) : t.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? t.primary : t.divider, width: sel ? 1.5 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: sel ? t.primary : t.sub, size: 20),
          const SizedBox(height: 6),
          Text(title, style: TextStyle(color: sel ? t.primary : t.text, fontWeight: FontWeight.w700, fontSize: 13)),
          Text(subtitle, style: TextStyle(color: t.sub, fontSize: 11)),
          if (sel) ...[const SizedBox(height: 4), Icon(Icons.check_circle, color: t.primary, size: 14)],
        ]),
      ),
    );
  }

  bool get _hasLinkedPlayers =>
      widget.players.any((p) => p.hasLinkedAccount);

  Widget _startBtn(GolfTheme t, String icon, String title, String subtitle, StartingNine nine) {
    final sel = _selectedStartingNine == nine;
    return GestureDetector(
      onTap: () => setState(() => _selectedStartingNine = nine),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sel ? t.primary.withValues(alpha: 0.12) : t.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: sel ? t.primary : t.divider,
            width: sel ? 1.5 : 1,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(icon, style: const TextStyle(fontSize: 22)),
            const Spacer(),
            if (sel) Icon(Icons.check_circle_rounded, color: t.primary, size: 18),
          ]),
          const SizedBox(height: 6),
          Text(title, style: TextStyle(
              color: sel ? t.primary : t.text,
              fontWeight: FontWeight.w700,
              fontSize: 13)),
          Text(subtitle, style: TextStyle(color: t.sub, fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _confirmBtn(GolfTheme t) {
    final enabled = _selectedStartingNine != null;
    return GestureDetector(
      onTap: enabled ? () => _launch(_selectedStartingNine!) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: enabled ? t.primary : t.divider,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.flag_rounded,
              color: enabled ? Colors.white : t.sub,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              'Confirmar e iniciar ronda',
              style: TextStyle(
                color: enabled ? Colors.white : t.sub,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── _FormatModeCard ───────────────────────────────────────────────────────────
class _FormatModeCard extends StatelessWidget {
  final bool isSelected;
  final String icon;
  final String title;
  final String description;
  final GolfTheme t;
  final VoidCallback onTap;
  const _FormatModeCard({
    required this.isSelected, required this.icon,
    required this.title, required this.description,
    required this.t, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? t.primary.withValues(alpha: 0.08) : t.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? t.primary : t.divider,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Expanded(child: Text(title, style: TextStyle(
              color: isSelected ? t.primary : t.text,
              fontWeight: FontWeight.w700, fontSize: 13,
            ))),
            if (isSelected)
              Container(
                width: 18, height: 18,
                decoration: BoxDecoration(color: t.primary, shape: BoxShape.circle),
                child: Icon(Icons.check, color: t.onPrimary, size: 11),
              ),
          ]),
          const SizedBox(height: 4),
          Text(description, style: TextStyle(color: t.sub, fontSize: 11)),
        ]),
      ),
    );
  }
}

// ── Banner de corrección oficial disponible ───────────────────────────────────
class _CorrectionBanner extends StatelessWidget {
  final CourseCorrection correction;
  final VoidCallback onApply;
  final VoidCallback onDismiss;
  final GolfTheme t;

  const _CorrectionBanner({
    required this.correction,
    required this.onApply,
    required this.onDismiss,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B5E20).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.green.shade600.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: Colors.green.shade700.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.verified_outlined, color: Colors.green.shade700, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Datos del campo actualizados',
              style: TextStyle(
                color: Colors.green.shade800,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(Icons.close, color: Colors.green.shade700, size: 18),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          correction.notes,
          style: TextStyle(color: t.text, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onApply,
            icon: const Icon(Icons.download_done_outlined, size: 16),
            label: const Text('Aplicar corrección'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BettingGroupsBanner — Muestra grupos compatibles en el paso de Apuestas
// ─────────────────────────────────────────────────────────────────────────────
class _BettingGroupsBanner extends StatelessWidget {
  const _BettingGroupsBanner({
    required this.presentIds,
    required this.onApply,
    required this.t,
  });

  final Set<String>          presentIds;
  final void Function(BettingGroup) onApply;
  final GolfTheme            t;

  @override
  Widget build(BuildContext context) {
    final bgProv = context.watch<BettingGroupProvider>();
    if (bgProv.loading) return const SizedBox.shrink();

    final compatible = bgProv.compatibleGroups(presentIds);
    if (compatible.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Encabezado sección ──────────────────────────────────────────────
        GSectionHeader(title: 'GRUPOS DE APUESTA COMPATIBLES'),
        const SizedBox(height: 8),

        ...compatible.map((bg) {
          final summary = bgProv.summaryFor(bg, presentIds);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _BettingGroupCard(
              bg:      bg,
              summary: summary,
              t:       t,
              onApply: () => onApply(bg),
              onReview: () => _showReviewSheet(context, bg, summary),
            ),
          );
        }),
      ],
    );
  }

  // Muestra un sheet de revisión antes de aplicar
  void _showReviewSheet(
      BuildContext context, BettingGroup bg, BettingGroupSummary summary) {
    final playerProv = context.read<PlayerProvider>();

    // Helper: nombre del jugador por ID
    String nameOf(String id) {
      try {
        return playerProv.directory
            .firstWhere((p) => p.player.id == id)
            .player
            .name;
      } catch (_) {
        return id;
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (_, ctrl) => Container(
          decoration: BoxDecoration(
            color: t.bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: t.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(children: [
                Text(bg.emoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(bg.name,
                      style: TextStyle(color: t.text,
                          fontWeight: FontWeight.w800, fontSize: 17)),
                  Text(
                    '${summary.activeRules.length} duelos · '
                    '${summary.totalModules} apuestas activas',
                    style: TextStyle(color: t.sub, fontSize: 12),
                  ),
                ])),
              ]),
            ),
            const Divider(height: 1),
            // Lista de reglas
            Expanded(
              child: ListView.separated(
                controller: ctrl,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: summary.activeRules.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final rule = summary.activeRules[i];
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: t.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: t.divider),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // Duelo
                      Row(children: [
                        Icon(Icons.sports_golf, color: t.primary, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          '${nameOf(rule.playerAId)} vs ${nameOf(rule.playerBId)}',
                          style: TextStyle(color: t.text,
                              fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                      ]),
                      if (rule.modules.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(spacing: 6, runSpacing: 4,
                          children: rule.modules.map((m) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: t.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              m.summaryLabel,
                              style: TextStyle(color: t.primary,
                                  fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          )).toList(),
                        ),
                      ],
                    ]),
                  );
                },
              ),
            ),
            // Botones
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16,
                  MediaQuery.of(context).padding.bottom + 12),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: t.divider),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('Cancelar',
                        style: TextStyle(
                            color: t.sub, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      onApply(bg);
                    },
                    icon: const Icon(Icons.bolt, size: 16),
                    label: const Text('Aplicar grupo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: t.primary,
                      foregroundColor: t.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BettingGroupCard — Tarjeta individual de grupo compatible
// ─────────────────────────────────────────────────────────────────────────────
class _BettingGroupCard extends StatelessWidget {
  const _BettingGroupCard({
    required this.bg,
    required this.summary,
    required this.t,
    required this.onApply,
    required this.onReview,
  });

  final BettingGroup         bg;
  final BettingGroupSummary  summary;
  final GolfTheme            t;
  final VoidCallback         onApply;
  final VoidCallback         onReview;

  @override
  Widget build(BuildContext context) {
    final nDuelos    = summary.activeRules.length;
    final nApuestas  = summary.totalModules;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.primary.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Encabezado ──────────────────────────────────────────────────────
        Row(children: [
          Text(bg.emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(bg.name,
                style: TextStyle(color: t.text,
                    fontWeight: FontWeight.w800, fontSize: 15)),
            if (bg.description != null && bg.description!.isNotEmpty)
              Text(bg.description!,
                  style: TextStyle(color: t.sub, fontSize: 11),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          // Botón Gestionar
          GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const BettingGroupsScreen())),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: t.divider),
              ),
              child: Text('Gestionar',
                  style: TextStyle(color: t.sub,
                      fontSize: 10, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        // ── Chips de stats ──────────────────────────────────────────────────
        Wrap(spacing: 6, runSpacing: 4, children: [
          _StatChip(
            icon: Icons.sports_golf,
            label: '$nDuelos ${nDuelos == 1 ? 'duelo' : 'duelos'}',
            t: t,
          ),
          _StatChip(
            icon: Icons.casino_outlined,
            label: '$nApuestas ${nApuestas == 1 ? 'apuesta' : 'apuestas'}',
            t: t,
          ),
        ]),
        const SizedBox(height: 12),
        // ── Botones de acción ───────────────────────────────────────────────
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onReview,
              icon: Icon(Icons.visibility_outlined, size: 14, color: t.sub),
              label: Text('Revisar',
                  style: TextStyle(color: t.sub,
                      fontSize: 12, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: t.divider),
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: onApply,
              icon: const Icon(Icons.bolt, size: 14),
              label: const Text('Aplicar grupo',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: t.primary,
                foregroundColor: t.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}

// Helper chip pequeño para stats
class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label, required this.t});
  final IconData  icon;
  final String    label;
  final GolfTheme t;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: t.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: t.primary),
      const SizedBox(width: 4),
      Text(label,
          style: TextStyle(color: t.primary,
              fontSize: 11, fontWeight: FontWeight.w600)),
    ]),
  );
}

