import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/constants/iap_constants.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../../models/race.dart';
import '../../../models/race_entry.dart';
import '../../../models/odds.dart';
import '../../../models/prediction.dart';
import '../../purchase/providers/in_app_purchase_provider.dart';
import '../providers/race_providers.dart';
import '../widgets/race_auto_refresh_hook.dart';

class RaceEntryScreen extends ConsumerWidget {
  final String meet;
  final String date;
  final int raceNo;
  final int initialTabIndex;

  const RaceEntryScreen({
    super.key,
    required this.meet,
    required this.date,
    required this.raceNo,
    this.initialTabIndex = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iapState = ref.watch(inAppPurchaseProvider);
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
    final meetName = ApiConstants.meetNames[meet] ?? meet;
    final purchasedProductIds = ref.watch(
      inAppPurchaseProvider.select((state) => state.purchasedProductIds),
    );
    final canViewComprehensive = purchasedProductIds.any(
      IapConstants.subscriptionProductIds.contains,
    );
    final race = raceAsync.valueOrNull
        ?.where((r) => r.raceNo == raceNo)
        .firstOrNull;

    return DefaultTabController(
      length: 2,
      initialIndex: initialTabIndex.clamp(0, 1),
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
            if (_isRaceFinished(race))
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton.icon(
                  onPressed: () => context.push('/result/$meet/$date/$raceNo'),
                  icon: Icon(
                    Icons.emoji_events_rounded,
                    size: 18,
                    color: AppTheme.winColor,
                  ),
                  label: Text(
                    '결과',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.winColor,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.winColor,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
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
                    // ── 종합추천 탭 ──
                    _buildTotalTab(
                      context,
                      ref,
                      race,
                      entriesAsync,
                      oddsAsync,
                      predAsync,
                      canViewComprehensive,
                    ),
                    // ── AI 추천 탭 ──
                    _buildAiTab(
                      context,
                      entriesAsync,
                      predAsync,
                      canViewComprehensive,
                      iapState,
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

  Widget _buildTotalTab(
    BuildContext context,
    WidgetRef ref,
    Race? race,
    AsyncValue<List<RaceEntry>> entriesAsync,
    AsyncValue<List<Odds>> oddsAsync,
    AsyncValue<PredictionReport?> predAsync,
    bool canViewComprehensive,
  ) {
    return entriesAsync.when(
      loading: () => ListView(
        padding: const EdgeInsets.all(12),
        children: const [
          ShimmerLoading(height: 200),
          SizedBox(height: 10),
          ShimmerLoading(height: 300),
        ],
      ),
      error: (err, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey.shade600),
            const SizedBox(height: 12),
            Text(
              '출마표를 불러올 수 없습니다',
              style: TextStyle(color: Colors.grey.shade400),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => ref.invalidate(
                raceStartListProvider((meet: meet, date: date, raceNo: raceNo)),
              ),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return const Center(child: Text('출마 정보가 없습니다'));
        }
        final odds = oddsAsync.valueOrNull ?? [];
        final predictions = predAsync.valueOrNull?.predictions ?? [];
        final sorted = List<RaceEntry>.from(entries)
          ..sort((a, b) => a.horseNo.compareTo(b.horseNo));
        final distance = race?.distance ?? 0;

        return CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
            SliverToBoxAdapter(
              child: _NumberRecommender(
                key: ValueKey('pick_${meet}_${date}_$raceNo'),
                raceKey: '${meet}_${date}_$raceNo',
                entries: entries,
                predictions: predictions,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
            // 종합 추천
            SliverToBoxAdapter(
              child: () {
                if (entries.isEmpty) return const SizedBox.shrink();
                if (!canViewComprehensive) {
                  return const _PremiumSubscribeInlineCta();
                }
                return _ComprehensiveRecommendation(
                  raceKey: '${meet}_${date}_$raceNo',
                  entries: entries,
                  predictions: predictions,
                  odds: odds,
                  distance: race?.distance ?? 1400,
                );
              }(),
            ),

            // 예상 전개
            SliverToBoxAdapter(
              child: () {
                if (entries.isEmpty) return const SizedBox.shrink();
                if (!canViewComprehensive) {
                  return const SizedBox.shrink();
                }
                return _RacePacePreview(
                  entries: entries,
                  predictions: predictions,
                  odds: odds,
                  distance: race?.distance ?? 1400,
                );
              }(),
            ),

            // 출마표 헤더
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
                  ],
                ),
              ),
            ),

            // 출마표 목록
            SliverList(
              delegate: SliverChildBuilderDelegate((ctx, i) {
                final entry = sorted[i];
                final winOdds = _findWinOdds(odds, entry.horseNo);
                final pred = _findPrediction(predictions, entry.horseNo);
                final predRank = _predictionRank(predictions, entry.horseNo);
                return _HorseCard(
                  entry: entry,
                  winOdds: winOdds,
                  prediction: pred,
                  predictionRank: predRank,
                  distance: distance,
                  onTap: () => context.push(
                    '/horse/${Uri.encodeComponent(entry.horseName)}?meet=$meet',
                    extra: entry,
                  ),
                );
              }, childCount: sorted.length),
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
        );
      },
    );
  }

  Widget _buildAiTab(
    BuildContext context,
    AsyncValue<List<RaceEntry>> entriesAsync,
    AsyncValue<PredictionReport?> predAsync,
    bool canViewComprehensive,
    InAppPurchaseState iapState,
  ) {
    if (!canViewComprehensive) {
      return _PremiumSubscriptionPaywall(iapState: iapState);
    }

    return predAsync.when(
      loading: () => ListView(
        padding: const EdgeInsets.all(12),
        children: const [
          ShimmerLoading(height: 120),
          SizedBox(height: 10),
          ShimmerLoading(height: 400),
        ],
      ),
      error: (_, __) => const Center(child: Text('AI 예측 데이터를 불러올 수 없습니다')),
      data: (report) {
        if (report == null || report.predictions.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.auto_awesome,
                    size: 48,
                    color: Colors.purple.shade300,
                  ),
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
            ),
          );
        }

        final entries = entriesAsync.valueOrNull ?? [];
        final meetName = ApiConstants.meetNames[meet] ?? meet;
        final sorted = [...report.predictions]
          ..sort((a, b) => b.winProbability.compareTo(a.winProbability));

        final gap = sorted.length >= 2
            ? sorted[0].winProbability - sorted[1].winProbability
            : 0.0;
        final confidence = (55 + gap * 2.5).clamp(50, 92).round();

        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 28, 14, 32),
          children: [
            _NumberRecommender(
              key: ValueKey('pick_${meet}_${date}_$raceNo'),
              raceKey: '${meet}_${date}_$raceNo',
              entries: entries,
              predictions: sorted,
              horizontalMargin: 0,
            ),
            const SizedBox(height: 20),
            // AI 예측 신뢰도 카드
            Container(
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
                          '$meetName ${raceNo}R AI 예측',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF956FFF),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
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
                      value: (confidence / 100).clamp(0.0, 1.0),
                      minHeight: 7,
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      valueColor: const AlwaysStoppedAnimation(
                        AppTheme.accentGold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 순위 예측 헤더
            Row(
              children: [
                const Icon(
                  Icons.emoji_events_rounded,
                  color: AppTheme.winColor,
                  size: 18,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    '순위 예측',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                if (_isRaceFinished(null))
                  OutlinedButton.icon(
                    onPressed: () =>
                        context.push('/result/$meet/$date/$raceNo'),
                    icon: const Icon(Icons.emoji_events, size: 14),
                    label: const Text(
                      '결과',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accentGold,
                      side: BorderSide(
                        color: AppTheme.accentGold.withValues(alpha: 0.4),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // 순위 예측 리스트
            ...sorted.asMap().entries.map((e) {
              final rank = e.key + 1;
              final pred = e.value;
              final isTop3 = rank <= 3;
              final matchEntry = entries
                  .where((en) => en.horseNo == pred.horseNo)
                  .firstOrNull;

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
                          width: 30,
                          child: Text(
                            '$rank',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: isTop3
                                  ? AppTheme.accentGold
                                  : Colors.grey.shade500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Text(
                                '${pred.horseNo}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  pred.horseName,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  '선발',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                              ),
                              if ((matchEntry?.jockeyName ?? '')
                                  .isNotEmpty) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0A4A2F),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    matchEntry!.jockeyName,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF00D35B),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Text(
                          '${pred.winProbability.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: isTop3
                                ? AppTheme.accentGold
                                : Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                    if (isTop3) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: (pred.winProbability / 100).clamp(0.0, 1.0),
                          minHeight: 4,
                          backgroundColor: Colors.transparent,
                          valueColor: const AlwaysStoppedAnimation(
                            Color(0xFF00C853),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),

            const SizedBox(height: 18),

            // AI 분석 설명
            _buildAiAnalysis(sorted, entries),
          ],
        );
      },
    );
  }

  Widget _buildAiAnalysis(List<Prediction> sorted, List<RaceEntry> entries) {
    if (sorted.isEmpty) return const SizedBox.shrink();
    final a = sorted[0];
    final b = sorted.length > 1 ? sorted[1] : a;
    final c = sorted.length > 2 ? sorted[2] : b;

    final aEntry = entries.where((e) => e.horseNo == a.horseNo).firstOrNull;
    final bEntry = entries.where((e) => e.horseNo == b.horseNo).firstOrNull;

    String reason1 = _buildReason(a, aEntry);
    String reason2 = _buildReason(b, bEntry);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.insights_rounded,
              color: Colors.lightBlueAccent,
              size: 18,
            ),
            const SizedBox(width: 6),
            const Text(
              'AI 분석',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ],
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
            '${a.horseNo}번 ${a.horseName} 선수가 $reason1으로 가장 유리합니다.\n\n'
            '대항마로 ${b.horseNo}번 ${b.horseName}($reason2), '
            '${c.horseNo}번 ${c.horseName} 선수를 주시하세요.',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.5,
              color: Colors.grey.shade200,
            ),
          ),
        ),
        const SizedBox(height: 14),

        // 선택 근거 상세
        ...sorted.take(3).toList().asMap().entries.map((entry) {
          final idx = entry.key;
          final pred = entry.value;
          final matchEntry = entries
              .where((e) => e.horseNo == pred.horseNo)
              .firstOrNull;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF141D28),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.accentGold.withValues(alpha: 0.15),
                      ),
                      child: Text(
                        '${idx + 1}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.accentGold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${pred.horseNo}번 ${pred.horseName}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '${pred.winProbability.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.accentGold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _buildDetailedReason(pred, matchEntry),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: Colors.grey.shade300,
                  ),
                ),
                if (pred.tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: pred.tags
                        .map(
                          (tag) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.deepPurple.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.purple.shade200,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  String _buildReason(Prediction pred, RaceEntry? entry) {
    final parts = <String>[];

    if (entry != null && entry.rating >= 60) {
      parts.add('선발등급의 높은 기량');
    } else if (entry != null && entry.rating > 0) {
      parts.add('안정적인 등급');
    }

    if (pred.winProbability >= 15) {
      parts.add('높은 승률 지표');
    }

    if (entry != null && entry.winCount >= 3) {
      parts.add('풍부한 우승 경험');
    }

    final tagHints = pred.tags.where(
      (t) =>
          t.contains('선행') ||
          t.contains('추입') ||
          t.contains('선두') ||
          t.contains('추월'),
    );
    if (tagHints.isNotEmpty) {
      parts.add('${tagHints.first} 전법');
    }

    if (parts.isEmpty) parts.add('종합 지표 우위');
    return parts.join(' · ');
  }

  String _buildDetailedReason(Prediction pred, RaceEntry? entry) {
    final lines = <String>[];

    if (entry != null) {
      if (entry.rating > 0) {
        lines.add(
          '레이팅 ${entry.rating.toStringAsFixed(0)}점으로 '
          '${entry.rating >= 60 ? "상위권" : "중위권"} 등급입니다.',
        );
      }
      if (entry.totalRaces > 0) {
        lines.add(
          '통산 ${entry.totalRaces}전 ${entry.winCount}승 ${entry.placeCount}복'
          '(승률 ${entry.winRate.toStringAsFixed(1)}%)의 전적을 보유하고 있습니다.',
        );
      }
      if (entry.jockeyName.isNotEmpty) {
        lines.add('기수 ${entry.jockeyName}과(와) 호흡을 맞춥니다.');
      }
    }

    if (pred.winProbability > 0) {
      lines.add(
        'AI 분석 결과 승률 ${pred.winProbability.toStringAsFixed(1)}%로 예측됩니다.',
      );
    }

    if (pred.tags.isNotEmpty) {
      lines.add('주요 특징: ${pred.tags.join(", ")}');
    }

    if (lines.isEmpty) {
      lines.add('종합 데이터 분석 기반으로 추천된 선수입니다.');
    }

    return lines.join(' ');
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
}

// ═══════════════════════════════════════════════════
// 예상 전개
// ═══════════════════════════════════════════════════

class _RacePacePreview extends StatelessWidget {
  final List<RaceEntry> entries;
  final List<Prediction> predictions;
  final List<Odds> odds;
  final int distance;

  const _RacePacePreview({
    required this.entries,
    required this.predictions,
    required this.odds,
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

  Map<int, int> _buildComprehensiveRankMap() {
    final recs = <(int horseNo, double totalScore, double ratingScore)>[];
    if (entries.isEmpty) return {};

    final ratings = entries.map((e) => e.rating).toList()
      ..sort((a, b) => b.compareTo(a));
    final maxRating = ratings.isNotEmpty ? ratings.first : 100.0;
    final avgRating = ratings.isNotEmpty
        ? ratings.reduce((a, b) => a + b) / ratings.length
        : 50.0;

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
      final pred = predictions
          .where((p) => p.horseNo == entry.horseNo)
          .firstOrNull;
      final style = runningStyles[entry.horseNo] ?? '중단';
      final winOdds = oddsMap[entry.horseNo] ?? 0;

      double ratingScore = 0;
      final ratingRank = ratings.indexOf(entry.rating) + 1;
      final ratingPercentile = entry.rating / maxRating;
      if (ratingRank <= 2 && entry.rating >= 80) {
        ratingScore = 25;
      } else if (ratingRank <= 3 && entry.rating >= 70) {
        ratingScore = 22;
      } else if (ratingPercentile >= 0.85) {
        ratingScore = 20;
      } else if (ratingPercentile >= 0.7) {
        ratingScore = 15;
      } else if (entry.rating >= avgRating) {
        ratingScore = 10;
      } else {
        ratingScore = 5;
      }

      double performanceScore = 0;
      final winRate = entry.winRate;
      final placeRate = entry.placeRate;
      final totalRaces = entry.totalRaces;
      if (winRate >= 30) {
        performanceScore += 15;
      } else if (winRate >= 20) {
        performanceScore += 12;
      } else if (winRate >= 10) {
        performanceScore += 8;
      } else if (winRate > 0) {
        performanceScore += 4;
      }
      if (placeRate >= 50) {
        performanceScore += 7;
      } else if (placeRate >= 35) {
        performanceScore += 5;
      } else if (placeRate >= 20) {
        performanceScore += 3;
      }
      if (totalRaces >= 20 && entry.winCount >= 3) {
        performanceScore += 3;
      } else if (totalRaces >= 10) {
        performanceScore += 2;
      } else if (totalRaces >= 5) {
        performanceScore += 1;
      }

      double jockeyScore = 0;
      if (pred != null && pred.winProbability > 0) {
        if (pred.winProbability >= 25) {
          jockeyScore += 12;
        } else if (pred.winProbability >= 15) {
          jockeyScore += 10;
        } else if (pred.winProbability >= 10) {
          jockeyScore += 7;
        } else if (pred.winProbability >= 5) {
          jockeyScore += 4;
        }
      }
      if (hasOdds && winOdds > 0) {
        if (winOdds <= 3.0) {
          jockeyScore += 8;
        } else if (winOdds <= 5.0) {
          jockeyScore += 6;
        } else if (winOdds <= avgOdds) {
          jockeyScore += 4;
        } else if (winOdds <= avgOdds * 2) {
          jockeyScore += 2;
        }
      } else if (pred != null) {
        jockeyScore += (pred.winProbability / 100 * 8).clamp(0, 8);
      }

      double distanceScore = 0;
      if (entry.winCount >= 2 && totalRaces >= 5) {
        distanceScore = 15;
      } else if (entry.winCount >= 1 && totalRaces >= 3) {
        distanceScore = 12;
      } else if (totalRaces >= 5 && placeRate >= 30) {
        distanceScore = 10;
      } else if (totalRaces >= 3) {
        distanceScore = 7;
      } else if (totalRaces >= 1) {
        distanceScore = 4;
      } else {
        distanceScore = 2;
      }

      double paceScore = 5;
      if (isFrontHeavy) {
        if (style == '추입' || style == '후입') {
          paceScore = 15;
        } else if (style == '중단') {
          paceScore = 10;
        } else {
          paceScore = 3;
        }
      } else if (isCloserFavored || frontRunners.length <= 1) {
        if (style == '선행' || style == '선입') {
          paceScore = 15;
        } else if (style == '중단') {
          paceScore = 8;
        }
      } else {
        paceScore = ratingRank <= 3 ? 10 : 7;
      }

      final totalScore =
          ratingScore +
          performanceScore +
          jockeyScore +
          distanceScore +
          paceScore;
      recs.add((entry.horseNo, totalScore, ratingScore));
    }

    recs.sort((a, b) {
      final scoreDiff = b.$2.compareTo(a.$2);
      if (scoreDiff != 0) return scoreDiff;
      return b.$3.compareTo(a.$3);
    });

    final rankMap = <int, int>{};
    for (int i = 0; i < recs.length; i++) {
      rankMap[recs[i].$1] = i + 1;
    }
    return rankMap;
  }

  @override
  Widget build(BuildContext context) {
    final sorted = List<RaceEntry>.from(entries)
      ..sort((a, b) => a.horseNo.compareTo(b.horseNo));

    final horsePaces = <int, _HorsePaceData>{};
    final comprehensiveRankMap = _buildComprehensiveRankMap();
    for (final entry in sorted) {
      final pred = predictions
          .where((p) => p.horseNo == entry.horseNo)
          .firstOrNull;
      final style = _getRunningStyle(entry, pred);
      final positions = List.generate(
        4,
        (i) => _estimatePosition(style, i, sorted.length),
      );
      final compRank = comprehensiveRankMap[entry.horseNo];
      if (compRank != null) {
        // 결승 구간 순위는 종합추천 순위와 동일하게 맞춥니다.
        positions[3] = compRank.clamp(1, sorted.length);
      }
      horsePaces[entry.horseNo] = _HorsePaceData(
        horseNo: entry.horseNo,
        horseName: entry.horseName,
        style: style,
        color: _styleColor(style),
        positions: positions,
      );
    }

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

          _PacePhaseSelector(horsePaces: horsePaces.values.toList()),
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

class _PacePhaseSelector extends StatefulWidget {
  const _PacePhaseSelector({required this.horsePaces});

  final List<_HorsePaceData> horsePaces;

  @override
  State<_PacePhaseSelector> createState() => _PacePhaseSelectorState();
}

class _PacePhaseSelectorState extends State<_PacePhaseSelector> {
  static const _phases = ['스타트', '1코너', '3코너', '결승'];
  int _selectedPhase = 3;

  @override
  Widget build(BuildContext context) {
    final phaseSorted = [...widget.horsePaces]
      ..sort((a, b) {
        final byPos = a.positions[_selectedPhase].compareTo(
          b.positions[_selectedPhase],
        );
        if (byPos != 0) return byPos;
        return a.horseNo.compareTo(b.horseNo);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: _phases.asMap().entries.map((entry) {
            final idx = entry.key;
            final selected = idx == _selectedPhase;
            return Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _selectedPhase = idx),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Column(
                    children: [
                      Text(
                        entry.value,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: selected
                              ? AppTheme.winColor
                              : Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 5),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: 3,
                        decoration: BoxDecoration(
                          color: selected
                              ? AppTheme.winColor
                              : Colors.grey.shade700,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: phaseSorted.take(8).map((horse) {
              final position = horse.positions[_selectedPhase];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: horse.color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: horse.color.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  '$position위 ${horse.horseNo}번',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: horse.color,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
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
  final String raceKey;
  final List<RaceEntry> entries;
  final List<Prediction> predictions;
  final List<Odds> odds;
  final int distance;

  const _ComprehensiveRecommendation({
    required this.raceKey,
    required this.entries,
    required this.predictions,
    required this.odds,
    required this.distance,
  });

  Future<void> _saveRecommendations(List<_HorseRecommendation> recs) async {
    final prefs = await SharedPreferences.getInstance();
    final top5 = recs.take(5).map((r) => r.horseNo.toString()).toList();
    await prefs.setStringList('comp_$raceKey', top5);
  }

  @override
  Widget build(BuildContext context) {
    final recommendations = _analyzeAndRecommend();
    if (recommendations.isEmpty) return const SizedBox.shrink();
    _saveRecommendations(recommendations);

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

class _PremiumSubscriptionPaywall extends ConsumerStatefulWidget {
  const _PremiumSubscriptionPaywall({required this.iapState});

  final InAppPurchaseState iapState;

  @override
  ConsumerState<_PremiumSubscriptionPaywall> createState() =>
      _PremiumSubscriptionPaywallState();
}

class _PremiumSubscribeInlineCta extends StatelessWidget {
  const _PremiumSubscribeInlineCta();

  @override
  Widget build(BuildContext context) {
    void moveToSubscription() {
      final returnTo = Uri.encodeComponent(
        GoRouterState.of(context).uri.toString(),
      );
      context.push('/subscription?plan=premium_monthly&returnTo=$returnTo');
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF171B24),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.workspace_premium_rounded,
                color: AppTheme.accentGold,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '프리미엄 구독으로 종합추천/AI추천 보기',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade200,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Center(
            child: FilledButton(
              onPressed: moveToSubscription,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2E5B8A),
                foregroundColor: Colors.white,
                minimumSize: const Size(220, 38),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text(
                '구독하기',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '결제는 구글플레이에서 진행되며 신용카드, 휴대폰 결제, 계좌이체(지원 시) 중 선택할 수 있습니다.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade400, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _PremiumSubscriptionPaywallState
    extends ConsumerState<_PremiumSubscriptionPaywall> {
  String _selectedProductId = 'premium_monthly';

  @override
  Widget build(BuildContext context) {
    final productMap = {for (final p in widget.iapState.products) p.id: p};
    final isMonthly = _selectedProductId == 'premium_monthly';

    String formatPriceSpacing(String raw) {
      return raw.replaceAllMapped(
        RegExp(r'[￦₩]\s*'),
        (match) => '${match.group(0)![0]} ',
      );
    }

    String monthlyText() {
      final monthly = productMap['premium_monthly'];
      if (monthly != null) return '월간 ${formatPriceSpacing(monthly.price)}';
      return '월간 ￦ 9,900원';
    }

    String yearlyText() {
      final yearly = productMap['premium_yearly'];
      if (yearly != null) {
        return '연간 ${formatPriceSpacing(yearly.price)} (17% 절약)';
      }
      return '연간 ￦ 99,000원 (17% 절약)';
    }

    final card = Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.17)),
        gradient: const LinearGradient(
          colors: [Color(0xFF141D29), Color(0xFF0F1722)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          const Icon(Icons.lock_rounded, color: Colors.amber, size: 32),
          const SizedBox(height: 12),
          const Text(
            'AI 추천, 종합추천은\n구독 후 이용할 수 있습니다.',
            textAlign: TextAlign.left,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, height: 1.35),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              color: Colors.white.withValues(alpha: 0.02),
            ),
            child: Column(
              children: [
                _PlanOptionTile(
                  selected: isMonthly,
                  label: monthlyText(),
                  onTap: () => setState(() => _selectedProductId = 'premium_monthly'),
                ),
                const SizedBox(height: 10),
                _PlanOptionTile(
                  selected: !isMonthly,
                  label: yearlyText(),
                  onTap: () => setState(() => _selectedProductId = 'premium_yearly'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 220,
            child: FilledButton.icon(
              onPressed: () {
                final returnTo = Uri.encodeComponent(
                  GoRouterState.of(context).uri.toString(),
                );
                context.push(
                  '/subscription?plan=$_selectedProductId&returnTo=$returnTo',
                );
              },
              icon: const Icon(Icons.verified_rounded, size: 18),
              label: const Text(
                '구독하기',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2E5B8A),
                foregroundColor: Colors.white,
                minimumSize: const Size(220, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
      children: [card],
    );
  }
}

class _PlanOptionTile extends StatelessWidget {
  const _PlanOptionTile({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          color: selected ? const Color(0x33FFB300) : const Color(0x12000000),
          border: Border.all(
            color: selected
                ? const Color(0xCCFFB300)
                : Colors.white.withValues(alpha: 0.2),
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.amber : Colors.white,
            ),
          ),
        ),
      ),
    );
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

class _NumberRecommender extends StatefulWidget {
  final String raceKey;
  final List<RaceEntry> entries;
  final List<Prediction> predictions;
  final double horizontalMargin;

  const _NumberRecommender({
    super.key,
    required this.raceKey,
    required this.entries,
    required this.predictions,
    this.horizontalMargin = 14,
  });

  @override
  State<_NumberRecommender> createState() => _NumberRecommenderState();
}

class _NumberRecommenderState extends State<_NumberRecommender> {
  static const _slotCount = 5;
  static const _slotLabels = ['1착', '2착', '3착', '4착', '5착'];
  static const _slotColors = [
    Color(0xFFFFD700),
    Color(0xFF6C5CE7),
    Color(0xFF00C853),
    Color(0xFF00B0FF),
    Color(0xFFFF6D00),
  ];

  List<int?> _slots = List.filled(_slotCount, null);
  bool _loaded = false;
  int? _activeSlot;

  String get _storageKey => 'picks_${widget.raceKey}';

  Set<int> get _selectedSet => _slots.whereType<int>().toSet();

  @override
  void initState() {
    super.initState();
    _loadPicks();
  }

  @override
  void didUpdateWidget(covariant _NumberRecommender old) {
    super.didUpdateWidget(old);
    if (old.raceKey != widget.raceKey) _loadPicks();
  }

  Future<void> _loadPicks() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_storageKey);
    if (saved != null && mounted) {
      final loaded = List<int?>.filled(_slotCount, null);
      for (var i = 0; i < saved.length && i < _slotCount; i++) {
        loaded[i] = int.tryParse(saved[i]);
      }
      setState(() {
        _slots = loaded;
        _loaded = true;
      });
    } else if (mounted) {
      setState(() => _loaded = true);
    }
  }

  Future<void> _savePicks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _storageKey,
      _slots.map((n) => n?.toString() ?? '').toList(),
    );
  }

  void _onTapSlot(int slotIdx) {
    setState(() {
      if (_activeSlot == slotIdx) {
        _activeSlot = null;
      } else {
        _activeSlot = slotIdx;
      }
    });
  }

  void _onPickNumber(int no) {
    if (_activeSlot == null) return;
    setState(() {
      final prevIdx = _slots.indexOf(no);
      if (prevIdx >= 0) _slots[prevIdx] = null;
      _slots[_activeSlot!] = no;
      _activeSlot = null;
    });
    _savePicks();
  }

  void _onClearSlot(int slotIdx) {
    setState(() {
      _slots[slotIdx] = null;
      if (_activeSlot == slotIdx) _activeSlot = null;
    });
    _savePicks();
  }

  void _onClearAll() {
    setState(() {
      _slots = List.filled(_slotCount, null);
      _activeSlot = null;
    });
    _savePicks();
  }

  String _horseName(int horseNo) {
    final pred = widget.predictions
        .where((p) => p.horseNo == horseNo)
        .firstOrNull;
    if (pred != null && pred.horseName.isNotEmpty) return pred.horseName;
    return widget.entries
            .where((e) => e.horseNo == horseNo)
            .firstOrNull
            ?.horseName ??
        '';
  }

  double? _winProb(int horseNo) {
    return widget.predictions
        .where((p) => p.horseNo == horseNo)
        .firstOrNull
        ?.winProbability;
  }

  @override
  Widget build(BuildContext context) {
    final allNos = widget.entries.map((e) => e.horseNo).toList()..sort();
    if (allNos.isEmpty || !_loaded) return const SizedBox.shrink();
    final hasAny = _selectedSet.isNotEmpty;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: widget.horizontalMargin),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1C1240), Color(0xFF0F1B30)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF6C5CE7).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Row(
            children: [
              const Icon(
                Icons.casino_rounded,
                color: Color(0xFFFFD700),
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '나의 선택',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              if (hasAny)
                GestureDetector(
                  onTap: _onClearAll,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      '초기화',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _activeSlot != null
                ? '${_slotLabels[_activeSlot!]}에 넣을 번호를 선택하세요'
                : '착순을 탭하여 번호를 등록하세요',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 14),

          // 1착~5착 슬롯
          Row(
            children: List.generate(_slotCount, (i) {
              final no = _slots[i];
              final color = _slotColors[i];
              final filled = no != null;
              final isActive = _activeSlot == i;

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i > 0 ? 6 : 0),
                  child: GestureDetector(
                    onTap: () => _onTapSlot(i),
                    onLongPress: filled ? () => _onClearSlot(i) : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 64,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: isActive
                            ? color.withValues(alpha: 0.25)
                            : filled
                            ? color.withValues(alpha: 0.15)
                            : Colors.white.withValues(alpha: 0.04),
                        border: Border.all(
                          color: isActive
                              ? color
                              : filled
                              ? color.withValues(alpha: 0.6)
                              : Colors.white.withValues(alpha: 0.1),
                          width: isActive
                              ? 2
                              : filled
                              ? 1.5
                              : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _slotLabels[i],
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: isActive || filled
                                  ? color
                                  : Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (filled)
                            Text(
                              '$no',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: color,
                              ),
                            )
                          else
                            Icon(
                              isActive
                                  ? Icons.touch_app_rounded
                                  : Icons.add_rounded,
                              size: 18,
                              color: isActive ? color : Colors.grey.shade700,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),

          // 번호 스크롤 (슬롯 선택 시 표시)
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: _activeSlot != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 80,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: allNos.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final no = allNos[index];
                            final alreadyUsed = _selectedSet.contains(no);
                            final prob = _winProb(no);
                            final name = _horseName(no);
                            final activeColor = _slotColors[_activeSlot!];

                            return GestureDetector(
                              onTap: () => _onPickNumber(no),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 62,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  color: alreadyUsed
                                      ? Colors.white.withValues(alpha: 0.03)
                                      : activeColor.withValues(alpha: 0.08),
                                  border: Border.all(
                                    color: alreadyUsed
                                        ? Colors.white.withValues(alpha: 0.06)
                                        : activeColor.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '$no',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                        color: alreadyUsed
                                            ? Colors.grey.shade700
                                            : Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      name.length > 4
                                          ? '${name.substring(0, 4)}..'
                                          : name,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: alreadyUsed
                                            ? Colors.grey.shade700
                                            : Colors.grey.shade400,
                                      ),
                                    ),
                                    if (prob != null)
                                      Text(
                                        '${prob.toStringAsFixed(1)}%',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w600,
                                          color: alreadyUsed
                                              ? Colors.grey.shade800
                                              : activeColor.withValues(
                                                  alpha: 0.8,
                                                ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),

          if (hasAny) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                '착순 탭: 번호 변경 · 길게 누르기: 해제',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
