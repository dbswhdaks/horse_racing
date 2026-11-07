import 'package:flutter_test/flutter_test.dart';
import 'package:horse_racing/core/services/entry_features.dart';

PastRunRecord _run({
  required String date,
  required String passOrder,
  int fieldSize = 10,
  int raceNo = 1,
}) => PastRunRecord(
  raceDate: date,
  raceNo: raceNo,
  horseName: '테스트마',
  jockeyName: '기수01',
  rank: 3,
  fieldSize: fieldSize,
  distance: 1400,
  horseWeight: 470,
  passOrder: passOrder,
);

void main() {
  group('parseRaceTimeSeconds', () {
    test('분:초와 초 단위를 파싱한다', () {
      expect(parseRaceTimeSeconds('1:12.3'), closeTo(72.3, 1e-9));
      expect(parseRaceTimeSeconds('59.9'), closeTo(59.9, 1e-9));
      expect(parseRaceTimeSeconds('0.0'), 0);
      expect(parseRaceTimeSeconds('bad'), 0);
    });
  });

  group('parsePassOrderStyle', () {
    test('빈 값과 숫자 없는 값은 모른다', () {
      expect(parsePassOrderStyle('', 10), isEmpty);
      expect(parsePassOrderStyle('   ', 12), isEmpty);
      expect(parsePassOrderStyle('n/a', 10), isEmpty);
    });

    test('한글 유형이 숫자보다 우선한다', () {
      expect(parsePassOrderStyle('선행 8-8-8-8', 12), '선행');
      expect(parsePassOrderStyle('선입', 8), '선입');
      expect(parsePassOrderStyle('추입형', 10), '추입');
      expect(parsePassOrderStyle('중단', 10), '중단');
    });

    test('1~2위 초반은 두수와 관계없이 선행이다', () {
      expect(parsePassOrderStyle('1-1-1-1', 6), '선행');
      expect(parsePassOrderStyle('2-2-3-2', 14), '선행');
    });

    test('첫 구간 위치를 두수 비율로 나눈다', () {
      expect(parsePassOrderStyle('3-3-3-3', 12), '선행'); // 0.25
      expect(parsePassOrderStyle('4-4-3-2', 10), '선입'); // 0.40
      expect(parsePassOrderStyle('6-5-4-3', 10), '중단'); // 0.60
      expect(parsePassOrderStyle('8-7-5-3', 10), '추입'); // 0.80
    });
  });

  group('runningStyleFromRecords', () {
    test('유효 표본이 2건 미만이면 빈 문자열이다', () {
      expect(runningStyleFromRecords(const []), isEmpty);
      expect(
        runningStyleFromRecords([
          _run(date: '20260101', passOrder: '1-1-1-1'),
          _run(date: '20260108', passOrder: ''),
        ]),
        isEmpty,
      );
    });

    test('직전 5경주 최빈값을 쓰고 동률이면 가장 최근을 택한다', () {
      final records = [
        _run(date: '20260101', passOrder: '8-8-7-6'),
        _run(date: '20260108', passOrder: '8-7-6-5'),
        _run(date: '20260115', passOrder: '1-1-1-1'),
        _run(date: '20260122', passOrder: '1-2-2-1'),
        _run(date: '20260129', passOrder: '1-1-2-1'),
      ];
      expect(runningStyleFromRecords(records), '선행');
    });
  });
}
