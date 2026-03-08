# 경마 AI 예측 ML 백엔드

KRA 공공데이터 API 기반 XGBoost 경마 예측 서버입니다.

## 구조

```
ml_backend/
├── app/
│   ├── main.py              # FastAPI 서버 (엔드포인트 정의)
│   ├── config.py             # 환경변수 및 경로 설정
│   ├── data_collector.py     # KRA API 데이터 수집
│   ├── feature_engineering.py # 피처 엔지니어링
│   ├── trainer.py            # XGBoost 모델 학습
│   └── predictor.py          # 실시간 예측
├── models/                   # 학습된 모델 저장 폴더
├── data/                     # 수집된 CSV 데이터 폴더
├── requirements.txt
├── Dockerfile
└── README.md
```

## 빠른 시작

### 1. 환경 설정

```bash
cd ml_backend
pip install -r requirements.txt
```

### 2. 데이터 수집

```bash
# 최근 90일 서울 경마 데이터 수집
python -m app.data_collector --meet 1 --start 20251201 --end 20260308
```

### 3. 모델 학습

```bash
python -m app.trainer
```

### 4. 서버 실행

```bash
python -m app.main
# 또는
uvicorn app.main:app --reload --port 8000
```

### 5. API 테스트

```bash
# 서버 상태 확인
curl http://localhost:8000/

# 예측 요청 (서울, 2026-03-08, 1경주)
curl http://localhost:8000/predict/1/20260308/1

# 모델 정보
curl http://localhost:8000/model/info
```

## API 엔드포인트

| 메서드 | 경로 | 설명 |
|--------|------|------|
| GET | `/` | 서버 상태 |
| GET | `/health` | 헬스 체크 |
| GET | `/predict/{meet}/{date}/{race_no}` | 경주 예측 |
| GET | `/model/info` | 모델 메타정보 |
| POST | `/collect?meet=1&days=90` | 데이터 수집 (백그라운드) |
| POST | `/train` | 모델 재학습 (백그라운드) |

## API 사용 흐름 (웹 UI)

```bash
# 1단계: 데이터 수집 시작
curl -X POST "http://localhost:8000/collect?meet=1&days=90"

# 2단계: 수집 완료 후 학습 시작
curl -X POST "http://localhost:8000/train"

# 3단계: 예측 요청
curl http://localhost:8000/predict/1/20260308/1
```

## 모델이 없을 때

학습된 모델이 없어도 서버는 정상 동작합니다.
통계 기반 휴리스틱 예측(승률, 레이팅, 상금 등)을 대신 사용합니다.

## Docker 배포

```bash
docker build -t horse-racing-ml .
docker run -p 8000:8000 horse-racing-ml
```

## 무료 배포 옵션

- **Render.com**: `render.yaml`로 자동 배포
- **Railway**: GitHub 연결 후 자동 배포
- **Google Cloud Run**: Dockerfile 기반 배포

## 피처 목록

| 피처 | 설명 |
|------|------|
| race_distance | 경주 거리 (m) |
| burden_weight | 부담중량 (kg) |
| horse_weight | 마체중 (kg) |
| rating | KRA 레이팅 |
| age | 나이 |
| sex_encoded | 성별 (수=0, 암=1, 거=2) |
| birth_place_encoded | 출생지 인코딩 |
| total_races | 총 출전 횟수 |
| win_count | 1착 횟수 |
| place_count | 2착 횟수 |
| win_rate | 승률 |
| place_rate | 입상률 |
| total_prize_log | 총 상금 (log) |
| recent_prize_log | 최근 1년 상금 (log) |
| field_size | 출전 두수 |
| win_odds | 단승 배당률 |
| horse_weight_diff | 평균 대비 마체중 차이 |
| weight_per_distance | 거리당 부담중량 비율 |
| experience_score | 경험 점수 (출전수 × 승률) |
| form_score | 최근 컨디션 (최근상금/총상금) |
