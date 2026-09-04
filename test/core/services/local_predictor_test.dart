import 'package:flutter_test/flutter_test.dart';
import 'package:horse_racing/core/constants/prediction_constants.dart';
import 'package:horse_racing/core/services/local_predictor.dart';
import 'package:horse_racing/models/prediction.dart';
import 'package:horse_racing/models/race_entry.dart';

RaceEntry _entry(
  int horseNo,
  double rating,
  int wins, {
  int? places,
  int totalRaces = 10,
}) => RaceEntry(
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
  placeCount: places ?? wins,
  totalRaces: totalRaces,
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
    expect(report.modelVersion, PredictionConstants.modelVersion);
  });

  test('입상 확률 합계는 입상 슬롯 수와 같다', () {
    final report = LocalPredictor.generate(
      meet: '1',
      date: '20260813',
      raceNo: 3,
      entries: [
        _entry(1, 90, 5),
        _entry(2, 80, 3),
        _entry(3, 70, 2),
        _entry(4, 60, 1),
        _entry(5, 50, 0),
        _entry(6, 40, 0),
      ],
    );

    final total = report.predictions.fold<double>(
      0,
      (sum, prediction) => sum + prediction.placeProbability,
    );

    expect(total, closeTo(PredictionConstants.placeSlots * 100, 1.0));
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

  test('안정 입상마는 단승보다 입상 순위에서 앞선다', () {
    final report = LocalPredictor.generate(
      meet: '1',
      date: '20260904',
      raceNo: 5,
      entries: [
        _entry(1, 92, 6, places: 0),
        _entry(2, 68, 0, places: 8).copyWith(
          totalPrize: 420000,
          recentPrize: 90000,
        ),
        _entry(3, 86, 4, places: 0),
        _entry(4, 82, 3, places: 1),
        _entry(5, 60, 1, places: 0),
        _entry(6, 50, 0, places: 0),
      ],
    );

    final byWin = [...report.predictions]..sort(Prediction.compareByWinThenPlace);
    final byPlace = [...report.predictions]
      ..sort(Prediction.compareByPlaceThenWin);

    final winRankOf = {
      for (var i = 0; i < byWin.length; i++) byWin[i].horseNo: i,
    };
    final placeRankOf = {
      for (var i = 0; i < byPlace.length; i++) byPlace[i].horseNo: i,
    };

    expect(winRankOf[1]!, lessThan(winRankOf[2]!));
    expect(placeRankOf[2]!, lessThan(winRankOf[2]!));
    expect(placeRankOf[2]!, lessThan(3));
  });
}
