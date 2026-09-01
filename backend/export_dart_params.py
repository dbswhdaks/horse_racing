"""튜닝 결과 JSON을 Flutter 상수로 반영한다.

`backend/models/heuristic_tuned_params.json` 의 `best_params` 를
`lib/core/services/local_predictor.dart` 의 `_params` 블록과
`lib/core/constants/prediction_constants.dart` 의 `marketWeight` 에 써 넣는다.

손으로 옮기면 파이썬과 Dart 가 조용히 어긋나므로 항상 이 스크립트를 쓴다.

사용:
  python backend/export_dart_params.py            # 파일 갱신
  python backend/export_dart_params.py --check    # 변경 필요 시 비정상 종료(CI용)
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

from prediction_constants import MODEL_VERSION

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PARAMS_JSON = os.path.join(REPO_ROOT, "backend", "models", "heuristic_tuned_params.json")
PREDICTOR_DART = os.path.join(
    REPO_ROOT, "lib", "core", "services", "local_predictor.dart"
)
CONSTANTS_DART = os.path.join(
    REPO_ROOT, "lib", "core", "constants", "prediction_constants.dart"
)

PARAMS_BEGIN = "  // TUNED_PARAMS_BEGIN"
PARAMS_END = "  // TUNED_PARAMS_END"
MARKET_BEGIN = "  // TUNED_MARKET_WEIGHT_BEGIN"
MARKET_END = "  // TUNED_MARKET_WEIGHT_END"

# JSON 키 → Dart 필드명. 여기 없는 키는 Dart 로 내보내지 않는다.
FIELD_MAP: list[tuple[str, str]] = [
    ("w_rating", "wRating"),
    ("w_perf", "wPerformance"),
    ("w_class_form", "wClassForm"),
    ("w_pace", "wPace"),
    ("w_condition", "wCondition"),
    ("w_jockey", "wJockey"),
    ("w_recent_form", "wRecentForm"),
    ("w_fitness", "wFitness"),
    ("rating_pow", "ratingPow"),
    ("prior_weight", "priorWeight"),
    ("temp_scale", "tempScale"),
    ("place_temp_scale", "placeTempScale"),
    ("reliability_penalty", "reliabilityPenalty"),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="튜닝 파라미터 → Dart 상수 반영")
    parser.add_argument(
        "--check",
        action="store_true",
        help="파일을 고치지 않고, 갱신이 필요하면 종료 코드 1을 반환",
    )
    parser.add_argument("--params-file", default=PARAMS_JSON, help="튜닝 JSON 경로")
    return parser.parse_args()


def _replace_block(source: str, begin: str, end: str, body: str, path: str) -> str:
    pattern = re.compile(
        rf"({re.escape(begin)}\n).*?({re.escape(end)})",
        re.DOTALL,
    )
    if not pattern.search(source):
        raise SystemExit(f"{path} 에서 {begin.strip()} / {end.strip()} 마커를 찾지 못했습니다.")
    return pattern.sub(lambda m: f"{m.group(1)}{body}{m.group(2)}", source)


def _params_block(best: dict[str, float]) -> str:
    missing = [key for key, _ in FIELD_MAP if key not in best]
    if missing:
        raise SystemExit(
            f"튜닝 JSON 에 다음 키가 없습니다: {', '.join(missing)}. "
            "tune_heuristic_predictions.py 를 다시 실행하십시오."
        )

    lines = ["  static const _params = _HeuristicParams("]
    for json_key, dart_field in FIELD_MAP:
        lines.append(f"    {dart_field}: {float(best[json_key]):.6f},")
    lines.append("  );")
    return "\n".join(lines) + "\n"


def _market_block(best: dict[str, float]) -> str:
    weight = float(best.get("w_market", 0.0))
    return f"  static const marketWeight = {weight:.6f};\n"


def _verify_model_version(constants_source: str) -> None:
    match = re.search(r"static const modelVersion = '([^']+)';", constants_source)
    if not match:
        raise SystemExit("prediction_constants.dart 에서 modelVersion 을 찾지 못했습니다.")
    if match.group(1) != MODEL_VERSION:
        raise SystemExit(
            f"모델 버전 불일치: Dart='{match.group(1)}', "
            f"Python='{MODEL_VERSION}'. 양쪽을 맞춘 뒤 다시 실행하십시오."
        )


def main() -> None:
    args = parse_args()

    with open(args.params_file, encoding="utf-8") as f:
        payload = json.load(f)
    best = payload.get("best_params") or {}
    if not best:
        raise SystemExit(f"{args.params_file} 에 best_params 가 없습니다.")

    with open(PREDICTOR_DART, encoding="utf-8") as f:
        predictor_source = f.read()
    with open(CONSTANTS_DART, encoding="utf-8") as f:
        constants_source = f.read()

    _verify_model_version(constants_source)

    updated_predictor = _replace_block(
        predictor_source, PARAMS_BEGIN, PARAMS_END, _params_block(best), PREDICTOR_DART
    )
    updated_constants = _replace_block(
        constants_source, MARKET_BEGIN, MARKET_END, _market_block(best), CONSTANTS_DART
    )

    changes = [
        (PREDICTOR_DART, predictor_source, updated_predictor),
        (CONSTANTS_DART, constants_source, updated_constants),
    ]
    stale = [path for path, before, after in changes if before != after]

    if args.check:
        if stale:
            for path in stale:
                print(f"[STALE] {os.path.relpath(path, REPO_ROOT)}")
            print(
                "Dart 상수가 튜닝 결과와 다릅니다. "
                "python backend/export_dart_params.py 를 실행해 반영하십시오."
            )
            sys.exit(1)
        print("[OK] Dart 상수가 튜닝 결과와 일치합니다.")
        return

    for path, _, after in changes:
        with open(path, "w", encoding="utf-8") as f:
            f.write(after)
    if stale:
        for path in stale:
            print(f"[UPDATED] {os.path.relpath(path, REPO_ROOT)}")
    else:
        print("[OK] 변경 사항 없음.")
    print(f"[DONE] model_version={MODEL_VERSION}")


if __name__ == "__main__":
    main()
