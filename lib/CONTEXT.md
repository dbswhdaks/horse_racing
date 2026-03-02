# 경마 예측 앱 (Horse Racing Prediction)

## 프로젝트 구조

```
lib/
├── main.dart                  # 앱 진입점 (ProviderScope + MaterialApp.router)
├── router/
│   └── app_router.dart        # GoRouter 라우팅 설정
├── core/
│   ├── constants/
│   │   └── api_constants.dart  # API 키, 엔드포인트, 경마장 코드
│   ├── theme/
│   │   └── app_theme.dart      # 다크/라이트 테마 (Green + Gold)
│   ├── network/
│   │   └── dio_client.dart     # Dio HTTP 클라이언트 (KRA, ML 서버)
│   ├── services/
│   │   ├── kra_api_service.dart  # 한국마사회 공공데이터 API 서비스
│   │   └── ml_api_service.dart   # Python ML 백엔드 API 서비스
│   └── widgets/
│       └── shimmer_loading.dart  # 로딩 Shimmer 위젯
├── models/
│   ├── race.dart              # 경주 계획 모델
│   ├── race_entry.dart        # 출마표 (마번, 마명, 기수, 부담중량 등)
│   ├── race_result.dart       # 경주 결과 (순위, 기록, S1F, G3F)
│   ├── odds.dart              # 배당률 (단승, 복승, 삼쌍승)
│   └── prediction.dart        # AI 예측 결과 모델
├── features/
│   ├── home/
│   │   ├── screens/home_screen.dart  # 홈: 경마장별 탭, 경주 목록
│   │   └── widgets/race_card.dart    # 경주 카드 위젯
│   ├── race/
│   │   ├── screens/
│   │   │   ├── race_detail_screen.dart  # 출마표 + 배당률 + AI 예측
│   │   │   └── race_result_screen.dart  # 경주 결과 순위
│   │   ├── widgets/
│   │   │   ├── entry_card.dart         # 출마 마필 카드
│   │   │   ├── odds_panel.dart         # 배당률 패널
│   │   │   └── prediction_summary.dart # AI 예측 요약
│   │   └── providers/
│   │       └── race_providers.dart     # Riverpod 프로바이더
│   ├── horse/
│   │   └── screens/horse_detail_screen.dart  # 마필 전적, 차트
│   └── prediction/
│       └── screens/prediction_screen.dart    # AI 예측 상세 리포트

backend/
├── main.py              # FastAPI 서버 (예측, 데이터수집, 학습 API)
├── config.py            # 환경변수 설정
├── requirements.txt     # Python 의존성
├── services/
│   ├── kra_client.py    # 한국마사회 API 클라이언트
│   ├── data_collector.py # 과거 데이터 수집/CSV 저장
│   └── predictor.py     # ML 예측 서비스 (XGBoost + RandomForest)
├── features/
│   └── engineering.py   # 특성 엔지니어링 (19개 피처)
├── models/              # 학습된 모델 저장 (.joblib)
└── data/                # 수집된 데이터 캐시 (.csv)
```

## 기술 스택
- **Flutter**: Riverpod, GoRouter, Dio, fl_chart, Google Fonts
- **Backend**: Python FastAPI, XGBoost, scikit-learn, pandas
- **API**: 한국마사회 공공데이터 (data.go.kr)

## 화면 라우팅
- `/` → 홈 (오늘의 경주)
- `/race/:meet/:date/:raceNo` → 경주 상세 (출마표)
- `/result/:meet/:date/:raceNo` → 경주 결과
- `/horse/:horseName?meet=` → 마필 상세
- `/prediction/:meet/:date/:raceNo` → AI 예측 리포트

## ML 특성 (19개)
distance, weight, horse_weight, s1f, g3f, speed, s1f_ratio, g3f_ratio,
weight_change, rank_avg5, race_time_avg5, speed_avg5, s1f_avg5, g3f_avg5,
jockey_win_rate, jockey_place_rate, jockey_dist_win_rate, dist_cat_code,
meet_encoded

## 백엔드 사용법
```bash
cd backend
pip install -r requirements.txt
# 1) 데이터 수집
curl -X POST "http://localhost:8000/collect?meet=1&days=90"
# 2) 모델 학습
curl -X POST "http://localhost:8000/train"
# 3) 예측
curl "http://localhost:8000/predict/1/20260302/1"
# 서버 시작
uvicorn main:app --reload --port 8000
```
