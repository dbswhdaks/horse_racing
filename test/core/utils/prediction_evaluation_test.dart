import 'package:flutter_test/flutter_test.dart';
import 'package:horse_racing/core/utils/prediction_evaluation.dart';

void main() {
  test('순위별 일치만 적중으로 계산한다', () {
    final accuracy = PredictionEvaluation.positionAccuracy(
      predicted: [2, 1, 3],
      actual: [1, 2, 3],
    );

    expect(accuracy, closeTo(100 / 3, 0.001));
  });

  test('선택 수가 부족해도 분모는 세 자리로 유지한다', () {
    final accuracy = PredictionEvaluation.positionAccuracy(
      predicted: [1],
      actual: [1, 2, 3],
    );

    expect(accuracy, closeTo(100 / 3, 0.001));
  });
}
