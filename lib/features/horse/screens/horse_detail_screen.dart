import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../../models/race_result.dart';
import '../../race/providers/race_providers.dart';

class HorseDetailScreen extends ConsumerWidget {
  final String horseName;
  final String meet;

  const HorseDetailScreen({
    super.key,
    required this.horseName,
    required this.meet,
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
            ),
            resultsAsync.when(
              loading: () => SliverFillRemaining(
                child: ShimmerCardList(cardHeight: 80),
              ),
              error: (err, _) => SliverFillRemaining(
                child: Center(child: Text('전적을 불러올 수 없습니다: $err')),
              ),
              data: (results) {
                if (results.isEmpty) {
                  return const SliverFillRemaining(
                    child: Center(child: Text('최근 경주 기록이 없습니다')),
                  );
                }
                return SliverList(
                  delegate: SliverChildListDelegate([
                    _StatsOverview(results: results),
                    _SectionTitle('최근 순위 추이'),
                    _RankChart(results: results),
                    _SectionTitle('S1F / G3F 기록'),
                    _SplitTimesChart(results: results),
                    _SectionTitle('기수별 성적'),
                    _JockeyStats(results: results),
                    _SectionTitle('최근 경주 기록'),
                    ...results.take(10).map(
                          (r) => _ResultTile(result: r),
                        ),
                    const SizedBox(height: 32),
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

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _StatsOverview extends StatelessWidget {
  final List<RaceResult> results;
  const _StatsOverview({required this.results});

  @override
  Widget build(BuildContext context) {
    final total = results.length;
    final wins = results.where((r) => r.rank == 1).length;
    final places = results.where((r) => r.rank >= 1 && r.rank <= 3).length;
    final winRate = total > 0 ? (wins / total * 100) : 0.0;
    final placeRate = total > 0 ? (places / total * 100) : 0.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryGreen.withValues(alpha: 0.25),
            AppTheme.cardDark,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _StatItem(label: '출주', value: '$total회'),
          _Divider(),
          _StatItem(
            label: '승률',
            value: '${winRate.toStringAsFixed(1)}%',
            color:
                winRate >= 20 ? AppTheme.positiveGreen : null,
          ),
          _Divider(),
          _StatItem(
            label: '복승률',
            value: '${placeRate.toStringAsFixed(1)}%',
            color:
                placeRate >= 40 ? AppTheme.positiveGreen : null,
          ),
          _Divider(),
          _StatItem(label: '1착', value: '$wins회', color: AppTheme.winColor),
        ],
      ),
    );
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
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      color: Colors.grey.shade700,
    );
  }
}

class _RankChart extends StatelessWidget {
  final List<RaceResult> results;
  const _RankChart({required this.results});

  @override
  Widget build(BuildContext context) {
    final recent = results.take(10).toList().reversed.toList();
    if (recent.length < 2) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('데이터가 부족합니다'),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: 200,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: LineChart(
        LineChartData(
          minY: 0.5,
          maxY: 12.5,
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
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
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
                    child: Text(
                      label,
                      style: TextStyle(
                          fontSize: 10, color: Colors.grey.shade500),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 3,
                getTitlesWidget: (value, meta) {
                  return Text(
                    '${value.toInt()}',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: recent.asMap().entries.map((e) {
                final rank = e.value.rank > 0 ? e.value.rank.toDouble() : 12.0;
                return FlSpot(e.key.toDouble(), rank);
              }).toList(),
              isCurved: true,
              color: AppTheme.accentGold,
              barWidth: 3,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, pct, bar, idx) {
                  final isWin = spot.y == 1;
                  return FlDotCirclePainter(
                    radius: isWin ? 5 : 3,
                    color: isWin ? AppTheme.winColor : AppTheme.accentGold,
                    strokeColor: Colors.transparent,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                color: AppTheme.accentGold.withValues(alpha: 0.1),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) {
                return spots.map((spot) {
                  return LineTooltipItem(
                    '${spot.y.toInt()}착',
                    const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SplitTimesChart extends StatelessWidget {
  final List<RaceResult> results;
  const _SplitTimesChart({required this.results});

  @override
  Widget build(BuildContext context) {
    final withS1f = results.where((r) => r.s1f.isNotEmpty).take(10).toList();
    final withG3f = results.where((r) => r.g3f.isNotEmpty).take(10).toList();

    if (withS1f.isEmpty && withG3f.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('구간 기록 데이터가 없습니다'),
      );
    }

    final s1fValues = withS1f.reversed
        .map((r) => double.tryParse(r.s1f) ?? 0)
        .where((v) => v > 0)
        .toList();
    final g3fValues = withG3f.reversed
        .map((r) => double.tryParse(r.g3f) ?? 0)
        .where((v) => v > 0)
        .toList();

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
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${value.toInt() + 1}',
                      style: TextStyle(
                          fontSize: 10, color: Colors.grey.shade500),
                    ),
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
            s1fValues.length.clamp(0, g3fValues.length.clamp(0, 10)),
            (i) {
              return BarChartGroupData(
                x: i,
                barRods: [
                  if (i < s1fValues.length)
                    BarChartRodData(
                      toY: s1fValues[i],
                      color: Colors.cyanAccent,
                      width: 8,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  if (i < g3fValues.length)
                    BarChartRodData(
                      toY: g3fValues[i],
                      color: Colors.orangeAccent,
                      width: 8,
                      borderRadius: BorderRadius.circular(3),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

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
          final winRate = stat.total > 0 ? stat.wins / stat.total * 100 : 0.0;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.person, size: 20),
                const SizedBox(width: 10),
                Text(
                  stat.name,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  '${stat.total}전 ${stat.wins}승',
                  style:
                      TextStyle(fontSize: 13, color: Colors.grey.shade400),
                ),
                const SizedBox(width: 12),
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
                    '${winRate.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: winRate >= 30
                          ? AppTheme.positiveGreen
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

class _ResultTile extends StatelessWidget {
  final RaceResult result;
  const _ResultTile({required this.result});

  @override
  Widget build(BuildContext context) {
    final rankColor = result.rank == 1
        ? AppTheme.winColor
        : result.rank == 2
            ? AppTheme.placeColor
            : result.rank == 3
                ? AppTheme.showColor
                : Colors.grey.shade400;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: rankColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  result.rankLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: rankColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatDate(result.raceDate),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${result.distance}m | ${result.jockeyName} | ${result.weight.toStringAsFixed(0)}kg',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  result.raceTime,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
                if (result.passOrder.isNotEmpty)
                  Text(
                    result.passOrder,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500),
                  ),
              ],
            ),
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
}
