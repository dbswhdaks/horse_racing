"""race_results 테이블에서 race_no=0인 레코드를 출마표(race_entries) 기반으로 수정합니다."""

from supabase import create_client
from dotenv import load_dotenv
import os

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_KEY")

supa = create_client(SUPABASE_URL, SUPABASE_KEY)


def main():
    broken = (
        supa.table("race_results")
        .select("id,meet,race_date,horse_name,horse_no")
        .eq("race_no", 0)
        .execute()
        .data
    )
    if not broken:
        print("race_no=0인 레코드가 없습니다.")
        return

    print(f"race_no=0 레코드: {len(broken)}건")

    dates = {(r["meet"], r["race_date"]) for r in broken}

    entry_map: dict[tuple[str, str, str], int] = {}
    for meet, race_date in dates:
        entries = (
            supa.table("race_entries")
            .select("race_no,horse_name")
            .eq("meet", meet)
            .eq("race_date", race_date)
            .execute()
            .data
        )
        for e in entries:
            key = (meet, race_date, e["horse_name"])
            entry_map[key] = e["race_no"]

    fixed = 0
    not_found = 0
    for r in broken:
        key = (r["meet"], r["race_date"], r["horse_name"])
        race_no = entry_map.get(key)
        if race_no and race_no > 0:
            supa.table("race_results").update(
                {"race_no": race_no}
            ).eq("id", r["id"]).execute()
            fixed += 1
        else:
            print(f"  매칭 실패: {r['horse_name']} (meet={r['meet']}, date={r['race_date']})")
            not_found += 1

    print(f"\n완료: {fixed}건 수정, {not_found}건 매칭 실패")


if __name__ == "__main__":
    main()
