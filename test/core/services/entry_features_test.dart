import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:horse_racing/core/services/entry_features.dart';

/// `backend/generate_entry_features_golden.py` 로 재생성하는 픽스처.
const _goldenPath = 'test/fixtures/entry_features_golden.json';

/// 파이썬 쪽은 결과 행을 세어 두수를 구하므로, Dart 테스트도 같은 방식으로
/// 두수를 채워 넣어야 두 구현의 입력이 동일해진다.
Map<String, int> _fieldSizes(List<Map<String, dynamic>> history) {
  final sizes = <String, int>{};
  for (final row in history) {
    if (((row['rank'] as num?)?.toInt() ?? 0) <= 0) continue;
    final key = '${row['meet']}_${row['race_date']}_${row['race_no']}';
    sizes[key] = (sizes[key] ?? 0) + 1;
  }
  return sizes;
}

void main() {
  group('AsOfFeatureIndex', () {
    late AsOfFeatureIndex index;
    late Map<String, dynamic> golden;

    setUpAll(() {
      golden =
          jsonDecode(File(_goldenPath).readAsStringSync())
              as Map<String, dynamic>;

      final history = (golden['history'] as List)
          .cast<Map<String, dynamic>>()
          .toList();
      final sizes = _fieldSizes(history);

      index = AsOfFeatureIndex(
        history.map((row) {
          final key = '${row['meet']}_${row['race_date']}_${row['race_no']}';
          return PastRunRecord(
            raceDate: row['race_date'] as String,
            raceNo: (row['race_no'] as num).toInt(),
            horseName: row['horse_name'] as String,
            jockeyName: row['jockey_name'] as String,
            rank: (row['rank'] as num).toInt(),
            fieldSize: sizes[key] ?? 0,
            distance: (row['distance'] as num).toInt(),
            horseWeight: (row['horse_weight'] as num).toDouble(),
          );
        }),
      );
    });

    test('전체 입상률 prior 가 파이썬과 일치한다', () {
      expect(
        index.priorPlaceRate,
        closeTo((golden['prior_place_rate'] as num).toDouble(), 1e-12),
      );
    });

    test('as-of 서브스코어가 파이썬과 일치한다', () {
      final cases = (golden['cases'] as List).cast<Map<String, dynamic>>();
      expect(cases, isNotEmpty);

      for (final testCase in cases) {
        final raceDate = testCase['race_date'] as String;
        final horseName = testCase['horse_name'] as String;
        final expected = testCase['expected'] as Map<String, dynamic>;

        final actual = index.featuresFor(
          raceDate: raceDate,
          horseName: horseName,
          jockeyName: testCase['jockey_name'] as String,
          distance: (testCase['distance'] as num).toInt(),
          horseWeight: (testCase['horse_weight'] as num).toDouble(),
        );

        final label = '$raceDate/$horseName';
        expect(
          actual.jockey,
          closeTo((expected['jockey'] as num).toDouble(), 1e-9),
          reason: '$label jockey',
        );
        expect(
          actual.recentForm,
          closeTo((expected['recent_form'] as num).toDouble(), 1e-9),
          reason: '$label recentForm',
        );
        expect(
          actual.fitness,
          closeTo((expected['fitness'] as num).toDouble(), 1e-9),
          reason: '$label fitness',
        );
      }
    });

    test('경주일 이후 결과는 참조하지 않는다', () {
      // 가장 이른 시행일에는 참조할 과거가 없으므로 모두 중립값이어야 한다.
      final scores = index.featuresFor(
        raceDate: '20240105',
        horseName: '말01',
        jockeyName: '기수01',
        distance: 1200,
        horseWeight: 480,
      );

      expect(scores.jockey, neutralFeatureScore);
      expect(scores.recentForm, neutralFeatureScore);
      expect(scores.fitness, neutralFeatureScore);
    });

    test('이력이 없는 말과 기수는 중립값을 받는다', () {
      final scores = index.featuresFor(
        raceDate: '20250425',
        horseName: '등록되지않은말',
        jockeyName: '등록되지않은기수',
        distance: 1400,
        horseWeight: 470,
      );

      expect(scores.jockey, neutralFeatureScore);
      expect(scores.recentForm, neutralFeatureScore);
      expect(scores.fitness, neutralFeatureScore);
    });
  });
}
