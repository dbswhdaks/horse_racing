"""앱과 운영 예측 파이프라인이 공유하는 버전·정책 상수."""

MODEL_VERSION = "heuristic-place-1.5"
MAX_TRAINING_RACES = 2500

# 과거 odds 테이블은 경주 후 확정 배당일 수 있으므로 학습 기본값에서 제외합니다.
USE_MARKET_ODDS_BY_DEFAULT = False

# 출주 두수가 이보다 적은 경주는 표본으로 쓰지 않습니다.
MIN_ENTRIES_PER_RACE = 5

# 튜닝 목적함수 가중치. 입상권(Top3) 포함률을 최우선으로 둡니다.
OBJECTIVE_WEIGHTS = {
    "top3_match": 0.55,
    "top3_winner": 0.20,
    "place_brier": 0.15,
    "top1_acc": 0.10,
}

# 시간순 walk-forward 검증 폴드 수.
WALK_FORWARD_FOLDS = 3
