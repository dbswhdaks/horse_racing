-- 운영 Supabase 스키마를 코드가 기대하는 상태로 되돌립니다.
--
-- 배경: 20260813 / 20260901 마이그레이션이 운영 DB 에 적용되지 않아
-- `ops-sync` 워크플로가 `column odds.captured_at does not exist` 로 실패했고,
-- `scheduled-tune` 은 운영 DB 에만 남아 있던 `idx_predictions_unique` 때문에
-- 중복 키 오류로 실패했습니다.
--
-- 이 파일은 현재 DB 상태와 무관하게, 몇 번을 다시 실행해도 같은 결과가 되도록
-- 작성했습니다.

-- =========================================================
-- odds
-- =========================================================

-- 유니크 인덱스는 NULL 을 서로 다른 값으로 취급하므로, upsert 충돌 판정이
-- 동작하려면 키 컬럼에 NULL 이 없어야 합니다.
UPDATE odds
SET horse_no1 = COALESCE(horse_no1, 0),
    horse_no2 = COALESCE(horse_no2, 0),
    horse_no3 = COALESCE(horse_no3, 0)
WHERE horse_no1 IS NULL
   OR horse_no2 IS NULL
   OR horse_no3 IS NULL;

ALTER TABLE odds
  ALTER COLUMN horse_no1 SET DEFAULT 0,
  ALTER COLUMN horse_no2 SET DEFAULT 0,
  ALTER COLUMN horse_no3 SET DEFAULT 0,
  ALTER COLUMN horse_no1 SET NOT NULL,
  ALTER COLUMN horse_no2 SET NOT NULL,
  ALTER COLUMN horse_no3 SET NOT NULL;

-- 유니크 인덱스를 만들기 전에 과거 중복 행을 정리합니다(최신 id 만 남깁니다).
DELETE FROM odds older
USING odds newer
WHERE older.id < newer.id
  AND older.meet = newer.meet
  AND older.race_date = newer.race_date
  AND older.race_no = newer.race_no
  AND older.bet_type = newer.bet_type
  AND older.horse_no1 = newer.horse_no1
  AND older.horse_no2 = newer.horse_no2
  AND older.horse_no3 = newer.horse_no3;

-- `ops_sync.py odds` 의 on_conflict 대상입니다.
CREATE UNIQUE INDEX IF NOT EXISTS uq_odds_race_selection
  ON odds (meet, race_date, race_no, bet_type, horse_no1, horse_no2, horse_no3);

-- 배당 수집 시각. `_is_prerace_capture()` 가 사전/사후 배당을 가르는 기준입니다.
-- 기존 행은 적용 시각을 받는데, 모두 경주 종료 후 백필된 확정 배당이므로
-- 사전 배당으로 오인되지 않습니다.
-- now() 는 STABLE 이라 큰 테이블이어도 재작성 없이 추가됩니다.
ALTER TABLE odds
  ADD COLUMN IF NOT EXISTS captured_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- =========================================================
-- predictions
-- =========================================================

-- 모든 upsert 가 model_version 을 충돌 키에 포함하므로 NULL 이면 안 됩니다.
UPDATE predictions SET model_version = '' WHERE model_version IS NULL;

ALTER TABLE predictions
  ALTER COLUMN model_version SET DEFAULT '',
  ALTER COLUMN model_version SET NOT NULL;

DELETE FROM predictions older
USING predictions newer
WHERE older.id < newer.id
  AND older.meet = newer.meet
  AND older.race_date = newer.race_date
  AND older.race_no = newer.race_no
  AND older.horse_no = newer.horse_no
  AND older.model_version = newer.model_version;

-- 운영 DB 에만 있던 (meet, race_date, race_no, horse_no) 유니크 제약은 한 경주에
-- 모델 버전을 하나만 저장할 수 있게 만들어 튜닝 upsert 를 깨뜨립니다.
ALTER TABLE predictions DROP CONSTRAINT IF EXISTS idx_predictions_unique;
DROP INDEX IF EXISTS idx_predictions_unique;

-- 기본 스키마의 UNIQUE 제약이 살아 있으면 중복 인덱스를 만들지 않습니다.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_index i
    JOIN pg_attribute a
      ON a.attrelid = i.indrelid
     AND a.attnum = ANY (i.indkey)
    WHERE i.indrelid = 'predictions'::regclass
      AND i.indisunique
      AND a.attname = 'model_version'
  ) THEN
    CREATE UNIQUE INDEX uq_predictions_race_horse_model
      ON predictions (meet, race_date, race_no, horse_no, model_version);
  END IF;
END $$;

ALTER TABLE predictions
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- =========================================================
-- prediction_accuracy (`ops_sync.py accuracy` 가 채웁니다)
-- =========================================================

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
  UNIQUE (meet, race_date, race_no, model_version)
);

CREATE INDEX IF NOT EXISTS idx_prediction_accuracy_date
  ON prediction_accuracy (race_date, meet, model_version);

ALTER TABLE prediction_accuracy ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read prediction accuracy" ON prediction_accuracy;
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

-- =========================================================
-- RLS: 쓰기는 service_role(RLS 우회) 로만
-- =========================================================
--
-- 아래 정책들은 모두 `public` 롤에 조건 `true` 로 걸려 있어, anon 키만 있으면
-- 누구나 경주 데이터와 예측을 고치거나 지울 수 있는 상태였습니다.
-- 앱(`lib/`)은 Supabase 에 쓰기를 하지 않으므로 제거해도 영향이 없습니다.

DROP POLICY IF EXISTS "Service insert races" ON races;
DROP POLICY IF EXISTS "Service insert entries" ON race_entries;
DROP POLICY IF EXISTS "Service insert results" ON race_results;
DROP POLICY IF EXISTS "Service insert predictions" ON predictions;
DROP POLICY IF EXISTS "Service insert odds" ON odds;

DROP POLICY IF EXISTS "Service update races" ON races;
DROP POLICY IF EXISTS "Service update entries" ON race_entries;
DROP POLICY IF EXISTS "Service update results" ON race_results;
DROP POLICY IF EXISTS "Service update predictions" ON predictions;
DROP POLICY IF EXISTS "Service update odds" ON odds;

-- 이름과 달리 service_role 이 아니라 public 롤 대상이라 사실상 전체 공개 쓰기입니다.
DROP POLICY IF EXISTS "Allow all for service_role" ON races;
DROP POLICY IF EXISTS "Allow all for service_role" ON race_entries;
DROP POLICY IF EXISTS "Allow all for service_role" ON predictions;
