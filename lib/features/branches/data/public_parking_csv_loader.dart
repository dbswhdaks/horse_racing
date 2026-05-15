import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/parking_place.dart';

/// 자산으로 포함된 전국 공영주차장 CSV(`assets/data/public_parking.csv`)를
/// 한 번만 로드해 [ParkingPlace] 목록으로 변환한다.
///
/// 원본은 한국교통안전공단 '전국공영주차장정보(20191224)' 공개 데이터다.
/// 25개 컬럼 중 UI에 필요한 항목만 추려서 보관한다.
class PublicParkingCsvLoader {
  PublicParkingCsvLoader._();

  static List<ParkingPlace>? _cached;

  static const _assetPath = 'assets/data/public_parking.csv';

  /// CSV 컬럼 인덱스. CSV 헤더 순서가 바뀌면 여기서만 조정한다.
  static const _colId = 0; // 주차장관리번호
  static const _colName = 1; // 주차장명
  static const _colLng = 2; // 경도
  static const _colLat = 3; // 위도
  // static const _colKind = 4; // 주차장구분(공영) - 본 데이터는 전부 공영
  // static const _colType = 5; // 주차장유형(노상/노외)
  static const _colJibun = 6; // 주차장지번주소
  static const _colRoad = 7; // 주차장도로명주소
  static const _colSlot = 8; // 주차구획수
  static const _colFee = 16; // 요금정보(무료/유료)
  static const _colPhone = 23; // 연락처

  /// 자산 CSV를 로드해 파싱한다. 두 번째 호출부터는 캐시된 값을 즉시 반환.
  static Future<List<ParkingPlace>> load() async {
    final existing = _cached;
    if (existing != null) return existing;

    final raw = await rootBundle.loadString(_assetPath);
    final parsed = _parse(raw);
    _cached = parsed;
    return parsed;
  }

  static List<ParkingPlace> _parse(String raw) {
    final lines = const LineSplitter().convert(raw);
    if (lines.isEmpty) return const [];

    final result = <ParkingPlace>[];
    // 첫 줄은 헤더이므로 건너뛴다.
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final cells = _splitCsvLine(line);
      if (cells.length < 24) continue;

      final lat = double.tryParse(cells[_colLat].trim());
      final lng = double.tryParse(cells[_colLng].trim());
      if (lat == null || lng == null) continue;
      if (lat == 0 && lng == 0) continue;

      final fee = cells[_colFee].trim();
      final isFree = fee == '무료';

      result.add(
        ParkingPlace(
          id: cells[_colId].trim(),
          name: cells[_colName].trim(),
          address: cells[_colJibun].trim(),
          roadAddress: cells[_colRoad].trim(),
          phone: cells[_colPhone].trim(),
          latitude: lat,
          longitude: lng,
          distanceM: 0,
          placeUrl: '',
          isFree: isFree,
          slotCount: int.tryParse(cells[_colSlot].trim()),
          feeText: fee,
        ),
      );
    }
    return result;
  }

  /// 단순 CSV 라인 파서.
  ///
  /// 원본 CSV에는 셀 안에 쉼표가 들어간 경우가 보이지 않아 따옴표 처리는 최소화했다.
  /// (필요 시 추후 RFC4180 호환 파서로 교체.)
  static List<String> _splitCsvLine(String line) {
    final cells = <String>[];
    final buffer = StringBuffer();
    var inQuote = false;

    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        inQuote = !inQuote;
      } else if (ch == ',' && !inQuote) {
        cells.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(ch);
      }
    }
    cells.add(buffer.toString());
    return cells;
  }
}
