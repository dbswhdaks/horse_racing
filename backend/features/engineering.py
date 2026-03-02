import pandas as pd
import numpy as np


def engineer_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Build ML features from raw race result data.

    Expected columns (from KRA AI race result API):
        hrNm, rcTime, ord, rcDist, wght/brdnWt, jkNm, s1f/s1fTm, g3f/g3fTm,
        rcDate/rcDt, meet, hrWght/rcHrsWt, etc.

    Returns a DataFrame with one row per horse-race, with engineered features.
    """
    out = df.copy()

    _unify(out, "rank", ["ord", "rankNo"])
    _unify(out, "horse", ["hrNm"])
    _unify(out, "jockey", ["jkNm", "jockyNm"])
    _unify(out, "distance", ["rcDist"])
    _unify(out, "weight", ["wght", "brdnWt"])
    _unify(out, "horse_weight", ["hrWght", "rcHrsWt"])
    _unify(out, "race_time_raw", ["rcTime", "rcTimeTxt"])
    _unify(out, "s1f_raw", ["s1f", "s1fTm"])
    _unify(out, "g3f_raw", ["g3f", "g3fTm"])
    _unify(out, "race_date", ["rcDate", "rcDt", "collect_date"])
    _unify(out, "meet_code", ["meet", "rccrs_cd"])
    _unify(out, "race_no", ["rcNo"])

    out["rank"] = pd.to_numeric(out["rank"], errors="coerce").fillna(99).astype(int)
    out["distance"] = pd.to_numeric(out["distance"], errors="coerce").fillna(0)
    out["weight"] = pd.to_numeric(out["weight"], errors="coerce").fillna(0)
    out["horse_weight"] = pd.to_numeric(out["horse_weight"], errors="coerce").fillna(0)

    out["race_time"] = out["race_time_raw"].apply(_parse_time)
    out["s1f"] = pd.to_numeric(out["s1f_raw"], errors="coerce").fillna(0)
    out["g3f"] = pd.to_numeric(out["g3f_raw"], errors="coerce").fillna(0)

    out["is_win"] = (out["rank"] == 1).astype(int)
    out["is_place"] = (out["rank"].between(1, 3)).astype(int)

    # Speed features
    out["speed"] = out.apply(
        lambda r: r["distance"] / r["race_time"] if r["race_time"] > 0 else 0, axis=1
    )

    # S1F ratio: early pace relative to total time
    out["s1f_ratio"] = out.apply(
        lambda r: r["s1f"] / r["race_time"] if r["race_time"] > 0 else 0, axis=1
    )

    # G3F ratio: finishing kick strength
    out["g3f_ratio"] = out.apply(
        lambda r: r["g3f"] / r["race_time"] if r["race_time"] > 0 else 0, axis=1
    )

    out.sort_values(["horse", "race_date"], inplace=True)

    # Weight change from previous race
    out["prev_weight"] = out.groupby("horse")["weight"].shift(1)
    out["weight_change"] = out["weight"] - out["prev_weight"]
    out["weight_change"] = out["weight_change"].fillna(0)

    # Rolling stats per horse (last 5 races)
    for col in ["rank", "race_time", "speed", "s1f", "g3f"]:
        rolled = out.groupby("horse")[col].transform(
            lambda x: x.rolling(5, min_periods=1).mean()
        )
        out[f"{col}_avg5"] = rolled

    # Jockey stats: win rate and place rate overall
    jockey_stats = (
        out.groupby("jockey")
        .agg(
            jockey_races=("rank", "count"),
            jockey_wins=("is_win", "sum"),
            jockey_places=("is_place", "sum"),
        )
        .reset_index()
    )
    jockey_stats["jockey_win_rate"] = jockey_stats["jockey_wins"] / jockey_stats["jockey_races"]
    jockey_stats["jockey_place_rate"] = jockey_stats["jockey_places"] / jockey_stats["jockey_races"]
    out = out.merge(jockey_stats[["jockey", "jockey_win_rate", "jockey_place_rate"]], on="jockey", how="left")

    # Jockey-distance win rate
    jd_stats = (
        out.groupby(["jockey", "distance"])
        .agg(jd_races=("rank", "count"), jd_wins=("is_win", "sum"))
        .reset_index()
    )
    jd_stats["jockey_dist_win_rate"] = jd_stats["jd_wins"] / jd_stats["jd_races"]
    out = out.merge(
        jd_stats[["jockey", "distance", "jockey_dist_win_rate"]],
        on=["jockey", "distance"],
        how="left",
    )

    # Distance category
    out["dist_cat"] = pd.cut(
        out["distance"],
        bins=[0, 1200, 1400, 1800, 2400, 9999],
        labels=["sprint", "mile_short", "mile", "middle", "long"],
    )
    out["dist_cat_code"] = out["dist_cat"].cat.codes

    # Meet encoding
    out["meet_encoded"] = pd.Categorical(out["meet_code"]).codes

    out.fillna(0, inplace=True)
    return out


FEATURE_COLUMNS = [
    "distance",
    "weight",
    "horse_weight",
    "s1f",
    "g3f",
    "speed",
    "s1f_ratio",
    "g3f_ratio",
    "weight_change",
    "rank_avg5",
    "race_time_avg5",
    "speed_avg5",
    "s1f_avg5",
    "g3f_avg5",
    "jockey_win_rate",
    "jockey_place_rate",
    "jockey_dist_win_rate",
    "dist_cat_code",
    "meet_encoded",
]


def _unify(df: pd.DataFrame, target: str, candidates: list[str]) -> None:
    if target in df.columns:
        return
    for col in candidates:
        if col in df.columns:
            df[target] = df[col]
            return
    df[target] = ""


def _parse_time(raw: object) -> float:
    s = str(raw).strip()
    if not s or s == "nan":
        return 0.0
    # Formats: "1:23.4", "83.4", "1.23.4"
    parts = s.replace(".", ":").split(":")
    try:
        if len(parts) == 3:
            return float(parts[0]) * 60 + float(parts[1]) + float(parts[2]) / 10
        if len(parts) == 2:
            return float(parts[0]) + float(parts[1]) / 10
        return float(parts[0])
    except ValueError:
        return 0.0
