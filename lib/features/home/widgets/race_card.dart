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
    final isLive = status == _RaceStatus.live;

    final borderColor = isLive
        ? AppTheme.negativeRed.withValues(alpha: 0.35)
        : Colors.white.withValues(alpha: 0.06);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: AppTheme.accentGold.withValues(alpha: 0.08),
          highlightColor: AppTheme.accentGold.withValues(alpha: 0.04),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1F1F1F), Color(0xFF151515)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: 1),
              boxShadow: [
                BoxShadow(
                  color: isLive
                      ? AppTheme.negativeRed.withValues(alpha: 0.18)
                      : Colors.black.withValues(alpha: 0.35),
                  blurRadius: isLive ? 20 : 10,
                  spreadRadius: isLive ? -3 : -1,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 13, 14, 11),
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
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.3,
                                      color: Colors.white,
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
                              '${race.meetName}  ·  ${race.gradeLabel}  ·  ${race.distanceLabel}',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey.shade400,
                                fontWeight: FontWeight.w500,
                                letterSpacing: -0.1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.accentGold,
                                letterSpacing: -0.5,
                                shadows: [
                                  Shadow(
                                    color: AppTheme.accentGold
                                        .withValues(alpha: 0.4),
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                            ),
                          if (countdown.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                countdown,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isLive
                                      ? AppTheme.negativeRed
                                      : AppTheme.positiveGreen,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 9, 14, 11),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.025),
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
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
                                horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppTheme.winColor.withValues(alpha: 0.20),
                                  AppTheme.winColor.withValues(alpha: 0.08),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                color:
                                    AppTheme.winColor.withValues(alpha: 0.35),
                              ),
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
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.winColor,
                                    letterSpacing: -0.2,
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
                              horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppTheme.accentGold.withValues(alpha: 0.22),
                                AppTheme.accentGold.withValues(alpha: 0.08),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(
                              color: AppTheme.accentGold
                                  .withValues(alpha: 0.35),
                            ),
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
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.accentGold,
                                  letterSpacing: -0.2,
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
    final (label, color) = switch (status) {
      _RaceStatus.upcoming => ('진행전', Colors.orange.shade400),
      _RaceStatus.live => ('진행중', AppTheme.negativeRed),
      _RaceStatus.finished => ('종료', Colors.grey.shade500),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.2,
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
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF2E7D32),
            AppTheme.primaryGreen,
            const Color(0xFF0D3810),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.6, 1.0],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.accentGold.withValues(alpha: 0.28),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryGreen.withValues(alpha: 0.45),
            blurRadius: 10,
            spreadRadius: -2,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: Text(
          '$raceNo',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            shadows: [
              Shadow(
                color: Colors.black45,
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
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
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.grey.shade500),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade300,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}
