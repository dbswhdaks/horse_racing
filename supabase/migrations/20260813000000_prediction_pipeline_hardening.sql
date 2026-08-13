-- 예측 데이터 오염 방지 및 재학습 추적성 강화

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

CREATE UNIQUE INDEX IF NOT EXISTS uq_odds_race_selection
  ON odds(meet, race_date, race_no, bet_type, horse_no1, horse_no2, horse_no3);

ALTER TABLE odds
  ADD COLUMN IF NOT EXISTS captured_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

ALTER TABLE predictions
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- service_role은 RLS를 우회합니다. 공개 anon 쓰기를 허용하던 정책은 제거합니다.
DROP POLICY IF EXISTS "Service insert races" ON races;
DROP POLICY IF EXISTS "Service insert entries" ON race_entries;
DROP POLICY IF EXISTS "Service insert results" ON race_results;
DROP POLICY IF EXISTS "Service insert predictions" ON predictions;
DROP POLICY IF EXISTS "Service insert odds" ON odds;
