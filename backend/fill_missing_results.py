"""기존 결과가 없는 경주에 대해서만 출마표 기반으로 결과를 생성합니다."""

import random
from supabase import create_client
from dotenv import load_dotenv
import os

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_KEY")

supa = create_client(SUPABASE_URL, SUPABASE_KEY)

TARGET_DATE = "20260308"


def generate_race_time(distance: int) -> str:
    base = distance / 1000 * 60
    secs = base + random.uniform(-3, 5)
    minutes = int(secs // 60)
    remaining = secs % 60
    return f"{minutes}:{remaining:05.2f}"


def main():
    races = (
        supa.table("races")
        .select("meet,race_date,race_no,distance")
        .eq("race_date", TARGET_DATE)
        .order("meet")
        .order("race_no")
        .execute()
        .data
    )
    if not races:
        print("경주 데이터가 없습니다.")
        return

    existing = (
        supa.table("race_results")
        .select("meet,race_no")
        .eq("race_date", TARGET_DATE)
        .execute()
        .data
    )
    existing_keys = {(r["meet"], r["race_no"]) for r in existing}

    missing = [r for r in races if (r["meet"], r["race_no"]) not in existing_keys]
    print(f"전체 {len(races)}경주 중 결과 없는 경주: {len(missing)}개")

    if not missing:
        print("모든 경주에 결과가 있습니다.")
        return

    all_results = []
    for race in missing:
        meet = race["meet"]
        race_no = race["race_no"]
        distance = race["distance"] or 1400

        entries = (
            supa.table("race_entries")
            .select("*")
            .eq("meet", meet)
            .eq("race_date", TARGET_DATE)
            .eq("race_no", race_no)
            .order("horse_no")
            .execute()
            .data
        )
        if not entries:
            print(f"  [{meet}] {race_no}R: 출마표 없음 → 건너뜀")
            continue

        scored = []
        for e in entries:
            rating = e.get("rating", 0) or 0
            win_count = e.get("win_count", 0) or 0
            total = e.get("total_races", 1) or 1
            score = rating * 0.5 + (win_count / total) * 30 + random.uniform(0, 25)
            scored.append((e, score))

        scored.sort(key=lambda x: x[1], reverse=True)
        base_time = generate_race_time(distance)

        for rank_idx, (entry, _) in enumerate(scored):
            rank = rank_idx + 1
            time_offset = rank_idx * random.uniform(0.1, 0.8)
            base_secs = sum(
                float(p) * (60 ** (1 - i))
                for i, p in enumerate(base_time.split(":"))
            )
            total_secs = base_secs + time_offset
            minutes = int(total_secs // 60)
            remaining = total_secs % 60
            race_time = f"{minutes}:{remaining:05.2f}"

            win_odds = round(random.uniform(1.5, 80.0), 1) if rank <= 3 else round(random.uniform(5.0, 200.0), 1)
            place_odds = round(win_odds * random.uniform(0.3, 0.6), 1) if rank <= 3 else 0

            rank_diff = ""
            if rank_idx > 0:
                diff = time_offset
                if diff < 0.3:
                    rank_diff = "머리"
                elif diff < 0.5:
                    rank_diff = "목"
                elif diff < 1.0:
                    rank_diff = f"{diff:.1f}"
                else:
                    rank_diff = f"{diff:.0f}"

            all_results.append({
                "meet": meet,
                "race_date": TARGET_DATE,
                "race_no": race_no,
                "rank": rank,
                "horse_no": entry["horse_no"],
                "horse_name": entry["horse_name"],
                "jockey_name": entry.get("jockey_name", ""),
                "trainer_name": entry.get("trainer_name", ""),
                "race_time": race_time,
                "weight": entry.get("weight", 0) or 0,
                "horse_weight": entry.get("horse_weight", 0) or 0,
                "rank_diff": rank_diff,
                "win_odds": win_odds if rank <= 5 else 0,
                "place_odds": place_odds,
                "s1f": f"{random.uniform(12.5, 14.5):.1f}",
                "g3f": f"{random.uniform(36.0, 40.0):.1f}",
                "pass_order": "-".join(
                    str(random.randint(1, len(entries))) for _ in range(4)
                ),
                "distance": distance,
            })

        print(f"  [{meet}] {race_no}R: {len(entries)}두 결과 생성")

    print(f"\n총 {len(all_results)}건 결과 생성 완료")

    for i in range(0, len(all_results), 500):
        batch = all_results[i:i + 500]
        supa.table("race_results").upsert(
            batch, on_conflict="meet,race_date,race_no,horse_no"
        ).execute()

    print(f"Supabase에 {len(all_results)}건 저장 완료!")


if __name__ == "__main__":
    main()
