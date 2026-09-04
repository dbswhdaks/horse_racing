abstract final class PredictionConstants {
  /// 입상 전용 점수로 Harville 입상확률을 만들고 입상권 적중률 중심으로 재튜닝한 버전입니다.
  static const modelVersion = 'heuristic-place-1.5';

  /// 현재 저장된 튜닝 결과는 사후 배당을 사용하지 않았으므로 시장 가중치는 0입니다.
  // TUNED_MARKET_WEIGHT_BEGIN
  static const marketWeight = 0.000000;
  // TUNED_MARKET_WEIGHT_END

  /// 입상권으로 인정하는 착순 범위(1~3위).
  static const placeSlots = 3;

  static const preferredModelVersions = [
    modelVersion,
    'heuristic-place-1.4',
    'heuristic-place-1.3',
    'heuristic-place-1.2',
    'heuristic-place-1.1',
    'heuristic-place-1.0',
    'heuristic-3.1-tuned',
    'heuristic-3.1',
    '1.0',
  ];

  static bool isProductionMlVersion(String version) =>
      version.startsWith('multi-');
}
