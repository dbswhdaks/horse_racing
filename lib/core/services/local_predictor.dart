import 'dart:math';
import '../../models/odds.dart';
import '../../models/prediction.dart';
import '../../models/race_entry.dart';

/// heuristic-3.1: 표본 보정 기반 로컬 예측
/// 점수 차이를 극대화하여 실제 경마에 가까운 승률 분포를 생성
class LocalPredictor {
  /// `heuristic-place-1.1`부터 단승(WIN) 배당(있다면)을 점수에 섞습니다.
  static const modelVersion = 'heuristic-place-1.1';
  static const _params = _HeuristicParams(
    wRating: 0.324359,
    wPerformance: 0.371729,
    wClassForm: 0.020350,
    wPace: 0.005776,
    wCondition: 0.277786,
    ratingPow: 2.614967,
    priorWeight: 7.375545,
    tempScale: 1.595725,
    reliabilityPenalty: 0.174242,
  );
  static const _wMarket = 0.12;

  static PredictionReport generate({
    required String meet,
    required String date,
    required int raceNo,
    required List<RaceEntry> entries,
    List<Odds> odds = const [],
  }) {
    if (entries.isEmpty) {
      return PredictionReport(
        raceId: '${meet}_${date}_$raceNo',
        raceDate: date,
        meet: meet,
        raceNo: raceNo,
        predictions: [],
        modelVersion: modelVersion,
        generatedAt: DateTime.now(),
      );
    }

    final predictions = <Prediction>[];

    final maxRating = entries.map((e) => e.rating).reduce(max);
    final minRating = entries.map((e) => e.rating).reduce(min);
    final avgRating =
        entries.map((e) => e.rating).fold(0.0, (a, b) => a + b) /
        entries.length;
    final maxPrize = entries.map((e) => e.totalPrize.toDouble()).reduce(max);
    final minPrize = entries.map((e) => e.totalPrize.toDouble()).reduce(min);
    final maxRecentPrize = entries
        .map((e) => e.recentPrize.toDouble())
        .reduce(max);
    final minRecentPrize = entries
        .map((e) => e.recentPrize.toDouble())
        .reduce(min);
    final avgWinRate =
        entries.map((e) => e.winRate).fold(0.0, (a, b) => a + b) /
        entries.length;
    final avgPlaceRate =
        entries.map((e) => e.placeRate).fold(0.0, (a, b) => a + b) /
        entries.length;
    final maxHorseWeight = entries.map((e) => e.horseWeight).reduce(max);
    final minHorseWeight = entries.map((e) => e.horseWeight).reduce(min);

    final styles = _analyzeRunningStyles(entries);
    final frontCount = styles.values
        .where((s) => s == '선행' || s == '선입')
        .length;
    final pacePressure = frontCount >= 4;

    final rawScores = <double>[];
    final scoreByHorseNo = <int, double>{};
    final featureImportanceByHorseNo = <int, Map<String, double>>{};

    final marketByHorse = _marketComponentsFromWinOdds(
      odds: odds,
      entryHorseNos: entries.map((e) => e.horseNo).toSet(),
    );
    final marketWeight = _effectiveMarketWeight(
      fieldSize: entries.length,
      marketByHorse: marketByHorse,
    );

    for (final entry in entries) {
      final style = styles[entry.horseNo] ?? '중단';
      // 튜닝 스크립트와 같은 0~1 항목 점수를 만든 뒤 Top3 지표에 맞춘 가중합을 적용합니다.
      final ratingNorm = _normalize(entry.rating, minRating, maxRating);
      final ratingScore = pow(ratingNorm, _params.ratingPow).toDouble();

      final raceSamples = entry.totalRaces.toDouble();
      final smoothWinRate =
          ((entry.winRate * raceSamples) + (avgWinRate * _params.priorWeight)) /
          (raceSamples + _params.priorWeight);
      final smoothPlaceRate =
          ((entry.placeRate * raceSamples) +
              (avgPlaceRate * _params.priorWeight)) /
          (raceSamples + _params.priorWeight);
      final consistency = max(smoothPlaceRate - smoothWinRate, 0.0);
      final performanceScore =
          ((smoothWinRate.clamp(0, 40) / 40) * 0.48) +
          ((smoothPlaceRate.clamp(0, 75) / 75) * 0.42) +
          ((consistency.clamp(0, 35) / 35) * 0.10);

      final prizeLog = log(max(entry.totalPrize.toDouble(), 0) + 1);
      final minPrizeLog = log(max(minPrize, 0) + 1);
      final maxPrizeLog = log(max(maxPrize, 0) + 1);
      final prizeScore = _normalize(prizeLog, minPrizeLog, maxPrizeLog);

      final recentPrizeLog = log(max(entry.recentPrize.toDouble(), 0) + 1);
      final minRecentPrizeLog = log(max(minRecentPrize, 0) + 1);
      final maxRecentPrizeLog = log(max(maxRecentPrize, 0) + 1);
      final recentPrizeScore = _normalize(
        recentPrizeLog,
        minRecentPrizeLog,
        maxRecentPrizeLog,
      );

      final classFormScore = (prizeScore * 0.45) + (recentPrizeScore * 0.55);

      final paceScore = _paceScore(
        style: style,
        pacePressure: pacePressure,
        frontCount: frontCount,
      );

      final conditionScore = _conditionScore(
        entry,
        minHorseWeight,
        maxHorseWeight,
      );

      final base0to1 =
          (ratingScore * _params.wRating) +
          (performanceScore * _params.wPerformance) +
          (classFormScore * _params.wClassForm) +
          (paceScore * _params.wPace) +
          (conditionScore * _params.wCondition);

      final marketComp = marketByHorse[entry.horseNo] ?? 0.5;
      final s = 1.0 - _wMarket;
      final scaledBase = base0to1 * s;
      final blended0to1 = marketWeight > 0
          ? (scaledBase + (marketComp * marketWeight))
          : base0to1;
      double score = blended0to1 * 100.0;

      final reliability = _sampleReliability(entry.totalRaces);
      final reliabilityScale =
          1 - ((1 - reliability) * _params.reliabilityPenalty);
      score = (score * reliabilityScale).clamp(1, 120).toDouble();

      rawScores.add(score);
      scoreByHorseNo[entry.horseNo] = score;
      featureImportanceByHorseNo[entry.horseNo] = {
        'rating': ratingScore * 100,
        'win_rate': smoothWinRate.clamp(0, 100).toDouble(),
        'place_rate': smoothPlaceRate.clamp(0, 100).toDouble(),
        'prize': prizeScore * 100,
        'recent_prize': recentPrizeScore * 100,
        'market': marketComp * 100.0,
      };
    }

    // 안정적 소프트맥스: max-shift + 동적 temperature
    final maxRaw = rawScores.reduce(max);
    final minRaw = rawScores.reduce(min);
    final spread = maxRaw - minRaw;
    final temperature = _calcTemperature(entries.length, spread);
    final expScores = rawScores
        .map((s) => exp((s - maxRaw) / temperature))
        .toList();
    final sumExp = expScores.fold(0.0, (a, b) => a + b);
    final probabilities = expScores.map((e) => (e / sumExp) * 100).toList();

    final rankedHorseNos =
        List.generate(entries.length, (i) => entries[i].horseNo)..sort((a, b) {
          final scoreCompare = (scoreByHorseNo[b] ?? 0).compareTo(
            scoreByHorseNo[a] ?? 0,
          );
          if (scoreCompare != 0) return scoreCompare;
          return a.compareTo(b);
        });

    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final style = styles[entry.horseNo] ?? '중단';
      final winProb = probabilities[i];
      final rank = rankedHorseNos.indexOf(entry.horseNo) + 1;
      final placeProb = _calcPlaceProb(
        winProb: winProb,
        horseCount: entries.length,
        rank: rank,
      );

      final tags = _generateTags(
        entry,
        style,
        winProb,
        placeProb,
        avgRating,
        pacePressure,
      );

      predictions.add(
        Prediction(
          horseNo: entry.horseNo,
          horseName: entry.horseName,
          jockeyName: entry.jockeyName,
          winProbability: double.parse(winProb.toStringAsFixed(1)),
          placeProbability: double.parse(placeProb.toStringAsFixed(1)),
          tags: tags,
          featureImportance: featureImportanceByHorseNo[entry.horseNo] ?? {},
        ),
      );
    }

    predictions.sort((a, b) {
      final winCompare = b.winProbability.compareTo(a.winProbability);
      if (winCompare != 0) return winCompare;
      final placeCompare = b.placeProbability.compareTo(a.placeProbability);
      if (placeCompare != 0) return placeCompare;
      final scoreCompare = (scoreByHorseNo[b.horseNo] ?? 0).compareTo(
        scoreByHorseNo[a.horseNo] ?? 0,
      );
      if (scoreCompare != 0) return scoreCompare;
      return a.horseNo.compareTo(b.horseNo);
    });

    return PredictionReport(
      raceId: '${meet}_${date}_$raceNo',
      raceDate: date,
      meet: meet,
      raceNo: raceNo,
      predictions: predictions,
      modelVersion: modelVersion,
      generatedAt: DateTime.now(),
    );
  }

  static double _calcTemperature(int horseCount, double spread) {
    final base = horseCount <= 6
        ? 6.8
        : horseCount <= 10
        ? 8.2
        : 9.3;
    final spreadFactor = spread <= 8
        ? 1.15
        : spread <= 14
        ? 1.0
        : 0.88;
    return (base * spreadFactor * _params.tempScale)
        .clamp(5.5, 11.0)
        .toDouble();
  }

  static double _calcPlaceProb({
    required double winProb,
    required int horseCount,
    required int rank,
  }) {
    final fieldBoost = horseCount >= 10 ? 8.0 : 5.0;
    final rankBoost = rank == 1
        ? 9.0
        : rank == 2
        ? 7.0
        : rank == 3
        ? 6.0
        : rank <= 5
        ? 3.0
        : 1.0;
    final placeProb = (winProb * 1.65) + fieldBoost + rankBoost;
    return placeProb.clamp(winProb + 4, 92).toDouble();
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
    double placeProb,
    double avgRating,
    bool pacePressure,
  ) {
    final tags = <String>[];
    if (entry.rating >= avgRating * 1.15) tags.add('고레이팅');
    if (entry.winRate >= 20) tags.add('고승률');
    if (entry.placeRate >= 40 && entry.winRate < 20) tags.add('안정입상');
    if (entry.totalRaces >= 15) tags.add('경험마');
    if (entry.recentPrize > 300000) tags.add('최근호조');
    if (entry.totalRaces <= 2) tags.add('표본적음');
    if (placeProb >= 45) {
      tags.add('입상강력');
    } else if (placeProb >= 35) {
      tags.add('입상유력');
    }

    if (winProb >= 20) {
      tags.add('우승후보');
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

  static double _normalize(double value, double minV, double maxV) {
    if (maxV <= minV) return 0.5;
    return ((value - minV) / (maxV - minV)).clamp(0, 1).toDouble();
  }

  static double _effectiveMarketWeight({
    required int fieldSize,
    required Map<int, double> marketByHorse,
  }) {
    if (fieldSize <= 0) return 0.0;
    if (marketByHorse.isEmpty) return 0.0;
    // 너무 적은 커버리지(일부 말만 배당이 잡힘)는 왜곡이 커서 가중을 줄입니다.
    final coverage = marketByHorse.length / fieldSize;
    if (coverage < 0.35) return 0.0;
    // 커버리지가 35~100%로 올라갈수록 시장 가중이 서서히 최대치에 도달
    return (_wMarket * coverage.clamp(0.0, 1.0));
  }

  static Map<int, double> _marketComponentsFromWinOdds({
    required List<Odds> odds,
    required Set<int> entryHorseNos,
  }) {
    final rates = <int, double>{};
    for (final o in odds) {
      if (o.betType != 'WIN' && o.betType != '1') continue;
      if (o.rate <= 0) continue;
      if (o.horseNo1 <= 0) continue;
      if (!entryHorseNos.contains(o.horseNo1)) continue;
      // 동일 말이 여러 줄로 오면(드물게) 가장 "유리한(낮은) 배당"을 사용
      final prev = rates[o.horseNo1];
      if (prev == null || o.rate < prev) {
        rates[o.horseNo1] = o.rate;
      }
    }
    if (rates.isEmpty) return {};

    var invSum = 0.0;
    for (final r in rates.values) {
      invSum += 1.0 / r;
    }
    if (invSum <= 0) return {};

    final out = <int, double>{};
    for (final e in rates.entries) {
      final implied = (1.0 / e.value) / invSum;
      out[e.key] = implied.clamp(0.0, 1.0);
    }
    return out;
  }

  static double _sampleReliability(int totalRaces) {
    if (totalRaces <= 0) return 0.0;
    return (totalRaces / 12).clamp(0, 1).toDouble();
  }

  static double _paceScore({
    required String style,
    required bool pacePressure,
    required int frontCount,
  }) {
    if (pacePressure && (style == '추입' || style == '중단')) {
      return 1.0;
    }
    if (!pacePressure && (style == '선행' || style == '선입')) {
      return 0.92;
    }
    if (frontCount <= 2 && style == '선행') return 0.84;
    if (frontCount >= 5 && style == '추입') return 0.84;
    return 0.55;
  }

  static double _conditionScore(
    RaceEntry entry,
    double minHorseWeight,
    double maxHorseWeight,
  ) {
    final ageScore = entry.age >= 3 && entry.age <= 5
        ? 1.0
        : entry.age == 6
        ? 0.65
        : 0.45;
    final burdenScore = entry.weight >= 52 && entry.weight <= 56
        ? 0.95
        : entry.weight >= 50 && entry.weight <= 57
        ? 0.62
        : 0.35;
    final bodyNorm = _normalize(
      entry.horseWeight,
      minHorseWeight,
      maxHorseWeight,
    );
    final bodyMid = (1 - ((bodyNorm - 0.5).abs() * 2)).clamp(0, 1).toDouble();
    final expBonus = entry.totalRaces >= 5 ? 0.18 : 0.0;

    return ((ageScore * 0.40) +
            (burdenScore * 0.33) +
            (bodyMid * 0.27) +
            expBonus)
        .clamp(0, 1)
        .toDouble();
  }
}

class _HeuristicParams {
  final double wRating;
  final double wPerformance;
  final double wClassForm;
  final double wPace;
  final double wCondition;
  final double ratingPow;
  final double priorWeight;
  final double tempScale;
  final double reliabilityPenalty;

  const _HeuristicParams({
    required this.wRating,
    required this.wPerformance,
    required this.wClassForm,
    required this.wPace,
    required this.wCondition,
    required this.ratingPow,
    required this.priorWeight,
    required this.tempScale,
    required this.reliabilityPenalty,
  });
}
