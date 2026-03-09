"""
KRA API → Supabase 동기화 서비스.

경주 일정, 출전표, 경주 결과를 KRA API에서 가져와 Supabase에 저장합니다.
"""

import time
import requests
from datetime import datetime, timedelta

from app.config import KRA_SERVICE_KEY, KRA_BASE_URL, MEET_NAMES
from app.supabase_client import upsert_races, upsert_entries, upsert_results
from app.data_collector import _safe_float, _safe_int, _get_json


def _clean_name(name: str) -> str:
    import re
    return re.sub(r"\([^)]*\)", "", name).strip()


def sync_race_plan(meet: str, date_str: str):
    """API72_2에서 경주 일정을 가져와 Supabase races 테이블에 저장합니다."""
    items = _get_json("/API72_2/racePlan_2", {
        "meet": meet,
        "rc_date": date_str,
    })
    if not items:
        items = _get_json("/API72_2/racePlan_2", {
            "meet": meet,
            "rc_month": date_str[:6],
        })
        items = [i for i in items if str(i.get("rcDate", "")) == date_str]

    if not items:
        print(f"[SYNC] 경주일정 없음: meet={meet}, date={date_str}")
        return 0

    rows = []
    for item in items:
        rows.append({
            "meet": meet,
            "race_date": str(item.get("rcDate", "")),
            "race_no": _safe_int(item.get("rcNo")),
            "distance": _safe_int(item.get("rcDist")),
            "grade_condition": str(item.get("rank", item.get("grdCond", ""))),
            "race_name": str(item.get("rcName", item.get("rcNm", ""))),
            "age_condition": str(item.get("ageCond", "")),
            "sex_condition": str(item.get("sexCond", "")),
            "weight_condition": str(item.get("budam", item.get("wghtCond", ""))),
            "start_time": str(item.get("schStTime", item.get("stTime", ""))),
            "prize1": _safe_int(item.get("chaksun1", item.get("prz1"))),
            "prize2": _safe_int(item.get("chaksun2", item.get("prz2"))),
            "prize3": _safe_int(item.get("chaksun3", item.get("prz3"))),
            "head_count": _safe_int(item.get("dusu", item.get("headCnt", 0))),
        })

    upsert_races(rows)
    print(f"[SYNC] 경주일정 {len(rows)}건 저장 (meet={meet}, date={date_str})")
    return len(rows)


def sync_entries(meet: str, date_str: str):
    """API26_2에서 출전표를 가져와 Supabase race_entries 테이블에 저장합니다."""
    items = _get_json("/API26_2/entrySheet_2", {
        "meet": meet,
        "rc_date": date_str,
        "numOfRows": 500,
    })
    if not items:
        print(f"[SYNC] 출전표 없음: meet={meet}, date={date_str}")
        return 0

    rows = []
    for e in items:
        chul_no = _safe_int(e.get("chulNo"))
        hr_no = _safe_int(e.get("hrNo"))
        horse_no = chul_no if chul_no > 0 else hr_no

        rows.append({
            "meet": meet,
            "race_date": date_str,
            "race_no": _safe_int(e.get("rcNo")),
            "horse_no": horse_no,
            "horse_name": str(e.get("hrName", e.get("hrNm", ""))).strip(),
            "birth_place": str(e.get("prd", e.get("birthPlc", ""))),
            "sex": str(e.get("sex", e.get("sexNm", ""))),
            "age": _safe_int(e.get("age")),
            "jockey_name": _clean_name(
                str(e.get("jkName", e.get("jkNm", "")))
            ),
            "trainer_name": str(e.get("trName", e.get("trNm", ""))).strip(),
            "owner_name": str(e.get("owName", e.get("owNm", ""))).strip(),
            "weight": _safe_float(e.get("wgBudam", e.get("wght"))),
            "rating": _safe_float(e.get("rating")),
            "total_prize": _safe_int(e.get("chaksunT", e.get("totalPrz"))),
            "recent_prize": _safe_int(e.get("chaksunY", e.get("recentPrz"))),
            "win_count": _safe_int(e.get("ord1CntT", e.get("ord1Cnt"))),
            "place_count": _safe_int(e.get("ord2CntT", e.get("ord2Cnt"))),
            "total_races": _safe_int(e.get("rcCntT", e.get("totalCnt"))),
            "horse_weight": _safe_float(e.get("hrWght", 0)),
        })

    upsert_entries(rows)
    print(f"[SYNC] 출전표 {len(rows)}건 저장 (meet={meet}, date={date_str})")
    return len(rows)


def sync_results(meet: str, date_str: str):
    """API155에서 경주 결과를 가져와 Supabase race_results 테이블에 저장합니다."""
    items = _get_json("/API155/raceResult", {
        "rccrs_cd": meet,
        "race_dt": date_str,
        "numOfRows": 500,
    })
    if not items:
        print(f"[SYNC] 경주결과 없음: meet={meet}, date={date_str}")
        return 0

    rows = []
    for r in items:
        race_no = _safe_int(r.get("raceNo") or r.get("rcNo") or r.get("race_no"))
        horse_no = _safe_int(r.get("gtno") or r.get("chulNo") or r.get("hrNo"))

        race_time_raw = r.get("raceRcd", r.get("rcTime", ""))
        if isinstance(race_time_raw, (int, float)):
            sec = int(race_time_raw)
            frac = str(race_time_raw).split(".")[-1] if "." in str(race_time_raw) else "0"
            m, s = divmod(sec, 60)
            race_time = f"{m}:{str(s).zfill(2)}.{frac}" if m > 0 else f"{s}.{frac}"
        else:
            race_time = str(race_time_raw).strip()

        horse_weight_raw = r.get("rchrWeg", r.get("hrWght", 0))
        if isinstance(horse_weight_raw, str):
            horse_weight_raw = horse_weight_raw.split("(")[0].strip()
        horse_weight = _safe_float(horse_weight_raw)

        rows.append({
            "meet": meet,
            "race_date": str(r.get("raceDt", r.get("rcDate", ""))),
            "race_no": race_no,
            "rank": _safe_int(r.get("rk") or r.get("ord")),
            "horse_no": horse_no,
            "horse_name": str(r.get("hrnm", r.get("hrName", ""))).strip(),
            "jockey_name": _clean_name(
                str(r.get("jckyNm", r.get("jkName", "")))
            ),
            "trainer_name": str(r.get("trarNm", r.get("trName", ""))).strip(),
            "race_time": race_time,
            "weight": _safe_float(r.get("burdWgt", r.get("wgBudam"))),
            "horse_weight": horse_weight,
            "rank_diff": str(r.get("margin", r.get("ordDiff", ""))),
            "win_odds": _safe_float(r.get("winPrice", r.get("winOdds"))),
            "place_odds": _safe_float(r.get("placePrice", r.get("plcOdds"))),
            "s1f": str(r.get("s1f", "")),
            "g3f": str(r.get("g3f", "")),
            "pass_order": str(r.get("ordBigo", r.get("passOrdTxt", ""))),
            "distance": _safe_int(r.get("raceDs", r.get("rcDist"))),
        })

    upsert_results(rows)
    print(f"[SYNC] 경주결과 {len(rows)}건 저장 (meet={meet}, date={date_str})")
    return len(rows)


def sync_all(meet: str, date_str: str, delay: float = 0.3):
    """경주일정 + 출전표 + 결과를 한번에 동기화합니다."""
    print(f"\n{'='*50}")
    print(f"[SYNC] {MEET_NAMES.get(meet, meet)} {date_str} 전체 동기화 시작")
    print(f"{'='*50}")

    n_races = sync_race_plan(meet, date_str)
    time.sleep(delay)

    n_entries = sync_entries(meet, date_str)
    time.sleep(delay)

    n_results = sync_results(meet, date_str)

    print(f"[SYNC] 완료: 일정 {n_races}건, 출전표 {n_entries}건, 결과 {n_results}건")
    return {"races": n_races, "entries": n_entries, "results": n_results}


def sync_date_range(
    meet: str,
    start_date: str,
    end_date: str,
    delay: float = 0.5,
):
    """지정 기간의 모든 데이터를 동기화합니다."""
    current = datetime.strptime(start_date, "%Y%m%d")
    end = datetime.strptime(end_date, "%Y%m%d")
    total = {"races": 0, "entries": 0, "results": 0}

    while current <= end:
        date_str = current.strftime("%Y%m%d")
        result = sync_all(meet, date_str, delay=0.3)
        for k in total:
            total[k] += result[k]
        time.sleep(delay)
        current += timedelta(days=1)

    print(f"\n[SYNC] 전체 기간 완료: {total}")
    return total


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="KRA → Supabase 데이터 동기화")
    parser.add_argument("--meet", default="1", help="경마장 코드")
    parser.add_argument("--date", default=None, help="특정 일자 (YYYYMMDD)")
    parser.add_argument("--start", default=None, help="시작일 (YYYYMMDD)")
    parser.add_argument("--end", default=None, help="종료일 (YYYYMMDD)")
    args = parser.parse_args()

    if args.date:
        sync_all(args.meet, args.date)
    elif args.start and args.end:
        sync_date_range(args.meet, args.start, args.end)
    else:
        today = datetime.now().strftime("%Y%m%d")
        sync_all(args.meet, today)
