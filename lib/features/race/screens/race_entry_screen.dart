import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../../models/race.dart';
import '../../../models/race_entry.dart';
import '../../../models/odds.dart';
import '../../../models/prediction.dart';
import '../providers/race_providers.dart';

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
    final raceAsync = ref.watch(
      racePlanProvider((meet: meet, date: date)),
    );
    final entriesAsync = ref.watch(
      raceStartListProvider(
        (meet: meet, date: date, raceNo: raceNo),
      ),
    );
    final oddsAsync = ref.watch(
      oddsProvider(
        (meet: meet, date: date, raceNo: raceNo),
      ),
    );
    final predAsync = ref.watch(
      predictionProvider(
        (meet: meet, date: date, raceNo: raceNo),
      ),
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
                    onPressed: () => context.push(
                      '/result/$meet/$date/$raceNo',
                    ),
                  ),
              ],
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
                  return _AiPredictionChart(
                      report: report, entries: entries);
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
                        onTap: () => context.push(
                          '/result/$meet/$date/$raceNo',
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.emoji_events_rounded,
                                size: 15, color: AppTheme.winColor),
                            const SizedBox(width: 4),
                            Text(
                              '결과',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.winColor,
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded,
                                size: 18, color: AppTheme.winColor),
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
                      Icon(Icons.error_outline,
                          size: 48, color: Colors.grey.shade600),
                      const SizedBox(height: 12),
                      Text('출마표를 불러올 수 없습니다',
                          style: TextStyle(color: Colors.grey.shade400)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => ref.invalidate(raceStartListProvider(
                          (meet: meet, date: date, raceNo: raceNo),
                        )),
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
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final entry = sorted[i];
                      final winOdds = _findWinOdds(odds, entry.horseNo);
                      final pred =
                          _findPrediction(predictions, entry.horseNo);
                      final predRank =
                          _predictionRank(predictions, entry.horseNo);

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
                    },
                    childCount: sorted.length,
                  ),
                );
              },
            ),

            const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
          ],
        ),
      ),
    );
  }

  static bool _isRaceFinished(Race? race) {
    if (race == null || race.startTime.isEmpty) return false;
    try {
      final now = DateTime.now();
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
}

// ═══════════════════════════════════════════════════
// AI 예측 TOP 3
// ═══════════════════════════════════════════════════

class _AiPredictionChart extends StatelessWidget {
  final PredictionReport report;
  final List<RaceEntry> entries;

  const _AiPredictionChart({
    required this.report,
    required this.entries,
  });

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
        border: Border.all(
            color: Colors.deepPurple.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome,
                  size: 18, color: Colors.purpleAccent.shade100),
              const SizedBox(width: 6),
              const Text('AI 승률 예측 TOP 3',
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('v${report.modelVersion}',
                    style: TextStyle(
                        fontSize: 10, color: Colors.grey.shade400)),
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
                        horizontal: 8, vertical: 12),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: color.withValues(alpha: 0.3)),
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
                              horizontal: 8, vertical: 3),
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
                        Builder(builder: (_) {
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
                        }),
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
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
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
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _sexColor(entry.sexLabel)
                                    .withValues(alpha: 0.15),
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
                            Icon(Icons.person, size: 13,
                                color: Colors.blueAccent.shade100),
                            const SizedBox(width: 3),
                            Text(
                              entry.jockeyName.isNotEmpty
                                  ? entry.jockeyName
                                  : '-',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.blueAccent.shade100,
                              ),
                            ),
                            if (entry.trainerName.isNotEmpty) ...[
                              Text('  •  ',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600)),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
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
                          : prediction != null &&
                                  prediction!.winProbability > 0
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

