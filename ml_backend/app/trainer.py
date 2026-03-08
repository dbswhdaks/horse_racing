"""
XGBoost 모델 학습 및 평가 모듈.

두 가지 모델을 학습합니다:
  1. win_model: 1착 예측 (이진 분류)
  2. place_model: 3착 이내 예측 (이진 분류)
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
    classification_report,
)
from datetime import datetime

from app.config import MODEL_DIR, DATA_DIR
from app.feature_engineering import engineer_features, prepare_xy, FEATURE_COLUMNS


def train_model(
    data_path: str | None = None,
    n_splits: int = 5,
) -> dict:
    """
    학습 데이터로 XGBoost 모델을 학습합니다.

    Returns:
        학습 결과 메트릭을 담은 dict
    """
    if data_path is None:
        data_path = os.path.join(DATA_DIR, "race_data.csv")

    if not os.path.exists(data_path):
        raise FileNotFoundError(f"학습 데이터가 없습니다: {data_path}")

    print(f"데이터 로딩: {data_path}")
    df = pd.read_csv(data_path)
    print(f"전체 {len(df)}행 로드")

    df = df.sort_values(["race_date", "race_no", "horse_no"]).reset_index(drop=True)

    results = {}

    for target_name in ["is_win", "is_place"]:
        print(f"\n{'='*50}")
        print(f"모델 학습: {target_name}")
        print(f"{'='*50}")

        X, y = prepare_xy(df, target=target_name)
        print(f"피처 shape: {X.shape}, 양성 비율: {y.mean():.4f}")

        pos_count = y.sum()
        neg_count = len(y) - pos_count
        scale_pos_weight = neg_count / max(pos_count, 1)

        params = {
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

        tscv = TimeSeriesSplit(n_splits=n_splits)
        fold_metrics = []

        for fold, (train_idx, val_idx) in enumerate(tscv.split(X)):
            X_train, X_val = X.iloc[train_idx], X.iloc[val_idx]
            y_train, y_val = y.iloc[train_idx], y.iloc[val_idx]

            model = xgb.XGBClassifier(**params)
            model.fit(
                X_train, y_train,
                eval_set=[(X_val, y_val)],
                verbose=False,
            )

            y_pred_proba = model.predict_proba(X_val)[:, 1]
            y_pred = (y_pred_proba >= 0.5).astype(int)

            metrics = {
                "fold": fold,
                "accuracy": accuracy_score(y_val, y_pred),
                "auc": roc_auc_score(y_val, y_pred_proba) if y_val.nunique() > 1 else 0,
                "logloss": log_loss(y_val, y_pred_proba),
            }
            fold_metrics.append(metrics)
            print(f"  Fold {fold}: AUC={metrics['auc']:.4f}, "
                  f"Acc={metrics['accuracy']:.4f}, "
                  f"LogLoss={metrics['logloss']:.4f}")

        print(f"\n최종 모델 학습 (전체 데이터)...")
        final_params = {k: v for k, v in params.items() if k != "early_stopping_rounds"}
        final_model = xgb.XGBClassifier(**final_params)
        final_model.fit(X, y, verbose=False)

        model_path = os.path.join(MODEL_DIR, f"{target_name}_model.json")
        final_model.save_model(model_path)
        print(f"모델 저장: {model_path}")

        importance = dict(zip(
            X.columns.tolist(),
            final_model.feature_importances_.tolist(),
        ))
        importance = dict(sorted(importance.items(), key=lambda x: -x[1]))

        avg_metrics = {
            "avg_auc": np.mean([m["auc"] for m in fold_metrics]),
            "avg_accuracy": np.mean([m["accuracy"] for m in fold_metrics]),
            "avg_logloss": np.mean([m["logloss"] for m in fold_metrics]),
            "feature_importance": importance,
            "fold_details": fold_metrics,
        }
        results[target_name] = avg_metrics

        print(f"\n  평균 AUC: {avg_metrics['avg_auc']:.4f}")
        print(f"  평균 Accuracy: {avg_metrics['avg_accuracy']:.4f}")
        print(f"  피처 중요도 Top 5:")
        for fname, fval in list(importance.items())[:5]:
            print(f"    {fname}: {fval:.4f}")

    feature_names = [c for c in FEATURE_COLUMNS if c in X.columns]
    meta = {
        "trained_at": datetime.now().isoformat(),
        "data_rows": len(df),
        "feature_names": feature_names,
        "model_version": f"xgb-{datetime.now().strftime('%Y%m%d')}",
        "metrics": {
            k: {mk: mv for mk, mv in v.items() if mk != "fold_details"}
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

    parser = argparse.ArgumentParser(description="경마 예측 모델 학습")
    parser.add_argument("--data", default=None, help="학습 데이터 CSV 경로")
    parser.add_argument("--splits", type=int, default=5, help="CV fold 수")
    args = parser.parse_args()

    train_model(data_path=args.data, n_splits=args.splits)
