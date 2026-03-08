"""
경마 예측을 위한 피처 엔지니어링 모듈.

원시 데이터를 XGBoost가 학습할 수 있는 피처로 변환합니다.
"""

import pandas as pd
import numpy as np


SEX_MAP = {"수": 0, "암": 1, "거": 2, "M": 0, "F": 1, "G": 2}
BIRTH_PLACE_MAP = {"한": 0, "미": 1, "일": 2, "호": 3, "영": 4, "불": 5}

FEATURE_COLUMNS = [
    "race_distance",
    "burden_weight",
    "horse_weight",
    "rating",
    "age",
    "sex_encoded",
    "birth_place_encoded",
    "total_races",
    "win_count",
    "place_count",
    "win_rate",
    "place_rate",
    "total_prize_log",
    "recent_prize_log",
    "field_size",
    "win_odds",
    "horse_weight_diff",
    "weight_per_distance",
    "experience_score",
    "form_score",
]


def engineer_features(df: pd.DataFrame) -> pd.DataFrame:
    """원시 데이터프레임에 학습용 피처를 추가합니다."""
    out = df.copy()

    out["sex_encoded"] = out["sex"].map(SEX_MAP).fillna(-1).astype(int)
    out["birth_place_encoded"] = (
        out["birth_place"].str[:1].map(BIRTH_PLACE_MAP).fillna(-1).astype(int)
    )

    out["win_rate"] = np.where(
        out["total_races"] > 0,
        out["win_count"] / out["total_races"],
        0.0,
    )
    out["place_rate"] = np.where(
        out["total_races"] > 0,
        (out["win_count"] + out["place_count"]) / out["total_races"],
        0.0,
    )

    out["total_prize_log"] = np.log1p(out["total_prize"].clip(lower=0))
    out["recent_prize_log"] = np.log1p(out["recent_prize"].clip(lower=0))

    out["field_size"] = out.groupby(
        ["meet", "race_date", "race_no"]
    )["horse_no"].transform("count")

    avg_weight = out.groupby(
        ["meet", "race_date", "race_no"]
    )["horse_weight"].transform("mean")
    out["horse_weight_diff"] = out["horse_weight"] - avg_weight

    out["weight_per_distance"] = np.where(
        out["race_distance"] > 0,
        out["burden_weight"] / out["race_distance"] * 1000,
        0.0,
    )

    out["experience_score"] = np.log1p(out["total_races"]) * out["win_rate"]

    out["form_score"] = np.where(
        out["total_prize"] > 0,
        out["recent_prize"] / out["total_prize"].clip(lower=1),
        0.0,
    )

    return out


def prepare_xy(
    df: pd.DataFrame,
    target: str = "is_win",
) -> tuple[pd.DataFrame, pd.Series]:
    """
    피처 행렬 X와 타겟 y를 반환합니다.

    target 옵션:
      - "is_win": 1착 여부 (이진 분류)
      - "is_place": 3착 이내 여부 (이진 분류)
      - "rank": 순위 (회귀)
    """
    featured = engineer_features(df)

    if target == "is_win":
        y = (featured["rank"] == 1).astype(int)
    elif target == "is_place":
        y = (featured["rank"].between(1, 3)).astype(int)
    elif target == "rank":
        y = featured["rank"]
    else:
        raise ValueError(f"Unknown target: {target}")

    valid_mask = featured["rank"] > 0
    featured = featured[valid_mask]
    y = y[valid_mask]

    available = [c for c in FEATURE_COLUMNS if c in featured.columns]
    X = featured[available].fillna(0)

    return X, y
