"""앱과 운영 예측 파이프라인이 공유하는 버전·정책 상수."""

MODEL_VERSION = "heuristic-place-1.3"
MAX_TRAINING_RACES = 2500

# 과거 odds 테이블은 경주 후 확정 배당일 수 있으므로 학습 기본값에서 제외합니다.
USE_MARKET_ODDS_BY_DEFAULT = False
