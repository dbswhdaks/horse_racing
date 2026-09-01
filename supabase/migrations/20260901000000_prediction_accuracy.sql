-- 운영 예측의 장기 입상 적중률 추적
--
-- `backend/ops_sync.py accuracy` 가 결과 확정 후 경주 단위로 채웁니다.
-- 튜닝 스크립트의 백테스트와 달리, 실제로 앱이 노출한 predictions 행을
-- 그대로 평가하므로 운영 성능을 그대로 보여줍니다.

CREATE TABLE IF NOT EXISTS prediction_accuracy (
  id BIGSERIAL PRIMARY KEY,
  meet TEXT NOT NULL,
  race_date TEXT NOT NULL,
  race_no INTEGER NOT NULL,
  model_version TEXT NOT NULL,
  field_size INTEGER NOT NULL DEFAULT 0,
  -- 예측 Top3(입상확률 기준) 와 실제 1~3위의 교집합 비율
  top3_match REAL NOT NULL DEFAULT 0,
  -- 실제 1위가 예측 Top3 안에 있었는지
  top3_winner BOOLEAN NOT NULL DEFAULT FALSE,
  -- 예측 1위(단승 기준) 가 실제 1위였는지
  top1_hit BOOLEAN NOT NULL DEFAULT FALSE,
  -- 입상확률의 Brier score (낮을수록 정확)
  place_brier REAL NOT NULL DEFAULT 0,
  evaluated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(meet, race_date, race_no, model_version)
);

CREATE INDEX IF NOT EXISTS idx_prediction_accuracy_date
  ON prediction_accuracy(race_date, meet, model_version);

ALTER TABLE prediction_accuracy ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public read prediction accuracy"
  ON prediction_accuracy FOR SELECT USING (true);

-- 일자·모델별 요약. 앱이나 대시보드에서 추세를 볼 때 사용합니다.
CREATE OR REPLACE VIEW prediction_accuracy_daily AS
SELECT
  race_date,
  meet,
  model_version,
  COUNT(*)::INTEGER            AS races,
  AVG(top3_match)              AS top3_match,
  AVG(top3_winner::INT)        AS top3_winner_rate,
  AVG(top1_hit::INT)           AS top1_acc,
  AVG(place_brier)             AS place_brier
FROM prediction_accuracy
GROUP BY race_date, meet, model_version;
