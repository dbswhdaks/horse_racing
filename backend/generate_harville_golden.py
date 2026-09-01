"""Python 구현의 Harville 입상확률을 Dart 테스트용 골든 파일로 내보낸다.

Dart 포팅본(`LocalPredictor.harvillePlaceProbs`)이 파이썬 튜닝 스크립트와
같은 값을 내는지 검증하기 위한 고정 픽스처를 만든다.

사용:
  python backend/generate_harville_golden.py
"""

from __future__ import annotations

import json
import os
import random

from tune_heuristic_predictions import PLACE_SLOTS, _harville_place_probs

OUTPUT_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "test",
    "fixtures",
    "harville_golden.json",
)

# 경계 조건과 실제 경주에 가까운 분포를 모두 담는다.
FIXED_CASES: list[tuple[str, list[float], int]] = [
    ("uniform_10", [1.0] * 10, PLACE_SLOTS),
    ("field_equals_slots", [3.0, 2.0, 1.0], PLACE_SLOTS),
    ("field_below_slots", [5.0, 1.0], PLACE_SLOTS),
    ("single_dominant", [50.0, 1.0, 1.0, 1.0, 1.0, 1.0], PLACE_SLOTS),
    ("two_way", [40.0, 40.0, 1.0, 1.0, 1.0, 1.0, 1.0], PLACE_SLOTS),
    ("descending_16", [float(16 - i) for i in range(16)], PLACE_SLOTS),
    ("tiny_weights", [1e-6, 2e-6, 3e-6, 4e-6, 5e-6, 6e-6], PLACE_SLOTS),
    ("all_zero", [0.0] * 8, PLACE_SLOTS),
    ("slots_one", [4.0, 3.0, 2.0, 1.0], 1),
    ("slots_two", [4.0, 3.0, 2.0, 1.0, 1.0], 2),
]


def _random_cases(count: int, seed: int) -> list[tuple[str, list[float], int]]:
    rng = random.Random(seed)
    cases = []
    for i in range(count):
        n = rng.randint(5, 16)
        weights = [round(rng.uniform(0.01, 20.0), 6) for _ in range(n)]
        cases.append((f"random_{i:02d}_n{n}", weights, PLACE_SLOTS))
    return cases


def main() -> None:
    cases = FIXED_CASES + _random_cases(20, seed=20260901)
    payload = {
        "description": (
            "backend/tune_heuristic_predictions.py 의 _harville_place_probs 출력. "
            "backend/generate_harville_golden.py 로 재생성합니다."
        ),
        "cases": [
            {
                "name": name,
                "slots": slots,
                "weights": weights,
                "expected": _harville_place_probs(weights, slots=slots),
            }
            for name, weights, slots in cases
        ],
    }

    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
    print(f"[DONE] 골든 파일 {len(payload['cases'])}건 저장: {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
