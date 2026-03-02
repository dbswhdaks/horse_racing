class ApiConstants {
  ApiConstants._();

  static const String serviceKey =
      '788d1f62af9d665d2f002057f9526ac8f2776910fef87b0e95d27e232fe0967f';

  static const String baseUrl = 'https://apis.data.go.kr/B551015';

  static const String racePlanPath = '/API72_2/racePlan_2';
  static const String raceStartListPath = '/API26_2';
  static const String raceResultPath = '/API299';
  static const String oddInfoPath = '/API145';
  static const String horseRecordPath = '/API153';
  static const String trainerRecordPath = '/API155';
  static const String jockeyRecordPath = '/API156';
  static const String aiRaceResultPath = '/API218/aiRaceResult';

  static const String mlBackendUrl = 'http://localhost:8000';

  static const Map<String, String> meetCodes = {
    '서울': '1',
    '제주': '2',
    '부산경남': '3',
  };

  static const Map<String, String> meetNames = {
    '1': '서울',
    '2': '제주',
    '3': '부산경남',
  };
}
