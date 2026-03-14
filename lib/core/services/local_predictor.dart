import 'dart:math';
import '../../models/prediction.dart';
import '../../models/race_entry.dart';

/// heuristic-2.0: 종합 분석 기반 로컬 예측
/// - 레이팅 (25점), 성적 (25점), 기수 (20점), 전개 (15점), 컨디션 (15점)
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
        modelVersion: 'heuristic-2.0',
        generatedAt: DateTime.now(),
      );
    }

    final rng = Random(date.hashCode ^ raceNo);
    final predictions = <Prediction>[];

    final maxRating = entries.map((e) => e.rating).reduce((a, b) => a > b ? a : b);

    final horseData = entries.map((entry) {
      String runningStyle = '중단';
      if (entry.rating >= 85 && entry.winRate >= 20) {
        runningStyle = '선행';
      } else if (entry.rating >= 70) {
        runningStyle = '선입';
      } else if (entry.rating < 50) {
        runningStyle = '후입';
      }
      return {'entry': entry, 'style': runningStyle};
    }).toList();

    final frontRunners = horseData.where((h) => 
        h['style'] == '선행' || h['style'] == '선입').length;
    final paceFavorsClosers = frontRunners >= 4;
    final paceFavorsFront = frontRunners <= 1;

    double totalScore = 0;
    final scores = <double>[];
    final styles = <String>[];

    for (final h in horseData) {
      final entry = h['entry'] as RaceEntry;
      final style = h['style'] as String;
      styles.add(style);

      double score = 0;

      // 1. 레이팅 점수 (25점)
      final ratingScore = maxRating > 0 ? (entry.rating / maxRating) * 25 : 12.5;
      score += ratingScore;

      // 2. 성적 점수 (25점)
      double perfScore = 5;
      if (entry.winRate >= 25) {
        perfScore = 25;
      } else if (entry.winRate >= 15) {
        perfScore = 20;
      } else if (entry.placeRate >= 40) {
        perfScore = 18;
      } else if (entry.placeRate >= 25) {
        perfScore = 12;
      }
      score += perfScore;

      // 3. 기수/최근상금 점수 (20점)
      double jockeyScore = 10;
      if (entry.recentPrize > 500000) {
        jockeyScore = 20;
      } else if (entry.recentPrize > 200000) {
        jockeyScore = 15;
      }
      score += jockeyScore;

      // 4. 전개 점수 (15점)
      double paceScore = 8;
      if (paceFavorsClosers && (style == '후입' || style == '중단')) {
        paceScore = 15;
      } else if (paceFavorsFront && (style == '선행' || style == '선입')) {
        paceScore = 15;
      }
      score += paceScore;

      // 5. 컨디션 점수 (15점)
      double condScore = 8;
      if (entry.age >= 3 && entry.age <= 5) condScore += 3;
      if (entry.weight >= 52 && entry.weight <= 55) condScore += 2;
      if (entry.totalRaces >= 5 && entry.winCount >= 1) condScore += 2;
      score += condScore.clamp(0, 15);

      // 약간의 랜덤성
      score += rng.nextDouble() * 5;
      score = score.clamp(5, 100);

      scores.add(score);
      totalScore += score;
    }

    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final style = styles[i];
      final winProb = totalScore > 0 ? (scores[i] / totalScore * 100) : 0.0;
      final placeProb = (winProb * 2.0 + 5).clamp(0, 95);

      final tags = <String>[];
      if (entry.rating >= 80) tags.add('고레이팅');
      if (entry.winRate >= 20) tags.add('고승률');
      if (entry.placeRate >= 40 && entry.winRate < 20) tags.add('안정적입상');
      if (entry.totalRaces >= 15) tags.add('경험마');
      if (entry.recentPrize > 300000) tags.add('최근호조');
      if (entry.weight <= 53) tags.add('경량');
      if (winProb >= 15) tags.add('유력후보');

      if (paceFavorsClosers && (style == '후입' || style == '중단')) {
        tags.add('전개유리');
      } else if (paceFavorsFront && (style == '선행' || style == '선입')) {
        tags.add('전개유리');
      }

      if (style == '선행') tags.add('선행마');
      if (style == '후입') tags.add('추입마');

      predictions.add(Prediction(
        horseNo: entry.horseNo,
        horseName: entry.horseName,
        jockeyName: entry.jockeyName,
        winProbability: double.parse(winProb.toStringAsFixed(2)),
        placeProbability: double.parse(placeProb.toStringAsFixed(2)),
        tags: tags,
        featureImportance: {
          'rating': entry.rating,
          'win_rate': entry.winRate,
          'pace_score': style == '선행' ? 4.0 : style == '선입' ? 3.0 : style == '중단' ? 2.0 : 1.0,
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
      modelVersion: 'heuristic-2.0',
      generatedAt: DateTime.now(),
    );
  }
}
