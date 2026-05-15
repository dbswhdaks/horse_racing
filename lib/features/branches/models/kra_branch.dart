/// 한국마사회(KRA) 본장(렛츠런파크) 또는 장외발매소(지사), 경륜경정/스피존 지점 정보.
///
/// 좌표는 사용자 제공 자료(한국마사회 및 공개 위치자료) 기준이다.
class KraBranch {
  const KraBranch({
    required this.name,
    required this.address,
    required this.phone,
    required this.category,
    required this.latitude,
    required this.longitude,
  });

  /// 지점명. 예: '렛츠런파크 서울', '강동지사', '경륜경정 분당지사'.
  final String name;

  /// 도로명/지번 주소.
  final String address;

  /// 대표 전화번호.
  final String phone;

  /// 카테고리 구분 (정렬·필터·아이콘 분기 용도).
  final KraBranchCategory category;

  final double latitude;
  final double longitude;
}

enum KraBranchCategory {
  /// 공식 경마장(렛츠런파크): 서울 / 부산경남 / 제주 3곳.
  racepark,

  /// TV경마장 / 장외발매소(한국마사회 지사).
  offTrack,
}

extension KraBranchCategoryLabel on KraBranchCategory {
  String get label {
    switch (this) {
      case KraBranchCategory.racepark:
        return '공식 경마장';
      case KraBranchCategory.offTrack:
        return '장외발매소';
    }
  }
}
