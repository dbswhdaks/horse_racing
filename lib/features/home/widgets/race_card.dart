import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/race.dart';

class RaceCard extends StatelessWidget {
  final Race race;
  final int? headCount;
  final VoidCallback onTap;
  final VoidCallback? onResultTap;

  const RaceCard({
    super.key,
    required this.race,
    this.headCount,
    required this.onTap,
    this.onResultTap,
  });

  @override
  Widget build(BuildContext context) {
    final status = _raceStatus();
    final timeStr = _formatTime(race.startTime);
    final countdown = _countdown();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RaceNumberBadge(raceNo: race.raceNo),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
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
                            ),
                            const SizedBox(width: 8),
                            _StatusBadge(status: status),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${race.meetName}  •  ${race.gradeLabel}  •  ${race.distanceLabel}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (timeStr.isNotEmpty)
                        Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.accentGold,
                          ),
                        ),
                      if (countdown.isNotEmpty)
                        Text(
                          countdown,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: status == _RaceStatus.live
                                ? AppTheme.negativeRed
                                : AppTheme.positiveGreen,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if ((headCount ?? race.headCount) > 0)
                          _MiniStat(
                            icon: Icons.groups_rounded,
                            value: '${headCount ?? race.headCount}두',
                          ),
                        _MiniStat(
                          icon: Icons.straighten_rounded,
                          value: race.distanceLabel,
                        ),
                        if (race.ageCondition.isNotEmpty)
                          _MiniStat(
                            icon: Icons.cake_rounded,
                            value: race.ageCondition,
                          ),
                        if (race.sexCondition.isNotEmpty)
                          _MiniStat(
                            icon: Icons.wc_rounded,
                            value: race.sexCondition,
                          ),
                      ],
                    ),
                  ),
                  if (onResultTap != null &&
                      status == _RaceStatus.finished)
                    GestureDetector(
                      onTap: onResultTap,
                      child: Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.winColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.emoji_events_rounded,
                                size: 13, color: AppTheme.winColor),
                            const SizedBox(width: 3),
                            Text(
                              '결과',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.winColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (race.prize1 > 0)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.accentGold.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.monetization_on_rounded,
                              size: 13, color: AppTheme.accentGold),
                          const SizedBox(width: 3),
                          Text(
                            _formatPrize(race.prize1),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.accentGold,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  DateTime? _raceDay() {
    if (race.raceDate.length < 8) return null;
    final y = int.tryParse(race.raceDate.substring(0, 4));
    final mo = int.tryParse(race.raceDate.substring(4, 6));
    final d = int.tryParse(race.raceDate.substring(6, 8));
    if (y == null || mo == null || d == null) return null;
    return DateTime(y, mo, d);
  }

  DateTime? _startDateTime() {
    if (race.startTime.isEmpty || race.startTime.length < 4) return null;
    final h = int.tryParse(race.startTime.substring(0, 2)) ?? 0;
    final m = int.tryParse(race.startTime.substring(2, 4)) ?? 0;
    final day = _raceDay();
    if (day != null) return DateTime(day.year, day.month, day.day, h, m);
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, h, m);
  }

  _RaceStatus _raceStatus() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = _raceDay();

    if (day != null && day.isBefore(today)) return _RaceStatus.finished;
    if (day != null && day.isAfter(today)) return _RaceStatus.upcoming;

    final start = _startDateTime();
    if (start == null) return _RaceStatus.upcoming;
    final diff = start.difference(now).inMinutes;
    if (diff > 0) return _RaceStatus.upcoming;
    if (diff > -30) return _RaceStatus.live;
    return _RaceStatus.finished;
  }

  String _countdown() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = _raceDay();

    if (day != null && day.isBefore(today)) return '';
    if (day != null && day.isAfter(today)) {
      final daysLeft = day.difference(today).inDays;
      return '$daysLeft일 후';
    }

    final start = _startDateTime();
    if (start == null) return '';
    final diff = start.difference(now);
    if (diff.isNegative && diff.inMinutes < -30) return '';
    if (diff.isNegative) return '진행중';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 후';
    final hours = diff.inHours;
    final mins = diff.inMinutes % 60;
    return '$hours시간 $mins분 후';
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

enum _RaceStatus { upcoming, live, finished }

class _StatusBadge extends StatelessWidget {
  final _RaceStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      _RaceStatus.upcoming => (
        '진행전',
        Colors.orange.shade900.withValues(alpha: 0.5),
        Colors.orange.shade300,
      ),
      _RaceStatus.live => (
        '진행중',
        AppTheme.negativeRed.withValues(alpha: 0.3),
        AppTheme.negativeRed,
      ),
      _RaceStatus.finished => (
        '종료',
        Colors.grey.shade800,
        Colors.grey.shade400,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class _RaceNumberBadge extends StatelessWidget {
  final int raceNo;

  const _RaceNumberBadge({required this.raceNo});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryGreen,
            AppTheme.primaryGreen.withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(11),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryGreen.withValues(alpha: 0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
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

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;

  const _MiniStat({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.grey.shade500),
        const SizedBox(width: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade400,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
