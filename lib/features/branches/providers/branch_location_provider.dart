import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../data/kra_branches.dart';
import '../models/kra_branch.dart';

/// 거리 계산 결과(지점 + 사용자로부터의 거리 km).
class KraBranchWithDistance {
  const KraBranchWithDistance({required this.branch, required this.distanceKm});

  final KraBranch branch;

  /// 사용자 현재 위치로부터의 거리(km). 위치가 없으면 null.
  final double? distanceKm;
}

/// 위치 권한·획득의 단계별 상태.
enum LocationStatus {
  loading,
  ready,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  error,
}

class LocationState {
  const LocationState({
    required this.status,
    this.position,
    this.errorMessage,
  });

  final LocationStatus status;
  final Position? position;
  final String? errorMessage;

  const LocationState.loading() : this(status: LocationStatus.loading);
}

/// 사용자 현재 위치를 관리한다.
///
/// 화면이 처음 진입할 때 [ensureLoaded] 한 번 호출하면 권한 요청·좌표 획득까지 진행한다.
/// 명시적 새로고침은 [refresh] 사용.
class LocationController extends StateNotifier<LocationState> {
  LocationController() : super(const LocationState.loading());

  bool _started = false;

  Future<void> ensureLoaded() async {
    if (_started) return;
    _started = true;
    await _fetch();
  }

  Future<void> refresh() async {
    state = const LocationState.loading();
    await _fetch();
  }

  Future<void> _fetch() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        state = const LocationState(status: LocationStatus.serviceDisabled);
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        state = const LocationState(
          status: LocationStatus.permissionDeniedForever,
        );
        return;
      }
      if (permission == LocationPermission.denied) {
        state = const LocationState(status: LocationStatus.permissionDenied);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
      );
      state = LocationState(status: LocationStatus.ready, position: position);
    } catch (e) {
      state = LocationState(
        status: LocationStatus.error,
        errorMessage: e.toString(),
      );
    }
  }
}

final locationControllerProvider =
    StateNotifierProvider<LocationController, LocationState>(
      (ref) => LocationController(),
    );

/// 카테고리 필터 상태. null이면 전체 표시.
final branchCategoryFilterProvider = StateProvider<KraBranchCategory?>(
  (_) => null,
);

/// 현재 위치 기준 거리순 + 카테고리 필터 적용된 지점 리스트.
///
/// 위치가 아직 없으면 거리값은 null, 카테고리 → 이름순 fallback 정렬.
final sortedKraBranchesProvider = Provider<List<KraBranchWithDistance>>((ref) {
  final location = ref.watch(locationControllerProvider);
  final filter = ref.watch(branchCategoryFilterProvider);
  final position = location.position;

  final source = filter == null
      ? kraBranches
      : kraBranches.where((b) => b.category == filter).toList();

  final list = source.map((branch) {
    double? distance;
    if (position != null) {
      final meters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        branch.latitude,
        branch.longitude,
      );
      distance = meters / 1000.0;
    }
    return KraBranchWithDistance(branch: branch, distanceKm: distance);
  }).toList();

  if (position != null) {
    list.sort(
      (a, b) => (a.distanceKm ?? double.infinity).compareTo(
        b.distanceKm ?? double.infinity,
      ),
    );
  } else {
    list.sort((a, b) {
      final c = a.branch.category.index.compareTo(b.branch.category.index);
      if (c != 0) return c;
      return a.branch.name.compareTo(b.branch.name);
    });
  }
  return list;
});
