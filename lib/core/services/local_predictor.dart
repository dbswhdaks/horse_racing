import 'dart:math';
import '../../models/prediction.dart';
import '../../models/race_entry.dart';

/// Generates a local fallback prediction when the ML backend is unreachable.
/// Uses simple heuristics based on entry stats (win rate, rating, weight).
class LocalPredictor {
  static PredictionReport generate({
    required String meet,
    required String date,
    required int raceNo,
    required List<RaceEntry> entries,
  }) {
    if (entries.isEmpty) {
      return PredictionReport(
        raceId: '${meet}_${date}_$raceNo',
        raceDate: date,
        meet: meet,
        raceNo: raceNo,
        predictions: [],
        modelVersion: 'local-1.0',
        generatedAt: DateTime.now(),
      );
    }

    final rng = Random(date.hashCode ^ raceNo);
    final predictions = <Prediction>[];

    double totalScore = 0;
    final scores = <double>[];

    for (final entry in entries) {
      double score = 10.0;

      // Rating-based score
      if (entry.rating > 0) {
        score += entry.rating * 0.3;
      }

      // Win rate factor
      if (entry.totalRaces > 0) {
        score += entry.winRate * 0.5;
        score += entry.placeRate * 0.2;
      }

      // Recent prize as a proxy for form
      if (entry.recentPrize > 0) {
        score += (entry.recentPrize / 100000).clamp(0, 20);
      }

      // Weight penalty (lighter = slight advantage)
      if (entry.weight > 0) {
        score -= (entry.weight - 54) * 0.3;
      }

      // Randomness to simulate uncertainty
      score += rng.nextDouble() * 8;
      score = score.clamp(1, 100);

      scores.add(score);
      totalScore += score;
    }

    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final winProb = totalScore > 0 ? (scores[i] / totalScore * 100) : 0.0;
      final placeProb = (winProb * 2.2).clamp(0, 95);

      final tags = <String>[];
      if (entry.winRate >= 20) tags.add('고승률');
      if (entry.rating >= 60) tags.add('고레이팅');
      if (entry.totalRaces >= 20 && entry.winRate >= 15) tags.add('경험마');
      if (entry.recentPrize > 500000) tags.add('최근호조');
      if (entry.weight <= 53) tags.add('경량');

      predictions.add(Prediction(
        horseNo: entry.horseNo,
        horseName: entry.horseName,
        winProbability: double.parse(winProb.toStringAsFixed(2)),
        placeProbability: double.parse(placeProb.toStringAsFixed(2)),
        tags: tags,
        featureImportance: {
          'rating': entry.rating > 0 ? (entry.rating / 100).clamp(0, 1) : 0,
          'win_rate': (entry.winRate / 100).clamp(0, 1),
          'recent_prize': entry.recentPrize > 0
              ? (entry.recentPrize / 1000000).clamp(0, 1)
              : 0,
          'weight': ((60 - entry.weight) / 10).clamp(0, 1),
        },
      ));
    }

    predictions.sort((a, b) => b.winProbability.compareTo(a.winProbability));

    return PredictionReport(
      raceId: '${meet}_${date}_$raceNo',
      raceDate: date,
      meet: meet,
      raceNo: raceNo,
      predictions: predictions,
      modelVersion: 'local-1.0',
      generatedAt: DateTime.now(),
    );
  }
}
