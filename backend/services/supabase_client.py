"""Supabase 클라이언트 – 데이터 저장 및 조회를 담당합니다."""

from __future__ import annotations

import logging
from typing import Any

from supabase import create_client, Client

from config import SUPABASE_URL, SUPABASE_SERVICE_KEY

logger = logging.getLogger(__name__)


class SupabaseDB:
    def __init__(self) -> None:
        if not SUPABASE_URL or "YOUR_PROJECT" in SUPABASE_URL:
            logger.warning("Supabase URL이 설정되지 않았습니다. .env 파일을 확인하세요.")
            self._client: Client | None = None
        else:
            self._client = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    @property
    def enabled(self) -> bool:
        return self._client is not None

    # ── Races ──

    def upsert_races(self, rows: list[dict[str, Any]]) -> int:
        if not self.enabled or not rows:
            return 0
        mapped = [_map_race(r) for r in rows]
        res = self._client.table("races").upsert(
            mapped, on_conflict="meet,race_date,race_no"
        ).execute()
        return len(res.data) if res.data else 0

    def get_races(self, meet: str, race_date: str | None = None) -> list[dict]:
        if not self.enabled:
            return []
        q = self._client.table("races").select("*").eq("meet", meet)
        if race_date:
            q = q.eq("race_date", race_date)
        return q.order("race_no").execute().data or []

    # ── Entries ──

    def upsert_entries(self, rows: list[dict[str, Any]], meet: str, race_date: str) -> int:
        if not self.enabled or not rows:
            return 0
        mapped = [_map_entry(r, meet, race_date) for r in rows]
        res = self._client.table("race_entries").upsert(
            mapped, on_conflict="meet,race_date,race_no,horse_no"
        ).execute()
        return len(res.data) if res.data else 0

    def get_entries(
        self, meet: str, race_date: str | None = None, race_no: int | None = None
    ) -> list[dict]:
        if not self.enabled:
            return []
        q = self._client.table("race_entries").select("*").eq("meet", meet)
        if race_date:
            q = q.eq("race_date", race_date)
        if race_no is not None:
            q = q.eq("race_no", race_no)
        return q.order("horse_no").execute().data or []

    # ── Results ──

    def upsert_results(self, rows: list[dict[str, Any]], meet: str) -> int:
        if not self.enabled or not rows:
            return 0
        mapped = [_map_result(r, meet) for r in rows]
        res = self._client.table("race_results").upsert(
            mapped, on_conflict="meet,race_date,race_no,horse_no"
        ).execute()
        return len(res.data) if res.data else 0

    def get_results(
        self, meet: str, race_date: str | None = None, race_no: int | None = None
    ) -> list[dict]:
        if not self.enabled:
            return []
        q = self._client.table("race_results").select("*").eq("meet", meet)
        if race_date:
            q = q.eq("race_date", race_date)
        if race_no is not None:
            q = q.eq("race_no", race_no)
        return q.order("rank").execute().data or []

    def get_horse_results(self, horse_name: str) -> list[dict]:
        if not self.enabled:
            return []
        return (
            self._client.table("race_results")
            .select("*")
            .eq("horse_name", horse_name)
            .order("race_date", desc=True)
            .limit(30)
            .execute()
            .data or []
        )

    # ── Predictions ──

    def upsert_predictions(self, predictions: list[dict[str, Any]]) -> int:
        if not self.enabled or not predictions:
            return 0
        res = self._client.table("predictions").upsert(
            predictions, on_conflict="meet,race_date,race_no,horse_no,model_version"
        ).execute()
        return len(res.data) if res.data else 0

    def get_predictions(
        self, meet: str, race_date: str, race_no: int
    ) -> list[dict]:
        if not self.enabled:
            return []
        return (
            self._client.table("predictions")
            .select("*")
            .eq("meet", meet)
            .eq("race_date", race_date)
            .eq("race_no", race_no)
            .order("win_probability", desc=True)
            .execute()
            .data or []
        )

    # ── Odds ──

    def upsert_odds(self, rows: list[dict[str, Any]]) -> int:
        if not self.enabled or not rows:
            return 0
        res = self._client.table("odds").upsert(rows).execute()
        return len(res.data) if res.data else 0


# ── Field mapping helpers ──


def _safe_int(val: Any, default: int = 0) -> int:
    try:
        return int(val)
    except (TypeError, ValueError):
        return default


def _safe_float(val: Any, default: float = 0.0) -> float:
    try:
        return float(val)
    except (TypeError, ValueError):
        return default


def _map_race(r: dict) -> dict:
    return {
        "meet": str(r.get("meet", "")),
        "race_date": str(r.get("rcDate", r.get("race_date", ""))),
        "race_no": _safe_int(r.get("rcNo", r.get("race_no", 0))),
        "distance": _safe_int(r.get("rcDist", r.get("distance", 0))),
        "grade_condition": str(r.get("rank", r.get("grade_condition", ""))),
        "race_name": str(r.get("rcNm", r.get("race_name", ""))),
        "age_condition": str(r.get("ageCond", r.get("age_condition", ""))),
        "sex_condition": str(r.get("sexCond", r.get("sex_condition", ""))),
        "weight_condition": str(r.get("wghtCond", r.get("weight_condition", ""))),
        "start_time": str(r.get("schStTime", r.get("start_time", ""))),
        "prize1": _safe_int(r.get("chaksun1", r.get("prize1", 0))),
        "prize2": _safe_int(r.get("chaksun2", r.get("prize2", 0))),
        "prize3": _safe_int(r.get("chaksun3", r.get("prize3", 0))),
        "head_count": _safe_int(r.get("ilsu", r.get("head_count", 0))),
    }


def _map_entry(r: dict, meet: str, race_date: str) -> dict:
    return {
        "meet": meet,
        "race_date": race_date,
        "race_no": _safe_int(r.get("rcNo", r.get("race_no", 0))),
        "horse_no": _safe_int(r.get("hrNo", r.get("chulNo", r.get("horse_no", 0)))),
        "horse_name": str(r.get("hrNm", r.get("horse_name", ""))),
        "birth_place": str(r.get("birthPlace", r.get("birth_place", ""))),
        "sex": str(r.get("sex", "")),
        "age": _safe_int(r.get("age", 0)),
        "jockey_name": str(r.get("jkNm", r.get("jockyNm", r.get("jockey_name", "")))),
        "trainer_name": str(r.get("trNm", r.get("trainer_name", ""))),
        "owner_name": str(r.get("owNm", r.get("owner_name", ""))),
        "weight": _safe_float(r.get("wght", r.get("brdnWt", r.get("weight", 0)))),
        "rating": _safe_float(r.get("rating", 0)),
        "total_prize": _safe_int(r.get("totalPrize", r.get("total_prize", 0))),
        "recent_prize": _safe_int(r.get("recentPrize", r.get("recent_prize", 0))),
        "win_count": _safe_int(r.get("winCnt", r.get("win_count", 0))),
        "place_count": _safe_int(r.get("placeCnt", r.get("place_count", 0))),
        "total_races": _safe_int(r.get("totalRaces", r.get("total_races", 0))),
        "horse_weight": _safe_float(r.get("hrWght", r.get("rcHrsWt", r.get("horse_weight", 0)))),
    }


def _map_result(r: dict, meet: str) -> dict:
    return {
        "meet": meet,
        "race_date": str(
            r.get("raceDt", r.get("rcDate", r.get("race_date", r.get("collect_date", ""))))
        ),
        "race_no": _safe_int(
            r.get("raceNo") or r.get("rcNo") or r.get("race_no") or 0
        ),
        "rank": _safe_int(r.get("rk") or r.get("ord") or r.get("rank") or 0),
        "horse_no": _safe_int(
            r.get("gtno") or r.get("hrNo") or r.get("chulNo") or r.get("horse_no") or 0
        ),
        "horse_name": str(
            r.get("hrnm", r.get("hrNm", r.get("horse_name", "")))
        ),
        "jockey_name": str(
            r.get("jckyNm", r.get("jkNm", r.get("jockyNm", r.get("jockey_name", ""))))
        ),
        "trainer_name": str(
            r.get("trarNm", r.get("trNm", r.get("trainer_name", "")))
        ),
        "race_time": str(r.get("raceRcd", r.get("rcTime", r.get("race_time", "")))),
        "weight": _safe_float(
            r.get("burdWgt") or r.get("wght") or r.get("brdnWt") or r.get("weight") or 0
        ),
        "horse_weight": _safe_float(
            r.get("rchrWeg") or r.get("hrWght") or r.get("rcHrsWt") or r.get("horse_weight") or 0
        ),
        "rank_diff": str(r.get("margin", r.get("rankDiff", r.get("rank_diff", "")))),
        "win_odds": _safe_float(
            r.get("winPrice") or r.get("winOdds") or r.get("win_odds") or 0
        ),
        "place_odds": _safe_float(
            r.get("placePrice") or r.get("plcOdds") or r.get("place_odds") or 0
        ),
        "s1f": str(r.get("s1f", "")),
        "g3f": str(r.get("g3f", "")),
        "pass_order": str(r.get("ordBigo", r.get("passOrder", r.get("pass_order", "")))),
        "distance": _safe_int(r.get("raceDs") or r.get("rcDist") or r.get("distance") or 0),
    }
