import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/odds.dart';

class OddsPanel extends StatelessWidget {
  final List<Odds> odds;
  final int raceNo;

  const OddsPanel({super.key, required this.odds, required this.raceNo});

  @override
  Widget build(BuildContext context) {
    if (odds.isEmpty) return const SizedBox.shrink();

    final winOdds = odds.where(
      (o) => o.betType == 'WIN' || o.betType == '1',
    );

    if (winOdds.isEmpty) return const SizedBox.shrink();

    final sorted = winOdds.toList()..sort((a, b) => a.rate.compareTo(b.rate));
    final top3 = sorted.take(3).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryGreen.withValues(alpha: 0.2),
            AppTheme.cardDark,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.primaryGreen.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.show_chart,
                  size: 18, color: AppTheme.accentGold),
              const SizedBox(width: 6),
              const Text(
                '단승 배당률 TOP 3',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: top3.asMap().entries.map((e) {
              final idx = e.key;
              final o = e.value;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: idx > 0 ? 8 : 0,
                  ),
                  child: _OddsTile(
                    rank: idx + 1,
                    horseNo: o.horseNo1,
                    rate: o.rate,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _OddsTile extends StatelessWidget {
  final int rank;
  final int horseNo;
  final double rate;

  const _OddsTile({
    required this.rank,
    required this.horseNo,
    required this.rate,
  });

  @override
  Widget build(BuildContext context) {
    final colors = [
      AppTheme.winColor,
      AppTheme.placeColor,
      AppTheme.showColor,
    ];
    final color = colors[rank - 1];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            '$horseNo번',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${rate.toStringAsFixed(1)}배',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
