/// 출마표 항목별 as-of 시계열 피처.
///
/// `race_results` 의 과거 이력만으로 기수·조교사 입상률, 마·기수 조합,
/// 최근 폼, 거리 적성·체중 변화, 통과순위 주행유형을 환산합니다.
/// 모든 집계는 대상 경주일 **이전** 데이터만 사용해 결과 누출을 막습니다.
///
/// 같은 계산이 `backend/entry_features.py` 에도 있으므로 공식을 바꿀 때는
/// 양쪽을 함께 수정해야 합니다.
library;

import '../constants/prediction_constants.dart';

/// 기수·조교사 집계 창(일)과 베이지안 prior 표본 수.
const int jockeyWindowDays = 365;
const double jockeyPriorSamples = 20.0;
const int trainerWindowDays = 365;
const double trainerPriorSamples = 20.0;

/// 마·기수 조합. 365일 창 표본이 이보다 적으면 전 기간을 씁니다.
const int comboWindowDays = 365;
const double comboPriorSamples = 20.0;
const int comboMinWindowSamples = 3;

/// 최근 폼에 반영할 직전 경주 수.
const int recentFormRaces = 5;

/// 주행 유형: 직전 경주 통과순위 표본. 이보다 적으면 레이팅 휴리스틱으로 넘깁니다.
const int runningStyleRaces = 5;
const int runningStyleMinSamples = 2;
const List<String> _knownRunningStyles = ['선행', '선입', '중단', '추입'];
final RegExp _passOrderSplit = RegExp(r'[-–—,/\s]+');
final RegExp _nonDigit = RegExp(r'[^\d]');

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
  final double trainer;
  final double combo;
  final double speed;
  final double burden;
  final double gate;
  final String runningStyle;

  const EntryFeatureScores({
    required this.jockey,
    required this.recentForm,
    required this.fitness,
    required this.trainer,
    required this.combo,
    this.speed = neutralFeatureScore,
    this.burden = neutralFeatureScore,
    this.gate = neutralFeatureScore,
    this.runningStyle = '',
  });

  static const neutral = EntryFeatureScores(
    jockey: neutralFeatureScore,
    recentForm: neutralFeatureScore,
    fitness: neutralFeatureScore,
    trainer: neutralFeatureScore,
    combo: neutralFeatureScore,
    speed: neutralFeatureScore,
    burden: neutralFeatureScore,
    gate: neutralFeatureScore,
    runningStyle: '',
  );
}

/// 과거 경주 한 건의 최소 정보.
class PastRunRecord {
  final String raceDate;
  final int raceNo;
  final String meet;
  final String horseName;
  final String jockeyName;
  final String trainerName;
  final int rank;
  final int fieldSize;
  final int distance;
  final String raceTime;
  final double carriedWeight;
  final double horseWeight;
  final String passOrder;

  const PastRunRecord({
    required this.raceDate,
    required this.raceNo,
    this.meet = '',
    required this.horseName,
    required this.jockeyName,
    this.trainerName = '',
    required this.rank,
    required this.fieldSize,
    required this.distance,
    this.raceTime = '',
    this.carriedWeight = 0,
    required this.horseWeight,
    this.passOrder = '',
  });

  bool get placed => rank >= 1 && rank <= PredictionConstants.placeSlots;

  /// 1착이면 1.0, 꼴찌면 0.0 이 되는 착순 백분위.
  double get finishQuality {
    if (rank <= 0 || fieldSize <= 1) return neutralFeatureScore;
    return _clamp01(1.0 - ((rank - 1) / (fieldSize - 1)));
  }
}

double _clamp01(double value) => value.clamp(0.0, 1.0).toDouble();

/// KRA `M:SS.s` 또는 초 단위 경주기록을 초로 변환합니다.
double parseRaceTimeSeconds(String value) {
  final text = value.trim();
  if (text.isEmpty) return 0;
  if (!text.contains(':')) {
    final seconds = double.tryParse(text) ?? 0;
    return seconds > 0 ? seconds : 0;
  }
  final parts = text.split(':');
  if (parts.length != 2) return 0;
  final minutes = double.tryParse(parts[0]);
  final seconds = double.tryParse(parts[1]);
  if (minutes == null || seconds == null) return 0;
  final total = (minutes * 60) + seconds;
  return total > 0 ? total : 0;
}

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
  return weightSum > 0 ? _clamp01(weighted / weightSum) : neutralFeatureScore;
}

String? _comboKey(String horseName, String jockeyName) {
  final horse = horseName.trim();
  final jockey = jockeyName.trim();
  if (horse.isEmpty || jockey.isEmpty) return null;
  return '$horse\u001f$jockey';
}

/// 통과순위에서 선행/선입/중단/추입을 읽습니다. 모르면 빈 문자열.
///
/// `1-1-1-1`, `8-7-5-3` 처럼 첫 구간 위치를 두수 대비 비율로 봅니다.
/// 문자열에 한글 유형이 있으면 숫자보다 우선합니다.
String parsePassOrderStyle(String passOrder, int fieldSize) {
  final text = passOrder.trim();
  if (text.isEmpty) return '';
  for (final label in _knownRunningStyles) {
    if (text.contains(label)) return label;
  }

  int? first;
  for (final part in text.split(_passOrderSplit)) {
    final digits = part.replaceAll(_nonDigit, '');
    if (digits.isEmpty) continue;
    final value = int.tryParse(digits);
    if (value != null && value > 0) {
      first = value;
      break;
    }
  }
  if (first == null) return '';
  if (first <= 2) return '선행';
  if (fieldSize <= 1) return '';
  final ratio = first / fieldSize;
  if (ratio <= 0.25) return '선행';
  if (ratio <= 0.45) return '선입';
  if (ratio <= 0.70) return '중단';
  return '추입';
}

/// 직전 최대 5경주 통과순위의 최빈 유형. 유효 표본이 2건 미만이면 빈 문자열.
String runningStyleFromRecords(List<PastRunRecord> records) {
  if (records.isEmpty) return '';
  final window = records.length > runningStyleRaces
      ? records.sublist(records.length - runningStyleRaces)
      : records;
  final styles = <String>[];
  for (var i = window.length - 1; i >= 0; i--) {
    final style = parsePassOrderStyle(window[i].passOrder, window[i].fieldSize);
    if (style.isNotEmpty) styles.add(style);
  }
  if (styles.length < runningStyleMinSamples) return '';

  final counts = <String, int>{};
  for (final style in styles) {
    counts[style] = (counts[style] ?? 0) + 1;
  }
  final best = counts.values.reduce((a, b) => a > b ? a : b);
  for (final style in styles) {
    if (counts[style] == best) return style;
  }
  return '';
}

/// 경주일 이전 이력만 조회하도록 정렬해 둔 과거 성적 인덱스.
class AsOfFeatureIndex {
  final Map<String, List<PastRunRecord>> _byHorse;
  final Map<String, List<PastRunRecord>> _byJockey;
  final Map<String, List<PastRunRecord>> _byTrainer;
  final Map<String, List<PastRunRecord>> _byCombo;
  final List<PastRunRecord> _allRecords;
  final double priorPlaceRate;

  AsOfFeatureIndex._(
    this._byHorse,
    this._byJockey,
    this._byTrainer,
    this._byCombo,
    this._allRecords,
    this.priorPlaceRate,
  );

  factory AsOfFeatureIndex(Iterable<PastRunRecord> records) {
    final byHorse = <String, List<PastRunRecord>>{};
    final byJockey = <String, List<PastRunRecord>>{};
    final byTrainer = <String, List<PastRunRecord>>{};
    final byCombo = <String, List<PastRunRecord>>{};
    final allRecords = <PastRunRecord>[];
    var placedTotal = 0;
    var recordTotal = 0;

    for (final record in records) {
      if (record.rank <= 0 || _toEpochDay(record.raceDate) == null) continue;
      allRecords.add(record);

      final horse = record.horseName.trim();
      if (horse.isNotEmpty) {
        byHorse.putIfAbsent(horse, () => []).add(record);
      }
      final jockey = record.jockeyName.trim();
      if (jockey.isNotEmpty) {
        byJockey.putIfAbsent(jockey, () => []).add(record);
      }
      final trainer = record.trainerName.trim();
      if (trainer.isNotEmpty) {
        byTrainer.putIfAbsent(trainer, () => []).add(record);
      }
      final combo = _comboKey(horse, jockey);
      if (combo != null) {
        byCombo.putIfAbsent(combo, () => []).add(record);
      }

      recordTotal++;
      if (record.placed) placedTotal++;
    }

    // 같은 날 두 번 출전해도 순서가 흔들리지 않도록 경주 번호까지 비교합니다.
    // (Dart 의 List.sort 는 안정 정렬이 아니므로 완전한 키가 필요합니다.)
    int bySchedule(PastRunRecord a, PastRunRecord b) {
      final dateCompare = a.raceDate.compareTo(b.raceDate);
      if (dateCompare != 0) return dateCompare;
      final raceCompare = a.raceNo.compareTo(b.raceNo);
      if (raceCompare != 0) return raceCompare;
      return a.meet.compareTo(b.meet);
    }

    for (final list in [
      ...byHorse.values,
      ...byJockey.values,
      ...byTrainer.values,
      ...byCombo.values,
    ]) {
      list.sort(bySchedule);
    }
    allRecords.sort(bySchedule);

    return AsOfFeatureIndex._(
      byHorse,
      byJockey,
      byTrainer,
      byCombo,
      allRecords,
      recordTotal > 0 ? placedTotal / recordTotal : defaultPriorPlaceRate,
    );
  }

  double _priorPlaceRateBefore(String cutoff) {
    final records = _before(_allRecords, cutoff);
    if (records.isEmpty) return defaultPriorPlaceRate;
    return records.where((record) => record.placed).length / records.length;
  }

  static List<PastRunRecord> _before(
    List<PastRunRecord>? records,
    String cutoff,
  ) {
    if (records == null || records.isEmpty) return const [];
    // raceDate 는 YYYYMMDD 고정 폭이라 문자열 비교가 곧 날짜 비교입니다.
    var end = 0;
    while (end < records.length &&
        records[end].raceDate.compareTo(cutoff) < 0) {
      end++;
    }
    return records.sublist(0, end);
  }

  List<PastRunRecord> horseHistory(String horseName, String cutoff) =>
      _before(_byHorse[horseName.trim()], cutoff);

  List<PastRunRecord> jockeyHistory(String jockeyName, String cutoff) =>
      _before(_byJockey[jockeyName.trim()], cutoff);

  List<PastRunRecord> trainerHistory(String trainerName, String cutoff) =>
      _before(_byTrainer[trainerName.trim()], cutoff);

  List<PastRunRecord> comboHistory(
    String horseName,
    String jockeyName,
    String cutoff,
  ) {
    final key = _comboKey(horseName, jockeyName);
    if (key == null) return const [];
    return _before(_byCombo[key], cutoff);
  }

  double _windowedPlaceScore(
    List<PastRunRecord> history,
    String cutoff,
    int windowDays,
    double priorSamples, {
    bool fallbackToAll = false,
    int minWindowSamples = 1,
  }) {
    if (history.isEmpty) return neutralFeatureScore;
    final cutoffDay = _toEpochDay(cutoff);
    if (cutoffDay == null) return neutralFeatureScore;
    final windowStart = cutoffDay - windowDays;

    var recent = history.where((r) {
      final day = _toEpochDay(r.raceDate);
      return day != null && day >= windowStart;
    }).toList();
    if (recent.isEmpty) {
      if (!fallbackToAll) return neutralFeatureScore;
      recent = history;
    } else if (fallbackToAll && recent.length < minWindowSamples) {
      recent = history;
    }

    final prior = _priorPlaceRateBefore(cutoff);
    final rate = _smoothedPlaceRate(recent, prior, priorSamples);
    return _relativeToPrior(rate, prior);
  }

  double jockeyScore(String jockeyName, String cutoff, [String meet = '']) {
    final history = jockeyHistory(jockeyName, cutoff);
    final venue = meet.isEmpty
        ? const <PastRunRecord>[]
        : history.where((record) => record.meet == meet).toList();
    return _windowedPlaceScore(
      venue.length >= 3 ? venue : history,
      cutoff,
      jockeyWindowDays,
      jockeyPriorSamples,
    );
  }

  double trainerScore(String trainerName, String cutoff, [String meet = '']) {
    final history = trainerHistory(trainerName, cutoff);
    final venue = meet.isEmpty
        ? const <PastRunRecord>[]
        : history.where((record) => record.meet == meet).toList();
    return _windowedPlaceScore(
      venue.length >= 3 ? venue : history,
      cutoff,
      trainerWindowDays,
      trainerPriorSamples,
    );
  }

  double comboScore(String horseName, String jockeyName, String cutoff) =>
      _windowedPlaceScore(
        comboHistory(horseName, jockeyName, cutoff),
        cutoff,
        comboWindowDays,
        comboPriorSamples,
        fallbackToAll: true,
        minWindowSamples: comboMinWindowSamples,
      );

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

    final prior = _priorPlaceRateBefore(cutoff);
    final distanceScore = sameBand.isNotEmpty
        ? _relativeToPrior(
            _smoothedPlaceRate(sameBand, prior, distancePriorSamples),
            prior,
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

  String runningStyleFor(String horseName, String cutoff) =>
      runningStyleFromRecords(horseHistory(horseName, cutoff));

  double speedScore(String horseName, String cutoff, [String meet = '']) {
    final history = horseHistory(horseName, cutoff);
    final venue = history
        .where(
          (record) =>
              meet.isNotEmpty &&
              record.meet == meet &&
              parseRaceTimeSeconds(record.raceTime) > 0 &&
              record.distance > 0,
        )
        .toList();
    final valid = venue.length >= 2
        ? venue
        : history
              .where(
                (record) =>
                    parseRaceTimeSeconds(record.raceTime) > 0 &&
                    record.distance > 0,
              )
              .toList();
    if (valid.isEmpty) return neutralFeatureScore;
    final window = valid.length > 5 ? valid.sublist(valid.length - 5) : valid;
    final average =
        window.fold<double>(
          0,
          (sum, record) =>
              sum +
              (parseRaceTimeSeconds(record.raceTime) /
                  (record.distance / 100.0)),
        ) /
        window.length;
    return _clamp01(0.5 + ((6.5 - average) / 2.0));
  }

  double burdenScore(
    String horseName,
    String cutoff,
    double carriedWeight,
    double horseWeight,
  ) {
    final history = horseHistory(horseName, cutoff);
    double? previous;
    for (var i = history.length - 1; i >= 0; i--) {
      if (history[i].carriedWeight > 0) {
        previous = history[i].carriedWeight;
        break;
      }
    }
    final deltaScore = previous == null || carriedWeight <= 0
        ? neutralFeatureScore
        : _clamp01(0.75 - ((carriedWeight - previous) * 0.12));
    final ratioScore = carriedWeight > 0 && horseWeight > 0
        ? _clamp01(0.5 + ((0.12 - (carriedWeight / horseWeight)) / 0.04))
        : neutralFeatureScore;
    return _clamp01((deltaScore * 0.45) + (ratioScore * 0.55));
  }

  static double gateScore(int horseNo, int fieldSize) {
    if (horseNo <= 0 || fieldSize <= 1) return neutralFeatureScore;
    return _clamp01(1.0 - ((horseNo - 1) / (fieldSize - 1)));
  }

  EntryFeatureScores featuresFor({
    required String raceDate,
    String meet = '',
    required String horseName,
    required String jockeyName,
    String trainerName = '',
    required int distance,
    double carriedWeight = 0,
    required double horseWeight,
    int horseNo = 0,
    int fieldSize = 0,
  }) {
    if (_toEpochDay(raceDate) == null) return EntryFeatureScores.neutral;
    return EntryFeatureScores(
      jockey: jockeyScore(jockeyName, raceDate, meet),
      recentForm: recentFormScore(horseName, raceDate),
      fitness: fitnessScore(horseName, raceDate, distance, horseWeight),
      trainer: trainerScore(trainerName, raceDate, meet),
      combo: comboScore(horseName, jockeyName, raceDate),
      speed: speedScore(horseName, raceDate, meet),
      burden: burdenScore(horseName, raceDate, carriedWeight, horseWeight),
      gate: gateScore(horseNo, fieldSize),
      runningStyle: runningStyleFor(horseName, raceDate),
    );
  }
}
