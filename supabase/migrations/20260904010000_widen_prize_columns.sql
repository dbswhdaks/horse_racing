-- 상금 컬럼을 BIGINT 로 넓힙니다.
--
-- 마필 누적 상금(`chaksunT`)은 int4 상한(2,147,483,647)을 쉽게 넘습니다.
-- 실제로 백필 중 5,137,450,000 원 마필에서 `22003 out of range` 로 중단됐습니다.

ALTER TABLE race_entries
  ALTER COLUMN total_prize TYPE BIGINT,
  ALTER COLUMN recent_prize TYPE BIGINT;

-- 경주별 상금은 아직 여유가 있지만 같은 성격이므로 함께 맞춥니다.
ALTER TABLE races
  ALTER COLUMN prize1 TYPE BIGINT,
  ALTER COLUMN prize2 TYPE BIGINT,
  ALTER COLUMN prize3 TYPE BIGINT;
