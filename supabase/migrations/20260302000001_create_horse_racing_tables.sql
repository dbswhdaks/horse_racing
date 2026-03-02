-- =============================================
-- 경마 예측 앱 Supabase 테이블
-- =============================================

-- 경주 계획
CREATE TABLE IF NOT EXISTS races (
  id BIGSERIAL PRIMARY KEY,
  meet TEXT NOT NULL,
  race_date TEXT NOT NULL,
  race_no INTEGER NOT NULL,
  distance INTEGER NOT NULL DEFAULT 0,
  grade_condition TEXT DEFAULT '',
  race_name TEXT DEFAULT '',
  age_condition TEXT DEFAULT '',
  sex_condition TEXT DEFAULT '',
  weight_condition TEXT DEFAULT '',
  start_time TEXT DEFAULT '',
  prize1 INTEGER DEFAULT 0,
  prize2 INTEGER DEFAULT 0,
  prize3 INTEGER DEFAULT 0,
  head_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(meet, race_date, race_no)
);

-- 출마표 (출전 마필)
CREATE TABLE IF NOT EXISTS race_entries (
  id BIGSERIAL PRIMARY KEY,
  meet TEXT NOT NULL,
  race_date TEXT NOT NULL,
  race_no INTEGER NOT NULL DEFAULT 0,
  horse_no INTEGER NOT NULL,
  horse_name TEXT NOT NULL,
  birth_place TEXT DEFAULT '',
  sex TEXT DEFAULT '',
  age INTEGER DEFAULT 0,
  jockey_name TEXT DEFAULT '',
  trainer_name TEXT DEFAULT '',
  owner_name TEXT DEFAULT '',
  weight REAL DEFAULT 0,
  rating REAL DEFAULT 0,
  total_prize INTEGER DEFAULT 0,
  recent_prize INTEGER DEFAULT 0,
  win_count INTEGER DEFAULT 0,
  place_count INTEGER DEFAULT 0,
  total_races INTEGER DEFAULT 0,
  horse_weight REAL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(meet, race_date, race_no, horse_no)
);

-- 경주 결과
CREATE TABLE IF NOT EXISTS race_results (
  id BIGSERIAL PRIMARY KEY,
  meet TEXT NOT NULL,
  race_date TEXT NOT NULL,
  race_no INTEGER NOT NULL DEFAULT 0,
  rank INTEGER NOT NULL,
  horse_no INTEGER NOT NULL,
  horse_name TEXT NOT NULL,
  jockey_name TEXT DEFAULT '',
  trainer_name TEXT DEFAULT '',
  race_time TEXT DEFAULT '',
  weight REAL DEFAULT 0,
  horse_weight REAL DEFAULT 0,
  rank_diff TEXT DEFAULT '',
  win_odds REAL DEFAULT 0,
  place_odds REAL DEFAULT 0,
  s1f TEXT DEFAULT '',
  g3f TEXT DEFAULT '',
  pass_order TEXT DEFAULT '',
  distance INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(meet, race_date, race_no, horse_no)
);

-- AI 예측 결과
CREATE TABLE IF NOT EXISTS predictions (
  id BIGSERIAL PRIMARY KEY,
  meet TEXT NOT NULL,
  race_date TEXT NOT NULL,
  race_no INTEGER NOT NULL,
  horse_no INTEGER NOT NULL,
  horse_name TEXT NOT NULL,
  win_probability REAL DEFAULT 0,
  place_probability REAL DEFAULT 0,
  tags TEXT[] DEFAULT '{}',
  feature_importance JSONB DEFAULT '{}',
  model_version TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(meet, race_date, race_no, horse_no, model_version)
);

-- 배당률
CREATE TABLE IF NOT EXISTS odds (
  id BIGSERIAL PRIMARY KEY,
  meet TEXT NOT NULL,
  race_date TEXT NOT NULL,
  race_no INTEGER NOT NULL,
  bet_type TEXT NOT NULL,
  horse_no1 INTEGER DEFAULT 0,
  horse_no2 INTEGER DEFAULT 0,
  horse_no3 INTEGER DEFAULT 0,
  rate REAL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 인덱스
CREATE INDEX IF NOT EXISTS idx_races_date ON races(race_date, meet);
CREATE INDEX IF NOT EXISTS idx_entries_date ON race_entries(race_date, meet);
CREATE INDEX IF NOT EXISTS idx_entries_horse ON race_entries(horse_name);
CREATE INDEX IF NOT EXISTS idx_results_date ON race_results(race_date, meet);
CREATE INDEX IF NOT EXISTS idx_results_horse ON race_results(horse_name);
CREATE INDEX IF NOT EXISTS idx_predictions_date ON predictions(race_date, meet, race_no);
CREATE INDEX IF NOT EXISTS idx_odds_date ON odds(race_date, meet, race_no);

-- RLS 정책 (공개 읽기)
ALTER TABLE races ENABLE ROW LEVEL SECURITY;
ALTER TABLE race_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE race_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE predictions ENABLE ROW LEVEL SECURITY;
ALTER TABLE odds ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public read races" ON races FOR SELECT USING (true);
CREATE POLICY "Public read entries" ON race_entries FOR SELECT USING (true);
CREATE POLICY "Public read results" ON race_results FOR SELECT USING (true);
CREATE POLICY "Public read predictions" ON predictions FOR SELECT USING (true);
CREATE POLICY "Public read odds" ON odds FOR SELECT USING (true);

CREATE POLICY "Service insert races" ON races FOR INSERT WITH CHECK (true);
CREATE POLICY "Service insert entries" ON race_entries FOR INSERT WITH CHECK (true);
CREATE POLICY "Service insert results" ON race_results FOR INSERT WITH CHECK (true);
CREATE POLICY "Service insert predictions" ON predictions FOR INSERT WITH CHECK (true);
CREATE POLICY "Service insert odds" ON odds FOR INSERT WITH CHECK (true);
