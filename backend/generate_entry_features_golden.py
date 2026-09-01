"""Python 구현의 as-of 피처 점수를 Dart 테스트용 골든 파일로 내보낸다.

`lib/core/services/entry_features.dart` 포팅본이 `backend/entry_features.py` 와
같은 값을 내는지 검증하기 위한 고정 픽스처를 만든다.

사용:
  python backend/generate_entry_features_golden.py
"""

from __future__ import annotations

import json
import os
import random

from entry_features import AsOfFeatureIndex

OUTPUT_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "test",
    "fixtures",
    "entry_features_golden.json",
)

RACE_DATES = [
    "20240105", "20240112", "20240119", "20240202", "20240216",
    "20240301", "20240315", "20240419", "20240517", "20240614",
    "20240712", "20240816", "20240913", "20241011", "20241108",
    "20241213", "20250110", "20250214", "20250321", "20250425",
]

HORSES = [f"말{i:02d}" for i in range(1, 15)]
JOCKEYS = [f"기수{i:02d}" for i in range(1, 7)]
DISTANCES = [1000, 1200, 1400, 1600, 1800, 2000]


def _build_history(seed: int) -> list[dict]:
    """경주 단위로 완결된 결과 행을 만든다(두수 계산이 정확해야 하므로)."""
    rng = random.Random(seed)
    rows: list[dict] = []
    for date_str in RACE_DATES:
        for race_no in (1, 2, 3):
            runners = rng.sample(HORSES, rng.randint(6, 12))
            rng.shuffle(runners)
            distance = rng.choice(DISTANCES)
            for rank, horse in enumerate(runners, start=1):
                rows.append(
                    {
                        "meet": "1",
                        "race_date": date_str,
                        "race_no": race_no,
                        "horse_no": rank,
                        "horse_name": horse,
                        "jockey_name": rng.choice(JOCKEYS),
                        "rank": rank,
                        "horse_weight": float(rng.randint(430, 530)),
                        "distance": distance,
                    }
                )
    return rows


def main() -> None:
    history = _build_history(seed=20260901)
    index = AsOfFeatureIndex(history)

    rng = random.Random(4242)
    queries = []
    # 이력이 없는 경계(가장 이른 날짜, 미등록 말)도 함께 검증한다.
    fixed = [
        ("20240105", HORSES[0], JOCKEYS[0], 1200, 480.0),
        ("20990101", "없는말", "없는기수", 1400, 470.0),
        ("20250425", HORSES[3], JOCKEYS[2], 2000, 500.0),
    ]
    for race_date, horse, jockey, distance, weight in fixed:
        queries.append(
            {
                "race_date": race_date,
                "horse_name": horse,
                "jockey_name": jockey,
                "distance": distance,
                "horse_weight": weight,
            }
        )
    for _ in range(40):
        queries.append(
            {
                "race_date": rng.choice(RACE_DATES),
                "horse_name": rng.choice(HORSES),
                "jockey_name": rng.choice(JOCKEYS),
                "distance": rng.choice(DISTANCES),
                "horse_weight": float(rng.randint(430, 530)),
            }
        )

    cases = []
    for query in queries:
        scores = index.features_for(**query)
        cases.append(
            {
                **query,
                "expected": {
                    "jockey": scores.jockey,
                    "recent_form": scores.recent_form,
                    "fitness": scores.fitness,
                },
            }
        )

    payload = {
        "description": (
            "backend/entry_features.py 의 AsOfFeatureIndex 출력. "
            "backend/generate_entry_features_golden.py 로 재생성합니다."
        ),
        "prior_place_rate": index.prior_place_rate,
        "history": history,
        "cases": cases,
    }

    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
    print(
        f"[DONE] 이력 {len(history)}행 / 케이스 {len(cases)}건 저장: {OUTPUT_PATH}"
    )


if __name__ == "__main__":
    main()
