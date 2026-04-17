import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/services/kra_video_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../../models/race.dart';
import '../../../models/race_entry.dart';
import '../../../models/odds.dart';
import '../../../models/prediction.dart';
import '../providers/race_providers.dart';
import '../widgets/race_auto_refresh_hook.dart';
import '../widgets/race_video_panel.dart';

class RaceEntryScreen extends ConsumerWidget {
  final String meet;
  final String date;
  final int raceNo;

  const RaceEntryScreen({
    super.key,
    required this.meet,
    required this.date,
    required this.raceNo,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raceAsync = ref.watch(racePlanProvider((meet: meet, date: date)));
    final entriesAsync = ref.watch(
      raceStartListProvider((meet: meet, date: date, raceNo: raceNo)),
    );
    final oddsAsync = ref.watch(
      oddsProvider((meet: meet, date: date, raceNo: raceNo)),
    );
    final predAsync = ref.watch(
      predictionProvider((meet: meet, date: date, raceNo: raceNo)),
    );
    final videoAsync = ref.watch(
      raceVideoLinksProvider((meet: meet, date: date, raceNo: raceNo)),
    );

    final meetName = ApiConstants.meetNames[meet] ?? meet;
    final race = raceAsync.valueOrNull
        ?.where((r) => r.raceNo == raceNo)
        .firstOrNull;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              title: Text('$meetName ${raceNo}R 출마표'),
              actions: [
                if (_isRaceFinished(race))
                  IconButton(
                    icon: const Icon(Icons.emoji_events_rounded),
                    tooltip: '경주결과',
                    onPressed: () =>
                        context.push('/result/$meet/$date/$raceNo'),
                  ),
              ],
            ),

            SliverToBoxAdapter(
              child: RaceAutoRefreshHook(
                meet: meet,
                date: date,
                raceNo: raceNo,
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: videoAsync.when(
                  loading: () => const ShimmerLoading(height: 78),
                  error: (_, __) => RaceVideoPanel(
                    links: RaceVideoLinks(
                      liveUrl: _buildRaceVideoUrl(),
                      paradeUrl: ApiConstants.todayRaceParadeVideoUrl,
                      hasVideoSection: false,
                      isRaceVideoFromApi: false,
                    ),
                    showParadeButton: false,
                  ),
                  data: (links) => RaceVideoPanel(
                    links: RaceVideoLinks(
                      liveUrl: _buildRaceVideoUrl(),
                      paradeUrl: links.paradeUrl,
                      hasVideoSection: links.hasVideoSection,
                      isRaceVideoFromApi: links.isRaceVideoFromApi,
                    ),
                    showParadeButton: false,
                  ),
                ),
              ),
            ),

            // AI 예측 그래프
            SliverToBoxAdapter(
              child: predAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: ShimmerLoading(height: 200),
                ),
                error: (_, __) => const SizedBox.shrink(),
                data: (report) {
                  if (report == null || report.predictions.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  final entries = entriesAsync.valueOrNull ?? [];
                  return _AiPredictionChart(report: report, entries: entries);
                },
              ),
            ),

            // 종합 추천
            SliverToBoxAdapter(
              child: entriesAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (entries) {
                  if (entries.isEmpty) return const SizedBox.shrink();
                  final predictions = predAsync.valueOrNull?.predictions ?? [];
                  final odds = oddsAsync.valueOrNull ?? [];
                  return _ComprehensiveRecommendation(
                    entries: entries,
                    predictions: predictions,
                    odds: odds,
                    distance: race?.distance ?? 1400,
                  );
                },
              ),
            ),

            // 예상 전개
            SliverToBoxAdapter(
              child: entriesAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (entries) {
                  if (entries.isEmpty) return const SizedBox.shrink();
                  final predictions = predAsync.valueOrNull?.predictions ?? [];
                  return _RacePacePreview(
                    entries: entries,
                    predictions: predictions,
                    distance: race?.distance ?? 1400,
                  );
                },
              ),
            ),

            // 출마표 / 결과 헤더
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                child: Row(
                  children: [
                    const Text(
                      '출마표',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    if (_isRaceFinished(race))
                      GestureDetector(
                        onTap: () =>
                            context.push('/result/$meet/$date/$raceNo'),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.emoji_events_rounded,
                              size: 15,
                              color: AppTheme.winColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '결과',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.winColor,
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: AppTheme.winColor,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // 출마표 목록
            entriesAsync.when(
              loading: () => SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: ShimmerLoading(height: 160),
                  ),
                  childCount: 6,
                ),
              ),
              error: (err, _) => SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '출마표를 불러올 수 없습니다',
                        style: TextStyle(color: Colors.grey.shade400),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => ref.invalidate(
                          raceStartListProvider((
                            meet: meet,
                            date: date,
                            raceNo: raceNo,
                          )),
                        ),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('다시 시도'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (entries) {
                if (entries.isEmpty) {
                  return const SliverFillRemaining(
                    child: Center(child: Text('출마 정보가 없습니다')),
                  );
                }

                final odds = oddsAsync.valueOrNull ?? [];
                final predictions = predAsync.valueOrNull?.predictions ?? [];
                final sorted = List<RaceEntry>.from(entries)
                  ..sort((a, b) => a.horseNo.compareTo(b.horseNo));
                final distance = race?.distance ?? 0;

                return SliverList(
                  delegate: SliverChildBuilderDelegate((ctx, i) {
                    final entry = sorted[i];
                    final winOdds = _findWinOdds(odds, entry.horseNo);
                    final pred = _findPrediction(predictions, entry.horseNo);
                    final predRank = _predictionRank(
                      predictions,
                      entry.horseNo,
                    );

                    return _HorseCard(
                      entry: entry,
                      winOdds: winOdds,
                      prediction: pred,
                      predictionRank: predRank,
                      distance: distance,
                      onTap: () => context.push(
                        '/horse/${Uri.encodeComponent(entry.horseName)}'
                        '?meet=$meet',
                        extra: entry,
                      ),
                    );
                  }, childCount: sorted.length),
                );
              },
            ),

            if (_isRaceFinished(race))
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 32),
                  child: FilledButton.icon(
                    onPressed: () =>
                        context.push('/result/$meet/$date/$raceNo'),
                    icon: const Icon(Icons.emoji_events_rounded),
                    label: const Text(
                      '경주결과 보기',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.winColor,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),

            const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
          ],
        ),
      ),
    );
  }

  bool _isRaceFinished(Race? race) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (date.length >= 8) {
      final y = int.tryParse(date.substring(0, 4));
      final mo = int.tryParse(date.substring(4, 6));
      final d = int.tryParse(date.substring(6, 8));
      if (y != null && mo != null && d != null) {
        final raceDay = DateTime(y, mo, d);
        if (raceDay.isBefore(today)) return true;
      }
    }

    if (race == null || race.startTime.isEmpty) return false;
    try {
      final t = race.startTime.replaceAll(':', '').trim();
      final h = int.parse(t.substring(0, t.length - 2));
      final m = int.parse(t.substring(t.length - 2));
      final raceTime = DateTime(now.year, now.month, now.day, h, m);
      return now.difference(raceTime).inMinutes >= 30;
    } catch (_) {
      return false;
    }
  }

  static double _findWinOdds(List<Odds> odds, int horseNo) {
    for (final o in odds) {
      if ((o.betType == 'WIN' || o.betType == '1') && o.horseNo1 == horseNo) {
        return o.rate;
      }
    }
    return 0;
  }

  static Prediction? _findPrediction(List<Prediction> preds, int horseNo) {
    for (final p in preds) {
      if (p.horseNo == horseNo) return p;
    }
    return null;
  }

  static int _predictionRank(List<Prediction> preds, int horseNo) {
    if (preds.isEmpty) return 0;
    final sorted = [...preds]
      ..sort((a, b) => b.winProbability.compareTo(a.winProbability));
    for (int i = 0; i < sorted.length; i++) {
      if (sorted[i].horseNo == horseNo) return i + 1;
    }
    return 0;
  }

  String _buildRaceVideoUrl() {
    return Uri.https('kraplayer.starplayer.net', '/kra/vod/starplayer.php', {
      'meet': meet,
      'rcdate': date,
      'rcno': raceNo.toString(),
      'vod_type': 'r',
    }).toString();
  }
}

// ═══════════════════════════════════════════════════
// 예상 전개
// ═══════════════════════════════════════════════════

class _RacePacePreview extends StatelessWidget {
  final List<RaceEntry> entries;
  final List<Prediction> predictions;
  final int distance;

  const _RacePacePreview({
    required this.entries,
    required this.predictions,
    required this.distance,
  });

  String _getRunningStyle(RaceEntry entry, Prediction? pred) {
    final rating = entry.rating;
    final winRate = entry.winRate;
    final totalRaces = entry.totalRaces;

    if (pred != null && pred.winProbability > 15) {
      if (rating >= 80) return '선행';
      if (rating >= 60) return '선입';
      return '추입';
    }

    if (totalRaces < 3) return '미지수';
    if (rating >= 85 && winRate >= 20) return '선행';
    if (rating >= 70) return '선입';
    if (rating >= 50) return '중단';
    return '후입';
  }

  Color _styleColor(String style) {
    switch (style) {
      case '선행':
        return AppTheme.winColor;
      case '선입':
        return AppTheme.placeColor;
      case '중단':
        return Colors.cyanAccent;
      case '추입':
        return Colors.orangeAccent;
      case '후입':
        return Colors.purpleAccent;
      default:
        return Colors.grey;
    }
  }

  int _estimatePosition(String style, int phase, int totalHorses) {
    final basePositions = {
      '선행': [1, 1, 2, 2],
      '선입': [2, 2, 2, 3],
      '중단': [4, 4, 3, 4],
      '추입': [5, 5, 4, 3],
      '후입': [6, 6, 5, 4],
      '미지수': [4, 4, 4, 5],
    };
    final base = basePositions[style] ?? [4, 4, 4, 4];
    final pos = base[phase.clamp(0, 3)];
    return (pos * totalHorses / 7).round().clamp(1, totalHorses);
  }

  @override
  Widget build(BuildContext context) {
    final sorted = List<RaceEntry>.from(entries)
      ..sort((a, b) => a.horseNo.compareTo(b.horseNo));

    final horsePaces = <int, _HorsePaceData>{};
    for (final entry in sorted) {
      final pred = predictions
          .where((p) => p.horseNo == entry.horseNo)
          .firstOrNull;
      final style = _getRunningStyle(entry, pred);
      horsePaces[entry.horseNo] = _HorsePaceData(
        horseNo: entry.horseNo,
        horseName: entry.horseName,
        style: style,
        color: _styleColor(style),
        positions: List.generate(
          4,
          (i) => _estimatePosition(style, i, sorted.length),
        ),
      );
    }

    final phases = ['스타트', '1코너', '3코너', '결승'];

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.show_chart_rounded,
                size: 18,
                color: Colors.cyanAccent,
              ),
              const SizedBox(width: 6),
              const Text(
                '예상 전개',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.grey.shade800,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${distance}m',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: phases.asMap().entries.map((e) {
              final isLast = e.key == phases.length - 1;
              return Expanded(
                child: Column(
                  children: [
                    Text(
                      e.value,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isLast
                            ? AppTheme.winColor
                            : Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 2,
                      color: isLast
                          ? AppTheme.winColor.withValues(alpha: 0.5)
                          : Colors.grey.shade700,
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          ...['선행', '선입', '중단', '추입', '후입'].map((style) {
            final horses = horsePaces.values
                .where((h) => h.style == style)
                .toList();
            if (horses.isEmpty) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _styleColor(style).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      style,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _styleColor(style),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: horses.map((h) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: h.color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: h.color.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            '${h.horseNo}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: h.color,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 12),

          Builder(
            builder: (_) {
              final frontRunners = horsePaces.values
                  .where((h) => h.style == '선행' || h.style == '선입')
                  .length;
              final closers = horsePaces.values
                  .where((h) => h.style == '추입' || h.style == '후입')
                  .length;
              final total = horsePaces.length;

              final isFrontHeavy =
                  frontRunners >= 4 || (frontRunners >= 3 && total <= 10);
              final isCloserHeavy =
                  closers >= 4 || (closers >= 3 && frontRunners <= 1);

              String advantage;
              String reason;
              Color advColor;
              IconData advIcon;
              List<int> advantageHorses;

              if (isFrontHeavy) {
                advantage = '추입마 유리';
                reason = '선행마가 많아 앞쪽 경합이 치열할 것으로 예상됩니다. 후반 추입 전법이 유리합니다.';
                advColor = Colors.orangeAccent;
                advIcon = Icons.speed_rounded;
                advantageHorses = horsePaces.values
                    .where((h) => h.style == '추입' || h.style == '후입')
                    .map((h) => h.horseNo)
                    .toList();
              } else if (isCloserHeavy || frontRunners <= 1) {
                advantage = '선행마 유리';
                reason = '선행마가 적어 편한 페이스로 레이스를 이끌 수 있습니다. 선행/선입 전법이 유리합니다.';
                advColor = AppTheme.winColor;
                advIcon = Icons.flag_rounded;
                advantageHorses = horsePaces.values
                    .where((h) => h.style == '선행' || h.style == '선입')
                    .map((h) => h.horseNo)
                    .toList();
              } else {
                advantage = '균형 전개';
                reason = '선행과 추입이 균형을 이뤄 다양한 전법이 가능한 경주입니다.';
                advColor = Colors.cyanAccent;
                advIcon = Icons.balance_rounded;
                advantageHorses = [];
              }

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      advColor.withValues(alpha: 0.15),
                      advColor.withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: advColor.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: advColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(advIcon, size: 20, color: advColor),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '전개 분석',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                              Text(
                                advantage,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: advColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '선행 $frontRunners',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.winColor,
                                ),
                              ),
                              Text(
                                ' / ',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                              Text(
                                '추입 $closers',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orangeAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      reason,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade300,
                        height: 1.4,
                      ),
                    ),
                    if (advantageHorses.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            Icons.thumb_up_alt_rounded,
                            size: 14,
                            color: advColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '유리한 마번: ',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          Expanded(
                            child: Wrap(
                              spacing: 4,
                              children: advantageHorses.take(6).map((no) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: advColor.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '$no',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: advColor,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HorsePaceData {
  final int horseNo;
  final String horseName;
  final String style;
  final Color color;
  final List<int> positions;

  _HorsePaceData({
    required this.horseNo,
    required this.horseName,
    required this.style,
    required this.color,
    required this.positions,
  });
}

// ═══════════════════════════════════════════════════
// 종합 추천
// ═══════════════════════════════════════════════════

class _ComprehensiveRecommendation extends StatelessWidget {
  final List<RaceEntry> entries;
  final List<Prediction> predictions;
  final List<Odds> odds;
  final int distance;

  const _ComprehensiveRecommendation({
    required this.entries,
    required this.predictions,
    required this.odds,
    required this.distance,
  });

  @override
  Widget build(BuildContext context) {
    final recommendations = _analyzeAndRecommend();
    if (recommendations.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.amber.shade900.withValues(alpha: 0.3),
            AppTheme.cardDark,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.recommend_rounded,
                  size: 22,
                  color: Colors.amber,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '종합 추천',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '레이팅 · 성적 · 기수 · 거리 · 전개 분석',
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          ...recommendations.asMap().entries.map((e) {
            final idx = e.key;
            final rec = e.value;
            final rankColors = [
              Colors.amber,
              Colors.grey.shade300,
              Colors.orange.shade300,
            ];
            final rankColor = rankColors[idx.clamp(0, 2)];

            return Container(
              margin: EdgeInsets.only(
                bottom: idx < recommendations.length - 1 ? 10 : 0,
              ),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: rankColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: rankColor.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: rankColor,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${idx + 1}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: rankColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${rec.horseNo}번',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: rankColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          rec.horseName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getScoreColor(
                            rec.totalScore,
                          ).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${rec.totalScore.toStringAsFixed(0)}점',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: _getScoreColor(rec.totalScore),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      _ScoreBadge(
                        label: '레이팅',
                        score: rec.ratingScore,
                        maxScore: 25,
                      ),
                      const SizedBox(width: 6),
                      _ScoreBadge(
                        label: '성적',
                        score: rec.performanceScore,
                        maxScore: 25,
                      ),
                      const SizedBox(width: 6),
                      _ScoreBadge(
                        label: '기수',
                        score: rec.jockeyScore,
                        maxScore: 20,
                      ),
                      const SizedBox(width: 6),
                      _ScoreBadge(
                        label: '거리',
                        score: rec.distanceScore,
                        maxScore: 15,
                      ),
                      const SizedBox(width: 6),
                      _ScoreBadge(
                        label: '전개',
                        score: rec.paceScore,
                        maxScore: 15,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: rec.reasons.map((reason) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _getReasonIcon(reason),
                              size: 12,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              reason,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade300,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '레이팅, 최근 성적, 기수 승률, 거리 적성, 예상 전개를 종합 분석한 결과입니다',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<_HorseRecommendation> _analyzeAndRecommend() {
    final recs = <_HorseRecommendation>[];
    if (entries.isEmpty) return recs;

    // 1. 경주 내 상대적 위치 분석
    final ratings = entries.map((e) => e.rating).toList()
      ..sort((a, b) => b.compareTo(a));
    final maxRating = ratings.isNotEmpty ? ratings.first : 100.0;
    final avgRating = ratings.isNotEmpty
        ? ratings.reduce((a, b) => a + b) / ratings.length
        : 50.0;

    // 2. 전개 분석
    final runningStyles = <int, String>{};
    final frontRunners = <int>[];
    final closers = <int>[];

    for (final entry in entries) {
      final pred = predictions
          .where((p) => p.horseNo == entry.horseNo)
          .firstOrNull;
      final style = _getRunningStyle(entry, pred);
      runningStyles[entry.horseNo] = style;
      if (style == '선행' || style == '선입') {
        frontRunners.add(entry.horseNo);
      } else if (style == '추입' || style == '후입') {
        closers.add(entry.horseNo);
      }
    }

    final isFrontHeavy =
        frontRunners.length >= 4 ||
        (frontRunners.length >= 3 && entries.length <= 10);
    final isCloserFavored = closers.length >= 3 && frontRunners.length <= 2;

    // 3. 배당률 분석 (낮은 배당 = 인기마)
    final oddsMap = <int, double>{};
    for (final o in odds) {
      if ((o.betType == 'WIN' || o.betType == '1') && o.rate > 0) {
        oddsMap[o.horseNo1] = o.rate;
      }
    }
    final hasOdds = oddsMap.isNotEmpty;
    final avgOdds = hasOdds
        ? oddsMap.values.reduce((a, b) => a + b) / oddsMap.length
        : 10.0;

    for (final entry in entries) {
      final reasons = <String>[];
      final pred = predictions
          .where((p) => p.horseNo == entry.horseNo)
          .firstOrNull;
      final style = runningStyles[entry.horseNo] ?? '중단';
      final winOdds = oddsMap[entry.horseNo] ?? 0;

      // ═══════════════════════════════════════════════════
      // 1. 레이팅 점수 (25점) - 상대적 위치 기반
      // ═══════════════════════════════════════════════════
      double ratingScore = 0;
      final ratingRank = ratings.indexOf(entry.rating) + 1;
      final ratingPercentile = entry.rating / maxRating;

      if (ratingRank <= 2 && entry.rating >= 80) {
        ratingScore = 25;
        reasons.add('레이팅 ${ratingRank}위 (${entry.rating.toStringAsFixed(0)})');
      } else if (ratingRank <= 3 && entry.rating >= 70) {
        ratingScore = 22;
        reasons.add('레이팅 상위권');
      } else if (ratingPercentile >= 0.85) {
        ratingScore = 20;
      } else if (ratingPercentile >= 0.7) {
        ratingScore = 15;
      } else if (entry.rating >= avgRating) {
        ratingScore = 10;
      } else {
        ratingScore = 5;
      }

      // ═══════════════════════════════════════════════════
      // 2. 성적 점수 (25점) - 승률 + 입상률 + 경험
      // ═══════════════════════════════════════════════════
      double performanceScore = 0;
      final winRate = entry.winRate;
      final placeRate = entry.placeRate;
      final totalRaces = entry.totalRaces;

      // 승률 기반 (15점)
      if (winRate >= 30) {
        performanceScore += 15;
        reasons.add('고승률 ${winRate.toStringAsFixed(0)}%');
      } else if (winRate >= 20) {
        performanceScore += 12;
        reasons.add('승률 ${winRate.toStringAsFixed(0)}%');
      } else if (winRate >= 10) {
        performanceScore += 8;
      } else if (winRate > 0) {
        performanceScore += 4;
      }

      // 입상률 기반 (7점)
      if (placeRate >= 50) {
        performanceScore += 7;
        if (winRate < 15)
          reasons.add('안정적 입상 ${placeRate.toStringAsFixed(0)}%');
      } else if (placeRate >= 35) {
        performanceScore += 5;
      } else if (placeRate >= 20) {
        performanceScore += 3;
      }

      // 경험치 보너스 (3점)
      if (totalRaces >= 20 && entry.winCount >= 3) {
        performanceScore += 3;
        reasons.add('풍부한 경험 (${totalRaces}전 ${entry.winCount}승)');
      } else if (totalRaces >= 10) {
        performanceScore += 2;
      } else if (totalRaces >= 5) {
        performanceScore += 1;
      }

      // ═══════════════════════════════════════════════════
      // 3. AI 예측 + 배당 점수 (20점)
      // ═══════════════════════════════════════════════════
      double jockeyScore = 0;

      // AI 예측 (12점)
      if (pred != null && pred.winProbability > 0) {
        if (pred.winProbability >= 25) {
          jockeyScore += 12;
          reasons.add('AI 1순위 예측');
        } else if (pred.winProbability >= 15) {
          jockeyScore += 10;
          reasons.add('AI 상위 예측');
        } else if (pred.winProbability >= 10) {
          jockeyScore += 7;
        } else if (pred.winProbability >= 5) {
          jockeyScore += 4;
        }
      }

      // 배당률 분석 (8점) - 낮은 배당 = 인기마
      if (hasOdds && winOdds > 0) {
        if (winOdds <= 3.0) {
          jockeyScore += 8;
          reasons.add('1번 인기 (${winOdds.toStringAsFixed(1)}배)');
        } else if (winOdds <= 5.0) {
          jockeyScore += 6;
          reasons.add('상위 인기마');
        } else if (winOdds <= avgOdds) {
          jockeyScore += 4;
        } else if (winOdds <= avgOdds * 2) {
          jockeyScore += 2;
        }
      } else if (pred != null) {
        // 배당 없으면 AI 예측으로 보정
        jockeyScore += (pred.winProbability / 100 * 8).clamp(0, 8);
      }

      // ═══════════════════════════════════════════════════
      // 4. 거리 적성 점수 (15점)
      // ═══════════════════════════════════════════════════
      double distanceScore = 0;

      // 해당 거리에서의 승리 경험
      if (entry.winCount >= 2 && totalRaces >= 5) {
        distanceScore = 15;
        reasons.add('해당 거리 적성 우수');
      } else if (entry.winCount >= 1 && totalRaces >= 3) {
        distanceScore = 12;
      } else if (totalRaces >= 5 && placeRate >= 30) {
        distanceScore = 10;
        reasons.add('거리 경험 풍부');
      } else if (totalRaces >= 3) {
        distanceScore = 7;
      } else if (totalRaces >= 1) {
        distanceScore = 4;
      } else {
        distanceScore = 2; // 첫 출전
      }

      // ═══════════════════════════════════════════════════
      // 5. 전개 유리 점수 (15점)
      // ═══════════════════════════════════════════════════
      double paceScore = 5; // 기본점

      if (isFrontHeavy) {
        // 선행마 많음 → 추입마 유리
        if (style == '추입' || style == '후입') {
          paceScore = 15;
          reasons.add('전개 유리 (추입)');
        } else if (style == '중단') {
          paceScore = 10;
        } else {
          paceScore = 3; // 선행은 불리
        }
      } else if (isCloserFavored || frontRunners.length <= 1) {
        // 선행마 적음 → 선행마 유리
        if (style == '선행' || style == '선입') {
          paceScore = 15;
          reasons.add('전개 유리 (선행)');
        } else if (style == '중단') {
          paceScore = 8;
        }
      } else {
        // 균형 전개
        if (ratingRank <= 3) {
          paceScore = 10; // 상위 레이팅은 균형 전개에서도 유리
        } else {
          paceScore = 7;
        }
      }

      // ═══════════════════════════════════════════════════
      // 종합 점수 계산
      // ═══════════════════════════════════════════════════
      final totalScore =
          ratingScore +
          performanceScore +
          jockeyScore +
          distanceScore +
          paceScore;

      recs.add(
        _HorseRecommendation(
          horseNo: entry.horseNo,
          horseName: entry.horseName,
          totalScore: totalScore,
          ratingScore: ratingScore,
          performanceScore: performanceScore,
          jockeyScore: jockeyScore,
          distanceScore: distanceScore,
          paceScore: paceScore,
          reasons: reasons,
        ),
      );
    }

    // 점수순 정렬 + 동점시 레이팅 높은 순
    recs.sort((a, b) {
      final scoreDiff = b.totalScore.compareTo(a.totalScore);
      if (scoreDiff != 0) return scoreDiff;
      return b.ratingScore.compareTo(a.ratingScore);
    });

    return recs.take(3).toList();
  }

  String _getRunningStyle(RaceEntry entry, Prediction? pred) {
    final rating = entry.rating;
    final winRate = entry.winRate;
    final totalRaces = entry.totalRaces;

    if (pred != null && pred.winProbability > 15) {
      if (rating >= 80) return '선행';
      if (rating >= 60) return '선입';
      return '추입';
    }

    if (totalRaces < 3) return '미지수';
    if (rating >= 85 && winRate >= 20) return '선행';
    if (rating >= 70) return '선입';
    if (rating >= 50) return '중단';
    return '후입';
  }

  Color _getScoreColor(double score) {
    if (score >= 80) return Colors.amber;
    if (score >= 65) return AppTheme.positiveGreen;
    if (score >= 50) return Colors.cyanAccent;
    return Colors.grey;
  }

  IconData _getReasonIcon(String reason) {
    if (reason.contains('레이팅')) return Icons.star_rounded;
    if (reason.contains('승률') || reason.contains('입상'))
      return Icons.emoji_events_rounded;
    if (reason.contains('AI')) return Icons.auto_awesome_rounded;
    if (reason.contains('거리')) return Icons.straighten_rounded;
    if (reason.contains('전개')) return Icons.speed_rounded;
    return Icons.check_circle_rounded;
  }
}

class _HorseRecommendation {
  final int horseNo;
  final String horseName;
  final double totalScore;
  final double ratingScore;
  final double performanceScore;
  final double jockeyScore;
  final double distanceScore;
  final double paceScore;
  final List<String> reasons;

  _HorseRecommendation({
    required this.horseNo,
    required this.horseName,
    required this.totalScore,
    required this.ratingScore,
    required this.performanceScore,
    required this.jockeyScore,
    required this.distanceScore,
    required this.paceScore,
    required this.reasons,
  });
}

class _ScoreBadge extends StatelessWidget {
  final String label;
  final double score;
  final double maxScore;

  const _ScoreBadge({
    required this.label,
    required this.score,
    required this.maxScore,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = score / maxScore;
    final color = ratio >= 0.8
        ? AppTheme.positiveGreen
        : ratio >= 0.6
        ? Colors.cyanAccent
        : ratio >= 0.4
        ? Colors.orangeAccent
        : Colors.grey;

    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 3),
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: ratio.clamp(0, 1),
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${score.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// AI 예측 TOP 3
// ═══════════════════════════════════════════════════

class _AiPredictionChart extends StatelessWidget {
  final PredictionReport report;
  final List<RaceEntry> entries;

  const _AiPredictionChart({required this.report, required this.entries});

  String _jockeyFor(Prediction p) {
    if (p.jockeyName.isNotEmpty) return p.jockeyName;
    final entry = entries.where((e) => e.horseNo == p.horseNo).firstOrNull;
    return entry?.jockeyName ?? '';
  }

  RaceEntry? _entryFor(int horseNo) {
    return entries.where((e) => e.horseNo == horseNo).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...report.predictions]
      ..sort((a, b) => b.winProbability.compareTo(a.winProbability));
    final top3 = sorted.take(3).toList();
    if (top3.isEmpty) return const SizedBox.shrink();

    final rankColors = [
      AppTheme.winColor,
      AppTheme.placeColor,
      AppTheme.showColor,
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.deepPurple.shade900.withValues(alpha: 0.55),
            AppTheme.cardDark,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
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
                'AI 승률 예측 TOP 3',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'v${report.modelVersion}',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            children: top3.asMap().entries.map((e) {
              final idx = e.key;
              final p = e.value;
              final color = rankColors[idx];
              final jockey = _jockeyFor(p);

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: idx > 0 ? 8 : 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      children: [
                        // 순위 뱃지
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${idx + 1}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // 마번 (방송 스타일: "1번마")
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${p.horseNo}번',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: color,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // 말 이름
                        Text(
                          p.horseName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),

                        // 기수 이름
                        if (jockey.isNotEmpty)
                          Text(
                            jockey,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        const SizedBox(height: 8),

                        // AI 예측 승률
                        Text(
                          '${p.winProbability.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: color,
                          ),
                        ),
                        const SizedBox(height: 6),

                        // 레이팅 & 승률 (과거 전적)
                        Builder(
                          builder: (_) {
                            final entry = _entryFor(p.horseNo);
                            if (entry == null) return const SizedBox.shrink();
                            return Column(
                              children: [
                                _miniStat(
                                  '레이팅',
                                  entry.rating.toStringAsFixed(0),
                                  Colors.cyanAccent,
                                ),
                                const SizedBox(height: 3),
                                _miniStat(
                                  entry.winCount > 0 ? '승률' : '입상률',
                                  entry.totalRaces > 0
                                      ? entry.winCount > 0
                                            ? '${entry.winRate.toStringAsFixed(1)}%'
                                            : '${entry.placeRate.toStringAsFixed(1)}%'
                                      : '-',
                                  AppTheme.positiveGreen,
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label ',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
        ),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════
// 출마 카드
// ═══════════════════════════════════════════════════

class _HorseCard extends StatelessWidget {
  final RaceEntry entry;
  final double winOdds;
  final Prediction? prediction;
  final int predictionRank;
  final int distance;
  final VoidCallback onTap;

  const _HorseCard({
    required this.entry,
    required this.winOdds,
    this.prediction,
    this.predictionRank = 0,
    this.distance = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isTop = predictionRank >= 1 && predictionRank <= 3;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              // ── 1행: 마번 + 말이름/기수 ──
              Row(
                children: [
                  _HorseNumberBadge(no: entry.horseNo, isTop: isTop),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                entry.horseName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isTop) ...[
                              const SizedBox(width: 8),
                              _AiRankBadge(rank: predictionRank),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            // 성별·연령
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _sexColor(
                                  entry.sexLabel,
                                ).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${entry.sexLabel}${entry.age}세',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _sexColor(entry.sexLabel),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            // 기수
                            Icon(
                              Icons.person,
                              size: 13,
                              color: Colors.blueAccent.shade100,
                            ),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                entry.jockeyName.isNotEmpty
                                    ? entry.jockeyName
                                    : '-',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blueAccent.shade100,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (entry.trainerName.isNotEmpty) ...[
                              Text(
                                '  •  ',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  entry.trainerName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade400,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ── 2행: 핵심 5개 스탯 (마번, 레이팅, 승률, 배당, AI예측) ──
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    _StatColumn(
                      label: '레이팅',
                      value: entry.rating > 0
                          ? entry.rating.toStringAsFixed(0)
                          : '-',
                      color: Colors.cyanAccent,
                    ),
                    _statDivider(),
                    _StatColumn(
                      label: '전적',
                      value: entry.totalRaces > 0
                          ? '${entry.totalRaces}전${entry.winCount}승${entry.placeCount}복'
                          : '-',
                      color: Colors.white70,
                    ),
                    _statDivider(),
                    _StatColumn(
                      label: entry.winCount > 0 ? '승률' : '입상률',
                      value: entry.totalRaces > 0
                          ? entry.winCount > 0
                                ? '${entry.winRate.toStringAsFixed(1)}%'
                                : '${entry.placeRate.toStringAsFixed(1)}%'
                          : '-',
                      color: AppTheme.positiveGreen,
                    ),
                    _statDivider(),
                    _StatColumn(
                      label: winOdds > 0 ? '배당' : '예상배당',
                      value: winOdds > 0
                          ? '${winOdds.toStringAsFixed(1)}배'
                          : prediction != null && prediction!.winProbability > 0
                          ? '${(100 / prediction!.winProbability).toStringAsFixed(1)}배'
                          : '-',
                      color: AppTheme.accentGold,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // ── 3행: 부가 정보 ──
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _MiniChip(
                          '${entry.weight.toStringAsFixed(0)}kg',
                          Colors.grey.shade400,
                        ),
                        if (entry.horseWeight > 0)
                          _MiniChip(
                            '마체중 ${entry.horseWeight.toStringAsFixed(0)}kg',
                            Colors.grey.shade400,
                          ),
                        if (distance > 0)
                          _MiniChip('${distance}m', AppTheme.accentGold),
                        _MiniChip(
                          '${entry.totalRaces}전 ${entry.winCount}승 ${entry.placeCount}복',
                          Colors.grey.shade400,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statDivider() => Container(
    width: 1,
    height: 28,
    margin: const EdgeInsets.symmetric(horizontal: 2),
    color: Colors.grey.shade700.withValues(alpha: 0.5),
  );

  static Color _sexColor(String sex) {
    switch (sex) {
      case '수':
        return Colors.blueAccent;
      case '암':
        return Colors.pinkAccent;
      case '거':
        return Colors.tealAccent;
      default:
        return Colors.grey;
    }
  }
}

// ═══════════════════════════════════════════════════
// 공통 위젯
// ═══════════════════════════════════════════════════

class _HorseNumberBadge extends StatelessWidget {
  final int no;
  final bool isTop;

  const _HorseNumberBadge({required this.no, this.isTop = false});

  static const _gradients = [
    [Color(0xFFE0E0E0), Color(0xFFBDBDBD)], // 1 흰
    [Color(0xFF424242), Color(0xFF212121)], // 2 검
    [Color(0xFFEF5350), Color(0xFFC62828)], // 3 빨
    [Color(0xFF42A5F5), Color(0xFF1565C0)], // 4 파
    [Color(0xFFFFA726), Color(0xFFE65100)], // 5 주
    [Color(0xFF66BB6A), Color(0xFF2E7D32)], // 6 초
    [Color(0xFFAB47BC), Color(0xFF6A1B9A)], // 7 보
    [Color(0xFFEC407A), Color(0xFFC2185B)], // 8 핑
    [Color(0xFF78909C), Color(0xFF37474F)], // 9 회
    [Color(0xFF8D6E63), Color(0xFF4E342E)], // 10 갈
    [Color(0xFF26A69A), Color(0xFF00695C)], // 11 청
    [Color(0xFF5C6BC0), Color(0xFF283593)], // 12 남
  ];

  @override
  Widget build(BuildContext context) {
    final colors = _gradients[(no - 1) % _gradients.length];
    final isLight = no == 1 || no == 5;

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(11),
        boxShadow: isTop
            ? [
                BoxShadow(
                  color: colors[0].withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Center(
        child: Text(
          '$no',
          style: TextStyle(
            color: isLight ? Colors.black87 : Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _AiRankBadge extends StatelessWidget {
  final int rank;
  const _AiRankBadge({required this.rank});

  @override
  Widget build(BuildContext context) {
    final colors = [AppTheme.winColor, AppTheme.placeColor, AppTheme.showColor];
    final color = colors[(rank - 1).clamp(0, 2)];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        'AI $rank위',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatColumn({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String text;
  final Color color;

  const _MiniChip(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
