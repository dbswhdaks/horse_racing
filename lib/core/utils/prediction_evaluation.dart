abstract final class PredictionEvaluation {
  static int positionHits({
    required List<int?> predicted,
    required List<int?> actual,
    int slots = 3,
  }) {
    var hits = 0;
    for (var index = 0; index < slots; index++) {
      final predictedHorse = index < predicted.length ? predicted[index] : null;
      final actualHorse = index < actual.length ? actual[index] : null;
      if (predictedHorse != null &&
          actualHorse != null &&
          predictedHorse == actualHorse) {
        hits++;
      }
    }
    return hits;
  }

  static double positionAccuracy({
    required List<int?> predicted,
    required List<int?> actual,
    int slots = 3,
  }) {
    if (slots <= 0) return 0;
    return positionHits(predicted: predicted, actual: actual, slots: slots) /
        slots *
        100;
  }
}
