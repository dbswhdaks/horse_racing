import 'dart:math';
import '../constants/prediction_constants.dart';
import '../../models/odds.dart';
import '../../models/prediction.dart';
import '../../models/race_entry.dart';
import 'entry_features.dart';

/// 표본 보정 기반 로컬 예측.
///
/// 점수 차이를 극대화해 실제 경마에 가까운 승률 분포를 만들고, 입상 확률은
/// 별도 온도의 분포에서 Harville 공식으로 유도합니다.
///
/// 가중치는 `backend/tune_heuristic_predictions.py` 튜닝 결과이며
/// `backend/export_dart_params.py` 가 자동으로 갱신합니다. 직접 수정하지 마십시오.
class LocalPredictor {
  static const modelVersion = PredictionConstants.modelVersion;
  // TUNED_PARAMS_BEGIN
  static const _params = _HeuristicParams(
    wRating: 0.253406,
    wPerformance: 0.290413,
    wClassForm: 0.015898,
    wPace: 0.004513,
    wCondition: 0.217020,
    wJockey: 0.062500,
    wRecentForm: 0.093750,
    wFitness: 0.062500,
    ratingPow: 2.614967,
    priorWeight: 7.375545,
    tempScale: 1.595725,
    placeTempScale: 1.000000,
    reliabilityPenalty: 0.174242,
  );
  // TUNED_PARAMS_END
  static const _wMarket = PredictionConstants.marketWeight;

  /// [features] 는 `SupabaseService.getEntryFeaturesBatch` 가 만든 as-of
  /// 서브스코어입니다. 비어 있으면 중립값이 쓰여 점수에 영향을 주지 않습니다.
  static PredictionReport generate({
    required String meet,
    required String date,
    required int raceNo,
    required List<RaceEntry> entries,
    List<Odds> odds = const [],
    Map<int, EntryFeatureScores> features = const {},
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
    var marketWeight = _effectiveMarketWeight(
      fieldSize: entries.length,
      marketByHorse: marketByHorse,
    );

    // 출주표(rating/totalRaces 등)가 비어 base 점수의 분산이 거의 없을 때,
    // 시장(배당) 가중을 자동으로 크게 올려 균등 분포(1/N)를 피한다.
    final fundamentalSignalAbsent =
        (maxRating - minRating).abs() < 1e-6 &&
        entries.every((e) => e.totalRaces == 0) &&
        (maxPrize - minPrize).abs() < 1e-6;
    if (fundamentalSignalAbsent && marketByHorse.length >= 2) {
      marketWeight = 0.9;
    }

    // 기초 지표·시장 신호가 모두 없으면 정직하게 1/N 확률을 표시합니다.
    final isUniformDistribution =
        fundamentalSignalAbsent && marketByHorse.length < 2;

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

      // as-of 시계열 피처. 공급되지 않으면 중립값이라 점수에 영향이 없습니다.
      final entryFeatures = features[entry.horseNo] ?? EntryFeatureScores.neutral;

      final base0to1 =
          (ratingScore * _params.wRating) +
          (performanceScore * _params.wPerformance) +
          (classFormScore * _params.wClassForm) +
          (paceScore * _params.wPace) +
          (conditionScore * _params.wCondition) +
          (entryFeatures.jockey * _params.wJockey) +
          (entryFeatures.recentForm * _params.wRecentForm) +
          (entryFeatures.fitness * _params.wFitness);

      final marketComp = marketByHorse[entry.horseNo] ?? 0.5;
      final s = (1.0 - marketWeight).clamp(0.0, 1.0);
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
        'jockey': entryFeatures.jockey * 100.0,
        'recent_form': entryFeatures.recentForm * 100.0,
        'fitness': entryFeatures.fitness * 100.0,
      };
    }

    // 안정적 소프트맥스: max-shift + 동적 temperature
    final maxRaw = rawScores.reduce(max);
    final minRaw = rawScores.reduce(min);
    final spread = maxRaw - minRaw;
    final temperature = _calcTemperature(
      entries.length,
      spread,
      _params.tempScale,
    );
    final expScores = rawScores
        .map((s) => exp((s - maxRaw) / temperature))
        .toList();
    final sumExp = expScores.fold(0.0, (a, b) => a + b);
    final probabilities = expScores.map((e) => (e / sumExp) * 100).toList();

    // 입상 확률은 단승과 다른 온도의 분포에서 Harville 공식으로 유도합니다.
    final placeTemperature = _calcTemperature(
      entries.length,
      spread,
      _params.placeTempScale,
    );
    final placeExpScores = rawScores
        .map((s) => exp((s - maxRaw) / placeTemperature))
        .toList();
    final placeProbabilities = harvillePlaceProbs(
      placeExpScores,
    ).map((v) => v * 100).toList();

    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final style = styles[entry.horseNo] ?? '중단';
      final winProb = probabilities[i];
      final placeProb = placeProbabilities[i];

      final tags = _generateTags(
        entry,
        style,
        winProb,
        placeProb,
        avgRating,
        pacePressure,
        entries.length,
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
      isUniformDistribution: isUniformDistribution,
    );
  }

  static double _calcTemperature(
    int horseCount,
    double spread,
    double scale,
  ) {
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
    return (base * spreadFactor * scale).clamp(5.5, 11.0).toDouble();
  }

  /// Harville 공식으로 단승 확률에서 입상(top-[slots]) 확률을 유도합니다.
  ///
  /// 말 i가 2착일 확률은 "j가 1착이고 남은 풀에서 i가 뽑힐 확률"의 합이며,
  /// 3착도 같은 방식으로 조건부 추출을 한 단계 더 적용합니다. 순서쌍 합을
  /// 미리 구해 O(n^2)으로 정확히 계산합니다.
  ///
  /// [weights]는 정규화되지 않아도 되며, 반환값은 0~1 스케일입니다.
  /// `backend/tune_heuristic_predictions.py` 의 `_harville_place_probs` 와
  /// 동일한 결과를 내야 합니다.
  static List<double> harvillePlaceProbs(
    List<double> weights, {
    int slots = PredictionConstants.placeSlots,
  }) {
    final n = weights.length;
    if (n == 0) return const [];
    if (n <= slots) return List<double>.filled(n, 1.0);

    final total = weights.fold(0.0, (a, b) => a + b);
    if (total <= 0) return List<double>.filled(n, slots / n);

    const eps = 1e-9;
    final p = weights.map((v) => max(v / total, 1e-12)).toList();

    final probs = List<double>.of(p);
    if (slots <= 1) return probs.map(_clamp01).toList();

    // 2착: P(i 2착) = p_i * (T - p_i/(1-p_i)),  T = sum_j p_j/(1-p_j)
    final ratio = p.map((v) => v / max(1.0 - v, eps)).toList();
    final tSum = ratio.fold(0.0, (a, b) => a + b);
    for (int i = 0; i < n; i++) {
      probs[i] += p[i] * (tSum - ratio[i]);
    }
    if (slots <= 2) return probs.map(_clamp01).toList();

    // 3착: c[j][k] = p_j * (p_k / (1 - p_j)) / (1 - p_j - p_k) 의 순서쌍 합을
    // 재사용해 P(i 3착) = p_i * (S - rowSum_i - colSum_i) 로 계산합니다.
    var pairTotal = 0.0;
    final rowSum = List<double>.filled(n, 0.0);
    final colSum = List<double>.filled(n, 0.0);
    for (int j = 0; j < n; j++) {
      final first = p[j];
      final rest = max(1.0 - first, eps);
      for (int k = 0; k < n; k++) {
        if (k == j) continue;
        final denom = max(1.0 - first - p[k], eps);
        final c = first * (p[k] / rest) / denom;
        pairTotal += c;
        rowSum[j] += c;
        colSum[k] += c;
      }
    }
    for (int i = 0; i < n; i++) {
      probs[i] += p[i] * (pairTotal - rowSum[i] - colSum[i]);
    }

    return probs.map(_clamp01).toList();
  }

  static double _clamp01(double v) => v.clamp(0.0, 1.0).toDouble();

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
    int horseCount,
  ) {
    final tags = <String>[];
    if (entry.rating >= avgRating * 1.15) tags.add('고레이팅');
    if (entry.winRate >= 20) tags.add('고승률');
    if (entry.placeRate >= 40 && entry.winRate < 20) tags.add('안정입상');
    if (entry.totalRaces >= 15) tags.add('경험마');
    if (entry.recentPrize > 300000) tags.add('최근호조');
    if (entry.totalRaces <= 2) tags.add('표본적음');

    // 입상 확률의 기준선은 두수에 따라 달라지므로(무작위 = 슬롯수/두수)
    // 고정 임계값 대신 기준선 대비 배수로 판정한다.
    final placeBaseline = horseCount > 0
        ? (PredictionConstants.placeSlots / horseCount) * 100
        : 0.0;
    if (placeBaseline > 0 && placeProb >= placeBaseline * 1.5) {
      tags.add('입상강력');
    } else if (placeBaseline > 0 && placeProb >= placeBaseline * 1.2) {
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
  final double wJockey;
  final double wRecentForm;
  final double wFitness;
  final double ratingPow;
  final double priorWeight;
  final double tempScale;
  final double placeTempScale;
  final double reliabilityPenalty;

  const _HeuristicParams({
    required this.wRating,
    required this.wPerformance,
    required this.wClassForm,
    required this.wPace,
    required this.wCondition,
    required this.wJockey,
    required this.wRecentForm,
    required this.wFitness,
    required this.ratingPow,
    required this.priorWeight,
    required this.tempScale,
    required this.placeTempScale,
    required this.reliabilityPenalty,
  });
}
