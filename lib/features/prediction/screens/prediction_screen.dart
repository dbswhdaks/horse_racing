import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../../models/prediction.dart';
import '../../race/providers/race_providers.dart';

class PredictionScreen extends ConsumerWidget {
  final String meet;
  final String date;
  final int raceNo;

  const PredictionScreen({
    super.key,
    required this.meet,
    required this.date,
    required this.raceNo,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final predAsync = ref.watch(
      predictionProvider((meet: meet, date: date, raceNo: raceNo)),
    );
    final meetName = ApiConstants.meetNames[meet] ?? meet;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              title: Text('AI 예측 - $meetName ${raceNo}R'),
            ),
            predAsync.when(
              loading: () => SliverFillRemaining(
                child: ShimmerCardList(cardHeight: 80),
              ),
              error: (err, _) => SliverFillRemaining(
                child: _OfflineView(),
              ),
              data: (report) {
                if (report == null) {
                  return SliverFillRemaining(child: _OfflineView());
                }
                return SliverList(
                  delegate: SliverChildListDelegate([
                    _ModelInfoCard(report: report),
                    const _SectionTitle('우승 확률'),
                    _WinProbabilityChart(predictions: report.predictions),
                    const _SectionTitle('복승 확률'),
                    _PlaceProbabilityChart(predictions: report.predictions),
                    const _SectionTitle('상세 분석'),
                    ...report.predictions.map(
                      (p) => _PredictionDetailCard(prediction: p),
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

class _OfflineView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 64, color: Colors.purple.shade300),
            const SizedBox(height: 16),
            const Text(
              '예측 데이터 준비 중',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '출전표 API 활용 신청 후\n출마 데이터 기반 AI 예측이 제공됩니다',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Text(
              'data.go.kr → 한국마사회 출전표상세정보 활용 신청',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
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

class _ModelInfoCard extends StatelessWidget {
  final PredictionReport report;
  const _ModelInfoCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade900.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.deepPurple.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome,
              color: Colors.purpleAccent.shade100, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI 예측 리포트',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '모델 v${report.modelVersion} | ${report.predictions.length}두 분석',
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade400),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.positiveGreen.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'XGBoost',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.positiveGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WinProbabilityChart extends StatelessWidget {
  final List<Prediction> predictions;
  const _WinProbabilityChart({required this.predictions});

  @override
  Widget build(BuildContext context) {
    final sorted = [...predictions]
      ..sort((a, b) => b.winProbability.compareTo(a.winProbability));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: 220,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: (sorted.first.winProbability * 1.2).clamp(10, 100),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, gIdx, rod, rIdx) {
                final p = sorted[group.x.toInt()];
                return BarTooltipItem(
                  '${p.horseName}\n${p.winProbability.toStringAsFixed(1)}%',
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                );
              },
            ),
          ),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: 10,
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
                  if (idx < 0 || idx >= sorted.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${sorted[idx].horseNo}번',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade400),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                interval: 10,
                getTitlesWidget: (v, meta) => Text(
                  '${v.toInt()}%',
                  style:
                      TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: sorted.asMap().entries.map((e) {
            final idx = e.key;
            final p = e.value;
            final isTop = idx < 3;
            return BarChartGroupData(
              x: idx,
              barRods: [
                BarChartRodData(
                  toY: p.winProbability,
                  width: sorted.length > 8 ? 12 : 18,
                  borderRadius: BorderRadius.circular(4),
                  gradient: isTop
                      ? LinearGradient(
                          colors: [
                            Colors.purpleAccent,
                            Colors.deepPurple.shade300,
                          ],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        )
                      : null,
                  color: isTop ? null : Colors.grey.shade700,
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _PlaceProbabilityChart extends StatelessWidget {
  final List<Prediction> predictions;
  const _PlaceProbabilityChart({required this.predictions});

  @override
  Widget build(BuildContext context) {
    final sorted = [...predictions]
      ..sort((a, b) => b.placeProbability.compareTo(a.placeProbability));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: 220,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: (sorted.first.placeProbability * 1.2).clamp(10, 100),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, gIdx, rod, rIdx) {
                final p = sorted[group.x.toInt()];
                return BarTooltipItem(
                  '${p.horseName}\n${p.placeProbability.toStringAsFixed(1)}%',
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                );
              },
            ),
          ),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: 10,
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
                  if (idx < 0 || idx >= sorted.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${sorted[idx].horseNo}번',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade400),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                interval: 10,
                getTitlesWidget: (v, meta) => Text(
                  '${v.toInt()}%',
                  style:
                      TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: sorted.asMap().entries.map((e) {
            final idx = e.key;
            final p = e.value;
            final isTop = idx < 3;
            return BarChartGroupData(
              x: idx,
              barRods: [
                BarChartRodData(
                  toY: p.placeProbability,
                  width: sorted.length > 8 ? 12 : 18,
                  borderRadius: BorderRadius.circular(4),
                  gradient: isTop
                      ? LinearGradient(
                          colors: [
                            Colors.tealAccent.shade400,
                            Colors.teal.shade600,
                          ],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        )
                      : null,
                  color: isTop ? null : Colors.grey.shade700,
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _PredictionDetailCard extends StatelessWidget {
  final Prediction prediction;
  const _PredictionDetailCard({required this.prediction});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '${prediction.horseNo}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    prediction.horseName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '승 ${prediction.winProbability.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: prediction.winProbability >= 15
                            ? AppTheme.positiveGreen
                            : null,
                      ),
                    ),
                    Text(
                      '복 ${prediction.placeProbability.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (prediction.tags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: prediction.tags.map((tag) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade300,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            if (prediction.featureImportance.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...prediction.featureImportance.entries.take(5).map((e) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 80,
                        child: Text(
                          e.key,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500),
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: e.value.clamp(0, 1),
                            backgroundColor: Colors.grey.shade800,
                            valueColor: AlwaysStoppedAnimation(
                              Colors.purpleAccent.withValues(alpha: 0.6),
                            ),
                            minHeight: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(e.value * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade400),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
