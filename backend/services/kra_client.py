import httpx
from typing import Any

from config import KRA_SERVICE_KEY, KRA_BASE_URL

ENDPOINTS = {
    "race_plan": "/API72_2/racePlan_2",
    "start_list": "/API26_2",
    "race_result": "/API299",
    "odd_info": "/API145",
    "trainer_record": "/API155",
    "jockey_record": "/API156",
    "ai_result": "/API218/aiRaceResult",
    "horse_record": "/API153",
}


class KraClient:
    def __init__(self) -> None:
        self.base_url = KRA_BASE_URL
        self.service_key = KRA_SERVICE_KEY
        self._client = httpx.AsyncClient(timeout=30.0)

    async def close(self) -> None:
        await self._client.aclose()

    async def _get(self, path: str, params: dict[str, Any] | None = None) -> list[dict]:
        query = {
            "ServiceKey": self.service_key,
            "_type": "json",
            **(params or {}),
        }
        url = f"{self.base_url}{path}"
        resp = await self._client.get(url, params=query)
        resp.raise_for_status()
        return self._parse_items(resp.json())

    @staticmethod
    def _parse_items(data: dict) -> list[dict]:
        body = data.get("response", {}).get("body", {})
        items = body.get("items", {}).get("item", [])
        if isinstance(items, dict):
            return [items]
        if isinstance(items, list):
            return items
        return []

    async def get_race_plan(self, meet: str, rc_date: str | None = None) -> list[dict]:
        params: dict[str, Any] = {"meet": meet}
        if rc_date:
            params["rc_date"] = rc_date
        return await self._get(ENDPOINTS["race_plan"], params)

    async def get_start_list(
        self, meet: str, rc_date: str | None = None, rc_no: int | None = None
    ) -> list[dict]:
        params: dict[str, Any] = {
            "meet": meet,
            "pageNo": 1,
            "numOfRows": 100,
        }
        if rc_date and len(rc_date) == 8:
            params["month"] = rc_date[4:6]
            params["day"] = rc_date[6:8]
        return await self._get(ENDPOINTS["start_list"], params)

    async def get_race_result(
        self, meet: str, rc_date: str | None = None, rc_no: int | None = None
    ) -> list[dict]:
        params: dict[str, Any] = {
            "meet": meet,
            "pageNo": 1,
            "numOfRows": 100,
        }
        if rc_date and len(rc_date) == 8:
            params["month"] = rc_date[4:6]
            params["day"] = rc_date[6:8]
        if rc_no:
            params["rc_no"] = rc_no
        return await self._get(ENDPOINTS["race_result"], params)

    async def get_odds(
        self, meet: str, rc_date: str | None = None, rc_no: int | None = None
    ) -> list[dict]:
        params: dict[str, Any] = {
            "meet": meet,
            "pageNo": 1,
            "numOfRows": 100,
        }
        if rc_date and len(rc_date) == 8:
            params["month"] = rc_date[4:6]
            params["day"] = rc_date[6:8]
        if rc_no:
            params["rc_no"] = rc_no
        return await self._get(ENDPOINTS["odd_info"], params)

    async def get_ai_race_result(self, rccrs_cd: str, race_dt: str) -> list[dict]:
        params = {"rccrs_cd": rccrs_cd, "race_dt": race_dt}
        return await self._get(ENDPOINTS["ai_result"], params)
