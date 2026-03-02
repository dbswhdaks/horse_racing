"""경마 예측 정밀도 개선 – 실제 경마 분석 팩터 기반 예측 재생성"""

import math
import random
from supabase import create_client
from dotenv import load_dotenv
import os

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_KEY")
supa = create_client(SUPABASE_URL, SUPABASE_KEY)


def compute_score(entry: dict, race_distance: int, all_entries: list[dict]) -> dict:
    """실제 경마 분석 팩터 기반 점수 산출"""
    rating = entry.get("rating", 0) or 0
    win_count = entry.get("win_count", 0) or 0
    place_count = entry.get("place_count", 0) or 0
    total_races = entry.get("total_races", 1) or 1
    total_prize = entry.get("total_prize", 0) or 0
    recent_prize = entry.get("recent_prize", 0) or 0
    weight = entry.get("weight", 55) or 55
    horse_weight = entry.get("horse_weight", 470) or 470

    # 1) 레이팅 점수 (0~100) – 가장 중요한 지표
    max_rating = max((e.get("rating", 0) or 0) for e in all_entries) or 1
    rating_score = (rating / max_rating) * 100

    # 2) 승률 점수
    win_rate = win_count / total_races if total_races > 0 else 0
    win_rate_score = min(win_rate * 200, 100)

    # 3) 연대율 (1~3착) 점수
    place_rate = (win_count + place_count) / total_races if total_races > 0 else 0
    place_rate_score = min(place_rate * 150, 100)

    # 4) 경험치 점수 (출전 횟수)
    exp_score = min(total_races / 40, 1.0) * 60

    # 5) 상금 점수 – 총 상금과 최근 상금
    max_prize = max((e.get("total_prize", 0) or 0) for e in all_entries) or 1
    max_recent = max((e.get("recent_prize", 0) or 0) for e in all_entries) or 1
    prize_score = (total_prize / max_prize) * 40 + (recent_prize / max_recent) * 60

    # 6) 부담중량 점수 (가벼울수록 유리, 52~59kg 범위)
    weight_score = max(0, (59 - weight) / 7) * 50

    # 7) 마체중 점수 (적정 범위 460~500kg이 최적)
    if 460 <= horse_weight <= 500:
        hw_score = 50
    elif 440 <= horse_weight <= 520:
        hw_score = 30
    else:
        hw_score = 10

    # 8) 최근 폼 (최근 상금 비중이 높으면 상승세)
    form_ratio = recent_prize / total_prize if total_prize > 0 else 0.3
    form_score = min(form_ratio * 200, 80)

    # 가중 합산
    total = (
        rating_score * 0.30    # 레이팅 30%
        + win_rate_score * 0.18  # 승률 18%
        + place_rate_score * 0.12  # 연대율 12%
        + prize_score * 0.15     # 상금 15%
        + form_score * 0.10      # 최근 폼 10%
        + exp_score * 0.05       # 경험 5%
        + weight_score * 0.05    # 부담중량 5%
        + hw_score * 0.05        # 마체중 5%
    )

    # 약간의 변동성 (±3% 이내)
    noise = random.gauss(0, 1.5)
    total = max(0, total + noise)

    # 태그 생성
    tags = []
    if win_rate >= 0.25:
        tags.append("고승률")
    elif win_rate >= 0.15:
        tags.append("안정적")
    if place_rate >= 0.5:
        tags.append("연대율 상위")
    if rating_score >= 80:
        tags.append("최상위 레이팅")
    elif rating_score >= 60:
        tags.append("상위 레이팅")
    if form_ratio >= 0.4:
        tags.append("상승세")
    elif form_ratio <= 0.1 and total_prize > 0:
        tags.append("하락세")
    if weight <= 53:
        tags.append("경량 유리")
    if 470 <= horse_weight <= 495:
        tags.append("적정 마체중")
    if total_races >= 30 and win_rate >= 0.1:
        tags.append("다전다승")
    if total_races <= 8:
        tags.append("신예마")

    # feature importance (실제 기여도 기반)
    importance = {
        "rating": round(0.30 * (rating_score / 100), 4),
        "win_rate": round(0.18 * (win_rate_score / 100), 4),
        "place_rate": round(0.12 * (place_rate_score / 100), 4),
        "prize": round(0.15 * (prize_score / 100), 4),
        "form": round(0.10 * (form_score / 100), 4),
    }

    return {
        "raw_score": total,
        "tags": tags[:3],
        "feature_importance": importance,
    }


def main():
    # 모든 경주 가져오기
    races = supa.table("races").select("meet,race_date,race_no,distance").execute().data
    if not races:
        print("경주 데이터가 없습니다.")
        return

    print(f"총 {len(races)}개 경주 예측 재생성 중...")

    all_predictions = []

    for race in races:
        meet = race["meet"]
        race_date = race["race_date"]
        race_no = race["race_no"]
        distance = race["distance"] or 1400

        entries = (
            supa.table("race_entries")
            .select("*")
            .eq("meet", meet)
            .eq("race_date", race_date)
            .eq("race_no", race_no)
            .order("horse_no")
            .execute()
            .data
        )

        if not entries:
            continue

        # 점수 계산
        scored = []
        for e in entries:
            result = compute_score(e, distance, entries)
            scored.append((e, result))

        # softmax로 확률 변환
        raw_scores = [s["raw_score"] for _, s in scored]
        max_s = max(raw_scores) if raw_scores else 1
        exp_scores = [math.exp((s - max_s) / 15) for s in raw_scores]
        total_exp = sum(exp_scores)

        for i, (entry, result) in enumerate(scored):
            win_prob = round(exp_scores[i] / total_exp * 100, 2)

            # place 확률: top3 에 들 확률 (win_prob 기반으로 누적)
            sorted_probs = sorted(
                [exp_scores[j] / total_exp * 100 for j in range(len(scored))],
                reverse=True,
            )
            rank_in_field = sorted(
                range(len(scored)),
                key=lambda j: exp_scores[j],
                reverse=True,
            ).index(i)

            if rank_in_field < 3:
                place_prob = round(min(win_prob * 2.5, 95), 2)
            elif rank_in_field < 6:
                place_prob = round(win_prob * 1.8, 2)
            else:
                place_prob = round(win_prob * 1.2, 2)

            all_predictions.append({
                "meet": meet,
                "race_date": race_date,
                "race_no": race_no,
                "horse_no": entry["horse_no"],
                "horse_name": entry["horse_name"],
                "win_probability": win_prob,
                "place_probability": place_prob,
                "tags": result["tags"],
                "feature_importance": result["feature_importance"],
                "model_version": "2.0",
            })

    print(f"총 {len(all_predictions)}개 예측 생성 완료")

    # 기존 v1.0 예측 삭제 후 v2.0 삽입
    print("기존 예측 삭제 중...")
    supa.table("predictions").delete().eq("model_version", "1.0").execute()

    print("새 예측 삽입 중...")
    total_synced = 0
    for i in range(0, len(all_predictions), 500):
        batch = all_predictions[i:i+500]
        res = supa.table("predictions").upsert(
            batch, on_conflict="meet,race_date,race_no,horse_no,model_version"
        ).execute()
        total_synced += len(res.data) if res.data else 0

    print(f"Supabase에 {total_synced}개 예측 삽입 완료!")

    # Top 3 샘플 출력
    print("\n─── 서울 2R Top 5 예측 ───")
    sample = [p for p in all_predictions if p["meet"] == "1" and p["race_date"] == "20260302" and p["race_no"] == 2]
    sample.sort(key=lambda x: x["win_probability"], reverse=True)
    for i, p in enumerate(sample[:5]):
        print(f"  {i+1}위: {p['horse_no']}번 {p['horse_name']} "
              f"  승률 {p['win_probability']:.1f}%  연대 {p['place_probability']:.1f}%  "
              f"태그: {', '.join(p['tags'])}")


if __name__ == "__main__":
    main()
