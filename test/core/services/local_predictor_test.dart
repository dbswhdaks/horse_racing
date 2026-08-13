import 'package:flutter_test/flutter_test.dart';
import 'package:horse_racing/core/services/local_predictor.dart';
import 'package:horse_racing/models/race_entry.dart';

RaceEntry _entry(int horseNo, double rating, int wins) => RaceEntry(
  horseNo: horseNo,
  horseName: '말$horseNo',
  birthPlace: '한',
  sex: '수',
  age: 4,
  jockeyName: '기수$horseNo',
  trainerName: '조교사$horseNo',
  ownerName: '',
  weight: 54,
  rating: rating,
  totalPrize: wins * 100000,
  recentPrize: wins * 10000,
  winCount: wins,
  placeCount: wins,
  totalRaces: 10,
  horseWeight: 470 + horseNo.toDouble(),
);

void main() {
  test('승률은 인위적 lift 없이 합계 100%로 유지된다', () {
    final report = LocalPredictor.generate(
      meet: '1',
      date: '20260813',
      raceNo: 1,
      entries: [
        _entry(1, 80, 3),
        _entry(2, 70, 2),
        _entry(3, 60, 1),
        _entry(4, 50, 0),
        _entry(5, 40, 0),
      ],
    );

    final total = report.predictions.fold<double>(
      0,
      (sum, prediction) => sum + prediction.winProbability,
    );

    expect(total, closeTo(100, 0.2));
    expect(report.modelVersion, 'heuristic-place-1.3');
  });

  test('정보가 없는 경주는 균등 확률로 표시된다', () {
    final entries = List.generate(
      5,
      (index) => _entry(
        index + 1,
        0,
        0,
      ).copyWith(totalRaces: 0, totalPrize: 0, recentPrize: 0, horseWeight: 0),
    );

    final report = LocalPredictor.generate(
      meet: '1',
      date: '20260813',
      raceNo: 2,
      entries: entries,
    );

    expect(report.isUniformDistribution, isTrue);
    for (final prediction in report.predictions) {
      expect(prediction.winProbability, 20);
    }
  });
}
