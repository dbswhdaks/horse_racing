import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../race/providers/race_providers.dart';
import '../widgets/race_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _meets = ['1', '2', '3'];
  final _meetLabels = ['서울', '제주', '부산경남'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _meets.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        ref.read(selectedMeetProvider.notifier).state =
            _meets[_tabController.index];
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(selectedDateProvider);
    final dateStr = DateFormat('yyyy.MM.dd (E)', 'ko').format(selectedDate);
    final isToday = _isSameDay(selectedDate, DateTime.now());

    return Scaffold(
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              pinned: true,
              expandedHeight: 170,
              toolbarHeight: 70,
              title: Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.emoji_events, color: AppTheme.accentGold),
                    const SizedBox(width: 8),
                    const Text('경마 Plus'),
                  ],
                ),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(top: 24, right: 6),
                  child: IconButton(
                    icon: const Icon(Icons.share_rounded),
                    tooltip: '공유하기',
                    onPressed: () => _share(dateStr),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(114),
                child: Column(
                  children: [
                    const SizedBox(height: 14),
                    TabBar(
                      controller: _tabController,
                      tabs: _meetLabels.map((l) => Tab(text: l)).toList(),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left, size: 20),
                            onPressed: _prevDay,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                          ),
                          GestureDetector(
                            onTap: _selectDate,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isToday
                                    ? AppTheme.accentGold.withValues(
                                        alpha: 0.15,
                                      )
                                    : Colors.grey.shade800.withValues(
                                        alpha: 0.5,
                                      ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                isToday ? '$dateStr (오늘)' : dateStr,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isToday
                                      ? AppTheme.accentGold
                                      : Colors.grey.shade300,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right, size: 20),
                            onPressed: _nextDay,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: List.generate(
              _meets.length,
              (i) => _RaceListTab(meet: _meets[i], meetLabel: _meetLabels[i]),
            ),
          ),
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _prevDay() {
    final current = ref.read(selectedDateProvider);
    ref.read(selectedDateProvider.notifier).state = current.subtract(
      const Duration(days: 1),
    );
  }

  void _nextDay() {
    final current = ref.read(selectedDateProvider);
    final next = current.add(const Duration(days: 1));
    if (!next.isAfter(DateTime.now().add(const Duration(days: 30)))) {
      ref.read(selectedDateProvider.notifier).state = next;
    }
  }

  Future<void> _selectDate() async {
    final current = ref.read(selectedDateProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      locale: const Locale('ko'),
    );
    if (picked != null) {
      ref.read(selectedDateProvider.notifier).state = picked;
    }
  }

  void _share(String dateStr) {
    final meet = _meetLabels[_tabController.index];
    final date = formatDateParam(ref.read(selectedDateProvider));
    final racesAsync = ref.read(
      racePlanProvider((meet: _meets[_tabController.index], date: date)),
    );
    final raceCount = racesAsync.valueOrNull?.length ?? 0;

    final text = StringBuffer()
      ..writeln('🏇 경마 Plus - $meet 경마')
      ..writeln('📅 $dateStr')
      ..writeln('🏁 총 $raceCount개 경주');

    final races = racesAsync.valueOrNull;
    if (races != null && races.isNotEmpty) {
      text.writeln();
      for (final r in races) {
        final time = r.startTime.length >= 4
            ? '${r.startTime.substring(0, 2)}:${r.startTime.substring(2, 4)}'
            : '';
        text.writeln(
          '${r.raceNo}R $time ${r.raceName} '
          '${r.distanceLabel} ${r.gradeLabel} ${r.headCount}두',
        );
      }
    }

    text.writeln('\n경마 Plus 앱에서 확인하세요!');
    SharePlus.instance.share(ShareParams(text: text.toString()));
  }

}

class _RaceListTab extends ConsumerStatefulWidget {
  final String meet;
  final String meetLabel;

  const _RaceListTab({required this.meet, required this.meetLabel});

  @override
  ConsumerState<_RaceListTab> createState() => _RaceListTabState();
}

class _RaceListTabState extends ConsumerState<_RaceListTab> {
  DateTime _lastUpdated = DateTime.now();

  void _refresh() {
    final dateParam = formatDateParam(ref.read(selectedDateProvider));
    ref.invalidate(racePlanProvider((meet: widget.meet, date: dateParam)));
    ref.invalidate(raceHeadCountProvider((meet: widget.meet, date: dateParam)));
    setState(() => _lastUpdated = DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(selectedDateProvider);
    final dateParam = formatDateParam(selectedDate);
    final racesAsync = ref.watch(
      racePlanProvider((meet: widget.meet, date: dateParam)),
    );

    return racesAsync.when(
      loading: () => const ShimmerCardList(cardHeight: 130),
      error: (err, stack) =>
          _ErrorView(message: '경주 정보를 불러올 수 없습니다\n$err', onRetry: _refresh),
      data: (races) {
        if (races.isEmpty) {
          return _EmptyView(date: selectedDate, meetLabel: widget.meetLabel);
        }
        races = [...races]..sort((a, b) => a.raceNo.compareTo(b.raceNo));

        final headCounts =
            ref
                .watch(
                  raceHeadCountProvider((meet: widget.meet, date: dateParam)),
                )
                .valueOrNull ??
            {};

        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
            itemCount: races.length + 2,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _UpdateButton(
                  lastUpdated: _lastUpdated,
                  onTap: _refresh,
                );
              }
              if (index == races.length + 1) {
                return const _ManageSubscriptionButton();
              }
              final race = races[index - 1];
              final actualHeadCount = headCounts[race.raceNo] ?? race.headCount;
              return RaceCard(
                race: race,
                headCount: actualHeadCount,
                onTap: () => context.push(
                  '/entry/${race.meet}/${race.raceDate}/${race.raceNo}',
                ),
                onResultTap: () => context.push(
                  '/result/${race.meet}/${race.raceDate}/${race.raceNo}',
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _ManageSubscriptionButton extends StatelessWidget {
  const _ManageSubscriptionButton();

  Future<void> _openSubscriptionManagePage(BuildContext context) async {
    final uri = Uri.parse(
      'https://play.google.com/store/account/subscriptions?package=com.horseracingplus.app',
    );

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('구독 관리 페이지를 열 수 없습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Row(
        children: [
          const Spacer(),
          OutlinedButton(
            onPressed: () => _openSubscriptionManagePage(context),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.grey.shade600),
              foregroundColor: Colors.grey.shade300,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              '구독 취소',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade300,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 업데이트 버튼 ──

class _UpdateButton extends StatelessWidget {
  final DateTime lastUpdated;
  final VoidCallback onTap;

  const _UpdateButton({required this.lastUpdated, required this.onTap});

  String _timeAgo(DateTime from) {
    final diff = DateTime.now().difference(from);
    if (diff.inSeconds < 5) return '방금';
    if (diff.inSeconds < 60) return '${diff.inSeconds}초 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    return '${diff.inHours}시간 전';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, _) {
        final label = _timeAgo(lastUpdated);
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
          child: Row(
            children: [
              Text(
                '$label 업데이트',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onTap,
                child: Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: AppTheme.primaryGreen,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── 에러 / 빈 화면 ──

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey.shade600),
            const SizedBox(height: 16),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final DateTime date;
  final String meetLabel;

  const _EmptyView({required this.date, required this.meetLabel});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy, size: 48, color: Colors.grey.shade700),
            const SizedBox(height: 16),
            Text(
              '선택한 날짜에는 $meetLabel 경주가 없습니다.',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade400,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
