abstract final class PredictionConstants {
  /// 승률 인위 보정을 제거하고 앱·동기화 파이프라인을 통일한 버전입니다.
  static const modelVersion = 'heuristic-place-1.3';

  /// 현재 저장된 튜닝 결과는 사후 배당을 사용하지 않았으므로 시장 가중치는 0입니다.
  static const marketWeight = 0.0;

  static const preferredModelVersions = [
    modelVersion,
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
