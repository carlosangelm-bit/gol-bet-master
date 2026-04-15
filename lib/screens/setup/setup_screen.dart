// SETUP SCREEN — Configurar jugadores, partidas y módulos de apuesta
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/app_theme.dart';
import '../../engines/bet_engine.dart';
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

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _uuid = const Uuid();
  // 4 pasos: 0=Campo  1=Jugadores  2=Apuestas  3=Resumen
  int _step = 0;

  static String _defaultRoundName() {
    final now = DateTime.now();
    final months = ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'];
    return 'Ronda Golf ${now.day} ${months[now.month - 1]} ${now.year}';
  }

  late final _nameCtrl = TextEditingController(text: _defaultRoundName());
  final List<Player> _players = [];
  final List<BetGroup> _groups = [];

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

  @override void dispose() { _nameCtrl.dispose(); super.dispose(); }

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
        _StepBar(step: _step, t: t),
        Expanded(child: IndexedStack(
          index: _step,
          children: [_stepCourse(t), _stepPlayers(t), _stepGroups(t), _stepReview(t)],
        )),
        _bottomBar(context, t),
      ]),
    );
  }

  // ── Bottom navigation bar ─────────────────────────────────────────────────
  Widget _bottomBar(BuildContext ctx, GolfTheme t) {
    final isLast = _step == 3;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(ctx).padding.bottom + 12),
      decoration: BoxDecoration(color: t.bg, border: Border(top: BorderSide(color: t.divider))),
      child: Row(children: [
        if (_step > 0) ...[
          Expanded(child: GSecButton(label: 'Atrás', onTap: () => setState(() => _step--))),
          const SizedBox(width: 12),
        ],
        Expanded(flex: 2, child: GPrimaryButton(
          label: isLast ? '⛳ Iniciar Ronda' : 'Siguiente →',
          onTap: () {
            // Validaciones por paso
            if (_step == 0) {
              // Campo es opcional — cualquier cosa está bien
            } else if (_step == 2 && _groups.isEmpty) {
              _addDefaultGroup();
            }
            if (!isLast) { setState(() => _step++); return; }
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
            final isSelected = _selectedApiCourse?.id.toString() == fav.courseId ||
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
                f.courseId == _selectedApiCourse?.id.toString() ||
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
          GestureDetector(onTap: () => setState(() => _players.removeAt(i)), child: Icon(Icons.delete_outline, color: t.loss.withValues(alpha: 0.7), size: 18)),
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
  Widget _stepGroups(GolfTheme t) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Partidas configuradas ─────────────────────────────────────────
        if (_groups.isNotEmpty) ...[
          GSectionHeader(title: 'PARTIDAS CONFIGURADAS'),
          ..._groups.asMap().entries.map((e) => _groupCard(e.key, e.value, t)),
          const SizedBox(height: 8),
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

  /// Aplica un preset directamente sin sheet intermedio (usa todos los jugadores del grupo).
  void _applyPresetDirect(GamePreset preset, GolfTheme t) {
    final allPids = _players.map((p) => p.id).toList();
    if (allPids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: t.loss,
        content: const Text('Agrega jugadores primero'),
      ));
      return;
    }
    final modules = preset.toModules(allPids);
    final group = BetGroup(
      id: _uuid.v4(),
      name: preset.name,
      format: PartidaFormat.allInOnePot,
      playerIds: allPids,
      modules: modules,
    );
    setState(() => _groups.add(group));
    // Incrementar contador de uso del preset
    FirestoreService.saveGamePreset(preset.copyWith(useCount: preset.useCount + 1));
  }

  Widget _groupCard(int idx, BetGroup g, GolfTheme t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ────────────────────────────────────────────────────────
        Row(children: [
          Expanded(child: Text(g.name, style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 16))),
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

        ...g.modules.asMap().entries.map((e) => _moduleTile(idx, e.key, e.value, g, t)),
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

  // ── Editor de instancia (bottom sheet con config tipada) ─────────────────
  void _editModuleInstance(int gi, int mi, BetModuleInstance mod, BetGroup g, GolfTheme t) {
    var cfg = mod;
    final allPids = g.playerIds;
    var localPids = List<String>.from(
        mod.participantIds.isEmpty ? allPids : mod.participantIds);

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
  List<Widget> _configWidgets(BetModuleInstance cfg, GolfTheme t, StateSetter setSt, void Function(BetModuleInstance) update) {
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
      case BetModuleType.skins:
        final s = cfg.skins;
        final ctrl = TextEditingController(text: s.valuePerSkin.toStringAsFixed(0));
        return [
          ...formatSelector,
          _sectionLabel('VALOR POR SKIN', t),
          const SizedBox(height: 8),
          _amountField('Valor por skin', ctrl, t),
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
              ctrl.text = s.valuePerSkin.toStringAsFixed(0);
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
                    ctrl.text = s.valuePerSkin.toStringAsFixed(0);
                    setSt(() => update(cfg.copyWith(skinsConfig: s.copyWith(carryOver: v))));
                  },
                  activeThumbColor: t.accent,
                  activeTrackColor: t.accent.withValues(alpha: 0.4),
                  inactiveTrackColor: t.divider,
                ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          // Guardar valor al escribir
          Builder(builder: (_) {
            ctrl.addListener(() {
              final v = double.tryParse(ctrl.text);
              if (v != null) update(cfg.copyWith(skinsConfig: s.copyWith(valuePerSkin: v)));
            });
            return const SizedBox.shrink();
          }),
        ];

      case BetModuleType.nassau:
        final n = cfg.nassau;
        final cFront = TextEditingController(text: n.frontValue.toStringAsFixed(0));
        final cBack  = TextEditingController(text: n.backValue.toStringAsFixed(0));
        final cTotal = TextEditingController(text: n.totalValue.toStringAsFixed(0));
        final cPF    = TextEditingController(text: n.frontPressValue.toStringAsFixed(0));
        final cPB    = TextEditingController(text: n.backPressValue.toStringAsFixed(0));
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
        cFront.addListener(saveNassauValues);
        cBack.addListener(saveNassauValues);
        cTotal.addListener(saveNassauValues);
        cPF.addListener(saveNassauValues);
        cPB.addListener(saveNassauValues);
        return [
          ...formatSelector,
          _sectionLabel('VALORES', t),
          const SizedBox(height: 8),
          _amountField('Front 9', cFront, t),
          const SizedBox(height: 8),
          _amountField('Back 9', cBack, t),
          const SizedBox(height: 8),
          _amountField('Total 18', cTotal, t),
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
            _amountField('Press Front 9', cPF, t),
            const SizedBox(height: 8),
            _amountField('Press Back 9', cPB, t),
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
        final ctrl = TextEditingController(text: m.value.toStringAsFixed(0));
        ctrl.addListener(() { final v = double.tryParse(ctrl.text); if (v != null) update(cfg.copyWith(medalConfig: m.copyWith(value: v))); });
        return [
          ...formatSelector,
          _sectionLabel('VALOR', t),
          const SizedBox(height: 8),
          _amountField('Monto', ctrl, t),
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
        final ctrl = TextEditingController(text: p.value.toStringAsFixed(0));
        ctrl.addListener(() { final v = double.tryParse(ctrl.text); if (v != null) update(cfg.copyWith(puttsConfig: p.copyWith(value: v))); });
        return [
          ...formatSelector,
          _sectionLabel('VALOR', t),
          const SizedBox(height: 8),
          _amountField('Monto por segmento', ctrl, t),
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
        final ctrl = TextEditingController(text: o.value.toStringAsFixed(0));
        ctrl.addListener(() { final v = double.tryParse(ctrl.text); if (v != null) update(cfg.copyWith(oyesesConfig: o.copyWith(value: v))); });
        // Controller para valor fijo del zapato (0 = automático)
        final zapatoCtrl = TextEditingController(
          text: o.zapatoValue > 0 ? o.zapatoValue.toStringAsFixed(0) : '',
        );
        zapatoCtrl.addListener(() {
          final v = double.tryParse(zapatoCtrl.text) ?? 0;
          update(cfg.copyWith(oyesesConfig: o.copyWith(zapatoValue: v)));
        });
        // Par-3 reales del campo seleccionado (fallback: estándar)
        final realPar3Holes = (_selectedCourse?.holes ?? CourseInfo.standard.holes)
            .where((h) => h.isPar3)
            .map((h) => h.hole)
            .toList()
          ..sort();
        return [
          _sectionLabel('VALOR POR OYÉS', t),
          const SizedBox(height: 8),
          _amountField('Monto por oyés', ctrl, t),
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
        // Un controller por cada tipo de evento
        final ctrls = <UnitEventType, TextEditingController>{
          for (final e in UnitEventType.values)
            e: TextEditingController(text: u.valueFor(e).toStringAsFixed(0)),
        };
        // Listeners: actualizar el mapa al editar cada campo
        void rebuildUnits() {
          final newMap = <UnitEventType, double>{};
          for (final e in UnitEventType.values) {
            final v = double.tryParse(ctrls[e]!.text);
            if (v != null) newMap[e] = v;
          }
          update(cfg.copyWith(unitsConfig: UnitsConfig(eventValues: newMap)));
        }
        for (final e in UnitEventType.values) {
          ctrls[e]!.addListener(rebuildUnits);
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
    final cMatch = TextEditingController(text: m.matchValue.toStringAsFixed(0));
    final cPress = TextEditingController(text: m.pressValue.toStringAsFixed(0));
    cMatch.addListener(() { final v = double.tryParse(cMatch.text); if (v != null) update(cfg.copyWith(matchAutoPressConfig: m.copyWith(matchValue: v))); });
    cPress.addListener(() { final v = double.tryParse(cPress.text); if (v != null) update(cfg.copyWith(matchAutoPressConfig: m.copyWith(pressValue: v))); });
    return [
      _sectionLabel('MATCH PRINCIPAL', t),
      const SizedBox(height: 8),
      _amountField('Valor del match', cMatch, t),
      const SizedBox(height: 16),
      _sectionLabel('PRESIONES ADICIONALES', t),
      const SizedBox(height: 8),
      _amountField('Valor por presión', cPress, t),
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

  Widget _amountField(String label, TextEditingController ctrl, GolfTheme t) => TextField(
    controller: ctrl, keyboardType: TextInputType.number, style: TextStyle(color: t.text),
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
              onTap: () => setSt(() { if (sel) selectedPids.remove(p.id); else selectedPids.add(p.id); }),
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
    final selected = <BetModuleType>{};
    showModalBottomSheet(
      context: context, backgroundColor: t.card, isScrollControlled: true, useRootNavigator: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setSt) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx2).viewInsets.bottom + 24, left: 20, right: 20, top: 24),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Agregar apuesta', style: TextStyle(color: t.text, fontSize: 18, fontWeight: FontWeight.w800)),
            const Spacer(),
            GestureDetector(onTap: () => Navigator.pop(ctx2), child: Icon(Icons.close, color: t.sub)),
          ]),
          const SizedBox(height: 4),
          Text('Selecciona el tipo de apuesta a agregar', style: TextStyle(color: t.sub, fontSize: 12)),
          const SizedBox(height: 16),

          // ── Grupo Match / Apuestas de 18 hoyos ──────────────────────────
          Text('MATCH PLAY', style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          ...[BetModuleType.nassau, BetModuleType.matchAutoPress].map((bt) => _betTypeTile(bt, selected, setSt, t)),
          const SizedBox(height: 16),

          // ── Grupo apuestas individuales ───────────────────────────────
          Text('OTRAS APUESTAS', style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          ...[BetModuleType.skins, BetModuleType.medal, BetModuleType.putts, BetModuleType.oyeses, BetModuleType.units].map((bt) => _betTypeTile(bt, selected, setSt, t)),

          const SizedBox(height: 16),
          GPrimaryButton(
            label: selected.isEmpty ? 'Selecciona al menos uno' : 'Agregar ${selected.length} módulo${selected.length > 1 ? 's' : ''}',
            onTap: selected.isEmpty ? null : () {
              final startIdx = _groups[gi].modules.length;
              setState(() {
                final mods = List<BetModuleInstance>.from(_groups[gi].modules);
                for (final bt in selected) {
                  mods.add(BetModuleInstance.defaultFor(bt, g.playerIds));
                }
                _groups[gi] = _groups[gi].copyWith(modules: mods);
              });
              Navigator.pop(ctx2);
              if (selected.length == 1) {
                final newGroup = _groups[gi];
                final newMod   = newGroup.modules[startIdx];
                Future.delayed(const Duration(milliseconds: 220), () {
                  if (mounted) _editModuleInstance(gi, startIdx, newMod, newGroup, t);
                });
              }
            },
          ),
        ])),
      )),
    );
  }

  Widget _betTypeTile(BetModuleType bt, Set<BetModuleType> selected, StateSetter setSt, GolfTheme t) {
    final isSel = selected.contains(bt);
    // Colores especiales para Match types
    final isMatchType = bt == BetModuleType.nassau || bt == BetModuleType.matchAutoPress;
    final accentColor = isMatchType ? t.accent : t.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => setSt(() { if (isSel) selected.remove(bt); else selected.add(bt); }),
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
              onTap: () => setState(() => _step = 1), // Ir al paso jugadores
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
        // ── PARTIDAS (editables) ──────────────────────────────────────────
        Row(children: [
          Expanded(child: GSectionHeader(title: 'PARTIDAS')),
          GestureDetector(
            onTap: () => setState(() => _step = 2), // Ir a paso Apuestas
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: t.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.primary.withValues(alpha: 0.35)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add, color: t.primary, size: 12),
                const SizedBox(width: 4),
                Text('Agregar', style: TextStyle(color: t.primary, fontSize: 11, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ]),
        ...effectiveGroups.map((g) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(g.name, style: TextStyle(color: t.text, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: g.modules.map((m) {
              final isNassau = m.type == BetModuleType.nassau;
              final fv = (m.extra['frontValue'] as num?)?.toDouble() ?? m.value;
              final bv = (m.extra['backValue']  as num?)?.toDouble() ?? m.value;
              final tv = (m.extra['totalValue'] as num?)?.toDouble() ?? m.value;
              return GestureDetector(
                onTap: () => _openModuleEdit(context, g, m, t),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: t.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: t.primary.withValues(alpha: 0.35)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(m.type.icon, style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 4),
                    Text(
                      isNassau
                          ? 'Nassau  F\$${fv.toStringAsFixed(0)}·B\$${bv.toStringAsFixed(0)}·T\$${tv.toStringAsFixed(0)}'
                          : '${m.type.label} \$${m.value.toStringAsFixed(0)}',
                      style: TextStyle(color: t.primary, fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.edit_outlined, color: t.primary.withValues(alpha: 0.6), size: 11),
                  ]),
                ),
              );
            }).toList()),
          ])),
        )),
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
    final course = _selectedApiCourse?.id.toString() == fav.courseId
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
              _selectedApiCourse?.id.toString() == fav.courseId;
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

    final courseIdInt = int.tryParse(fav.courseId);

    // Mostrar loading + placeholder inmediato
    setState(() {
      _pendingCorrection = null;
      _loadingFavId = fav.courseId;
      _selectedCourse = CourseInfo(name: fav.fullName, holes: CourseInfo.standard.holes);
      _selectedApiCourse = null;
      _playerTees.clear();
    });

    if (courseIdInt == null) {
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
      // Si el parsing de courseCorrections falló en Web, usamos el cachedCourse
      // que fue actualizado con datos corregidos desde Ajustes o automáticamente.
      if (fav.hasCachedData && mounted) {
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
      final fresh = await GolfCourseService.getById(courseIdInt);
      if (!mounted) return;
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
        for (final side in mod.sides!) {
          if (side.playerIds.length < 2) continue;

          final members = _players.where((p) => side.playerIds.contains(p.id)).toList();
          if (members.isEmpty) continue;

          final hcps      = members.map((p) => _teeOf(p.id).playingHandicap(p.handicapBase)).toList()..sort();
          final tees      = members.map((p) => _teeOf(p.id)).toList();
          final hardestTee = tees.reduce((a, b) => a.courseRating > b.courseRating ? a : b);
          final teamHcp   = (hcps.first * 0.35 + hcps.last * 0.15).round().toDouble();

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
    final effectiveGroups = (_groups.isEmpty
        ? [BetGroup(
            id: _uuid.v4(), name: 'Partida Principal',
            format: PartidaFormat.allInOnePot,
            playerIds: allPidsLaunch,
            modules: [BetModuleInstance.defaultFor(BetModuleType.nassau, allPidsLaunch)],
          )]
        : _groups).map((group) {

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
        for (final side in mod.sides!) {
          if (sideIdToVirtualId.containsKey(side.id)) {
            newParticipantIds.add(sideIdToVirtualId[side.id]!);
          } else if (sideIdToBBTeamId.containsKey(side.id)) {
            newParticipantIds.add(sideIdToBBTeamId[side.id]!);
          } else {
            newParticipantIds.addAll(side.playerIds);
          }
        }
        return mod.copyWith(participantIds: newParticipantIds);
      }).toList();

      return group.copyWith(modules: updatedModules, playerIds: updatedGroupPlayerIds);
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
  final int step;
  final GolfTheme t;
  const _StepBar({required this.step, required this.t});

  @override
  Widget build(BuildContext context) {
    final labels = ['Campo', 'Jugadores', 'Apuestas', 'Revisar'];
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
                      color: t.loss.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: t.loss.withValues(alpha: 0.3)),
                    ),
                    child: Icon(Icons.remove, color: t.loss, size: 16),
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
                      color: t.profit.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: t.profit.withValues(alpha: 0.3)),
                    ),
                    child: Icon(Icons.add, color: t.profit, size: 16),
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
                  color: editVal == 0 ? t.surface : (editVal > 0 ? t.profit : t.loss).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: editVal == 0 ? t.divider : (editVal > 0 ? t.profit : t.loss).withValues(alpha: 0.3),
                  ),
                ),
                child: Text(desc, style: TextStyle(
                  color: editVal == 0 ? t.sub : (editVal > 0 ? t.profit : t.loss),
                  fontSize: 13, fontWeight: FontWeight.w700,
                ), textAlign: TextAlign.center),
              ),
              const SizedBox(height: 16),
              // Controles grandes
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                // −5
                _bigBtn('−5', t.loss, () => setSt(() => editVal -= 5)),
                const SizedBox(width: 6),
                // −1
                _bigBtn('−1', t.loss, () => setSt(() => editVal -= 1)),
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
                _bigBtn('+1', t.profit, () => setSt(() => editVal += 1)),
                const SizedBox(width: 6),
                // +5
                _bigBtn('+5', t.profit, () => setSt(() => editVal += 5)),
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
  bool _saveTemplate  = false;
  bool _startLive     = false;
  String _scoringMode = 'open'; // 'admin' | 'open'
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
          backgroundColor: widget.t.loss,
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
                'Hoyos 1–9 con stroke extra', () => _launch(StartingNine.front))),
            const SizedBox(width: 10),
            Expanded(child: _startBtn(t, '2️⃣', 'Back 9 primero',
                'Hoyos 10–18 con stroke extra', () => _launch(StartingNine.back))),
          ]),
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

  Widget _startBtn(GolfTheme t, String icon, String title, String subtitle, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.primary.withValues(alpha: 0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 6),
          Text(title, style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 13)),
          Text(subtitle, style: TextStyle(color: t.sub, fontSize: 11)),
        ]),
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

