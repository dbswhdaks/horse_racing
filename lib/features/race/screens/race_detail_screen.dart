import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../../models/odds.dart';
import '../providers/race_providers.dart';
import '../widgets/entry_card.dart';
import '../widgets/odds_panel.dart';
import '../widgets/prediction_summary.dart';

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

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              title: Text('$meetName ${raceNo}R'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.bar_chart),
                  tooltip: 'AI 예측',
                  onPressed: () =>
                      context.push('/prediction/$meet/$date/$raceNo'),
                ),
              ],
            ),

            // AI Prediction Summary
            SliverToBoxAdapter(
              child: predAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: ShimmerLoading(height: 80),
                ),
                error: (_, __) => const SizedBox.shrink(),
                data: (report) {
                  if (report == null) return const _MlOfflineBanner();
                  return PredictionSummary(report: report);
                },
              ),
            ),

            // Odds Panel
            SliverToBoxAdapter(
              child: oddsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ShimmerLoading(height: 60),
                ),
                error: (_, __) => const SizedBox.shrink(),
                data: (odds) => OddsPanel(odds: odds, raceNo: raceNo),
              ),
            ),

            // 출마표 헤더 + 결과 버튼
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '출마표',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 34,
                      child: FilledButton.icon(
                        onPressed: () =>
                            context.push('/result/$meet/$date/$raceNo'),
                        icon: const Icon(Icons.emoji_events, size: 16),
                        label: const Text(
                          '경주결과',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.accentGold,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Entry List
            entriesAsync.when(
              loading: () => SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: ShimmerLoading(height: 120),
                  ),
                  childCount: 8,
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
                      const Text('출마표를 불러올 수 없습니다'),
                    ],
                  ),
                ),
              ),
              data: (entries) => SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final entry = entries[i];
                    final winOdds = _findWinOdds(
                      oddsAsync.valueOrNull ?? [],
                      entry.horseNo,
                    );
                    return EntryCard(
                      entry: entry,
                      winOdds: winOdds,
                      onTap: () => context.push(
                        '/horse/${Uri.encodeComponent(entry.horseName)}?meet=$meet',
                      ),
                    );
                  },
                  childCount: entries.length,
                ),
              ),
            ),

            const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
          ],
        ),
      ),
    );
  }

  double _findWinOdds(List<Odds> odds, int horseNo) {
    for (final o in odds) {
      if ((o.betType == 'WIN' || o.betType == '1') && o.horseNo1 == horseNo) {
        return o.rate;
      }
    }
    return 0;
  }
}

// ── ML 오프라인 배너 ──

class _MlOfflineBanner extends StatelessWidget {
  const _MlOfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade900.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.deepPurple.shade700.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, color: Colors.purpleAccent.shade100, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '출전표 API 활용 신청 후 AI 예측이 표시됩니다',
              style: TextStyle(
                fontSize: 13,
                color: Colors.purple.shade200,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
