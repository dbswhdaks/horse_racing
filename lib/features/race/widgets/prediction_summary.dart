import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/prediction.dart';

class PredictionSummary extends StatelessWidget {
  final PredictionReport report;

  const PredictionSummary({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    if (report.predictions.isEmpty) return const SizedBox.shrink();

    final sorted = [...report.predictions]
      ..sort(Prediction.compareByPlaceThenWin);
    final top3 = sorted.take(3).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.deepPurple.shade900.withValues(alpha: 0.4),
            AppTheme.cardDark,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                size: 18,
                color: Colors.purpleAccent.shade100,
              ),
              const SizedBox(width: 6),
              const Text(
                'AI 입상 TOP 3',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                'v${report.modelVersion}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...top3.asMap().entries.map((e) {
            final idx = e.key;
            final p = e.value;
            return Padding(
              padding: EdgeInsets.only(bottom: idx < 2 ? 6 : 0),
              child: _PredictionRow(
                rank: idx + 1,
                prediction: p,
                maxProb: top3.first.placeProbability,
              ),
            );
          }),
          if (top3.first.tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: top3.first.tags.map((tag) {
                return Chip(
                  label: Text(tag),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  labelStyle: const TextStyle(fontSize: 11),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _PredictionRow extends StatelessWidget {
  final int rank;
  final Prediction prediction;
  final double maxProb;

  const _PredictionRow({
    required this.rank,
    required this.prediction,
    required this.maxProb,
  });

  @override
  Widget build(BuildContext context) {
    final pct = prediction.placeProbability;
    final fraction = maxProb > 0 ? pct / maxProb : 0.0;

    return Row(
      children: [
        SizedBox(
          width: 22,
          child: Text(
            '$rank',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: rank == 1
                  ? AppTheme.winColor
                  : rank == 2
                  ? AppTheme.placeColor
                  : AppTheme.showColor,
            ),
          ),
        ),
        Text(
          '${prediction.horseNo}번 ',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        Expanded(
          child: Text(
            prediction.horseName,
            style: const TextStyle(fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              backgroundColor: Colors.grey.shade800,
              valueColor: AlwaysStoppedAnimation(
                Colors.purpleAccent.withValues(alpha: 0.7),
              ),
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 48,
          child: Text(
            '${pct.toStringAsFixed(1)}%',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
