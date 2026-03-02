-- 1종대형 수강료 컬럼 추가
ALTER TABLE academy ADD COLUMN IF NOT EXISTS fee_type1_large TEXT;
