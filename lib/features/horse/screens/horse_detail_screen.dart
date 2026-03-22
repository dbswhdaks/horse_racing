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

                    // 2) 레이팅
                    if (entry != null && entry!.rating > 0) ...[
                      const _SectionTitle('레이팅'),
                      _RatingGauge(entry: entry!, results: results),
                    ],

                    // 3) 훈련 컨디션
                    if (results.isNotEmpty) ...[
                      const _SectionTitle('훈련 컨디션'),
                      _TrainingCondition(results: results),
                    ],

                    // 4) 최근 5경주 성적
                    if (results.isNotEmpty) ...[
                      const _SectionTitle('최근 5경주 성적'),
                      _Recent5Races(results: results),
                    ],

                    // 4) 부담중량 분석
                    if (results.isNotEmpty) ...[
                      const _SectionTitle('부담중량'),
                      _WeightAnalysis(results: results, currentWeight: entry?.weight),
                    ],

                    // 5) 거리 적성
                    if (results.isNotEmpty) ...[
                      const _SectionTitle('거리 적성'),
                      _DistanceAptitude(results: results),
                    ],

                    // 6) 기수 승률
                    if (results.isNotEmpty) ...[
                      const _SectionTitle('기수 승률'),
                      _JockeyWinRate(results: results, currentJockey: entry?.jockeyName),
                    ],

                    // 7) 마체중 변화
                    if (results.where((r) => r.horseWeight > 0).length >= 2) ...[
                      const _SectionTitle('마체중 변화'),
                      _HorseWeightTrend(results: results, currentWeight: entry?.horseWeight),
                    ],

                    // 8) 최근 성적 추이 그래프
                    if (results.length >= 2) ...[
                      const _SectionTitle('성적 추이 그래프'),
                      _RecentPerformanceChart(results: results),
                    ],

                    // 9) S1F / G3F 차트
                    if (results.any((r) =>
                        r.s1f.isNotEmpty && r.s1f != '0' && r.s1f != '0.0')) ...[
                      const _SectionTitle('구간 기록 (S1F / G3F)'),
                      _SplitTimesChart(results: results),
                    ],

                    // 10) 전체 경주 기록
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
            children: [
              Expanded(child: _StatItem(label: '출주', value: '$total회')),
              _VDivider(),
              Expanded(
                child: _StatItem(
                  label: '전적',
                  value: '$wins승 $places복 $thirds패',
                  color: wins > 0 ? AppTheme.winColor : null,
                ),
              ),
              _VDivider(),
              Expanded(
                child: _StatItem(
                  label: '승률',
                  value: '${winRate.toStringAsFixed(1)}%',
                  color: winRate >= 20 ? AppTheme.positiveGreen : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatItem(
                  label: '입상률',
                  value: '${placeRate.toStringAsFixed(1)}%',
                  color: placeRate >= 30 ? AppTheme.positiveGreen : null,
                ),
              ),
              _VDivider(),
              Expanded(
                child: _StatItem(
                  label: 'TOP3율',
                  value: '${top3Rate.toStringAsFixed(1)}%',
                  color: top3Rate >= 30 ? Colors.cyanAccent : null,
                ),
              ),
              _VDivider(),
              Expanded(
                child: totalPrize > 0
                    ? _StatItem(
                        label: '총상금',
                        value: _formatPrize(totalPrize),
                        color: AppTheme.accentGold,
                      )
                    : _StatItem(
                        label: '최근상금',
                        value: recentPrize > 0 ? _formatPrize(recentPrize) : '-',
                      ),
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
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

// ━━━━━━━━━━━━━━━━━━━━━━━ Training Condition ━━━━━━━━━━━━━━━━━━━━━━━

class _TrainingCondition extends StatelessWidget {
  final List<RaceResult> results;
  const _TrainingCondition({required this.results});

  @override
  Widget build(BuildContext context) {
    final analysis = _analyzeCondition();

    final conditionColor = analysis.overall == '좋음'
        ? AppTheme.positiveGreen
        : analysis.overall == '보통'
            ? Colors.orangeAccent
            : Colors.redAccent;

    final conditionIcon = analysis.overall == '좋음'
        ? Icons.trending_up_rounded
        : analysis.overall == '보통'
            ? Icons.trending_flat_rounded
            : Icons.trending_down_rounded;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: conditionColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(conditionIcon, size: 32, color: conditionColor),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '컨디션',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                  Text(
                    analysis.overall,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: conditionColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _ConditionIndicator(
                  label: '기록 추이',
                  value: analysis.recordTrend,
                  isPositive: analysis.isRecordImproving,
                  icon: analysis.isRecordImproving
                      ? Icons.arrow_upward_rounded
                      : analysis.recordTrend == '유지'
                          ? Icons.remove_rounded
                          : Icons.arrow_downward_rounded,
                ),
              ),
              Container(width: 1, height: 50, color: Colors.grey.shade800),
              Expanded(
                child: _ConditionIndicator(
                  label: '훈련량',
                  value: analysis.trainingVolume,
                  isPositive: analysis.isTrainingActive,
                  icon: analysis.isTrainingActive
                      ? Icons.fitness_center_rounded
                      : Icons.hotel_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: conditionColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: conditionColor.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lightbulb_outline_rounded,
                        size: 16, color: conditionColor),
                    const SizedBox(width: 6),
                    Text(
                      '분석',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: conditionColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  analysis.comment,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade300,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (analysis.details.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: analysis.details.map((detail) {
                final isPositive = detail.startsWith('+') || detail.contains('상승') || detail.contains('활발');
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isPositive
                        ? AppTheme.positiveGreen.withValues(alpha: 0.1)
                        : Colors.redAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPositive ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                        size: 14,
                        color: isPositive ? AppTheme.positiveGreen : Colors.redAccent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        detail,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isPositive ? AppTheme.positiveGreen : Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  _ConditionAnalysis _analyzeCondition() {
    final details = <String>[];
    
    bool isRecordImproving = false;
    String recordTrend = '데이터 부족';
    bool isTrainingActive = false;
    String trainingVolume = '데이터 부족';
    String overall = '보통';
    String comment = '';

    final withTime = results.where((r) => 
        r.raceTime.isNotEmpty && 
        r.raceTime != '0' && 
        r.raceTime.contains(':') &&
        r.distance > 0
    ).take(5).toList();

    if (withTime.length >= 2) {
      final distanceGroups = <int, List<RaceResult>>{};
      for (final r in withTime) {
        distanceGroups.putIfAbsent(r.distance, () => []).add(r);
      }

      double totalChange = 0;
      int comparisonCount = 0;

      for (final group in distanceGroups.values) {
        if (group.length >= 2) {
          final recent = _parseTime(group[0].raceTime);
          final previous = _parseTime(group[1].raceTime);
          if (recent != null && previous != null) {
            totalChange += previous - recent;
            comparisonCount++;
          }
        }
      }

      if (comparisonCount > 0) {
        final avgChange = totalChange / comparisonCount;
        if (avgChange > 0.5) {
          isRecordImproving = true;
          recordTrend = '상승';
          details.add('기록 ${avgChange.toStringAsFixed(1)}초 단축');
        } else if (avgChange < -0.5) {
          isRecordImproving = false;
          recordTrend = '하락';
          details.add('기록 ${(-avgChange).toStringAsFixed(1)}초 증가');
        } else {
          recordTrend = '유지';
        }
      }
    }

    final now = DateTime.now();
    final recentRaces = results.where((r) {
      if (r.raceDate.length < 8) return false;
      try {
        final y = int.parse(r.raceDate.substring(0, 4));
        final m = int.parse(r.raceDate.substring(4, 6));
        final d = int.parse(r.raceDate.substring(6, 8));
        final raceDate = DateTime(y, m, d);
        return now.difference(raceDate).inDays <= 60;
      } catch (_) {
        return false;
      }
    }).length;

    if (recentRaces >= 3) {
      isTrainingActive = true;
      trainingVolume = '활발';
      details.add('최근 2개월 ${recentRaces}회 출주');
    } else if (recentRaces >= 1) {
      isTrainingActive = true;
      trainingVolume = '보통';
    } else {
      isTrainingActive = false;
      trainingVolume = '부족';
      details.add('최근 2개월 출주 없음');
    }

    final recentRanks = results.take(3).where((r) => r.rank > 0).map((r) => r.rank).toList();
    if (recentRanks.isNotEmpty) {
      final avgRank = recentRanks.reduce((a, b) => a + b) / recentRanks.length;
      if (avgRank <= 3) {
        details.add('최근 평균 ${avgRank.toStringAsFixed(1)}착');
      }
    }

    int positiveCount = 0;
    int negativeCount = 0;

    if (isRecordImproving) positiveCount++;
    if (recordTrend == '하락') negativeCount++;
    if (isTrainingActive && trainingVolume == '활발') positiveCount++;
    if (!isTrainingActive || trainingVolume == '부족') negativeCount++;

    if (positiveCount >= 2 && negativeCount == 0) {
      overall = '좋음';
      comment = '기록이 상승세이며 훈련량도 충분합니다. 좋은 컨디션으로 기대할 수 있습니다.';
    } else if (negativeCount >= 2) {
      overall = '주의';
      comment = '기록이 하락하거나 훈련량이 부족합니다. 컨디션 회복이 필요해 보입니다.';
    } else if (positiveCount > negativeCount) {
      overall = '좋음';
      comment = '전반적으로 양호한 컨디션입니다.';
    } else if (negativeCount > positiveCount) {
      overall = '주의';
      comment = '컨디션에 다소 우려가 있습니다.';
    } else {
      overall = '보통';
      comment = '평균적인 컨디션 상태입니다. 당일 상태를 확인하세요.';
    }

    if (results.isEmpty) {
      overall = '보통';
      comment = '경주 기록이 없어 컨디션을 판단하기 어렵습니다.';
    }

    return _ConditionAnalysis(
      overall: overall,
      recordTrend: recordTrend,
      isRecordImproving: isRecordImproving,
      trainingVolume: trainingVolume,
      isTrainingActive: isTrainingActive,
      comment: comment,
      details: details,
    );
  }

  double? _parseTime(String timeStr) {
    try {
      final parts = timeStr.split(':');
      if (parts.length == 2) {
        final minutes = int.parse(parts[0]);
        final seconds = double.parse(parts[1]);
        return minutes * 60 + seconds;
      }
    } catch (_) {}
    return null;
  }
}

class _ConditionAnalysis {
  final String overall;
  final String recordTrend;
  final bool isRecordImproving;
  final String trainingVolume;
  final bool isTrainingActive;
  final String comment;
  final List<String> details;

  _ConditionAnalysis({
    required this.overall,
    required this.recordTrend,
    required this.isRecordImproving,
    required this.trainingVolume,
    required this.isTrainingActive,
    required this.comment,
    required this.details,
  });
}

class _ConditionIndicator extends StatelessWidget {
  final String label;
  final String value;
  final bool isPositive;
  final IconData icon;

  const _ConditionIndicator({
    required this.label,
    required this.value,
    required this.isPositive,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final color = value == '데이터 부족'
        ? Colors.grey
        : isPositive
            ? AppTheme.positiveGreen
            : value == '유지' || value == '보통'
                ? Colors.orangeAccent
                : Colors.redAccent;

    return Column(
      children: [
        Icon(icon, size: 24, color: color),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
      ],
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━ Recent 5 Races ━━━━━━━━━━━━━━━━━━━━━━━

class _Recent5Races extends StatelessWidget {
  final List<RaceResult> results;
  const _Recent5Races({required this.results});

  @override
  Widget build(BuildContext context) {
    final recent = results.take(5).toList();
    if (recent.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('경주 기록이 없습니다'),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                const SizedBox(width: 44),
                Expanded(
                  child: Text('날짜', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                ),
                Expanded(
                  child: Text('거리', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                ),
                Expanded(
                  child: Text('순위', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                ),
                Expanded(
                  child: Text('기록', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                ),
                Expanded(
                  child: Text('배당', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.grey),
          ...recent.asMap().entries.map((e) {
            final idx = e.key;
            final r = e.value;
            final isTop3 = r.rank >= 1 && r.rank <= 3;
            final rankColor = r.rank == 1
                ? AppTheme.winColor
                : r.rank == 2
                    ? AppTheme.placeColor
                    : r.rank == 3
                        ? AppTheme.showColor
                        : Colors.grey.shade400;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isTop3 ? rankColor.withValues(alpha: 0.05) : null,
                border: idx < recent.length - 1
                    ? Border(bottom: BorderSide(color: Colors.grey.shade800, width: 0.5))
                    : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: rankColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        r.rank > 0 ? '${r.rank}' : '-',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: rankColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      r.raceDate.length >= 8
                          ? '${r.raceDate.substring(4, 6)}/${r.raceDate.substring(6, 8)}'
                          : r.raceDate,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      r.distance > 0 ? '${r.distance}m' : '-',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade300),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      r.rank > 0 ? '${r.rank}착' : r.rankRaw.isNotEmpty ? r.rankRaw : '-',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: rankColor,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      r.raceTime.isNotEmpty && r.raceTime != '0' ? r.raceTime : '-',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      r.winOdds > 0 ? '${r.winOdds.toStringAsFixed(1)}' : '-',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: r.winOdds > 0 ? AppTheme.accentGold : Colors.grey.shade500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━ Weight Analysis ━━━━━━━━━━━━━━━━━━━━━━━

class _WeightAnalysis extends StatelessWidget {
  final List<RaceResult> results;
  final double? currentWeight;
  const _WeightAnalysis({required this.results, this.currentWeight});

  @override
  Widget build(BuildContext context) {
    final withWeight = results.where((r) => r.weight > 0).toList();
    if (withWeight.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('부담중량 데이터가 없습니다'),
      );
    }

    final weightMap = <String, _WeightStat>{};
    for (final r in withWeight) {
      final range = _getWeightRange(r.weight);
      final stat = weightMap.putIfAbsent(range, () => _WeightStat(range, r.weight));
      stat.total++;
      if (r.rank == 1) stat.wins++;
      if (r.rank >= 1 && r.rank <= 3) stat.places++;
      if (r.rank > 0) {
        stat.totalRank += r.rank;
        stat.rankedCount++;
      }
    }

    final sorted = weightMap.values.toList()
      ..sort((a, b) => a.avgWeight.compareTo(b.avgWeight));

    final currentRange = currentWeight != null ? _getWeightRange(currentWeight!) : null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          if (currentWeight != null) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '현재 부담중량: ',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                ),
                Text(
                  '${currentWeight!.toStringAsFixed(1)}kg',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primaryGreen,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
          ],
          ...sorted.map((stat) {
            final winRate = stat.total > 0 ? stat.wins / stat.total * 100 : 0.0;
            final placeRate = stat.total > 0 ? stat.places / stat.total * 100 : 0.0;
            final avgRank = stat.rankedCount > 0 ? stat.totalRank / stat.rankedCount : 0.0;
            final isCurrent = stat.range == currentRange;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isCurrent
                    ? AppTheme.primaryGreen.withValues(alpha: 0.1)
                    : Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
                border: isCurrent
                    ? Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.3))
                    : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 70,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? AppTheme.primaryGreen.withValues(alpha: 0.2)
                          : Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      stat.range,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isCurrent ? AppTheme.primaryGreen : Colors.grey.shade300,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _MiniStat('출주', '${stat.total}회', Colors.grey.shade300),
                        _MiniStat(
                          '승률',
                          '${winRate.toStringAsFixed(0)}%',
                          winRate > 0 ? AppTheme.positiveGreen : Colors.grey.shade500,
                        ),
                        _MiniStat(
                          'TOP3',
                          '${placeRate.toStringAsFixed(0)}%',
                          placeRate > 0 ? Colors.cyanAccent : Colors.grey.shade500,
                        ),
                        _MiniStat(
                          '평균',
                          avgRank > 0 ? '${avgRank.toStringAsFixed(1)}착' : '-',
                          avgRank > 0 && avgRank <= 3 ? AppTheme.accentGold : Colors.grey.shade400,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  String _getWeightRange(double weight) {
    if (weight < 52) return '~51kg';
    if (weight < 54) return '52-53kg';
    if (weight < 56) return '54-55kg';
    if (weight < 58) return '56-57kg';
    return '58kg~';
  }
}

class _WeightStat {
  final String range;
  final double avgWeight;
  int total = 0;
  int wins = 0;
  int places = 0;
  int totalRank = 0;
  int rankedCount = 0;
  _WeightStat(this.range, this.avgWeight);
}

// ━━━━━━━━━━━━━━━━━━━━━━━ Distance Aptitude ━━━━━━━━━━━━━━━━━━━━━━━

class _DistanceAptitude extends StatelessWidget {
  final List<RaceResult> results;
  const _DistanceAptitude({required this.results});

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

    final bestDistance = sorted.reduce((a, b) {
      final aRate = a.total > 0 ? a.wins / a.total : 0;
      final bRate = b.total > 0 ? b.wins / b.total : 0;
      if (aRate != bRate) return aRate > bRate ? a : b;
      return a.places > b.places ? a : b;
    });

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.star_rounded, size: 18, color: AppTheme.winColor),
              const SizedBox(width: 6),
              Text(
                '최적 거리: ',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
              ),
              Text(
                '${bestDistance.distance}m',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.winColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          ...sorted.map((stat) {
            final winRate = stat.total > 0 ? (stat.wins / stat.total * 100) : 0.0;
            final placeRate = stat.total > 0 ? (stat.places / stat.total * 100) : 0.0;
            final isBest = stat.distance == bestDistance.distance;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 70,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: isBest
                          ? AppTheme.winColor.withValues(alpha: 0.15)
                          : AppTheme.primaryGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: isBest
                          ? Border.all(color: AppTheme.winColor.withValues(alpha: 0.3))
                          : null,
                    ),
                    child: Text(
                      '${stat.distance}m',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: isBest ? AppTheme.winColor : AppTheme.primaryGreen,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${stat.total}전 ${stat.wins}승 ${stat.places - stat.wins}복',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isBest ? Colors.white : Colors.grey.shade400,
                              ),
                            ),
                            const Spacer(),
                            if (isBest)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.winColor.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '최적',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.winColor,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: Row(
                            children: [
                              Expanded(
                                flex: (winRate * 10).toInt().clamp(1, 1000),
                                child: Container(height: 6, color: AppTheme.winColor),
                              ),
                              Expanded(
                                flex: ((placeRate - winRate) * 10).toInt().clamp(0, 1000),
                                child: Container(height: 6, color: AppTheme.placeColor),
                              ),
                              Expanded(
                                flex: ((100 - placeRate) * 10).toInt().clamp(1, 1000),
                                child: Container(height: 6, color: Colors.grey.shade700),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${winRate.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: winRate > 0
                          ? (isBest ? AppTheme.winColor : AppTheme.positiveGreen)
                          : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━ Horse Weight Trend ━━━━━━━━━━━━━━━━━━━━━━━

class _HorseWeightTrend extends StatelessWidget {
  final List<RaceResult> results;
  final double? currentWeight;
  const _HorseWeightTrend({required this.results, this.currentWeight});

  @override
  Widget build(BuildContext context) {
    final withWeight = results.where((r) => r.horseWeight > 0).take(10).toList().reversed.toList();
    if (withWeight.length < 2) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('마체중 데이터가 부족합니다'),
      );
    }

    final weights = withWeight.map((r) => r.horseWeight).toList();
    final minWeight = weights.reduce((a, b) => a < b ? a : b) - 5;
    final maxWeight = weights.reduce((a, b) => a > b ? a : b) + 5;
    final avgWeight = weights.reduce((a, b) => a + b) / weights.length;

    final recentChange = withWeight.length >= 2
        ? withWeight.last.horseWeight - withWeight[withWeight.length - 2].horseWeight
        : 0.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _WeightStatItem(
                label: '현재',
                value: currentWeight != null
                    ? '${currentWeight!.toStringAsFixed(0)}kg'
                    : '${withWeight.last.horseWeight.toStringAsFixed(0)}kg',
                color: AppTheme.primaryGreen,
              ),
              Container(width: 1, height: 30, color: Colors.grey.shade700),
              _WeightStatItem(
                label: '평균',
                value: '${avgWeight.toStringAsFixed(0)}kg',
                color: Colors.cyanAccent,
              ),
              Container(width: 1, height: 30, color: Colors.grey.shade700),
              _WeightStatItem(
                label: '변화',
                value: recentChange >= 0
                    ? '+${recentChange.toStringAsFixed(0)}kg'
                    : '${recentChange.toStringAsFixed(0)}kg',
                color: recentChange > 0
                    ? Colors.redAccent
                    : recentChange < 0
                        ? Colors.blueAccent
                        : Colors.grey,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                minY: minWeight,
                maxY: maxWeight,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 5,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.shade800,
                    strokeWidth: 0.5,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= withWeight.length) return const SizedBox.shrink();
                        final date = withWeight[idx].raceDate;
                        final label = date.length >= 8
                            ? '${date.substring(4, 6)}/${date.substring(6, 8)}'
                            : '$idx';
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(label,
                              style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: 5,
                      getTitlesWidget: (value, meta) => Text(
                        '${value.toInt()}',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                      ),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: withWeight.asMap().entries.map((e) {
                      return FlSpot(e.key.toDouble(), e.value.horseWeight);
                    }).toList(),
                    isCurved: true,
                    color: Colors.orangeAccent,
                    barWidth: 3,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, pct, bar, idx) {
                        final isLast = idx == withWeight.length - 1;
                        return FlDotCirclePainter(
                          radius: isLast ? 6 : 4,
                          color: isLast ? AppTheme.primaryGreen : Colors.orangeAccent,
                          strokeColor: Colors.white,
                          strokeWidth: isLast ? 2 : 0,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.orangeAccent.withValues(alpha: 0.1),
                    ),
                  ),
                  LineChartBarData(
                    spots: withWeight.asMap().entries.map((e) {
                      return FlSpot(e.key.toDouble(), avgWeight);
                    }).toList(),
                    isCurved: false,
                    color: Colors.cyanAccent.withValues(alpha: 0.5),
                    barWidth: 1,
                    dotData: const FlDotData(show: false),
                    dashArray: [5, 5],
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) {
                      final spot = spots.first;
                      final idx = spot.x.toInt();
                      if (idx < 0 || idx >= withWeight.length) return [];
                      final r = withWeight[idx];
                      final date = r.raceDate.length >= 8
                          ? '${r.raceDate.substring(4, 6)}/${r.raceDate.substring(6, 8)}'
                          : '';
                      return [
                        LineTooltipItem(
                          '$date\n${r.horseWeight.toStringAsFixed(0)}kg',
                          const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ];
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 10,
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.orangeAccent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 4),
              Text('마체중', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              const SizedBox(width: 16),
              Container(
                width: 10,
                height: 2,
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 4),
              Text('평균', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeightStatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _WeightStatItem({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        const SizedBox(height: 2),
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

// ━━━━━━━━━━━━━━━━━━━━━━━ Rating Gauge ━━━━━━━━━━━━━━━━━━━━━━━

class _RatingGauge extends StatelessWidget {
  final RaceEntry entry;
  final List<RaceResult> results;
  const _RatingGauge({required this.entry, required this.results});

  @override
  Widget build(BuildContext context) {
    final rating = entry.rating;
    final maxRating = 120.0;
    final progress = (rating / maxRating).clamp(0.0, 1.0);

    Color ratingColor;
    String ratingLevel;
    if (rating >= 100) {
      ratingColor = AppTheme.winColor;
      ratingLevel = '최상위';
    } else if (rating >= 80) {
      ratingColor = AppTheme.placeColor;
      ratingLevel = '상위';
    } else if (rating >= 60) {
      ratingColor = Colors.cyanAccent;
      ratingLevel = '중상위';
    } else if (rating >= 40) {
      ratingColor = Colors.orangeAccent;
      ratingLevel = '중위';
    } else {
      ratingColor = Colors.grey;
      ratingLevel = '하위';
    }

    final avgRank = results.isNotEmpty
        ? results.where((r) => r.rank > 0).fold(0.0, (sum, r) => sum + r.rank) /
            results.where((r) => r.rank > 0).length
        : 0.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          rating.toStringAsFixed(0),
                          style: TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w900,
                            color: ratingColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: ratingColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            ratingLevel,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: ratingColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 10,
                        backgroundColor: Colors.grey.shade800,
                        valueColor: AlwaysStoppedAnimation<Color>(ratingColor),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('0', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                        Text('40', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                        Text('60', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                        Text('80', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                        Text('100', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                        Text('120', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(
                width: 80,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      '평균 순위',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      avgRank > 0 ? '${avgRank.toStringAsFixed(1)}착' : '-',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: avgRank > 0 && avgRank <= 3
                            ? AppTheme.positiveGreen
                            : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━ Recent Performance Chart ━━━━━━━━━━━━━━━━━━━━━━━

class _RecentPerformanceChart extends StatelessWidget {
  final List<RaceResult> results;
  const _RecentPerformanceChart({required this.results});

  @override
  Widget build(BuildContext context) {
    final recent = results.where((r) => r.rank > 0).take(10).toList().reversed.toList();
    if (recent.length < 2) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('데이터가 부족합니다'),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 200,
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
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= recent.length) return const SizedBox.shrink();
                        final date = recent[idx].raceDate;
                        final label = date.length >= 8
                            ? '${date.substring(4, 6)}/${date.substring(6, 8)}'
                            : '$idx';
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(label,
                              style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
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
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: recent.asMap().entries.map((e) {
                      return FlSpot(e.key.toDouble(), e.value.rank.toDouble());
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
                          r = 7;
                        } else if (spot.y <= 3) {
                          c = AppTheme.placeColor;
                          r = 5;
                        } else {
                          c = AppTheme.accentGold;
                          r = 4;
                        }
                        return FlDotCirclePainter(
                          radius: r,
                          color: c,
                          strokeColor: Colors.white,
                          strokeWidth: 1,
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
                    getTooltipItems: (spots) => spots.map((spot) {
                      final idx = spot.x.toInt();
                      final r = idx < recent.length ? recent[idx] : null;
                      final date = r != null && r.raceDate.length >= 8
                          ? '${r.raceDate.substring(4, 6)}/${r.raceDate.substring(6, 8)}'
                          : '';
                      final odds = r != null && r.winOdds > 0 ? ' (${r.winOdds.toStringAsFixed(1)}배)' : '';
                      return LineTooltipItem(
                        '$date ${spot.y.toInt()}착$odds',
                        const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _LegendItem(color: AppTheme.winColor, label: '1착'),
              const SizedBox(width: 16),
              _LegendItem(color: AppTheme.placeColor, label: '2-3착'),
              const SizedBox(width: 16),
              _LegendItem(color: AppTheme.accentGold, label: '4착+'),
            ],
          ),
          const SizedBox(height: 12),
          _PerformanceSummary(results: recent),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
      ],
    );
  }
}

class _PerformanceSummary extends StatelessWidget {
  final List<RaceResult> results;
  const _PerformanceSummary({required this.results});

  @override
  Widget build(BuildContext context) {
    final wins = results.where((r) => r.rank == 1).length;
    final places = results.where((r) => r.rank >= 1 && r.rank <= 3).length;
    final total = results.length;
    final winRate = total > 0 ? wins / total * 100 : 0.0;
    final placeRate = total > 0 ? places / total * 100 : 0.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _SummaryItem(label: '최근 $total전', value: '$wins승 ${places - wins}복'),
          Container(width: 1, height: 30, color: Colors.grey.shade700),
          _SummaryItem(
            label: '승률',
            value: '${winRate.toStringAsFixed(1)}%',
            color: winRate > 0 ? AppTheme.winColor : null,
          ),
          Container(width: 1, height: 30, color: Colors.grey.shade700),
          _SummaryItem(
            label: 'TOP3',
            value: '${placeRate.toStringAsFixed(1)}%',
            color: placeRate >= 30 ? AppTheme.positiveGreen : null,
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _SummaryItem({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color ?? Colors.white,
          ),
        ),
      ],
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━ Jockey Win Rate ━━━━━━━━━━━━━━━━━━━━━━━

class _JockeyWinRate extends StatelessWidget {
  final List<RaceResult> results;
  final String? currentJockey;
  const _JockeyWinRate({required this.results, this.currentJockey});

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
      ..sort((a, b) {
        if (a.name == currentJockey) return -1;
        if (b.name == currentJockey) return 1;
        return b.total.compareTo(a.total);
      });

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
          final placeRate = stat.total > 0 ? stat.places / stat.total * 100 : 0.0;
          final isCurrent = stat.name == currentJockey;

          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isCurrent
                  ? AppTheme.primaryGreen.withValues(alpha: 0.1)
                  : AppTheme.cardDark,
              borderRadius: BorderRadius.circular(12),
              border: isCurrent
                  ? Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.3))
                  : null,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      isCurrent ? Icons.star_rounded : Icons.person,
                      size: 20,
                      color: isCurrent ? AppTheme.primaryGreen : Colors.grey,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  stat.name,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: isCurrent ? AppTheme.primaryGreen : null,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isCurrent) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryGreen.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    '현재 기수',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.primaryGreen,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${stat.total}전 ${stat.wins}승 ${stat.places - stat.wins}복',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${winRate.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: winRate >= 30
                                ? AppTheme.winColor
                                : winRate > 0
                                    ? AppTheme.positiveGreen
                                    : Colors.grey.shade400,
                          ),
                        ),
                        Text(
                          '승률',
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Row(
                    children: [
                      Expanded(
                        flex: (winRate * 10).toInt().clamp(1, 1000),
                        child: Container(
                          height: 6,
                          color: AppTheme.winColor,
                        ),
                      ),
                      Expanded(
                        flex: ((placeRate - winRate) * 10).toInt().clamp(0, 1000),
                        child: Container(
                          height: 6,
                          color: AppTheme.placeColor,
                        ),
                      ),
                      Expanded(
                        flex: ((100 - placeRate) * 10).toInt().clamp(1, 1000),
                        child: Container(
                          height: 6,
                          color: Colors.grey.shade700,
                        ),
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
