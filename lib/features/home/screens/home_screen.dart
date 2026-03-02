import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

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
    return Scaffold(
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              floating: true,
              snap: true,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.emoji_events, color: AppTheme.accentGold),
                  const SizedBox(width: 8),
                  const Text('경마 Plus'),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.calendar_today),
                  onPressed: _selectDate,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _refresh,
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(72),
                child: Column(
                  children: [
                    TabBar(
                      controller: _tabController,
                      tabs: _meetLabels.map((l) => Tab(text: l)).toList(),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 4),
                      child: Text(
                        DateFormat('yyyy.MM.dd (E)', 'ko').format(DateTime.now()),
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.orange,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: _meets.map((meet) => _RaceListTab(meet: meet)).toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) {
      // Could implement date selection state here
    }
  }

  void _refresh() {
    final meet = _meets[_tabController.index];
    ref.invalidate(racePlanProvider((meet: meet, date: null)));
  }
}

class _RaceListTab extends ConsumerWidget {
  final String meet;

  const _RaceListTab({required this.meet});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final racesAsync = ref.watch(racePlanProvider((meet: meet, date: null)));

    return racesAsync.when(
      loading: () => const ShimmerCardList(cardHeight: 130),
      error: (err, stack) => _ErrorView(
        message: '경주 정보를 불러올 수 없습니다',
        onRetry: () =>
            ref.invalidate(racePlanProvider((meet: meet, date: null))),
      ),
      data: (races) {
        if (races.isEmpty) {
          return const _EmptyView();
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(racePlanProvider((meet: meet, date: null)));
          },
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
            itemCount: races.length,
            itemBuilder: (context, index) {
              final race = races[index];
              return RaceCard(
                race: race,
                onTap: () => context.push(
                  '/race/${race.meet}/${race.raceDate}/${race.raceNo}',
                ),
              );
            },
          ),
        );
      },
    );
  }
}

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
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy, size: 64, color: Colors.grey.shade600),
            const SizedBox(height: 16),
            Text(
              '오늘 예정된 경주가 없습니다',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
