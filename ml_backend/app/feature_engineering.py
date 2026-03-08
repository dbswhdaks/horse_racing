"""
경마 예측을 위한 피처 엔지니어링 모듈.

원시 데이터를 ML 모델이 학습할 수 있는 피처로 변환합니다.
롤링 피처(직전 N경기 통계)와 LTR 데이터 구성을 지원합니다.
"""

import pandas as pd
import numpy as np


SEX_MAP = {"수": 0, "암": 1, "거": 2, "M": 0, "F": 1, "G": 2}
BIRTH_PLACE_MAP = {"한": 0, "미": 1, "일": 2, "호": 3, "영": 4, "불": 5}

BASE_FEATURE_COLUMNS = [
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

ROLLING_FEATURE_COLUMNS = [
    "recent_5_avg_rank",
    "recent_5_win_rate",
    "recent_5_place_rate",
    "days_since_last_race",
    "rank_trend",
    "jockey_win_rate",
]

FEATURE_COLUMNS = BASE_FEATURE_COLUMNS + ROLLING_FEATURE_COLUMNS


def engineer_features(df: pd.DataFrame) -> pd.DataFrame:
    """원시 데이터프레임에 기본 학습용 피처를 추가합니다."""
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


def add_rolling_features(df: pd.DataFrame, window: int = 5) -> pd.DataFrame:
    """
    마필별 롤링(과거 기반) 피처를 추가합니다.

    shift(1)을 사용하여 현재 경주 정보가 피처에 누출되지 않도록 보장합니다.
    rank=0(미완주/예측용) 행은 롤링 계산에서 제외됩니다.
    """
    out = df.copy()
    out = out.sort_values(["race_date", "race_no", "horse_no"]).reset_index(drop=True)

    out["_race_dt"] = pd.to_datetime(out["race_date"], format="%Y%m%d", errors="coerce")

    valid = out["rank"] > 0
    out["_rank_v"] = np.where(valid, out["rank"].astype(float), np.nan)
    out["_is_win_v"] = np.where(valid, (out["rank"] == 1).astype(float), np.nan)
    out["_is_place_v"] = np.where(valid, out["rank"].between(1, 3).astype(float), np.nan)

    horse_grp = out.groupby("horse_name")

    out["recent_5_avg_rank"] = horse_grp["_rank_v"].transform(
        lambda x: x.shift(1).rolling(window, min_periods=1).mean()
    )
    out["recent_5_win_rate"] = horse_grp["_is_win_v"].transform(
        lambda x: x.shift(1).rolling(window, min_periods=1).mean()
    )
    out["recent_5_place_rate"] = horse_grp["_is_place_v"].transform(
        lambda x: x.shift(1).rolling(window, min_periods=1).mean()
    )

    out["days_since_last_race"] = horse_grp["_race_dt"].transform(
        lambda x: x.diff().dt.days
    )

    last_rank = horse_grp["_rank_v"].transform(lambda x: x.shift(1))
    out["rank_trend"] = out["recent_5_avg_rank"] - last_rank

    if "jockey_name" in out.columns:
        jockey_grp = out.groupby("jockey_name")
        out["jockey_win_rate"] = jockey_grp["_is_win_v"].transform(
            lambda x: x.shift(1).rolling(20, min_periods=3).mean()
        )
    else:
        out["jockey_win_rate"] = 0.0

    median_field = out["field_size"].median() if "field_size" in out.columns else 8.0
    out["recent_5_avg_rank"] = out["recent_5_avg_rank"].fillna(median_field / 2)
    out["recent_5_win_rate"] = out["recent_5_win_rate"].fillna(0.0)
    out["recent_5_place_rate"] = out["recent_5_place_rate"].fillna(0.0)
    out["days_since_last_race"] = out["days_since_last_race"].fillna(90.0)
    out["rank_trend"] = out["rank_trend"].fillna(0.0)
    out["jockey_win_rate"] = out["jockey_win_rate"].fillna(0.0)

    out.drop(
        columns=["_race_dt", "_rank_v", "_is_win_v", "_is_place_v"],
        inplace=True,
        errors="ignore",
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
    featured = add_rolling_features(featured)

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


def prepare_ltr_data(
    df: pd.DataFrame,
) -> tuple[pd.DataFrame, pd.Series, np.ndarray]:
    """
    Learning-to-Rank용 데이터를 구성합니다.

    Returns:
        X: 피처 행렬
        y: 관련도 레이블 (field_size - rank + 1; 1위가 가장 높음)
        groups: 각 쿼리(경주)에 속한 문서(말) 수 배열
    """
    featured = engineer_features(df)
    featured = add_rolling_features(featured)
    featured = featured[featured["rank"] > 0].copy()

    featured = featured.sort_values(
        ["race_date", "race_no", "horse_no"]
    ).reset_index(drop=True)

    race_max_rank = featured.groupby(
        ["meet", "race_date", "race_no"]
    )["rank"].transform("max")
    featured["relevance"] = (race_max_rank - featured["rank"] + 1).clip(lower=0)

    groups = (
        featured.groupby(["meet", "race_date", "race_no"])
        .size()
        .values
    )

    available = [c for c in FEATURE_COLUMNS if c in featured.columns]
    X = featured[available].fillna(0)
    y = featured["relevance"]

    return X, y, groups
