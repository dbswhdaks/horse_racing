"""
멀티 모델 학습 및 평가 모듈.

XGBoost, LightGBM, CatBoost를 CV로 비교하여 최적 모델을 자동 선택하고,
Learning-to-Rank(LambdaMART) 모델도 함께 학습합니다.
"""

import os
import json
import joblib
import numpy as np
import pandas as pd
import xgboost as xgb
from sklearn.model_selection import TimeSeriesSplit
from sklearn.metrics import (
    accuracy_score,
    roc_auc_score,
    log_loss,
    ndcg_score,
)
from datetime import datetime

from app.config import MODEL_DIR, DATA_DIR
from app.feature_engineering import (
    engineer_features,
    prepare_xy,
    prepare_ltr_data,
    FEATURE_COLUMNS,
)

try:
    import lightgbm as lgb
    HAS_LIGHTGBM = True
except ImportError:
    HAS_LIGHTGBM = False

try:
    import catboost as cb
    HAS_CATBOOST = True
except ImportError:
    HAS_CATBOOST = False


# ---------------------------------------------------------------------------
# 모델별 하이퍼파라미터 설정
# ---------------------------------------------------------------------------

def _xgb_params(scale_pos_weight: float) -> dict:
    return {
        "objective": "binary:logistic",
        "eval_metric": "logloss",
        "max_depth": 6,
        "learning_rate": 0.05,
        "n_estimators": 500,
        "subsample": 0.8,
        "colsample_bytree": 0.8,
        "min_child_weight": 5,
        "gamma": 0.1,
        "reg_alpha": 0.1,
        "reg_lambda": 1.0,
        "scale_pos_weight": scale_pos_weight,
        "random_state": 42,
        "n_jobs": -1,
        "early_stopping_rounds": 30,
    }


def _lgb_params(scale_pos_weight: float) -> dict:
    return {
        "objective": "binary",
        "metric": "binary_logloss",
        "max_depth": 6,
        "learning_rate": 0.05,
        "n_estimators": 500,
        "subsample": 0.8,
        "colsample_bytree": 0.8,
        "min_child_samples": 20,
        "reg_alpha": 0.1,
        "reg_lambda": 1.0,
        "scale_pos_weight": scale_pos_weight,
        "random_state": 42,
        "n_jobs": -1,
        "verbose": -1,
    }


def _cb_params(scale_pos_weight: float) -> dict:
    return {
        "loss_function": "Logloss",
        "eval_metric": "Logloss",
        "depth": 6,
        "learning_rate": 0.05,
        "iterations": 500,
        "subsample": 0.8,
        "rsm": 0.8,
        "min_data_in_leaf": 20,
        "l2_leaf_reg": 1.0,
        "auto_class_weights": "Balanced" if scale_pos_weight > 2 else None,
        "random_seed": 42,
        "verbose": 0,
        "thread_count": -1,
    }


# ---------------------------------------------------------------------------
# 모델 학습 / 평가 유틸
# ---------------------------------------------------------------------------

def _build_and_fit(
    name: str,
    params: dict,
    X_train: pd.DataFrame,
    y_train: pd.Series,
    X_val: pd.DataFrame,
    y_val: pd.Series,
):
    """모델을 생성하고 early stopping과 함께 학습합니다."""
    if name == "xgboost":
        model = xgb.XGBClassifier(**params)
        model.fit(X_train, y_train, eval_set=[(X_val, y_val)], verbose=False)

    elif name == "lightgbm":
        model = lgb.LGBMClassifier(**params)
        model.fit(
            X_train, y_train,
            eval_set=[(X_val, y_val)],
            callbacks=[
                lgb.early_stopping(stopping_rounds=30, verbose=False),
                lgb.log_evaluation(period=0),
            ],
        )

    elif name == "catboost":
        clean = {k: v for k, v in params.items() if v is not None}
        model = cb.CatBoostClassifier(**clean)
        model.fit(
            X_train, y_train,
            eval_set=(X_val, y_val),
            early_stopping_rounds=30,
        )

    else:
        raise ValueError(f"Unknown model: {name}")

    return model


def _evaluate(model, X_val: pd.DataFrame, y_val: pd.Series) -> dict:
    y_proba = model.predict_proba(X_val)[:, 1]
    y_pred = (y_proba >= 0.5).astype(int)
    return {
        "accuracy": float(accuracy_score(y_val, y_pred)),
        "auc": float(roc_auc_score(y_val, y_proba)) if y_val.nunique() > 1 else 0.0,
        "logloss": float(log_loss(y_val, y_proba)),
    }


def _get_feature_importance(model, feature_names: list[str]) -> dict:
    if hasattr(model, "feature_importances_"):
        imp = dict(zip(feature_names, model.feature_importances_.tolist()))
    elif hasattr(model, "get_feature_importance"):
        imp = dict(zip(feature_names, model.get_feature_importance().tolist()))
    else:
        return {}
    return dict(sorted(imp.items(), key=lambda x: -x[1]))


# ---------------------------------------------------------------------------
# 분류 모델 학습 (멀티 모델 비교)
# ---------------------------------------------------------------------------

def _cross_validate_model(
    name: str,
    params_fn,
    X: pd.DataFrame,
    y: pd.Series,
    n_splits: int,
) -> dict:
    """TimeSeriesSplit CV로 단일 모델을 평가합니다."""
    pos = y.sum()
    neg = len(y) - pos
    spw = neg / max(pos, 1)

    tscv = TimeSeriesSplit(n_splits=n_splits)
    fold_metrics = []

    for fold, (train_idx, val_idx) in enumerate(tscv.split(X)):
        X_tr, X_vl = X.iloc[train_idx], X.iloc[val_idx]
        y_tr, y_vl = y.iloc[train_idx], y.iloc[val_idx]

        params = params_fn(spw)
        model = _build_and_fit(name, params, X_tr, y_tr, X_vl, y_vl)
        metrics = _evaluate(model, X_vl, y_vl)
        metrics["fold"] = fold
        fold_metrics.append(metrics)

    avg_auc = float(np.mean([m["auc"] for m in fold_metrics]))
    avg_acc = float(np.mean([m["accuracy"] for m in fold_metrics]))
    avg_ll = float(np.mean([m["logloss"] for m in fold_metrics]))

    return {
        "avg_auc": avg_auc,
        "avg_accuracy": avg_acc,
        "avg_logloss": avg_ll,
        "fold_details": fold_metrics,
    }


def _train_final_model(
    name: str,
    params_fn,
    X: pd.DataFrame,
    y: pd.Series,
):
    """전체 데이터로 최종 모델을 학습합니다."""
    spw = (len(y) - y.sum()) / max(y.sum(), 1)
    params = params_fn(spw)

    if name == "xgboost":
        clean = {k: v for k, v in params.items() if k != "early_stopping_rounds"}
        model = xgb.XGBClassifier(**clean)
        model.fit(X, y, verbose=False)
    elif name == "lightgbm":
        model = lgb.LGBMClassifier(**params)
        model.fit(X, y)
    elif name == "catboost":
        clean = {k: v for k, v in params.items() if v is not None}
        model = cb.CatBoostClassifier(**clean)
        model.fit(X, y)
    else:
        raise ValueError(f"Unknown model: {name}")

    return model


# ---------------------------------------------------------------------------
# LTR 모델 학습
# ---------------------------------------------------------------------------

def _train_ltr(
    df: pd.DataFrame,
) -> dict:
    """LightGBM LambdaMART 기반 Learning-to-Rank 모델을 학습합니다."""
    if not HAS_LIGHTGBM:
        print("[LTR] lightgbm 미설치 → LTR 학습 생략")
        return {"status": "skipped", "reason": "lightgbm not installed"}

    X, y, groups = prepare_ltr_data(df)
    if len(groups) < 10:
        print("[LTR] 경주 수 부족 → LTR 학습 생략")
        return {"status": "skipped", "reason": "not enough races"}

    cum = np.cumsum(groups)
    split_race = int(len(groups) * 0.8)
    split_row = cum[split_race - 1]

    X_tr, X_vl = X.iloc[:split_row], X.iloc[split_row:]
    y_tr, y_vl = y.iloc[:split_row], y.iloc[split_row:]
    g_tr = groups[:split_race]
    g_vl = groups[split_race:]

    model = lgb.LGBMRanker(
        objective="lambdarank",
        metric="ndcg",
        n_estimators=300,
        learning_rate=0.05,
        max_depth=6,
        num_leaves=31,
        min_child_samples=20,
        subsample=0.8,
        colsample_bytree=0.8,
        lambdarank_truncation_level=10,
        random_state=42,
        n_jobs=-1,
        verbose=-1,
    )

    model.fit(
        X_tr, y_tr,
        group=g_tr,
        eval_set=[(X_vl, y_vl)],
        eval_group=[g_vl],
        callbacks=[
            lgb.early_stopping(stopping_rounds=30, verbose=False),
            lgb.log_evaluation(period=0),
        ],
    )

    val_scores = model.predict(X_vl)
    ndcg_3 = _compute_group_ndcg(y_vl.values, val_scores, g_vl, k=3)
    ndcg_5 = _compute_group_ndcg(y_vl.values, val_scores, g_vl, k=5)

    print(f"[LTR] NDCG@3={ndcg_3:.4f}  NDCG@5={ndcg_5:.4f}")

    final_model = lgb.LGBMRanker(
        objective="lambdarank",
        metric="ndcg",
        n_estimators=300,
        learning_rate=0.05,
        max_depth=6,
        num_leaves=31,
        min_child_samples=20,
        subsample=0.8,
        colsample_bytree=0.8,
        lambdarank_truncation_level=10,
        random_state=42,
        n_jobs=-1,
        verbose=-1,
    )
    final_model.fit(X, y, group=groups)

    ltr_path = os.path.join(MODEL_DIR, "ltr_model.pkl")
    joblib.dump(final_model, ltr_path)
    print(f"[LTR] 모델 저장: {ltr_path}")

    return {
        "status": "ok",
        "ndcg_3": ndcg_3,
        "ndcg_5": ndcg_5,
        "n_races_train": int(len(g_tr)),
        "n_races_val": int(len(g_vl)),
    }


def _compute_group_ndcg(
    y_true: np.ndarray,
    y_score: np.ndarray,
    groups: np.ndarray,
    k: int = 5,
) -> float:
    """그룹(경주)별 NDCG를 계산하여 평균을 반환합니다."""
    ndcgs = []
    offset = 0
    for g in groups:
        g = int(g)
        if g < 2:
            offset += g
            continue
        yt = y_true[offset: offset + g].reshape(1, -1)
        ys = y_score[offset: offset + g].reshape(1, -1)
        try:
            ndcgs.append(float(ndcg_score(yt, ys, k=min(k, g))))
        except ValueError:
            pass
        offset += g
    return float(np.mean(ndcgs)) if ndcgs else 0.0


# ---------------------------------------------------------------------------
# 메인 학습 함수
# ---------------------------------------------------------------------------

def train_model(
    data_path: str | None = None,
    n_splits: int = 5,
    models_to_try: list[str] | None = None,
) -> dict:
    """
    학습 데이터로 최적 분류 모델 + LTR 모델을 학습합니다.

    Args:
        data_path: CSV 경로 (None이면 기본 위치)
        n_splits: CV fold 수
        models_to_try: 시도할 모델 목록 (기본: 설치된 모든 모델)

    Returns:
        학습 결과 메트릭 dict
    """
    if data_path is None:
        data_path = os.path.join(DATA_DIR, "race_data.csv")

    if not os.path.exists(data_path):
        raise FileNotFoundError(f"학습 데이터가 없습니다: {data_path}")

    print(f"데이터 로딩: {data_path}")
    df = pd.read_csv(data_path)
    print(f"전체 {len(df)}행 로드")

    df = df.sort_values(["race_date", "race_no", "horse_no"]).reset_index(drop=True)

    available_models: dict[str, callable] = {"xgboost": _xgb_params}
    if HAS_LIGHTGBM:
        available_models["lightgbm"] = _lgb_params
    if HAS_CATBOOST:
        available_models["catboost"] = _cb_params

    if models_to_try:
        available_models = {
            k: v for k, v in available_models.items() if k in models_to_try
        }

    if not available_models:
        raise RuntimeError("사용 가능한 모델이 없습니다.")

    print(f"비교 대상 모델: {list(available_models.keys())}")

    results = {}
    best_models_info = {}

    for target_name in ["is_win", "is_place"]:
        print(f"\n{'='*60}")
        print(f"타겟: {target_name}")
        print(f"{'='*60}")

        X, y = prepare_xy(df, target=target_name)
        print(f"피처 shape: {X.shape}, 양성 비율: {y.mean():.4f}")

        comparison = {}
        for model_name, params_fn in available_models.items():
            print(f"\n  [{model_name}] CV 시작...")
            try:
                cv_result = _cross_validate_model(
                    model_name, params_fn, X, y, n_splits,
                )
                comparison[model_name] = cv_result
                print(
                    f"  [{model_name}] "
                    f"AUC={cv_result['avg_auc']:.4f}  "
                    f"Acc={cv_result['avg_accuracy']:.4f}  "
                    f"LogLoss={cv_result['avg_logloss']:.4f}"
                )
            except Exception as e:
                print(f"  [{model_name}] 학습 실패: {e}")
                comparison[model_name] = {"avg_auc": 0, "error": str(e)}

        best_name = max(comparison, key=lambda k: comparison[k].get("avg_auc", 0))
        best_auc = comparison[best_name].get("avg_auc", 0)
        print(f"\n  ★ 최적 모델: {best_name} (AUC={best_auc:.4f})")

        print(f"\n  최종 모델 학습 ({best_name}, 전체 데이터)...")
        final_model = _train_final_model(
            best_name, available_models[best_name], X, y,
        )

        model_path = os.path.join(MODEL_DIR, f"{target_name}_model.pkl")
        joblib.dump(final_model, model_path)
        print(f"  모델 저장: {model_path}")

        importance = _get_feature_importance(final_model, X.columns.tolist())
        if importance:
            print(f"  피처 중요도 Top 5:")
            for fname, fval in list(importance.items())[:5]:
                print(f"    {fname}: {fval:.4f}")

        best_cv = comparison[best_name]
        results[target_name] = {
            "best_model": best_name,
            "avg_auc": best_cv.get("avg_auc", 0),
            "avg_accuracy": best_cv.get("avg_accuracy", 0),
            "avg_logloss": best_cv.get("avg_logloss", 0),
            "feature_importance": importance,
            "comparison": {
                k: {mk: mv for mk, mv in v.items() if mk != "fold_details"}
                for k, v in comparison.items()
            },
        }
        best_models_info[target_name] = best_name

    print(f"\n{'='*60}")
    print("LTR 모델 학습")
    print(f"{'='*60}")
    ltr_result = _train_ltr(df)
    results["ltr"] = ltr_result

    ts = datetime.now()
    feature_names = [c for c in FEATURE_COLUMNS if c in X.columns]
    meta = {
        "trained_at": ts.isoformat(),
        "data_rows": len(df),
        "feature_names": feature_names,
        "best_models": best_models_info,
        "model_version": f"multi-{ts.strftime('%Y%m%d')}",
        "metrics": {
            k: {mk: mv for mk, mv in v.items() if mk not in ("comparison", "fold_details")}
            for k, v in results.items()
        },
    }
    meta_path = os.path.join(MODEL_DIR, "model_meta.json")
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2, default=str)
    print(f"\n메타데이터 저장: {meta_path}")

    return results


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="경마 예측 모델 학습 (멀티 모델)")
    parser.add_argument("--data", default=None, help="학습 데이터 CSV 경로")
    parser.add_argument("--splits", type=int, default=5, help="CV fold 수")
    parser.add_argument(
        "--models", nargs="*", default=None,
        help="시도할 모델 (xgboost lightgbm catboost)",
    )
    args = parser.parse_args()

    train_model(
        data_path=args.data,
        n_splits=args.splits,
        models_to_try=args.models,
    )
