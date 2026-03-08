"""
KRA API에서 과거 경주 결과 데이터를 수집하여 학습용 CSV로 저장합니다.

사용 API:
  - API155 (AI학습용 경주결과): 과거 경주 결과 + 배당 + 기록
  - API26_2 (출전표 상세정보): 출전마 레이팅, 성적, 부담중량 등
"""

import os
import time
import requests
import pandas as pd
from datetime import datetime, timedelta
from app.config import KRA_SERVICE_KEY, KRA_BASE_URL, DATA_DIR


def _get_json(path: str, params: dict) -> list[dict]:
    params["ServiceKey"] = KRA_SERVICE_KEY
    params["_type"] = "json"
    params.setdefault("numOfRows", 500)
    params.setdefault("pageNo", 1)

    url = f"{KRA_BASE_URL}{path}"
    try:
        resp = requests.get(url, params=params, timeout=20)
        resp.raise_for_status()
        data = resp.json()
    except Exception as e:
        print(f"[ERROR] {path} → {e}")
        return []

    body = data.get("response", {}).get("body", {})
    items = body.get("items", {}).get("item", [])
    if isinstance(items, dict):
        items = [items]
    return items if isinstance(items, list) else []


def fetch_race_results(meet: str, date_str: str) -> list[dict]:
    """API155에서 해당 일자의 경주 결과를 가져옵니다."""
    items = _get_json("/API155/raceResult", {
        "rccrs_cd": meet,
        "race_dt": date_str,
        "numOfRows": 500,
    })
    return items


def fetch_entry_list(meet: str, date_str: str) -> list[dict]:
    """API26_2에서 해당 일자의 전체 출전표를 가져옵니다."""
    items = _get_json("/API26_2/entrySheet_2", {
        "meet": meet,
        "rc_date": date_str,
        "numOfRows": 500,
    })
    return items


def _safe_float(v) -> float:
    if v is None:
        return 0.0
    try:
        return float(v)
    except (ValueError, TypeError):
        return 0.0


def _safe_int(v) -> int:
    if v is None:
        return 0
    try:
        return int(v)
    except (ValueError, TypeError):
        return 0


def _parse_horse_weight(v) -> float:
    if v is None:
        return 0.0
    s = str(v).split("(")[0].strip()
    return _safe_float(s)


def build_training_row(result: dict, entry: dict | None) -> dict:
    """경주결과 + 출전표 데이터를 합쳐 학습용 1행을 만듭니다."""
    race_no = _safe_int(result.get("rcNo") or result.get("race_no"))
    horse_no = _safe_int(result.get("gtno") or result.get("chulNo"))

    row = {
        "meet": str(result.get("meet", result.get("rccrsNm", ""))),
        "race_date": str(result.get("raceDt", result.get("rcDate", ""))),
        "race_no": race_no,
        "horse_no": horse_no,
        "horse_name": str(result.get("hrnm", result.get("hrName", ""))).strip(),
        "rank": _safe_int(result.get("rk") or result.get("ord")),
        "race_distance": _safe_int(result.get("raceDs") or result.get("rcDist")),
        "burden_weight": _safe_float(result.get("burdWgt") or result.get("wgBudam")),
        "horse_weight": _parse_horse_weight(result.get("rchrWeg") or result.get("hrWght")),
        "win_odds": _safe_float(result.get("winPrice") or result.get("winOdds")),
        "place_odds": _safe_float(result.get("placePrice") or result.get("plcOdds")),
        "race_time": _safe_float(result.get("raceRcd") or result.get("rcTime")),
        "s1f": _safe_float(result.get("s1f", 0)),
        "g3f": _safe_float(result.get("g3f", 0)),
    }

    if entry:
        row.update({
            "rating": _safe_float(entry.get("rating", 0)),
            "age": _safe_int(entry.get("age", 0)),
            "sex": str(entry.get("sex", "")),
            "jockey_name": str(entry.get("jkName", entry.get("jkNm", ""))).strip(),
            "trainer_name": str(entry.get("trName", entry.get("trNm", ""))).strip(),
            "total_races": _safe_int(entry.get("rcCntT") or entry.get("totalCnt")),
            "win_count": _safe_int(entry.get("ord1CntT") or entry.get("ord1Cnt")),
            "place_count": _safe_int(entry.get("ord2CntT") or entry.get("ord2Cnt")),
            "total_prize": _safe_int(entry.get("chaksunT") or entry.get("totalPrz")),
            "recent_prize": _safe_int(entry.get("chaksunY") or entry.get("recentPrz")),
            "birth_place": str(entry.get("prd", entry.get("birthPlc", ""))),
        })
    else:
        row.update({
            "rating": 0.0,
            "age": 0,
            "sex": "",
            "jockey_name": "",
            "trainer_name": "",
            "total_races": 0,
            "win_count": 0,
            "place_count": 0,
            "total_prize": 0,
            "recent_prize": 0,
            "birth_place": "",
        })

    return row


def collect_date_range(
    meet: str,
    start_date: str,
    end_date: str,
    delay: float = 0.5,
) -> pd.DataFrame:
    """
    지정 기간의 경주 데이터를 수집합니다.

    Args:
        meet: 경마장 코드 ("1"=서울, "2"=제주, "3"=부산경남)
        start_date: 시작일 (YYYYMMDD)
        end_date: 종료일 (YYYYMMDD)
        delay: API 호출 간 대기 시간(초)
    """
    rows: list[dict] = []
    current = datetime.strptime(start_date, "%Y%m%d")
    end = datetime.strptime(end_date, "%Y%m%d")

    while current <= end:
        date_str = current.strftime("%Y%m%d")
        print(f"[{meet}] {date_str} 수집 중...")

        results = fetch_race_results(meet, date_str)
        if not results:
            current += timedelta(days=1)
            continue

        entries = fetch_entry_list(meet, date_str)
        entry_map: dict[tuple[int, int], dict] = {}
        for e in entries:
            rc_no = _safe_int(e.get("rcNo"))
            chul_no = _safe_int(e.get("chulNo"))
            if rc_no > 0 and chul_no > 0:
                entry_map[(rc_no, chul_no)] = e

        for r in results:
            rc_no = _safe_int(r.get("rcNo") or r.get("race_no"))
            h_no = _safe_int(r.get("gtno") or r.get("chulNo"))
            entry = entry_map.get((rc_no, h_no))
            rows.append(build_training_row(r, entry))

        time.sleep(delay)
        current += timedelta(days=1)

    df = pd.DataFrame(rows)
    print(f"총 {len(df)}행 수집 완료")
    return df


def save_data(df: pd.DataFrame, filename: str = "race_data.csv"):
    path = os.path.join(DATA_DIR, filename)
    if os.path.exists(path):
        existing = pd.read_csv(path)
        df = pd.concat([existing, df], ignore_index=True)
        df = df.drop_duplicates(
            subset=["meet", "race_date", "race_no", "horse_no"],
            keep="last",
        )
    df.to_csv(path, index=False, encoding="utf-8-sig")
    print(f"저장 완료: {path} ({len(df)}행)")
    return path


def load_historical_data(filename: str = "race_data.csv") -> pd.DataFrame:
    """저장된 과거 경주 데이터를 로드합니다."""
    path = os.path.join(DATA_DIR, filename)
    if not os.path.exists(path):
        return pd.DataFrame()
    df = pd.read_csv(path)
    df = df.sort_values(["race_date", "race_no", "horse_no"]).reset_index(drop=True)
    return df


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="KRA 경주 데이터 수집")
    parser.add_argument("--meet", default="1", help="경마장 코드 (1=서울, 2=제주, 3=부산경남)")
    parser.add_argument("--start", required=True, help="시작일 (YYYYMMDD)")
    parser.add_argument("--end", required=True, help="종료일 (YYYYMMDD)")
    parser.add_argument("--delay", type=float, default=0.5, help="API 호출 간격(초)")
    args = parser.parse_args()

    df = collect_date_range(args.meet, args.start, args.end, args.delay)
    if not df.empty:
        save_data(df)
