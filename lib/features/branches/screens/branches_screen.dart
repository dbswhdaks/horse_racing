import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../models/kra_branch.dart';
import '../providers/branch_location_provider.dart';

/// 길찾기 교통수단. 네이버 지도 URL 스킴의 route type과 1:1로 매핑된다.
enum TransportMode {
  walk('walk', '도보', Icons.directions_walk_rounded),
  transit('public', '대중교통', Icons.directions_bus_rounded),
  car('car', '자동차', Icons.directions_car_rounded);

  const TransportMode(this.nmapType, this.label, this.icon);

  /// 네이버 지도 앱 URL 스킴의 `route/{type}` 값 (walk / public / car).
  final String nmapType;
  final String label;
  final IconData icon;
}

/// 전국 공식 경마장(렛츠런파크) + 장외발매소 + 경륜·경정 지점 목록을
/// 사용자 현재 위치 기준 거리순으로 보여주는 화면.
///
/// 항목을 탭하면 외부 지도 앱(구글 맵)으로 길찾기를 실행한다.
class BranchesScreen extends ConsumerStatefulWidget {
  const BranchesScreen({super.key});

  @override
  ConsumerState<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends ConsumerState<BranchesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(locationControllerProvider.notifier).ensureLoaded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(locationControllerProvider);
    final filter = ref.watch(branchCategoryFilterProvider);
    final branches = ref.watch(sortedKraBranchesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('경마장 가는길'),
        actions: [
          IconButton(
            tooltip: '위치 새로고침',
            onPressed: location.status == LocationStatus.loading
                ? null
                : () =>
                      ref.read(locationControllerProvider.notifier).refresh(),
            icon: location.status == LocationStatus.loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _StatusBanner(location: location),
            _CategoryFilterChips(
              selected: filter,
              onChanged: (value) => ref
                  .read(branchCategoryFilterProvider.notifier)
                  .state = value,
            ),
            const Divider(height: 1),
            Expanded(
              child: branches.isEmpty
                  ? const Center(child: Text('표시할 지점이 없습니다.'))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: branches.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        thickness: 1,
                        color: Colors.white.withValues(alpha: 0.05),
                        indent: 16,
                        endIndent: 16,
                      ),
                      itemBuilder: (context, index) {
                        final item = branches[index];
                        return _BranchTile(
                          item: item,
                          rank: index + 1,
                          showDistance:
                              location.status == LocationStatus.ready,
                          onOpenMap: (mode) =>
                              _openNaverDirections(item, mode),
                          onCopyAddress: () => _copyAddress(item.branch),
                          onCallPhone: () => _callPhone(item.branch),
                          onParking: () =>
                              _openNaverParkingSearch(item.branch),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 네이버 지도로 길찾기를 연다.
  ///
  /// 1) 우선 네이버 지도 앱(`nmap://route/{mode}`)을 시도하고,
  /// 2) 앱이 설치되지 않은 경우 네이버 지도 모바일 웹으로 fallback 한다.
  Future<void> _openNaverDirections(
    KraBranchWithDistance item,
    TransportMode mode,
  ) async {
    final branch = item.branch;
    final position = ref.read(locationControllerProvider).position;
    final dlat = branch.latitude;
    final dlng = branch.longitude;
    final dname = Uri.encodeComponent(branch.name);

    final appQuery = StringBuffer('dlat=$dlat&dlng=$dlng&dname=$dname');
    if (position != null) {
      appQuery
        ..write('&slat=${position.latitude}')
        ..write('&slng=${position.longitude}')
        ..write('&sname=${Uri.encodeComponent('내 위치')}');
    }
    appQuery.write('&appname=com.kra.horse_racing');

    final appUri = Uri.parse('nmap://route/${mode.nmapType}?$appQuery');

    var launched = false;
    try {
      launched = await launchUrl(appUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (launched) return;

    final webUri = Uri.parse(
      'https://map.naver.com/p/directions'
      '/${position != null ? '${position.longitude},${position.latitude},내%20위치,,PLACE_POI' : '-'}'
      '/$dlng,$dlat,${branch.name},,PLACE_POI'
      '/-/${mode.nmapType == 'public' ? 'transit' : mode.nmapType}',
    );
    final ok = await launchUrl(webUri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('네이버 지도를 열 수 없습니다.')),
      );
    }
  }

  /// 네이버 지도에서 해당 지점 주변 '주차장' 키워드 검색 결과를 띄운다.
  ///
  /// 네이버 지도가 검색 결과 상세에 무료/공영 여부, 요금, 운영 시간 등을 함께
  /// 노출하므로 별도의 정적 데이터 없이도 최신 주차장 정보를 확인할 수 있다.
  Future<void> _openNaverParkingSearch(KraBranch branch) async {
    final query = Uri.encodeComponent('${branch.name} 주차장');

    final appUri = Uri.parse(
      'nmap://search?query=$query'
      '&lat=${branch.latitude}&lng=${branch.longitude}'
      '&zoom=16&appname=com.kra.horse_racing',
    );

    var launched = false;
    try {
      launched = await launchUrl(appUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (launched) return;

    final webUri = Uri.parse(
      'https://map.naver.com/p/search/$query'
      '?c=${branch.longitude},${branch.latitude},16,0,0,0,dh',
    );
    final ok = await launchUrl(webUri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('네이버 지도를 열 수 없습니다.')),
      );
    }
  }

  Future<void> _copyAddress(KraBranch branch) async {
    await Clipboard.setData(ClipboardData(text: branch.address));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${branch.name} 주소를 복사했습니다.')),
    );
  }

  Future<void> _callPhone(KraBranch branch) async {
    final uri = Uri(scheme: 'tel', path: branch.phone);
    final ok = await launchUrl(uri);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('전화 앱을 열 수 없습니다.')),
      );
    }
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.location});

  final LocationState location;

  ({String text, IconData icon, Color color})? _info() {
    switch (location.status) {
      case LocationStatus.loading:
        return (
          text: '현재 위치 확인 중…',
          icon: Icons.location_searching,
          color: Colors.blueGrey,
        );
      case LocationStatus.ready:
        return null;
      case LocationStatus.serviceDisabled:
        return (
          text: '기기 위치 서비스가 꺼져 있어요. 설정에서 켜주세요.',
          icon: Icons.location_disabled,
          color: Colors.orange,
        );
      case LocationStatus.permissionDenied:
        return (
          text: '위치 권한이 없어 거리순 정렬을 사용할 수 없어요.',
          icon: Icons.lock_outline,
          color: Colors.orange,
        );
      case LocationStatus.permissionDeniedForever:
        return (
          text: '위치 권한이 영구 거부되었어요. 앱 설정에서 권한을 허용해 주세요.',
          icon: Icons.lock_outline,
          color: Colors.redAccent,
        );
      case LocationStatus.error:
        return (
          text: '위치를 가져오지 못했어요. 새로고침을 눌러 주세요.',
          icon: Icons.error_outline,
          color: Colors.redAccent,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info();
    if (info == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: info.color.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(info.icon, size: 18, color: info.color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              info.text,
              style: TextStyle(
                fontSize: 12.5,
                color: info.color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryFilterChips extends StatelessWidget {
  const _CategoryFilterChips({
    required this.selected,
    required this.onChanged,
  });

  final KraBranchCategory? selected;
  final ValueChanged<KraBranchCategory?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _chip(label: '전체', value: null),
          ...KraBranchCategory.values.map(
            (c) => _chip(label: c.label, value: c),
          ),
        ],
      ),
    );
  }

  Widget _chip({required String label, required KraBranchCategory? value}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Center(
        child: ChoiceChip(
          label: Text(label),
          selected: selected == value,
          onSelected: (_) => onChanged(value),
        ),
      ),
    );
  }
}

class _BranchTile extends StatelessWidget {
  const _BranchTile({
    required this.item,
    required this.rank,
    required this.showDistance,
    required this.onOpenMap,
    required this.onCopyAddress,
    required this.onCallPhone,
    required this.onParking,
  });

  final KraBranchWithDistance item;
  final int rank;
  final bool showDistance;

  /// 길찾기 버튼 콜백. 사용자가 선택한 [TransportMode]를 전달받는다.
  final ValueChanged<TransportMode> onOpenMap;
  final VoidCallback onCopyAddress;
  final VoidCallback onCallPhone;

  /// 네이버 지도에서 해당 지점 주변 '주차장' 키워드 검색을 연다.
  final VoidCallback onParking;

  String _formatDistance(double km) {
    if (km < 1) return '${(km * 1000).round()} m';
    if (km < 10) return '${km.toStringAsFixed(1)} km';
    return '${km.round()} km';
  }

  Color _categoryColor(KraBranchCategory c) {
    switch (c) {
      case KraBranchCategory.racepark:
        return AppTheme.accentGold;
      case KraBranchCategory.offTrack:
        return AppTheme.primaryGreen;
    }
  }

  IconData _categoryIcon(KraBranchCategory c) {
    switch (c) {
      case KraBranchCategory.racepark:
        return Icons.emoji_events_rounded;
      case KraBranchCategory.offTrack:
        return Icons.storefront_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final branch = item.branch;
    final color = _categoryColor(branch.category);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            alignment: Alignment.center,
            child: Icon(
              _categoryIcon(branch.category),
              size: 20,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#$rank',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade300,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        branch.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (showDistance && item.distanceKm != null)
                      Text(
                        _formatDistance(item.distanceKm!),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  branch.address,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade400,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _ModeButton(
                        mode: TransportMode.walk,
                        onTap: () => onOpenMap(TransportMode.walk),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _ModeButton(
                        mode: TransportMode.transit,
                        onTap: () => onOpenMap(TransportMode.transit),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _ModeButton(
                        mode: TransportMode.car,
                        onTap: () => onOpenMap(TransportMode.car),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _MiniButton(
                      icon: Icons.local_parking_rounded,
                      label: '근처 주차장',
                      onTap: onParking,
                    ),
                    _MiniButton(
                      icon: Icons.call_rounded,
                      label: branch.phone,
                      onTap: onCallPhone,
                    ),
                    _MiniButton(
                      icon: Icons.copy_rounded,
                      label: '주소복사',
                      onTap: onCopyAddress,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 도보/대중교통/자동차 모드 버튼. 누르면 해당 모드로 네이버 지도 길찾기를 연다.
class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.mode, required this.onTap});

  final TransportMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.primaryGreen;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withValues(alpha: 0.55)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(mode.icon, size: 18, color: accent),
            const SizedBox(height: 2),
            Text(
              mode.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade200,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.grey.shade300),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade300,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
