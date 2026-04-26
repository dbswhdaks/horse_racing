class Prediction {
  final int horseNo;
  final String horseName;
  final String jockeyName;
  final double winProbability;
  final double placeProbability;
  final List<String> tags;
  final Map<String, double> featureImportance;

  Prediction({
    required this.horseNo,
    required this.horseName,
    this.jockeyName = '',
    required this.winProbability,
    required this.placeProbability,
    required this.tags,
    required this.featureImportance,
  });

  factory Prediction.fromJson(Map<String, dynamic> json) {
    return Prediction(
      horseNo: json['horse_no'] as int? ?? 0,
      horseName: json['horse_name'] as String? ?? '',
      jockeyName: json['jockey_name'] as String? ?? '',
      winProbability: (json['win_probability'] as num?)?.toDouble() ?? 0.0,
      placeProbability: (json['place_probability'] as num?)?.toDouble() ?? 0.0,
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          [],
      featureImportance:
          (json['feature_importance'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, (v as num).toDouble()),
          ) ??
          {},
    );
  }

  /// 1위(승률) 우선, 동률 시 입상 예측·마번 — **AI 추천** 탭
  static int compareByWinThenPlace(Prediction a, Prediction b) {
    final winCompare = b.winProbability.compareTo(a.winProbability);
    if (winCompare != 0) return winCompare;
    final placeCompare = b.placeProbability.compareTo(a.placeProbability);
    if (placeCompare != 0) return placeCompare;
    return a.horseNo.compareTo(b.horseNo);
  }

  /// 입상(연승) 쪽이 높을수록 먼저, 동률 시 승률 — **종합추천** 탭
  static int compareByPlaceThenWin(Prediction a, Prediction b) {
    final placeCompare = b.placeProbability.compareTo(a.placeProbability);
    if (placeCompare != 0) return placeCompare;
    final winCompare = b.winProbability.compareTo(a.winProbability);
    if (winCompare != 0) return winCompare;
    return a.horseNo.compareTo(b.horseNo);
  }
}

class PredictionReport {
  final String raceId;
  final String raceDate;
  final String meet;
  final int raceNo;
  final List<Prediction> predictions;
  final String modelVersion;
  final DateTime generatedAt;

  PredictionReport({
    required this.raceId,
    required this.raceDate,
    required this.meet,
    required this.raceNo,
    required this.predictions,
    required this.modelVersion,
    required this.generatedAt,
  });

  factory PredictionReport.fromJson(Map<String, dynamic> json) {
    return PredictionReport(
      raceId: json['race_id'] as String? ?? '',
      raceDate: json['race_date'] as String? ?? '',
      meet: json['meet'] as String? ?? '',
      raceNo: json['race_no'] as int? ?? 0,
      predictions:
          (json['predictions'] as List<dynamic>?)
              ?.map((e) => Prediction.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      modelVersion: json['model_version'] as String? ?? '',
      generatedAt:
          DateTime.tryParse(json['generated_at'] ?? '') ?? DateTime.now(),
    );
  }
}
