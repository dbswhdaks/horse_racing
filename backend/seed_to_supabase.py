"""오늘의 경주 계획을 KRA API에서 가져와 Supabase에 시드 데이터와 함께 삽입합니다."""

import json
import random
import httpx
from supabase import create_client
from dotenv import load_dotenv
import os

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_KEY")
KRA_KEY = os.getenv("KRA_SERVICE_KEY")
KRA_BASE = os.getenv("KRA_BASE_URL", "https://apis.data.go.kr/B551015")

supa = create_client(SUPABASE_URL, SUPABASE_KEY)

HORSE_NAMES = [
    "번개질주", "황금바람", "천둥번개", "초원의별", "불꽃질주",
    "바람의아들", "은하수", "폭풍전사", "달빛기사", "용의눈물",
    "비상하라", "왕의귀환", "강철심장", "꿈의날개", "파도소리",
    "별빛공주", "사파이어", "루비하트", "에메랄드", "다이아몬드",
    "금빛태양", "백설공주", "진격의말", "흑마왕", "청풍명월",
    "비단구름", "산들바람", "하늘빛", "무적전사", "영광의길",
    "뇌성벽력", "홍련화", "자유로운", "행운의별", "초음속",
    "명성황후", "검은독수리", "하이킥", "질풍노도", "승리요정",
]

JOCKEY_NAMES = [
    "문세영", "유현명", "김용근", "조성곤", "이찬호",
    "박태종", "김해성", "장석원", "송주호", "안장우",
    "윤성호", "이재현", "김동수", "박찬호", "정성환",
]

TRAINER_NAMES = [
    "김영관", "최석환", "김순기", "박재홍", "정도영",
    "임경록", "강홍석", "이상배", "서진형", "한규성",
]


def fetch_all_races(meet_code: str) -> list[dict]:
    """KRA API에서 오늘 경주 계획 전체를 가져옵니다."""
    url = f"{KRA_BASE}/API72_2/racePlan_2"
    all_items = []
    page = 1
    while True:
        resp = httpx.get(url, params={
            "ServiceKey": KRA_KEY,
            "meet": meet_code,
            "_type": "json",
            "numOfRows": 50,
            "pageNo": page,
        }, timeout=15)
        data = resp.json()
        items = data.get("response", {}).get("body", {}).get("items", {}).get("item", [])
        if not items:
            break
        if isinstance(items, dict):
            items = [items]
        all_items.extend(items)
        total = data.get("response", {}).get("body", {}).get("totalCount", 0)
        if len(all_items) >= total:
            break
        page += 1
    return all_items


def map_race(r: dict) -> dict:
    meet_raw = r.get("meet", "")
    meet_code = {"서울": "1", "제주": "2", "부산경남": "3"}.get(meet_raw, meet_raw)
    return {
        "meet": str(meet_code),
        "race_date": str(r.get("rcDate", "")),
        "race_no": int(r.get("rcNo", 0)),
        "distance": int(r.get("rcDist", 0)),
        "grade_condition": str(r.get("rank", "")),
        "race_name": str(r.get("rcName", "")),
        "age_condition": str(r.get("ageCond", "")),
        "sex_condition": str(r.get("sexCond", "")),
        "weight_condition": str(r.get("budam", "")),
        "start_time": str(r.get("schStTime", "")),
        "prize1": int(r.get("chaksun1", 0)),
        "prize2": int(r.get("chaksun2", 0)),
        "prize3": int(r.get("chaksun3", 0)),
        "head_count": int(r.get("ilsu", 0)),
    }


def generate_entries(meet: str, race_date: str, race_no: int, head_count: int) -> list[dict]:
    count = min(head_count, len(HORSE_NAMES)) if head_count > 0 else random.randint(8, 14)
    horses = random.sample(HORSE_NAMES, count)
    jockeys = random.choices(JOCKEY_NAMES, k=count)
    trainers = random.choices(TRAINER_NAMES, k=count)

    entries = []
    for i in range(count):
        total_races = random.randint(5, 60)
        win_count = random.randint(0, max(1, total_races // 5))
        place_count = random.randint(0, max(1, total_races // 3))
        entries.append({
            "meet": meet,
            "race_date": race_date,
            "race_no": race_no,
            "horse_no": i + 1,
            "horse_name": horses[i],
            "birth_place": random.choice(["한국", "미국", "일본", "호주", "영국", "아일랜드"]),
            "sex": random.choice(["수", "암", "거"]),
            "age": random.randint(3, 8),
            "jockey_name": jockeys[i],
            "trainer_name": trainers[i],
            "owner_name": "",
            "weight": round(random.uniform(52, 59), 1),
            "rating": round(random.uniform(30, 80), 1),
            "total_prize": random.randint(1000, 200000) * 1000,
            "recent_prize": random.randint(0, 50000) * 1000,
            "win_count": win_count,
            "place_count": place_count,
            "total_races": total_races,
            "horse_weight": round(random.uniform(440, 520), 0),
        })
    return entries


def generate_predictions(meet: str, race_date: str, race_no: int, entries: list[dict]) -> list[dict]:
    tags_pool = ["선행마", "추입마", "스퍼트 강화", "감량", "증량", "명기수", "최근호조", "부진중", "비오는날강자", "장거리강자"]

    raw_scores = []
    for e in entries:
        score = (
            e["rating"] * 0.4
            + e["win_count"] / max(e["total_races"], 1) * 100 * 0.3
            + e["recent_prize"] / 100000 * 0.2
            + random.uniform(0, 15)
        )
        raw_scores.append(score)

    total = sum(raw_scores) or 1
    preds = []
    for i, e in enumerate(entries):
        win_prob = round(raw_scores[i] / total * 100, 2)
        place_prob = round(min(win_prob * random.uniform(1.5, 2.5), 95), 2)
        num_tags = random.randint(1, 3)
        tags = random.sample(tags_pool, num_tags)

        preds.append({
            "meet": meet,
            "race_date": race_date,
            "race_no": race_no,
            "horse_no": e["horse_no"],
            "horse_name": e["horse_name"],
            "win_probability": win_prob,
            "place_probability": place_prob,
            "tags": tags,
            "feature_importance": {
                "rating": round(random.uniform(0.1, 0.3), 4),
                "jockey_win_rate": round(random.uniform(0.05, 0.2), 4),
                "s1f": round(random.uniform(0.05, 0.15), 4),
                "g3f": round(random.uniform(0.05, 0.15), 4),
                "weight": round(random.uniform(0.02, 0.1), 4),
            },
            "model_version": "1.0",
        })
    return preds


def main():
    meet_codes = {"1": "1", "2": "2", "3": "3"}
    all_races = []
    all_entries = []
    all_predictions = []

    for code in meet_codes:
        print(f"[{code}] KRA API에서 경주 계획 가져오는 중...")
        raw = fetch_all_races(code)
        print(f"  → {len(raw)}개 경주 발견")

        for r in raw:
            race = map_race(r)
            all_races.append(race)

            entries = generate_entries(
                meet=race["meet"],
                race_date=race["race_date"],
                race_no=race["race_no"],
                head_count=race["head_count"],
            )
            all_entries.extend(entries)

            preds = generate_predictions(
                meet=race["meet"],
                race_date=race["race_date"],
                race_no=race["race_no"],
                entries=entries,
            )
            all_predictions.extend(preds)

    print(f"\n총 {len(all_races)}개 경주, {len(all_entries)}개 출마, {len(all_predictions)}개 예측")

    # Supabase upsert (batch by 500)
    def batch_upsert(table: str, rows: list[dict], conflict: str):
        if not rows:
            return 0
        total = 0
        for i in range(0, len(rows), 500):
            batch = rows[i:i+500]
            res = supa.table(table).upsert(batch, on_conflict=conflict).execute()
            total += len(res.data) if res.data else 0
        return total

    print("\n[Supabase] races 삽입 중...")
    n = batch_upsert("races", all_races, "meet,race_date,race_no")
    print(f"  → {n}개 삽입")

    print("[Supabase] race_entries 삽입 중...")
    n = batch_upsert("race_entries", all_entries, "meet,race_date,race_no,horse_no")
    print(f"  → {n}개 삽입")

    print("[Supabase] predictions 삽입 중...")
    n = batch_upsert("predictions", all_predictions, "meet,race_date,race_no,horse_no,model_version")
    print(f"  → {n}개 삽입")

    print("\n완료!")


if __name__ == "__main__":
    main()
