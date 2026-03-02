import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/race.dart';

class RaceCard extends StatelessWidget {
  final Race race;
  final VoidCallback onTap;

  const RaceCard({super.key, required this.race, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _RaceNumberBadge(raceNo: race.raceNo),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          race.raceName.isNotEmpty
                              ? race.raceName
                              : '${race.raceNo}경주',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${race.meetName} | ${race.gradeLabel}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (race.startTime.isNotEmpty)
                        Text(
                          _formatTime(race.startTime),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.accentGold,
                          ),
                        ),
                      const SizedBox(height: 2),
                      Text(
                        race.distanceLabel,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _InfoChip(
                    icon: Icons.people,
                    label: '${race.headCount}두',
                  ),
                  if (race.ageCondition.isNotEmpty)
                    _InfoChip(
                      icon: Icons.cake,
                      label: race.ageCondition,
                    ),
                  if (race.sexCondition.isNotEmpty)
                    _InfoChip(
                      icon: Icons.wc,
                      label: race.sexCondition,
                    ),
                  if (race.prize1 > 0)
                    _InfoChip(
                      icon: Icons.monetization_on,
                      label: _formatPrize(race.prize1),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(String time) {
    if (time.length >= 4) {
      return '${time.substring(0, 2)}:${time.substring(2, 4)}';
    }
    return time;
  }

  String _formatPrize(int prize) {
    if (prize >= 10000) {
      return '${(prize / 10000).toStringAsFixed(0)}만';
    }
    return '$prize원';
  }
}

class _RaceNumberBadge extends StatelessWidget {
  final int raceNo;

  const _RaceNumberBadge({required this.raceNo});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppTheme.primaryGreen,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          '$raceNo',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade800.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade400),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade300),
          ),
        ],
      ),
    );
  }
}
