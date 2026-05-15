/// 주차장 1건(공영주차장 CSV 또는 카카오 로컬 API 결과)을 표현하는 값 객체.
///
/// 거리(`distanceM`)는 검색 기준점에 따라 런타임에 계산해 채워 넣는다.
class ParkingPlace {
  const ParkingPlace({
    required this.id,
    required this.name,
    required this.address,
    required this.roadAddress,
    required this.phone,
    required this.latitude,
    required this.longitude,
    required this.distanceM,
    required this.placeUrl,
    this.isFree = false,
    this.slotCount,
    this.feeText = '',
  });

  /// 데이터 고유 ID (CSV의 '주차장관리번호' 또는 카카오 'id').
  final String id;
  final String name;
  final String address;
  final String roadAddress;
  final String phone;
  final double latitude;
  final double longitude;

  /// 검색 기준점으로부터의 직선거리(m).
  final int distanceM;

  /// 외부 상세 페이지 URL (카카오맵 등). 데이터에 없으면 빈 문자열.
  final String placeUrl;

  /// 요금 무료 여부 (CSV의 '요금정보' = '무료').
  final bool isFree;

  /// 주차구획 수 (CSV).
  final int? slotCount;

  /// 요금 정보 원문 라벨 (예: '무료', '유료').
  final String feeText;

  /// 거리만 갱신한 복사본 생성 (재정렬·필터링용).
  ParkingPlace copyWithDistance(int newDistanceM) => ParkingPlace(
    id: id,
    name: name,
    address: address,
    roadAddress: roadAddress,
    phone: phone,
    latitude: latitude,
    longitude: longitude,
    distanceM: newDistanceM,
    placeUrl: placeUrl,
    isFree: isFree,
    slotCount: slotCount,
    feeText: feeText,
  );

  factory ParkingPlace.fromJson(Map<String, dynamic> json) {
    int parseDistance(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    double parseCoord(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    return ParkingPlace(
      id: (json['id'] ?? '').toString(),
      name: (json['place_name'] ?? '').toString(),
      address: (json['address_name'] ?? '').toString(),
      roadAddress: (json['road_address_name'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      latitude: parseCoord(json['y']),
      longitude: parseCoord(json['x']),
      distanceM: parseDistance(json['distance']),
      placeUrl: (json['place_url'] ?? '').toString(),
    );
  }
}
