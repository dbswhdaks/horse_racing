import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../../models/odds.dart';
import '../../../models/prediction.dart';
import '../../../models/race_entry.dart';
import '../providers/race_providers.dart';
import '../widgets/race_auto_refresh_hook.dart';

class RaceDetailScreen extends ConsumerWidget {
  final String meet;
  final String date;
  final int raceNo;

  const RaceDetailScreen({
    super.key,
    required this.meet,
    required this.date,
    required this.raceNo,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(
      raceStartListProvider((meet: meet, date: date, raceNo: raceNo)),
    );
    final oddsAsync = ref.watch(
      oddsProvider((meet: meet, date: date, raceNo: raceNo)),
    );
    final predAsync = ref.watch(
      predictionProvider((meet: meet, date: date, raceNo: raceNo)),
    );

    final meetName = ApiConstants.meetNames[meet] ?? meet;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 64,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/');
              }
            },
          ),
          title: Text('$meetName ${raceNo}R'),
          centerTitle: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.emoji_events_rounded, size: 22),
              tooltip: '경주결과',
              onPressed: () => context.push('/result/$meet/$date/$raceNo'),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(46),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                ),
              ),
              child: const TabBar(
                labelColor: Color(0xFF00C853),
                unselectedLabelColor: Color(0xFF8A8F96),
                indicatorSize: TabBarIndicatorSize.label,
                indicator: UnderlineTabIndicator(
                  borderSide: BorderSide(color: Color(0xFF00C853), width: 3),
                ),
                labelStyle: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
                unselectedLabelStyle: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                tabs: [
                  Tab(text: '종합추천'),
                  Tab(text: 'AI 추천'),
                ],
              ),
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              RaceAutoRefreshHook(meet: meet, date: date, raceNo: raceNo),
              Expanded(
                child: TabBarView(
                  children: [
                    _TotalTab(
                      meet: meet,
                      date: date,
                      raceNo: raceNo,
                      entriesAsync: entriesAsync,
                      oddsAsync: oddsAsync,
                      predAsync: predAsync,
                    ),
                    _AiTab(
                      meet: meet,
                      date: date,
                      raceNo: raceNo,
                      entriesAsync: entriesAsync,
                      predAsync: predAsync,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━ 종합추천 탭 ━━━━━━━━━━━━━━━━━

class _TotalTab extends StatelessWidget {
  final String meet, date;
  final int raceNo;
  final AsyncValue<List<RaceEntry>> entriesAsync;
  final AsyncValue<List<Odds>> oddsAsync;
  final AsyncValue<PredictionReport?> predAsync;

  const _TotalTab({
    required this.meet,
    required this.date,
    required this.raceNo,
    required this.entriesAsync,
    required this.oddsAsync,
    required this.predAsync,
  });

  @override
  Widget build(BuildContext context) {
    return entriesAsync.when(
      loading: () => const _TabShimmer(),
      error: (_, __) => const Center(child: Text('출주 데이터를 불러올 수 없습니다')),
      data: (entries) {
        final odds = oddsAsync.valueOrNull ?? const <Odds>[];
        final report = predAsync.valueOrNull;
        final ranked = _buildRanked(entries, odds, report);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (ranked.isNotEmpty) _PickSummaryCard(ranked: ranked),
            const SizedBox(height: 16),
            _SectionHeader(
              icon: Icons.format_list_numbered_rounded,
              title: '출주표',
              trailing: _ResultButton(
                onTap: () => context.push('/result/$meet/$date/$raceNo'),
              ),
            ),
            const SizedBox(height: 10),
            ...ranked.asMap().entries.map((e) {
              final idx = e.key;
              final horse = e.value;
              return _HorseEntryCard(
                rank: idx + 1,
                candidate: horse,
                onTap: () => context.push(
                  '/horse/${Uri.encodeComponent(horse.entry.horseName)}?meet=$meet',
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

// ━━━━━━━━━━━━━━━━━ AI 추천 탭 ━━━━━━━━━━━━━━━━━

class _AiTab extends StatelessWidget {
  final String meet, date;
  final int raceNo;
  final AsyncValue<List<RaceEntry>> entriesAsync;
  final AsyncValue<PredictionReport?> predAsync;

  const _AiTab({
    required this.meet,
    required this.date,
    required this.raceNo,
    required this.entriesAsync,
    required this.predAsync,
  });

  @override
  Widget build(BuildContext context) {
    final entries = entriesAsync.valueOrNull ?? const <RaceEntry>[];
    final meetName = ApiConstants.meetNames[meet] ?? meet;

    return predAsync.when(
      loading: () => const _TabShimmer(),
      error: (_, __) => const Center(child: Text('AI 예측 데이터를 불러올 수 없습니다')),
      data: (report) {
        if (report == null || report.predictions.isEmpty) {
          return const Center(child: _OfflineBanner());
        }

        final sorted = [...report.predictions]
          ..sort(Prediction.compareByWinThenPlace);
        final top3 = sorted.take(3).toList();
        final confidence = _confidence(sorted);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _AiHeaderCard(
              title: '$meetName ${raceNo}R AI 예측',
              confidence: confidence,
              topProb: top3.first.winProbability,
            ),
            const SizedBox(height: 16),
            _SectionHeader(
              icon: Icons.emoji_events_rounded,
              iconColor: AppTheme.winColor,
              title: 'AI 추천(승률순)',
              trailing: _ResultButton(
                onTap: () => context.push('/result/$meet/$date/$raceNo'),
              ),
            ),
            const SizedBox(height: 10),
            ...sorted.asMap().entries.map((e) {
              final rank = e.key + 1;
              final pred = e.value;
              final entry = entries
                  .where((en) => en.horseNo == pred.horseNo)
                  .firstOrNull;
              return _AiRankCard(
                rank: rank,
                prediction: pred,
                entry: entry,
                isTop3: rank <= 3,
              );
            }),
            const SizedBox(height: 16),
            _BettingSection(top3: top3),
            const SizedBox(height: 16),
            _AnalysisSection(top3: top3),
            const SizedBox(height: 16),
            _FeatureSection(top3: top3),
          ],
        );
      },
    );
  }

  int _confidence(List<Prediction> sorted) {
    if (sorted.length < 2) return 70;
    final gap = sorted[0].winProbability - sorted[1].winProbability;
    return (55 + gap * 2.2).clamp(50, 92).round();
  }
}

// ━━━━━━━━━━━━━━━━━ 종합추천 카드 ━━━━━━━━━━━━━━━━━

class _PickSummaryCard extends StatelessWidget {
  final List<_Candidate> ranked;
  const _PickSummaryCard({required this.ranked});

  @override
  Widget build(BuildContext context) {
    final top3 = ranked.take(3).toList();
    final a = top3[0], b = top3.length > 1 ? top3[1] : a;
    final c = top3.length > 2 ? top3[2] : b;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1820),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.star_rounded,
                color: AppTheme.accentGold,
                size: 18,
              ),
              const SizedBox(width: 6),
              const Text(
                '종합 추천',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                '등급 · 성적 · 배당 종합',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...top3.asMap().entries.map((item) {
            final rank = item.key + 1;
            final h = item.value;
            final colors = [
              AppTheme.winColor,
              AppTheme.placeColor,
              AppTheme.showColor,
            ];
            return Padding(
              padding: EdgeInsets.only(bottom: rank == 3 ? 0 : 6),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: colors[rank - 1].withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$rank',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: colors[rank - 1],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          '${h.entry.horseNo}번 ${h.entry.horseName}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _Tag('선발'),
                        if (h.entry.jockeyName.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          _Tag(h.entry.jockeyName, highlight: true),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    '평균 ${h.score.toStringAsFixed(1)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade300,
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFF2A2F38)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              _PickBadge(
                '단승 추천',
                '${a.entry.horseNo}번 ${a.entry.horseName}',
                const Color(0xFF8E2020),
              ),
              _PickBadge(
                '복승 추천',
                '${a.entry.horseNo}-${b.entry.horseNo}',
                const Color(0xFF0D3B7A),
              ),
              _PickBadge(
                '쌍승 추천',
                '${a.entry.horseNo}→${b.entry.horseNo}',
                const Color(0xFF4A1F86),
              ),
              _PickBadge(
                '삼복승 추천',
                '${a.entry.horseNo}-${b.entry.horseNo}-${c.entry.horseNo}',
                const Color(0xFF725500),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━ 출주표 카드 ━━━━━━━━━━━━━━━━━

class _HorseEntryCard extends StatelessWidget {
  final int rank;
  final _Candidate candidate;
  final VoidCallback onTap;

  const _HorseEntryCard({
    required this.rank,
    required this.candidate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final e = candidate.entry;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFF151C26),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
              alignment: Alignment.center,
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade400,
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
                      Flexible(
                        child: Text(
                          e.horseName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF00D35B),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.open_in_new_rounded,
                        size: 12,
                        color: Color(0xFF00D35B),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      _Tag('선발'),
                      if (e.jockeyName.isNotEmpty)
                        _Tag(e.jockeyName, highlight: true),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '평균 ${candidate.score.toStringAsFixed(1)}점',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '직전 우승 ${e.winCount}회',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━ AI 헤더 카드 ━━━━━━━━━━━━━━━━━

class _AiHeaderCard extends StatelessWidget {
  final String title;
  final int confidence;
  final double topProb;

  const _AiHeaderCard({
    required this.title,
    required this.confidence,
    required this.topProb,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A2042), Color(0xFF151B2E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF5A52A3).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                color: Color(0xFF9A7CFF),
                size: 16,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF956FFF),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accentGold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.accentGold.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  '신뢰도 $confidence%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.accentGold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (topProb / 100).clamp(0, 1),
              minHeight: 7,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              valueColor: const AlwaysStoppedAnimation(AppTheme.accentGold),
            ),
          ),
        ],
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━ AI 순위 카드 ━━━━━━━━━━━━━━━━━

class _AiRankCard extends StatelessWidget {
  final int rank;
  final Prediction prediction;
  final RaceEntry? entry;
  final bool isTop3;

  const _AiRankCard({
    required this.rank,
    required this.prediction,
    this.entry,
    this.isTop3 = false,
  });

  @override
  Widget build(BuildContext context) {
    final probColor = isTop3 ? AppTheme.accentGold : Colors.grey.shade400;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.fromLTRB(10, 10, 12, isTop3 ? 8 : 10),
      decoration: BoxDecoration(
        color: const Color(0xFF151C26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isTop3
              ? AppTheme.accentGold.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '$rank',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: isTop3 ? AppTheme.accentGold : Colors.grey.shade500,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                child: Text(
                  '${prediction.horseNo}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        prediction.horseName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 5),
                    _Tag('선발'),
                    if ((entry?.jockeyName ?? '').isNotEmpty) ...[
                      const SizedBox(width: 4),
                      _Tag(entry!.jockeyName, highlight: true),
                    ],
                  ],
                ),
              ),
              Text(
                '${prediction.winProbability.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: probColor,
                ),
              ),
            ],
          ),
          if (isTop3) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: (prediction.winProbability / 100).clamp(0, 1),
                minHeight: 4,
                backgroundColor: Colors.transparent,
                valueColor: const AlwaysStoppedAnimation(Color(0xFF00C853)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━ 추천 베팅 ━━━━━━━━━━━━━━━━━

class _BettingSection extends StatelessWidget {
  final List<Prediction> top3;
  const _BettingSection({required this.top3});

  @override
  Widget build(BuildContext context) {
    final a = top3[0];
    final b = top3.length > 1 ? top3[1] : a;
    final c = top3.length > 2 ? top3[2] : b;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          icon: Icons.casino_rounded,
          iconColor: AppTheme.primaryGreen,
          title: '추천 베팅',
        ),
        const SizedBox(height: 10),
        _BetCard('단승', const Color(0xFF2A151B), const Color(0xFF70313D), [
          _BetRow('${a.horseNo}번 ${a.horseName}', _tagLine(a)),
          _BetRow('${b.horseNo}번 ${b.horseName}', _tagLine(b)),
        ]),
        _BetCard('복승', const Color(0xFF10233D), const Color(0xFF234E7A), [
          _BetRow(
            '${a.horseNo}-${b.horseNo}',
            '${a.horseName} · ${b.horseName}',
          ),
          _BetRow(
            '${a.horseNo}-${c.horseNo}',
            '${a.horseName} · ${c.horseName}',
          ),
        ]),
        _BetCard('쌍승', const Color(0xFF221A43), const Color(0xFF5440A2), [
          _BetRow(
            '${a.horseNo}→${b.horseNo}',
            '${a.horseName}(1착) → ${b.horseName}(2착)',
          ),
          _BetRow(
            '${a.horseNo}→${c.horseNo}',
            '${a.horseName}(1착) → ${c.horseName}(2착)',
          ),
        ]),
      ],
    );
  }

  String _tagLine(Prediction p) {
    final tags = p.tags.take(2).join(' · ');
    return tags.isNotEmpty
        ? tags
        : '입상 ${p.placeProbability.toStringAsFixed(1)}%';
  }
}

// ━━━━━━━━━━━━━━━━━ AI 분석 ━━━━━━━━━━━━━━━━━

class _AnalysisSection extends StatelessWidget {
  final List<Prediction> top3;
  const _AnalysisSection({required this.top3});

  @override
  Widget build(BuildContext context) {
    final a = top3[0];
    final b = top3.length > 1 ? top3[1] : a;
    final c = top3.length > 2 ? top3[2] : b;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          icon: Icons.insights_rounded,
          iconColor: Colors.lightBlueAccent,
          title: 'AI 분석',
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF102540),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.lightBlue.withValues(alpha: 0.3)),
          ),
          child: Text(
            '${a.horseNo}번 ${a.horseName} 선수가 선발등급의 높은 기량과 '
            '선두 견제 후 추월 전법으로 가장 유리합니다.\n\n'
            '대항마로 ${b.horseNo}번 ${b.horseName}(선발), '
            '${c.horseNo}번 ${c.horseName} 선수를 주시하세요.',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.5,
              color: Colors.grey.shade200,
            ),
          ),
        ),
      ],
    );
  }
}

// ━━━━━━━━━━━━━━━━━ 요소별 분석 ━━━━━━━━━━━━━━━━━

class _FeatureSection extends StatelessWidget {
  final List<Prediction> top3;
  const _FeatureSection({required this.top3});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          icon: Icons.bar_chart_rounded,
          iconColor: AppTheme.accentGold,
          title: '요소별 분석 (상위 3명)',
        ),
        const SizedBox(height: 10),
        ...top3.asMap().entries.map((entry) {
          final idx = entry.key;
          final p = entry.value;
          return _FeatureCard(rank: idx + 1, prediction: p);
        }),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final int rank;
  final Prediction prediction;
  const _FeatureCard({required this.rank, required this.prediction});

  @override
  Widget build(BuildContext context) {
    final features = _topFeatures();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF141D28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                child: Text(
                  '${prediction.horseNo}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  prediction.horseName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$rank위',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.accentGold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...features.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: _BarRow(label: f.$1, value: f.$2, color: f.$3),
            ),
          ),
        ],
      ),
    );
  }

  List<(String, double, Color)> _topFeatures() {
    final raw =
        prediction.featureImportance.entries
            .map((e) => (e.key, e.value.toDouble()))
            .toList()
          ..sort((a, b) => b.$2.compareTo(a.$2));

    if (raw.isEmpty) {
      return [
        ('등급', 0.4, Colors.redAccent),
        ('평균득점', 0.5, Colors.blueAccent),
        ('최근 전적', 0.55, Colors.green),
        ('전법', 0.25, Colors.purpleAccent),
      ];
    }
    return raw.take(4).map((e) {
      final label = _label(e.$1);
      return (label, e.$2, _color(label));
    }).toList();
  }

  static String _label(String key) {
    const map = {
      'rating': '등급',
      'horse_rating': '등급',
      'win_rate': '평균득점',
      'jockey_win_rate': '평균득점',
      'recent_form': '최근 전적',
      'recent_rank': '최근 전적',
      'distance_fit': '전법',
      'distance_score': '거리',
    };
    return map[key] ?? key;
  }

  static Color _color(String label) {
    switch (label) {
      case '등급':
        return Colors.redAccent;
      case '평균득점':
        return Colors.blueAccent;
      case '최근 전적':
        return Colors.green;
      default:
        return Colors.purpleAccent;
    }
  }
}

// ━━━━━━━━━━━━━━━━━ 공통 위젯 ━━━━━━━━━━━━━━━━━

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final Widget? trailing;

  const _SectionHeader({
    required this.icon,
    this.iconColor,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: iconColor ?? Colors.white),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _ResultButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ResultButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.emoji_events, size: 14),
      label: const Text(
        '결과',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.accentGold,
        side: BorderSide(color: AppTheme.accentGold.withValues(alpha: 0.4)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final bool highlight;
  const _Tag(this.text, {this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: highlight
            ? const Color(0xFF0A4A2F)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: highlight ? const Color(0xFF00D35B) : Colors.grey.shade400,
        ),
      ),
    );
  }
}

class _PickBadge extends StatelessWidget {
  final String label, text;
  final Color color;
  const _PickBadge(this.label, this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _BetCard extends StatelessWidget {
  final String label;
  final Color bg, stroke;
  final List<_BetRow> rows;
  const _BetCard(this.label, this.bg, this.stroke, this.rows);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: stroke.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: stroke.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...rows,
        ],
      ),
    );
  }
}

class _BetRow extends StatelessWidget {
  final String number, desc;
  const _BetRow(this.number, this.desc);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              number,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              desc,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _BarRow({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: v,
              minHeight: 7,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 32,
          child: Text(
            (v * 30).toStringAsFixed(1),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 48, color: Colors.purple.shade300),
          const SizedBox(height: 12),
          const Text(
            'AI 예측 데이터를 준비 중입니다',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            '출전표 정보 확보 후 자동 표시됩니다',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

class _TabShimmer extends StatelessWidget {
  const _TabShimmer();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        ShimmerLoading(height: 160),
        SizedBox(height: 10),
        ShimmerLoading(height: 280),
      ],
    );
  }
}

// ━━━━━━━━━━━━━━━━━ 데이터 ━━━━━━━━━━━━━━━━━

class _Candidate {
  final RaceEntry entry;
  final double score;
  const _Candidate({required this.entry, required this.score});
}

List<_Candidate> _buildRanked(
  List<RaceEntry> entries,
  List<Odds> odds,
  PredictionReport? report,
) {
  final predByNo = <int, Prediction>{
    for (final p in report?.predictions ?? const <Prediction>[]) p.horseNo: p,
  };
  final oddsByNo = <int, double>{};
  for (final o in odds) {
    if (o.betType == 'WIN' || o.betType == '1') oddsByNo[o.horseNo1] = o.rate;
  }

  return entries.map((e) {
    final pred = predByNo[e.horseNo];
    final winOdds = oddsByNo[e.horseNo] ?? 0;
    final predScore = pred?.winProbability ?? 0;
    final placeScore = pred?.placeProbability ?? 0;
    final oddsScore = winOdds > 0 ? (100 / winOdds).clamp(0, 100) : 0.0;
    final formScore = e.rating > 0
        ? e.rating.clamp(0, 100)
        : (e.winRate * 2.3).clamp(0, 100);
    // 종합출주: 입상(3위권) 위주 — 승률 가중 ↓, 입상 가중 ↑
    final score =
        predScore * 0.22 +
        placeScore * 0.48 +
        oddsScore * 0.15 +
        formScore * 0.15;
    return _Candidate(entry: e, score: score);
  }).toList()..sort((a, b) {
    final scoreCompare = b.score.compareTo(a.score);
    if (scoreCompare != 0) return scoreCompare;
    return a.entry.horseNo.compareTo(b.entry.horseNo);
  });
}
