"""
Generate realistic seed training data for ML model when live API data is limited.
Based on typical Korean horse racing statistics and patterns.
"""

import os
import random
from datetime import datetime, timedelta

import numpy as np
import pandas as pd

from config import DATA_DIR

HORSE_NAMES = [
    "파워블레이드", "골든파워", "스피드킹", "자이언트", "윈드러너",
    "번개호", "청룡", "백마왕", "드래곤킹", "스타라이트",
    "뉴레전드", "퍼펙트", "탑클래스", "챔피언쉽", "에이스",
    "블루문", "레드썬더", "골드러시", "실버윙", "브레이브",
    "썬더볼트", "매직타임", "파이널킹", "뉴스타", "프라이드",
    "천둥호", "비상마", "영웅호", "광풍", "독수리",
    "하늘바람", "신바람", "돌풍", "태풍호", "무적호",
    "행운마", "결승타", "명마왕", "최강마", "전설마",
    "빛나는별", "코스모스", "갤럭시", "플라잉킹", "로얄킹",
    "다이아몬드", "사파이어", "루비스타", "에메랴르드", "크리스탈",
]

JOCKEY_NAMES = [
    "문세영", "유현명", "김용근", "이찬호", "조성곤",
    "김태완", "박찬호", "이승헌", "정성원", "최보경",
    "한동훈", "김민기", "박태종", "장석현", "송재광",
]

TRAINER_NAMES = [
    "정길상", "김영관", "이재형", "조순호", "박재형",
    "김동수", "오창근", "정해성", "박배진", "최두환",
]

MEETS = ["1", "2", "3"]
DISTANCES = [1000, 1200, 1300, 1400, 1600, 1700, 1800, 2000, 2400]
TRACK_CONDITIONS = ["양호", "포슬", "다습", "불량"]
WEATHERS = ["맑음", "흐림", "비", "눈"]


def generate_seed_data(
    num_races: int = 500,
    horses_per_race: int = 12,
) -> pd.DataFrame:
    """Generate realistic training data rows."""
    random.seed(42)
    np.random.seed(42)
    os.makedirs(DATA_DIR, exist_ok=True)

    rows: list[dict] = []
    base_date = datetime(2025, 6, 1)

    horse_abilities: dict[str, float] = {}
    for name in HORSE_NAMES:
        horse_abilities[name] = np.random.normal(50, 15)

    jockey_skills: dict[str, float] = {}
    for name in JOCKEY_NAMES:
        jockey_skills[name] = np.random.normal(50, 10)

    for race_idx in range(num_races):
        race_date = base_date + timedelta(days=race_idx // 5)
        meet = random.choice(MEETS)
        race_no = (race_idx % 10) + 1
        distance = random.choice(DISTANCES)
        track_cond = random.choices(
            TRACK_CONDITIONS, weights=[60, 20, 15, 5]
        )[0]
        weather = random.choices(WEATHERS, weights=[50, 25, 15, 10])[0]

        n_horses = min(horses_per_race, random.randint(8, 14))
        race_horses = random.sample(HORSE_NAMES, n_horses)

        scores: list[tuple[int, float]] = []
        for i, horse_name in enumerate(race_horses):
            jockey = random.choice(JOCKEY_NAMES)
            trainer = random.choice(TRAINER_NAMES)
            weight = round(random.uniform(52, 59), 1)
            horse_weight = round(random.uniform(440, 520), 0)
            age = random.randint(3, 8)

            ability = horse_abilities[horse_name]
            jockey_skill = jockey_skills[jockey]

            base_time = distance / 16.5
            noise = np.random.normal(0, 1.5)
            perf = ability + jockey_skill * 0.3 - weight * 0.5 + noise

            if track_cond in ("다습", "불량"):
                if horse_abilities[horse_name] > 55:
                    perf += 3
                else:
                    perf -= 2

            if weather == "비":
                perf += np.random.normal(0, 2)

            s1f_base = base_time * random.uniform(0.08, 0.15)
            g3f_base = base_time * random.uniform(0.35, 0.50)
            s1f = round(s1f_base + np.random.normal(0, 0.3), 1)
            g3f = round(g3f_base + np.random.normal(0, 0.5), 1)

            race_time = round(base_time - perf * 0.05 + np.random.normal(0, 0.5), 1)
            race_time = max(race_time, base_time * 0.85)

            scores.append((i, -perf))

            rows.append({
                "meet": meet,
                "rcDate": race_date.strftime("%Y%m%d"),
                "rcNo": race_no,
                "rcDist": distance,
                "hrNo": i + 1,
                "hrNm": horse_name,
                "jkNm": jockey,
                "trNm": trainer,
                "wght": weight,
                "hrWght": horse_weight,
                "age": age,
                "sex": random.choice(["수", "암", "거"]),
                "rcTime": str(race_time),
                "s1f": str(abs(s1f)),
                "g3f": str(abs(g3f)),
                "ordBigo": f"{random.randint(1,n_horses)}-{random.randint(1,n_horses)}-{random.randint(1,n_horses)}",
                "trackCond": track_cond,
                "weather": weather,
                "ord": 0,
                "winOdds": 0.0,
                "plcOdds": 0.0,
            })

        scores.sort(key=lambda x: x[1])
        for rank_idx, (horse_idx_in_race, _) in enumerate(scores):
            row_idx = len(rows) - n_horses + horse_idx_in_race
            rows[row_idx]["ord"] = rank_idx + 1

            if rank_idx == 0:
                rows[row_idx]["winOdds"] = round(random.uniform(1.5, 30.0), 1)
                rows[row_idx]["plcOdds"] = round(random.uniform(1.1, 5.0), 1)
            elif rank_idx <= 2:
                rows[row_idx]["winOdds"] = 0
                rows[row_idx]["plcOdds"] = round(random.uniform(1.1, 8.0), 1)

    df = pd.DataFrame(rows)
    path = os.path.join(DATA_DIR, "seed_training_data.csv")
    df.to_csv(path, index=False, encoding="utf-8-sig")
    return df


if __name__ == "__main__":
    df = generate_seed_data()
    print(f"Generated {len(df)} rows, saved to {DATA_DIR}/seed_training_data.csv")
    print(f"Columns: {list(df.columns)}")
    print(f"Unique horses: {df['hrNm'].nunique()}")
    print(f"Unique races: {len(df.groupby(['rcDate', 'rcNo']))}")
