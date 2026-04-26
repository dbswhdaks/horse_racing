class ApiConstants {
  ApiConstants._();

  static const String serviceKey =
      '788d1f62af9d665d2f002057f9526ac8f2776910fef87b0e95d27e232fe0967f';

  static const String baseUrl = 'https://apis.data.go.kr/B551015';

  // API72_2: 경주일정 상세정보
  static const String racePlanPath = '/API72_2/racePlan_2';

  // API26_2: 출전표 상세정보
  static const String raceStartListPath = '/API26_2/entrySheet_2';

  // API155: 경주결과 (AI학습용)
  static const String raceResultPath = '/API155/raceResult';

  // API5: 복승식 확정배당율
  static const String oddInfoPath = '/API5/oddInfo';

  // API155: AI학습용 경주결과
  static const String aiRaceResultPath = '/API155/raceResult';

  // API4_3: 한국마사회 경주기록 정보 (참고: API4_3_한국마사회 경주기록 정보.docx)
  static const String api4_3RaceRecordPath = '/API4_3';

  // API16_1: 경주마 성적정보
  static const String horseRecordPath = '/API16_1/horseRecord_1';

  // racedetailresult: 경주별 상세성적표
  static const String raceDetailResultPath =
      '/racedetailresult/raceDetailResult';

  static const String mlBackendUrl = 'http://localhost:8000';

  /// e오늘의 경주( todayrace.kra.co.kr )는 일자/경마장 안내·검증용. 배치 ETL은 공공데이터 KRA API 권장.
  static const String todayRaceBaseUrl = 'https://todayrace.kra.co.kr';
  static const String todayRaceScorePath = '/score/race/selectRaceList.do';
  static const String todayRaceParadeVideoUrl =
      'https://www.youtube.com/results?search_query=한국마사회+경주로+입장';
  static const String youtubeApiBaseUrl = 'https://www.googleapis.com';
  static const String youtubeChannelHandle = '@KRBCRACE';

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
