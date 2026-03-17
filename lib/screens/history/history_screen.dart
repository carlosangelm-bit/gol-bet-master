// ─────────────────────────────────────────────────────────────────────────────
// HISTORY SCREEN — Historial de rondas finalizadas
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/app_theme.dart';
import '../../models/models.dart';
import '../../providers/round_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/common_widgets.dart';
import '../results/results_screen.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.watch<RoundProvider>().theme;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        title: Text('Historial', style: TextStyle(color: t.text, fontWeight: FontWeight.w800)),
        iconTheme: IconThemeData(color: t.text),
      ),
      body: StreamBuilder<List<RoundSummary>>(
        stream: FirestoreService.historyStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: t.primary));
          }
          final history = snap.data ?? [];
          if (history.isEmpty) {
            return _EmptyHistory(t: t);
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: history.length,
            itemBuilder: (_, i) => _HistoryCard(summary: history[i], t: t),
          );
        },
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  final GolfTheme t;
  const _EmptyHistory({required this.t});
  @override
  Widget build(BuildContext context) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text('📊', style: TextStyle(fontSize: 60)),
      const SizedBox(height: 16),
      Text('Sin rondas finalizadas', style: TextStyle(color: t.text, fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text('Aquí aparecerán tus rondas\nterminadas con sus resultados.', style: TextStyle(color: t.sub, fontSize: 13), textAlign: TextAlign.center),
    ]));
  }
}

class _HistoryCard extends StatelessWidget {
  final RoundSummary summary;
  final GolfTheme t;
  const _HistoryCard({required this.summary, required this.t});

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMM yyyy', 'es');
    final timeFmt = DateFormat('HH:mm');
    final date    = summary.finishedAt ?? summary.createdAt;

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
                  Text('${dateFmt.format(date)} · ${timeFmt.format(date)}', style: TextStyle(color: t.sub, fontSize: 11)),
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
