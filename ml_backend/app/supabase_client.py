"""
Supabase 클라이언트 모듈.

수집 데이터, 예측 결과를 Supabase에 저장/조회합니다.
"""

import time

import httpx
from supabase import create_client, Client
from app.config import SUPABASE_ANON_KEY, SUPABASE_SERVICE_KEY, SUPABASE_URL

_client: Client | None = None


def get_client() -> Client:
    global _client
    if _client is None:
        key = SUPABASE_SERVICE_KEY or SUPABASE_ANON_KEY
        if not SUPABASE_URL or not key:
            raise RuntimeError("SUPABASE_URL과 Supabase API key가 필요합니다.")
        _client = create_client(SUPABASE_URL, key)
    return _client


def _execute_with_retry(build_query, attempts: int = 3, delay: float = 2.0):
    """전송 오류로 예약 실행이 통째로 실패하지 않도록 재시도합니다.

    스키마나 데이터가 잘못된 경우(APIError)는 다시 시도해도 결과가 같으므로
    httpx 전송 오류만 재시도 대상으로 둡니다.
    """
    for attempt in range(1, attempts + 1):
        try:
            return build_query().execute()
        except httpx.HTTPError as e:
            if attempt == attempts:
                raise
            wait = delay * attempt
            print(f"[SUPABASE] 전송 오류, {wait:.0f}초 후 재시도 ({attempt}/{attempts - 1}): {e}")
            time.sleep(wait)


# ───────────────────── Races ─────────────────────

def upsert_races(rows: list[dict]):
    if not rows:
        return
    client = get_client()
    _execute_with_retry(
        lambda: client.table("races").upsert(rows, on_conflict="meet,race_date,race_no")
    )
    print(f"[SUPABASE] races {len(rows)}건 upsert")


# ───────────────────── Race Entries ─────────────────────

def upsert_entries(rows: list[dict]):
    if not rows:
        return
    client = get_client()
    _execute_with_retry(
        lambda: client.table("race_entries").upsert(
            rows, on_conflict="meet,race_date,race_no,horse_no"
        )
    )
    print(f"[SUPABASE] race_entries {len(rows)}건 upsert")


# ───────────────────── Race Results ─────────────────────

def upsert_results(rows: list[dict]):
    if not rows:
        return
    seen = set()
    unique_rows = []
    for r in rows:
        key = (r["meet"], r["race_date"], r["race_no"], r["horse_no"])
        if key not in seen:
            seen.add(key)
            unique_rows.append(r)
    client = get_client()
    _execute_with_retry(
        lambda: client.table("race_results").upsert(
            unique_rows, on_conflict="meet,race_date,race_no,horse_no"
        )
    )
    print(f"[SUPABASE] race_results {len(unique_rows)}건 upsert")


# ───────────────────── Predictions ─────────────────────

def upsert_predictions(rows: list[dict]):
    if not rows:
        return
    client = get_client()
    _execute_with_retry(
        lambda: client.table("predictions").upsert(
            rows, on_conflict="meet,race_date,race_no,horse_no,model_version"
        )
    )
    print(f"[SUPABASE] predictions {len(rows)}건 upsert")


# ───────────────────── Odds ─────────────────────

def upsert_odds(rows: list[dict]):
    if not rows:
        return
    client = get_client()
    _execute_with_retry(lambda: client.table("odds").upsert(rows))
    print(f"[SUPABASE] odds {len(rows)}건 upsert")
