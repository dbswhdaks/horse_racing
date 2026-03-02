import os
import json
from datetime import datetime
from typing import Any

import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from xgboost import XGBClassifier

from config import MODEL_DIR, DATA_DIR
from features.engineering import engineer_features, FEATURE_COLUMNS
from services.kra_client import KraClient


class Predictor:
    def __init__(self, client: KraClient) -> None:
        self.client = client
        self.win_model: XGBClassifier | None = None
        self.place_model: RandomForestClassifier | None = None
        self._load_models()

    def _load_models(self) -> None:
        win_path = os.path.join(MODEL_DIR, "xgb_win.joblib")
        place_path = os.path.join(MODEL_DIR, "rf_place.joblib")
        if os.path.exists(win_path):
            self.win_model = joblib.load(win_path)
        if os.path.exists(place_path):
            self.place_model = joblib.load(place_path)

    def train(self, df: pd.DataFrame) -> dict[str, float]:
        """Train both models on provided data. Returns accuracy metrics."""
        featured = engineer_features(df)
        featured = featured[featured["race_time"] > 0]

        X = featured[FEATURE_COLUMNS].values
        y_win = featured["is_win"].values
        y_place = featured["is_place"].values

        self.win_model = XGBClassifier(
            n_estimators=200,
            max_depth=6,
            learning_rate=0.1,
            use_label_encoder=False,
            eval_metric="logloss",
            random_state=42,
        )
        self.win_model.fit(X, y_win)

        self.place_model = RandomForestClassifier(
            n_estimators=200,
            max_depth=8,
            random_state=42,
        )
        self.place_model.fit(X, y_place)

        os.makedirs(MODEL_DIR, exist_ok=True)
        joblib.dump(self.win_model, os.path.join(MODEL_DIR, "xgb_win.joblib"))
        joblib.dump(self.place_model, os.path.join(MODEL_DIR, "rf_place.joblib"))

        win_acc = float(np.mean(self.win_model.predict(X) == y_win))
        place_acc = float(np.mean(self.place_model.predict(X) == y_place))

        return {"win_accuracy": win_acc, "place_accuracy": place_acc}

    async def predict_race(
        self, meet: str, date: str, race_no: int
    ) -> dict[str, Any] | None:
        """Predict win/place probabilities for all horses in a race."""
        if self.win_model is None or self.place_model is None:
            return None

        entries = []
        try:
            entries = await self.client.get_start_list(meet=meet, rc_date=date, rc_no=race_no)
        except Exception:
            pass

        if not entries:
            entries = self._build_entries_from_seed(meet, date, race_no)
        if not entries:
            return None

        all_results = self._load_cached_results()

        predictions = []
        for entry in entries:
            horse_name = entry.get("hrNm", "")
            features = self._build_features_for_entry(entry, all_results)

            X = np.array([features])
            win_proba = float(self.win_model.predict_proba(X)[0][1])
            place_proba = float(self.place_model.predict_proba(X)[0][1])

            importance = dict(
                zip(FEATURE_COLUMNS, self.win_model.feature_importances_.tolist())
            )
            top_features = dict(
                sorted(importance.items(), key=lambda x: x[1], reverse=True)[:5]
            )

            tags = self._generate_tags(entry, features, all_results, horse_name)

            predictions.append({
                "horse_no": int(entry.get("hrNo", entry.get("chulNo", 0))),
                "horse_name": horse_name,
                "win_probability": round(win_proba * 100, 2),
                "place_probability": round(place_proba * 100, 2),
                "tags": tags,
                "feature_importance": {
                    k: round(v, 4) for k, v in top_features.items()
                },
            })

        predictions.sort(key=lambda p: p["win_probability"], reverse=True)

        return {
            "race_id": f"{meet}_{date}_{race_no}",
            "race_date": date,
            "meet": meet,
            "race_no": race_no,
            "predictions": predictions,
            "model_version": "1.0",
            "generated_at": datetime.now().isoformat(),
        }

    def _build_features_for_entry(
        self, entry: dict, all_results: pd.DataFrame
    ) -> list[float]:
        horse_name = entry.get("hrNm", "")
        jockey_name = entry.get("jkNm", entry.get("jockyNm", ""))
        distance = _to_float(entry.get("rcDist", 0))
        weight = _to_float(entry.get("wght", entry.get("brdnWt", 0)))
        horse_weight = _to_float(entry.get("hrWght", entry.get("rcHrsWt", 0)))

        defaults = {col: 0.0 for col in FEATURE_COLUMNS}
        defaults["distance"] = distance
        defaults["weight"] = weight
        defaults["horse_weight"] = horse_weight

        if not all_results.empty and horse_name:
            horse_data = all_results[all_results.get("horse", pd.Series()) == horse_name]
            if not horse_data.empty:
                recent = horse_data.tail(5)
                defaults["s1f"] = recent["s1f"].mean() if "s1f" in recent else 0
                defaults["g3f"] = recent["g3f"].mean() if "g3f" in recent else 0
                defaults["speed"] = recent["speed"].mean() if "speed" in recent else 0
                defaults["s1f_ratio"] = recent["s1f_ratio"].mean() if "s1f_ratio" in recent else 0
                defaults["g3f_ratio"] = recent["g3f_ratio"].mean() if "g3f_ratio" in recent else 0
                defaults["rank_avg5"] = recent["rank"].mean() if "rank" in recent else 0
                defaults["race_time_avg5"] = recent["race_time"].mean() if "race_time" in recent else 0
                defaults["speed_avg5"] = defaults["speed"]
                defaults["s1f_avg5"] = defaults["s1f"]
                defaults["g3f_avg5"] = defaults["g3f"]

                if len(horse_data) >= 2:
                    prev_weight = horse_data.iloc[-2].get("weight", weight)
                    defaults["weight_change"] = weight - prev_weight

        if not all_results.empty and jockey_name:
            jockey_data = all_results[all_results.get("jockey", pd.Series()) == jockey_name]
            if not jockey_data.empty:
                total = len(jockey_data)
                defaults["jockey_win_rate"] = (jockey_data.get("is_win", pd.Series()).sum() / total) if total else 0
                defaults["jockey_place_rate"] = (jockey_data.get("is_place", pd.Series()).sum() / total) if total else 0

                jd = jockey_data[jockey_data.get("distance", pd.Series()) == distance]
                if len(jd) > 0:
                    defaults["jockey_dist_win_rate"] = jd.get("is_win", pd.Series()).sum() / len(jd)

        dist_map = {
            "sprint": 0, "mile_short": 1, "mile": 2, "middle": 3, "long": 4
        }
        if distance <= 1200:
            defaults["dist_cat_code"] = 0
        elif distance <= 1400:
            defaults["dist_cat_code"] = 1
        elif distance <= 1800:
            defaults["dist_cat_code"] = 2
        elif distance <= 2400:
            defaults["dist_cat_code"] = 3
        else:
            defaults["dist_cat_code"] = 4

        return [defaults[col] for col in FEATURE_COLUMNS]

    def _load_cached_results(self) -> pd.DataFrame:
        frames: list[pd.DataFrame] = []
        if not os.path.exists(DATA_DIR):
            return pd.DataFrame()
        for f in os.listdir(DATA_DIR):
            if f.endswith(".csv"):
                try:
                    frames.append(pd.read_csv(os.path.join(DATA_DIR, f)))
                except Exception:
                    continue
        if not frames:
            return pd.DataFrame()
        combined = pd.concat(frames, ignore_index=True)
        try:
            return engineer_features(combined)
        except Exception:
            return combined

    def _build_entries_from_seed(self, meet: str, date: str, race_no: int) -> list[dict]:
        """Build pseudo entry list from seed data for prediction."""
        cached = self._load_cached_results()
        if cached.empty:
            return []

        if "meet_code" in cached.columns:
            race_data = cached[cached["meet_code"].astype(str) == str(meet)]
        else:
            race_data = cached

        if race_data.empty:
            return []

        horses = race_data.groupby("horse").last().reset_index()
        sample = horses.head(12)

        entries = []
        for i, row in sample.iterrows():
            entries.append({
                "hrNo": i + 1,
                "hrNm": row.get("horse", f"Horse{i+1}"),
                "jkNm": row.get("jockey", ""),
                "trNm": "",
                "wght": row.get("weight", 55),
                "hrWght": row.get("horse_weight", 470),
                "rcDist": row.get("distance", 1400),
                "age": 4,
                "sex": "수",
            })
        return entries

    @staticmethod
    def _generate_tags(
        entry: dict, features: list[float], results: pd.DataFrame, horse_name: str
    ) -> list[str]:
        tags: list[str] = []
        feat = dict(zip(FEATURE_COLUMNS, features))

        if feat.get("s1f_ratio", 0) > 0.18:
            tags.append("선행마")
        elif feat.get("g3f_ratio", 0) > 0.45:
            tags.append("추입마")

        if feat.get("g3f", 0) > 0 and feat.get("g3f_avg5", 0) > 0:
            if feat["g3f"] < feat["g3f_avg5"] * 0.98:
                tags.append("스퍼트 강화")

        if feat.get("weight_change", 0) < -1:
            tags.append("감량")
        elif feat.get("weight_change", 0) > 1:
            tags.append("증량")

        if feat.get("jockey_win_rate", 0) >= 0.2:
            tags.append("명기수")

        if feat.get("rank_avg5", 0) > 0 and feat["rank_avg5"] <= 3:
            tags.append("최근호조")
        elif feat.get("rank_avg5", 0) > 6:
            tags.append("부진중")

        return tags


def _to_float(val: Any) -> float:
    try:
        return float(val)
    except (TypeError, ValueError):
        return 0.0
