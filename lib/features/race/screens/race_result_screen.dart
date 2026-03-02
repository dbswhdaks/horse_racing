import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../../models/race_result.dart';
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
    final meetName = ApiConstants.meetNames[meet] ?? meet;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              title: Text('$meetName ${raceNo}R 결과'),
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
                      Icon(Icons.error_outline,
                          size: 48, color: Colors.grey.shade600),
                      const SizedBox(height: 12),
                      const Text('결과를 불러올 수 없습니다'),
                      const SizedBox(height: 8),
                      Text(
                        '아직 진행되지 않은 경주일 수 있습니다',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              data: (results) {
                if (results.isEmpty) {
                  return const SliverFillRemaining(
                    child: Center(child: Text('결과 데이터가 없습니다')),
                  );
                }

                final sorted = [...results]
                  ..sort((a, b) => a.rank.compareTo(b.rank));

                return SliverList(
                  delegate: SliverChildListDelegate([
                    _TopThreeCard(results: sorted.take(3).toList()),
                    _BettingResultsPanel(results: sorted),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Text(
                        '전체 순위',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    ...sorted.map(
                      (r) => _ResultCard(
                        result: r,
                        onHorseTap: () => context.push(
                          '/horse/${Uri.encodeComponent(r.horseName)}?meet=$meet',
                        ),
                      ),
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

// ── 승식별 결과 패널 ──

class _BettingResultsPanel extends StatelessWidget {
  final List<RaceResult> results;
  const _BettingResultsPanel({required this.results});

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

    String fmt(double v) => v >= 100 ? '${v.toStringAsFixed(0)}배' : '${v.toStringAsFixed(1)}배';

    final bettingTypes = [
      _BettingType(
        name: '단승식',
        desc: '1등 찾기',
        icon: Icons.looks_one,
        color: AppTheme.winColor,
        horses: '${r1.horseNo}번 ${r1.horseName}',
        odds: fmt(w1),
      ),
      _BettingType(
        name: '연승식',
        desc: '3등 안에 들기',
        icon: Icons.format_list_numbered,
        color: AppTheme.placeColor,
        horses: '${r1.horseNo}번 ${fmt(p1)} / ${r2.horseNo}번 ${fmt(p2)} / ${r3.horseNo}번 ${fmt(p3)}',
        odds: '',
      ),
      _BettingType(
        name: '복승식',
        desc: '순서 상관없이 1,2등',
        icon: Icons.swap_horiz,
        color: const Color(0xFF42A5F5),
        horses: '${r1.horseNo}번 + ${r2.horseNo}번',
        odds: fmt(quinella),
      ),
      _BettingType(
        name: '쌍승식',
        desc: '순서대로 1,2등',
        icon: Icons.arrow_forward,
        color: const Color(0xFFEF5350),
        horses: '${r1.horseNo}번 → ${r2.horseNo}번',
        odds: fmt(exacta),
      ),
      _BettingType(
        name: '복연승식',
        desc: '3등 안에 두 마리',
        icon: Icons.people,
        color: const Color(0xFF66BB6A),
        horses: '${r1.horseNo}·${r2.horseNo}, ${r1.horseNo}·${r3.horseNo}, ${r2.horseNo}·${r3.horseNo}',
        odds: fmt(quinellaPlace),
      ),
      _BettingType(
        name: '삼복승식',
        desc: '3등 안에 세 마리',
        icon: Icons.groups,
        color: const Color(0xFFAB47BC),
        horses: '${r1.horseNo}번 + ${r2.horseNo}번 + ${r3.horseNo}번',
        odds: fmt(trifecta),
      ),
      _BettingType(
        name: '삼쌍승식',
        desc: '순서대로 1,2,3등',
        icon: Icons.military_tech,
        color: const Color(0xFFFF7043),
        horses: '${r1.horseNo}번 → ${r2.horseNo}번 → ${r3.horseNo}번',
        odds: fmt(trio),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              '승식별 결과',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          ...bettingTypes.map((bt) => _BettingTypeCard(type: bt)),
        ],
      ),
    );
  }
}

class _BettingType {
  final String name;
  final String desc;
  final IconData icon;
  final Color color;
  final String horses;
  final String odds;

  const _BettingType({
    required this.name,
    required this.desc,
    required this.icon,
    required this.color,
    required this.horses,
    required this.odds,
  });
}

class _BettingTypeCard extends StatelessWidget {
  final _BettingType type;
  const _BettingTypeCard({required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: type.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: type.color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: type.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(type.icon, color: type.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      type.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: type.color,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      type.desc,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  type.horses,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (type.odds.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.accentGold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                type.odds,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accentGold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── 상위 3마리 카드 ──

class _TopThreeCard extends StatelessWidget {
  final List<RaceResult> results;
  const _TopThreeCard({required this.results});

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.winColor.withValues(alpha: 0.15),
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
          Row(
            children: [
              Icon(Icons.emoji_events, color: AppTheme.winColor, size: 22),
              const SizedBox(width: 8),
              const Text(
                '입상 마필',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: results.asMap().entries.map((e) {
              final idx = e.key;
              final r = e.value;
              final colors = [
                AppTheme.winColor,
                AppTheme.placeColor,
                AppTheme.showColor,
              ];
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: idx > 0 ? 8 : 0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors[idx].withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colors[idx].withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${idx + 1}착',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: colors[idx],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${r.horseNo}번',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: colors[idx],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          r.horseName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          r.raceTime,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade400,
                          ),
                        ),
                        if (r.winOdds > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '${r.winOdds.toStringAsFixed(1)}배',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.accentGold,
                              ),
                            ),
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
}

// ── 전체 순위 카드 ──

class _ResultCard extends StatelessWidget {
  final RaceResult result;
  final VoidCallback onHorseTap;

  const _ResultCard({required this.result, required this.onHorseTap});

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
      child: InkWell(
        onTap: onHorseTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: rankColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: rankColor.withValues(alpha: 0.4),
                  ),
                ),
                child: Center(
                  child: Text(
                    '${result.rank}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
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
                    Row(
                      children: [
                        Text(
                          '${result.horseNo}번 ',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            result.horseName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${result.jockeyName} | ${result.weight.toStringAsFixed(0)}kg',
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
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (result.rankDiff.isNotEmpty)
                    Text(
                      result.rankDiff,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade500),
                    ),
                  if (result.winOdds > 0)
                    Text(
                      '${result.winOdds.toStringAsFixed(1)}배',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.accentGold,
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
}
