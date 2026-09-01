import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:horse_racing/core/services/local_predictor.dart';

/// `backend/generate_harville_golden.py` 로 재생성하는 픽스처.
const _goldenPath = 'test/fixtures/harville_golden.json';

void main() {
  group('harvillePlaceProbs', () {
    late List<Map<String, dynamic>> cases;

    setUpAll(() {
      final raw = File(_goldenPath).readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      cases = (decoded['cases'] as List)
          .cast<Map<String, dynamic>>()
          .toList(growable: false);
    });

    test('파이썬 튜닝 스크립트와 값이 일치한다', () {
      expect(cases, isNotEmpty);

      for (final testCase in cases) {
        final name = testCase['name'] as String;
        final slots = testCase['slots'] as int;
        final weights = (testCase['weights'] as List)
            .map((v) => (v as num).toDouble())
            .toList();
        final expected = (testCase['expected'] as List)
            .map((v) => (v as num).toDouble())
            .toList();

        final actual = LocalPredictor.harvillePlaceProbs(
          weights,
          slots: slots,
        );

        expect(actual.length, expected.length, reason: name);
        for (int i = 0; i < expected.length; i++) {
          expect(actual[i], closeTo(expected[i], 1e-9), reason: '$name[$i]');
        }
      }
    });

    test('두수가 입상권보다 많으면 확률 합이 입상 슬롯 수와 같다', () {
      for (final testCase in cases) {
        final slots = testCase['slots'] as int;
        final weights = (testCase['weights'] as List)
            .map((v) => (v as num).toDouble())
            .toList();
        if (weights.length <= slots) continue;

        final total = LocalPredictor.harvillePlaceProbs(
          weights,
          slots: slots,
        ).fold<double>(0, (a, b) => a + b);

        expect(
          total,
          closeTo(slots.toDouble(), 1e-6),
          reason: testCase['name'] as String,
        );
      }
    });

    test('두수가 입상권 이하면 모두 100% 입상이다', () {
      expect(
        LocalPredictor.harvillePlaceProbs([5, 1], slots: 3),
        everyElement(1.0),
      );
      expect(
        LocalPredictor.harvillePlaceProbs([3, 2, 1], slots: 3),
        everyElement(1.0),
      );
    });

    test('가중치가 클수록 입상 확률이 단조 증가한다', () {
      final probs = LocalPredictor.harvillePlaceProbs([
        10,
        8,
        6,
        4,
        2,
        1,
      ], slots: 3);

      for (int i = 1; i < probs.length; i++) {
        expect(probs[i], lessThan(probs[i - 1]));
      }
    });

    test('빈 목록은 빈 결과를 반환한다', () {
      expect(LocalPredictor.harvillePlaceProbs(const []), isEmpty);
    });
  });
}
