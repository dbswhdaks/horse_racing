"""
경마 AI 예측 FastAPI 서버.

엔드포인트:
  GET  /                          → 서버 상태
  GET  /predict/{meet}/{date}/{race_no} → 특정 경주 예측
  POST /collect                   → 데이터 수집 트리거
  POST /train                     → 모델 재학습 트리거
  GET  /model/info                → 현재 모델 정보
  GET  /health                    → 헬스 체크
"""

import os
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from datetime import datetime, timedelta

from app.predictor import HorseRacingPredictor
from app.data_collector import collect_date_range, save_data
from app.trainer import train_model
from app.sync_service import sync_all, sync_date_range

predictor: HorseRacingPredictor | None = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global predictor
    predictor = HorseRacingPredictor()
    print(f"[SERVER] 예측 모델 로드 완료 (version: {predictor.model_version})")
    yield
    print("[SERVER] 서버 종료")


app = FastAPI(
    title="경마 AI 예측 서버",
    description="KRA 데이터 기반 멀티모델(XGBoost/LightGBM/CatBoost) + LTR 경마 예측 API",
    version="2.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
async def root():
    return {
        "service": "경마 AI 예측 서버",
        "model_ready": predictor.is_ready if predictor else False,
        "model_version": predictor.model_version if predictor else "not loaded",
    }


@app.get("/health")
async def health():
    return {"status": "ok", "timestamp": datetime.now().isoformat()}


@app.get("/predict/{meet}/{date}/{race_no}")
async def predict(meet: str, date: str, race_no: int):
    """
    특정 경주의 AI 예측을 반환합니다.

    - meet: 경마장 코드 (1=서울, 2=제주, 3=부산경남)
    - date: 경주일 (YYYYMMDD)
    - race_no: 경주 번호
    """
    if predictor is None:
        raise HTTPException(status_code=503, detail="모델이 로드되지 않았습니다")

    try:
        result = predictor.predict(meet=meet, date=date, race_no=race_no)
        if not result["predictions"]:
            raise HTTPException(
                status_code=404,
                detail=f"경주 데이터를 찾을 수 없습니다: {meet}/{date}/{race_no}",
            )
        return result
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/model/info")
async def model_info():
    """현재 로드된 모델의 메타정보를 반환합니다."""
    if predictor is None:
        raise HTTPException(status_code=503, detail="모델이 로드되지 않았습니다")
    return {
        "is_ready": predictor.is_ready,
        "version": predictor.model_version,
        "meta": predictor.meta,
    }


def _run_collection(meet: str, start: str, end: str):
    df = collect_date_range(meet, start, end)
    if not df.empty:
        save_data(df)


@app.post("/collect")
async def collect_data(
    background_tasks: BackgroundTasks,
    meet: str = "1",
    days: int = 90,
):
    """
    KRA API에서 과거 데이터를 수집합니다.
    백그라운드에서 실행됩니다.
    """
    end = datetime.now()
    start = end - timedelta(days=days)

    background_tasks.add_task(
        _run_collection,
        meet,
        start.strftime("%Y%m%d"),
        end.strftime("%Y%m%d"),
    )

    return {
        "status": "수집 시작",
        "meet": meet,
        "range": f"{start.strftime('%Y%m%d')} ~ {end.strftime('%Y%m%d')}",
    }


def _run_training():
    global predictor
    train_model()
    predictor = HorseRacingPredictor()


@app.post("/train")
async def train(background_tasks: BackgroundTasks):
    """
    수집된 데이터로 모델을 재학습합니다.
    백그라운드에서 실행됩니다.
    """
    from app.config import DATA_DIR
    data_path = os.path.join(DATA_DIR, "race_data.csv")
    if not os.path.exists(data_path):
        raise HTTPException(
            status_code=400,
            detail="학습 데이터가 없습니다. 먼저 /collect 를 실행하세요.",
        )

    background_tasks.add_task(_run_training)
    return {"status": "학습 시작됨"}


def _run_sync(meet: str, date: str):
    sync_all(meet, date)


def _run_sync_range(meet: str, start: str, end: str):
    sync_date_range(meet, start, end)


@app.post("/sync")
async def sync_data(
    background_tasks: BackgroundTasks,
    meet: str = "1",
    date: str | None = None,
):
    """
    KRA API → Supabase 데이터 동기화.
    date 미지정 시 오늘 데이터를 동기화합니다.
    """
    if date is None:
        date = datetime.now().strftime("%Y%m%d")

    background_tasks.add_task(_run_sync, meet, date)
    return {"status": "동기화 시작", "meet": meet, "date": date}


@app.post("/sync/range")
async def sync_range(
    background_tasks: BackgroundTasks,
    meet: str = "1",
    start: str = "",
    end: str = "",
):
    """지정 기간의 KRA 데이터를 Supabase에 동기화합니다."""
    if not start or not end:
        raise HTTPException(status_code=400, detail="start, end 파라미터가 필요합니다")

    background_tasks.add_task(_run_sync_range, meet, start, end)
    return {"status": "기간 동기화 시작", "meet": meet, "range": f"{start} ~ {end}"}


if __name__ == "__main__":
    import uvicorn

    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "8000"))
    uvicorn.run("app.main:app", host=host, port=port, reload=True)
