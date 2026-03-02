import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/race_entry.dart';

class EntryCard extends StatelessWidget {
  final RaceEntry entry;
  final double winOdds;
  final VoidCallback onTap;

  const EntryCard({
    super.key,
    required this.entry,
    required this.winOdds,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HorseNumberBadge(no: entry.horseNo),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.horseName,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${entry.sexLabel} ${entry.age}세 | ${entry.birthPlace}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (winOdds > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.accentGold.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppTheme.accentGold.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            winOdds.toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.accentGold,
                            ),
                          ),
                          Text(
                            '단승',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _StatChip(label: '기수', value: entry.jockeyName),
                  const SizedBox(width: 8),
                  _StatChip(label: '조교사', value: entry.trainerName),
                  const SizedBox(width: 8),
                  _StatChip(
                    label: '부담중량',
                    value: '${entry.weight.toStringAsFixed(0)}kg',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _PerformanceBadge(
                    label: '전적',
                    value: '${entry.totalRaces}전 '
                        '${entry.winCount}승 ${entry.placeCount}복',
                  ),
                  const Spacer(),
                  if (entry.winRate > 0) ...[
                    Text(
                      '승률 ',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    Text(
                      '${entry.winRate.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: entry.winRate >= 20
                            ? AppTheme.positiveGreen
                            : Colors.grey.shade300,
                      ),
                    ),
                  ],
                  if (entry.rating > 0) ...[
                    const SizedBox(width: 12),
                    Text(
                      'R ',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    Text(
                      entry.rating.toStringAsFixed(0),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HorseNumberBadge extends StatelessWidget {
  final int no;

  const _HorseNumberBadge({required this.no});

  static const _colors = [
    Colors.white,
    Colors.black,
    Colors.red,
    Colors.blue,
    Colors.orange,
    Colors.green,
    Colors.purple,
    Colors.pink,
    Colors.grey,
    Colors.brown,
    Colors.teal,
    Colors.indigo,
  ];

  @override
  Widget build(BuildContext context) {
    final color = _colors[(no - 1) % _colors.length];
    final isLight = color == Colors.white || color == Colors.orange;

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: color == Colors.white
            ? Border.all(color: Colors.grey.shade600)
            : null,
      ),
      child: Center(
        child: Text(
          '$no',
          style: TextStyle(
            color: isLight ? Colors.black : Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.grey.shade800.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 1),
            Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _PerformanceBadge extends StatelessWidget {
  final String label;
  final String value;

  const _PerformanceBadge({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label ',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
