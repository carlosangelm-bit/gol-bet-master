// ─────────────────────────────────────────────────────────────────────────────
// HISTORY SCREEN — Historial de rondas finalizadas
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/app_theme.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/round_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/common_widgets.dart';
import '../results/results_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _recovering = false;
  bool _syncing    = false;
  int  _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPendingCount());
  }

  Future<void> _loadPendingCount() async {
    if (!mounted) return;
    final count = await context.read<RoundProvider>().pendingFinishedCount();
    if (mounted) setState(() => _pendingCount = count);
  }

  /// Sincroniza rondas pendientes locales con Firestore
  Future<void> _syncPending(GolfTheme t) async {
    setState(() => _syncing = true);
    try {
      final synced = await context.read<RoundProvider>().syncPendingFinished();
      await _loadPendingCount();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(synced == 0
            ? 'No hay rondas pendientes de sincronizar'
            : '$synced ronda${synced > 1 ? 's sincronizadas' : ' sincronizada'} ✅'),
        backgroundColor: synced > 0 ? t.profit : t.sub,
        duration: const Duration(seconds: 3),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al sincronizar: $e')));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  /// Busca rondas no finalizadas en Firestore y las marca como finalizadas
  /// (recuperación de rondas "huérfanas" que se concluyeron pero no quedaron en historial)
  Future<void> _recoverOrphanRounds(GolfTheme t) async {
    setState(() => _recovering = true);
    try {
      final recovered = await FirestoreService.recoverOrphanRounds();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(recovered == 0
            ? 'No se encontraron rondas para recuperar'
            : '$recovered ronda${recovered > 1 ? 's recuperadas' : ' recuperada'} ✅'),
        backgroundColor: recovered > 0 ? t.profit : t.sub,
        duration: const Duration(seconds: 3),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al recuperar rondas')));
    } finally {
      if (mounted) setState(() => _recovering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t    = context.watch<RoundProvider>().theme;
    final auth = context.watch<AuthProvider>();
    final busy = _recovering || _syncing;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        title: Text('Historial', style: TextStyle(color: t.text, fontWeight: FontWeight.w800)),
        iconTheme: IconThemeData(color: t.text),
        actions: [
          if (busy)
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: t.primary)),
            )
          else ...[
            if (_pendingCount > 0)
              // Botón de sincronización — muestra badge con el conteo de pendientes
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: Icon(Icons.cloud_upload_outlined, color: Colors.orange.shade600),
                    tooltip: 'Sincronizar $_pendingCount ronda${_pendingCount > 1 ? 's' : ''} pendiente${_pendingCount > 1 ? 's' : ''}',
                    onPressed: () => _syncPending(t),
                  ),
                  Positioned(
                    right: 6, top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade600,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$_pendingCount',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            IconButton(
              icon: Icon(Icons.restore_outlined, color: t.sub),
              tooltip: 'Recuperar rondas',
              onPressed: () => _recoverOrphanRounds(t),
            ),
          ],
        ],
      ),
      // Si no está autenticado, mostrar mensaje
      body: !auth.isAuth
          ? Center(child: Text('Inicia sesión para ver el historial.',
              style: TextStyle(color: t.sub)))
          : Column(children: [
              // Banner de rondas pendientes de sync
              if (_pendingCount > 0)
                _PendingSyncBanner(
                  count: _pendingCount,
                  t: t,
                  onSync: () => _syncPending(t),
                ),
              Expanded(
                child: StreamBuilder<List<RoundSummary>>(
                  // Usar auth.user?.uid como key fuerza la recreación del StreamBuilder
                  // cuando cambia el usuario (login/logout), evitando stream vacío cacheado.
                  key: ValueKey(auth.user?.uid),
                  stream: FirestoreService.historyStream(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return Center(child: CircularProgressIndicator(color: t.primary));
                    }
                    final history = snap.data ?? [];
                    if (history.isEmpty) {
                      return _EmptyHistory(t: t, onRecover: () => _recoverOrphanRounds(t));
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: history.length,
                      itemBuilder: (_, i) => _HistoryCard(summary: history[i], t: t),
                    );
                  },
                ),
              ),
            ]),
    );
  }
}

// ── Banner de rondas pendientes de sincronización ─────────────────────────────
class _PendingSyncBanner extends StatelessWidget {
  final int count;
  final GolfTheme t;
  final VoidCallback onSync;
  const _PendingSyncBanner({required this.count, required this.t, required this.onSync});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Icon(Icons.cloud_upload_outlined, color: Colors.orange.shade700, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            '$count ronda${count > 1 ? 's' : ''} pendiente${count > 1 ? 's' : ''} de sincronizar',
            style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 12),
          ),
          Text(
            'Se guardaron localmente. Toca para subir a la nube.',
            style: TextStyle(color: t.sub, fontSize: 11),
          ),
        ])),
        const SizedBox(width: 8),
        TextButton(
          onPressed: onSync,
          style: TextButton.styleFrom(
            backgroundColor: Colors.orange.withValues(alpha: 0.15),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text('Sincronizar', style: TextStyle(color: Colors.orange.shade700, fontWeight: FontWeight.w700, fontSize: 12)),
        ),
      ]),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  final GolfTheme t;
  final VoidCallback onRecover;
  const _EmptyHistory({required this.t, required this.onRecover});
  @override
  Widget build(BuildContext context) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text('📊', style: TextStyle(fontSize: 60)),
      const SizedBox(height: 16),
      Text('Sin rondas finalizadas', style: TextStyle(color: t.text, fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text('Aquí aparecerán tus rondas\nterminadas con sus resultados.', style: TextStyle(color: t.sub, fontSize: 13), textAlign: TextAlign.center),
      const SizedBox(height: 20),
      TextButton.icon(
        onPressed: onRecover,
        icon: Icon(Icons.restore_outlined, size: 16, color: t.primary),
        label: Text('Buscar rondas no guardadas', style: TextStyle(color: t.primary, fontSize: 13)),
      ),
    ]));
  }
}

class _HistoryCard extends StatelessWidget {
  final RoundSummary summary;
  final GolfTheme t;
  const _HistoryCard({required this.summary, required this.t});

  @override
  Widget build(BuildContext context) {
    final date = summary.finishedAt ?? summary.createdAt;
    String formattedDate;
    try {
      final dateFmt = DateFormat('d MMM yyyy', 'es');
      final timeFmt = DateFormat('HH:mm');
      formattedDate = '${dateFmt.format(date)} · ${timeFmt.format(date)}';
    } catch (_) {
      formattedDate = '${date.day}/${date.month}/${date.year}';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GCard(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openRound(context),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(color: t.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: const Center(child: Text('⛳️', style: TextStyle(fontSize: 22))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(summary.name, style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  summary.playerNames.take(4).join(' · ') + (summary.playerNames.length > 4 ? ' +${summary.playerNames.length - 4}' : ''),
                  style: TextStyle(color: t.sub, fontSize: 11),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.calendar_today, size: 11, color: t.sub),
                  const SizedBox(width: 4),
                  Text(formattedDate, style: TextStyle(color: t.sub, fontSize: 11)),
                ]),
              ])),
              Icon(Icons.chevron_right, color: t.sub, size: 20),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _openRound(BuildContext context) async {
    final t = this.t;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(child: CircularProgressIndicator(color: t.primary)),
    );

    final round = await FirestoreService.loadRoundById(summary.docId);
    if (!context.mounted) return;
    Navigator.pop(context);

    if (round == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo cargar la ronda')));
      return;
    }

    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _HistoryRoundDetail(round: round, t: t),
    ));
  }
}

// ── Detalle de ronda del historial ────────────────────────────────────────────
class _HistoryRoundDetail extends StatelessWidget {
  final Round round;
  final GolfTheme t;
  const _HistoryRoundDetail({required this.round, required this.t});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        title: Text(round.name, style: TextStyle(color: t.text, fontWeight: FontWeight.w800)),
        iconTheme: IconThemeData(color: t.text),
      ),
      body: ResultsBody(round: round),
    );
  }
}
