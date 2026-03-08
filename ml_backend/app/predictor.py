"""
학습된 모델을 사용한 경마 예측 모듈.

XGBoost / LightGBM / CatBoost 분류 모델과
Learning-to-Rank 모델을 조합하여 예측합니다.
"""

import os
import json
import joblib
import numpy as np
import pandas as pd
from datetime import datetime

from app.config import MODEL_DIR, DATA_DIR
from app.feature_engineering import (
    engineer_features,
    add_rolling_features,
    FEATURE_COLUMNS,
)
from app.data_collector import (
    fetch_entry_list,
    fetch_race_results,
    load_historical_data,
    _safe_float,
    _safe_int,
)
from app.supabase_client import upsert_predictions


class HorseRacingPredictor:
    def __init__(self):
        self.win_model = None
        self.place_model = None
        self.ltr_model = None
        self.meta: dict = {}
        self.historical_df: pd.DataFrame | None = None
        self._load_models()
        self._load_historical()

    # ------------------------------------------------------------------
    # 모델 로드
    # ------------------------------------------------------------------

    def _load_models(self):
        meta_path = os.path.join(MODEL_DIR, "model_meta.json")
        if os.path.exists(meta_path):
            with open(meta_path, "r", encoding="utf-8") as f:
                self.meta = json.load(f)

        self.win_model = self._load_single("is_win")
        self.place_model = self._load_single("is_place")
        self.ltr_model = self._load_ltr()

    def _load_single(self, target: str):
        """joblib(.pkl) → XGBoost(.json) 순서로 시도합니다."""
        pkl_path = os.path.join(MODEL_DIR, f"{target}_model.pkl")
        json_path = os.path.join(MODEL_DIR, f"{target}_model.json")

        if os.path.exists(pkl_path):
            model = joblib.load(pkl_path)
            model_type = self.meta.get("best_models", {}).get(target, "unknown")
            print(f"[MODEL] {target} 로드 완료 ({model_type}): {pkl_path}")
            return model

        if os.path.exists(json_path):
            import xgboost as xgb
            model = xgb.XGBClassifier()
            model.load_model(json_path)
            print(f"[MODEL] {target} 로드 완료 (xgboost-legacy): {json_path}")
            return model

        print(f"[MODEL] {target} 모델 파일 없음")
        return None

    def _load_ltr(self):
        ltr_path = os.path.join(MODEL_DIR, "ltr_model.pkl")
        if os.path.exists(ltr_path):
            model = joblib.load(ltr_path)
            print(f"[MODEL] LTR 모델 로드 완료: {ltr_path}")
            return model
        return None

    def _load_historical(self):
        """롤링 피처 계산을 위한 과거 데이터를 캐시합니다."""
        try:
            self.historical_df = load_historical_data()
            if not self.historical_df.empty:
                print(f"[DATA] 과거 데이터 {len(self.historical_df)}행 로드")
            else:
                self.historical_df = None
        except Exception as e:
            print(f"[WARN] 과거 데이터 로드 실패: {e}")
            self.historical_df = None

    # ------------------------------------------------------------------
    # 속성
    # ------------------------------------------------------------------

    @property
    def is_ready(self) -> bool:
        return self.win_model is not None

    @property
    def model_version(self) -> str:
        return self.meta.get("model_version", "unknown")

    # ------------------------------------------------------------------
    # 예측
    # ------------------------------------------------------------------

    def predict(self, meet: str, date: str, race_no: int) -> dict:
        entries = fetch_entry_list(meet, date)
        race_entries = [
            e for e in entries if _safe_int(e.get("rcNo")) == race_no
        ]

        if not race_entries:
            return self._empty_report(meet, date, race_no)

        if not self.is_ready:
            result = self._heuristic_predict(meet, date, race_no, race_entries)
        else:
            result = self._model_predict(meet, date, race_no, race_entries)

        self._save_to_supabase(result)
        return result

    def _model_predict(
        self,
        meet: str,
        date: str,
        race_no: int,
        entries: list[dict],
    ) -> dict:
        rows = []
        for e in entries:
            rows.append({
                "meet": meet,
                "race_date": date,
                "race_no": race_no,
                "horse_no": _safe_int(e.get("chulNo")),
                "horse_name": str(e.get("hrName", e.get("hrNm", ""))).strip(),
                "rank": 0,
                "race_distance": _safe_int(e.get("rcDist", 0)),
                "burden_weight": _safe_float(e.get("wgBudam", e.get("wght", 0))),
                "horse_weight": _safe_float(e.get("hrWght", 0)),
                "win_odds": 0.0,
                "place_odds": 0.0,
                "race_time": 0.0,
                "s1f": 0.0,
                "g3f": 0.0,
                "rating": _safe_float(e.get("rating", 0)),
                "age": _safe_int(e.get("age", 0)),
                "sex": str(e.get("sex", "")),
                "jockey_name": str(e.get("jkName", e.get("jkNm", ""))).strip(),
                "trainer_name": str(e.get("trName", e.get("trNm", ""))).strip(),
                "total_races": _safe_int(e.get("rcCntT") or e.get("totalCnt", 0)),
                "win_count": _safe_int(e.get("ord1CntT") or e.get("ord1Cnt", 0)),
                "place_count": _safe_int(e.get("ord2CntT") or e.get("ord2Cnt", 0)),
                "total_prize": _safe_int(e.get("chaksunT") or e.get("totalPrz", 0)),
                "recent_prize": _safe_int(e.get("chaksunY") or e.get("recentPrz", 0)),
                "birth_place": str(e.get("prd", e.get("birthPlc", ""))),
            })

        current_df = pd.DataFrame(rows)
        featured = self._engineer_with_history(current_df)

        feature_names = self.meta.get("feature_names", FEATURE_COLUMNS)
        available = [c for c in feature_names if c in featured.columns]
        X = featured[available].fillna(0)

        win_proba = self.win_model.predict_proba(X)[:, 1]

        place_proba = np.zeros(len(X))
        if self.place_model is not None:
            place_proba = self.place_model.predict_proba(X)[:, 1]

        ltr_scores = None
        if self.ltr_model is not None:
            ltr_scores = self.ltr_model.predict(X)

        importance_keys = list(
            self.meta.get("metrics", {})
            .get("is_win", {})
            .get("feature_importance", {})
            .keys()
        )[:5]

        predictions = []
        for i, entry in enumerate(entries):
            horse_no = _safe_int(entry.get("chulNo"))
            horse_name = str(entry.get("hrName", entry.get("hrNm", ""))).strip()
            jockey_name = str(entry.get("jkName", entry.get("jkNm", ""))).strip()

            win_p = float(win_proba[i]) * 100
            place_p = float(place_proba[i]) * 100

            tags = self._generate_tags(entry, win_p)

            feat_imp = {}
            if hasattr(self.win_model, "feature_importances_"):
                for k in importance_keys:
                    idx = available.index(k) if k in available else -1
                    if idx >= 0:
                        feat_imp[k] = float(self.win_model.feature_importances_[idx])
            elif hasattr(self.win_model, "get_feature_importance"):
                fi = self.win_model.get_feature_importance()
                for k in importance_keys:
                    idx = available.index(k) if k in available else -1
                    if idx >= 0 and idx < len(fi):
                        feat_imp[k] = float(fi[idx])

            pred_entry = {
                "horse_no": horse_no,
                "horse_name": horse_name,
                "jockey_name": jockey_name,
                "win_probability": round(win_p, 2),
                "place_probability": round(place_p, 2),
                "tags": tags,
                "feature_importance": feat_imp,
            }
            if ltr_scores is not None:
                pred_entry["rank_score"] = round(float(ltr_scores[i]), 4)

            predictions.append(pred_entry)

        if ltr_scores is not None:
            predictions.sort(key=lambda x: -x.get("rank_score", 0))
        else:
            predictions.sort(key=lambda x: -x["win_probability"])

        return {
            "race_id": f"{meet}_{date}_{race_no}",
            "race_date": date,
            "meet": meet,
            "race_no": race_no,
            "predictions": predictions,
            "model_version": self.model_version,
            "generated_at": datetime.now().isoformat(),
        }

    def _engineer_with_history(self, current_df: pd.DataFrame) -> pd.DataFrame:
        """과거 데이터를 결합하여 롤링 피처를 포함한 피처를 생성합니다."""
        if self.historical_df is not None and not self.historical_df.empty:
            hist = self.historical_df.copy()
            for col in current_df.columns:
                if col not in hist.columns:
                    hist[col] = "" if hist.dtypes.get(col) == object else 0
            combined = pd.concat([hist, current_df], ignore_index=True)
        else:
            combined = current_df.copy()

        featured = engineer_features(combined)
        featured = add_rolling_features(featured)

        return featured.tail(len(current_df)).reset_index(drop=True)

    # ------------------------------------------------------------------
    # 휴리스틱 예측 (모델 없을 때)
    # ------------------------------------------------------------------

    def _heuristic_predict(
        self, meet: str, date: str, race_no: int, entries: list[dict],
    ) -> dict:
        scores = []
        for e in entries:
            score = 10.0
            rating = _safe_float(e.get("rating", 0))
            total_races = _safe_int(e.get("rcCntT") or e.get("totalCnt", 0))
            win_cnt = _safe_int(e.get("ord1CntT") or e.get("ord1Cnt", 0))
            place_cnt = _safe_int(e.get("ord2CntT") or e.get("ord2Cnt", 0))
            recent_prize = _safe_int(e.get("chaksunY") or e.get("recentPrz", 0))
            weight = _safe_float(e.get("wgBudam", e.get("wght", 54)))

            if rating > 0:
                score += rating * 0.3
            if total_races > 0:
                score += (win_cnt / total_races) * 50
                score += (place_cnt / total_races) * 20
            if recent_prize > 0:
                score += min(recent_prize / 100000, 20)
            score -= (weight - 54) * 0.3
            score = max(score, 1)
            scores.append(score)

        total = sum(scores)
        predictions = []
        for i, e in enumerate(entries):
            horse_no = _safe_int(e.get("chulNo"))
            horse_name = str(e.get("hrName", e.get("hrNm", ""))).strip()
            jockey_name = str(e.get("jkName", e.get("jkNm", ""))).strip()

            win_p = (scores[i] / total * 100) if total > 0 else 0
            place_p = min(win_p * 2.2, 95)
            tags = self._generate_tags(e, win_p)

            predictions.append({
                "horse_no": horse_no,
                "horse_name": horse_name,
                "jockey_name": jockey_name,
                "win_probability": round(win_p, 2),
                "place_probability": round(place_p, 2),
                "tags": tags,
                "feature_importance": {},
            })

        predictions.sort(key=lambda x: -x["win_probability"])
        return {
            "race_id": f"{meet}_{date}_{race_no}",
            "race_date": date,
            "meet": meet,
            "race_no": race_no,
            "predictions": predictions,
            "model_version": "heuristic-1.0",
            "generated_at": datetime.now().isoformat(),
        }

    # ------------------------------------------------------------------
    # 유틸
    # ------------------------------------------------------------------

    def _generate_tags(self, entry: dict, win_prob: float) -> list[str]:
        tags = []
        total_races = _safe_int(entry.get("rcCntT") or entry.get("totalCnt", 0))
        win_cnt = _safe_int(entry.get("ord1CntT") or entry.get("ord1Cnt", 0))
        rating = _safe_float(entry.get("rating", 0))
        recent_prize = _safe_int(entry.get("chaksunY") or entry.get("recentPrz", 0))
        weight = _safe_float(entry.get("wgBudam", entry.get("wght", 54)))

        if total_races > 0 and (win_cnt / total_races) >= 0.2:
            tags.append("고승률")
        if rating >= 60:
            tags.append("고레이팅")
        if total_races >= 20 and win_cnt >= 3:
            tags.append("경험마")
        if recent_prize > 500000:
            tags.append("최근호조")
        if weight <= 53:
            tags.append("경량")
        if win_prob >= 20:
            tags.append("유력후보")

        return tags

    def _save_to_supabase(self, report: dict):
        try:
            rows = []
            for p in report.get("predictions", []):
                rows.append({
                    "meet": report["meet"],
                    "race_date": report["race_date"],
                    "race_no": report["race_no"],
                    "horse_no": p["horse_no"],
                    "horse_name": p["horse_name"],
                    "jockey_name": p.get("jockey_name", ""),
                    "win_probability": p["win_probability"],
                    "place_probability": p["place_probability"],
                    "tags": p["tags"],
                    "feature_importance": p["feature_importance"],
                    "model_version": report["model_version"],
                })
            upsert_predictions(rows)
        except Exception as e:
            print(f"[WARN] Supabase 저장 실패: {e}")

    def _empty_report(self, meet: str, date: str, race_no: int) -> dict:
        return {
            "race_id": f"{meet}_{date}_{race_no}",
            "race_date": date,
            "meet": meet,
            "race_no": race_no,
            "predictions": [],
            "model_version": self.model_version,
            "generated_at": datetime.now().isoformat(),
        }
