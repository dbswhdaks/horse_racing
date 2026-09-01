/// 출마표 항목별 as-of 시계열 피처.
///
/// `race_results` 의 과거 이력만으로 기수 입상률, 최근 폼, 거리 적성·체중 변화를
/// 0~1 서브스코어로 환산합니다. 모든 집계는 대상 경주일 **이전** 데이터만
/// 사용해 결과 누출을 막습니다.
///
/// 같은 계산이 `backend/entry_features.py` 에도 있으므로 공식을 바꿀 때는
/// 양쪽을 함께 수정해야 합니다.
library;

import '../constants/prediction_constants.dart';

/// 기수 집계 창(일)과 베이지안 prior 표본 수.
const int jockeyWindowDays = 365;
const double jockeyPriorSamples = 20.0;

/// 최근 폼에 반영할 직전 경주 수.
const int recentFormRaces = 5;

/// 거리 적성으로 묶는 범위(±m)와 prior 표본 수.
const int distanceBandMeters = 200;
const double distancePriorSamples = 6.0;

/// 피처가 없을 때 쓰는 중립값. 점수에 영향을 주지 않습니다.
const double neutralFeatureScore = 0.5;

/// 이력이 하나도 없을 때 쓰는 전체 입상률 기본값.
const double defaultPriorPlaceRate = 0.25;

class EntryFeatureScores {
  final double jockey;
  final double recentForm;
  final double fitness;

  const EntryFeatureScores({
    required this.jockey,
    required this.recentForm,
    required this.fitness,
  });

  static const neutral = EntryFeatureScores(
    jockey: neutralFeatureScore,
    recentForm: neutralFeatureScore,
    fitness: neutralFeatureScore,
  );
}

/// 과거 경주 한 건의 최소 정보.
class PastRunRecord {
  final String raceDate;
  final int raceNo;
  final String horseName;
  final String jockeyName;
  final int rank;
  final int fieldSize;
  final int distance;
  final double horseWeight;

  const PastRunRecord({
    required this.raceDate,
    required this.raceNo,
    required this.horseName,
    required this.jockeyName,
    required this.rank,
    required this.fieldSize,
    required this.distance,
    required this.horseWeight,
  });

  bool get placed => rank >= 1 && rank <= PredictionConstants.placeSlots;

  /// 1착이면 1.0, 꼴찌면 0.0 이 되는 착순 백분위.
  double get finishQuality {
    if (rank <= 0 || fieldSize <= 1) return neutralFeatureScore;
    return _clamp01(1.0 - ((rank - 1) / (fieldSize - 1)));
  }
}

double _clamp01(double value) => value.clamp(0.0, 1.0).toDouble();

/// `YYYYMMDD` 를 일 단위 정수로 바꿉니다. 형식이 어긋나면 null.
int? _toEpochDay(String raceDate) {
  final text = raceDate.trim();
  if (text.length != 8) return null;
  final year = int.tryParse(text.substring(0, 4));
  final month = int.tryParse(text.substring(4, 6));
  final day = int.tryParse(text.substring(6, 8));
  if (year == null || month == null || day == null) return null;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return DateTime.utc(year, month, day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
}

/// 비율을 전체 평균 대비 0~1 점수로 환산합니다.
///
/// 평균과 같으면 0.5, 평균의 두 배 이상이면 1.0, 0이면 0.0 이 됩니다.
/// 경마장·두수 분포가 달라져도 스스로 보정되도록 절대 임계값을 쓰지 않습니다.
double _relativeToPrior(double rate, double priorRate) {
  if (priorRate <= 0) return neutralFeatureScore;
  return _clamp01(0.5 + ((rate - priorRate) / (2.0 * priorRate)));
}

double _smoothedPlaceRate(
  List<PastRunRecord> records,
  double priorRate,
  double priorSamples,
) {
  final hits = records.where((r) => r.placed).length;
  return (hits + (priorRate * priorSamples)) / (records.length + priorSamples);
}

/// 휴양 기간 점수. 너무 촘촘하거나 너무 오래 쉬면 감점합니다.
double _restScore(int? daysSinceLast) {
  if (daysSinceLast == null) return neutralFeatureScore;
  if (daysSinceLast >= 14 && daysSinceLast <= 60) return 1.0;
  if ((daysSinceLast >= 7 && daysSinceLast < 14) ||
      (daysSinceLast > 60 && daysSinceLast <= 120)) {
    return 0.8;
  }
  return 0.5;
}

/// 직전 경주 대비 마체중 변화 점수. 변동이 클수록 감점합니다.
double _weightChangeScore(double current, double? previous) {
  if (previous == null || current <= 0 || previous <= 0) return 0.6;
  final delta = (current - previous).abs();
  if (delta <= 4) return 1.0;
  if (delta <= 8) return 0.7;
  if (delta <= 12) return 0.4;
  return 0.2;
}

/// 최근 2경주 성적이 그 이전 3경주보다 좋아졌는지.
double _trendScore(List<PastRunRecord> records) {
  if (records.length < 3) return neutralFeatureScore;
  final recent = records.sublist(records.length - 2);
  final earlier = records.sublist(
    records.length > recentFormRaces ? records.length - recentFormRaces : 0,
    records.length - 2,
  );
  if (earlier.isEmpty) return neutralFeatureScore;

  final recentAvg =
      recent.fold<double>(0, (a, r) => a + r.finishQuality) / recent.length;
  final earlierAvg =
      earlier.fold<double>(0, (a, r) => a + r.finishQuality) / earlier.length;
  return _clamp01(0.5 + ((recentAvg - earlierAvg) / 2.0));
}

/// 최근 경주일수록 크게 반영하는 착순 백분위 평균.
double _weightedFinishQuality(List<PastRunRecord> records) {
  if (records.isEmpty) return neutralFeatureScore;
  var weighted = 0.0;
  var weightSum = 0.0;
  for (var offset = 1; offset <= records.length; offset++) {
    final record = records[records.length - offset];
    final weight = 1.0 / offset;
    weighted += record.finishQuality * weight;
    weightSum += weight;
  }
  return weightSum > 0
      ? _clamp01(weighted / weightSum)
      : neutralFeatureScore;
}

/// 경주일 이전 이력만 조회하도록 정렬해 둔 과거 성적 인덱스.
class AsOfFeatureIndex {
  final Map<String, List<PastRunRecord>> _byHorse;
  final Map<String, List<PastRunRecord>> _byJockey;
  final double priorPlaceRate;

  AsOfFeatureIndex._(this._byHorse, this._byJockey, this.priorPlaceRate);

  factory AsOfFeatureIndex(Iterable<PastRunRecord> records) {
    final byHorse = <String, List<PastRunRecord>>{};
    final byJockey = <String, List<PastRunRecord>>{};
    var placedTotal = 0;
    var recordTotal = 0;

    for (final record in records) {
      if (record.rank <= 0 || _toEpochDay(record.raceDate) == null) continue;

      final horse = record.horseName.trim();
      if (horse.isNotEmpty) {
        byHorse.putIfAbsent(horse, () => []).add(record);
      }
      final jockey = record.jockeyName.trim();
      if (jockey.isNotEmpty) {
        byJockey.putIfAbsent(jockey, () => []).add(record);
      }

      recordTotal++;
      if (record.placed) placedTotal++;
    }

    // 같은 날 두 번 출전해도 순서가 흔들리지 않도록 경주 번호까지 비교합니다.
    // (Dart 의 List.sort 는 안정 정렬이 아니므로 완전한 키가 필요합니다.)
    int bySchedule(PastRunRecord a, PastRunRecord b) {
      final dateCompare = a.raceDate.compareTo(b.raceDate);
      if (dateCompare != 0) return dateCompare;
      return a.raceNo.compareTo(b.raceNo);
    }

    for (final list in byHorse.values) {
      list.sort(bySchedule);
    }
    for (final list in byJockey.values) {
      list.sort(bySchedule);
    }

    return AsOfFeatureIndex._(
      byHorse,
      byJockey,
      recordTotal > 0 ? placedTotal / recordTotal : defaultPriorPlaceRate,
    );
  }

  static List<PastRunRecord> _before(
    List<PastRunRecord>? records,
    String cutoff,
  ) {
    if (records == null || records.isEmpty) return const [];
    // raceDate 는 YYYYMMDD 고정 폭이라 문자열 비교가 곧 날짜 비교입니다.
    var end = 0;
    while (end < records.length && records[end].raceDate.compareTo(cutoff) < 0) {
      end++;
    }
    return records.sublist(0, end);
  }

  List<PastRunRecord> horseHistory(String horseName, String cutoff) =>
      _before(_byHorse[horseName.trim()], cutoff);

  List<PastRunRecord> jockeyHistory(String jockeyName, String cutoff) =>
      _before(_byJockey[jockeyName.trim()], cutoff);

  double jockeyScore(String jockeyName, String cutoff) {
    final history = jockeyHistory(jockeyName, cutoff);
    if (history.isEmpty) return neutralFeatureScore;

    final cutoffDay = _toEpochDay(cutoff);
    if (cutoffDay == null) return neutralFeatureScore;
    final windowStart = cutoffDay - jockeyWindowDays;

    final recent = history.where((r) {
      final day = _toEpochDay(r.raceDate);
      return day != null && day >= windowStart;
    }).toList();
    if (recent.isEmpty) return neutralFeatureScore;

    final rate = _smoothedPlaceRate(recent, priorPlaceRate, jockeyPriorSamples);
    return _relativeToPrior(rate, priorPlaceRate);
  }

  double recentFormScore(String horseName, String cutoff) {
    final history = horseHistory(horseName, cutoff);
    if (history.isEmpty) return neutralFeatureScore;

    final window = history.length > recentFormRaces
        ? history.sublist(history.length - recentFormRaces)
        : history;

    final cutoffDay = _toEpochDay(cutoff);
    final lastDay = _toEpochDay(history.last.raceDate);
    final daysSince = (cutoffDay != null && lastDay != null)
        ? cutoffDay - lastDay
        : null;

    return _clamp01(
      (_weightedFinishQuality(window) * 0.60) +
          (_trendScore(window) * 0.20) +
          (_restScore(daysSince) * 0.20),
    );
  }

  double fitnessScore(
    String horseName,
    String cutoff,
    int distance,
    double horseWeight,
  ) {
    final history = horseHistory(horseName, cutoff);
    if (history.isEmpty) return neutralFeatureScore;

    final sameBand = distance > 0
        ? history
              .where(
                (r) =>
                    r.distance > 0 &&
                    (r.distance - distance).abs() <= distanceBandMeters,
              )
              .toList()
        : <PastRunRecord>[];

    final distanceScore = sameBand.isNotEmpty
        ? _relativeToPrior(
            _smoothedPlaceRate(sameBand, priorPlaceRate, distancePriorSamples),
            priorPlaceRate,
          )
        : neutralFeatureScore;

    double? previousWeight;
    for (var i = history.length - 1; i >= 0; i--) {
      if (history[i].horseWeight > 0) {
        previousWeight = history[i].horseWeight;
        break;
      }
    }

    return _clamp01(
      (distanceScore * 0.60) +
          (_weightChangeScore(horseWeight, previousWeight) * 0.40),
    );
  }

  EntryFeatureScores featuresFor({
    required String raceDate,
    required String horseName,
    required String jockeyName,
    required int distance,
    required double horseWeight,
  }) {
    if (_toEpochDay(raceDate) == null) return EntryFeatureScores.neutral;
    return EntryFeatureScores(
      jockey: jockeyScore(jockeyName, raceDate),
      recentForm: recentFormScore(horseName, raceDate),
      fitness: fitnessScore(horseName, raceDate, distance, horseWeight),
    );
  }
}
