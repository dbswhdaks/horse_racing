import 'dart:math';
import '../../models/prediction.dart';
import '../../models/race_entry.dart';

/// heuristic-3.0: 개선된 종합 분석 기반 로컬 예측
/// 점수 차이를 극대화하여 실제 경마에 가까운 승률 분포를 생성
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
        modelVersion: 'heuristic-3.0',
        generatedAt: DateTime.now(),
      );
    }

    final predictions = <Prediction>[];

    final maxRating = entries.map((e) => e.rating).reduce(max);
    final minRating = entries.map((e) => e.rating).reduce(min);
    final avgRating = entries.map((e) => e.rating).fold(0.0, (a, b) => a + b) / entries.length;
    final maxPrize = entries.map((e) => e.totalPrize).reduce(max);
    final maxRecentPrize = entries.map((e) => e.recentPrize).reduce(max);

    final styles = _analyzeRunningStyles(entries);
    final frontCount = styles.values.where((s) => s == '선행' || s == '선입').length;
    final pacePressure = frontCount >= 4;

    final rawScores = <double>[];

    for (final entry in entries) {
      final style = styles[entry.horseNo] ?? '중단';
      double score = 0;

      // 1. 레이팅 (40점) - 지수함수로 상위마 크게 우대
      if (maxRating > minRating) {
        final normalized = (entry.rating - minRating) / (maxRating - minRating);
        score += pow(normalized, 1.5).toDouble() * 40;
      } else {
        score += 20;
      }

      // 2. 승률 + 입상률 (30점) - 실전 성적 중시
      if (entry.totalRaces >= 3) {
        final wr = entry.winRate.clamp(0, 50);
        final pr = entry.placeRate.clamp(0, 80);
        score += (wr / 50) * 18 + (pr / 80) * 12;
      } else if (entry.totalRaces > 0) {
        score += entry.placeRate > 0 ? 10 : 5;
      } else {
        score += 3;
      }

      // 3. 상금 (20점) - 총상금 + 최근상금
      if (maxPrize > 0) {
        score += (entry.totalPrize / maxPrize) * 10;
      }
      if (maxRecentPrize > 0) {
        score += (entry.recentPrize / maxRecentPrize) * 10;
      }

      // 4. 전개 적합도 (10점)
      if (pacePressure && (style == '추입' || style == '중단')) {
        score += 10;
      } else if (!pacePressure && (style == '선행' || style == '선입')) {
        score += 10;
      } else {
        score += 5;
      }

      // 5. 컨디션 보정 (최대 8점)
      if (entry.age >= 3 && entry.age <= 5) score += 3;
      if (entry.weight >= 52 && entry.weight <= 56) score += 2;
      if (entry.winCount >= 2 && entry.totalRaces >= 5) score += 3;

      rawScores.add(max(score, 1));
    }

    // 소프트맥스로 확률 분포 생성 (temperature로 차이 강조)
    final temperature = _calcTemperature(entries.length);
    final expScores = rawScores.map((s) => exp(s / temperature)).toList();
    final sumExp = expScores.fold(0.0, (a, b) => a + b);
    final probabilities = expScores.map((e) => (e / sumExp) * 100).toList();

    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final style = styles[entry.horseNo] ?? '중단';
      final winProb = probabilities[i];
      final placeProb = _calcPlaceProb(winProb, entries.length);

      final tags = _generateTags(entry, style, winProb, avgRating, pacePressure);

      predictions.add(Prediction(
        horseNo: entry.horseNo,
        horseName: entry.horseName,
        jockeyName: entry.jockeyName,
        winProbability: double.parse(winProb.toStringAsFixed(1)),
        placeProbability: double.parse(placeProb.toStringAsFixed(1)),
        tags: tags,
        featureImportance: {
          'rating': entry.rating,
          'win_rate': entry.winRate,
          'place_rate': entry.placeRate,
          'prize': entry.totalPrize.toDouble(),
          'recent_prize': entry.recentPrize.toDouble(),
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
      modelVersion: 'heuristic-3.0',
      generatedAt: DateTime.now(),
    );
  }

  static double _calcTemperature(int horseCount) {
    if (horseCount <= 6) return 8.0;
    if (horseCount <= 10) return 10.0;
    return 12.0;
  }

  static double _calcPlaceProb(double winProb, int horseCount) {
    final base = winProb * 2.2;
    final boost = horseCount >= 10 ? 8 : 5;
    return (base + boost).clamp(5, 95);
  }

  static Map<int, String> _analyzeRunningStyles(List<RaceEntry> entries) {
    final result = <int, String>{};
    for (final e in entries) {
      if (e.rating >= 85 && e.winRate >= 20) {
        result[e.horseNo] = '선행';
      } else if (e.rating >= 70 && e.winRate >= 10) {
        result[e.horseNo] = '선입';
      } else if (e.rating < 50 || (e.totalRaces >= 5 && e.winRate < 5)) {
        result[e.horseNo] = '추입';
      } else {
        result[e.horseNo] = '중단';
      }
    }
    return result;
  }

  static List<String> _generateTags(
    RaceEntry entry,
    String style,
    double winProb,
    double avgRating,
    bool pacePressure,
  ) {
    final tags = <String>[];
    if (entry.rating >= avgRating * 1.15) tags.add('고레이팅');
    if (entry.winRate >= 20) tags.add('고승률');
    if (entry.placeRate >= 40 && entry.winRate < 20) tags.add('안정입상');
    if (entry.totalRaces >= 15) tags.add('경험마');
    if (entry.recentPrize > 300000) tags.add('최근호조');
    if (winProb >= 20) {
      tags.add('강력후보');
    } else if (winProb >= 12) {
      tags.add('유력후보');
    }

    if (pacePressure && (style == '추입' || style == '중단')) {
      tags.add('전개유리');
    } else if (!pacePressure && (style == '선행' || style == '선입')) {
      tags.add('전개유리');
    }

    if (style == '선행') tags.add('선행마');
    if (style == '추입') tags.add('추입마');

    return tags;
  }
}
