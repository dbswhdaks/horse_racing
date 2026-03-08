"""
Supabase 클라이언트 모듈.

수집 데이터, 예측 결과를 Supabase에 저장/조회합니다.
"""

from supabase import create_client, Client
from app.config import SUPABASE_URL, SUPABASE_ANON_KEY

_client: Client | None = None


def get_client() -> Client:
    global _client
    if _client is None:
        _client = create_client(SUPABASE_URL, SUPABASE_ANON_KEY)
    return _client


# ───────────────────── Races ─────────────────────

def upsert_races(rows: list[dict]):
    if not rows:
        return
    client = get_client()
    client.table("races").upsert(
        rows, on_conflict="meet,race_date,race_no"
    ).execute()
    print(f"[SUPABASE] races {len(rows)}건 upsert")


# ───────────────────── Race Entries ─────────────────────

def upsert_entries(rows: list[dict]):
    if not rows:
        return
    client = get_client()
    client.table("race_entries").upsert(
        rows, on_conflict="meet,race_date,race_no,horse_no"
    ).execute()
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
    client.table("race_results").upsert(
        unique_rows, on_conflict="meet,race_date,race_no,horse_no"
    ).execute()
    print(f"[SUPABASE] race_results {len(unique_rows)}건 upsert")


# ───────────────────── Predictions ─────────────────────

def upsert_predictions(rows: list[dict]):
    if not rows:
        return
    client = get_client()
    client.table("predictions").upsert(
        rows, on_conflict="meet,race_date,race_no,horse_no"
    ).execute()
    print(f"[SUPABASE] predictions {len(rows)}건 upsert")


# ───────────────────── Odds ─────────────────────

def upsert_odds(rows: list[dict]):
    if not rows:
        return
    client = get_client()
    client.table("odds").upsert(rows).execute()
    print(f"[SUPABASE] odds {len(rows)}건 upsert")
