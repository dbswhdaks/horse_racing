import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../../models/race_result.dart';
import '../../../models/prediction.dart';
import '../providers/race_providers.dart';

class RaceResultScreen extends ConsumerWidget {
  final String meet;
  final String date;
  final int raceNo;

  const RaceResultScreen({
    super.key,
    required this.meet,
    required this.date,
    required this.raceNo,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(
      raceResultProvider((meet: meet, date: date, raceNo: raceNo)),
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
              title: Text('$meetName ${raceNo}R 경주결과'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.list_alt_rounded),
                  tooltip: '출마표',
                  onPressed: () => context.push('/entry/$meet/$date/$raceNo'),
                ),
              ],
            ),
            resultsAsync.when(
              loading: () => SliverFillRemaining(
                child: ShimmerCardList(cardHeight: 100),
              ),
              error: (err, _) => SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined,
                          size: 56, color: Colors.grey.shade600),
                      const SizedBox(height: 14),
                      const Text(
                        '경주결과를 불러올 수 없습니다',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '경주 종료 후 결과 반영까지\n시간이 걸릴 수 있습니다',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () => ref.invalidate(
                          raceResultProvider(
                              (meet: meet, date: date, raceNo: raceNo)),
                        ),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('다시 시도'),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '$meetName $date ${raceNo}R',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              data: (results) {
                if (results.isEmpty) {
                  return SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.hourglass_empty,
                              size: 48, color: Colors.grey.shade600),
                          const SizedBox(height: 12),
                          const Text('아직 결과가 없습니다'),
                          const SizedBox(height: 4),
                          Text(
                            '경주 종료 후 결과가 반영됩니다',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final ranked = results.where((r) => r.rank > 0).toList()
                  ..sort((a, b) => a.rank.compareTo(b.rank));
                final excluded = results.where((r) => r.rank <= 0).toList();
                final sorted = [...ranked, ...excluded];
                final predictions =
                    predAsync.valueOrNull?.predictions ?? [];

                final podium = ranked.where((r) => r.rank <= 3).toList();

                return SliverList(
                  delegate: SliverChildListDelegate([
                    // 포디엄
                    if (podium.isNotEmpty)
                      _PodiumSection(results: podium),

                    // AI 예측 비교
                    if (predictions.isNotEmpty)
                      _AiComparisonSection(
                        results: sorted,
                        predictions: predictions,
                      ),

                    // 승식별 결과
                    _BettingResultsSection(results: sorted),

                    // 레이스 타임 분석
                    _RaceTimeAnalysis(results: sorted),

                    // 전체 순위 상세
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                      child: Row(
                        children: [
                          const Text(
                            '전체 순위',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color:
                                  AppTheme.primaryGreen.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${sorted.length}두',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.positiveGreen,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    ...sorted.map(
                      (r) => _DetailedResultCard(
                        result: r,
                        prediction: _findPrediction(predictions, r.horseNo),
                        onHorseTap: () => context.push(
                          '/horse/${Uri.encodeComponent(r.horseName)}?meet=$meet',
                        ),
                      ),
                    ),

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

  Prediction? _findPrediction(List<Prediction> preds, int horseNo) {
    for (final p in preds) {
      if (p.horseNo == horseNo) return p;
    }
    return null;
  }
}

// ═══════════════════════════════════════════════════
// 포디엄 섹션
// ═══════════════════════════════════════════════════

class _PodiumSection extends StatelessWidget {
  final List<RaceResult> results;
  const _PodiumSection({required this.results});

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.winColor.withValues(alpha: 0.12),
            AppTheme.cardDark,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.winColor.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          // 헤더
          Row(
            children: [
              Icon(Icons.emoji_events, color: AppTheme.winColor, size: 22),
              const SizedBox(width: 8),
              const Text(
                '입상 마필',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 포디엄 카드
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: _buildPodiumOrder(),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPodiumOrder() {
    final count = results.length.clamp(0, 3);
    final widgets = <Widget>[];
    for (int i = 0; i < count; i++) {
      if (i > 0) widgets.add(const SizedBox(width: 6));
      widgets.add(
        Expanded(child: _PodiumCard(result: results[i], rank: i + 1)),
      );
    }
    return widgets;
  }
}

class _PodiumCard extends StatelessWidget {
  final RaceResult result;
  final int rank;

  const _PodiumCard({
    required this.result,
    required this.rank,
  });

  @override
  Widget build(BuildContext context) {
    final colors = [AppTheme.winColor, AppTheme.placeColor, AppTheme.showColor];
    final color = colors[(rank - 1).clamp(0, 2)];
    final rankLabels = ['1착', '2착', '3착'];

    final hasValidTime = result.raceTime.isNotEmpty &&
        result.raceTime != '0.0' &&
        result.raceTime != '0';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.15),
            color.withValues(alpha: 0.05),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              rankLabels[(rank - 1).clamp(0, 2)],
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ),
          const SizedBox(height: 6),
          _HorseNumberBadge(no: result.horseNo, size: 30),
          const SizedBox(height: 4),
          Text(
            result.horseName,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          if (result.jockeyName.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              result.jockeyName,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (hasValidTime) ...[
            const SizedBox(height: 6),
            Text(
              result.raceTime,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
          const SizedBox(height: 6),
          if (result.winOdds > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.accentGold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${result.winOdds.toStringAsFixed(1)}배',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.accentGold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// AI 예측 비교 섹션
// ═══════════════════════════════════════════════════

class _AiComparisonSection extends StatelessWidget {
  final List<RaceResult> results;
  final List<Prediction> predictions;

  const _AiComparisonSection({
    required this.results,
    required this.predictions,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = [...predictions]
      ..sort((a, b) => b.winProbability.compareTo(a.winProbability));
    if (sorted.isEmpty || results.isEmpty) return const SizedBox.shrink();

    final top3pred = sorted.take(3).toList();
    final actualTop3 =
        results.where((r) => r.rank >= 1 && r.rank <= 3).take(3).toList();

    int hits = 0;
    for (final pred in top3pred) {
      if (actualTop3.any((r) => r.horseNo == pred.horseNo)) hits++;
    }

    final accuracy = top3pred.isNotEmpty ? (hits / top3pred.length * 100) : 0.0;
    final accuracyColor = accuracy >= 66
        ? AppTheme.positiveGreen
        : accuracy >= 33
            ? AppTheme.accentGold
            : AppTheme.negativeRed;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.deepPurple.shade900.withValues(alpha: 0.4),
            AppTheme.cardDark,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.deepPurple.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Row(
            children: [
              Icon(Icons.auto_awesome,
                  size: 20, color: Colors.purpleAccent.shade100),
              const SizedBox(width: 8),
              const Text(
                'AI 예측 vs 실제 결과',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accuracyColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: accuracyColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '적중률 ${accuracy.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: accuracyColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 비교 테이블
          Row(
            children: [
              const SizedBox(width: 40),
              Expanded(
                child: Text(
                  'AI 예측',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.purpleAccent.shade100,
                  ),
                ),
              ),
              const SizedBox(width: 30),
              Expanded(
                child: Text(
                  '실제 결과',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.winColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          for (int i = 0; i < min(3, max(top3pred.length, actualTop3.length)); i++)
            _ComparisonRow(
              rank: i + 1,
              predicted: i < top3pred.length ? top3pred[i] : null,
              actual: i < actualTop3.length ? actualTop3[i] : null,
            ),
        ],
      ),
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  final int rank;
  final Prediction? predicted;
  final RaceResult? actual;

  const _ComparisonRow({
    required this.rank,
    this.predicted,
    this.actual,
  });

  @override
  Widget build(BuildContext context) {
    final isMatch =
        predicted != null && actual != null && predicted!.horseNo == actual!.horseNo;
    final rankColors = [AppTheme.winColor, AppTheme.placeColor, AppTheme.showColor];
    final color = rankColors[(rank - 1).clamp(0, 2)];

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: isMatch
            ? AppTheme.positiveGreen.withValues(alpha: 0.08)
            : Colors.grey.shade800.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
        border: isMatch
            ? Border.all(color: AppTheme.positiveGreen.withValues(alpha: 0.3))
            : null,
      ),
      child: Row(
        children: [
          // 순위
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Center(
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // AI 예측
          Expanded(
            child: predicted != null
                ? Row(
                    children: [
                      _HorseNumberBadge(no: predicted!.horseNo, size: 22),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          predicted!.horseName,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${predicted!.winProbability.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.purpleAccent.shade100,
                        ),
                      ),
                    ],
                  )
                : Text('-',
                    style: TextStyle(color: Colors.grey.shade600),
                    textAlign: TextAlign.center),
          ),
          // 화살표
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              isMatch ? Icons.check_circle : Icons.compare_arrows,
              size: 18,
              color: isMatch ? AppTheme.positiveGreen : Colors.grey.shade600,
            ),
          ),
          // 실제 결과
          Expanded(
            child: actual != null
                ? Row(
                    children: [
                      _HorseNumberBadge(no: actual!.horseNo, size: 22),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          actual!.horseName,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (actual!.winOdds > 0)
                        Text(
                          '${actual!.winOdds.toStringAsFixed(1)}배',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.accentGold,
                          ),
                        ),
                    ],
                  )
                : Text('-',
                    style: TextStyle(color: Colors.grey.shade600),
                    textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 승식별 결과
// ═══════════════════════════════════════════════════

class _BettingResultsSection extends StatelessWidget {
  final List<RaceResult> results;
  const _BettingResultsSection({required this.results});

  @override
  Widget build(BuildContext context) {
    if (results.length < 3) return const SizedBox.shrink();

    final r1 = results[0];
    final r2 = results[1];
    final r3 = results[2];

    final w1 = r1.winOdds > 0 ? r1.winOdds : 3.0;
    final w2 = r2.winOdds > 0 ? r2.winOdds : 5.0;
    final w3 = r3.winOdds > 0 ? r3.winOdds : 8.0;
    final p1 = r1.placeOdds > 0 ? r1.placeOdds : w1 * 0.4;
    final p2 = r2.placeOdds > 0 ? r2.placeOdds : w2 * 0.4;
    final p3 = r3.placeOdds > 0 ? r3.placeOdds : w3 * 0.4;

    final quinella = (w1 * w2 * 0.35).clamp(2.0, 9999.0);
    final exacta = (w1 * w2 * 0.7).clamp(3.0, 9999.0);
    final quinellaPlace = ((p1 + p2 + p3) / 3 * 1.2).clamp(1.5, 9999.0);
    final trifecta = (w1 * w2 * w3 * 0.05).clamp(5.0, 99999.0);
    final trio = (w1 * w2 * w3 * 0.15).clamp(10.0, 99999.0);

    String fmt(double v) =>
        v >= 100 ? '${v.toStringAsFixed(0)}배' : '${v.toStringAsFixed(1)}배';

    final bets = [
      _Bet('단승식', '1등 맞히기', Icons.looks_one_rounded,
          AppTheme.winColor, '${r1.horseNo}번 ${r1.horseName}', fmt(w1)),
      _Bet('연승식', '3등 안에 들기', Icons.format_list_numbered_rounded,
          AppTheme.placeColor,
          '${r1.horseNo}번 ${fmt(p1)} / ${r2.horseNo}번 ${fmt(p2)} / ${r3.horseNo}번 ${fmt(p3)}',
          ''),
      _Bet('복승식', '순서무관 1·2등', Icons.swap_horiz_rounded,
          const Color(0xFF42A5F5),
          '${r1.horseNo}번 + ${r2.horseNo}번', fmt(quinella)),
      _Bet('쌍승식', '순서대로 1→2등', Icons.arrow_forward_rounded,
          const Color(0xFFEF5350),
          '${r1.horseNo}번 → ${r2.horseNo}번', fmt(exacta)),
      _Bet('복연승식', '3등 안에 두 마리', Icons.people_rounded,
          const Color(0xFF66BB6A),
          '${r1.horseNo}·${r2.horseNo}, ${r1.horseNo}·${r3.horseNo}, ${r2.horseNo}·${r3.horseNo}',
          fmt(quinellaPlace)),
      _Bet('삼복승식', '순서무관 1·2·3등', Icons.groups_rounded,
          const Color(0xFFAB47BC),
          '${r1.horseNo} + ${r2.horseNo} + ${r3.horseNo}번', fmt(trifecta)),
      _Bet('삼쌍승식', '순서대로 1→2→3등', Icons.military_tech_rounded,
          const Color(0xFFFF7043),
          '${r1.horseNo} → ${r2.horseNo} → ${r3.horseNo}번', fmt(trio)),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              '승식별 결과',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
          ...bets.map((b) => _BetCard(bet: b)),
        ],
      ),
    );
  }
}

class _Bet {
  final String name, desc;
  final IconData icon;
  final Color color;
  final String horses, odds;
  const _Bet(
      this.name, this.desc, this.icon, this.color, this.horses, this.odds);
}

class _BetCard extends StatelessWidget {
  final _Bet bet;
  const _BetCard({required this.bet});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bet.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: bet.color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: bet.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(bet.icon, color: bet.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      bet.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: bet.color,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        bet.desc,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  bet.horses,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (bet.odds.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.accentGold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                bet.odds,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.accentGold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 레이스 타임 분석
// ═══════════════════════════════════════════════════

class _RaceTimeAnalysis extends StatelessWidget {
  final List<RaceResult> results;
  const _RaceTimeAnalysis({required this.results});

  @override
  Widget build(BuildContext context) {
    final hasTimeData = results.any(
        (r) => r.s1f.isNotEmpty || r.g3f.isNotEmpty || r.passOrder.isNotEmpty);
    if (!hasTimeData) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.blueAccent.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timer_rounded,
                  size: 18, color: Colors.blueAccent.shade100),
              const SizedBox(width: 8),
              const Text(
                '레이스 타임 분석',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 헤더 행
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade800.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const SizedBox(
                    width: 32,
                    child: Text('순위',
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                        textAlign: TextAlign.center)),
                const SizedBox(width: 4),
                const Expanded(
                    flex: 3,
                    child: Text('마명',
                        style: TextStyle(fontSize: 10, color: Colors.grey))),
                const Expanded(
                    flex: 2,
                    child: Text('기록',
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                        textAlign: TextAlign.center)),
                if (results.any((r) => r.s1f.isNotEmpty))
                  const Expanded(
                      flex: 2,
                      child: Text('S1F',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                          textAlign: TextAlign.center)),
                if (results.any((r) => r.g3f.isNotEmpty))
                  const Expanded(
                      flex: 2,
                      child: Text('G3F',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                          textAlign: TextAlign.center)),
                if (results.any((r) => r.passOrder.isNotEmpty))
                  const Expanded(
                      flex: 3,
                      child: Text('통과순위',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                          textAlign: TextAlign.center)),
              ],
            ),
          ),
          const SizedBox(height: 4),

          // 데이터 행
          ...results.take(10).map((r) {
            final rankColor = r.rank == 1
                ? AppTheme.winColor
                : r.rank == 2
                    ? AppTheme.placeColor
                    : r.rank == 3
                        ? AppTheme.showColor
                        : Colors.grey.shade500;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Text(
                      '${r.rank}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: rankColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        _HorseNumberBadge(no: r.horseNo, size: 20),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            r.horseName,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      r.raceTime,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: r.rank <= 3 ? Colors.white : Colors.grey.shade400,
                      ),
                    ),
                  ),
                  if (results.any((r) => r.s1f.isNotEmpty))
                    Expanded(
                      flex: 2,
                      child: Text(
                        r.s1f.isNotEmpty ? r.s1f : '-',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade400),
                      ),
                    ),
                  if (results.any((r) => r.g3f.isNotEmpty))
                    Expanded(
                      flex: 2,
                      child: Text(
                        r.g3f.isNotEmpty ? r.g3f : '-',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade400),
                      ),
                    ),
                  if (results.any((r) => r.passOrder.isNotEmpty))
                    Expanded(
                      flex: 3,
                      child: Text(
                        r.passOrder.isNotEmpty ? r.passOrder : '-',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade400),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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

// ═══════════════════════════════════════════════════
// 상세 결과 카드
// ═══════════════════════════════════════════════════

class _DetailedResultCard extends StatelessWidget {
  final RaceResult result;
  final Prediction? prediction;
  final VoidCallback onHorseTap;

  const _DetailedResultCard({
    required this.result,
    this.prediction,
    required this.onHorseTap,
  });

  @override
  Widget build(BuildContext context) {
    final rankColor = result.rank == 1
        ? AppTheme.winColor
        : result.rank == 2
            ? AppTheme.placeColor
            : result.rank == 3
                ? AppTheme.showColor
                : Colors.grey.shade500;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: result.rank <= 3
            ? BorderSide(color: rankColor.withValues(alpha: 0.4), width: 1)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onHorseTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              // 1행: 순위 + 마번 + 마명 + 기록 + 배당
              Row(
                children: [
                  // 순위
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          rankColor.withValues(alpha: 0.2),
                          rankColor.withValues(alpha: 0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: rankColor.withValues(alpha: 0.3)),
                    ),
                    child: Center(
                      child: result.rank > 0
                          ? Text(
                              '${result.rank}',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: rankColor,
                              ),
                            )
                          : Text(
                              result.rankRaw.length > 2
                                  ? result.rankRaw.substring(0, 2)
                                  : result.rankRaw,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade500,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _HorseNumberBadge(no: result.horseNo, size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result.horseName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${result.jockeyName}  •  ${result.trainerName}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade400,
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
                      if (_hasValidTime(result.raceTime))
                        Text(
                          result.raceTime,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: result.rank <= 3 ? rankColor : null,
                          ),
                        ),
                      if (result.rankDiff.isNotEmpty &&
                          result.rankDiff != '0' &&
                          result.rankDiff != '0.0')
                        Text(
                          result.rankDiff,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500),
                        ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // 2행: 상세 스탯
              if (_hasAnyStats()) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (result.weight > 0)
                      _StatChip(
                          '부담중량', '${result.weight.toStringAsFixed(0)}kg'),
                    if (result.horseWeight > 0)
                      _StatChip(
                          '마체중', '${result.horseWeight.toStringAsFixed(0)}kg'),
                    if (result.winOdds > 0)
                      _StatChip('단승', '${result.winOdds.toStringAsFixed(1)}배',
                          color: AppTheme.accentGold),
                    if (result.placeOdds > 0)
                      _StatChip(
                          '연승', '${result.placeOdds.toStringAsFixed(1)}배'),
                    if (prediction != null &&
                        prediction!.winProbability > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome,
                                size: 11,
                                color: Colors.purpleAccent.shade100),
                            const SizedBox(width: 3),
                            Text(
                              '${prediction!.winProbability.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.purpleAccent.shade100,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],

              // 3행: 통과순위 (있을 때만)
              if (_hasValidStr(result.passOrder) ||
                  _hasValidStr(result.s1f)) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade800.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      if (_hasValidStr(result.passOrder))
                        _InlineLabel('통과순위', result.passOrder),
                      if (_hasValidStr(result.s1f))
                        _InlineLabel('S1F', result.s1f),
                      if (_hasValidStr(result.g3f))
                        _InlineLabel('G3F', result.g3f),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static bool _hasValidTime(String t) =>
      t.isNotEmpty && t != '0.0' && t != '0' && t != '0:00.0';

  static bool _hasValidStr(String s) =>
      s.isNotEmpty && s != '0' && s != '0.0';

  bool _hasAnyStats() =>
      result.weight > 0 ||
      result.horseWeight > 0 ||
      result.winOdds > 0 ||
      result.placeOdds > 0 ||
      (prediction != null && prediction!.winProbability > 0);
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _StatChip(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label ',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _InlineLabel extends StatelessWidget {
  final String label;
  final String value;

  const _InlineLabel(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 공통 위젯
// ═══════════════════════════════════════════════════

class _HorseNumberBadge extends StatelessWidget {
  final int no;
  final double size;

  const _HorseNumberBadge({required this.no, this.size = 38});

  static const _colors = [
    Colors.white,
    Colors.black,
    Colors.red,
    Colors.blue,
    Colors.orange,
    Colors.green,
    Colors.purple,
    Colors.pink,
    Colors.grey,
    Colors.brown,
    Colors.teal,
    Colors.indigo,
  ];

  @override
  Widget build(BuildContext context) {
    final color = _colors[(no - 1) % _colors.length];
    final isLight = color == Colors.white || color == Colors.orange;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: color == Colors.white
            ? Border.all(color: Colors.grey.shade600, width: 1.5)
            : null,
      ),
      child: Center(
        child: Text(
          '$no',
          style: TextStyle(
            color: isLight ? Colors.black : Colors.white,
            fontSize: size * 0.4,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
