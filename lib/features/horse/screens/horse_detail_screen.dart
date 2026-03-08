import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../core/theme/app_theme.dart';

import '../../../models/race_entry.dart';
import '../../../models/race_result.dart';
import '../../race/providers/race_providers.dart';

class HorseDetailScreen extends ConsumerWidget {
  final String horseName;
  final String meet;
  final RaceEntry? entry;

  const HorseDetailScreen({
    super.key,
    required this.horseName,
    required this.meet,
    this.entry,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(
      horseResultsProvider((meet: meet, horseName: horseName)),
    );

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              title: Text(horseName),
              centerTitle: true,
            ),
            resultsAsync.when(
              loading: () => SliverList(
                delegate: SliverChildListDelegate([
                  if (entry != null) _ProfileCard(entry: entry!),
                  if (entry != null) _StatsOverview(results: const [], entry: entry),
                  const SizedBox(height: 40),
                  const Center(
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(
                          '서울·제주·부산 최근 12개월 경주 기록 수집 중...',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '잠시만 기다려주세요',
                          style: TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 60),
                ]),
              ),
              error: (err, _) => SliverFillRemaining(
                child: Center(child: Text('전적을 불러올 수 없습니다: $err')),
              ),
              data: (results) {
                return SliverList(
                  delegate: SliverChildListDelegate([
                    // 1) 프로필 카드
                    if (entry != null) _ProfileCard(entry: entry!),

                    // 2) 성적 요약
                    _StatsOverview(results: results, entry: entry),

                    // 3) 순위 추이 차트
                    if (results.length >= 2) ...[
                      const _SectionTitle('순위 추이'),
                      _RankChart(results: results),
                    ],

                    // 4) 거리별 성적
                    if (results.isNotEmpty) ...[
                      const _SectionTitle('거리별 성적'),
                      _DistanceStats(results: results),
                    ],

                    // 5) S1F / G3F 차트
                    if (results.any((r) =>
                        r.s1f.isNotEmpty && r.s1f != '0' && r.s1f != '0.0')) ...[
                      const _SectionTitle('구간 기록 (S1F / G3F)'),
                      _SplitTimesChart(results: results),
                    ],

                    // 6) 기수별 성적
                    if (results.isNotEmpty) ...[
                      const _SectionTitle('기수별 성적'),
                      _JockeyStats(results: results),
                    ],

                    // 7) 전체 경주 기록
                    _SectionTitle(
                      results.isEmpty
                          ? '경주 기록'
                          : '전체 경주 기록 (${results.length}건)',
                    ),
                    if (results.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            '최근 3개월 내 경주 기록이 없습니다',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      ...results.map((r) => _ResultTile(result: r)),

                    const SizedBox(height: 40),
                  ]),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━ Section Title ━━━━━━━━━━━━━━━━━━━━━━━

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
      child: Text(
        title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━ Profile Card ━━━━━━━━━━━━━━━━━━━━━━━

class _ProfileCard extends StatelessWidget {
  final RaceEntry entry;
  const _ProfileCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryGreen.withValues(alpha: 0.15),
            AppTheme.cardDark,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    '${entry.horseNo}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.primaryGreen,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.horseName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _buildSubtitle(),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (entry.sex.isNotEmpty) _InfoChip('성별', entry.sexLabel),
              if (entry.age > 0) _InfoChip('나이', '${entry.age}세'),
              if (entry.birthPlace.isNotEmpty)
                _InfoChip('출생', entry.birthPlace),
              if (entry.weight > 0)
                _InfoChip('부담중량', '${entry.weight.toStringAsFixed(1)}kg'),
              if (entry.horseWeight > 0)
                _InfoChip('마체중', '${entry.horseWeight.toStringAsFixed(0)}kg'),
              if (entry.rating > 0)
                _InfoChip('레이팅', entry.rating.toStringAsFixed(0)),
              if (entry.jockeyName.isNotEmpty)
                _InfoChip('기수', entry.jockeyName),
              if (entry.trainerName.isNotEmpty)
                _InfoChip('조교사', entry.trainerName),
              if (entry.ownerName.isNotEmpty)
                _InfoChip('마주', entry.ownerName),
            ],
          ),
        ],
      ),
    );
  }

  String _buildSubtitle() {
    final parts = <String>[];
    if (entry.sex.isNotEmpty) parts.add(entry.sexLabel);
    if (entry.age > 0) parts.add('${entry.age}세');
    if (entry.birthPlace.isNotEmpty) parts.add(entry.birthPlace);
    return parts.join(' · ');
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  const _InfoChip(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━ Stats Overview ━━━━━━━━━━━━━━━━━━━━━━━

class _StatsOverview extends StatelessWidget {
  final List<RaceResult> results;
  final RaceEntry? entry;
  const _StatsOverview({required this.results, this.entry});

  @override
  Widget build(BuildContext context) {
    final total = entry?.totalRaces ?? results.length;
    final wins = entry?.winCount ?? results.where((r) => r.rank == 1).length;
    final places =
        entry?.placeCount ?? results.where((r) => r.rank == 2).length;
    final thirds = results.where((r) => r.rank == 3).length;
    final totalFromResults = results.length;
    final placesFromResults =
        results.where((r) => r.rank >= 1 && r.rank <= 3).length;
    final winRate = total > 0 ? (wins / total * 100) : 0.0;
    final placeRate = total > 0 ? ((wins + places) / total * 100) : 0.0;
    final top3Rate =
        totalFromResults > 0 ? (placesFromResults / totalFromResults * 100) : 0.0;

    final totalPrize = entry?.totalPrize ?? 0;
    final recentPrize = entry?.recentPrize ?? 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatItem(label: '출주', value: '$total회'),
              _VDivider(),
              _StatItem(
                label: '전적',
                value: '$wins승 $places복 $thirds패',
                color: wins > 0 ? AppTheme.winColor : null,
              ),
              _VDivider(),
              _StatItem(
                label: '승률',
                value: '${winRate.toStringAsFixed(1)}%',
                color: winRate >= 20 ? AppTheme.positiveGreen : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatItem(
                label: '입상률',
                value: '${placeRate.toStringAsFixed(1)}%',
                color: placeRate >= 30 ? AppTheme.positiveGreen : null,
              ),
              _VDivider(),
              _StatItem(
                label: 'TOP3율',
                value: '${top3Rate.toStringAsFixed(1)}%',
                color: top3Rate >= 30 ? Colors.cyanAccent : null,
              ),
              _VDivider(),
              if (totalPrize > 0)
                _StatItem(
                  label: '총상금',
                  value: _formatPrize(totalPrize),
                  color: AppTheme.accentGold,
                )
              else
                _StatItem(
                  label: '최근상금',
                  value: recentPrize > 0 ? _formatPrize(recentPrize) : '-',
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatPrize(int prize) {
    if (prize >= 10000) return '${(prize / 10000).toStringAsFixed(0)}억';
    if (prize >= 1000) return '${(prize / 1000).toStringAsFixed(1)}천만';
    return '$prize만';
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _StatItem({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _VDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 36, color: Colors.grey.shade700);
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━ Rank Chart ━━━━━━━━━━━━━━━━━━━━━━━

class _RankChart extends StatelessWidget {
  final List<RaceResult> results;
  const _RankChart({required this.results});

  @override
  Widget build(BuildContext context) {
    final recent =
        results.where((r) => r.rank > 0).take(15).toList().reversed.toList();
    if (recent.length < 2) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('데이터가 부족합니다'),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: 220,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: LineChart(
        LineChartData(
          minY: 0.5,
          maxY: 14.5,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 3,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.grey.shade800,
              strokeWidth: 0.5,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= recent.length) {
                    return const SizedBox.shrink();
                  }
                  final date = recent[idx].raceDate;
                  final label = date.length >= 8
                      ? '${date.substring(4, 6)}/${date.substring(6, 8)}'
                      : '$idx';
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(label,
                        style: TextStyle(
                            fontSize: 9, color: Colors.grey.shade500)),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 3,
                getTitlesWidget: (value, meta) => Text(
                  '${value.toInt()}',
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: recent.asMap().entries.map((e) {
                final rank =
                    e.value.rank > 0 ? e.value.rank.toDouble() : 14.0;
                return FlSpot(e.key.toDouble(), rank);
              }).toList(),
              isCurved: true,
              color: AppTheme.accentGold,
              barWidth: 3,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, pct, bar, idx) {
                  Color c;
                  double r;
                  if (spot.y == 1) {
                    c = AppTheme.winColor;
                    r = 6;
                  } else if (spot.y <= 3) {
                    c = AppTheme.placeColor;
                    r = 4;
                  } else {
                    c = AppTheme.accentGold;
                    r = 3;
                  }
                  return FlDotCirclePainter(
                    radius: r,
                    color: c,
                    strokeColor: Colors.transparent,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                color: AppTheme.accentGold.withValues(alpha: 0.08),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots.map((spot) {
                final idx = spot.x.toInt();
                final r = idx < recent.length ? recent[idx] : null;
                final date = r != null && r.raceDate.length >= 8
                    ? '${r.raceDate.substring(4, 6)}/${r.raceDate.substring(6, 8)}'
                    : '';
                return LineTooltipItem(
                  '$date ${spot.y.toInt()}착',
                  const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 12),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━ Distance Stats ━━━━━━━━━━━━━━━━━━━━━━━

class _DistanceStats extends StatelessWidget {
  final List<RaceResult> results;
  const _DistanceStats({required this.results});

  @override
  Widget build(BuildContext context) {
    final distMap = <int, _DistStat>{};
    for (final r in results) {
      if (r.distance <= 0) continue;
      final stat = distMap.putIfAbsent(r.distance, () => _DistStat(r.distance));
      stat.total++;
      if (r.rank == 1) stat.wins++;
      if (r.rank >= 1 && r.rank <= 3) stat.places++;
      if (r.rank > 0) {
        stat.totalRank += r.rank;
        stat.rankedCount++;
      }
    }

    final sorted = distMap.values.toList()
      ..sort((a, b) => a.distance.compareTo(b.distance));

    if (sorted.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('거리 데이터가 없습니다'),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: sorted.map((stat) {
          final winRate =
              stat.total > 0 ? (stat.wins / stat.total * 100) : 0.0;
          final placeRate =
              stat.total > 0 ? (stat.places / stat.total * 100) : 0.0;
          final avgRank =
              stat.rankedCount > 0 ? stat.totalRank / stat.rankedCount : 0.0;

          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${stat.distance}m',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primaryGreen,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _MiniStat(
                          '출주', '${stat.total}회', Colors.grey.shade300),
                      _MiniStat(
                        '승률',
                        '${winRate.toStringAsFixed(0)}%',
                        winRate > 0
                            ? AppTheme.positiveGreen
                            : Colors.grey.shade500,
                      ),
                      _MiniStat(
                        '입상',
                        '${placeRate.toStringAsFixed(0)}%',
                        placeRate > 0
                            ? Colors.cyanAccent
                            : Colors.grey.shade500,
                      ),
                      _MiniStat(
                        '평균',
                        avgRank > 0
                            ? '${avgRank.toStringAsFixed(1)}착'
                            : '-',
                        avgRank > 0 && avgRank <= 3
                            ? AppTheme.accentGold
                            : Colors.grey.shade400,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _DistStat {
  final int distance;
  int total = 0;
  int wins = 0;
  int places = 0;
  int totalRank = 0;
  int rankedCount = 0;
  _DistStat(this.distance);
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━ Split Times Chart ━━━━━━━━━━━━━━━━━━━━━━━

class _SplitTimesChart extends StatelessWidget {
  final List<RaceResult> results;
  const _SplitTimesChart({required this.results});

  @override
  Widget build(BuildContext context) {
    final withTimes = results.where((r) {
      final s = double.tryParse(r.s1f) ?? 0;
      final g = double.tryParse(r.g3f) ?? 0;
      return s > 0 || g > 0;
    }).take(15).toList().reversed.toList();

    if (withTimes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('구간 기록 데이터가 없습니다'),
      );
    }

    final s1fValues =
        withTimes.map((r) => double.tryParse(r.s1f) ?? 0).toList();
    final g3fValues =
        withTimes.map((r) => double.tryParse(r.g3f) ?? 0).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: 200,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, gIdx, rod, rIdx) {
                final label = rIdx == 0 ? 'S1F' : 'G3F';
                return BarTooltipItem(
                  '$label: ${rod.toY.toStringAsFixed(1)}초',
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                );
              },
            ),
          ),
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (v) => FlLine(
              color: Colors.grey.shade800,
              strokeWidth: 0.5,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= withTimes.length) {
                    return const SizedBox.shrink();
                  }
                  final date = withTimes[idx].raceDate;
                  final label = date.length >= 8
                      ? '${date.substring(4, 6)}/${date.substring(6, 8)}'
                      : '${idx + 1}';
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(label,
                        style: TextStyle(
                            fontSize: 9, color: Colors.grey.shade500)),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (v, meta) => Text(
                  '${v.toStringAsFixed(0)}초',
                  style:
                      TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(
            withTimes.length,
            (i) {
              final rods = <BarChartRodData>[];
              if (i < s1fValues.length && s1fValues[i] > 0) {
                rods.add(BarChartRodData(
                  toY: s1fValues[i],
                  color: Colors.cyanAccent,
                  width: 7,
                  borderRadius: BorderRadius.circular(3),
                ));
              }
              if (i < g3fValues.length && g3fValues[i] > 0) {
                rods.add(BarChartRodData(
                  toY: g3fValues[i],
                  color: Colors.orangeAccent,
                  width: 7,
                  borderRadius: BorderRadius.circular(3),
                ));
              }
              return BarChartGroupData(x: i, barRods: rods);
            },
          ),
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━ Jockey Stats ━━━━━━━━━━━━━━━━━━━━━━━

class _JockeyStats extends StatelessWidget {
  final List<RaceResult> results;
  const _JockeyStats({required this.results});

  @override
  Widget build(BuildContext context) {
    final jockeys = <String, _JockeyStat>{};
    for (final r in results) {
      if (r.jockeyName.isEmpty) continue;
      final stat = jockeys.putIfAbsent(
        r.jockeyName,
        () => _JockeyStat(r.jockeyName),
      );
      stat.total++;
      if (r.rank == 1) stat.wins++;
      if (r.rank >= 1 && r.rank <= 3) stat.places++;
    }

    final sorted = jockeys.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    if (sorted.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('기수 데이터가 없습니다'),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: sorted.take(5).map((stat) {
          final winRate =
              stat.total > 0 ? stat.wins / stat.total * 100 : 0.0;
          final placeRate =
              stat.total > 0 ? stat.places / stat.total * 100 : 0.0;

          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.person, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    stat.name,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${stat.total}전 ${stat.wins}승',
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade400),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: winRate >= 30
                        ? AppTheme.positiveGreen.withValues(alpha: 0.2)
                        : Colors.grey.shade800,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '승률 ${winRate.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: winRate >= 30
                          ? AppTheme.positiveGreen
                          : Colors.grey.shade300,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: placeRate >= 40
                        ? Colors.cyanAccent.withValues(alpha: 0.15)
                        : Colors.grey.shade800,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '입상 ${placeRate.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: placeRate >= 40
                          ? Colors.cyanAccent
                          : Colors.grey.shade300,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _JockeyStat {
  final String name;
  int total = 0;
  int wins = 0;
  int places = 0;
  _JockeyStat(this.name);
}

// ━━━━━━━━━━━━━━━━━━━━━━━ Result Tile ━━━━━━━━━━━━━━━━━━━━━━━

class _ResultTile extends StatelessWidget {
  final RaceResult result;
  const _ResultTile({required this.result});

  @override
  Widget build(BuildContext context) {
    final isTop3 = result.rank >= 1 && result.rank <= 3;
    final rankColor = result.rank == 1
        ? AppTheme.winColor
        : result.rank == 2
            ? AppTheme.placeColor
            : result.rank == 3
                ? AppTheme.showColor
                : Colors.grey.shade400;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isTop3
            ? BorderSide(color: rankColor.withValues(alpha: 0.3))
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                // 순위 배지
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        rankColor.withValues(alpha: 0.25),
                        rankColor.withValues(alpha: 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: result.rank > 0
                        ? Text(
                            result.rankLabel,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: rankColor,
                            ),
                          )
                        : Text(
                            result.rankRaw.length > 2
                                ? result.rankRaw.substring(0, 2)
                                : result.rankRaw.isEmpty
                                    ? '-'
                                    : result.rankRaw,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade500,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),

                // 날짜 + 기본정보
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _formatDate(result.raceDate),
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                          if (result.raceNo > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade800,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${result.raceNo}R',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _buildInfoLine(),
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // 기록 + 배당
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (_hasValidTime(result.raceTime))
                      Text(
                        result.raceTime,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: isTop3 ? rankColor : null,
                        ),
                      ),
                    if (result.winOdds > 0)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppTheme.accentGold.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${result.winOdds.toStringAsFixed(1)}배',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.accentGold,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),

            // 하단 세부 스탯
            if (_hasDetails()) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (result.weight > 0)
                    _SmallChip('부담 ${result.weight.toStringAsFixed(0)}kg'),
                  if (result.horseWeight > 0)
                    _SmallChip(
                        '마체중 ${result.horseWeight.toStringAsFixed(0)}kg'),
                  if (_hasValidStr(result.passOrder))
                    _SmallChip('통과 ${result.passOrder}'),
                  if (_hasValidStr(result.s1f)) _SmallChip('S1F ${result.s1f}'),
                  if (_hasValidStr(result.g3f)) _SmallChip('G3F ${result.g3f}'),
                  if (result.rankDiff.isNotEmpty &&
                      result.rankDiff != '0' &&
                      result.rankDiff != '0.0' &&
                      result.rankDiff != '-')
                    _SmallChip('착차 ${result.rankDiff}'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(String d) {
    if (d.length >= 8) {
      return '${d.substring(0, 4)}.${d.substring(4, 6)}.${d.substring(6, 8)}';
    }
    return d;
  }

  static const _meetNames = {'1': '서울', '2': '제주', '3': '부산경남'};

  String _buildInfoLine() {
    final parts = <String>[];
    final meetName = _meetNames[result.meet];
    if (meetName != null) parts.add(meetName);
    if (result.distance > 0) parts.add('${result.distance}m');
    if (result.jockeyName.isNotEmpty) parts.add(result.jockeyName);
    if (result.trainerName.isNotEmpty) parts.add(result.trainerName);
    return parts.join(' · ');
  }

  bool _hasDetails() =>
      result.weight > 0 ||
      result.horseWeight > 0 ||
      _hasValidStr(result.passOrder) ||
      _hasValidStr(result.s1f) ||
      _hasValidStr(result.g3f);

  static bool _hasValidTime(String t) =>
      t.isNotEmpty && t != '0.0' && t != '0' && t != '0:00.0';

  static bool _hasValidStr(String s) =>
      s.isNotEmpty && s != '0' && s != '0.0';
}

class _SmallChip extends StatelessWidget {
  final String text;
  const _SmallChip(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
      ),
    );
  }
}
