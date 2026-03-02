from contextlib import asynccontextmanager
from datetime import datetime, timedelta

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

from services.kra_client import KraClient
from services.data_collector import DataCollector
from services.predictor import Predictor
from services.supabase_client import SupabaseDB
from services.seed_data import generate_seed_data

kra_client: KraClient
collector: DataCollector
predictor: Predictor
supa: SupabaseDB


@asynccontextmanager
async def lifespan(app: FastAPI):
    global kra_client, collector, predictor, supa
    kra_client = KraClient()
    collector = DataCollector(kra_client)
    predictor = Predictor(kra_client)
    supa = SupabaseDB()
    yield
    await kra_client.close()


app = FastAPI(
    title="경마 예측 API",
    version="2.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Prediction ──────────────────────────────────────────────


@app.get("/predict/{meet}/{date}/{race_no}")
async def predict(meet: str, date: str, race_no: int):
    # 1) Supabase에 이미 예측이 있으면 반환
    if supa.enabled:
        cached = supa.get_predictions(meet, date, race_no)
        if cached:
            return {
                "race_id": f"{meet}_{date}_{race_no}",
                "race_date": date,
                "meet": meet,
                "race_no": race_no,
                "predictions": cached,
                "model_version": cached[0].get("model_version", ""),
                "generated_at": cached[0].get("created_at", ""),
            }

    # 2) ML 모델로 예측 생성
    result = await predictor.predict_race(meet, date, race_no)
    if result is None:
        raise HTTPException(
            status_code=503,
            detail="모델이 아직 학습되지 않았거나 출마표를 불러올 수 없습니다.",
        )

    # 3) 예측 결과를 Supabase에 저장
    if supa.enabled and result.get("predictions"):
        rows = [
            {
                "meet": meet,
                "race_date": date,
                "race_no": race_no,
                "horse_no": p["horse_no"],
                "horse_name": p["horse_name"],
                "win_probability": p["win_probability"],
                "place_probability": p["place_probability"],
                "tags": p.get("tags", []),
                "feature_importance": p.get("feature_importance", {}),
                "model_version": result.get("model_version", "1.0"),
            }
            for p in result["predictions"]
        ]
        supa.upsert_predictions(rows)

    return result


# ── Data collection ─────────────────────────────────────────


@app.post("/collect")
async def collect_data(
    meet: str = Query(default="1"),
    days: int = Query(default=30, ge=1, le=365),
):
    end = datetime.now()
    start = end - timedelta(days=days)
    df = await collector.collect_race_results(
        meet=meet,
        start_date=start.strftime("%Y%m%d"),
        end_date=end.strftime("%Y%m%d"),
    )
    stored = 0
    if not df.empty and supa.enabled:
        stored = supa.upsert_results(df.to_dict("records"), meet)
    return {"rows_collected": len(df), "rows_synced_to_supabase": stored, "meet": meet}


@app.post("/collect/entries")
async def collect_entries(
    meet: str = Query(default="1"),
    date: str = Query(default=""),
):
    if not date:
        date = datetime.now().strftime("%Y%m%d")
    entries = await kra_client.get_start_list(meet=meet, rc_date=date)
    stored = 0
    if entries and supa.enabled:
        stored = supa.upsert_entries(entries, meet, date)
    return {"entries_collected": len(entries), "entries_synced": stored}


@app.post("/collect/races")
async def collect_races(
    meet: str = Query(default="1"),
    date: str = Query(default=""),
):
    if not date:
        date = datetime.now().strftime("%Y%m%d")
    races = await kra_client.get_race_plan(meet=meet, rc_date=date)
    stored = 0
    if races and supa.enabled:
        stored = supa.upsert_races(races)
    return {"races_collected": len(races), "races_synced": stored}


@app.post("/collect/ai")
async def collect_ai_data(
    meet: str = Query(default="1"),
    days: int = Query(default=30, ge=1, le=365),
):
    end = datetime.now()
    start = end - timedelta(days=days)
    df = await collector.collect_ai_results(
        meet=meet,
        start_date=start.strftime("%Y%m%d"),
        end_date=end.strftime("%Y%m%d"),
    )
    return {"rows_collected": len(df), "meet": meet, "days": days}


# ── Sync to Supabase ────────────────────────────────────────


@app.post("/sync/seed")
async def sync_seed_to_supabase(
    num_races: int = Query(default=500, ge=10, le=5000),
):
    """시드 데이터를 생성하고 Supabase에 동기화합니다."""
    if not supa.enabled:
        raise HTTPException(status_code=400, detail="Supabase가 설정되지 않았습니다.")

    df = generate_seed_data(num_races=num_races)
    records = df.to_dict("records")

    results_synced = supa.upsert_results(records, "1")
    return {
        "rows_generated": len(df),
        "results_synced": results_synced,
    }


# ── Training ────────────────────────────────────────────────


@app.post("/seed")
async def seed_training_data(
    num_races: int = Query(default=500, ge=10, le=5000),
):
    df = generate_seed_data(num_races=num_races)
    return {"rows_generated": len(df), "num_races": num_races}


@app.post("/train")
async def train_model():
    df = collector.load_all_results()
    if df.empty:
        ai_df = collector.load_all_ai_results()
        if not ai_df.empty:
            df = ai_df
    if df.empty:
        df = collector.load_seed_data()
    if df.empty:
        raise HTTPException(
            status_code=400,
            detail="학습할 데이터가 없습니다. 먼저 /seed 또는 /collect 로 데이터를 생성하세요.",
        )
    metrics = predictor.train(df)

    # 학습 완료 후 시드 데이터 기반 예측을 Supabase에 동기화
    return {"status": "trained", "metrics": metrics}


# ── Recommendations ─────────────────────────────────────────


@app.get("/recommendations")
async def get_recommendations(
    track_condition: str | None = Query(default=None),
    weather: str | None = Query(default=None),
    distance: int | None = Query(default=None),
):
    all_results = predictor._load_cached_results()
    if all_results.empty:
        return []

    filtered = all_results.copy()

    if distance:
        filtered = filtered[filtered["distance"] == distance]

    if filtered.empty:
        return []

    horse_stats = (
        filtered.groupby("horse")
        .agg(
            total=("rank", "count"),
            wins=("is_win", "sum"),
            avg_rank=("rank", "mean"),
        )
        .reset_index()
    )
    horse_stats["win_rate"] = horse_stats["wins"] / horse_stats["total"]
    horse_stats = horse_stats[horse_stats["total"] >= 3]
    top = horse_stats.nlargest(10, "win_rate")

    return top.to_dict("records")


# ── Features ────────────────────────────────────────────────


@app.get("/features/{horse_name}")
async def get_horse_features(horse_name: str, meet: str = Query(default="1")):
    all_results = predictor._load_cached_results()
    if all_results.empty:
        raise HTTPException(status_code=404, detail="데이터가 없습니다.")

    horse_data = all_results[all_results.get("horse", "") == horse_name]
    if horse_data.empty:
        raise HTTPException(
            status_code=404, detail=f"'{horse_name}' 데이터를 찾을 수 없습니다."
        )

    recent = horse_data.tail(5)
    feature_vector = {}
    for col in [
        "distance", "weight", "horse_weight", "s1f", "g3f", "speed",
        "s1f_ratio", "g3f_ratio", "rank_avg5", "jockey_win_rate",
    ]:
        if col in recent.columns:
            feature_vector[col] = round(float(recent[col].mean()), 4)

    return {
        "horse_name": horse_name,
        "total_races": len(horse_data),
        "features": feature_vector,
        "recent_results": recent[
            ["race_date", "rank", "race_time", "distance"]
        ].to_dict("records")
        if all(c in recent.columns for c in ["race_date", "rank", "race_time", "distance"])
        else [],
    }


# ── Health ──────────────────────────────────────────────────


@app.get("/health")
async def health():
    return {
        "status": "ok",
        "model_loaded": predictor.win_model is not None,
        "supabase_connected": supa.enabled,
        "timestamp": datetime.now().isoformat(),
    }
