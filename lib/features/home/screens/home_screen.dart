import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../../models/race.dart';
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
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _meets = ['1', '2', '3'];
  final _meetLabels = ['서울', '제주', '영남'];

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
      key: _scaffoldKey,
      endDrawer: _AppDrawer(
        onBranchesTap: () {
          Navigator.of(context).pop();
          context.push('/branches');
        },
      ),
      body: Stack(
        children: [
          // 상단 앰비언트 골드 글로우 (헤더 영역에만 스며들도록)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 260,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.5),
                    radius: 1.2,
                    colors: [
                      AppTheme.accentGold.withValues(alpha: 0.10),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverAppBar(
                  pinned: true,
                  backgroundColor: AppTheme.surfaceDark,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  toolbarHeight: 68,
                  titleSpacing: 20,
                  title: const _AppLogo(),
                  actions: [
                    _GhostIconButton(
                      icon: Icons.share_rounded,
                      tooltip: '공유하기',
                      onPressed: () => _share(dateStr),
                    ),
                    const SizedBox(width: 8),
                    _GhostIconButton(
                      icon: Icons.menu_rounded,
                      tooltip: '메뉴',
                      onPressed: () =>
                          _scaffoldKey.currentState?.openEndDrawer(),
                    ),
                    const SizedBox(width: 14),
                  ],
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(120),
                    child: Column(
                      children: [
                        _MeetTabs(
                          controller: _tabController,
                          labels: _meetLabels,
                        ),
                        const SizedBox(height: 14),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _DateSelector(
                            date: selectedDate,
                            isToday: isToday,
                            onPrev: _prevDay,
                            onNext: _nextDay,
                            onTap: _selectDate,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
              ],
              body: TabBarView(
                controller: _tabController,
                children: List.generate(
                  _meets.length,
                  (i) =>
                      _RaceListTab(meet: _meets[i], meetLabel: _meetLabels[i]),
                ),
              ),
            ),
          ),
        ],
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

// ── 햄버거(엔드) 드로어 ──

class _AppDrawer extends StatelessWidget {
  const _AppDrawer({required this.onBranchesTap});

  final VoidCallback onBranchesTap;

  Future<void> _openPlayStore(BuildContext context, String packageId) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();

    final marketUri = Uri.parse('market://details?id=$packageId');
    final webUri = Uri.parse(
      'https://play.google.com/store/apps/details?id=$packageId',
    );

    try {
      final ok = await launchUrl(
        marketUri,
        mode: LaunchMode.externalApplication,
      );
      if (ok) return;
    } catch (_) {}

    try {
      final ok = await launchUrl(webUri, mode: LaunchMode.externalApplication);
      if (!ok) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Play 스토어를 열 수 없습니다.')),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Play 스토어를 열 수 없습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DrawerHeader(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.emoji_events, color: AppTheme.accentGold),
                      const SizedBox(width: 8),
                      const Text(
                        '경마 Plus',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '메뉴',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(
                Icons.directions_rounded,
                color: AppTheme.primaryGreen,
              ),
              title: const Text('경마장 가는길'),
              subtitle: Text(
                '현재 위치 기준 거리순',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: onBranchesTap,
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Row(
                children: [
                  Icon(
                    Icons.apps_rounded,
                    size: 14,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '추천 앱',
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.pedal_bike_rounded,
                color: Color(0xFFFBBF24),
              ),
              title: const Text('경륜Plus'),
              subtitle: Text(
                '실시간 경륜정보 및 경기 결과',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
              trailing: Icon(
                Icons.open_in_new_rounded,
                size: 16,
                color: Colors.grey.shade500,
              ),
              onTap: () => _openPlayStore(context, 'com.gyeongryunplus.app'),
            ),
            ListTile(
              leading: const Icon(
                Icons.directions_boat_rounded,
                color: Color(0xFF38BDF8),
              ),
              title: const Text('경정Plus'),
              subtitle: Text(
                '출주표 · AI 상세분석 및 예상',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
              trailing: Icon(
                Icons.open_in_new_rounded,
                size: 16,
                color: Colors.grey.shade500,
              ),
              onTap: () => _openPlayStore(context, 'com.boat_racing'),
            ),
            ListTile(
              leading: const Icon(
                Icons.confirmation_number_rounded,
                color: Color(0xFF22C55E),
              ),
              title: const Text('로또Plus'),
              subtitle: Text(
                'AI 추천 로또번호 및 당첨번호 확인',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
              trailing: Icon(
                Icons.open_in_new_rounded,
                size: 16,
                color: Colors.grey.shade500,
              ),
              onTap: () => _openPlayStore(context, 'com.inovixa.lotto'),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
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

  void _prefetchEntryData(Race race) {
    final entryParams = (
      meet: widget.meet,
      date: race.raceDate,
      raceNo: race.raceNo,
    );
    unawaited(ref.read(raceStartListProvider(entryParams).future));
    unawaited(ref.read(raceHorseStatsProvider(entryParams).future));
    unawaited(ref.read(oddsProvider(entryParams).future));
    unawaited(ref.read(predictionProvider(entryParams).future));
    unawaited(
      ref.read(
        racePlanProvider((meet: widget.meet, date: race.raceDate)).future,
      ),
    );
  }

  void _openEntryDetail(Race race, BuildContext context) {
    _prefetchEntryData(race);
    context.push(
      '/entry/${widget.meet}/${race.raceDate}/${race.raceNo}',
      extra: race,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(selectedDateProvider);
    final dateParam = formatDateParam(selectedDate);
    final racesAsync = ref.watch(
      racePlanProvider((meet: widget.meet, date: dateParam)),
    );

    return racesAsync.when(
      loading: () => const SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(12, 12, 12, 24),
        child: ShimmerRaceList(),
      ),
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

        final now = DateTime.now();
        final isToday =
            selectedDate.year == now.year &&
            selectedDate.month == now.month &&
            selectedDate.day == now.day;

        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
            itemCount: races.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _UpdateButton(
                  lastUpdated: _lastUpdated,
                  isLive: isToday,
                  onTap: _refresh,
                );
              }
              final race = races[index - 1];
              final actualHeadCount = headCounts[race.raceNo] ?? race.headCount;
              return RaceCard(
                race: race,
                headCount: actualHeadCount,
                onTap: () => _openEntryDetail(race, context),
                onResultTap: () => context.push(
                  '/result/${widget.meet}/${race.raceDate}/${race.raceNo}',
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ── 업데이트 인디케이터 (LIVE 펄스 도트 + 시간 + 새로고침) ──

class _UpdateButton extends StatefulWidget {
  final DateTime lastUpdated;
  final bool isLive;
  final VoidCallback onTap;

  const _UpdateButton({
    required this.lastUpdated,
    required this.onTap,
    this.isLive = false,
  });

  @override
  State<_UpdateButton> createState() => _UpdateButtonState();
}

class _UpdateButtonState extends State<_UpdateButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

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
        final label = _timeAgo(widget.lastUpdated);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Row(
            children: [
              if (widget.isLive) ...[
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) => Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppTheme.positiveGreen,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.positiveGreen.withValues(
                            alpha: 0.4 + _pulse.value * 0.4,
                          ),
                          blurRadius: 6 + _pulse.value * 6,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'LIVE',
                  style: TextStyle(
                    color: AppTheme.positiveGreen,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 1,
                  height: 10,
                  color: Colors.white.withValues(alpha: 0.12),
                ),
                const SizedBox(width: 10),
              ],
              Text(
                '$label 업데이트',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: widget.onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.refresh_rounded,
                        size: 13,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '새로고침',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
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

// ── 프리미엄 헤더 위젯 ──

/// 골드 그라데이션 뱃지 + '경마 Plus' 워드마크
class _AppLogo extends StatelessWidget {
  const _AppLogo();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.accentGold,
                AppTheme.accentGold.withValues(alpha: 0.55),
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentGold.withValues(alpha: 0.35),
                blurRadius: 14,
                spreadRadius: -3,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(
            Icons.emoji_events_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          '경마 Plus',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

/// 반투명 배경 + subtle 테두리의 라운드 사각형 아이콘 버튼.
class _GhostIconButton extends StatelessWidget {
  const _GhostIconButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Icon(
              icon,
              color: Colors.white.withValues(alpha: 0.85),
              size: 19,
            ),
          ),
        ),
      ),
    );
  }
}

/// 골드 언더라인 + 볼드 강조의 커스텀 경마장 탭.
class _MeetTabs extends StatelessWidget {
  const _MeetTabs({required this.controller, required this.labels});

  final TabController controller;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
            ),
          ),
          child: Row(
            children: List.generate(labels.length, (i) {
              final selected = controller.index == i;
              return Expanded(
                child: InkWell(
                  onTap: () => controller.animateTo(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: selected
                              ? AppTheme.accentGold
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 180),
                      style: TextStyle(
                        color: selected
                            ? AppTheme.accentGold
                            : Colors.white.withValues(alpha: 0.45),
                        fontSize: 15,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w500,
                        letterSpacing: -0.2,
                      ),
                      child: Text(labels[i]),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

/// 골드 그라데이션 테두리 + soft glow 의 리파인드 날짜 선택기.
class _DateSelector extends StatelessWidget {
  const _DateSelector({
    required this.date,
    required this.isToday,
    required this.onPrev,
    required this.onNext,
    required this.onTap,
  });

  final DateTime date;
  final bool isToday;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('yyyy.MM.dd (E)', 'ko').format(date);
    return Row(
      children: [
        _NavCircleButton(icon: Icons.chevron_left_rounded, onTap: onPrev),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                gradient: isToday
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppTheme.accentGold.withValues(alpha: 0.22),
                          AppTheme.accentGold.withValues(alpha: 0.08),
                        ],
                      )
                    : null,
                color: isToday ? null : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isToday
                      ? AppTheme.accentGold.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.08),
                ),
                boxShadow: isToday
                    ? [
                        BoxShadow(
                          color: AppTheme.accentGold.withValues(alpha: 0.18),
                          blurRadius: 14,
                          spreadRadius: -4,
                        ),
                      ]
                    : null,
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 13,
                    color: isToday ? AppTheme.accentGold : Colors.grey.shade400,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 14,
                      color: isToday
                          ? AppTheme.accentGold
                          : Colors.grey.shade200,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (isToday) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.accentGold.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '오늘',
                        style: TextStyle(
                          color: AppTheme.accentGold,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _NavCircleButton(icon: Icons.chevron_right_rounded, onTap: onNext),
      ],
    );
  }
}

class _NavCircleButton extends StatelessWidget {
  const _NavCircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Icon(
            icon,
            size: 20,
            color: Colors.white.withValues(alpha: 0.75),
          ),
        ),
      ),
    );
  }
}
