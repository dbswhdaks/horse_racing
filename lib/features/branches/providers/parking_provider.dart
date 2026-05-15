import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../data/public_parking_csv_loader.dart';
import '../models/kra_branch.dart';
import '../models/parking_place.dart';
import 'branch_location_provider.dart';

/// 주차장 검색에 사용할 키워드 분류.
enum ParkingKind {
  /// 공영주차장 (CSV 전체).
  public('공영주차장'),

  /// 무료주차장 (CSV의 요금정보=무료 행만 필터).
  free('무료주차장');

  const ParkingKind(this.keyword);

  /// UI 라벨 등으로 사용되는 키워드.
  final String keyword;
}

/// CSV 자산을 1회 로드해 메모리에 캐시한다.
final allPublicParkingProvider = FutureProvider<List<ParkingPlace>>((ref) {
  return PublicParkingCsvLoader.load();
});

/// 현재 사용자가 선택한 '기준 지사'.
///
/// 탭 진입 시 자동으로 가장 가까운 지사가 선택된다(UI 측에서 1회 세팅).
final selectedAnchorBranchProvider = StateProvider<KraBranch?>((_) => null);

/// 주차장 검색 매개변수.
class ParkingQuery {
  const ParkingQuery({
    required this.anchor,
    required this.kind,
    this.radius = 2000,
  });

  final KraBranch anchor;
  final ParkingKind kind;
  final int radius;

  @override
  bool operator ==(Object other) =>
      other is ParkingQuery &&
      other.anchor.name == anchor.name &&
      other.kind == kind &&
      other.radius == radius;

  @override
  int get hashCode => Object.hash(anchor.name, kind, radius);
}

/// 기준 지사 좌표 중심으로 [ParkingKind] 조건에 맞는 주차장을 반경 안에서 거리순 정렬해 반환한다.
///
/// - public: 전체(공영) 데이터에서 반경 필터링
/// - free: 요금정보=무료(isFree=true)만 추가 필터링
final nearbyParkingProvider =
    FutureProvider.family<List<ParkingPlace>, ParkingQuery>((ref, q) async {
      final all = await ref.watch(allPublicParkingProvider.future);

      final result = <ParkingPlace>[];
      for (final p in all) {
        if (q.kind == ParkingKind.free && !p.isFree) continue;

        final meters = Geolocator.distanceBetween(
          q.anchor.latitude,
          q.anchor.longitude,
          p.latitude,
          p.longitude,
        );
        if (meters > q.radius) continue;
        result.add(p.copyWithDistance(meters.round()));
      }
      result.sort((a, b) => a.distanceM.compareTo(b.distanceM));
      return result;
    });

/// 최초 진입 시 사용자 위치에서 가장 가까운 지사를 추천한다.
///
/// 사용자 위치가 없으면 거리순 정렬이 불가능하므로 첫 번째 지사를 반환한다.
final defaultAnchorBranchProvider = Provider<KraBranch?>((ref) {
  final sorted = ref.watch(sortedKraBranchesProvider);
  if (sorted.isEmpty) return null;
  return sorted.first.branch;
});
